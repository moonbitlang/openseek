// Saved custom models for the Custom URL provider slot: shared model matching,
// inline editor state, and whole-list persistence via `settings.set`.

///|
priv enum CustomModelMsg {
  Add
  Edit(String)
  IdChanged(String)
  LabelChanged(String)
  WindowChanged(String)
  Submit
  Cancel
  Delete(String)
}

///|
/// The engine model a saved custom entry resolves to: a built-in tier when the
/// user named a shipped id, or `Custom(id)` with the entry's context window.
fn custom_model_engine_model(entry : @protocol.CustomModel) -> @deepseek.Model {
  match parse_engine_model(entry.id) {
    Some(Custom(_)) | None =>
      @deepseek.Custom(entry.id, context_window=entry.context_window)
    Some(builtin) => builtin
  }
}

///|
/// Whether `model` names `entry`. Custom ids match by wire id regardless of
/// context window (session records carry the parse default).
fn custom_model_matches(
  entry : @protocol.CustomModel,
  model : @deepseek.Model,
) -> Bool {
  match (parse_engine_model(entry.id), model) {
    (Some(Custom(entry_id, ..)), Custom(model_id, ..)) => entry_id == model_id
    (Some(builtin), model) => builtin == model
    (None, Custom(model_id, ..)) => entry.id == model_id
    (None, _) => false
  }
}

///|
fn find_custom_model(
  models : Array[@protocol.CustomModel],
  model : @deepseek.Model,
) -> @protocol.CustomModel? {
  models
  .search_by(entry => custom_model_matches(entry, model))
  .map(index => models[index])
}

///|
fn custom_model_display_name(entry : @protocol.CustomModel) -> String {
  match entry.label {
    Some(label) => label
    None => custom_model_engine_model(entry).label()
  }
}

///|
/// The entry the editor holds: a new one when `original` is `None`, or the
/// stored entry named by `original` when editing an existing one.
#derive(Eq)
priv struct CustomModelDraft {
  original : String?
  id : String
  label : String
  window : String
}

///|
fn CustomModelDraft::empty() -> CustomModelDraft {
  { original: None, id: "", label: "", window: "", }
}

///|
fn CustomModelDraft::of(entry : @protocol.CustomModel) -> CustomModelDraft {
  {
    original: Some(entry.id),
    id: entry.id,
    label: entry.label.unwrap_or(""),
    window: entry.context_window.to_string(),
  }
}

///|
/// Parsed context window in range, or `None` when blank or invalid.
fn CustomModelDraft::window_value(self : CustomModelDraft) -> Int32? {
  let text = self.window.trim().to_owned().replace_all(old=",", new="")
  if text.is_empty() {
    return None
  }
  let value : Int32 = @string.from_str(text) catch { _ => return None }
  if value >= @protocol.MinCustomModelContextWindow &&
    value <= @protocol.MaxCustomModelContextWindow {
    Some(value)
  } else {
    None
  }
}

///|
fn CustomModelDraft::window_ok(self : CustomModelDraft) -> Bool {
  self.window.trim().is_empty() || self.window_value() is Some(_)
}

///|
fn CustomModelDraft::id_error(
  self : CustomModelDraft,
  existing : Array[@protocol.CustomModel],
) -> @settings.Message? {
  let id = self.id.trim().to_owned()
  if id.is_empty() {
    return None
  }
  let parsed = parse_engine_model(id)
  if existing.any(entry => {
      self.original != Some(entry.id) &&
      (
        entry.id == id ||
        (parsed is Some(model) && custom_model_matches(entry, model))
      )
    }) {
    return Some(ModelIdDuplicate)
  }
  None
}

///|
fn CustomModelDraft::can_submit(
  self : CustomModelDraft,
  existing : Array[@protocol.CustomModel],
) -> Bool {
  !self.id.trim().is_empty() &&
  self.id_error(existing) is None &&
  self.window_ok()
}

///|
fn CustomModelDraft::to_model(self : CustomModelDraft) -> @protocol.CustomModel {
  let label = self.label.trim().to_owned()
  {
    id: self.id.trim().to_owned(),
    label: if label.is_empty() {
      None
    } else {
      Some(label)
    },
    context_window: self
    .window_value()
    .unwrap_or(@protocol.DefaultCustomModelContextWindow),
  }
}

