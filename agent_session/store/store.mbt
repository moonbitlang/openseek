///|
let session_header_version : Int = 1

///|
let session_dir_name : String = "sessions"

///|
let header_file_name : String = "session.json"

///|
let event_log_file_name : String = "events.jsonl"

///|
priv struct SessionHeader {
  id : @agent_session.SessionId
  system_prompt : String
  last_sequence : Int
}

///|
/// Native filesystem-backed store for durable OpenSeek sessions. The store owns
/// a root directory and keeps each session under `root/sessions/<id>`.
pub struct SessionStore {
  priv root : String
} derive(Debug)

///|
pub fn SessionStore::SessionStore(root : String) -> SessionStore {
  { root, }
}

///|
pub fn SessionStore::root(self : SessionStore) -> String {
  self.root
}

///|
fn validate_session_id(id : @agent_session.SessionId) -> Unit raise {
  let value = id.value()
  if value == "" {
    fail("session id must not be empty")
  }
  if value.contains("/") || value.contains("\\") {
    fail("session id must not contain path separators: \{value}")
  }
  if value == "." || value == ".." {
    fail("session id must not be `.` or `..`")
  }
}

///|
fn SessionStore::sessions_dir(self : SessionStore) -> String {
  self.root + "/" + session_dir_name
}

///|
fn SessionStore::session_dir(
  self : SessionStore,
  id : @agent_session.SessionId,
) -> String raise {
  validate_session_id(id)
  self.sessions_dir() + "/" + id.value()
}

///|
fn SessionStore::header_path(
  self : SessionStore,
  id : @agent_session.SessionId,
) -> String raise {
  self.session_dir(id) + "/" + header_file_name
}

///|
fn SessionStore::event_log_path(
  self : SessionStore,
  id : @agent_session.SessionId,
) -> String raise {
  self.session_dir(id) + "/" + event_log_file_name
}

///|
fn session_header_json(session : @agent_session.Session) -> Json {
  {
    "version": session_header_version,
    "id": session.id(),
    "system_prompt": session.system_prompt(),
    "last_sequence": session.last_sequence(),
  }
}

///|
fn[T] json_decode_error(
  path : @json.JsonPath,
  message : String,
) -> T raise @json.JsonDecodeError {
  raise JsonDecodeError((path, message))
}

///|
fn header_string_field(
  fields : Map[String, Json],
  path : @json.JsonPath,
  key : String,
) -> String raise @json.JsonDecodeError {
  match fields.get(key) {
    Some(String(value)) => value
    Some(_) => json_decode_error(path.add_key(key), "expected string")
    None => json_decode_error(path.add_key(key), "expected string")
  }
}

///|
fn header_int_field(
  fields : Map[String, Json],
  path : @json.JsonPath,
  key : String,
) -> Int raise @json.JsonDecodeError {
  match fields.get(key) {
    Some(Number(value, ..)) => value.to_int()
    Some(_) => json_decode_error(path.add_key(key), "expected int")
    None => json_decode_error(path.add_key(key), "expected int")
  }
}

///|
fn decode_session_header(
  json : Json,
  path : @json.JsonPath,
) -> SessionHeader raise @json.JsonDecodeError {
  let fields = match json {
    Object(fields) => fields
    _ => json_decode_error(path, "expected session header object")
  }
  match header_int_field(fields, path, "version") {
    1 => ()
    other =>
      json_decode_error(
        path.add_key("version"),
        "unsupported session header version: \{other}",
      )
  }
  let id : @agent_session.SessionId = match fields.get("id") {
    Some(id) => @json.from_json(id, path=path.add_key("id"))
    None => json_decode_error(path.add_key("id"), "expected id")
  }
  {
    id,
    system_prompt: header_string_field(fields, path, "system_prompt"),
    last_sequence: header_int_field(fields, path, "last_sequence"),
  }
}

///|
impl FromJson for SessionHeader with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> SessionHeader {
  decode_session_header(json, path)
}

///|
fn events_jsonl(events : @vector.Vector[@agent_session.SessionEvent]) -> String {
  let builder = StringBuilder::new()
  for event in events {
    builder.write_string(event.to_json().stringify())
    builder.write_string("\n")
  }
  builder.to_string()
}

