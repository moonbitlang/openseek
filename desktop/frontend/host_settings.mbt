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
  }
}

///|
/// Seed (or refresh) the mirror from the host. A failed or malformed reply
/// leaves the current mirror in place — the broadcast channel will correct
/// it on the next change.
fn fetch_host_settings(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  connection_generation : Int,
) -> @cmd.Cmd {
  let dispatch = dispatch.map((msg : DeviceMsg) => FromDevice(channel, msg))
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply = @interop.bridge_request(
        channel,
        @commands.settings_get,
        @protocol.EmptyPayload::NoPayload,
      ) catch {
        _ => return
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
  connection_generation : Int,
) -> @cmd.Cmd {
  let dispatch = dispatch.map((msg : DeviceMsg) => FromDevice(channel, msg))
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
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
  })
}

///|
fn provider_settings_patch(
  provider : ApiProvider,
) -> @protocol.SettingsSetPayload {
  {
    provider: Some(provider.wire()),
    custom_api_url: None,
    deepseek_api_key: None,
    glm_api_key: None,
    custom_api_key: None,
    followup_behavior: None,
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
  }
}

///|
fn api_key_settings_patch(
  provider : ApiProvider,
  key : String,
) -> @protocol.SettingsSetPayload {
  {
    provider: None,
    custom_api_url: None,
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
    custom_api_key: if provider is Custom {
      Some(key)
    } else {
      None
    },
    followup_behavior: None,
  }
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
  }
}
