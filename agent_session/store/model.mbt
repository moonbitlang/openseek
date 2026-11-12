///|
/// The model a session last ran on lives beside its transcript, so resuming
/// the session keeps that model instead of falling back to a global default.
let model_file_name : String = "model.json"

///|
/// The chat model and thinking mode one session runs on. The protocol module
/// owns the type and its `model.json` codec, so `sessions list` and the Desktop
/// listing read the record with the same decoder.
pub using @protocol {type SessionModel}

///|
fn session_model_text(model : SessionModel) -> String {
  model.to_json().stringify()
}

///|
fn parse_session_model(text : String) -> SessionModel raise {
  @json.from_json(@json.parse(text))
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
