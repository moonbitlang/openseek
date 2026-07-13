// End-to-end tests of the MCP client over an in-memory jsonrpc transport driven
// by a scripted server — no process, no network. Every test spawns the jsonrpc
// message pump (the single reader the client requires) and a server task.

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
fn new_transport() -> FakeTransport {
  { inbound: Queue(kind=Unbounded), outbound: Queue(kind=Unbounded) }
}

///|
fn id_of(request : Json) -> Json {
  match request {
    { "id": id, .. } => id
    _ => Json::null()
  }
}

///|
fn method_of(request : Json) -> String {
  match request {
    { "method": String(method_), .. } => method_
    _ => ""
  }
}

///|
/// A JSON-RPC success reply echoing the request's id.
fn success(request : Json, result : Json) -> Json {
  { "jsonrpc": "2.0", "id": id_of(request), "result": result }
}

///|
/// A JSON-RPC error reply echoing the request's id.
fn failure(request : Json, code : Int, message : String) -> Json {
  {
    "jsonrpc": "2.0",
    "id": id_of(request),
    "error": { "code": Json::number(code.to_double()), "message": message },
  }
}

///|
/// The `initialize` result a stock fake server returns.
fn stock_initialize_result() -> Json {
  {
    "protocolVersion": "2025-11-25",
    "serverInfo": { "name": "fake", "version": "1.0" },
  }
}

///|
/// A stock server responder: answers `initialize`/`tools/list`/`tools/call`
/// with the given fixtures and ignores everything else (notifications).
fn stock_reply(tools_result : Json, call_result : Json) -> (Json) -> Json? {
  fn(request : Json) -> Json? {
    match method_of(request) {
      "initialize" => Some(success(request, stock_initialize_result()))
      "tools/list" => Some(success(request, tools_result))
      "tools/call" => Some(success(request, call_result))
      _ => None
    }
  }
}

///|
fn[X] spawn_client(group : @async.TaskGroup[X], rpc : @jsonrpc.Client) -> Unit {
  group.spawn_bg(no_wait=true, allow_failure=true, () => rpc.run_message_pump())
  group.spawn_bg(no_wait=true, allow_failure=true, () => rpc.run_writer())
}

///|
async fn serve_loop(transport : FakeTransport, reply : (Json) -> Json?) -> Unit {
  for ;; {
    let request = transport.outbound.get()
    if reply(request) is Some(response) {
      transport.inbound.put(response)
    }
  }
}

///|
fn[X] spawn_server(
  group : @async.TaskGroup[X],
  transport : FakeTransport,
  reply : (Json) -> Json?,
) -> Unit {
  group.spawn_bg(no_wait=true, allow_failure=true, () => {
    serve_loop(transport, reply)
  })
}

///|
async test "initialize completes the handshake and returns server identity" {
  @async.with_task_group(group => {
    let transport = new_transport()
    let rpc = @jsonrpc.Client::new(transport)
    spawn_client(group, rpc)
    spawn_server(
      group,
      transport,
      stock_reply({ "tools": [] }, { "content": [] }),
    )
    let init = @mcp.McpClient::new(rpc).initialize(
      client_name="openseek",
      client_version="0.1",
    )
    assert_eq(init.protocol_version, "2025-11-25")
    assert_eq(init.server_name, "fake")
    assert_eq(init.server_version, "1.0")
  })
}

///|
async test "initialize accepts a supported older protocol version" {
  @async.with_task_group(group => {
    let transport = new_transport()
    let rpc = @jsonrpc.Client::new(transport)
    spawn_client(group, rpc)
    let reply = fn(request : Json) -> Json? {
      match method_of(request) {
        "initialize" =>
          Some(
            success(request, {
              "protocolVersion": "2024-11-05",
              "serverInfo": { "name": "old", "version": "0.1" },
            }),
          )
        _ => None
      }
    }
    spawn_server(group, transport, reply)
    let init = @mcp.McpClient::new(rpc).initialize(
      client_name="openseek",
      client_version="0.1",
    )
    assert_eq(init.protocol_version, "2024-11-05")
  })
}

///|
async test "initialize rejects an unsupported negotiated protocol version" {
  @async.with_task_group(group => {
    let transport = new_transport()
    let rpc = @jsonrpc.Client::new(transport)
    spawn_client(group, rpc)
    let reply = fn(request : Json) -> Json? {
      match method_of(request) {
        "initialize" =>
          Some(
            success(request, {
              "protocolVersion": "1999-01-01",
              "serverInfo": { "name": "future", "version": "9.9" },
            }),
          )
        _ => None
      }
    }
    spawn_server(group, transport, reply)
    let outcome = try {
      @mcp.McpClient::new(rpc).initialize(
        client_name="openseek",
        client_version="0.1",
      )
      |> ignore
      "no error raised"
    } catch {
      @mcp.Protocol(_) => "protocol"
      error if @async.is_being_cancelled() => raise error
      _ => "other error"
    }
    assert_eq(outcome, "protocol")
  })
}

