// The host's engine endpoint settings, over the wire: `settings.get` seeds
// the mirror at bridge time, `settings.set` pushes each edit, and the
// `settings.changed` broadcast keeps every other client's mirror fresh
// (decoded in bridge.mbt through the same `decode_host_settings`). Key
// material never travels down — only presence flags.

///|
/// Decode one status payload (a reply's JSON or a broadcast's params).
/// Absent fields read as their defaults; a payload without `provider` is
/// malformed and dropped.
fn decode_host_settings(payload : Map[String, Json]) -> HostSettings? {
  guard @jsonx.json_text(payload, "provider") is Some(provider) else {
    return None
  }
  let (wsl_enabled, wsl_distro, wsl_engine) = match payload.get("wsl") {
    Some(Object(wsl)) =>
      (
        wsl.get("enabled") is Some(True),
        @jsonx.json_text(wsl, "distro").unwrap_or(""),
        @jsonx.json_text(wsl, "engine").unwrap_or(""),
      )
    _ => (false, "", "")
  }
  Some({
    revision: @jsonx.json_int(payload, "revision").unwrap_or(0),
    provider,
    custom_api_url: @jsonx.json_text(payload, "custom_api_url").unwrap_or(""),
    has_deepseek_key: payload.get("has_deepseek_key") is Some(True),
    has_custom_key: payload.get("has_custom_key") is Some(True),
    wsl_enabled,
    wsl_distro,
    wsl_engine,
  })
}

///|
fn reply_host_settings(reply : @js.Value) -> HostSettings? {
  let json = @json.parse(@interop.reply_json_text(reply)) catch {
    _ => return None
  }
  guard json is Object(fields) else { return None }
  decode_host_settings(fields)
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
        "settings.get",
        @js.Object::new().to_value(),
      ) catch {
        _ => return
      }
      if reply_host_settings(reply) is Some(settings) {
        scheduler.add(
          dispatch(
            HostSettingsLoaded(
              settings,
              connection_generation=Some(connection_generation),
            ),
          ),
        )
      }
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
  patch : @js.Value,
  connection_generation : Int,
  cleans_legacy? : Bool = false,
) -> @cmd.Cmd {
  let dispatch = dispatch.map((msg : DeviceMsg) => FromDevice(channel, msg))
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply = @interop.bridge_request(channel, "settings.set", patch) catch {
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
      match reply_host_settings(reply) {
        Some(settings) =>
          scheduler.add(
            dispatch(
              HostSettingsApplied(
                settings,
                connection_generation~,
                cleans_legacy~,
              ),
            ),
          )
        None =>
          scheduler.add(
            dispatch(
              HostSettingsSaveFailed(
                "malformed settings reply",
                connection_generation~,
                cleans_legacy~,
              ),
            ),
          )
      }
    })
  })
}

///|
fn provider_settings_patch(provider : ApiProvider) -> @js.Value {
  let patch = @js.Object::new()
  patch["provider"] = provider.wire()
  patch.to_value()
}

///|
/// The URL is sent verbatim (not omitted when blank): a present-but-empty
/// field is the wire's "clear the stored value".
fn custom_url_settings_patch(url : String) -> @js.Value {
  let patch = @js.Object::new()
  patch["custom_api_url"] = url
  patch.to_value()
}

///|
fn api_key_settings_patch(provider : ApiProvider, key : String) -> @js.Value {
  let patch = @js.Object::new()
  match provider {
    Deepseek => patch["deepseek_api_key"] = key
    Custom => patch["custom_api_key"] = key
    // The proxy takes no user key; callers never build this patch for it.
    Openseek | OpenseekStaging => ()
  }
  patch.to_value()
}

///|
/// A present `wsl` replaces the whole group, so every edit sends the
/// model's full current view of it.
fn wsl_settings_patch(
  enabled~ : Bool,
  distro~ : String,
  engine~ : String,
) -> @js.Value {
  let wsl = @js.Object::new()
  wsl["enabled"] = enabled
  wsl["distro"] = distro
  wsl["engine"] = engine
  let patch = @js.Object::new()
  patch["wsl"] = wsl.to_value()
  patch.to_value()
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
  wsl_enabled~ : String,
  wsl_distro~ : String,
  wsl_engine~ : String,
) -> @js.Value {
  let patch = @js.Object::new()
  // The host persists a one-shot fence with the first settings write.
  // Retrying this import after a lost reply therefore acknowledges and
  // clears localStorage without overwriting a newer host configuration.
  patch["legacy_migration"] = true
  @interop.set_trimmed(patch, "provider", provider)
  @interop.set_trimmed(patch, "custom_api_url", custom_url)
  @interop.set_trimmed(patch, "deepseek_api_key", api_key)
  @interop.set_trimmed(patch, "custom_api_key", custom_api_key)
  if wsl_enabled == "1" ||
    !wsl_distro.trim().is_empty() ||
    !wsl_engine.trim().is_empty() {
    let wsl = @js.Object::new()
    wsl["enabled"] = wsl_enabled == "1"
    @interop.set_trimmed(wsl, "distro", wsl_distro)
    @interop.set_trimmed(wsl, "engine", wsl_engine)
    patch["wsl"] = wsl.to_value()
  }
  patch.to_value()
}

///|
test "legacy migration preserves disabled WSL preferences" {
  let patch = legacy_settings_patch(
    provider="",
    custom_url="",
    api_key="",
    custom_api_key="",
    wsl_enabled="",
    wsl_distro=" Ubuntu ",
    wsl_engine=" /opt/openseek ",
  ).to_json()
  json_inspect(patch, content={
    "legacy_migration": true,
    "wsl": { "enabled": false, "distro": "Ubuntu", "engine": "/opt/openseek" },
  })
}
