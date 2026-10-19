// The MCP client: typed `initialize` / `tools/list` / `tools/call` over a
// `@jsonrpc.Client`. The caller owns the transport and must have a running
// message pump (the connect layer spawns it) before issuing these calls.

///|
/// The MCP protocol version this client prefers and advertises in `initialize`
/// on the legacy handshake path. Modern peers use `discover` instead.
const LegacyProtocolVersion : String = "2025-11-25"

///|
/// Whether this client can speak `version`. The server echoes our preferred
/// version when it supports it, otherwise names another; if that one is not in
/// this set the connection is incompatible and the handshake must not proceed.
/// The tool surface (`tools/list`, `tools/call`) is stable across these
/// revisions.
fn is_supported_version(version : String) -> Bool {
  // The preferred version is named, not respelled: this list is the one place
  // a bump to `LegacyProtocolVersion` would otherwise silently leave behind.
  version == LegacyProtocolVersion ||
  version == "2025-06-18" ||
  version == "2025-03-26" ||
  version == "2024-11-05"
}

///|
/// An MCP client bound to a connected `@jsonrpc.Client`.
struct McpClient {
  rpc : @jsonrpc.Client
  mut metadata : Json?
  list_before_call : Bool
  mut tools_listed : Bool
}

///|
/// Wrap a connected JSON-RPC client. Its message pump must already be running
/// (spawned by the transport/connect layer) so replies are routed.
/// HTTP transports enable `list_before_call` to obtain header annotations before
/// the first modern tool call, even when the caller has not listed tools.
pub fn McpClient::McpClient(
  rpc : @jsonrpc.Client,
  list_before_call~ : Bool = false,
) -> McpClient {
  { rpc, metadata: None, list_before_call, tools_listed: false, }
}

///|
/// Close the underlying JSON-RPC client and its transport. Idempotent.
pub fn McpClient::close(self : McpClient) -> Unit {
  self.rpc.close()
}

///|
/// Whether the connection has ended — the server exited or hung up, the
/// transport failed, or it was closed locally. A closed client never answers.
pub fn McpClient::is_closed(self : McpClient) -> Bool {
  self.rpc.is_closed()
}

///|
/// Install the handler run once when the connection ends, for any reason.
/// It runs synchronously on whichever task closed the client, so it must not
/// block.
pub fn McpClient::set_close_handler(
  self : McpClient,
  handler : () -> Unit,
) -> Unit {
  self.rpc.set_close_handler(handler)
}

///|
/// Run the MCP handshake: send `initialize` with our client identity, then the
/// `notifications/initialized` notification once the server has answered.
/// Returns the server's negotiated protocol version and identity. Raises on
/// transport failure (`@jsonrpc.ResponseError`) or a malformed result
/// (`McpError`).
pub async fn McpClient::initialize(
  self : McpClient,
  client_name~ : String,
  client_version~ : String,
) -> InitializeResult {
  self.metadata = None
  self.tools_listed = false
  let params : Json = {
    "protocolVersion": LegacyProtocolVersion,
    "capabilities": Json::empty_object(),
    "clientInfo": { "name": client_name, "version": client_version },
  }
  let result = self.rpc.request(method_="initialize", params~)
  let init = decode_initialize_result(result)
  // The server may negotiate down to a version it supports; if we cannot speak
  // it, do not send `initialized` — the connection is incompatible.
  guard is_supported_version(init.protocol_version) else {
    raise Protocol(
      "server negotiated unsupported protocol version \{init.protocol_version}",
    )
  }
  self.rpc.notify(
    method_="notifications/initialized",
    params=Json::empty_object(),
  )
  init
}

///|
/// List every tool the server offers, following `nextCursor` pagination until
/// the server stops returning one. Raises on transport failure or a malformed
/// result.
pub async fn McpClient::list_tools(self : McpClient) -> Array[McpTool] {
  let tools = []
  let mut cursor : String? = None
  for ;; {
    let params : Json = match cursor {
      Some(cursor) => { "cursor": cursor }
      None => Json::empty_object()
    }
    let result = self.request(method_="tools/list", params~)
    let (page, next) = decode_tools_page(result)
    tools.append(page)
    guard next is Some(_) else { break }
    cursor = next
  }
  self.tools_listed = true
  tools
}

///|
/// Invoke a tool by its server-side name. A JSON-RPC error reply (e.g. unknown
/// tool, invalid params) raises `@jsonrpc.ResponseError`; a tool-level failure
/// comes back as a normal result with `is_error = true`.
pub async fn McpClient::call_tool(
  self : McpClient,
  name~ : String,
  arguments~ : Json,
) -> CallToolResult {
  if self.metadata is Some(_) && self.list_before_call && !self.tools_listed {
    self.list_tools() |> ignore
  }
  let params : Json = { "name": Json(name), "arguments": arguments }
  let result = self.request(method_="tools/call", params~)
  decode_call_result(result)
}
