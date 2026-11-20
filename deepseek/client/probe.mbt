///|
/// Send one short request through the streaming transport. Custom gateways
/// can supply a wire ID independently of the built-in model catalog.
pub async fn Client::probe_streaming_text(
  self : Client,
  custom_model_id? : String,
) -> Bool {
  let messages : Array[@deepseek.ChatMessage] = [
    ChatMessage(User, content=[Text("Reply with OK.")]),
  ]
  let body : Json = match custom_model_id {
    Some(id) => {
      guard @deepseek.encode_chat_request(messages, stream=true)
        is Object(fields) else {
        fail("Expected a chat completion request object.")
      }
      fields["model"] = Json(id)
      Json(fields)
    }
    None =>
      encode_chat_request_for_endpoint(
        api_url=self.api_url,
        model=self.model,
        tools=[],
        thinking=self.thinking,
        stream=true,
        messages,
      )
  }
  let response = self.chat_stream_attempt(
    body,
    RequestProgress(),
    StreamHandler(on_content_delta=_ => ()),
  )
  !response.content.is_blank()
}
