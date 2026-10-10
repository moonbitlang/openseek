///|
fn SessionStore::prediction_path(
  self : SessionStore,
  id : @agent_session.SessionId,
) -> String raise {
  "\{self.session_dir(id)}/prediction.json"
}

///|
async fn read_prediction(
  store : SessionStore,
  id : @agent_session.SessionId,
) -> @protocol.PredictionRecord? {
  let text = @fs.read_file(store.prediction_path(id)).text() catch {
    @os_error.OSError(_) as error if error.is_ENOENT() => return None
    error => raise error
  }
  let json = @json.parse(text)
  // Development builds previously saved attempts before making the request.
  // They are not results and must not suppress a new attempt after reopening.
  if json is { "version": 1, "outcome": Null, .. } {
    return None
  }
  let record : @protocol.PredictionRecord = @json.from_json(json)
  if record.outcome is Completed(..) {
    Some(record)
  } else {
    None
  }
}

///|
/// Reading auxiliary metadata never creates a session or changes its transcript.
pub async fn SessionStore::prediction(
  self : SessionStore,
  id : @agent_session.SessionId,
) -> @protocol.PredictionRecord? {
  with_existing_session_lock(self, id, Shared, () => read_prediction(self, id))
}

///|
/// Save a completed result only while its source session is still current.
/// Reuse the transcript lock so a late result cannot overwrite a newer turn.
pub async fn SessionStore::save_prediction(
  self : SessionStore,
  session : @agent_session.Session,
  record : @protocol.PredictionRecord,
) -> Unit {
  guard record.source_sequence == session.last_sequence() &&
    record.outcome is Completed(..) else {
    fail("expected a completed prediction for the source session")
  }
  with_existing_session_lock(self, session.id(), Exclusive, () => {
    let current = read_session_file(self, session.id()).session
    guard current == session &&
      current.events().peek() is Some(event) &&
      event.item() is Terminal(Finished(_)) else {
      return
    }
    write_text_atomic(
      self.prediction_path(session.id()),
      record.to_json().stringify(),
      dirs=self.session_dir_chain(session.id()),
    )
  })
}