///|
/// Apply this draft to `existing`, replacing in place when editing or appending
/// when adding a new entry.
fn CustomModelDraft::apply(
  self : CustomModelDraft,
  existing : Array[@protocol.CustomModel],
) -> Array[@protocol.CustomModel] {
  let updated = self.to_model()
  match self.original {
    Some(original) => {
      let next : Array[@protocol.CustomModel] = []
      let mut replaced = false
      for entry in existing {
        if entry.id == original {
          next.push(updated)
          replaced = true
        } else {
          next.push(entry)
        }
      }
      if !replaced {
        next.push(updated)
      }
      next
    }
    None => [..existing, updated]
  }
}

///|
fn Model::custom_models(self : Model) -> Array[@protocol.CustomModel] {
  self.host_settings().map(settings => settings.models).unwrap_or([])
}

///|
fn save_custom_models(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  models : Array[@protocol.CustomModel],
  connection_generation : Int32,
) -> @cmd.Cmd {
  push_host_settings(
    dispatch,
    channel,
    {
      provider: None,
      providers: None,
      followup_behavior: None,
      prompt_source: None,
      custom_prompt: None,
      models: Some(models),
    },
    connection_generation,
  )
}

///|
fn Model::update_custom_model(
  self : Model,
  dispatch : @cmd.Emit[Msg],
  msg : CustomModelMsg,
) -> (@cmd.Cmd, Model) {
  match (msg, self.custom_model) {
    (Add, _) =>
      (@cmd.none, { ..self, custom_model: Some(CustomModelDraft::empty()), })
    (Edit(id), _) => {
      let entries = self.custom_models()
      let draft = entries
        .search_by(entry => entry.id == id)
        .map(index => CustomModelDraft::of(entries[index]))
      (@cmd.none, { ..self, custom_model: draft, })
    }
    (IdChanged(value), Some(draft)) =>
      (@cmd.none, { ..self, custom_model: Some({ ..draft, id: value, }), })
    (LabelChanged(value), Some(draft)) =>
      (@cmd.none, { ..self, custom_model: Some({ ..draft, label: value, }), })
    (WindowChanged(value), Some(draft)) =>
      (@cmd.none, { ..self, custom_model: Some({ ..draft, window: value, }), })
    (Cancel, _) => (@cmd.none, { ..self, custom_model: None, })
    (Submit, Some(draft)) => {
      let existing = self.custom_models()
      if draft.can_submit(existing) {
        (
          save_custom_models(
            dispatch,
            self.focused,
            draft.apply(existing),
            self.focused_connection_generation(),
          ),
          { ..self, custom_model: None, },
        )
      } else {
        (@cmd.none, self)
      }
    }
    (Delete(id), _) => {
      let next = self.custom_models().filter(entry => entry.id != id)
      (
        save_custom_models(
          dispatch,
          self.focused,
          next,
          self.focused_connection_generation(),
        ),
        {
          ..self,
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
test "custom model draft validates ids, windows, and applies edits in place" {
  let existing : Array[@protocol.CustomModel] = [
    { id: "alpha-model", label: Some("Alpha"), context_window: 131_072, },
    {
      id: "deepseek-flash",
      label: None,
      context_window: @protocol.DefaultCustomModelContextWindow,
    },
  ]
  let empty = CustomModelDraft::empty()
  assert_false(empty.can_submit(existing))
  // Blank window uses default; out-of-range or non-numeric blocks save.
  let named = { ..empty, id: "gemini-4-hydrogen", }
  assert_true(named.can_submit(existing))
  assert_eq(
    named.to_model().context_window,
    @protocol.DefaultCustomModelContextWindow,
  )
  for window in ["0", "many", "999", "10000001", "-5"] {
    assert_false({ ..named, window, }.can_submit(existing))
  }
  assert_eq({ ..named, window: "131,072", }.window_value(), Some(131_072))
  // Duplicate id and canonical built-in alias are rejected.
  assert_true(
    { ..empty, id: "alpha-model", }.id_error(existing) is Some(ModelIdDuplicate),
  )
  assert_true(
    { ..empty, id: "deepseek-v4-flash", }.id_error(existing)
    is Some(ModelIdDuplicate),
  )
  // Renaming replaces in place, keeping list order.
  let renamed = {
    ..CustomModelDraft::of(existing[0]),
    id: "alpha-v2",
    label: "",
  }.apply(existing)
  assert_eq(renamed.map(m => m.id), ["alpha-v2", "deepseek-flash"])
  assert_eq(renamed[0].label, None)
}
