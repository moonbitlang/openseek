///|
/// DeepSeek chat model variants.
pub(all) enum DsVariant {
  V4Flash
  V4Pro
} derive(Eq, Debug)

///|
/// Kimi chat model variants.
pub(all) enum KimiVariant {
  K27Code
  K27CodeHighSpeed
} derive(Eq, Debug)

///|
/// Supported chat models grouped by provider.
pub(all) enum Model {
  Deepseek(DsVariant)
  Kimi(KimiVariant)
} derive(Eq, Debug)

///|
/// Returns the wire name for a DeepSeek chat model variant.
impl Show for DsVariant with fn to_string(self : DsVariant) -> String {
  match self {
    V4Flash => "deepseek-v4-flash"
    V4Pro => "deepseek-v4-pro"
  }
}

///|
/// Returns the wire name for a Kimi chat model variant.
impl Show for KimiVariant with fn to_string(self : KimiVariant) -> String {
  match self {
    K27Code => "kimi-k2.7-code"
    K27CodeHighSpeed => "kimi-k2.7-code-highspeed"
  }
}

///|
/// Returns the wire name for a chat model.
pub impl Show for Model with fn to_string(self : Model) -> String {
  match self {
    Deepseek(variant) => "\{variant}"
    Kimi(variant) => "\{variant}"
  }
}

///|
/// Parses a wire model name into a typed model.
pub fn Model::parse(input : String) -> Model raise {
  match input {
    "deepseek-v4-flash" => Deepseek(V4Flash)
    "deepseek-v4-pro" => Deepseek(V4Pro)
    "kimi-k2.7-code" => Kimi(K27Code)
    "kimi-k2.7-code-highspeed" => Kimi(K27CodeHighSpeed)
    other => fail("unknown model: \{other}")
  }
}

///|
/// Context window served by the official API, in tokens.
///
/// Both V4 variants serve 1M context ("1M context is now the default across
/// all official DeepSeek services", api-docs.deepseek.com news260424); the
/// kimi-k2.7-code family serves 256K. These are the totals a request's
/// prompt and completion must fit within, used by the agent loop as the
/// ceiling for its auto-compaction guard. Per-variant match so adding a
/// variant forces an explicit choice here.
pub fn Model::context_window(self : Model) -> Int {
  match self {
    Deepseek(V4Flash | V4Pro) => 1_000_000
    Kimi(K27Code | K27CodeHighSpeed) => 262_144
  }
}

///|
/// DeepSeek thinking control for V4 models.
///
/// `No` disables thinking. `High` and `Max` enable thinking and select the
/// corresponding reasoning effort.
pub(all) enum ThinkingMode {
  No
  High
  Max
} derive(Eq, Debug)

///|
/// Returns the user-facing name for a thinking mode.
pub impl Show for ThinkingMode with fn to_string(self : ThinkingMode) -> String {
  match self {
    No => "no"
    High => "high"
    Max => "max"
  }
}

///|
/// Parses a thinking mode from its user-facing name (`no`/`high`/`max`),
/// raising on anything else.
///
/// The legacy `disabled` and `enabled` names remain accepted as aliases for
/// `No` and `Max` so existing environment settings keep working.
pub fn ThinkingMode::parse(input : String) -> ThinkingMode raise {
  match input {
    "no" | "disabled" => No
    "high" => High
    "max" | "enabled" => Max
    other => fail("unknown thinking mode: \{other} (use no, high, or max)")
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
pub(all) enum Role {
  System
  User
  Assistant
  Tool(String)
} derive(Eq, Debug)

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
} derive(Debug, ToJson)

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

///|
test "chat message constructor" {
  let user = ChatMessage(User, content="hello")
  assert_eq("\{user.role}", "user")
  assert_eq(user.content, "hello")
  let assistant = ChatMessage(Assistant, content="done")
  assert_eq("\{assistant.role}", "assistant")
  assert_eq(assistant.content, "done")
  let tool = ChatMessage(Tool("call_123"), content="tool result")
  assert_eq("\{tool.role}", "tool")
  assert_eq(tool.content, "tool result")
}

///|
#deprecated
pub extend ChatMessage with Debug::{to_repr}

///|
#deprecated
pub extend ChatResponse with Debug::{to_repr}

///|
#deprecated
pub extend DsVariant with Debug::{to_repr}

///|
pub extend DsVariant with Eq::{equal, not_equal}

///|
#deprecated
pub extend KimiVariant with Debug::{to_repr}

///|
pub extend KimiVariant with Eq::{equal, not_equal}

///|
#deprecated
pub extend Model with Debug::{to_repr}

///|
pub extend Model with Eq::{equal, not_equal}

///|
pub extend Model with Show::{output, to_string}

///|
#deprecated
pub extend ResponseFormat with Debug::{to_repr}

///|
pub extend ResponseFormat with Eq::{equal, not_equal}

///|
#deprecated
pub extend Role with Debug::{to_repr}

///|
pub extend Role with Eq::{equal, not_equal}

///|
#deprecated
pub extend ThinkingMode with Debug::{to_repr}

///|
pub extend ThinkingMode with Eq::{equal, not_equal}

///|
pub extend ThinkingMode with Show::{output, to_string}

///|
#deprecated
pub extend Usage with Debug::{to_repr}

///|
pub extend Usage with ToJson::{to_json}
