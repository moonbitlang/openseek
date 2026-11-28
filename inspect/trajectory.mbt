// Serving one run's timeline: a small cache of parsed session files, the
// cursor that lets a polling client skip a rebuild, and the route itself.

///|
/// One parsed session file, with the stamp it was read at.
priv struct CachedSession {
  mtime_s : Int64
  mtime_ns : Int32
  size : Int64
  mut last_used : Int64
  parsed : @session_log.ParsedLog
}

///|
/// Parsed session files by path.
///
/// A watching viewer polls one run every few seconds. Without this the server
/// re-read and re-parsed every file of the run on each poll — including
/// children that stopped writing hours ago, which are most of a long run's
/// bytes. The entry is validated by the file's mtime and size, so an appended
/// file is re-read and a quiet one is not.
let trajectory_cache : Map[String, CachedSession] = Map([])

///|
let trajectory_cache_clock : Ref[Int64] = Ref(0L)

///|
/// How many parsed files to keep before evicting older entries. A run holds
/// tens of sessions; this is far above that and still bounded.
const MaxCachedSessions : Int32 = 512

///|
fn next_cache_tick() -> Int64 {
  trajectory_cache_clock.val = trajectory_cache_clock.val + 1L
  trajectory_cache_clock.val
}

///|
/// Evict the least-recently-used half when the cache reaches capacity, so an
/// active run never suffers a full cold-cache cliff.
fn evict_stale_cache_entries() -> Unit {
  guard trajectory_cache.length() >= MaxCachedSessions else { return }
  let entries : Array[(String, Int64)] = [
    for path, cached in trajectory_cache => (path, cached.last_used)
  ]
  entries.sort_by((a, b) => a.1.compare(b.1))
  let drop_count = entries.length() / 2
  for i in 0..<drop_count {
    trajectory_cache.remove(entries[i].0)
  }
}

///|
/// A stable token for the files a timeline was built from.
///
/// The client echoes it back on its next poll: an equal token means every
/// participating file still carries the stamp and size it had, so the reply is
/// a one-line `unchanged` instead of a whole document. FNV-1a keeps the token
/// short however many files a run has.
fn files_token(entries : Array[(String, Int64, Int32, Int64)]) -> String {
  let mut hash = 1469598103934665603L
  for entry in entries {
    for code in @utf8.encode("\{entry.0}|\{entry.1}|\{entry.2}|\{entry.3};") {
      hash = (hash ^ code.to_int64()) * 1099511628211L
    }
  }
  "\{entries.length()}-\{hash}"
}

///|
/// The first prompt a parsed session carries, for its lane label.
///
/// Read from events the route already holds, so labelling a lane costs no
/// extra file read.
fn first_prompt_of(events : Array[@agent_session.SessionEvent]) -> String {
  for event in events {
    if event.item() is User(message) {
      let content = message.content()
      let text = content.text()
      return if text.is_blank() && !content.is_text_only() {
        "[Image]"
      } else {
        text
      }
    }
  }
  ""
}

///|
/// Load and cache a parsed session file keyed by `path`, stamping its `mtime`
/// and size. Returns `(parsed, stamp_s, nanoseconds, size, read_failed)`.
async fn load_cached_session(
  path : String,
) -> (@session_log.ParsedLog?, Int64, Int32, Int64, Bool) {
  let (seconds, nanoseconds) = session_file_stamp(path)
  let stamp_s = seconds.unwrap_or(0L)
  let size = file_size(path)
  match trajectory_cache.get(path) {
    Some(cached) if cached.mtime_s == stamp_s &&
      cached.mtime_ns == nanoseconds &&
      cached.size == size => {
      cached.last_used = next_cache_tick()
      (Some(cached.parsed), stamp_s, nanoseconds, size, false)
    }
    _ => {
      let read = Some(@fs.read_text(path)) catch { _ => None }
      match read {
        Some(text) => {
          let parsed = @session_log.parse_events(text)
          evict_stale_cache_entries()
          trajectory_cache[path] = {
            mtime_s: stamp_s,
            mtime_ns: nanoseconds,
            size,
            last_used: next_cache_tick(),
            parsed,
          }
          (Some(parsed), stamp_s, nanoseconds, size, false)
        }
        None => (None, stamp_s, nanoseconds, size, true)
      }
    }
  }
}

///|
/// Walk upward from `start_id` inside one store (matching `<parent>-sr-N`
/// naming first, then cached/parsed `child_session_ids_from_events` references)
/// to recover the topmost root session id for a child opened directly.
async fn resolve_root_session_id(
  by_id : Map[String, String],
  store_ids : Array[String],
  start_id : String,
) -> String {
  let mut current = start_id
  let seen : Map[String, Bool] = Map([(start_id, true)])
  let sorted_ids = store_ids.copy()
  sorted_ids.sort()
  while true {
    if @trajectory.parent_session_of(current) is Some(parent) &&
      by_id.get(parent) is Some(_) &&
      seen.get(parent) is None {
      seen[parent] = true
      current = parent
      continue
    }
    let mut found_parent : String? = None
    for candidate in sorted_ids {
      if candidate == current || seen.get(candidate) is Some(_) {
        continue
      }
      guard by_id.get(candidate) is Some(path) else { continue }
      let (parsed, _, _, _, _) = load_cached_session(path)
      if parsed is Some(log) &&
        @trajectory.child_session_ids_from_events(log.events).contains(current) {
        found_parent = Some(candidate)
        break
      }
    }
    match found_parent {
      Some(parent) => {
        seen[parent] = true
        current = parent
      }
      None => break
    }
  }
  current
}

