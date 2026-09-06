// Connect to a remote MCP server over Streamable HTTP.

///|
/// The default handshake deadline, matching the stdio transport's.
const DefaultHandshakeTimeoutMs : Int = 30000

///|
/// A live Streamable HTTP MCP connection: the initialized client. Its
/// reader/writer tasks run on the task group passed to `connect`; the
/// connection is torn down when that group ends, or eagerly via `shutdown`.
struct HttpConnection {
  client : @mcp.McpClient
  init : @mcp.InitializeResult
}

///|
/// The initialized MCP client to issue `list_tools` / `call_tool` against.
pub fn HttpConnection::client(self : HttpConnection) -> @mcp.McpClient {
  self.client
}

///|
/// Tear the connection down eagerly: close the client and its transport
/// (cancelling any in-flight exchange); the reader/writer tasks end on their
/// own once their queues close. Idempotent.
pub fn HttpConnection::shutdown(self : HttpConnection) -> Unit {
  self.client.close()
}

///|
/// Wire a Streamable HTTP transport for the MCP endpoint at `url` to a JSON-RPC
/// client (reader and writer tasks on `group`), run the MCP handshake under
/// `handshake_timeout_ms`, and return the initialized connection. Raises when
/// the endpoint is unreachable, answers with an error, or the handshake fails
/// or times out (`@async.TimeoutError`), closing the transport in every failure
/// case. `headers` (e.g. `Authorization`) go on every request.
pub async fn[X] connect(
  group : @async.TaskGroup[X],
  url~ : String,
  headers? : Map[String, String] = Map([]),
  client_name~ : String,
  client_version~ : String,
  handshake_timeout_ms? : Int = DefaultHandshakeTimeoutMs,
) -> HttpConnection {
  // Each POST exchange runs as its own cancellable task on the connection's
  // group, so the jsonrpc writer is never blocked by a long or stalled response
  // stream — and closing the transport cancels an in-flight exchange.
  let transport = HttpTransport::HttpTransport(
    url,
    spawn=exchange => group.spawn(exchange, no_wait=true, allow_failure=true),
    extra_headers=headers,
  )
  let client = @jsonrpc.Client(transport)
  group.spawn_bg(
    () => client.run_message_pump(),
    no_wait=true,
    allow_failure=true,
  )
  group.spawn_bg(() => client.run_writer(), no_wait=true, allow_failure=true)
  let mcp_client = @mcp.McpClient(client)
  errdefer mcp_client.close()
  let init = @async.with_timeout(handshake_timeout_ms, () => {
    mcp_client.initialize(client_name~, client_version~)
  })
  { client: mcp_client, init, }
}
