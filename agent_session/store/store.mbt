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
/// Native filesystem-backed collection of durable OpenSeek sessions.
///
/// A `SessionStore` owns only a root path string. Under that root, each session
/// is stored in `sessions/<id>/` with three files: `session.json`,
/// `events.jsonl`, and `session.lock`. The store is not a handle to one current
/// session; APIs that operate on a session either take a `SessionId` or a
/// `Session` carrying its id.
pub struct SessionStore {
  priv root : String
} derive(Debug)

///|
/// Construct a store rooted at `root`.
///
/// This does not touch the filesystem and therefore does not validate that the
/// directory exists, is writable, or is a directory. Files and directories are
/// created lazily by `create`, `append`, or `compact`. Read-only operations
/// treat a missing `root/sessions` directory as an empty store where that makes
/// sense.
pub fn SessionStore::SessionStore(root : String) -> SessionStore {
  { root, }
}

///|
/// Return the root path passed to `SessionStore(root)`.
///
/// The returned string is not canonicalized. It may be relative or absolute,
/// and no filesystem check is performed by this accessor.
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
  "\{self.root}/\{session_dir_name}"
}

///|
fn SessionStore::session_dir(
  self : SessionStore,
  id : @agent_session.SessionId,
) -> String raise {
  validate_session_id(id)
  "\{self.sessions_dir()}/\{id.value()}"
}

///|
fn SessionStore::header_path(
  self : SessionStore,
  id : @agent_session.SessionId,
) -> String raise {
  "\{self.session_dir(id)}/\{header_file_name}"
}

///|
fn SessionStore::event_log_path(
  self : SessionStore,
  id : @agent_session.SessionId,
) -> String raise {
  "\{self.session_dir(id)}/\{event_log_file_name}"
}

