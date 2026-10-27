// The host's engine endpoint settings, over the wire: `settings.get` seeds
// the mirror at bridge time, `settings.set` pushes each edit, and the
// `settings.changed` broadcast keeps every other client's mirror fresh
// (projected in bridge.mbt through the same `HostSettings::from_status`). Key
// material never travels down — only presence flags.

///|
/// Project the shared settings status used by both replies and broadcasts.
fn HostSettings::from_status(
  payload : @protocol.SettingsStatusPayload,
) -> HostSettings {
  {
    revision: payload.revision,
    provider: payload.provider,
    custom_api_url: payload.custom_api_url.unwrap_or(""),
    has_deepseek_key: payload.has_deepseek_key,
    has_glm_key: payload.has_glm_key,
    has_custom_key: payload.has_custom_key,
    followup_behavior: payload.followup_behavior,
    prompt_source: payload.prompt_source,
    custom_prompt: payload.custom_prompt,
  }
}

///|
/// Seed (or refresh) the mirror from the host. Failed reads leave the mirror
/// intact and expose a retry, rather than silently stranding pending drafts.
fn fetch_host_settings(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  connection_generation : Int32,
) -> @cmd.Cmd {
  let dispatch = dispatch.map((msg : DeviceMsg) => FromDevice(channel, msg))
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let reply = @interop.bridge_request(
        channel,
        @commands.settings_get,
        @protocol.EmptyPayload::NoPayload,
      ) catch {
        error => {
          scheduler.add(
            dispatch(
              HostSettingsLoadFailed(
                @interop.bridge_error_text(error),
                connection_generation~,
              ),
            ),
          )
          return
        }
      }
      scheduler.add(
        dispatch(
          HostSettingsLoaded(
            HostSettings::from_status(reply),
            connection_generation=Some(connection_generation),
          ),
        ),
      )
    })
    |> ignore
  })
}

///|
/// Push one settings patch to the host. The reply carries the post-write
/// state (`HostSettingsApplied` reconciles the mirror once no more writes
/// are in flight); a failure surfaces as a toast and leaves the host store
/// unchanged.
fn push_host_settings(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  patch : @protocol.SettingsSetPayload,
  connection_generation : Int32,
) -> @cmd.Cmd {
  let dispatch = dispatch.map((msg : DeviceMsg) => FromDevice(channel, msg))
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let reply = @interop.bridge_request(
        channel, @commands.settings_set, patch,
      ) catch {
        error => {
          scheduler.add(
            dispatch(
              HostSettingsSaveFailed(
                @interop.bridge_error_text(error),
                connection_generation~,
              ),
            ),
          )
          return
        }
      }
      scheduler.add(
        dispatch(
          HostSettingsApplied(
            HostSettings::from_status(reply),
            connection_generation~,
          ),
        ),
      )
    })
    |> ignore
  })
}

///|
fn provider_settings_patch(
  provider : ApiProvider,
  custom_api_url : String,
) -> @protocol.SettingsSetPayload {
  {
    provider: Some(
      if provider is OpenRouter {
        "custom"
      } else {
        provider.wire()
      },
    ),
    custom_api_url: match provider {
      OpenRouter => Some(OpenRouterChatCompletionsUrl)
      Custom if custom_api_url == OpenRouterChatCompletionsUrl => Some("")
      _ => None
    },
    deepseek_api_key: None,
    glm_api_key: None,
    custom_api_key: None,
    followup_behavior: None,
    prompt_source: None,
    custom_prompt: None,
  }
}

///|
/// The URL is sent verbatim (not omitted when blank): a present-but-empty
/// field is the wire's "clear the stored value".
fn custom_url_settings_patch(url : String) -> @protocol.SettingsSetPayload {
  {
    provider: None,
    custom_api_url: Some(url),
    deepseek_api_key: None,
    glm_api_key: None,
    custom_api_key: None,
    followup_behavior: None,
    prompt_source: None,
    custom_prompt: None,
  }
}

///|
fn api_key_settings_patch(
  provider : ApiProvider,
  key : String,
) -> @protocol.SettingsSetPayload {
  {
    provider: Some(
      if provider is OpenRouter {
        "custom"
      } else {
        provider.wire()
      },
    ),
    custom_api_url: if provider is OpenRouter {
      Some(OpenRouterChatCompletionsUrl)
    } else {
      None
    },
    deepseek_api_key: if provider is Deepseek {
      Some(key)
    } else {
      None
    },
    glm_api_key: if provider is Glm {
      Some(key)
    } else {
      None
    },
    custom_api_key: if provider is (OpenRouter | Custom) {
      Some(key)
    } else {
      None
    },
    followup_behavior: None,
    prompt_source: None,
    custom_prompt: None,
  }
}

///|
test "OpenRouter is an atomic custom-backend preset" {
  json_inspect(provider_settings_patch(OpenRouter, "").to_json(), content={
    "provider": "custom",
    "custom_api_url": "https://openrouter.ai/api/v1/chat/completions",
  })
  json_inspect(api_key_settings_patch(OpenRouter, "sk-openrouter").to_json(), content={
    "provider": "custom",
    "custom_api_url": "https://openrouter.ai/api/v1/chat/completions",
    "custom_api_key": "sk-openrouter",
  })
  json_inspect(
    provider_settings_patch(Custom, OpenRouterChatCompletionsUrl).to_json(),
    content={ "provider": "custom", "custom_api_url": "" },
  )
}

///|
fn followup_behavior_patch(
  behavior : FollowupBehavior,
) -> @protocol.SettingsSetPayload {
  {
    provider: None,
    custom_api_url: None,
    deepseek_api_key: None,
    glm_api_key: None,
    custom_api_key: None,
    followup_behavior: Some(behavior.wire()),
    prompt_source: None,
    custom_prompt: None,
  }
}
