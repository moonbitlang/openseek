// The MCP client: typed `initialize` / `tools/list` / `tools/call` over a
// `@jsonrpc.Client`. The caller owns the transport and must have a running
// message pump (the connect layer spawns it) before issuing these calls.

///|
/// The MCP protocol version this client prefers and advertises in `initialize`
/// (the current revision as of this writing).
pub const ProtocolVersion : String = "2025-11-25"

///|
/// Whether this client can speak `version`. The server echoes our preferred
/// version when it supports it, otherwise names another; if that one is not in
/// this set the connection is incompatible and the handshake must not proceed.
/// The tool surface (`tools/list`, `tools/call`) is stable across these
/// revisions.
fn is_supported_version(version : String) -> Bool {
  version == "2025-11-25" ||
  version == "2025-06-18" ||
  version == "2025-03-26" ||
  version == "2024-11-05"
}

///|
/// An MCP client bound to a connected `@jsonrpc.Client`.
struct McpClient {
  rpc : @jsonrpc.Client
}

///|
/// Wrap a connected JSON-RPC client. Its message pump must already be running
/// (spawned by the transport/connect layer) so replies are routed.
pub fn McpClient::new(rpc : @jsonrpc.Client) -> McpClient {
  { rpc, }
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
  let params : Json = {
    "protocolVersion": ProtocolVersion,
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
    let result = self.rpc.request(method_="tools/list", params~)
    let (page, next) = decode_tools_page(result)
    for tool in page {
      tools.push(tool)
    }
    match next {
      Some(next) => cursor = Some(next)
      None => break
    }
  }
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
  let params : Json = { "name": name, "arguments": arguments }
  let result = self.rpc.request(method_="tools/call", params~)
  decode_call_result(result)
}