///|
fn SessionStore::lock_path(
  self : SessionStore,
  id : @agent_session.SessionId,
) -> String raise {
  "\{self.session_dir(id)}/\{lock_file_name}"
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
  let builder = StringBuilder()
  for event in events {
    builder <+ "\{event.to_json().stringify()}\n"
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
    "\{event.to_json().stringify()}\n",
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
  let tmp_path = "\{path}.tmp"
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
/// Return whether the directory for `id` exists.
///
/// This checks only `root/sessions/<id>/`; it does not require `session.json` or
/// `events.jsonl` to exist and does not validate that the session is loadable.
/// Invalid ids raise before any filesystem probe, rather than being silently
/// treated as absent.
pub async fn SessionStore::exists(
  self : SessionStore,
  id : @agent_session.SessionId,
) -> Bool {
  @fs.exists(self.session_dir(id))
}

///|
/// Return the absolute or relative path to a session's `events.jsonl` file.
///
/// The path is formed from the store root and `id`; the file is not opened and
/// may not exist. Invalid ids raise. This helper exists for read-only tooling,
/// such as the visualizer server, that wants to stream the raw append-only log
/// without duplicating the store layout rules.
pub fn SessionStore::event_log_file(
  self : SessionStore,
  id : @agent_session.SessionId,
) -> String raise {
  self.event_log_path(id)
}

///|
/// Return the absolute or relative path to a session's `session.json` header.
///
/// The path is formed from the store root and `id`; the file is not opened and
/// may not exist. Invalid ids raise. The header is a small snapshot containing
/// the id, system prompt, last durable sequence, and an event-log fingerprint.
pub fn SessionStore::header_file(
  self : SessionStore,
  id : @agent_session.SessionId,
) -> String raise {
  self.header_path(id)
}

///|
/// List known session ids under `root/sessions`, sorted by directory name.
///
/// This is a directory listing only. It does not open headers, parse logs, or
/// check loadability. A missing `root/sessions` directory returns an empty
/// array. Other filesystem errors raise. Returned ids are raw directory names
/// wrapped as `SessionId`.
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
/// Human-facing metadata for one session directory.
///
/// A listing row is intentionally lighter than a loaded session. It can be
/// built without replaying the full event log, so it is suitable for pickers
/// and `--session-list`. A row can also represent a damaged directory: in that
/// case timestamp may be `None` and first prompt may be empty.
pub struct SessionListing {
  priv id : @agent_session.SessionId
  priv last_active_unix_seconds : Int64?
  priv first_prompt : String
} derive(Debug)

///|
/// Return the listed session id.
///
/// Pass this id to `load`, `exists`, `header_file`, or `event_log_file` when the
/// caller chooses this row.
pub fn SessionListing::id(self : SessionListing) -> @agent_session.SessionId {
  self.id
}

///|
/// Return the listing timestamp in unix seconds.
///
/// For normal sessions this is the modification time of `events.jsonl`; if the
/// log is absent, listing falls back to `session.json`. `None` means neither
/// file could be stat-ed. The value is for sorting/display and is not a durable
/// session field.
pub fn SessionListing::last_active_unix_seconds(
  self : SessionListing,
) -> Int64? {
  self.last_active_unix_seconds
}

///|
/// Return the first user prompt found near the start of the event log.
///
/// The value is a display label, not a validated session field. It is `""` when
/// no user event is found within the scan limit, when the log cannot be read,
/// or when the session directory is damaged.
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
/// List sessions with picker-friendly metadata, most recently active first.
///
/// This scans each session directory for timestamps and a first prompt label,
/// but it does not replay whole histories and does not require loadability.
/// Damaged directories remain visible with `last_active_unix_seconds=None` and
/// `first_prompt=""`, ordered after timestamped rows. Use `latest` when the
/// caller needs the newest session that can actually be loaded.
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
/// Persist a complete session snapshot, replacing prior contents for its id.
///
/// `create` ensures the session directory exists, takes an exclusive lock,
/// rewrites `session.json` and `events.jsonl`, and leaves a header fingerprint
/// that allows normal append-ahead recovery. Use it for new sessions, fixtures,
/// import tools, or deliberate full rewrites. Do not use it for ordinary agent
/// progress; `append` preserves stale-snapshot detection and writes only one
/// new event.
///
/// The call raises on invalid ids, filesystem errors, JSON encoding/write
/// failures, or lock failures.
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
/// Load one persisted session selected by `id`.
///
/// A `SessionStore` is a directory-backed collection, not a handle to one
/// current session. For a store rooted at `root`, the id selects the files under
/// `root/sessions/<id>/`: `session.json`, `events.jsonl`, and `session.lock`.
///
/// `load` validates the id before constructing paths, takes a shared lock when
/// the session directory already exists, reads `session.json`, checks that the
/// header id is exactly the requested id, parses and replays every event in
/// `events.jsonl`, checks that event sequence numbers are contiguous, and
/// validates the header/log fingerprint. The returned value is a rebuilt
/// immutable `Session`.
///
/// `load` never chooses a session implicitly and never mutates the store. Use
/// `list` or `listings` when presenting choices, or `latest` when implementing
/// "resume the newest loadable session", then pass the chosen id to `load`.
///
/// The call raises if the id is invalid, the files cannot be read, the JSON is
/// invalid, or the header and event log do not describe one consistent session.
pub async fn SessionStore::load(
  self : SessionStore,
  id : @agent_session.SessionId,
) -> @agent_session.Session {
  with_existing_session_lock(self, id, Shared, () => {
    load_persisted_session(self, id)
  })
}

///|
/// Append one item to a durable session and return the new session value.
///
/// The input `session` is the caller's current in-memory snapshot. `append`
/// ensures the directory exists, takes an exclusive lock, loads the durable
/// snapshot, and verifies that the durable system prompt and event log match the
/// supplied snapshot. If another writer has already changed the session, this
/// raises a stale-snapshot error instead of forking the log.
///
/// On success the item is assigned the next sequence number and the current
/// wall-clock timestamp, one JSONL line is appended to `events.jsonl`, the
/// header is rewritten with the new last sequence and fingerprint, and the new
/// immutable `Session` is returned. The input session is unchanged.
pub async fn SessionStore::append(
  self : SessionStore,
  session : @agent_session.Session,
  item : @agent_session.SessionItem,
) -> @agent_session.Session {
  ensure_session_dir(self, session.id())
  with_session_lock(self, session.id(), Exclusive, () => {
    ensure_session_is_current(self, session)
    let (next, event) = session.append_event(
      item,
      unix_ms=@env.now().reinterpret_as_int64(),
    )
    append_event(self, next, event)
    write_header(self, next, true)
    next
  })
}

///|
/// Append a validated summary event to a durable session.
///
/// This has the same stale-snapshot and locking behavior as `append`, but the
/// item is created by `Session::compact`. `content` must be non-blank,
/// `from_sequence` must be positive, `to_sequence` must be at least
/// `from_sequence`, and the range must already exist in the supplied session.
///
/// The covered raw events remain in `events.jsonl`; only
/// `Session::chat_messages` applies the compaction by skipping covered earlier
/// events and emitting the summary. On success, the returned session includes
/// the new `Summary` event with a wall-clock timestamp.
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
    let next = session.compact(
      content~,
      from_sequence~,
      to_sequence~,
      unix_ms=@env.now().reinterpret_as_int64(),
    )
    let event = match next.events().peek() {
      Some(event) => event
      None => fail("compacted session did not append a summary event")
    }
    append_event(self, next, event)
    write_header(self, next, true)
    next
  })
}
