///|
/// Creation input, not scratch data: edits and forks need the original base
/// without the source session's runtime environment. Directory moves carry it
/// with the transcript, and a resume never replaces it with a page preference.
fn session_prompt_path(
  store : @store.SessionStore,
  id : @agent_session.SessionId,
) -> @pathx.Path raise {
  Path(store.base_prompt_file(id))
}

///|
async fn saved_session_prompt(
  store : @store.SessionStore,
  id : @agent_session.SessionId,
) -> String? {
  store.read_base_prompt(id)
}

///|
/// Capture once before the first engine starts. A failed start can retry with
/// the captured input; a durable session uses its JSONL prompt, not this file.
async fn capture_session_prompt(
  store : @store.SessionStore,
  id : @agent_session.SessionId,
  text : String?,
) -> @pathx.Path? {
  if @fs.exists(store.session_file(id)) {
    return None
  }
  let path = session_prompt_path(store, id)
  // Two hosts may start the same draft. Only the first capture owns its base.
  let lock = if text is Some(_) {
    Some(@fsx.FileLock::acquire(path))
  } else {
    None
  }
  defer (if lock is Some(lock) { lock.release() })
  if @fs.exists(store.session_file(id)) {
    return None
  }
  if @fsx.read_text_if_exists(path) is Some(_) {
    return Some(path)
  }
  guard text is Some(text) else { return None }
  @openseek/atomic_file.write_text_atomic(path.to_string(), text)
  Some(path)
}
