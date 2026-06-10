///|
let session_header_version : Int = 1

///|
let session_dir_name : String = "sessions"

///|
let header_file_name : String = "session.json"

///|
let event_log_file_name : String = "events.jsonl"

///|
let lock_file_name : String = "session.lock"

///|
priv struct SessionHeader {
  id : @agent_session.SessionId
  system_prompt : String
  last_sequence : Int
  event_log_length : Int?
  event_log_hash : Int?
  allow_event_log_ahead : Bool?
}

///|
/// Native filesystem-backed store for durable OpenSeek sessions. The store owns
/// a root directory and keeps each session under `root/sessions/<id>`.
pub struct SessionStore {
  priv root : String
} derive(Debug)

///|
/// Open a store rooted at `root`. Nothing is touched on disk until the first
/// session is created or appended to, so constructing a store is free and
/// never fails.
pub fn SessionStore::SessionStore(root : String) -> SessionStore {
  { root, }
}

///|
/// The root directory this store keeps its `sessions/` tree under.
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
fn SessionStore::lock_path(
  self : SessionStore,
  id : @agent_session.SessionId,
) -> String raise {
  self.session_dir(id) + "/" + lock_file_name
}

///|
fn event_log_hash(text : StringView) -> Int {
  Hash::hash(text)
}

