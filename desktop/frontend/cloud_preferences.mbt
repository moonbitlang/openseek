///|
#derive(Eq)
priv enum CloudSettingsChoice {
  Editing(@cloud.CommandSettings)
  Submitted(@cloud.CommandSettings, Int32)
}

///|
const CloudPreferencesStorageKey : String = "openseek.cloud_model_preferences"

///|
fn cloud_preference_key(account : String, session : String?) -> String {
  ([Json(@cloud.CloudOrigin), Json(account), ToJson::to_json(session)] : Json).stringify()
}

///|
fn Model::cloud_settings(
  self : Model,
  owner : @interop.ConversationIdentity,
) -> @cloud.CommandSettings {
  guard owner is Cloud(account~, session~) else {
    return @cloud.CommandSettings::default()
  }
  let key = cloud_preference_key(account, Some(session))
  let history = if self.cloud.user_id == Some(account) {
    self.cloud.conversations.get(session)
  } else {
    None
  }
  match self.cloud_settings_edits.get(key) {
    Some(Editing(settings)) => return settings
    Some(Submitted(settings, request)) if history.map_or(true, conversation => {
        conversation.settings_request <= request
      }) => return settings
    _ => ()
  }
  if history is Some({ settings: Some(settings), .. }) {
    return settings
  }
  if self.cloud_preferences.iter().find_first(entry => entry.0 == key)
    is Some((_, settings)) {
    return settings
  }
  let key = cloud_preference_key(account, None)
  if self.cloud_preferences.iter().find_first(entry => entry.0 == key)
    is Some((_, settings)) {
    return settings
  }
  @cloud.CommandSettings::default()
}

///|
fn cloud_preferences_with(
  entries : Array[(String, @cloud.CommandSettings)],
  key : String,
  settings : @cloud.CommandSettings,
) -> Array[(String, @cloud.CommandSettings)] {
  let next = [(key, settings)]
  for entry in entries {
    if entry.0 != key && next.length() < ConversationModelsLimit {
      next.push(entry)
    }
  }
  next
}

///|
fn parse_cloud_preferences(
  text : String,
) -> Array[(String, @cloud.CommandSettings)] {
  let rows : Array[Json] = @json.from_json(@json.parse(text)) catch {
    _ => return []
  }
  let entries = []
  for row in rows {
    guard entries.length() < ConversationModelsLimit else { break }
    if row is { "key": String(key), "settings": value, .. } && !key.is_empty() {
      let settings : @cloud.CommandSettings = @json.from_json(value) catch {
        _ => continue
      }
      entries.push((key, settings))
    }
  }
  entries
}

///|
fn save_cloud_preference(
  key : String,
  settings : @cloud.CommandSettings,
) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => {
    // Merge the stored rows, just as save_conversation_model does for Local.
    let stored = load_setting(CloudPreferencesStorageKey)
      .map(parse_cloud_preferences)
      .unwrap_or([])
    let rows : Array[Json] = cloud_preferences_with(stored, key, settings).map(entry => {
      "key": Json(entry.0),
      "settings": ToJson::to_json(entry.1),
    })
    save_setting(CloudPreferencesStorageKey, Json(rows).stringify())
  })
}

///|
fn Model::remember_cloud_settings(
  self : Model,
  owner : @interop.ConversationIdentity,
  settings : @cloud.CommandSettings,
  default~ : Bool = false,
) -> (@cmd.Cmd, Model) {
  guard owner is Cloud(account~, session~) else { return (@cmd.none, self) }
  let key = cloud_preference_key(account, Some(session))
  let entries = cloud_preferences_with(self.cloud_preferences, key, settings)
  if default {
    let key_default = cloud_preference_key(account, None)
    (
      @cmd.batch([
        save_cloud_preference(key, settings),
        save_cloud_preference(key_default, settings),
      ]),
      {
        ..self,
        cloud_preferences: cloud_preferences_with(
          entries, key_default, settings,
        ),
      },
    )
  } else {
    (
      save_cloud_preference(key, settings),
      { ..self, cloud_preferences: entries, },
    )
  }
}

///|
fn Model::choose_cloud_settings(
  self : Model,
  owner : @interop.ConversationIdentity,
  settings : @cloud.CommandSettings,
) -> (@cmd.Cmd, Model) {
  guard owner is Cloud(account~, session~) &&
    self.cloud.user_id == Some(account) &&
    (
      self.cloud_identity() == Some(owner) ||
      self.cloud_draft_identity() == Some(owner)
    ) &&
    self.cloud.can_compose(session) &&
    !self.cloud.retired.contains(session) &&
    !self.cloud.deletions.contains(session) else {
    return (@cmd.none, self)
  }
  let (command, model) = self.remember_cloud_settings(
    owner,
    settings,
    default=true,
  )
  (
    command,
    { ..model.with_cloud_choice(owner, Editing(settings)), select_menu: None, },
  )
}

///|
fn Model::with_cloud_choice(
  self : Model,
  owner : @interop.ConversationIdentity,
  choice : CloudSettingsChoice,
) -> Model {
  guard owner is Cloud(account~, session~) else { return self }
  let edits = self.cloud_settings_edits.copy()
  edits[cloud_preference_key(account, Some(session))] = choice
  { ..self, cloud_settings_edits: edits, }
}

///|
fn Model::retry_cloud_settings(
  self : Model,
  account : String,
  session : String,
  request : Int32,
) -> Model {
  let owner : @interop.ConversationIdentity = Cloud(account~, session~)
  if self.cloud_settings_edits.get(cloud_preference_key(account, Some(session)))
    is Some(Submitted(settings, submitted)) &&
    submitted == request {
    self.with_cloud_choice(owner, Editing(settings))
  } else {
    self
  }
}
