///|
/// The model a session last ran on lives beside its transcript, so resuming
/// the session keeps that model instead of falling back to a global default.
let model_file_name : String = "model.json"

///|
/// The chat model and thinking mode one session runs on.
#derive(Eq, Debug)
pub(all) struct SessionModel {
  model : @deepseek.Model
  thinking : @deepseek.ThinkingMode
}

///|
#doc(hidden)
#deprecated
pub extend SessionModel with Eq::{equal, not_equal}

///|
#doc(hidden)
#deprecated
pub extend SessionModel with Debug::{to_repr}

///|
#doc(hidden)
#deprecated
pub extend SessionModel with ToJson::{to_json}

///|
/// Store the model's wire name and thinking mode, and pin the window for a
/// custom model so a resumed or forked session can use the same budget.
pub impl ToJson for SessionModel with fn to_json(self) {
  let fields : Map[String, Json] = {
    "model": Json(self.model.to_string()),
    "thinking": Json(self.thinking.to_string()),
  }
  if self.model is Custom(_, context_window~) {
    fields["context_window"] = Json(context_window)
  }
  Json::object(fields)
}

///|
fn session_model_text(model : SessionModel) -> String {
  ToJson::to_json(model).stringify()
}

///|
fn parse_session_model(text : String) -> SessionModel raise {
  guard @json.parse(text) is Object(fields) &&
    fields.get("model") is Some(String(model)) &&
    fields.get("thinking") is Some(String(thinking)) else {
    fail("session model must be an object with string model and thinking")
  }
  let context_window = match fields.get("context_window") {
    None => None
    Some(value) => {
      let window : Int32 = @json.from_json(value)
      guard window > 0 else {
        fail("session model context_window must be positive")
      }
      Some(window)
    }
  }
  {
    model: @deepseek.Model::parse(model, context_window?),
    thinking: @deepseek.ThinkingMode::parse(thinking),
  }
}

///|
fn SessionStore::model_path(
  self : SessionStore,
  id : @agent_session.SessionId,
) -> String raise {
  "\{self.session_dir(id)}/\{model_file_name}"
}

///|
/// The model the session last ran on, or `None` when nothing recorded one —
/// a session from before this file existed, or one that has not recorded a
/// turn yet. A file that is present but unreadable or malformed raises
/// rather than passing for absence.
pub async fn SessionStore::model(
  self : SessionStore,
  id : @agent_session.SessionId,
) -> SessionModel? {
  let text = @fs.read_text(self.model_path(id)) catch {
    @os_error.OsError(NotFound, ..) => return None
    error => raise error
  }
  Some(parse_session_model(text))
}

///|
/// Record the model a session runs on. The file is replaced atomically under
/// the session lock, so a reader sees either the old or the new value, and an
/// engine appending to the transcript is unaffected. The session directory
/// must already exist: a run records its model after its first append, so a
/// run that never recorded anything leaves no directory behind.
pub async fn SessionStore::save_model(
  self : SessionStore,
  id : @agent_session.SessionId,
  model : SessionModel,
) -> Unit {
  with_session_lock(self, id, Exclusive, () => {
    write_text_atomic(
      self.model_path(id),
      session_model_text(model),
      dirs=self.session_dir_chain(id),
    )
  })
}
