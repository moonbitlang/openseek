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
  let (model, endpoint) = match payload.model {
    None =>
      (
        @deepseek.Model::parse(settings.provider.default_model()),
        resolved_endpoint(settings),
      )
    Some(id) => {
      // One row tests one saved entry: its own endpoint and key, falling back
      // to the custom slot exactly as a run does.
      guard find_saved_model_entry(settings.models, id) is Some(_) else {
        raise EngineError(
          "Model \{id} is no longer saved. Add it again to test the connection.",
        )
      }
      let (route, _, _, _) = resolve_model_route(settings, id)
      (parse_model_opt(id).unwrap_or(Custom(id)), route)
    }
  }
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

///|
async test "a per-model connection test reads the saved entry and refuses an unknown id" {
  with_settings_dir((_dir, manager) => {
    let _ = update_settings(
      manager,
      {
        provider: Some("custom"),
        providers: Some({
          "custom": {
            api_url: Some("https://gateway.example/v1"),
            api_key: Some("sk-custom"),
          },
        }),
      },
      models=[
        {
          id: "gateway-chat",
          label: None,
          api_url: None,
          full_url: None,
          api_key: None,
          images: Some(true),
          context_window: None,
        },
        {
          id: "own-endpoint",
          label: None,
          api_url: Some("https://own.example/v1"),
          full_url: None,
          api_key: Some("sk-own"),
          images: Some(false),
          context_window: None,
        },
      ],
    )
    let payload : (String?) -> @protocol.ApiConnectionProbePayload = model => {
      revision: manager.settings_revision,
      model,
    }
    // A row tests its own entry, even when the entry names its own endpoint.
    let own = resolve_api_connection_probe(
      manager,
      payload(Some("own-endpoint")),
    )
    assert_eq(own.model, Custom("own-endpoint"))
    assert_eq(own.api_url, "https://own.example/v1/chat/completions")
    // An entry without an endpoint rides the custom slot, as a run would.
    let shared = resolve_api_connection_probe(
      manager,
      payload(Some("gateway-chat")),
    )
    assert_eq(shared.api_url, "https://gateway.example/v1/chat/completions")
    // Without a model the probe keeps testing the provider's own route.
    let provider_default = resolve_api_connection_probe(manager, payload(None))
    assert_eq(
      provider_default.api_url,
      "https://gateway.example/v1/chat/completions",
    )
    // A row whose entry is gone says so instead of testing something else.
    let refusal = try {
      ignore(resolve_api_connection_probe(manager, payload(Some("gone"))))
      ""
    } catch {
      EngineError(message) => message
      _ => "unexpected error"
    }
    assert_eq(
      refusal, "Model gone is no longer saved. Add it again to test the connection.",
    )
  })
}