///|
fn parse_events_jsonl(
  text : String,
) -> @vector.Vector[@agent_session.SessionEvent] raise {
  let events : Array[@agent_session.SessionEvent] = []
  for line in text.split("\n") {
    if line.trim().is_empty() {
      continue
    }
    let event : @agent_session.SessionEvent = @json.from_json(@json.parse(line))
    events.push(event)
  }
  @vector.from_array(events)
}

///|
async fn write_header(
  store : SessionStore,
  session : @agent_session.Session,
) -> Unit {
  @fs.write_file(
    store.header_path(session.id()),
    session_header_json(session).stringify(),
    create_mode=CreateOrTruncate,
  )
}

///|
async fn write_event_log(
  store : SessionStore,
  session : @agent_session.Session,
) -> Unit {
  @fs.write_file(
    store.event_log_path(session.id()),
    events_jsonl(session.events()),
    create_mode=CreateOrTruncate,
  )
}

///|
async fn append_event(
  store : SessionStore,
  session : @agent_session.Session,
  event : @agent_session.SessionEvent,
) -> Unit {
  @fs.write_file(
    store.event_log_path(session.id()),
    event.to_json().stringify() + "\n",
    create_mode=OpenOrCreate,
    append=true,
  )
}

///|
async fn read_event_log_text(path : String) -> String {
  @fs.read_file(path).text() catch {
    @os_error.OSError(_) as error if error.is_ENOENT() => ""
    error => raise error
  }
}

///|
async fn ensure_session_dir(
  store : SessionStore,
  id : @agent_session.SessionId,
) -> Unit {
  let dir = store.session_dir(id)
  if @fs.exists(dir) {
    return
  }
  @fs.mkdir(dir, recursive=true) catch {
    error => if @fs.exists(dir) { () } else { raise error }
  }
}

///|
/// Return whether a session directory exists. Invalid session ids raise rather
/// than being silently treated as absent.
pub async fn SessionStore::exists(
  self : SessionStore,
  id : @agent_session.SessionId,
) -> Bool {
  @fs.exists(self.session_dir(id))
}

///|
/// List known session ids under this store. Missing stores are treated as empty.
pub async fn SessionStore::list(
  self : SessionStore,
) -> Array[@agent_session.SessionId] {
  let names = @fs.readdir(self.sessions_dir(), sort=true) catch { _ => [] }
  [
    for name in names if name != "." && name != ".." => SessionId(name)
  ]
}

///|
/// Persist a complete session, replacing any previous header and event log for
/// the same id. Use this for new sessions or deliberate rewrites; ordinary
/// agent progress should use `append`.
pub async fn SessionStore::create(
  self : SessionStore,
  session : @agent_session.Session,
) -> Unit {
  ensure_session_dir(self, session.id())
  write_header(self, session)
  write_event_log(self, session)
}

///|
/// Load a session by reading its header and replaying the append-only event log.
pub async fn SessionStore::load(
  self : SessionStore,
  id : @agent_session.SessionId,
) -> @agent_session.Session {
  let header : SessionHeader = @json.from_json(
    @json.parse(@fs.read_file(self.header_path(id)).text()),
  )
  if header.id.value() != id.value() {
    fail(
      "session header id mismatch: requested \{id.value()}, found \{header.id.value()}",
    )
  }
  ignore(header.last_sequence)
  let events_text = read_event_log_text(self.event_log_path(id))
  Session(
    header.id,
    system_prompt=header.system_prompt,
    events=parse_events_jsonl(events_text),
  )
}

///|
/// Append one typed item to the session's event log and update the header.
/// Returns the new in-memory session value.
pub async fn SessionStore::append(
  self : SessionStore,
  session : @agent_session.Session,
  item : @agent_session.SessionItem,
) -> @agent_session.Session {
  let (next, event) = session.append_event(item)
  ensure_session_dir(self, next.id())
  append_event(self, next, event)
  write_header(self, next)
  next
}

///|
/// Append a validated summary event to the durable session log. The raw covered
/// events remain in `events.jsonl`; model-facing projection compacts them.
pub async fn SessionStore::compact(
  self : SessionStore,
  session : @agent_session.Session,
  content~ : String,
  from_sequence~ : Int,
  to_sequence~ : Int,
) -> @agent_session.Session {
  let next = session.compact(content~, from_sequence~, to_sequence~)
  let event = match next.events().peek() {
    Some(event) => event
    None => fail("compacted session did not append a summary event")
  }
  ensure_session_dir(self, next.id())
  append_event(self, next, event)
  write_header(self, next)
  next
}
