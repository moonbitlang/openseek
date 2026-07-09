// API settings persisted in the webview's localStorage. Access is guarded —
// a webview profile may deny storage — and a denied store just means the
// defaults come back next launch.

///|
fn load_saved_settings(dispatch : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    scheduler.add(
      dispatch(
        SettingsLoaded(
          provider=load_setting(ApiProviderStorageKey),
          custom_url=load_setting(CustomApiUrlStorageKey),
          api_key=load_setting(ApiKeyStorageKey),
          custom_api_key=load_setting(CustomApiKeyStorageKey),
          wsl_enabled=load_setting(WslEnabledStorageKey),
          wsl_distro=load_setting(WslDistroStorageKey),
          wsl_engine=load_setting(WslEngineStorageKey),
          notification_corner=load_setting(NotificationCornerStorageKey),
          tree_layout=load_setting(TreeLayoutStorageKey),
          update_channel=load_setting(UpdateChannelStorageKey),
        ),
      ),
    )
  })
}

///|
fn save_api_key(api_key : String) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => save_setting(ApiKeyStorageKey, api_key))
}

///|
fn save_custom_api_key(api_key : String) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => save_setting(CustomApiKeyStorageKey, api_key))
}

///|
fn save_api_provider(provider : ApiProvider) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => save_setting(ApiProviderStorageKey, provider.wire()))
}

///|
fn save_custom_api_url(url : String) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => save_setting(CustomApiUrlStorageKey, url))
}

///|
fn save_wsl_enabled(enabled : Bool) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => {
    save_setting(WslEnabledStorageKey, if enabled { "1" } else { "" })
  })
}

///|
fn save_wsl_distro(distro : String) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => save_setting(WslDistroStorageKey, distro))
}

///|
fn save_wsl_engine(engine : String) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => save_setting(WslEngineStorageKey, engine))
}

///|
fn save_notification_corner(corner : NotificationCorner) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => save_setting(NotificationCornerStorageKey, corner.wire()))
}

///|
fn save_tree_layout(layout : @fileeditor.TreeLayout) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => save_setting(TreeLayoutStorageKey, layout.wire()))
}

///|
fn save_update_channel(channel : UpdateChannel) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => save_setting(UpdateChannelStorageKey, channel.wire()))
}

///|
fn load_setting(storage_key : String) -> String {
  @js.Error_::wrap(
    fn() {
      guard @interop.js_prop(@js.globalThis, "localStorage") is Some(storage) else {
        return @js.Value::cast_from("")
      }
      storage.apply_with_string("getItem", [@js.Value::cast_from(storage_key)])
    },
    // getItem returns null for a key that was never stored.
    map_ok=value => if value.is_null() { "" } else { value.cast() },
  ) catch {
    _ => ""
  }
}

///|
fn save_setting(storage_key : String, value : String) -> Unit {
  @js.Error_::wrap(
    fn() {
      guard @interop.js_prop(@js.globalThis, "localStorage") is Some(storage) else {
        return @js.Value::cast_from(())
      }
      storage.apply_with_string("setItem", [
        @js.Value::cast_from(storage_key),
        @js.Value::cast_from(value),
      ])
    },
    map_ok=_ => (),
  ) catch {
    _ => ()
  }
}
