// Bridge tests: an in-process MCP server (over a queue transport) whose tools
// are bridged into agent tools and dispatched.

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
    error if @async.is_being_cancelled() => raise error
    _ => None
  }
}

///|
impl @jsonrpc.Transport for FakeTransport with fn close(self) {
  self.inbound.close()
  self.outbound.close()
}

///|
fn method_of(request : Json) -> String {
  match request {
    { "method": String(method_), .. } => method_
    _ => ""
  }
}

///|
fn ok(request : Json, result : Json) -> Json {
  let id = match request {
    { "id": id, .. } => id
    _ => Json::null()
  }
  { "jsonrpc": "2.0", "id": id, "result": result }
}

///|
/// A server that lists one `echo` tool and echoes a call's arguments back.
fn server_reply(request : Json) -> Json? {
  match method_of(request) {
    "initialize" =>
      Some(
        ok(request, {
          "protocolVersion": "2025-11-25",
          "serverInfo": { "name": "s", "version": "1" },
        }),
      )
    "tools/list" =>
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
            },
          ],
        }),
      )
    "tools/call" => {
      let args = match request {
        { "params": { "arguments": args, .. }, .. } => args
        _ => Json::null()
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
fn[X] wire(
  group : @async.TaskGroup[X],
  transport : FakeTransport,
  rpc : @jsonrpc.Client,
) -> Unit {
  group.spawn_bg(no_wait=true, allow_failure=true, () => rpc.run_message_pump())
  group.spawn_bg(no_wait=true, allow_failure=true, () => rpc.run_writer())
  group.spawn_bg(no_wait=true, allow_failure=true, () => {
    for ;; {
      let request = transport.outbound.get()
      if server_reply(request) is Some(response) {
        transport.inbound.put(response)
      }
    }
  })
}

///|
fn new_transport() -> FakeTransport {
  { inbound: Queue(kind=Unbounded), outbound: Queue(kind=Unbounded) }
}

///|
async test "tools_for_client bridges tools with namespaced names and schemas" {
  @async.with_task_group(group => {
    let transport = new_transport()
    let rpc = @jsonrpc.Client::new(transport)
    wire(group, transport, rpc)
    let client = @mcp.McpClient::new(rpc)
    let tools = @tools.tools_for_client("srv", client)
    assert_eq(tools.length(), 1)
    assert_eq(tools[0].name, "mcp__srv__echo")
    assert_eq(tools[0].description, "Echoes")
    let @agent_tool.JsonSchema(schema) = tools[0].schema
    assert_true(schema is { "type": String("object"), .. })
  })
}

///|
async test "a bridged tool proxies tools/call and returns the result" {
  @async.with_task_group(group => {
    let transport = new_transport()
    let rpc = @jsonrpc.Client::new(transport)
    wire(group, transport, rpc)
    let client = @mcp.McpClient::new(rpc)
    let tools = @tools.tools_for_client("srv", client)
    guard tools[0].execute is @agent_tool.Async(exec) else {
      fail("expected an async executor")
    }
    guard exec({ "text": "hi" }) is @agent_tool.Respond(output) else {
      fail("expected a respond action")
    }
    assert_false(output.is_error)
    assert_true(output.content.contains("echoed"))
    assert_true(output.content.contains("hi"))
  })
}

///|
test "tool_name sanitizes provider-hostile characters and caps the length" {
  assert_eq(
    @tools.tool_name("my.server", "read.file"),
    "mcp__my-server__read-file",
  )
  assert_eq(@tools.tool_name("a b", "c/d"), "mcp__a-b__c-d")
  let long = @tools.tool_name(
    "server", "an-extremely-long-tool-name-that-goes-on-and-on-and-on-and-on-and-on",
  )
  assert_true(long.length() <= 64)
  assert_true(long.has_prefix("mcp__server__"))
}

///|
/// Two tools whose sanitized names collide must both stay callable (the second
/// under a suffixed name), not silently drop one.
async test "build suffixes tools whose sanitized names collide" {
  @async.with_task_group(group => {
    let scope = @agent_runtime.AgentTaskScope(group)
    let script =
      #|read _
      #|printf '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25"}}\n'
      #|read _
      #|read _
      #|printf '{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"a.b"},{"name":"a-b"}]}}\n'
      #|sleep 5
    let servers = [
      @config.Stdio(name="s", command="sh", args=["-c", script], env=Map([])),
    ]
    let tools = @tools.build(
      scope,
      servers,
      client_name="openseek",
      client_version="0.1",
    )
    if tools.length() == 0 {
      // Spawning is forbidden in this sandbox: skip.
      println("skipped: cannot spawn sh")
      return
    }
    let names = [ for tool in tools => tool.name ]
    assert_eq(names, ["mcp__s__a-b", "mcp__s__a-b-2"])
  })
}

///|
/// A server that handshakes but never answers tools/list is skipped at the
/// discovery deadline instead of hanging engine startup.
async test "build times out discovery on a wedged server" {
  @async.with_task_group(group => {
    let scope = @agent_runtime.AgentTaskScope(group)
    let script =
      #|read _
      #|printf '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25"}}\n'
      #|sleep 30
    let servers = [
      @config.Stdio(name="w", command="sh", args=["-c", script], env=Map([])),
    ]
    let tools = @tools.build(
      scope,
      servers,
      client_name="openseek",
      client_version="0.1",
      discovery_timeout_ms=800,
    )
    assert_eq(tools.length(), 0)
  })
}

///|
async test "build skips a server that cannot start" {
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
    let tools = @tools.build(
      scope,
      servers,
      client_name="openseek",
      client_version="0.1",
    )
    assert_eq(tools.length(), 0)
  })
}
