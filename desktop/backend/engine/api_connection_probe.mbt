///|
const ApiConnectionProbeTimeoutMs : Int32 = 15_000

///|
priv enum ApiConnectionProbeRoute {
  BuiltinProbe(@client.Client)
  CustomProbe(api_url~ : String, api_key~ : String, model_id~ : String)
}

///|
async fn resolve_api_connection_probe(
  manager : EngineManager,
  payload : @protocol.ApiConnectionProbePayload,
) -> ApiConnectionProbeRoute {
  manager.settings_lock.acquire()
  defer manager.settings_lock.release()
  guard payload.revision == manager.settings_revision else {
    raise EngineError("Settings changed. Try the connection test again.")
  }
  let settings = load_engine_settings(manager.runtime_dir)
  let endpoint = resolved_endpoint(settings)
  match (settings.provider, payload.custom_model_id) {
    (Custom, Some(id)) if !id.is_blank() => {
      guard endpoint.api_url is Some(api_url) else {
        raise EngineError("Save the custom endpoint URL first.")
      }
      CustomProbe(
        api_url~,
        api_key=endpoint.api_key,
        model_id=id.trim().to_owned(),
      )
    }
    (Custom, _) =>
      raise EngineError("Enter a model ID for the connection test.")
    (provider, None) => {
      let model = @deepseek.Model::parse(provider.default_model())
      BuiltinProbe(
        Client(
          api_key=endpoint.api_key,
          api_url?=endpoint.api_url,
          model~,
          retry_attempts=1,
        ),
      )
    }
    (_, Some(_)) =>
      raise EngineError("Only Custom URL uses a model ID for the test.")
  }
}

///|
/// Verify one streamed text reply using the selected provider's saved route.
pub async fn test_api_connection(
  manager : EngineManager,
  payload : @protocol.ApiConnectionProbePayload,
) -> @protocol.ApiConnectionProbeReply {
  let route = resolve_api_connection_probe(manager, payload) catch {
    EngineError(message) => return { error: Some(message), }
    error => raise error
  }
  let response = @async.with_timeout(ApiConnectionProbeTimeoutMs, () => {
    let messages : Array[@deepseek.ChatMessage] = [
      ChatMessage(User, content=[Text("Reply with OK.")]),
    ]
    let stream = @client.StreamHandler(on_content_delta=_ => ())
    match route {
      BuiltinProbe(client) => client.chat(messages, stream~)
      CustomProbe(api_url~, api_key~, model_id~) =>
        @client.stream_custom_chat(
          api_url~,
          api_key~,
          model_id~,
          messages,
          stream~,
        )
    }
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
