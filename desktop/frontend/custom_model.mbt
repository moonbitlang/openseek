// The custom endpoint's models, listed and edited inline in the API section.
//
// The endpoint URL and its API key belong to the section itself, so an entry
// holds only what is specific to the model: its id and the name the menu
// shows. Nothing is shown twice — the run resolves an entry's endpoint from
// the custom provider above it.
//
// Several entries share the one endpoint. Saving upserts the entry the editor
// holds and leaves every other entry alone, so editing one model never
// strands a conversation that uses another.
//
// Every custom entry accepts image input. There is nothing to choose, so the
// form offers no switch and always records `images: true`.

///|
/// The context window a new entry starts from, and the range the form accepts.
/// The host stores and enforces the same numbers; the form states them here so
/// a field is checked before it is sent.
const DefaultContextWindow : Int32 = 1_000_000

///|
const MinContextWindow : Int32 = 1_024

///|
const MaxContextWindow : Int32 = 10_000_000

///|
/// Maximum length of a model display name, matching the host check.
const MaxModelLabelChars : Int32 = 64

///|
/// The entry the editor holds: a new one when `original` is `None`, or the
/// stored entry named by `original` when it edits an existing one.
#derive(Eq)
priv struct CustomModelDraft {
  // The id of the entry being edited; `None` while adding a new one.
  original : String?
  id : String
  label : String
  // The window the entry names, as typed. No table here can know an arbitrary
  // endpoint's, so the user states it and the run plans against it.
  window : String
}

///|
fn CustomModelDraft::empty() -> CustomModelDraft {
  { original: None, id: "", label: "", window: "", }
}

///|
/// The stored entry as the editor shows it. The key never comes back down, so
/// the key field belongs to the API section, not to this draft.
fn CustomModelDraft::of(entry : CustomModel) -> CustomModelDraft {
  {
    original: Some(entry.id),
    id: entry.id,
    label: entry.label.unwrap_or(""),
    window: entry.context_window.to_string(),
  }
}

///|
/// The window the field names, or `None` when it names no value of its own:
/// blank, which means the default, or a number the host would not store.
/// Grouping commas (such as `1,000,000` from the hint) are accepted.
fn CustomModelDraft::window_value(self : CustomModelDraft) -> Int32? {
  let text = self.window.trim().to_owned().replace_all(old=",", new="")
  if text.is_empty() {
    return None
  }
  let value : Int32 = @string.from_str(text) catch { _ => return None }
  if value >= MinContextWindow && value <= MaxContextWindow {
    Some(value)
  } else {
    None
  }
}

///|
/// Whether the field holds something the host will store: blank, which means
/// the default, or a number in range. A field the user filled in with anything
/// else blocks Save, so the host never has to refuse it.
fn CustomModelDraft::window_ok(self : CustomModelDraft) -> Bool {
  self.window.trim().is_empty() || self.window_value() is Some(_)
}

///|
/// Whether the display name fits within the host's limit.
fn CustomModelDraft::label_ok(self : CustomModelDraft) -> Bool {
  self.label.trim().length() <= MaxModelLabelChars
}

///|
/// Why the typed model id cannot be saved against `existing`, or `None` when
/// it is valid. Built-in names are allowed so a custom endpoint can expose a
/// shipped tier explicitly; renaming onto an already saved id cannot silently
/// overwrite the other entry.
fn CustomModelDraft::id_error(
  self : CustomModelDraft,
  existing : Array[CustomModel],
) -> @settings.Message? {
  let id = self.id.trim().to_owned()
  if id.is_empty() {
    return None
  }
  let parsed = parse_engine_model(id)
  if existing.any(entry => {
      self.original != Some(entry.id) &&
      (entry.id == id || (parsed is Some(model) && entry.matches_model(model)))
    }) {
    return Some(ModelIdDuplicate)
  }
  None
}

///|
/// Whether the Save button may be pressed: a model needs a non-colliding name,
/// a display name within the limit, and a window that is either blank or a
/// number the host will store.
fn CustomModelDraft::can_submit(
  self : CustomModelDraft,
  existing : Array[CustomModel],
) -> Bool {
  !self.id.trim().is_empty() &&
  self.id_error(existing) is None &&
  self.label_ok() &&
  self.window_ok()
}

///|
/// The settings patch that writes this draft. The endpoint and its key are
/// cleared rather than repeated: the run falls back to the custom provider's
/// endpoint, which is the single place the section shows them.
fn CustomModelDraft::patch(self : CustomModelDraft) -> @protocol.ModelPatch {
  {
    id: self.id.trim().to_owned(),
    label: Some(self.label.trim().to_owned()),
    api_url: None,
    full_url: None,
    api_key: None,
    // A custom entry always accepts images; the form offers no switch.
    images: Some(true),
    // The window the user stated, or the default when the field is blank. The
    // stored entry always names a number, so a run never has to guess.
    context_window: Some(self.window_value().unwrap_or(DefaultContextWindow)),
  }
}

