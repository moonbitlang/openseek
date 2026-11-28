// Serving a background job's durable record and a bounded tail of the file it
// wrote: what a reader needs to see what a job printed, without leaving the
// waterfall and without touching the store.
//
// Everything here is derived from files the engine already wrote — the
// `jobs/<generation>/<id>.json` record and the output file it names — so it
// works on old stores and adds no write path. `inspect` never writes.

///|
/// The window one request reads. The desktop panel reads the same size page,
/// so a long job reads the same in both views.
const MaxJobOutputBytes : Int32 = 65536

///|
/// Bounds on the record itself, matching what the desktop refuses to read.
const MaxJobRecordBytes : Int64 = 1048576L

///|
/// A job record found on disk, with the generation directory holding it and
/// the output file's path already resolved.
priv struct JobHit {
  generation : String
  record : Json
  // `None` when the record names no output file (a job whose log was dropped,
  // or one still starting).
  output_path : String?
}

///|
/// The `jobs` directory beside a session file. A store keeps one directory per
/// session — `<store>/sessions/<id>/openseek_session-<id>.jsonl` — with the
/// engine's job generations beside it as `<store>/sessions/<id>/jobs/<generation>`.
/// A directory of copied logs has no such sibling, which is how an archive
/// answers "no record".
fn jobs_dir_beside(session_path : String, session_id : String) -> String? {
  guard valid_session_id(session_id) else { return None }
  match session_path =~ re"^(.|\n)*[/\\]" {
    true => {
      let cut = session_path.length() - path_tail(session_path).length()
      let parent = session_path[:cut].to_owned()
      Some(join_path(trim_trailing_path_separators(parent), "jobs"))
    }
    false => None
  }
}

///|
/// One field of a job record, read leniently: a record written by a newer
/// engine must still lend the viewer its command and size rather than 500 the
/// route.
fn job_string(record : Json, name : String) -> String? {
  match record {
    Object(fields) =>
      match fields.get(name) {
        Some(String(value)) => Some(value)
        _ => None
      }
    _ => None
  }
}

///|
fn job_int(record : Json, name : String) -> Int64? {
  match record {
    Object(fields) =>
      match fields.get(name) {
        Some(Number(value, ..)) if value >= 0.0 && value <= 9007199254740991.0 =>
          Some(value.to_int64())
        _ => None
      }
    _ => None
  }
}

///|
fn job_bool(record : Json, name : String) -> Bool {
  match record {
    Object(fields) => fields.get(name) is Some(True)
    _ => false
  }
}

///|
/// Read one job record file, bounded, and check that it is the record its
/// storage name claims. A malformed record is a miss, not an error: the route
/// answers "no record", which is what the reader can act on.
async fn read_job_record_file(path : String) -> Json? {
  let file = @fs.open(path, mode=ReadOnly) catch { _ => return None }
  defer file.close()
  guard file.kind() is Regular else { return None }
  let size = file.size() catch { _ => return None }
  guard size > 0L && size <= MaxJobRecordBytes else { return None }
  let bytes = file.at(0L).read_exactly(size.to_int()) catch { _ => return None }
  let record = @json.parse(@utf8.decode_lossy(bytes)) catch { _ => return None }
  guard record is Object(_) else { return None }
  Some(record)
}

