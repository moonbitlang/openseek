///|
const ApiConnectionProbeTimeoutMs : Int32 = 15_000

///|
async fn resolve_api_connection_probe(
  manager : EngineManager,
  payload : @protocol.ApiConnectionProbePayload,
) -> @client.Client {
  manager.settings_lock.acquire()
  defer manager.settings_lock.release()
  guard payload.revision == manager.settings_revision else {
    raise EngineError("Settings changed. Try the connection test again.")
  }
  let settings = load_engine_settings(manager.runtime_dir)
  let endpoint = resolved_endpoint(settings)
  let model = @deepseek.Model::parse(settings.provider.default_model())
  Client(
    api_key=endpoint.api_key,
    api_url?=endpoint.api_url,
    model~,
    retry_attempts=1,
  )
}

///|
/// Verify one streamed text reply using the selected provider's saved route.
pub async fn test_api_connection(
  manager : EngineManager,
  payload : @protocol.ApiConnectionProbePayload,
) -> @protocol.ApiConnectionProbeReply {
  let client = resolve_api_connection_probe(manager, payload) catch {
    EngineError(message) => return { error: Some(message), }
    error => raise error
  }
  let response = @async.with_timeout(ApiConnectionProbeTimeoutMs, () => {
    let messages : Array[@deepseek.ChatMessage] = [
      ChatMessage(User, content=[Text("Reply with OK.")]),
    ]
    let stream = @client.StreamHandler(on_content_delta=_ => ())
    client.chat(messages, stream~)
  }) catch {
    @async.TimeoutError =>
      return { error: Some("The connection test timed out."), }
    error if @async.is_being_cancelled() => raise error
    _ =>
      return {
        error: Some(
          "Could not read a streamed reply. Check the endpoint, API key, and model.",
        ),
      }
  }
  {
    error: if response.content.is_blank() {
      Some("The model returned no text.")
    } else {
      None
    },
  }
}
