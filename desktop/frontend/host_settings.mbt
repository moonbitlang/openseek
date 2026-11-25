// The host's engine endpoint settings, over the wire: `settings.get` seeds
// the mirror at bridge time, `settings.set` pushes each edit, and the
// `settings.changed` broadcast keeps every other client's mirror fresh
// (projected in bridge.mbt through the same `HostSettings::from_status`). Key
// material never travels down — only presence flags.

///|
/// Project the shared settings status used by both replies and broadcasts.
/// Each provider owns its credentials independently of the active selection.
fn HostSettings::from_status(
  payload : @protocol.SettingsStatusPayload,
) -> HostSettings {
  let provider = ApiProvider::parse(payload.provider)
  let mut providers = @sorted_map.SortedMap([])
  for provider in [Deepseek, Glm, OpenRouter, Custom] {
    if payload.providers.get(provider.wire()) is Some(config) {
      providers = providers.add(provider, ProviderConfig::{
        api_url: config.api_url,
        has_api_key: config.has_api_key,
      })
    }
  }
  {
    revision: payload.revision,
    endpoint: {
      provider,
      providers,
      followup_behavior: FollowupBehavior::parse(payload.followup_behavior),
    },
    models: payload.models,
    prompt_source: payload.prompt_source,
    custom_prompt: payload.custom_prompt,
  }
}

///|
/// The complete base prompt this host's committed default gives a new chat
/// on `model`.
fn HostSettings::prompt_text(
  self : HostSettings,
  model : @deepseek.Model,
) -> String {
  @prompt.Model::new()
  .receive(self.prompt_source, self.custom_prompt)
  .text(model)
}

///|
fn HostEndpoint::config(
  self : HostEndpoint,
  provider : ApiProvider,
) -> ProviderConfig {
  self.providers.get(provider).unwrap_or({ api_url: None, has_api_key: false, })
}

///|
fn HostEndpoint::key_saved(self : HostEndpoint) -> Bool {
  self.config(self.provider).has_api_key
}

///|
/// A connection's mirror before its first authoritative status.
fn HostSettingsMirror::loading() -> HostSettingsMirror {
  { current: None, saves: 0, deferred: None, error: None, }
}

///|
/// Whether `settings` is at least as new as the accepted status. Equal is
/// deliberately accepted so a failed optimistic edit can be restored by an
/// authoritative `get`.
fn HostSettingsMirror::accepts(
  self : HostSettingsMirror,
  settings : HostSettings,
) -> Bool {
  !(self.current is Some(current) && settings.revision < current.revision)
}

///|
fn HostSettingsMirror::apply(
  self : HostSettingsMirror,
  settings : HostSettings,
) -> HostSettingsMirror {
  { ..self, current: Some(settings), deferred: None, error: None, }
}

///|
/// Retain the highest revision observed while optimistic writes are
/// outstanding. It is applied only when the last write settles, preventing
/// both stale rollback and mid-edit UI clobbering.
fn HostSettingsMirror::hold(
  self : HostSettingsMirror,
  settings : HostSettings,
) -> HostSettingsMirror {
  guard self.accepts(settings) else { return self }
  let deferred = match self.deferred {
    Some(current) if current.revision > settings.revision => current
    _ => settings
  }
  { ..self, deferred: Some(deferred), }
}

///|
/// One optimistic write: the edited endpoint shows at once and the write is
/// counted until its reply settles. Nothing changes before the first
/// snapshot.
fn HostSettingsMirror::edit(
  self : HostSettingsMirror,
  endpoint : HostEndpoint,
) -> HostSettingsMirror {
  guard self.current is Some(current) else { return self }
  { ..self.write_sent(), current: Some({ ..current, endpoint, }), }
}

///|
/// One write went out; its reply settles it.
fn HostSettingsMirror::write_sent(
  self : HostSettingsMirror,
) -> HostSettingsMirror {
  { ..self, saves: self.saves + 1, }
}

///|
/// One write's reply arrived, successful or not.
fn HostSettingsMirror::write_settled(
  self : HostSettingsMirror,
) -> HostSettingsMirror {
  { ..self, saves: if self.saves > 0 { self.saves - 1 } else { 0 }, }
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
) -> @protocol.SettingsSetPayload {
  {
    provider: Some(provider.wire()),
    providers: None,
    followup_behavior: None,
    prompt_source: None,
    custom_prompt: None,
    models: None,
  }
}

///|
/// The URL is sent verbatim (not omitted when blank): a present-but-empty
/// field is the wire's "clear the stored value".
fn custom_url_settings_patch(url : String) -> @protocol.SettingsSetPayload {
  {
    provider: None,
    providers: Some({ "custom": { api_url: Some(url), api_key: None, } }),
    followup_behavior: None,
    prompt_source: None,
    custom_prompt: None,
    models: None,
  }
}

///|
fn api_key_settings_patch(
  provider : ApiProvider,
  key : String,
) -> @protocol.SettingsSetPayload {
  {
    provider: None,
    providers: Some(
      Map([(provider.wire(), { api_url: None, api_key: Some(key), })]),
    ),
    followup_behavior: None,
    prompt_source: None,
    custom_prompt: None,
    models: None,
  }
}

///|
test "OpenRouter has independent settings" {
  json_inspect(provider_settings_patch(OpenRouter).to_json(), content={
    "provider": "openrouter",
  })
  json_inspect(api_key_settings_patch(OpenRouter, "sk-openrouter").to_json(), content={
    "providers": { "openrouter": { "api_key": "sk-openrouter" } },
  })
  json_inspect(provider_settings_patch(Custom).to_json(), content={
    "provider": "custom",
  })
}

///|
fn followup_behavior_patch(
  behavior : FollowupBehavior,
) -> @protocol.SettingsSetPayload {
  {
    provider: None,
    providers: None,
    followup_behavior: Some(behavior.wire()),
    prompt_source: None,
    custom_prompt: None,
    models: None,
  }
}