///|
/// Serve one run's timeline: the root session plus every sub-run it spawned,
/// folded into one waterfall.
///
/// The reader hands the builder raw session files, not a pre-parsed shape, so
/// this route stays as tolerant as the rest of the viewer: a torn tail line or
/// a half-written record is dropped by the log parser rather than failing the
/// whole view. Sessions are discovered through the same catalog scan the
/// sidebar uses, which means a child session living under a different root is
/// still found.
///
/// `root_id` is a session id, not a catalog key: a run spans several files, so
/// one opaque per-file key cannot name it. `cursor` is the token of the
/// previous reply: when every participating file still has that stamp the
/// answer is `{ unchanged: true }` and nothing is read at all.
async fn trajectory_reply(
  catalog : SessionCatalog,
  requested_id : String,
  cursor? : String,
  resolve_root~ : Bool = false,
) -> Reply {
  guard valid_session_id(requested_id) else {
    return text_reply(400, "Bad Request", "invalid session id")
  }
  // The scan alone: this route labels lanes from what it parses, so it must
  // not pay the sidebar's per-file prompt read on every poll.
  let files = catalog.files()
  let store_root = match files.search_by(file => file.0 == requested_id) {
    Some(index) => files[index].1
    None =>
      return text_reply(404, "Not Found", "no session file for \{requested_id}")
  }
  let by_id : Map[String, String] = Map([])
  let store_ids : Array[String] = []
  for file in files {
    if file.1 == store_root {
      by_id[file.0] = file.2
      store_ids.push(file.0)
    }
  }
  let root_id = if resolve_root {
    resolve_root_session_id(by_id, store_ids, requested_id)
  } else {
    requested_id
  }
  let mut incomplete = false
  let parsed_by_id : Map[String, @session_log.ParsedLog] = Map([])
  let stamps : Array[(String, Int64, Int32, Int64)] = []
  let participants : Array[(String, String)] = []
  let visited : Map[String, Bool] = Map([])
  let queue : Array[String] = [root_id]
  visited[root_id] = true
  // Seed legacy `<root>-sr-N` children up front so sparse or unannotated trees
  // join the BFS even if an intermediate file is missing.
  for candidate in store_ids {
    if visited.get(candidate) is None &&
      @trajectory.belongs_to_run(root_id, candidate) {
      visited[candidate] = true
      queue.push(candidate)
    }
  }
  let mut head = 0
  while head < queue.length() {
    let id = queue[head]
    head += 1
    guard by_id.get(id) is Some(path) else { continue }
    let (parsed, stamp_s, nanoseconds, size, failed) = load_cached_session(path)
    if failed {
      incomplete = true
    }
    participants.push((id, path))
    stamps.push((path, stamp_s, nanoseconds, size))
    if parsed is Some(parsed) {
      parsed_by_id[id] = parsed
      for child_id in @trajectory.child_session_ids_from_events(parsed.events) {
        if visited.get(child_id) is None && by_id.get(child_id) is Some(_) {
          visited[child_id] = true
          queue.push(child_id)
        }
      }
    }
  }
  if participants.is_empty() {
    return text_reply(404, "Not Found", "no session file for \{root_id}")
  }
  let stamp_pairs : Array[(String, (String, Int64, Int32, Int64))] = [
    for i in 0..<participants.length() => (participants[i].0, stamps[i])
  ]
  for participant in participants {
    let (id, path) = participant
    for pair in session_job_stamps(path, id) {
      stamp_pairs.push(pair)
    }
  }
  stamp_pairs.sort_by((a, b) => a.0.compare(b.0))
  let sorted_stamps : Array[(String, Int64, Int32, Int64)] = [
    for pair in stamp_pairs => pair.1
  ]
  let token = files_token(sorted_stamps)
  if !incomplete && cursor is Some(seen) && seen == token {
    return json_reply({ "unchanged": true, "cursor": token })
  }
  participants.sort_by((a, b) => a.0.compare(b.0))
  let logs : Array[@trajectory.ParsedSessionLog] = []
  let job_records : Array[@trajectory.JobMetadata] = []
  for file in participants {
    let (id, path) = file
    guard parsed_by_id.get(id) is Some(parsed) else { continue }
    for record in read_session_job_metadata(path, id) {
      job_records.push(record)
    }
    // The first prompt is the best human label a session file carries; only
    // its first line is used, because a pasted multi-line brief would
    // swallow the whole lane.
    let title = @trajectory.lane_title(first_prompt_of(parsed.events))
    logs.push({
      id,
      events: parsed.events,
      title: if title.is_empty() {
        None
      } else {
        Some(title)
      },
    })
  }
  if logs.is_empty() {
    return text_reply(404, "Not Found", "no session file for \{root_id}")
  }
  let document = @trajectory.build_trajectory_parsed(
    root_id,
    logs,
    job_records~,
  ).to_json()
  let body = match document {
    Object(fields) => {
      let merged = fields.copy()
      // A file that could not be read leaves the document short of a lane, so the
      // cursor must not claim it is current: the suffix never matches the plain
      // token the next poll computes, which makes that poll read the file again
      // rather than freeze an incomplete drawing in place.
      merged["cursor"] = Json(
        if incomplete {
          "\{token}-partial"
        } else {
          token
        },
      )
      Json::object(merged)
    }
    other => other
  }
  json_reply(body)
}