///|
/// The custom entries the host reports, in stored order.
fn Model::custom_models(self : Model) -> Array[CustomModel] {
  self.host_settings().map(settings => settings.models).unwrap_or([])
}

///|
/// The stored entry named `id`, when the host still reports it.
fn Model::custom_model_entry(self : Model, id : String) -> CustomModel? {
  let entries = self.custom_models()
  entries.search_by(entry => entry.id == id).map(index => entries[index])
}

///|
/// How many of this host's sessions — live or archived — recorded `id` as the
/// model they last ran on. A delete confirmation uses it to say who deleting
/// the entry would strand.
fn Model::custom_model_session_count(self : Model, id : String) -> Int32 {
  guard self.device_state(self.focused) is Some(dev) else { return 0 }
  let parsed_entry = parse_engine_model(id)
  let mut count : Int32 = 0
  for item in [..dev.sessions, ..dev.archived] {
    guard item.model_settings is Some({ model, .. }) else { continue }
    let matches = model.trim() == id ||
      (
        parsed_entry is Some(entry_model) &&
        parse_engine_model(model) == Some(entry_model)
      )
    if matches {
      count += 1
    }
  }
  count
}

///|
/// Write the draft as an upsert. Every other entry is left alone, so editing
/// one custom model never strands a conversation on another. Renaming the
/// entry the editor holds drops the id it used to have.
fn save_custom_model(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  draft : CustomModelDraft,
  connection_generation : Int32,
) -> @cmd.Cmd {
  let id = draft.id.trim().to_owned()
  let renamed_from : Array[String] = match draft.original {
    Some(original) if original != id => [original]
    _ => []
  }
  let patch : @protocol.SettingsSetPayload = {
    provider: None,
    providers: None,
    followup_behavior: None,
    prompt_source: None,
    custom_prompt: None,
    models: Some([draft.patch()]),
    removed_models: if renamed_from.is_empty() {
      None
    } else {
      Some(renamed_from)
    },
  }
  push_host_settings(dispatch, channel, patch, connection_generation)
}

///|
fn Model::update_custom_model(
  self : Model,
  dispatch : @cmd.Emit[Msg],
  msg : Msg,
) -> (@cmd.Cmd, Model) {
  match (msg, self.custom_model) {
    (CustomModelAdd, _) =>
      (
        @cmd.none,
        {
          ..self,
          custom_model: Some(CustomModelDraft::empty()),
          custom_model_delete: None,
        },
      )
    (CustomModelEdit(id), _) =>
      (
        @cmd.none,
        {
          ..self,
          custom_model: self
          .custom_model_entry(id)
          .map(entry => CustomModelDraft::of(entry)),
          custom_model_delete: None,
        },
      )
    (CustomModelIdChanged(value), Some(draft)) =>
      (@cmd.none, { ..self, custom_model: Some({ ..draft, id: value, }), })
    (CustomModelLabelChanged(value), Some(draft)) =>
      (@cmd.none, { ..self, custom_model: Some({ ..draft, label: value, }), })
    (CustomModelWindowChanged(value), Some(draft)) =>
      (@cmd.none, { ..self, custom_model: Some({ ..draft, window: value, }), })
    (CustomModelCancel, _) => (@cmd.none, { ..self, custom_model: None, })
    (CustomModelSubmit, Some(draft)) =>
      if draft.can_submit(self.custom_models()) {
        (
          save_custom_model(
            dispatch,
            self.focused,
            draft,
            self.focused_connection_generation(),
          ),
          { ..self, custom_model: None, },
        )
      } else {
        (@cmd.none, self)
      }
    (CustomModelDeleteRequest(id), _) =>
      (@cmd.none, { ..self, custom_model_delete: Some(id), })
    (CustomModelDeleteCancelled, _) =>
      (@cmd.none, { ..self, custom_model_delete: None, })
    (CustomModelDelete(id), _) => {
      let patch : @protocol.SettingsSetPayload = {
        provider: None,
        providers: None,
        followup_behavior: None,
        prompt_source: None,
        custom_prompt: None,
        models: None,
        removed_models: Some([id]),
      }
      (
        push_host_settings(
          dispatch,
          self.focused,
          patch,
          self.focused_connection_generation(),
        ),
        {
          ..self,
          custom_model_delete: None,
          custom_model: match self.custom_model {
            Some({ original: Some(original), .. }) if original == id => None
            other => other
          },
        },
      )
    }
    _ => (@cmd.none, self)
  }
}

