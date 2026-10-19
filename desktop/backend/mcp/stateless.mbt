///|
/// Validate the metadata of this request, without consulting any previous call.
/// Legacy requests keep their existing handshake and header semantics.
fn Server::validate_modern(
  self : Server,
  headers : @http.Headers,
  message : Json,
) -> Json? {
  let header_version = headers.get("MCP-Protocol-Version")
  let body_version = @wire.request_version(message)
  let has_metadata = message
    is {
      "params": {
        "_meta": { "io.modelcontextprotocol/protocolVersion": _, .. },
        ..
      },
      ..
    }
  guard has_metadata ||
    (header_version is Some(version) && !supported_legacy_version(version)) else {
    return None
  }
  guard message
    is { "id": id, "method": String(method_), "params": Object(params), .. } else {
    return Some(
      failure(Json::null(), InvalidRequest, "Invalid stateless request"),
    )
  }
  guard body_version is Some(version) &&
    header_version == Some(version) &&
    headers.get("Mcp-Method") == Some(method_) else {
    return Some(
      failure(
        id, -32020, "Missing or mismatched protocol version or Mcp-Method",
      ),
    )
  }
  guard version == @wire.ModernVersion else {
    return Some({
      "jsonrpc": "2.0",
      "id": id,
      "error": {
        "code": -32022,
        "message": "Unsupported protocol version",
        "data": { "requested": version, "supported": [@wire.ModernVersion] },
      },
    })
  }
  guard params.get("_meta")
    is Some({ "io.modelcontextprotocol/clientCapabilities": Object(_), .. }) else {
    return Some(failure(id, InvalidParams, "Missing clientCapabilities"))
  }
  if method_ == "tools/call" {
    guard params.get("name") is Some(String(name)) else {
      return Some(failure(id, InvalidParams, "tools/call needs a string name"))
    }
    let matches = if headers.get("Mcp-Name") is Some(value) {
      (@wire.decode_header(value) == name) catch {
        _ => false
      }
    } else {
      false
    }
    guard matches else {
      return Some(failure(id, -32020, "Missing or mismatched Mcp-Name"))
    }
    if self.tools.get(name) is Some(tool) {
      let (names, expected) = (
        @wire.parameter_header_names(tool.input_schema),
        @wire.parameter_headers(
          tool.input_schema,
          params.get("arguments").unwrap_or(Json::empty_object()),
        ),
      ) catch {
        _ =>
          return Some(
            failure(id, InvalidParams, "Invalid mirrored tool arguments"),
          )
      }
      for key in names {
        let matches = match
          (expected.get(key), headers.get(CaseInsensitiveString(key))) {
          (None, None) => true
          (Some(encoded), Some(value)) =>
            (@wire.decode_header(value) == @wire.decode_header(encoded)) catch {
              _ => false
            }
          _ => false
        }
        guard matches else {
          return Some(failure(id, -32020, "Missing or mismatched \{key}"))
        }
      }
    }
  }
  None
}
