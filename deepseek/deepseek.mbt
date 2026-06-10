///|
/// DeepSeek chat model names accepted by the chat completions API.
pub(all) enum Model {
  V4Flash
  V4Pro
} derive(Eq, Debug)

///|
/// Returns the DeepSeek wire name for a chat model.
pub impl Show for Model with fn to_string(self : Model) -> String {
  match self {
    V4Flash => "deepseek-v4-flash"
    V4Pro => "deepseek-v4-pro"
  }
}

///|
/// Parses a DeepSeek wire model name into a typed model.
pub fn Model::parse(input : String) -> Model raise {
  match input {
    "deepseek-v4-flash" => V4Flash
    "deepseek-v4-pro" => V4Pro
    other => fail("unknown DeepSeek model: \{other}")
  }
}

///|
/// DeepSeek thinking mode request toggle.
pub(all) enum ThinkingMode {
  Enabled
  Disabled
} derive(Eq, Debug)

///|
/// Returns the DeepSeek wire name for a thinking mode toggle.
pub impl Show for ThinkingMode with fn to_string(self : ThinkingMode) -> String {
  match self {
    Enabled => "enabled"
    Disabled => "disabled"
  }
}

///|
/// Parses a thinking mode from its wire name (`enabled`/`disabled`), raising
/// on anything else — the inverse of `Show`, for CLI flags and config.
pub fn ThinkingMode::parse(input : String) -> ThinkingMode raise {
  match input {
    "enabled" => Enabled
    "disabled" => Disabled
    other => fail("unknown thinking mode: \{other} (use enabled or disabled)")
  }
}

///|
/// DeepSeek reasoning effort for thinking mode.
pub(all) enum ReasoningEffort {
  High
  Max
} derive(Eq, Debug)

///|
/// Returns the DeepSeek wire name for a reasoning effort.
pub impl Show for ReasoningEffort with fn to_string(self : ReasoningEffort) -> String {
  match self {
    High => "high"
    Max => "max"
  }
}

///|
/// Parses a reasoning effort from its wire name (`high`/`max`), raising on
/// anything else — the inverse of `Show`, for CLI flags and config.
pub fn ReasoningEffort::parse(input : String) -> ReasoningEffort raise {
  match input {
    "high" => High
    "max" => Max
    other => fail("unknown reasoning effort: \{other} (use high or max)")
  }
}

///|
/// Optional structured response format for DeepSeek chat completions.
///
/// Leave absent for normal assistant text. Use `JsonObject` only when a caller
/// explicitly wants the model's assistant content constrained to a JSON object.
pub(all) enum ResponseFormat {
  JsonObject
} derive(Eq, Debug)

///|
/// Returns the DeepSeek wire name for a response format.
pub impl Show for ResponseFormat with fn to_string(self : ResponseFormat) -> String {
  match self {
    JsonObject => "json_object"
  }
}

///|
/// DeepSeek chat message roles.
///
/// `Tool(tool_call_id)` represents a tool response message and carries the
/// `tool_call_id` field required by the API.
pub(all) enum Role {
  System
  User
  Assistant
  Tool(String)
} derive(Eq, Debug)

///|
/// Returns the DeepSeek wire name for a chat message role.
pub impl Show for Role with fn to_string(self : Role) -> String {
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
/// Construct content messages with `ChatMessage(User, content="hello")`,
/// `ChatMessage(System, content="...")`, or
/// `ChatMessage(Tool("call_id"), content="...")`.
/// Assistant tool-call echo messages should pass the assistant response
/// content explicitly with `ChatMessage(Assistant, content=response.content,
/// tool_calls=response.tool_calls)`. When that content is empty, it is encoded
/// with JSON `content: null`.
pub struct ChatMessage {
  role : Role
  content : String
  tool_calls : Array[ToolCall]
  reasoning_content : String?
} derive(Debug)

///|
/// Constructs a typed chat message.
pub fn ChatMessage::ChatMessage(
  role : Role,
  content~ : String,
  tool_calls? : Array[ToolCall] = [],
  reasoning_content? : String,
) -> ChatMessage {
  { role, content, tool_calls, reasoning_content }
}

///|
/// Token usage reported by DeepSeek chat responses.
pub struct Usage {
  prompt_tokens : Int
  completion_tokens : Int
  total_tokens : Int
  prompt_cache_hit_tokens : Int
  prompt_cache_miss_tokens : Int
} derive(Debug)

///|
/// Decoded DeepSeek chat response content, tool calls, and token usage.
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
} derive(Debug)
