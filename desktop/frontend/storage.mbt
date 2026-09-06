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
    // server selection now), and each workspace's launch-mode default lives
    // in its own `.openseek/settings.json`; drop both obsolete keys
    // wherever they linger.
    remove_setting(UpdateChannelStorageKey)
    remove_setting(WorkspaceDefaultModeStorageKey)
    scheduler.add(
      dispatch(
        SettingsLoaded(
          notification_corner=load_setting(NotificationCornerStorageKey),
          tree_layout=load_setting(TreeLayoutStorageKey),
          theme=load_setting(ThemeStorageKey),
          font=load_setting(AppFontStorageKey),
          font_size=load_setting(AppFontSizeStorageKey),
          fps_overlay_enabled=load_setting(FpsOverlayStorageKey) == "true",
          model=load_setting(ModelStorageKey),
          conversation_models=load_setting(ConversationModelsStorageKey),
          agent=load_setting(AgentStorageKey),
          codex_model=load_setting(CodexModelStorageKey),
          codex_effort=load_setting(CodexReasoningEffortStorageKey),
          openseek_effort=load_setting(OpenSeekReasoningStorageKey),
          glm_effort=load_setting(GlmReasoningStorageKey),
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
fn save_fps_overlay(enabled : Bool) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => save_setting(FpsOverlayStorageKey, enabled.to_string()))
}

///|
/// Persist the tier new conversations start from.
fn save_default_model(model : EngineModel) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => save_setting(ModelStorageKey, model.wire()))
}

///|
/// Persist the agent new conversations start with.
fn save_default_agent(agent : AgentChoice) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => save_setting(AgentStorageKey, agent.wire()))
}

///|
/// Persist the Codex model the next thread or turn starts with.
fn save_codex_model(id : String) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => save_setting(CodexModelStorageKey, id))
}

///|
/// Persist the catalog-validated Codex effort used for the next ordinary turn.
fn save_codex_reasoning_effort(effort : String) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => save_setting(CodexReasoningEffortStorageKey, effort))
}

///|
/// Persist OpenSeek's typed reasoning choice for its next engine operation.
fn OpenSeekReasoning::save(self : OpenSeekReasoning) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => save_setting(OpenSeekReasoningStorageKey, self.wire()))
}

///|
/// Persist GLM's reasoning choice independently from DeepSeek's. In
/// particular, a stored DeepSeek Max must not turn a fresh GLM chat into a
/// long forced-thinking run.
fn OpenSeekReasoning::save_for_glm(self : OpenSeekReasoning) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => save_setting(GlmReasoningStorageKey, self.wire()))
}

///|
/// Pin one conversation's tier, merging into the rows already stored rather
/// than writing this page's whole list over them. Relay console pages share
/// one browser origin, so a second tab holds a copy loaded at its own
/// startup; dumping that stale copy would delete whatever the other tab has
/// since chosen for unrelated conversations — a scalar preference next to
/// this one only races over its own value, but a collection loses rows.
///
/// This preserves those rows; it does not make tabs live-consistent. A tab
/// still learns another's choices only when it reloads, which is the same
/// staleness every other preference here already has.
///
/// The list is written as an array, not an object: newest first is the cap's
/// eviction order, which an object's key order would not promise.
fn save_conversation_model(key : String, model : EngineModel) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => {
    let stored = parse_conversation_models(
      load_setting(ConversationModelsStorageKey),
    )
    let rows : Array[Json] = remembered_with(stored, key, model).map(entry => {
      "key": entry.key.to_json(),
      "model": entry.model.wire().to_json(),
    })
    save_setting(ConversationModelsStorageKey, rows.to_json().stringify())
  })
}

///|
/// Read them back. Storage is an input boundary shared with older and newer
/// builds: a store that will not parse degrades to remembering nothing, and a
/// single malformed row is skipped rather than discarding the rest.
fn parse_conversation_models(text : String) -> Array[StoredConversationModel] {
  let entries : Array[StoredConversationModel] = []
  guard !text.is_blank() else { return entries }
  let json = @json.parse(text) catch { _ => return entries }
  guard json is Array(rows) else { return entries }
  for row in rows {
    guard entries.length() < ConversationModelsLimit else { break }
    if row is Object(fields) &&
      fields.get("key") is Some(String(key)) &&
      !key.is_empty() &&
      fields.get("model") is Some(String(wire)) &&
      EngineModel::parse(wire) is Some(model) {
      entries.push({ key, model, })
    }
  }
  entries
}

///|
/// Persist the Settings selection. An absent key still parses as the initial
/// System state, while an explicit System choice survives subsequent reloads.
fn Theme::save(self : Theme) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => save_setting(ThemeStorageKey, self.wire()))
}

///|
/// Persist the monospace family used by code, the editor, and the terminal.
fn AppFont::save(self : AppFont) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => save_setting(AppFontStorageKey, self.wire()))
}

///|
/// Persist the type scale used by every app-owned text surface.
fn AppFontSize::save(self : AppFontSize) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => save_setting(AppFontSizeStorageKey, self.wire()))
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
      .any(value => !value.is_blank()) {
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
/// One guarded `localStorage` mutation. A profile that denies storage, and a
/// call that throws, are both silently no-ops — the defaults come back on the
/// next launch.
fn storage_write(call : String, args : Array[@js.Value]) -> Unit {
  @js.Error_::wrap(
    fn() {
      guard @interop.js_prop(@js.globalThis, "localStorage") is Some(storage) else {
        return @js.Value::cast_from(())
      }
      storage.apply_with_string(call, args)
    },
    map_ok=_ => (),
  ) catch {
    _ => ()
  }
}

///|
fn save_setting(storage_key : String, value : String) -> Unit {
  storage_write("setItem", [
    @js.Value::cast_from(storage_key),
    @js.Value::cast_from(value),
  ])
}

///|
fn remove_setting(storage_key : String) -> Unit {
  storage_write("removeItem", [@js.Value::cast_from(storage_key)])
}
