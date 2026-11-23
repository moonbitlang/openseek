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
/// The caller holds the session lock and has checked that the title is absent
/// and the candidate is nonblank. A later listing can retry a failed write.
async fn SessionStore::write_initial_title(
  self : SessionStore,
  id : @agent_session.SessionId,
  title : String,
) -> Unit {
  write_text_atomic(self.title_path(id), title, dirs=[self.session_dir(id)]) catch {
    _ => ()
  }
}

///|
/// The session lock covers the absence check and the title write. The
/// transcript has already been saved, so a title error leaves it readable.
async fn SessionStore::initialize_title(
  self : SessionStore,
  id : @agent_session.SessionId,
  title : String,
) -> Unit {
  guard !title.is_empty() else { return }
  let existing = self.title(id) catch { _ => return }
  if existing is None {
    self.write_initial_title(id, title)
  }
}

///|
/// Fill a missing session title from the transcript. Recheck the title
/// under the session lock so a concurrent rename or initializer wins. Return
/// no title when the reader finds no usable text.
pub async fn SessionStore::backfill_title(
  self : SessionStore,
  id : @agent_session.SessionId,
  read_first_prompt~ : async (String) -> String?,
) -> String? {
  let transcript = self.session_file_path(id)
  with_session_lock(self, id, Exclusive, () => {
    if self.title(id) is Some(title) {
      return Some(title)
    }
    let title = title_from_prompt(read_first_prompt(transcript))
    if title is Some(title) {
      self.write_initial_title(id, title)
    }
    title
  }) catch {
    // A read-only store can still supply its display title.
    @os_error.OsError(_) => title_from_prompt(read_first_prompt(transcript))
    error => raise error
  }
}

///|
fn title_from_prompt(prompt : String?) -> String? {
  let title = default_title_text(prompt.unwrap_or(""))
  if title.is_empty() {
    None
  } else {
    Some(title)
  }
}