///|
/// Every generation of a session's jobs that holds a record for `job_id`,
/// ordered closest to `start` when supplied or newest start first otherwise.
///
/// A job id is unique in practice (the engine mints a UUID), but legacy
/// counters (`bg-1`) repeat per generation. `start` — the instant the waterfall
/// drew the span at — separates them: the record that started closest to it
/// wins. Without `start`, the newest record wins, which is what a reader
/// looking at a run's last generation expects.
async fn find_job_hits(
  jobs_dir : String,
  job_id : String,
  start~ : Int64?,
) -> Array[JobHit] {
  guard valid_job_component(job_id) else { return [] }
  let generations = @fs.readdir(jobs_dir, sort=true) catch { _ => return [] }
  let hits : Array[JobHit] = []
  for generation in generations {
    guard valid_job_component(generation) else { continue }
    let directory = join_path(jobs_dir, generation)
    let kind = @fs.kind(directory, follow_symlink=false) catch { _ => continue }
    guard kind is Directory else { continue }
    let name = "\{job_storage_name(job_id)}.json"
    let record = read_job_record_file(join_path(directory, name)) catch {
      _ => continue
    }
    guard record is Some(record) else { continue }
    guard job_string(record, "id") is Some(id) &&
      id == job_id &&
      job_string(record, "generation") == Some(generation) else {
      continue
    }
    let output_path = match job_string(record, "output_file") {
      Some(file) =>
        if valid_job_component(file) {
          Some(join_path(directory, file))
        } else {
          None
        }
      None => None
    }
    hits.push({ generation, record, output_path, })
  }
  fn started(hit : JobHit) -> Int64 {
    job_int(hit.record, "started_at_ms").unwrap_or(0L)
  }
  match start {
    Some(at) =>
      hits.sort_by((a, b) => {
        let (da, db) = ((started(a) - at).abs(), (started(b) - at).abs())
        if da != db {
          da.compare(db)
        } else {
          b.generation.compare(a.generation)
        }
      })
    None =>
      hits.sort_by((a, b) => {
        let (sa, sb) = (started(a), started(b))
        if sa != sb {
          sb.compare(sa)
        } else {
          b.generation.compare(a.generation)
        }
      })
  }
  hits
}

///|
/// One read of a job's output file: the text, the byte range it covers, and
/// whether it was cut short at either end.
priv struct OutputWindow {
  text : String
  start_offset : Int64
  next_offset : Int64
  size : Int64
  // The reply is the tail of a longer file; earlier bytes exist and are not
  // shown.
  head_omitted : Bool
  // The cursor the reader sent no longer names a position in this file — the
  // output was rewritten or truncated — so it must re-read the tail.
  stale : Bool
}

///|
/// Trim a byte page to whole UTF-8 code points. A tail read may begin inside a
/// character (the window is cut at a byte count, not a line), and a
/// concurrently written file may end inside one.
fn utf8_window(bytes : Bytes, tail : Bool) -> (Int32, Int32) {
  let mut start = 0
  if tail {
    while start < bytes.length() && (bytes[start].to_int() & 0xc0) == 0x80 {
      start += 1
    }
  }
  let mut end = bytes.length()
  if end > start {
    let mut lead = end - 1
    while lead > start && (bytes[lead].to_int() & 0xc0) == 0x80 {
      lead -= 1
    }
    let byte = bytes[lead].to_int()
    let width = if byte < 0x80 {
      1
    } else if byte < 0xe0 {
      2
    } else if byte < 0xf0 {
      3
    } else {
      4
    }
    if lead + width > end {
      end = lead
    }
  }
  (start, end)
}

///|
/// Read up to one window of a job's output.
///
/// Without a cursor this is the tail: the last `MaxJobOutputBytes`, so a 40 MB
/// log still answers in one page a reader can scroll. With a cursor it is what
/// was appended since the reader last looked, which is how an open, still
/// running job follows its own output.
async fn read_output_window(path : String, cursor~ : Int64?) -> OutputWindow? {
  let file = @fs.open(path, mode=ReadOnly) catch { _ => return None }
  defer file.close()
  guard file.kind() is Regular else { return None }
  let size = file.size() catch { _ => return None }
  let limit = MaxJobOutputBytes.to_int64()
  let (start, tail) = match cursor {
    Some(offset) =>
      if offset > size {
        return Some({
          text: "",
          start_offset: size,
          next_offset: size,
          size,
          head_omitted: false,
          stale: true,
        })
      } else {
        (offset, false)
      }
    None => ((size - limit).max(0L), size > limit)
  }
  let length = (size - start).min(limit).to_int()
  let bytes = file.at(start).read_exactly(length) catch { _ => return None }
  let (skip, end) = utf8_window(bytes, tail)
  Some({
    text: @utf8.decode_lossy(bytes[skip:end]),
    start_offset: start + skip.to_int64(),
    next_offset: start + end.to_int64(),
    size,
    head_omitted: tail && start + skip.to_int64() > 0L,
    stale: false,
  })
}

