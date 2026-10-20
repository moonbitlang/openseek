// MCP protocol value types and their decoders, plus rendering a `tools/call`
// result into the text and images openseek surfaces to the model.

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
  /// The JSON Schema of the tool's `structuredContent`, when the server
  /// declares one (`outputSchema`, since 2025-06-18) as an object.
  output_schema : Json?
} derive(Eq, Debug)

///|
/// One block of a `tools/call` result's `content` array. Text and image blocks
/// keep their payload; other blocks are kept as compact descriptors — audio
/// bytes are noted, not forwarded.
pub enum ContentBlock {
  /// A text block and its text.
  Text(String)
  /// An image block: its declared MIME type and base64 `data`, as sent.
  Image(mime_type~ : String, data~ : String)
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
/// What discovery or legacy initialization reported: the selected protocol version
/// and identity. `server_name`/`server_version` are absent when the server omits
/// `serverInfo`.
pub struct InitializeResult {
  protocol_version : String
  server_name : String?
  server_version : String?
  instructions : String?
} derive(Eq, Debug)

///|
/// Decode an `initialize` result. Raises `Protocol` when `protocolVersion` is
/// missing (the one field the handshake cannot proceed without).
fn decode_initialize_result(result : Json) -> InitializeResult raise {
  guard result is { "protocolVersion": String(protocol_version), .. } else {
    raise Protocol("initialize result is missing a string `protocolVersion`")
  }
  let server_name = match result {
    { "serverInfo": { "name": String(name), .. }, .. } => Some(name)
    _ => None
  }
  let server_version = match result {
    { "serverInfo": { "version": String(version), .. }, .. } => Some(version)
    _ => None
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
  let input_schema : Json = match entry {
    { "inputSchema": schema, .. } => schema
    _ => { "type": "object" }
  }
  let output_schema = match entry {
    { "outputSchema": Object(_) as schema, .. } => Some(schema)
    _ => None
  }
  { name, description, input_schema, output_schema, }
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
  let is_error = result is { "isError": true, .. }
  { content, structured_content, is_error, }
}

///|
/// Decode one content block. Raises `Protocol` when the block has no string
/// `type`.
fn decode_content_block(block : Json) -> ContentBlock raise {
  match block {
    { "type": "text", "text": String(text), .. } => Text(text)
    { "type": "image", "data": String(data), "mimeType": String(mime_type), .. } =>
      Image(mime_type~, data~)
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
/// A `tools/call` result as the model receives it: its text and the images
/// attached alongside it.
pub struct RenderedResult {
  text : String
  images : Array[@protocol.Image]
}

///|
/// Render the result for the model in content order: text blocks verbatim,
/// images the shared validator accepts as attached images, and every other
/// block (including a rejected image) as a compact placeholder in the text.
/// Text parts are joined by newlines, plus any `structuredContent` the content
/// array does not already carry (so structured output is never lost). The
/// caller applies any size budget and metadata footer. Empty content and no
/// structured output yields "" and no images.
pub fn CallToolResult::render(self : CallToolResult) -> RenderedResult {
  let parts = []
  let images = []
  for block in self.content {
    match block {
      Text(text) => parts.push(text)
      Image(mime_type~, data~) =>
        try @protocol.Image::from_base64(media_type=mime_type, data) catch {
          error => {
            // `ImageError` shows its reason only through `Error`.
            let error : Error = error
            parts.push("[image \{mime_type} not attached: \{error}]")
          }
        } noraise {
          image => images.push(image)
        }
      Resource(uri~, text~) =>
        match text {
          Some(text) => parts.push("[resource \{uri}]\n\{text}")
          None => parts.push("[resource: \{uri}]")
        }
      Other(kind~) => parts.push("[unsupported content: \{kind}]")
    }
  }
  let text = parts.join("\n")
  // Preserve structured output. A conformant server mirrors it into a text
  // block (then `text` already contains it — don't duplicate); when it does not
  // (empty content, or a bare status) append the serialized structure.
  let text = match self.structured_content {
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
  { text, images, }
}

///|
/// The text part of `render`, for callers that read a result as text.
pub fn CallToolResult::render_text(self : CallToolResult) -> String {
  self.render().text
}

///|
/// The string at `key`, or nothing when the field is absent or not a string.
///
/// Only for the fields MCP lets a server omit — every `guard ... else raise
/// Protocol` in this file stays exactly as strict as it was.
fn optional_string(json : Json, key : String) -> String? {
  guard json is Object(fields) && fields.get(key) is Some(String(text)) else {
    return None
  }
  Some(text)
}

///|
#doc(hidden)
#deprecated
pub extend CallToolResult with Debug::{to_repr}

///|
#doc(hidden)
#deprecated
pub extend CallToolResult with Eq::{equal, not_equal}

///|
#doc(hidden)
#deprecated
pub extend ContentBlock with Debug::{to_repr}

///|
#doc(hidden)
#deprecated
pub extend ContentBlock with Eq::{equal, not_equal}

///|
#doc(hidden)
#deprecated
pub extend InitializeResult with Debug::{to_repr}

///|
#doc(hidden)
#deprecated
pub extend InitializeResult with Eq::{equal, not_equal}

///|
#doc(hidden)
#deprecated
pub extend McpTool with Debug::{to_repr}

///|
#doc(hidden)
#deprecated
pub extend McpTool with Eq::{equal, not_equal}
