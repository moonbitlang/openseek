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
  cleans_legacy? : Bool = false,
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
                cleans_legacy~,
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
            cleans_legacy~,
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
    legacy_migration: None,
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
    legacy_migration: None,
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
    legacy_migration: None,
    followup_behavior: None,
  }
}

///|
/// The migration patch: every legacy value the page still held, in one
/// write. Blank legacy fields are omitted (nothing stored) rather than
/// sent as clears — the host may already hold newer values.
fn legacy_settings_patch(
  provider~ : String,
  custom_url~ : String,
  api_key~ : String,
  custom_api_key~ : String,
) -> @protocol.SettingsSetPayload {
  // The host persists a one-shot fence with the first settings write.
  // Retrying this import after a lost reply therefore acknowledges and
  // clears localStorage without overwriting a newer host configuration.
  fn carried(value : String) -> String? {
    let value = value.trim().to_owned()
    if value.is_empty() {
      None
    } else {
      Some(value)
    }
  }

  {
    provider: carried(provider),
    custom_api_url: carried(custom_url),
    deepseek_api_key: carried(api_key),
    // No legacy page ever stored a GLM key; the import has nothing to carry.
    glm_api_key: None,
    custom_api_key: carried(custom_api_key),
    legacy_migration: Some(true),
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
    legacy_migration: None,
    followup_behavior: Some(behavior.wire()),
  }
}

///|
test "legacy migration trims the values it preserves" {
  let patch = legacy_settings_patch(
    provider=" deepseek ",
    custom_url=" https://example.invalid/chat ",
    api_key=" sk-legacy ",
    custom_api_key="",
  ).to_json()
  json_inspect(patch, content={
    "legacy_migration": true,
    "provider": "deepseek",
    "custom_api_url": "https://example.invalid/chat",
    "deepseek_api_key": "sk-legacy",
  })
}
