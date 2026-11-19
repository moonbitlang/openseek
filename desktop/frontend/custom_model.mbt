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
/// What the last connection test said. `Probing` is what the form shows while
/// the request is in flight, so a slow endpoint cannot look like a dead form.
#derive(Eq)
priv enum ProbeState {
  NotProbed
  Probing
  Probed(ok~ : Bool, detail~ : String)
}

///|
/// The entry the editor holds: a new one when `original` is `None`, or the
/// stored entry named by `original` when it edits an existing one.
#derive(Eq)
priv struct CustomModelDraft {
  // The id of the entry being edited; `None` while adding a new one.
  original : String?
  id : String
  label : String
  probe : ProbeState
  // Set when the Save button was pressed before the probe finished: the reply
  // saves it, so one press both reports the endpoint and writes the entry.
  save_after_probe : Bool
}

///|
fn CustomModelDraft::empty() -> CustomModelDraft {
  {
    original: None,
    id: "",
    label: "",
    probe: NotProbed,
    save_after_probe: false,
  }
}

///|
/// The stored entry as the editor shows it. The key never comes back down, so
/// the key field belongs to the API section, not to this draft.
fn CustomModelDraft::of(entry : CustomModel) -> CustomModelDraft {
  {
    original: Some(entry.id),
    id: entry.id,
    label: entry.label.unwrap_or(""),
    probe: NotProbed,
    save_after_probe: false,
  }
}

///|
/// Whether the Save button may be pressed: a model needs a name.
fn CustomModelDraft::can_submit(self : CustomModelDraft) -> Bool {
  !self.id.trim().is_empty()
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
    context_window: None,
  }
}

///|
/// The endpoint the section above the form holds: its URL and the key typed
/// into it. A blank key means "use the stored one", which the probe resolves
/// on the host.
fn Model::endpoint_inputs(self : Model) -> (String, String?) {
  let url = self
    .host_settings()
    .map(settings => settings.endpoint.config(Custom).api_url.unwrap_or(""))
    .unwrap_or("")
  let key = if self.setup_api_key.is_blank() {
    None
  } else {
    Some(self.setup_api_key.trim().to_owned())
  }
  (url, key)
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
  let mut count : Int32 = 0
  for item in [..dev.sessions, ..dev.archived] {
    guard item.model_settings is Some({ model, .. }) else { continue }
    if parse_engine_model(model) is Some(Custom(recorded)) && recorded == id {
      count += 1
    }
  }
  count
}

///|
/// Send one draft to `settings.test` and report the verdict back as a message.
fn probe_custom_model(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  payload : @protocol.ModelProbePayload,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let reply = @interop.bridge_request(
        channel, @commands.settings_test, payload,
      ) catch {
        error => {
          scheduler.add(
            dispatch(CustomModelProbeFailed(@interop.bridge_error_text(error))),
          )
          return
        }
      }
      scheduler.add(
        dispatch(CustomModelProbed(ok=reply.ok, detail=reply.detail)),
      )
    })
    |> ignore
  })
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
      (
        @cmd.none,
        {
          ..self,
          custom_model: Some({ ..draft, id: value, probe: NotProbed, }),
        },
      )
    (CustomModelLabelChanged(value), Some(draft)) =>
      (@cmd.none, { ..self, custom_model: Some({ ..draft, label: value, }), })
    (CustomModelCancel, _) => (@cmd.none, { ..self, custom_model: None, })
    (CustomModelSubmit, Some(draft)) =>
      if draft.can_submit() {
        let (url, key) = self.endpoint_inputs()
        (
          probe_custom_model(dispatch, self.focused, {
            id: draft.id.trim().to_owned(),
            api_url: url,
            full_url: false,
            api_key: key,
          }),
          {
            ..self,
            custom_model: Some({
              ..draft,
              probe: Probing,
              save_after_probe: true,
            }),
          },
        )
      } else {
        (@cmd.none, self)
      }
    (CustomModelProbed(ok~, detail~), Some(draft)) =>
      if draft.save_after_probe {
        (
          save_custom_model(
            dispatch,
            self.focused,
            draft,
            self.focused_connection_generation(),
          ),
          {
            ..self,
            // A passing probe closes the editor: the entry is in the list now.
            // A failed one keeps it open so the verdict stays readable.
            custom_model: if ok {
              None
            } else {
              Some({
                ..draft,
                probe: Probed(ok~, detail~),
                save_after_probe: false,
              })
            },
          },
        )
      } else {
        (
          @cmd.none,
          {
            ..self,
            custom_model: Some({
              ..draft,
              probe: Probed(ok~, detail~),
              save_after_probe: false,
            }),
          },
        )
      }
    (CustomModelProbeFailed(message), Some(draft)) =>
      // An unreachable endpoint does not block the write: the user may be
      // behind a proxy that the probe cannot use, and refusing to save would
      // strand the form.
      if draft.save_after_probe {
        (
          save_custom_model(
            dispatch,
            self.focused,
            draft,
            self.focused_connection_generation(),
          ),
          {
            ..self,
            custom_model: Some({
              ..draft,
              probe: Probed(ok=false, detail=message),
              save_after_probe: false,
            }),
          },
        )
      } else {
        (
          @cmd.none,
          {
            ..self,
            custom_model: Some({
              ..draft,
              probe: Probed(ok=false, detail=message),
              save_after_probe: false,
            }),
          },
        )
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
  assert_false(empty.can_submit())
  let named = { ..empty, id: "gemini-4-hydrogen", }
  assert_true(named.can_submit())
  let patch = named.patch()
  // The endpoint and its key are the API section's, so the entry names neither.
  assert_true(patch.api_url is None)
  assert_true(patch.api_key is None)
  assert_true(patch.full_url is None)
  // Every custom entry accepts images; the form offers nothing to choose.
  assert_eq(patch.images, Some(true))
  assert_eq(patch.id, "gemini-4-hydrogen")
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
  }
  let draft = CustomModelDraft::of(entry)
  assert_eq(draft.original, Some("gemini-4-hydrogen"))
  assert_eq(draft.id, "gemini-4-hydrogen")
  assert_eq(draft.label, "Gemini 4 Hydrogen")
  // The name falls back to the id when the user never set one.
  assert_eq(CustomModelDraft::of({ ..entry, label: None, }).label, "")
}
