// Page-local UI preferences persisted in the webview's localStorage. Access
// is guarded — a webview profile may deny storage — and a denied store just
// means the defaults come back next launch.
//
// The engine endpoint settings (provider, URLs, API keys) are NOT here: they
// live on the host (`settings.get`/`set`), because relay pages
// for different devices share one browser origin — a secret in
// localStorage would leak across hosts. The legacy readers below exist
// only for the one-time migration (desktop) and purge (browser).

///|
fn load_saved_settings(dispatch : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    // The update channel stopped being its own setting (it derives from the
    // server selection now); drop the obsolete key wherever it lingers.
    remove_setting(UpdateChannelStorageKey)
    scheduler.add(
      dispatch(
        SettingsLoaded(
          notification_corner=load_setting(NotificationCornerStorageKey),
          tree_layout=load_setting(TreeLayoutStorageKey),
          theme=load_setting(ThemeStorageKey),
        ),
      ),
    )
  })
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
/// Persist the Settings selection. An absent key still parses as the initial
/// System state, while an explicit System choice survives subsequent reloads.
fn Theme::save(self : Theme) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => save_setting(ThemeStorageKey, self.wire()))
}

///|
/// Read the legacy client-stored engine settings, dispatched only when any
/// value is actually stored — a page that never held them (or already
/// migrated) dispatches nothing.
fn read_legacy_engine_settings(dispatch : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    let provider = load_setting(LegacyApiProviderStorageKey)
    let custom_url = load_setting(LegacyCustomApiUrlStorageKey)
    let api_key = load_setting(LegacyApiKeyStorageKey)
    let custom_api_key = load_setting(LegacyCustomApiKeyStorageKey)
    if [provider, custom_url, api_key, custom_api_key]
      .iter()
      .any(value => !value.trim().is_empty()) {
      scheduler.add(
        dispatch(
          LegacySettingsRead(provider~, custom_url~, api_key~, custom_api_key~),
        ),
      )
    }
  })
}

///|
/// Delete the legacy client-stored engine settings — after the desktop
/// migrated them up, or on any browser page (where the stored key is the
/// cross-device leak this design removes).
fn clear_legacy_engine_settings() -> @cmd.Cmd {
  @cmd.custom_cmd(_ => {
    for
      key in [
        LegacyApiProviderStorageKey,
        LegacyCustomApiUrlStorageKey,
        LegacyApiKeyStorageKey,
        LegacyCustomApiKeyStorageKey,
      ] {
      remove_setting(key)
    }
  })
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

///|
fn remove_setting(storage_key : String) -> Unit {
  @js.Error_::wrap(
    fn() {
      guard @interop.js_prop(@js.globalThis, "localStorage") is Some(storage) else {
        return @js.Value::cast_from(())
      }
      storage.apply_with_string("removeItem", [
        @js.Value::cast_from(storage_key),
      ])
    },
    map_ok=_ => (),
  ) catch {
    _ => ()
  }
}
