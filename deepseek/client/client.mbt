///|
let default_api_url : String = "https://api.deepseek.com/chat/completions"

///|
let default_model : @deepseek.Model = V4Pro

///|
type API_KEY = String

///|
/// HTTP client for the DeepSeek chat completions API.
pub struct Client {
  priv api_key : API_KEY
  model : @deepseek.Model
  api_url : String
  thinking : @deepseek.ThinkingMode?
  reasoning_effort : @deepseek.ReasoningEffort?
} derive(Debug(ignore=API_KEY))

///|
/// Constructs a DeepSeek HTTP client.
///
/// `model` defaults to `deepseek-v4-pro`; `api_url` defaults to the DeepSeek
/// chat completions endpoint. Pass `thinking` and `reasoning_effort` to control
/// DeepSeek V4 thinking mode explicitly.
pub fn Client::Client(
  api_key~ : String,
  model? : @deepseek.Model = default_model,
  api_url? : String = default_api_url,
  thinking? : @deepseek.ThinkingMode? = None,
  reasoning_effort? : @deepseek.ReasoningEffort? = None,
) -> Client {
  { api_key, model, api_url, thinking, reasoning_effort }
}

///|
/// Sends typed chat messages to DeepSeek and decodes the response.
///
/// Pass `tools` to enable native DeepSeek function tool calls. Pass
/// `response_format=JsonObject` only when the assistant content itself should
/// be constrained to a JSON object.
pub async fn Client::chat(
  self : Client,
  messages : Array[@deepseek.ChatMessage],
  tools? : Array[@deepseek.ToolDefinition] = [],
  response_format? : @deepseek.ResponseFormat,
) -> @deepseek.ChatResponse {
  let body = @deepseek.encode_chat_request(
    self.model,
    messages,
    tools~,
    thinking?=self.thinking,
    reasoning_effort?=self.reasoning_effort,
    response_format?,
  )
  let (resp, data) = @http.post(self.api_url, body, headers={
    "Content-Type": "application/json",
    "Authorization": "Bearer \{self.api_key}",
  })
  let text = data.text()
  guard resp.code >= 200 && resp.code < 300 else {
    fail("DeepSeek API error \{resp.code}: \{text}")
  }
  let parsed = @json.parse(text)
  @json.from_json(parsed)
}
