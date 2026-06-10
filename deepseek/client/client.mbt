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

///|
/// Sends typed chat messages in DeepSeek SSE streaming mode.
///
/// `on_content_delta` is called for each assistant content fragment as it
/// arrives; `on_reasoning_delta` likewise for each thinking-mode reasoning
/// fragment (it is simply not called when thinking is off). The returned value
/// is the fully accumulated response, including reasoning, tool calls, and
/// final token usage when the API sends it.
pub async fn Client::chat_stream(
  self : Client,
  messages : Array[@deepseek.ChatMessage],
  on_content_delta~ : async (String) -> Unit,
  on_reasoning_delta? : async (String) -> Unit = _ => (),
  tools? : Array[@deepseek.ToolDefinition] = [],
  response_format? : @deepseek.ResponseFormat,
) -> @deepseek.ChatResponse {
  let body = @deepseek.encode_chat_request(
    self.model,
    messages,
    tools~,
    thinking?=self.thinking,
    reasoning_effort?=self.reasoning_effort,
    stream=true,
    response_format?,
  )
  let client = @http.post_stream(self.api_url, headers={
    "Content-Type": "application/json",
    "Authorization": "Bearer \{self.api_key}",
    // Without an explicit Accept-Encoding the HTTP client advertises gzip and
    // transparently decompresses. A gzip-compressing intermediary buffers
    // whole compression blocks, which would re-batch the SSE deltas this
    // request exists to stream — so pin the identity encoding.
    "Accept-Encoding": "identity",
  })
  defer client.close()
  client.write(body.stringify())
  let resp = client.end_request()
  guard resp.code >= 200 && resp.code < 300 else {
    let text = client.read_all().text()
    fail("DeepSeek API error \{resp.code}: \{text}")
  }
  read_chat_stream(client, on_content_delta~, on_reasoning_delta~)
}
