///|
fn SessionStore::default_title_path(
  self : SessionStore,
  id : @agent_session.SessionId,
) -> String raise {
  "\{self.session_dir(id)}/session-default-title"
}

///|
fn default_title_text(first_prompt : String) -> String {
  let first_prompt = match @command_context.parse(first_prompt) {
    Some(shell) => "$ \{shell.command}"
    None => first_prompt
  }
  let content = first_prompt.trim()
  match content.split_once("\n") {
    Some((line, _)) => line.trim().to_owned()
    None => content.to_owned()
  }
}

///|
fn default_title_from_content(content : @protocol.Content) -> String {
  let text = content.text()
  if text.is_blank() && !content.is_text_only() {
    "[Image]"
  } else {
    default_title_text(text)
  }
}

///|
fn first_title_content(session : @agent_session.Session) -> @protocol.Content? {
  let events = session.events()
  for i in 0..<events.length().min(first_prompt_scan_limit) {
    if events[i].item() is User(message) {
      return Some(message.content())
    }
  }
  None
}

///|
fn snapshot_default_title(session : @agent_session.Session) -> String {
  first_title_content(session).map(default_title_from_content).unwrap_or("")
}

///|
async fn read_default_title(path : String) -> String? {
  Some(@fs.read_text(path)) catch {
    @os_error.OsError(NotFound, ..) => None
    error => raise error
  }
}

///|
/// The caller holds the session lock. Clear the old title before publishing a
/// transcript that can have a different first prompt. If publication stops
/// halfway, the next reader can recover the title from the current transcript.
async fn SessionStore::clear_default_title(
  self : SessionStore,
  id : @agent_session.SessionId,
) -> Unit {
  @fs.remove(self.default_title_path(id)) catch {
    @os_error.OsError(NotFound, ..) => return
    error => raise error
  }
  sync_dir_best_effort(self.session_dir(id))
}

///|
/// The transcript is authoritative. A failed metadata write leaves it
/// readable and lets a listing retry the backfill.
async fn SessionStore::save_default_title_best_effort(
  self : SessionStore,
  id : @agent_session.SessionId,
  title : String,
) -> Unit {
  write_text_atomic(self.default_title_path(id), title, dirs=[
    self.session_dir(id),
  ]) catch {
    _ => ()
  }
}

///|
/// Return the saved default display title for an existing transcript. An
/// empty title records that the transcript has no usable label. Callers opt
/// into legacy backfill by providing their first-prompt reader. Backfill and
/// transcript replacement share a lock so a title from the old transcript
/// cannot be published after replacement.
pub async fn SessionStore::read_or_backfill_default_title(
  self : SessionStore,
  id : @agent_session.SessionId,
  read_legacy_prompt~ : async (String) -> String?,
) -> String {
  let path = self.default_title_path(id)
  if read_default_title(path) is Some(title) {
    return title
  }
  let transcript = self.session_file_path(id)
  with_session_lock(self, id, Exclusive, () => {
    if read_default_title(path) is Some(title) {
      return title
    }
    let title = default_title_text(read_legacy_prompt(transcript).unwrap_or(""))
    self.save_default_title_best_effort(id, title)
    title
  }) catch {
    // A read-only legacy store can still supply its display title.
    @os_error.OsError(_) =>
      default_title_text(read_legacy_prompt(transcript).unwrap_or(""))
    error => raise error
  }
}
