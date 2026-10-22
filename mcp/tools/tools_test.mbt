// Catalog tests: an in-process MCP server (over a queue transport) whose tools
// are discovered and called.

///|
struct FakeTransport {
  inbound : @async.Queue[Json]
  outbound : @async.Queue[Json]
}

///|
impl @jsonrpc.Transport for FakeTransport with fn send(self, message) {
  self.outbound.put(message)
}

///|
impl @jsonrpc.Transport for FakeTransport with fn recv(self) {
  Some(self.inbound.get()) catch {
    _ => None
  }
}

///|
impl @jsonrpc.Transport for FakeTransport with fn close(self) {
  self.inbound.close()
  self.outbound.close()
}

///|
fn ok(request : Json, result : Json) -> Json {
  let id = match request {
    { "id": id, .. } => id
    _ => null
  }
  { "jsonrpc": "2.0", "id": id, "result": result }
}

///|
/// A server that lists one `echo` tool and echoes a call's arguments back.
fn server_reply(request : Json) -> Json? {
  match request {
    { "method": "initialize", .. } =>
      Some(
        ok(request, {
          "protocolVersion": "2025-11-25",
          "serverInfo": { "name": "s", "version": "1" },
        }),
      )
    { "method": "tools/list", .. } =>
      Some(
        ok(request, {
          "tools": [
            {
              "name": "echo",
              "description": "Echoes",
              "inputSchema": {
                "type": "object",
                "properties": { "text": { "type": "string" } },
              },
              "outputSchema": {
                "type": "object",
                "properties": { "echo": { "type": "string" } },
              },
            },
          ],
        }),
      )
    {
      "method": "tools/call",
      "params": { "arguments": { "structured": structured, .. }, .. },
      ..
    } =>
      Some(
        ok(request, {
          "content": [{ "type": "text", "text": "status: ok" }],
          "structuredContent": structured,
        }),
      )
    { "method": "tools/call", .. } => {
      let args = match request {
        { "params": { "arguments": args, .. }, .. } => args
        _ => null
      }
      Some(
        ok(request, {
          "content": [{ "type": "text", "text": "echoed: \{args.stringify()}" }],
        }),
      )
    }
    _ => None
  }
}

///|
/// `server_reply`, except that every `tools/call` answers with a caption, a PNG
/// image, and an SVG image the model cannot receive.
fn image_reply(request : Json) -> Json? {
  match request {
    { "method": "tools/call", .. } =>
      Some(
        ok(request, {
          "content": [
            { "type": "text", "text": "a screenshot" },
            { "type": "image", "data": "iVBORw0KGgo=", "mimeType": "image/png" },
            { "type": "image", "data": "PHN2Zy8+", "mimeType": "image/svg+xml" },
          ],
        }),
      )
    _ => server_reply(request)
  }
}

///|
fn[X] wire(
  group : @async.TaskGroup[X],
  transport : FakeTransport,
  rpc : @jsonrpc.Client,
  reply? : (Json) -> Json?,
) -> Unit {
  group.spawn_bg(no_wait=true, allow_failure=true, () => rpc.run_message_pump())
  group.spawn_bg(no_wait=true, allow_failure=true, () => rpc.run_writer())
  group.spawn_bg(no_wait=true, allow_failure=true, () => {
    for ;; {
      let request = transport.outbound.get()
      let response = if reply is Some(reply) {
        reply(request)
      } else {
        server_reply(request)
      }
      if response is Some(response) {
        transport.inbound.put(response)
      }
    }
  })
}

///|
fn new_transport() -> FakeTransport {
  { inbound: Queue(kind=Unbounded), outbound: Queue(kind=Unbounded), }
}

///|
async test "discover keeps each tool under its own name with its schemas" {
  @async.with_task_group(group => {
    let transport = new_transport()
    let rpc = @jsonrpc.Client(transport)
    wire(group, transport, rpc)
    let tools = @tools.discover("srv", McpClient(rpc))
    assert_eq(tools.length(), 1)
    assert_eq(tools[0].name, "echo")
    assert_eq(tools[0].description, "Echoes")
    assert_true(tools[0].input_schema is { "type": "object", .. })
    assert_true(
      tools[0].output_schema is Some({ "properties": { "echo": _, .. }, .. }),
    )
  })
}

///|
async test "call_tool proxies tools/call and returns the result" {
  @async.with_task_group(group => {
    let transport = new_transport()
    let rpc = @jsonrpc.Client(transport)
    wire(group, transport, rpc)
    let exec = args => @tools.call_tool(McpClient(rpc), "echo", args)
    guard exec({ "text": "hi" }) is Respond(output) else {
      fail("expected a respond action")
    }
    assert_false(output.is_error)
    assert_true(output.content.contains("echoed"))
    assert_true(output.content.contains("hi"))
  })
}

