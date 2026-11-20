///|
const ApiConnectionProbeTimeoutMs : Int32 = 15_000

///|
async fn resolve_api_connection_probe(
  manager : EngineManager,
  payload : @protocol.ApiConnectionProbePayload,
) -> (@client.Client, String?) {
  manager.settings_lock.acquire()
  defer manager.settings_lock.release()
  guard payload.revision == manager.settings_revision else {
    raise EngineError("Settings changed. Try the connection test again.")
  }
  let settings = load_engine_settings(manager.runtime_dir)
  let endpoint = resolved_endpoint(settings)
  let custom_model_id = match (settings.provider, payload.custom_model_id) {
    (Custom, Some(id)) if !id.is_blank() => Some(id.trim().to_owned())
    (Custom, _) =>
      raise EngineError("Enter a model ID for the connection test.")
    (_, None) => None
    (_, Some(_)) =>
      raise EngineError("Only Custom URL uses a model ID for the test.")
  }
  let model = @deepseek.Model::parse(settings.provider.default_model())
  (
    Client(api_key=endpoint.api_key, api_url?=endpoint.api_url, model~),
    custom_model_id,
  )
}

///|
/// Verify one streamed text reply using the selected provider's saved route.
pub async fn test_api_connection(
  manager : EngineManager,
  payload : @protocol.ApiConnectionProbePayload,
) -> @protocol.ApiConnectionProbeReply {
  let (client, custom_model_id) = resolve_api_connection_probe(manager, payload) catch {
    EngineError(message) => return { error: Some(message), }
    error => raise error
  }
  let received = @async.with_timeout(ApiConnectionProbeTimeoutMs, () => {
    client.probe_streaming_text(custom_model_id?)
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
  { error: if received { None } else { Some("The model returned no text.") }, }
}