///|
/// An artifact component (a generation or a job id), never a path supplied by
/// output text. The engine's own rule is `protocol/jobs.mbt`; the two helpers
/// here are the same on-disk contract, kept local so this module — published on
/// its own — needs no dependency beyond the session reader it already has.
fn valid_job_component(value : String) -> Bool {
  !value.is_empty() &&
  value != "." &&
  value != ".." &&
  value.length() <= 200 &&
  value.all(c => {
    c is ('a'..<='z' | 'A'..<='Z' | '0'..<='9') ||
    c == '-' ||
    c == '_' ||
    c == '.'
  })
}

///|
/// The file stem a job record is stored under: a compact handle maps back to
/// the UUID hex name the engine writes, anything else is its own name.
fn job_storage_name(id : String) -> String {
  guard id.length() == 22 else { return id }
  let encoded = id.replace_all(old="-", new="+").replace_all(old="_", new="/")
  let bytes = @base64.decode(encoded + "==") catch { _ => return id }
  guard bytes.length() == 16 else { return id }
  "uuid-" + @hex.encode(bytes)
}

///|
/// The `start` and `cursor` a job request carries: a millisecond instant and a
/// byte offset. A missing or malformed value means "not given", so a bad query
/// degrades to the plain tail read rather than failing the row.
fn job_offset_param(path : String, name : String) -> Int64? {
  guard query_param(path, name) is Some(text) else { return None }
  let value = @string.parse_int64(text) catch { _ => return None }
  if value < 0L {
    None
  } else {
    Some(value)
  }
}

///|
/// The record as the viewer reads it. Only what it draws: the whole record
/// carries host paths and engine bookkeeping no reader needs.
fn job_summary(hit : JobHit) -> Json {
  let record = hit.record
  let state = match record {
    Object(fields) => fields.get("state").unwrap_or(null)
    _ => null
  }
  let optional = name => {
    match job_string(record, name) {
      Some(value) => Json(value)
      None => null
    }
  }
  let optional_int = name => {
    match job_int(record, name) {
      Some(value) => Json(value.to_double())
      None => null
    }
  }
  Json::object({
    "id": Json(job_string(record, "id").unwrap_or("")),
    "generation": Json(hit.generation),
    "state": state,
    "command": Json(job_string(record, "command").unwrap_or("")),
    "description": optional("description"),
    "started_at_ms": optional_int("started_at_ms"),
    "finished_at_ms": optional_int("finished_at_ms"),
    "output_bytes": Json(
      job_int(record, "output_bytes").unwrap_or(0L).to_double(),
    ),
    "output_file": optional("output_file"),
    "output_truncated": Json(job_bool(record, "output_truncated")),
    "invalid_utf8": Json(job_bool(record, "invalid_utf8")),
    "output_error": optional("output_error"),
  })
}

///|
/// Map a durable job record's `state` JSON into `@trajectory.SpanStatus`.
fn job_span_status(record : Json) -> @trajectory.SpanStatus {
  match record {
    Object(fields) =>
      match fields.get("state") {
        Some(Object(state)) =>
          match state.get("kind") {
            Some(String("exited")) =>
              match state.get("code") {
                Some(Number(0.0, ..)) => Succeeded
                _ => Failed
              }
            Some(String("stopped" | "interrupted")) => Interrupted
            _ => Running
          }
        _ => Running
      }
    _ => Running
  }
}