///|
async test "a structured result reaches scripts as data beside its text" {
  @async.with_task_group(group => {
    let transport = new_transport()
    let rpc = @jsonrpc.Client(transport)
    wire(group, transport, rpc)
    let exec = args => @tools.call_tool(McpClient(rpc), "echo", args)
    let structured : Json = { "repo": "alpha", "open": 7 }
    guard exec({ "structured": structured }) is Respond(output) else {
      fail("expected a respond action")
    }
    assert_eq(output.data, Some(structured))
    assert_true(output.content.contains("status: ok"))
    assert_true(output.content.contains(structured.stringify()))
  })
}

///|
async test "a large structured result keeps the text whole and leaves data out" {
  @async.with_task_group(group => {
    let transport = new_transport()
    let rpc = @jsonrpc.Client(transport)
    wire(group, transport, rpc)
    let exec = args => @tools.call_tool(McpClient(rpc), "echo", args)
    // Text and data both fit alone, not together: the text, which a direct
    // call's model reads, wins.
    let structured : Json = { "blob": "x".repeat(40000) }
    guard exec({ "structured": structured }) is Respond(output) else {
      fail("expected a respond action")
    }
    assert_true(output.data is None)
    assert_true(output.content.contains(structured.stringify()))
    assert_false(output.content.contains("truncated=true"))
  })
}

///|
async test "a structured result over the reply budget stays text only" {
  @async.with_task_group(group => {
    let transport = new_transport()
    let rpc = @jsonrpc.Client(transport)
    wire(group, transport, rpc)
    let exec = args => @tools.call_tool(McpClient(rpc), "echo", args)
    let structured : Json = { "blob": "x".repeat(70000) }
    guard exec({ "structured": structured }) is Respond(output) else {
      fail("expected a respond action")
    }
    assert_true(output.data is None)
    assert_true(output.content.contains("truncated=true"))
    assert_true(Json(output.content).stringify().length() < 65536)
  })
}

///|
async test "call_tool returns image content as image input" {
  @async.with_task_group(group => {
    let transport = new_transport()
    let rpc = @jsonrpc.Client(transport)
    wire(group, transport, rpc, reply=image_reply)
    let exec = args => @tools.call_tool(McpClient(rpc), "echo", args)
    guard exec({}) is Respond(output) else { fail("expected a respond action") }
    assert_false(output.is_error)
    assert_eq(
      output.content,
      "a screenshot\n[image image/svg+xml not attached: expected PNG, JPEG, GIF, or WebP image bytes]",
    )
    assert_eq(output.images.length(), 1)
    assert_eq(output.images[0].media_type, "image/png")
    assert_eq(output.images[0].bytes, b"\x89PNG\r\n\x1a\n")
  })
}

///|
/// A server that handshakes but never answers tools/list is skipped at the
/// discovery deadline instead of hanging engine startup.
async test "connect times out discovery on a wedged server" {
  @async.with_task_group(group => {
    let scope = @agent_runtime.AgentTaskScope(group)
    let script =
      #|read _
      #|printf '{"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"legacy"}}\n'
      #|read _
      #|printf '{"jsonrpc":"2.0","id":2,"result":{"protocolVersion":"2025-11-25"}}\n'
      #|sleep 30
    let servers = [
      @config.Stdio(name="w", command="sh", args=["-c", script], env=Map([])),
    ]
    let entries = @tools.connect(
      scope,
      servers,
      client_name="openseek",
      client_version="0.1",
      discovery_timeout_ms=800,
    )
    assert_true(entries is [{ connection: Failed(_), tools: [], .. }])
  })
}

///|
async test "connect records a server that cannot start" {
  @async.with_task_group(group => {
    let scope = @agent_runtime.AgentTaskScope(group)
    let servers = [
      @config.Stdio(
        name="bad",
        command="openseek-no-such-mcp-server-xyz",
        args=[],
        env=Map([]),
      ),
    ]
    let entries = @tools.connect(
      scope,
      servers,
      client_name="openseek",
      client_version="0.1",
    )
    assert_true(entries is [{ connection: Failed(_), tools: [], .. }])
    guard entries[0].call("anything", {}) is Respond(output) else {
      fail("expected a respond action")
    }
    assert_true(output.is_error)
    assert_true(output.content.contains("`bad` is unavailable"))
  })
}

