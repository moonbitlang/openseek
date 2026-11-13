///|
/// The chat model and thinking types are owned by the protocol module, which
/// the Desktop host and frontend share; re-exported so engine code keeps
/// naming them `@deepseek.Model` and `@deepseek.ThinkingMode`.
pub using @protocol {
  type DsVariant,
  type KimiVariant,
  type GlmVariant,
  type Model,
  type ThinkingMode,
}

///|
/// Optional structured response format for DeepSeek chat completions.
///
/// Leave absent for normal assistant text. Use `JsonObject` only when a caller
/// explicitly wants the model's assistant content constrained to a JSON object.
#derive(Eq, Debug)
pub(all) enum ResponseFormat {
  JsonObject
}

///|
/// Returns the DeepSeek wire name for a response format.
impl Show for ResponseFormat with fn to_string(self : ResponseFormat) -> String {
  match self {
    JsonObject => "json_object"
  }
}

///|
/// DeepSeek chat message roles.
///
/// `Tool(tool_call_id)` represents a tool response message and carries the
/// `tool_call_id` field required by the API.
#derive(Eq, Debug)
pub(all) enum Role {
  System
  User
  Assistant
  Tool(String)
}

///|
/// Returns the DeepSeek wire name for a chat message role.
impl Show for Role with fn to_string(self : Role) -> String {
  match self {
    System => "system"
    User => "user"
    Assistant => "assistant"
    Tool(_) => "tool"
  }
}

///|
/// A typed chat message.
///
/// Construct content messages with `ChatMessage(User, content=[Text("hello")])`,
/// `ChatMessage(System, content=[Text("...")])`, or
/// `ChatMessage(Tool("call_id"), content=[Text("...")])`.
/// Assistant tool-call echo messages should pass the assistant response
/// content explicitly with `ChatMessage(Assistant, content=[Text(response.content)],
/// tool_calls=response.tool_calls)`. When the combined assistant text is empty,
/// a tool-call message encodes JSON `content: null`.
#derive(Debug)
pub struct ChatMessage {
  role : Role
  content : Content
  tool_calls : Array[ToolCall]
  reasoning_content : String?
}

///|
/// Constructs a typed chat message with an ordered array of content parts.
/// Even plain text uses one `Text` part; string-versus-array JSON is an encoding
/// detail. System and assistant messages accept text parts only.
/// The supplied array is wrapped in `Content`, providing `text()` and `iter()`.
/// Request encoders validate role restrictions and file IDs before sending.
pub fn ChatMessage::ChatMessage(
  role : Role,
  content~ : Array[ContentPart],
  tool_calls~ : Array[ToolCall] = [],
  reasoning_content? : String,
) -> ChatMessage {
  { role, content: Content(content), tool_calls, reasoning_content, }
}

///|
/// Token usage reported by DeepSeek chat responses.
#derive(Debug, ToJson)
pub struct Usage {
  prompt_tokens : Int32
  completion_tokens : Int32
  total_tokens : Int32
  prompt_cache_hit_tokens : Int32
  prompt_cache_miss_tokens : Int32
}

///|
/// Decoded DeepSeek chat response content, tool calls, and token usage.
#derive(Debug)
pub struct ChatResponse {
  /// Assistant text content returned by DeepSeek. This is empty when the API
  /// returns JSON `content: null`, such as a tool-call-only assistant message.
  content : String
  /// Reasoning or thinking text returned by DeepSeek. This is empty when the
  /// response does not include `reasoning_content`.
  reasoning_content : String
  /// Tool calls requested by the assistant. Echo these in the next assistant
  /// `ChatMessage` before sending the corresponding tool result messages.
  tool_calls : Array[ToolCall]
  /// Token usage metadata reported for the chat completion.
  usage : Usage
}

///|
test "chat message constructor" {
  let user = ChatMessage(User, content=[Text("hello")])
  assert_eq("\{user.role}", "user")
  assert_eq(user.content.text(), "hello")
  let assistant = ChatMessage(Assistant, content=[Text("done")])
  assert_eq("\{assistant.role}", "assistant")
  assert_eq(assistant.content.text(), "done")
  let tool = ChatMessage(Tool("call_123"), content=[Text("tool result")])
  assert_eq("\{tool.role}", "tool")
  assert_eq(tool.content.text(), "tool result")
}

///|
#doc(hidden)
#deprecated
pub extend ChatMessage with Debug::{to_repr}

///|
#doc(hidden)
#deprecated
pub extend ChatResponse with Debug::{to_repr}

///|
#doc(hidden)
#deprecated
pub extend ResponseFormat with Debug::{to_repr}

///|
#doc(hidden)
#deprecated
pub extend ResponseFormat with Eq::{equal, not_equal}

///|
#doc(hidden)
#deprecated
pub extend Role with Debug::{to_repr}

///|
#doc(hidden)
#deprecated
pub extend Role with Eq::{equal, not_equal}

///|
#doc(hidden)
#deprecated
pub extend Usage with Debug::{to_repr}

///|
#doc(hidden)
#deprecated
pub extend Usage with ToJson::{to_json}
