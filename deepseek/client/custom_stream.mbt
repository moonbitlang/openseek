///|
/// Read one streamed chat completion from an explicit OpenAI-compatible
/// endpoint using the model ID the gateway expects.
pub async fn stream_custom_chat(
  api_url~ : String,
  api_key~ : String,
  model_id~ : String,
  messages : Array[@deepseek.ChatMessage],
  stream~ : StreamHandler,
) -> @deepseek.ChatResponse {
  guard @deepseek.encode_chat_request(messages, stream=true) is Object(fields) else {
    fail("Expected a chat completion request object.")
  }
  fields["model"] = Json(model_id)
  let progress = RequestProgress()
  progress.begin_attempt()
  chat_stream_attempt(
    api_url~,
    api_key~,
    idle_timeout_ms=DefaultChatIdleTimeoutMs,
    Json(fields),
    progress,
    stream,
  )
}