///|
/// Answer one mock-endpoint request with a JSON-RPC success body.
async fn respond_json(
  conn : @http.ServerConnection,
  id : Json,
  result : Json,
) -> Unit {
  let reply : Json = { "jsonrpc": "2.0", "id": id, "result": result }
  conn.send_response(200, "OK", extra_headers={
    "Content-Type": "application/json",
  })
  conn.write(reply.stringify())
}

///|
/// End-to-end over HTTP: `connect` connects a configured Http server (a local
/// mock MCP endpoint), discovers its tool, and a call is proxied as a live
/// tools/call through the Streamable HTTP transport, directly and through the
/// MCP host.
async test "connect reaches an HTTP server's tools directly and through the MCP host" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0")) catch {
      error if "\{error}".contains("Operation not permitted") => {
        println("local TCP bind unavailable; skipping http bridge test")
        return
      }
      error => raise error
    }
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      server.run_forever(
        (_request, body, conn) => {
          let message = @json.parse(body.read_all().text()) catch { _ => null }
          let id = match message {
            { "id": id, .. } => id
            _ => null
          }
          match message {
            { "method": "server/discover", .. } =>
              conn.send_response(400, "Bad Request")
            { "method": "initialize", .. } =>
              respond_json(conn, id, { "protocolVersion": "2025-11-25" })
            { "method": "tools/list", .. } =>
              respond_json(conn, id, {
                "tools": [
                  {
                    "name": "ping",
                    "description": "Ping",
                    "inputSchema": { "type": "object" },
                  },
                  // Oversized in every server-supplied part.
                  {
                    "name": "big",
                    "description": "d".repeat(2000),
                    "inputSchema": [1, 2],
                    "outputSchema": {
                      "type": "object",
                      "properties": { "x": { "enum": ["y".repeat(20000)] } },
                    },
                  },
                ],
              })
            {
              "method": "tools/call",
              "params": {
                "name": "ping",
                "arguments": { "fail": true, .. },
                ..
              },
              ..
            } =>
              respond_json(conn, id, {
                "content": [{ "type": "text", "text": "ping failed" }],
                "isError": true,
              })
            { "method": "tools/call", "params": { "name": "ping", .. }, .. } =>
              respond_json(conn, id, {
                "content": [{ "type": "text", "text": "pong" }],
              })
            _ => conn.send_response(202, "Accepted")
          }
        },
        max_connections=8,
      )
    }
    let scope = @agent_runtime.AgentTaskScope(group)
    let servers = [
      @config.Http(
        name="remote",
        url="http://127.0.0.1:\{server.addr.port()}/mcp",
        headers=Map([]),
      ),
    ]
    let entries = @tools.connect(
      scope,
      servers,
      client_name="openseek",
      client_version="0.1",
    )
    guard entries is [remote] else { fail("expected one entry") }
    assert_eq([ for tool in remote.tools => tool.name ], ["ping", "big"])
    // The catalog caps what the server supplied, so any item fits a reply.
    guard @tools.catalog_items(entries)
      is [
        { "server": "remote", .. } as server_item,
        { "server": "remote", "tool": { "name": "ping", .. }, .. },
        { "server": "remote", "tool": big, .. },
      ] else {
      fail("expected the server, then its tools")
    }
    assert_false(server_item is { "error": _, .. })
    let open : Json = { "type": "object" }
    guard big
      is { "description": String(description), "input_schema": input, .. } else {
      fail("expected a tool record")
    }
    assert_eq(description.char_length(), 1025)
    assert_eq(input, open)
    assert_false(big is { "output_schema": _, .. })
    guard remote.call("ping", Json::empty_object()) is Respond(output) else {
      fail("expected a respond action")
    }
    assert_false(output.is_error)
    assert_eq(output.content, "pong")
    guard remote.call("pong", Json::empty_object()) is Respond(missing) else {
      fail("expected a respond action")
    }
    assert_true(missing.is_error)
    assert_true(missing.content.contains("has no tool `pong`"))
    // Through the real MCP host: a call to the server, and to one that is not
    // configured.
    let host = @mcphost.Service::start(
      group,
      call=(server, tool, arguments) => {
        guard server == "remote" else {
          return @agent_tool.respond("no MCP server `\{server}`", is_error=true)
        }
        remote.call(tool, arguments)
      },
      items=() => @tools.catalog_items(entries),
    )
    guard @json.parse(host.env()["OPENSEEK_MCP"])
      is { "url": String(url), "token": String(token), .. } else {
      fail("missing MCP host handoff")
    }
    let requests : Array[(Json, Json)] = [
      (
        {
          "version": 1,
          "call": { "server": "remote", "tool": "ping", "arguments": {} },
        },
        { "version": 1, "content": "pong", "is_error": false },
      ),
      (
        {
          "version": 1,
          "call": {
            "server": "remote",
            "tool": "ping",
            "arguments": { "fail": true },
          },
        },
        { "version": 1, "content": "ping failed", "is_error": true },
      ),
      (
        {
          "version": 1,
          "call": { "server": "other", "tool": "ping", "arguments": {} },
        },
        { "version": 1, "content": "no MCP server `other`", "is_error": true },
      ),
    ]
    for pair in requests {
      let (request, expected) = pair
      let (response, body) = @http.post(url, request, headers={
        "Authorization": "Bearer \{token}",
      })
      assert_eq(response.code, 200)
      assert_eq(body.json(), expected)
    }
  }
}