///|
/// List `(sort_key, (path, mtime_s, mtime_ns, size))` stamps for every durable
/// job metadata file under one session's `jobs/` directory (`stat` only).
async fn session_job_stamps(
  session_path : String,
  session_id : String,
) -> Array[(String, (String, Int64, Int32, Int64))] {
  guard jobs_dir_beside(session_path, session_id) is Some(jobs_dir) else {
    return []
  }
  let generations = @fs.readdir(jobs_dir, sort=true) catch { _ => return [] }
  let out : Array[(String, (String, Int64, Int32, Int64))] = []
  for generation in generations {
    guard valid_job_component(generation) else { continue }
    let dir = join_path(jobs_dir, generation)
    let kind = @fs.kind(dir, follow_symlink=false) catch { _ => continue }
    guard kind is Directory else { continue }
    let files = @fs.readdir(dir, sort=true) catch { _ => continue }
    for file in files {
      guard file.has_suffix(".json") else { continue }
      let path = join_path(dir, file)
      let (seconds, nanoseconds) = session_file_stamp(path)
      let size = file_size(path)
      out.push(
        (
          "\{session_id}/jobs/\{generation}/\{file}",
          (path, seconds.unwrap_or(0L), nanoseconds, size),
        ),
      )
    }
  }
  out
}

///|
/// Read lightweight job timing and outcome metadata for one session without
/// reading `.out` log bodies.
async fn read_session_job_metadata(
  session_path : String,
  session_id : String,
) -> Array[@trajectory.JobMetadata] {
  let entries = session_job_stamps(session_path, session_id)
  let records : Array[@trajectory.JobMetadata] = []
  for entry in entries {
    let path = entry.1.0
    let record = read_job_record_file(path) catch { _ => continue }
    guard record is Some(record) else { continue }
    guard job_string(record, "id") is Some(job_id) &&
      job_int(record, "started_at_ms") is Some(started_at_ms) else {
      continue
    }
    records.push({
      session_id,
      job_id,
      started_at_ms,
      finished_at_ms: job_int(record, "finished_at_ms"),
      status: job_span_status(record),
    })
  }
  records
}

///|
/// Serve one job of one session: its record plus a page of its output.
///
/// `session_path` is the session's own `.jsonl` file, taken from the catalog
/// scan rather than from the URL, so the route cannot be steered at another
/// directory. `job` is percent-decoded and validated as a storage component.
/// `start` disambiguates a legacy job id reused by an earlier generation;
/// `cursor` continues from a byte offset the last reply named.
async fn job_reply(
  session_path : String,
  session_id : String,
  job_id : String,
  start~ : Int64?,
  cursor~ : Int64?,
) -> Reply {
  let directory = match jobs_dir_beside(session_path, session_id) {
    Some(dir) => dir
    None =>
      return json_reply({
        "found": false,
        "error": "this session file has no job store beside it",
      })
  }
  let hits = find_job_hits(directory, job_id, start~)
  let hit = match hits.get(0) {
    Some(hit) => hit
    None =>
      return json_reply({
        "found": false,
        "error": "no saved record for job \{job_id}",
      })
  }
  let job = job_summary(hit)
  let output : Json = match hit.output_path {
    None =>
      match job_string(hit.record, "output_error") {
        Some(error) => Json::object({ "error": Json(error) })
        None => Json::object({ "error": "this job kept no output file" })
      }
    Some(path) =>
      match read_output_window(path, cursor~) {
        None => Json::object({ "error": "the output file cannot be read" })
        Some(window) =>
          Json::object({
            "text": Json(window.text),
            "start_offset": Json(window.start_offset.to_double()),
            "next_offset": Json(window.next_offset.to_double()),
            "size": Json(window.size.to_double()),
            "head_omitted": Json(window.head_omitted),
            "stale": Json(window.stale),
          })
      }
  }
  json_reply({ "found": true, "job": job, "output": output })
}