///|
test "a draft starts as a new entry and needs an id" {
  let empty = CustomModelDraft::empty()
  assert_eq(empty.original, None)
  assert_false(empty.can_submit([]))
  // A blank window means the default, so the field is optional.
  assert_eq(empty.window, "")
  assert_true(empty.window_ok())
  assert_eq(empty.window_value(), None)
  let named = { ..empty, id: "gemini-4-hydrogen", }
  assert_true(named.can_submit([]))
  let patch = named.patch()
  // The endpoint and its key are the API section's, so the entry names neither.
  assert_true(patch.api_url is None)
  assert_true(patch.api_key is None)
  assert_true(patch.full_url is None)
  // Every custom entry accepts images; the form offers nothing to choose.
  assert_eq(patch.images, Some(true))
  assert_eq(patch.id, "gemini-4-hydrogen")
  // A blank field stores the default rather than leaving the run to guess.
  assert_eq(patch.context_window, Some(1_000_000))
}

///|
/// The window is the endpoint's real one, so the form accepts a blank field
/// (the default) or a number the host would store. Anything else blocks Save
/// rather than being sent for the host to refuse.
test "a window the host would not store blocks saving" {
  let draft = { ..CustomModelDraft::empty(), id: "gemini-4-hydrogen", }
  assert_true(draft.can_submit([]))
  for window in ["0", "many", "999", "10000001", "-5"] {
    let invalid = { ..draft, window, }
    assert_false(invalid.window_ok())
    assert_false(invalid.can_submit([]))
    assert_true(invalid.window_value() is None)
  }
  // An endpoint serving less than the default is the case the field exists for.
  let lowered = { ..draft, window: "131072", }
  assert_eq(lowered.window_value(), Some(131_072))
  assert_true(lowered.can_submit([]))
  assert_eq(lowered.patch().context_window, Some(131_072))
  // Grouping commas from the hint are accepted as well.
  let with_commas = { ..draft, window: "131,072", }
  assert_eq(with_commas.window_value(), Some(131_072))
  assert_true(with_commas.can_submit([]))
  // Clearing the field again goes back to the default.
  let cleared = { ..lowered, window: "", }
  assert_true(cleared.can_submit([]))
  assert_eq(cleared.patch().context_window, Some(1_000_000))
}

///|
test "built-in model ids are accepted and duplicate ids block saving in place" {
  let existing : Array[CustomModel] = [
    {
      id: "alpha-model",
      label: None,
      api_url: None,
      full_url: false,
      has_api_key: false,
      images: true,
      context_window: 1_000_000,
    },
    {
      id: "beta-model",
      label: None,
      api_url: None,
      full_url: false,
      has_api_key: false,
      images: true,
      context_window: 1_000_000,
    },
  ]
  for builtin in ["deepseek-flash", "deepseek-v4-flash", "glm-5.3"] {
    let draft = { ..CustomModelDraft::empty(), id: builtin, }
    assert_true(draft.id_error(existing) is None)
    assert_true(draft.can_submit(existing))
  }
  let dup_add = { ..CustomModelDraft::empty(), id: "alpha-model", }
  assert_true(dup_add.id_error(existing) is Some(ModelIdDuplicate))
  assert_false(dup_add.can_submit(existing))
  let dup_rename = { ..CustomModelDraft::of(existing[0]), id: "beta-model", }
  assert_true(dup_rename.id_error(existing) is Some(ModelIdDuplicate))
  assert_false(dup_rename.can_submit(existing))
  // An alias of an already saved built-in id also counts as a duplicate.
  let with_flash : Array[CustomModel] = [
    ..existing,
    { ..existing[0], id: "deepseek-flash", },
  ]
  let alias_dup = { ..CustomModelDraft::empty(), id: "deepseek-v4-flash", }
  assert_true(alias_dup.id_error(with_flash) is Some(ModelIdDuplicate))
  // A display name beyond 64 characters blocks Save in place.
  let long_label = String::make(65, 'a')
  let too_long = {
    ..CustomModelDraft::empty(),
    id: "gamma-model",
    label: long_label,
  }
  assert_false(too_long.label_ok())
  assert_false(too_long.can_submit(existing))
  // Editing an entry while keeping its own id stays valid.
  let same_entry = CustomModelDraft::of(existing[0])
  assert_true(same_entry.id_error(existing) is None)
  assert_true(same_entry.can_submit(existing))
}

///|
test "editing a stored entry remembers which id it came from" {
  let entry : CustomModel = {
    id: "gemini-4-hydrogen",
    label: Some("Gemini 4 Hydrogen"),
    api_url: Some("https://openrouter.ai/api/v1/chat/completions"),
    full_url: false,
    has_api_key: true,
    images: true,
    context_window: 131_072,
  }
  let draft = CustomModelDraft::of(entry)
  assert_eq(draft.original, Some("gemini-4-hydrogen"))
  assert_eq(draft.id, "gemini-4-hydrogen")
  assert_eq(draft.label, "Gemini 4 Hydrogen")
  // The window re-opens as the entry stored it, not as the default.
  assert_eq(draft.window, "131072")
  // The name falls back to the id when the user never set one.
  assert_eq(CustomModelDraft::of({ ..entry, label: None, }).label, "")
}
