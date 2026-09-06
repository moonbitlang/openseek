// MCP protocol value types and their decoders, plus rendering a `tools/call`
// result into the plain text openseek surfaces to the model.

///|
/// An MCP-layer failure: the server sent a response that could not be read as
/// the expected MCP shape. A JSON-RPC *error* reply surfaces separately as
/// `@jsonrpc.ResponseError`.
pub suberror McpError {
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
pub enum ContentBlock {
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
  let instructions = optional_string(result, "instructions")
  { protocol_version, server_name, server_version, instructions, }
}

///|
/// Decode one page of a `tools/list` result: its tools and the `nextCursor`
/// (when the server paginates). Raises `Protocol` when the `tools` array is
/// absent.
fn decode_tools_page(result : Json) -> (Array[McpTool], String?) raise {
  guard result is { "tools": Array(entries), .. } else {
    raise Protocol("tools/list result is missing a `tools` array")
  }
  let tools = entries.map(decode_tool)
  let cursor = optional_string(result, "nextCursor")
  (tools, cursor)
}

///|
/// Decode one tool entry. Raises `Protocol` when it has no string `name`.
fn decode_tool(entry : Json) -> McpTool raise {
  guard entry is { "name": String(name), .. } else {
    raise Protocol("tool entry is missing a string `name`")
  }
  let description = optional_string(entry, "description").unwrap_or("")
  let input_schema = match entry {
    { "inputSchema": schema, .. } => schema
    _ => default_object_schema()
  }
  { name, description, input_schema, }
}

///|
/// Decode a `tools/call` result. A missing `content` array yields empty content;
/// `isError` defaults to false.
fn decode_call_result(result : Json) -> CallToolResult raise {
  let content = match result {
    { "content": Array(blocks), .. } => blocks.map(decode_content_block)
    _ => []
  }
  let structured_content = match result {
    { "structuredContent": value, .. } => Some(value)
    _ => None
  }
  let is_error = match result {
    { "isError": true, .. } => true
    _ => false
  }
  { content, structured_content, is_error, }
}

///|
/// Decode one content block. Raises `Protocol` when the block has no string
/// `type`.
fn decode_content_block(block : Json) -> ContentBlock raise {
  match block {
    { "type": "text", "text": String(text), .. } => Text(text)
    { "type": "image", .. } => {
      let mime_type = optional_string(block, "mimeType").unwrap_or("")
      Image(mime_type~)
    }
    { "type": "resource", "resource": resource, .. } => {
      let uri = optional_string(resource, "uri").unwrap_or("")
      let text = optional_string(resource, "text")
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
  let text = self.content
    .map(block => {
      match block {
        Text(text) => text
        Image(mime_type~) => "[image: \{mime_type}]"
        Resource(uri~, text~) =>
          match text {
            Some(text) => "[resource \{uri}]\n\{text}"
            None => "[resource: \{uri}]"
          }
        Other(kind~) => "[unsupported content: \{kind}]"
      }
    })
    .join("\n")
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
} ///|
/// The string at `key`, or nothing when the field is absent or not a string.
///
/// Only for the fields MCP lets a server omit — every `guard ... else raise
/// Protocol` in this file stays exactly as strict as it was.

///|
fn optional_string(json : Json, key : String) -> String? {
  guard json is Object(fields) && fields.get(key) is Some(String(text)) else {
    return None
  }
  Some(text)
}

///|
pub extend CallToolResult with Debug::{to_repr}

///|
pub extend CallToolResult with Eq::{equal, not_equal}

///|
pub extend ContentBlock with Debug::{to_repr}

///|
pub extend ContentBlock with Eq::{equal, not_equal}

///|
pub extend InitializeResult with Debug::{to_repr}

///|
pub extend InitializeResult with Eq::{equal, not_equal}

///|
pub extend McpTool with Debug::{to_repr}

///|
pub extend McpTool with Eq::{equal, not_equal}
