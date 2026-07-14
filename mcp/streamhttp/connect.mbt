// Connect to a remote MCP server over Streamable HTTP.

///|
/// The default handshake deadline, matching the stdio transport's.
pub const DefaultHandshakeTimeoutMs : Int = 30000

///|
/// A live Streamable HTTP MCP connection: the initialized client plus an
/// idempotent teardown. Its reader/writer tasks run on the task group passed to
/// `connect`; the connection is torn down when that group ends, or eagerly via
/// `shutdown`.
struct HttpConnection {
  client : @mcp.McpClient
  init : @mcp.InitializeResult
  teardown : () -> Unit
}

///|
/// The initialized MCP client to issue `list_tools` / `call_tool` against.
pub fn HttpConnection::client(self : HttpConnection) -> @mcp.McpClient {
  self.client
}

///|
/// What the server reported from `initialize`.
pub fn HttpConnection::init(self : HttpConnection) -> @mcp.InitializeResult {
  self.init
}

///|
/// Tear the connection down eagerly: cancel the reader/writer tasks and close
/// the transport. Idempotent.
pub fn HttpConnection::shutdown(self : HttpConnection) -> Unit {
  (self.teardown)()
}

///|
/// Wire a Streamable HTTP transport for the MCP endpoint at `url` to a JSON-RPC
/// client (reader and writer tasks on `group`), run the MCP handshake under
/// `handshake_timeout_ms`, and return the initialized connection — or `None`
/// when the endpoint is unreachable, answers with an error, or the handshake
/// fails or times out. `headers` (e.g. `Authorization`) go on every request.
pub async fn[X] connect(
  group : @async.TaskGroup[X],
  url~ : String,
  headers? : Map[String, String] = Map([]),
  client_name~ : String,
  client_version~ : String,
  handshake_timeout_ms? : Int = DefaultHandshakeTimeoutMs,
) -> HttpConnection? {
  // Each POST exchange runs as its own cancellable task on the connection's
  // group, so the jsonrpc writer is never blocked by a long or stalled response
  // stream — and teardown can cancel an in-flight exchange.
  let transport = HttpTransport::new(
    url,
    spawn=exchange => group.spawn(exchange, no_wait=true, allow_failure=true),
    extra_headers=headers,
  )
  let client = @jsonrpc.Client::new(transport)
  let pump = group.spawn(
    () => client.run_message_pump(),
    no_wait=true,
    allow_failure=true,
  )
  let writer = group.spawn(
    () => client.run_writer(),
    no_wait=true,
    allow_failure=true,
  )
  let torn_down : Ref[Bool] = { val: false }
  let teardown = () => {
    if !torn_down.val {
      torn_down.val = true
      pump.cancel()
      writer.cancel()
      transport.close()
    }
  }
  let mcp_client = @mcp.McpClient::new(client)
  let init = @async.with_timeout_opt(handshake_timeout_ms, () => {
    mcp_client.initialize(client_name~, client_version~)
  }) catch {
    error if @async.is_being_cancelled() => {
      teardown()
      raise error
    }
    _ => {
      teardown()
      return None
    }
  }
  guard init is Some(init) else {
    teardown()
    return None
  }
  Some({ client: mcp_client, init, teardown })
}