///|
/// Beside the tools, `connect` keeps what connecting each server came to, and
/// a live connection goes on saying whether it is still there.
async test "connect keeps what each server came to, and a live one reports its loss" {
  @async.with_task_group(group => {
    let scope = @agent_runtime.AgentTaskScope(group)
    // Offers one tool, then exits a moment later.
    let brief =
      #|read _
      #|printf '{"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"legacy"}}\n'
      #|read _
      #|printf '{"jsonrpc":"2.0","id":2,"result":{"protocolVersion":"2025-11-25"}}\n'
      #|read _
      #|read _
      #|printf '{"jsonrpc":"2.0","id":3,"result":{"tools":[{"name":"ping"}]}}\n'
      #|sleep 1
    let empty =
      #|read _
      #|printf '{"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"legacy"}}\n'
      #|read _
      #|printf '{"jsonrpc":"2.0","id":2,"result":{"protocolVersion":"2025-11-25"}}\n'
      #|read _
      #|read _
      #|printf '{"jsonrpc":"2.0","id":3,"result":{"tools":[]}}\n'
      #|sleep 5
    let wedged =
      #|read _
      #|printf '{"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"legacy"}}\n'
      #|read _
      #|printf '{"jsonrpc":"2.0","id":2,"result":{"protocolVersion":"2025-11-25"}}\n'
      #|sleep 30
    fn sh(name : String, script : String) -> @config.McpServer {
      Stdio(name~, command="sh", args=["-c", script], env=Map([]))
    }

    let entries = @tools.connect(
      scope,
      [
        sh("brief", brief),
        sh("empty", empty),
        sh("wedged", wedged),
        Stdio(
          name="bad",
          command="openseek-no-such-mcp-server-xyz",
          args=[],
          env=Map([]),
        ),
      ],
      client_name="openseek",
      client_version="0.1",
      discovery_timeout_ms=800,
    )
    guard entries is [brief, empty, wedged, bad] else {
      fail("expected one entry per configured server, in order")
    }
    if brief.connection is Failed(_) {
      // Spawning is forbidden in this sandbox: skip.
      println("skipped: cannot spawn sh")
      return
    }
    guard brief.connection is Live(client) else {
      fail("a server that offered a tool should be live")
    }
    assert_eq([ for tool in brief.tools => tool.name ], ["ping"])
    assert_eq(brief.server.name(), "brief")
    assert_true(empty.connection is NoTools)
    assert_true(empty.tools.is_empty())
    assert_true(wedged.connection is Failed("timed out listing its tools"))
    assert_true(bad.connection is Failed(_))
    assert_true(bad.tools.is_empty())
    // The server exits on its own, and the client says so without being
    // asked: that is what lets an engine report the loss when it happens.
    // Install, then read — a connection already gone never runs the handler.
    let lost : @async.Queue[Unit] = Queue(kind=Unbounded)
    client.set_close_handler(() => ignore(lost.try_put(()) catch { _ => false }))
    if !client.is_closed() {
      @async.with_timeout(10000, () => lost.get())
    }
    assert_true(client.is_closed())
  })
}

///|
/// A configured server whose spawn fails, as a catalog entry.
async fn[X] unavailable(
  scope : @agent_runtime.AgentTaskScope[X],
) -> Array[@tools.ServerEntry] {
  @tools.connect(
    scope,
    [
      Stdio(
        name="bad",
        command="openseek-no-such-mcp-server-xyz",
        args=[],
        env=Map([]),
      ),
    ],
    client_name="openseek",
    client_version="0.1",
  )
}

///|
async test "the catalog lists an unavailable server with its error and no tools" {
  @async.with_task_group(group => {
    let items = @tools.catalog_items(unavailable(AgentTaskScope(group)))
    assert_true(
      items is [{ "server": "bad", "error": String(_), .. } as item] &&
      !(item is { "tool": _, .. }),
    )
  })
}