///|
async test "list_tools returns tools with pass-through schemas" {
  @async.with_task_group(group => {
    let transport = new_transport()
    let rpc = @jsonrpc.Client::new(transport)
    spawn_client(group, rpc)
    let tools_result : Json = {
      "tools": [
        {
          "name": "echo",
          "description": "Echo text",
          "inputSchema": {
            "type": "object",
            "properties": { "text": { "type": "string" } },
          },
        },
      ],
    }
    spawn_server(group, transport, stock_reply(tools_result, { "content": [] }))
    let tools = @mcp.McpClient::new(rpc).list_tools()
    assert_eq(tools.length(), 1)
    assert_eq(tools[0].name, "echo")
    assert_eq(tools[0].description, "Echo text")
    assert_true(
      tools[0].input_schema
      is {
        "type": String("object"),
        "properties": { "text": { "type": String("string"), .. }, .. },
        ..
      },
    )
  })
}

///|
async test "list_tools follows nextCursor pagination" {
  @async.with_task_group(group => {
    let transport = new_transport()
    let rpc = @jsonrpc.Client::new(transport)
    spawn_client(group, rpc)
    let calls : Ref[Int] = { val: 0 }
    let reply = fn(request : Json) -> Json? {
      match method_of(request) {
        "tools/list" => {
          calls.val = calls.val + 1
          if calls.val == 1 {
            Some(
              success(request, {
                "tools": [{ "name": "a" }],
                "nextCursor": "page-2",
              }),
            )
          } else {
            Some(success(request, { "tools": [{ "name": "b" }] }))
          }
        }
        _ => None
      }
    }
    spawn_server(group, transport, reply)
    let tools = @mcp.McpClient::new(rpc).list_tools()
    assert_eq(tools.length(), 2)
    assert_eq(tools[0].name, "a")
    assert_eq(tools[1].name, "b")
  })
}

///|
async test "call_tool returns text content and renders it" {
  @async.with_task_group(group => {
    let transport = new_transport()
    let rpc = @jsonrpc.Client::new(transport)
    spawn_client(group, rpc)
    let call_result : Json = {
      "content": [{ "type": "text", "text": "hello world" }],
      "isError": false,
    }
    spawn_server(group, transport, stock_reply({ "tools": [] }, call_result))
    let result = @mcp.McpClient::new(rpc).call_tool(name="echo", arguments={
      "text": "hi",
    })
    assert_false(result.is_error)
    assert_eq(result.render_text(), "hello world")
  })
}

///|
async test "call_tool surfaces a tool-level error as is_error" {
  @async.with_task_group(group => {
    let transport = new_transport()
    let rpc = @jsonrpc.Client::new(transport)
    spawn_client(group, rpc)
    let call_result : Json = {
      "content": [{ "type": "text", "text": "boom" }],
      "isError": true,
    }
    spawn_server(group, transport, stock_reply({ "tools": [] }, call_result))
    let result = @mcp.McpClient::new(rpc).call_tool(
      name="explode",
      arguments=Json::empty_object(),
    )
    assert_true(result.is_error)
    assert_eq(result.render_text(), "boom")
  })
}

///|
async test "call_tool raises on a JSON-RPC error reply" {
  @async.with_task_group(group => {
    let transport = new_transport()
    let rpc = @jsonrpc.Client::new(transport)
    spawn_client(group, rpc)
    let reply = fn(request : Json) -> Json? {
      match method_of(request) {
        "tools/call" => Some(failure(request, -32602, "unknown tool"))
        _ => None
      }
    }
    spawn_server(group, transport, reply)
    let outcome = try {
      @mcp.McpClient::new(rpc).call_tool(
        name="ghost",
        arguments=Json::empty_object(),
      )
      |> ignore
      "no error raised"
    } catch {
      @jsonrpc.Failed(code~, message~) => "failed \{code} \{message}"
      error if @async.is_being_cancelled() => raise error
      _ => "other error"
    }
    assert_eq(outcome, "failed -32602 unknown tool")
  })
}

///|
async test "list_tools raises Protocol on a malformed result" {
  @async.with_task_group(group => {
    let transport = new_transport()
    let rpc = @jsonrpc.Client::new(transport)
    spawn_client(group, rpc)
    let reply = fn(request : Json) -> Json? {
      match method_of(request) {
        "tools/list" => Some(success(request, Json::empty_object()))
        _ => None
      }
    }
    spawn_server(group, transport, reply)
    let outcome = try {
      @mcp.McpClient::new(rpc).list_tools() |> ignore
      "no error raised"
    } catch {
      @mcp.Protocol(_) => "protocol"
      error if @async.is_being_cancelled() => raise error
      _ => "other error"
    }
    assert_eq(outcome, "protocol")
  })
}
