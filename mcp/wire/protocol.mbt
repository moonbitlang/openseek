///|
/// Stateless MCP revision implemented by the client and host server.
pub const ModernVersion = "2026-07-28"

///|
/// Protocol-defined stateless errors identify a stateless peer, even on HTTP 400.
pub fn modern_error(code : Int32) -> Bool {
  code is (-32020 | -32021 | -32022)
}

///|
/// Version carried by an individual stateless request, absent on legacy traffic.
pub fn request_version(message : Json) -> String? {
  match message {
    {
      "params": {
        "_meta": {
          "io.modelcontextprotocol/protocolVersion": String(version),
          ..
        },
        ..
      },
      ..
    } => Some(version)
    _ => None
  }
}

///|
/// Encode a mirrored HTTP field without losing Unicode, whitespace or sentinels.
pub fn encode_header(value : String) -> String {
  if value.trim() != value ||
    !value.all(c => c == '\t' || (c >= ' ' && c <= '~')) ||
    (value.has_prefix("=?base64?") && value.has_suffix("?=")) {
    "=?base64?\{@base64.encode(@utf8.encode(value))}?="
  } else {
    value
  }
}

///|
/// Decode a mirrored field; malformed encodings are protocol failures.
pub fn decode_header(value : String) -> String raise {
  if value.strip_prefix("=?base64?") is Some(rest) &&
    rest.strip_suffix("?=") is Some(encoded) {
    @utf8.decode(@base64.decode(encoded))
  } else {
    guard value.all(c => c == '\t' || (c >= ' ' && c <= '~')) else {
      raise HeaderError("invalid HTTP header value")
    }
    value
  }
}

///|
/// A schema annotation or argument cannot be represented by MCP HTTP headers.
pub suberror HeaderError {
  HeaderError(String)
}
