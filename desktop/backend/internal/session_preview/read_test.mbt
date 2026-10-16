///|
async fn new_store() -> @store.SessionStore {
  let root = @fs.tmpdir(prefix="openseek-session-store-")
  SessionStore(root)
}

///|
/// Append raw bytes to a session's durable file the way a torn write or a
/// foreign writer would: no header rewrite, no lock, and no trailing newline
/// unless `text` carries one.
async fn append_raw(
  store : @store.SessionStore,
  id : String,
  text : String,
) -> Unit {
  @fs.write_file(
    store.session_file(SessionId(id)),
    text,
    create_mode=OpenOrCreate,
    append=true,
  )
}

///|
async test "listing extracts text without decoding image payloads" {
  let store = new_store()
  defer @fs.rmdir(store.root(), recursive=true)
  let id = @agent_session.SessionId("image-preview")
  store.create(Session(id, system_prompt="system"))
  // A listing is display metadata, not a loadability check. Even an image
  // whose bytes cannot be decoded must not hide the accompanying title.
  append_raw(
    store,
    id.value(),
    (
      #|{"sequence":1,"ts":0,"item":{"kind":"user","payload":{"content":[{"type":"text","text":"Before "},{"type":"image","media_type":"image/png","data":"not-base64"},{"type":"text","text":"after"}]}}}
    ) +
    "\n",
  )
  assert_eq(
    @session_preview.read_first_prompt(store.session_file(id)),
    Some("Before after"),
  )
  store.create(Session(id, system_prompt="system"))
  append_raw(
    store,
    id.value(),
    (
      #|{"item":{"kind":"user","payload":{"content":[{"type":"image","media_type":"image/png","data":"not-base64"}]}}}
    ) +
    "\n",
  )
  assert_eq(
    @session_preview.read_first_prompt(store.session_file(id)),
    Some("[Image]"),
  )
}

///|
async test "listing reads current prompt on demand without retaining errors" {
  let store = new_store()
  defer @fs.rmdir(store.root(), recursive=true)
  let id = @agent_session.SessionId("changing")
  store.create(Session(id, system_prompt="system"))
  @fs.remove(store.session_file(id))
  try @session_preview.read_first_prompt(store.session_file(id)) catch {
    _ => ()
  } noraise {
    _ => fail("prompt access must read the current file")
  }
  store.create(
    @agent_session.Session(id, system_prompt="system").append(
      User(UserMessage(Content([Text("Recreated")]))),
    ),
  )
  assert_eq(
    @session_preview.read_first_prompt(store.session_file(id)),
    Some("Recreated"),
  )
}

///|
async test "listing distinguishes absent empty and unreadable prompts" {
  let store = new_store()
  defer @fs.rmdir(store.root(), recursive=true)
  let id = @agent_session.SessionId("prompt-states")
  let empty = @agent_session.Session(id, system_prompt="system")
  store.create(empty)
  assert_eq(@session_preview.read_first_prompt(store.session_file(id)), None)
  store.create(empty.append(User(UserMessage(Content([Text("")])))))
  // Empty text remains a found prompt on repeated reads.
  assert_eq(
    @session_preview.read_first_prompt(store.session_file(id)),
    Some(""),
  )
  assert_eq(
    @session_preview.read_first_prompt(store.session_file(id)),
    Some(""),
  )
  store.create(empty)
  append_raw(store, id.value(), "{\n")
  try @session_preview.read_first_prompt(store.session_file(id)) catch {
    @json.ParseError::InvalidEof => ()
    error => raise error
  } noraise {
    _ => fail("invalid JSON must report its parse error")
  }
  store.create(empty)
  append_raw(store, id.value(), "{}\n")
  try @session_preview.read_first_prompt(store.session_file(id)) catch {
    @json.JsonDecodeError(_) => ()
    error => raise error
  } noraise {
    _ => fail("invalid event must report its decode error")
  }
  store.create(empty)
  append_raw(
    store,
    id.value(),
    (
      #|{"item":{"kind":"user","payload":{"content":42}}}
    ) +
    "\n",
  )
  try @session_preview.read_first_prompt(store.session_file(id)) catch {
    Failure(message) =>
      assert_true(message.contains("expected content string or array"))
    error => raise error
  } noraise {
    _ => fail("invalid user content must report an error")
  }
  // Repairing the transcript restores its label.
  store.create(empty.append(User(UserMessage(Content([Text("repaired")])))))
  assert_eq(
    @session_preview.read_first_prompt(store.session_file(id)),
    Some("repaired"),
  )
}

///|
async test "listing scan limit reports absence rather than empty text" {
  let store = new_store()
  defer @fs.rmdir(store.root(), recursive=true)
  let mut session = @agent_session.Session(
    SessionId("scan-limit"),
    system_prompt="system",
  )
  for _ in 0..<50 {
    session = session.append(Terminal(Finished("done")))
  }
  store.create(session.append(User(UserMessage(Content([Text("past limit")])))))
  assert_eq(
    @session_preview.read_first_prompt(store.session_file(session.id())),
    None,
  )
}
