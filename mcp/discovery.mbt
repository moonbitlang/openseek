///|
/// Probe a peer using stateless discovery. Transport owners decide whether an
/// error or timeout warrants legacy initialization; malformed successes never do.
/// Once discovered, every tool request carries this client's metadata.
pub async fn McpClient::discover(
  self : McpClient,
  client_name~ : String,
  client_version~ : String,
) -> InitializeResult {
  let metadata : Json = {
    "io.modelcontextprotocol/protocolVersion": @wire.ModernVersion,
    "io.modelcontextprotocol/clientInfo": {
      "name": client_name,
      "version": client_version,
    },
    "io.modelcontextprotocol/clientCapabilities": {},
  }
  let result = self.rpc.request(method_="server/discover", params={
    "_meta": metadata,
  })
  check_complete(result)
  guard result
    is { "supportedVersions": Array(versions), "capabilities": Object(_), .. } else {
    raise Protocol(
      "server/discover result needs supportedVersions and capabilities",
    )
  }
  guard versions.all(v => v is String(_)) &&
    versions.contains(Json(@wire.ModernVersion)) else {
    raise Protocol(
      "server/discover offers no supported stateless protocol version",
    )
  }
  let (server_name, server_version) = match result {
    {
      "_meta": {
        "io.modelcontextprotocol/serverInfo": {
          "name": String(name),
          "version": String(version),
          ..
        },
        ..
      },
      ..
    } => (Some(name), Some(version))
    _ => (None, None)
  }
  self.metadata = Some(metadata)
  self.tools_listed = false
  {
    protocol_version: @wire.ModernVersion,
    server_name,
    server_version,
    instructions: optional_string(result, "instructions"),
  }
}

///|
/// A stateless result must not be silently decoded as an empty successful tool
/// result when the peer actually requested input or used an unknown result type.
fn check_complete(result : Json) -> Unit raise {
  guard result is Object(fields) else {
    raise Protocol("result must be an object")
  }
  match fields.get("resultType") {
    None | Some(String("complete")) => ()
    Some(String("input_required")) =>
      raise Protocol(
        "server requested input; this client advertises no optional input capabilities",
      )
    _ => raise Protocol("unrecognized MCP resultType")
  }
}

///|
async fn McpClient::request(
  self : McpClient,
  method_~ : String,
  params~ : Json,
) -> Json {
  let params = match (self.metadata, params) {
    (Some(metadata), Object(fields)) => {
      let fields = fields.copy()
      fields["_meta"] = metadata
      Json(fields)
    }
    _ => params
  }
  let result = self.rpc.request(
    method_~,
    params~,
    cancel_on_exit=self.metadata is Some(_),
  )
  check_complete(result)
  result
}
