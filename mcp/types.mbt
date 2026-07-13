// MCP protocol value types and their decoders, plus rendering a `tools/call`
// result into the plain text openseek surfaces to the model.

///|
/// An MCP-layer failure: the server sent a response that could not be read as
/// the expected MCP shape. A JSON-RPC *error* reply surfaces separately as
/// `@jsonrpc.ResponseError`.
pub(all) suberror McpError {
  /// The server's response did not match the expected MCP shape; the string
  /// says what was wrong.
  Protocol(String)
}

///|
impl Show for McpError with fn output(self, logger) {
  match self {
    Protocol(message) => logger.write_string("mcp protocol error: \{message}")
  }
}

///|
/// A tool advertised by an MCP server via `tools/list`.
pub struct McpTool {
  /// The tool's name as the server exposes it (before openseek namespaces it).
  name : String
  /// Human-readable description, or "" when the server omits one.
  description : String
  /// The tool's JSON Schema for arguments, forwarded to the model unchanged.
  /// Defaults to an open object schema when the server omits `inputSchema`.
  input_schema : Json
} derive(Eq, Debug)

///|
/// One block of a `tools/call` result's `content` array. openseek's model view
/// is text, so non-text blocks are kept as compact descriptors — image/audio
/// bytes are noted, not forwarded.
pub(all) enum ContentBlock {
  /// A text block and its text.
  Text(String)
  /// An image block; only its MIME type is surfaced (the base64 payload is not
  /// sent to a text model).
  Image(mime_type~ : String)
  /// An embedded resource: its uri and, when the server inlines it, its text.
  Resource(uri~ : String, text~ : String?)
  /// Any other block type (audio, resource_link, unknown): its `type` tag.
  Other(kind~ : String)
} derive(Eq, Debug)

///|
/// The result of a `tools/call`: its content blocks, any structured output, and
/// whether the server flagged the call as a tool-level error (distinct from a
/// JSON-RPC error). Since 2025-06-18 a server may return the real result in
/// `structuredContent` and leave `content` empty (or a generic status), so the
/// structured value is kept rather than dropped.
pub struct CallToolResult {
  content : Array[ContentBlock]
  structured_content : Json?
  is_error : Bool
} derive(Eq, Debug)

///|
/// What the server reported from `initialize`: its negotiated protocol version
/// and identity. `server_name`/`server_version` are "" when the server omits
/// `serverInfo`.
pub struct InitializeResult {
  protocol_version : String
  server_name : String
  server_version : String
  instructions : String?
} derive(Eq, Debug)

///|
/// The open object schema used when a tool omits its `inputSchema`.
fn default_object_schema() -> Json {
  { "type": "object" }
}

///|
/// Decode an `initialize` result. Raises `Protocol` when `protocolVersion` is
/// missing (the one field the handshake cannot proceed without).
fn decode_initialize_result(result : Json) -> InitializeResult raise {
  guard result is { "protocolVersion": String(protocol_version), .. } else {
    raise Protocol("initialize result is missing a string `protocolVersion`")
  }
  let server_name = match result {
    { "serverInfo": { "name": String(name), .. }, .. } => name
    _ => ""
  }
  let server_version = match result {
    { "serverInfo": { "version": String(version), .. }, .. } => version
    _ => ""
  }
  let instructions = match result {
    { "instructions": String(text), .. } => Some(text)
    _ => None
  }
  { protocol_version, server_name, server_version, instructions }
}

///|
/// Decode one page of a `tools/list` result: its tools and the `nextCursor`
/// (when the server paginates). Raises `Protocol` when the `tools` array is
/// absent.
fn decode_tools_page(result : Json) -> (Array[McpTool], String?) raise {
  guard result is { "tools": Array(entries), .. } else {
    raise Protocol("tools/list result is missing a `tools` array")
  }
  let tools = []
  for entry in entries {
    tools.push(decode_tool(entry))
  }
  let cursor = match result {
    { "nextCursor": String(cursor), .. } => Some(cursor)
    _ => None
  }
  (tools, cursor)
}

///|
/// Decode one tool entry. Raises `Protocol` when it has no string `name`.
fn decode_tool(entry : Json) -> McpTool raise {
  guard entry is { "name": String(name), .. } else {
    raise Protocol("tool entry is missing a string `name`")
  }
  let description = match entry {
    { "description": String(description), .. } => description
    _ => ""
  }
  let input_schema = match entry {
    { "inputSchema": schema, .. } => schema
    _ => default_object_schema()
  }
  { name, description, input_schema }
}

///|
/// Decode a `tools/call` result. A missing `content` array yields empty content;
/// `isError` defaults to false.
fn decode_call_result(result : Json) -> CallToolResult raise {
  let content = match result {
    { "content": Array(blocks), .. } => {
      let decoded = []
      for block in blocks {
        decoded.push(decode_content_block(block))
      }
      decoded
    }
    _ => []
  }
  let structured_content = match result {
    { "structuredContent": value, .. } => Some(value)
    _ => None
  }
  let is_error = match result {
    { "isError": True, .. } => true
    _ => false
  }
  { content, structured_content, is_error }
}

///|
/// Decode one content block. Raises `Protocol` when the block has no string
/// `type`.
fn decode_content_block(block : Json) -> ContentBlock raise {
  match block {
    { "type": String("text"), "text": String(text), .. } => Text(text)
    { "type": String("image"), .. } => {
      let mime_type = match block {
        { "mimeType": String(mime_type), .. } => mime_type
        _ => ""
      }
      Image(mime_type~)
    }
    { "type": String("resource"), "resource": resource, .. } => {
      let uri = match resource {
        { "uri": String(uri), .. } => uri
        _ => ""
      }
      let text = match resource {
        { "text": String(text), .. } => Some(text)
        _ => None
      }
      Resource(uri~, text~)
    }
    { "type": String(kind), .. } => Other(kind~)
    _ => raise Protocol("content block is missing a string `type`")
  }
}

///|
/// Render the result into a single string for the model: text blocks verbatim,
/// non-text blocks as compact placeholders, joined by newlines, plus any
/// `structuredContent` the content array does not already carry (so structured
/// output is never lost). The caller applies any size budget and metadata
/// footer. Empty content and no structured output yields "".
pub fn CallToolResult::render_text(self : CallToolResult) -> String {
  let out = StringBuilder()
  let mut first = true
  for block in self.content {
    if !first {
      out.write_string("\n")
    }
    first = false
    match block {
      Text(text) => out.write_string(text)
      Image(mime_type~) => out.write_string("[image: \{mime_type}]")
      Resource(uri~, text~) =>
        match text {
          Some(text) => out.write_string("[resource \{uri}]\n\{text}")
          None => out.write_string("[resource: \{uri}]")
        }
      Other(kind~) => out.write_string("[unsupported content: \{kind}]")
    }
  }
  let text = out.to_string()
  // Preserve structured output. A conformant server mirrors it into a text
  // block (then `text` already contains it — don't duplicate); when it does not
  // (empty content, or a bare status) append the serialized structure.
  match self.structured_content {
    Some(structured) => {
      let serialized = structured.stringify()
      if text == "" {
        serialized
      } else if text.contains(serialized) {
        text
      } else {
        "\{text}\n\{serialized}"
      }
    }
    None => text
  }
}
