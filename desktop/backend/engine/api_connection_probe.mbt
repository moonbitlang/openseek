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
  let model = match payload.model {
    None => @deepseek.Model::parse(settings.provider.default_model())
    Some(id) => {
      guard settings.provider is Custom &&
        find_custom_model(settings.models, id) is Some(_) else {
        raise EngineError(
          "Model \{id} is no longer saved. Add it again to test the connection.",
        )
      }
      @deepseek.Model::parse(id) catch {
        _ =>
          raise EngineError(
            "Model \{id} has no name to test. Add it again to test the connection.",
          )
      }
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
async test "per-model connection probe resolves saved custom models and refuses unknown ids" {
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
          context_window: @protocol.DefaultCustomModelContextWindow,
        },
      ],
    )
    let payload : (String?) -> @protocol.ApiConnectionProbePayload = model => {
      revision: manager.settings_revision,
      model,
    }
    let probed = resolve_api_connection_probe(
      manager,
      payload(Some("gateway-chat")),
    )
    assert_eq(
      probed.model,
      Custom(
        "gateway-chat",
        context_window=@protocol.DefaultCustomModelContextWindow,
      ),
    )
    assert_eq(probed.api_url, "https://gateway.example/v1/chat/completions")
    let provider_default = resolve_api_connection_probe(manager, payload(None))
    assert_eq(
      provider_default.api_url,
      "https://gateway.example/v1/chat/completions",
    )
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