///|
fn session_header_json(
  session : @agent_session.Session,
  events_text : String,
  allow_event_log_ahead : Bool,
) -> Json {
  {
    "version": session_header_version,
    "id": session.id(),
    "system_prompt": session.system_prompt(),
    "last_sequence": session.last_sequence(),
    "event_log_length": events_text.length(),
    "event_log_hash": event_log_hash(events_text),
    "allow_event_log_ahead": allow_event_log_ahead,
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
fn header_optional_int_field(
  fields : Map[String, Json],
  path : @json.JsonPath,
  key : String,
) -> Int? raise @json.JsonDecodeError {
  match fields.get(key) {
    Some(Number(value, ..)) => Some(value.to_int())
    Some(_) => json_decode_error(path.add_key(key), "expected int")
    None => None
  }
}

///|
fn header_optional_bool_field(
  fields : Map[String, Json],
  path : @json.JsonPath,
  key : String,
) -> Bool? raise @json.JsonDecodeError {
  match fields.get(key) {
    Some(True) => Some(true)
    Some(False) => Some(false)
    Some(_) => json_decode_error(path.add_key(key), "expected bool")
    None => None
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
    event_log_length: header_optional_int_field(
      fields, path, "event_log_length",
    ),
    event_log_hash: header_optional_int_field(fields, path, "event_log_hash"),
    allow_event_log_ahead: header_optional_bool_field(
      fields, path, "allow_event_log_ahead",
    ),
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
fn checked_last_sequence_in_events(
  events : @vector.Vector[@agent_session.SessionEvent],
) -> Int raise {
  let mut expected = 1
  for event in events {
    if event.sequence() != expected {
      fail(
        "session event log sequence mismatch: expected \{expected}, found \{event.sequence()}",
      )
    }
    expected += 1
  }
  expected - 1
}

///|
async fn durable_last_sequence(
  store : SessionStore,
  id : @agent_session.SessionId,
) -> Int {
  let events_text = read_event_log_text(store.event_log_path(id))
  checked_last_sequence_in_events(parse_events_jsonl(events_text))
}

///|
async fn read_session_header(
  store : SessionStore,
  id : @agent_session.SessionId,
) -> SessionHeader {
  @json.from_json(@json.parse(@fs.read_file(store.header_path(id)).text()))
}

///|
fn validate_loaded_header(
  header : SessionHeader,
  requested_id : @agent_session.SessionId,
) -> Unit raise {
  if header.id.value() != requested_id.value() {
    fail(
      "session header id mismatch: requested \{requested_id.value()}, found \{header.id.value()}",
    )
  }
}

///|
fn validate_event_log_fingerprint(
  header : SessionHeader,
  events_text : String,
) -> Unit raise {
  match (header.event_log_length, header.event_log_hash) {
    (Some(length), Some(hash)) => {
      if events_text.length() < length ||
        event_log_hash(events_text[:length]) != hash {
        fail("session event log fingerprint mismatch for \{header.id.value()}")
      }
      if header.allow_event_log_ahead == Some(false) &&
        events_text.length() != length {
        fail(
          "session event log stale tail after replacement for \{header.id.value()}",
        )
      }
      let prefix_last_sequence = checked_last_sequence_in_events(
        parse_events_jsonl(events_text[:length].to_owned()),
      )
      if prefix_last_sequence != header.last_sequence {
        fail(
          "session header fingerprint tail mismatch: header last sequence \{header.last_sequence}, fingerprint last sequence \{prefix_last_sequence}",
        )
      }
    }
    (None, None) => ()
    _ => fail("session header event log fingerprint is incomplete")
  }
}

///|
fn session_from_replayed_events(
  header : SessionHeader,
  events_text : String,
  events : @vector.Vector[@agent_session.SessionEvent],
) -> @agent_session.Session raise {
  validate_event_log_fingerprint(header, events_text)
  let replayed_last_sequence = checked_last_sequence_in_events(events)
  if replayed_last_sequence < header.last_sequence {
    fail(
      "session event log tail mismatch: header last sequence \{header.last_sequence}, replayed last sequence \{replayed_last_sequence}",
    )
  }
  Session(header.id, system_prompt=header.system_prompt, events~)
}

///|
async fn load_persisted_session(
  store : SessionStore,
  id : @agent_session.SessionId,
) -> @agent_session.Session {
  let header = read_session_header(store, id)
  validate_loaded_header(header, id)
  let events_text = read_event_log_text(store.event_log_path(id))
  session_from_replayed_events(
    header,
    events_text,
    parse_events_jsonl(events_text),
  )
}

///|
async fn ensure_empty_missing_session(
  store : SessionStore,
  session : @agent_session.Session,
) -> Unit {
  let durable_last = durable_last_sequence(store, session.id())
  if durable_last != 0 || session.last_sequence() != 0 {
    fail(
      "stale session snapshot for \{session.id().value()}: no persisted header, in-memory last sequence \{session.last_sequence()}, durable last sequence \{durable_last}",
    )
  }
}

///|
async fn ensure_session_is_current(
  store : SessionStore,
  session : @agent_session.Session,
) -> Unit {
  let persisted = load_persisted_session(store, session.id()) catch {
    @os_error.OSError(_) as error if error.is_ENOENT() => {
      ensure_empty_missing_session(store, session)
      return
    }
    error => raise error
  }
  if persisted.system_prompt() != session.system_prompt() ||
    events_jsonl(persisted.events()) != events_jsonl(session.events()) {
    fail("stale session snapshot for \{session.id().value()}")
  }
}

///|
async fn write_header(
  store : SessionStore,
  session : @agent_session.Session,
  allow_event_log_ahead : Bool,
) -> Unit {
  let events_text = events_jsonl(session.events())
  write_text_atomic(
    store.header_path(session.id()),
    session_header_json(session, events_text, allow_event_log_ahead).stringify(),
  )
}

///|
async fn write_event_log(
  store : SessionStore,
  session : @agent_session.Session,
) -> Unit {
  write_text_atomic(
    store.event_log_path(session.id()),
    events_jsonl(session.events()),
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
async fn write_text_atomic(path : String, text : String) -> Unit {
  let tmp_path = path + ".tmp"
  @fs.write_file(tmp_path, text, create_mode=CreateOrTruncate)
  @fs.rename(tmp_path, path, replace=true)
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
async fn[T] with_session_lock(
  store : SessionStore,
  id : @agent_session.SessionId,
  kind : @fs.Lock,
  body : async () -> T,
) -> T {
  let file = @fs.open(
    store.lock_path(id),
    mode=ReadWrite,
    create_mode=OpenOrCreate,
  )
  defer file.close()
  file.lock(kind)
  defer file.unlock()
  body()
}

///|
async fn[T] with_existing_session_lock(
  store : SessionStore,
  id : @agent_session.SessionId,
  kind : @fs.Lock,
  body : async () -> T,
) -> T {
  let dir = store.session_dir(id)
  if !@fs.exists(dir) {
    return body()
  }
  with_session_lock(store, id, kind, body)
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
  let names = @fs.readdir(self.sessions_dir(), sort=true) catch {
    @os_error.OSError(_) as error if error.is_ENOENT() => []
    error => raise error
  }
  [
    for name in names if name != "." && name != ".." => SessionId(name)
  ]
}

///|
/// One row of a store listing: a session id plus the metadata a picker or
/// `--session-list` shows beside it.
pub struct SessionListing {
  priv id : @agent_session.SessionId
  priv last_active_unix_seconds : Int64?
  priv first_prompt : String
} derive(Debug)

///|
/// The listed session's id.
pub fn SessionListing::id(self : SessionListing) -> @agent_session.SessionId {
  self.id
}

///|
/// When the session last saw activity (event-log mtime, unix seconds), or
/// `None` for a directory whose session could not be loaded.
pub fn SessionListing::last_active_unix_seconds(
  self : SessionListing,
) -> Int64? {
  self.last_active_unix_seconds
}

///|
/// The session's first user prompt — the line that identifies a conversation
/// to a human — or `""` for a session with no user event (or one that could
/// not be loaded).
pub fn SessionListing::first_prompt(self : SessionListing) -> String {
  self.first_prompt
}

///|
/// Lines scanned from the front of an event log while looking for the first
/// user prompt. The agent appends the user turn as a session's first event,
/// so this is normally one line; the cap keeps a pathological log from
/// turning a listing into a full read.
let first_prompt_scan_limit : Int = 50

///|
/// The first user prompt recorded in the event log at `path`, or `""` when
/// none is found within the scan limit (or the log cannot be read). Streams
/// line by line instead of loading the session: a listing only needs a
/// label, and long or compacted histories should not make `--session-list`
/// deserialize every event ever appended.
async fn first_prompt_in_log(path : String) -> String {
  let file = @fs.open(path, mode=ReadOnly) catch { _ => return "" }
  defer file.close()
  for _ in 0..<first_prompt_scan_limit {
    let next = file.read_until("\n") catch { _ => return "" }
    guard next is Some(line) else { break }
    if line.trim().is_empty() {
      continue
    }
    let event : @agent_session.SessionEvent = @json.from_json(@json.parse(line)) catch {
      _ => return ""
    }
    if event.item() is User(message) {
      return message.content()
    }
  }
  ""
}

///|
/// List sessions with the metadata a picker shows, most recently active
/// first. Rows reflect what is on disk without validating whole histories
/// (see `first_prompt_in_log`); a directory whose files cannot even be
/// stat-ed still appears — with no timestamp, ordered last — because a
/// listing is where a user finds the husk they may want to clean up.
/// Loadability is `latest()`'s gate, not the listing's.
pub async fn SessionStore::listings(
  self : SessionStore,
) -> Array[SessionListing] {
  let stamped : Array[(SessionListing, Int64, Int)] = []
  let unreadable : Array[SessionListing] = []
  for id in self.list() {
    let log_path = self.event_log_path(id) catch { _ => continue }
    let stamp = @fs.mtime(log_path) catch {
      _ =>
        @fs.mtime(self.header_path(id) catch { _ => continue }) catch {
          _ => {
            unreadable.push({
              id,
              last_active_unix_seconds: None,
              first_prompt: "",
            })
            continue
          }
        }
    }
    let (seconds, nanoseconds) = stamp
    stamped.push(
      (
        {
          id,
          last_active_unix_seconds: Some(seconds),
          first_prompt: first_prompt_in_log(log_path),
        },
        seconds,
        nanoseconds,
      ),
    )
  }
  // Most recently active first.
  stamped.sort_by((a, b) => {
    let (_, a_seconds, a_nanoseconds) = a
    let (_, b_seconds, b_nanoseconds) = b
    if b_seconds != a_seconds {
      b_seconds.compare(a_seconds)
    } else {
      b_nanoseconds.compare(a_nanoseconds)
    }
  })
  let listings = [ for entry in stamped => entry.0 ]
  for listing in unreadable {
    listings.push(listing)
  }
  listings
}

///|
/// The most recently active session id that can actually be resumed, or
/// `None` for an empty store.
///
/// Recency is the event log's modification time: the header is written once
/// at creation while the log is touched on every append, so its mtime tracks
/// the last turn of actual conversation. A session directory whose log is
/// missing falls back to its header's mtime (created but never appended to).
///
/// Candidates are probed newest-first with a real `load`: a directory can
/// stat fine yet hold a torn session (a crash between log append and header
/// write), and resuming demands a loadable conversation — one broken
/// directory must not make every older, valid session unresumable. In the
/// common case the newest candidate loads and the probe costs one load.
pub async fn SessionStore::latest(
  self : SessionStore,
) -> @agent_session.SessionId? {
  let stamped : Array[(@agent_session.SessionId, Int64, Int)] = []
  for id in self.list() {
    let stamp = @fs.mtime(self.event_log_path(id)) catch {
      _ => @fs.mtime(self.header_path(id)) catch { _ => continue }
    }
    let (seconds, nanoseconds) = stamp
    stamped.push((id, seconds, nanoseconds))
  }
  // Newest first.
  stamped.sort_by((a, b) => {
    let (_, a_seconds, a_nanoseconds) = a
    let (_, b_seconds, b_nanoseconds) = b
    if b_seconds != a_seconds {
      b_seconds.compare(a_seconds)
    } else {
      b_nanoseconds.compare(a_nanoseconds)
    }
  })
  for entry in stamped {
    let (id, _, _) = entry
    let _ = self.load(id) catch { _ => continue }
    return Some(id)
  }
  None
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
  with_session_lock(self, session.id(), Exclusive, () => {
    // Exact header-first rewrites fail closed on stale old-log tails.
    write_header(self, session, false)
    write_event_log(self, session)
    write_header(self, session, true)
  })
}

///|
/// Load a session by reading its header and replaying the append-only event log.
pub async fn SessionStore::load(
  self : SessionStore,
  id : @agent_session.SessionId,
) -> @agent_session.Session {
  with_existing_session_lock(self, id, Shared, () => {
    load_persisted_session(self, id)
  })
}

///|
/// Append one typed item to the session's event log and update the header.
/// Returns the new in-memory session value.
pub async fn SessionStore::append(
  self : SessionStore,
  session : @agent_session.Session,
  item : @agent_session.SessionItem,
) -> @agent_session.Session {
  ensure_session_dir(self, session.id())
  with_session_lock(self, session.id(), Exclusive, () => {
    ensure_session_is_current(self, session)
    let (next, event) = session.append_event(item)
    append_event(self, next, event)
    write_header(self, next, true)
    next
  })
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
  ensure_session_dir(self, session.id())
  with_session_lock(self, session.id(), Exclusive, () => {
    ensure_session_is_current(self, session)
    let next = session.compact(content~, from_sequence~, to_sequence~)
    let event = match next.events().peek() {
      Some(event) => event
      None => fail("compacted session did not append a summary event")
    }
    append_event(self, next, event)
    write_header(self, next, true)
    next
  })
}
