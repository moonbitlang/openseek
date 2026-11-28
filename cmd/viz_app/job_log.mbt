// Reading a background job's log from inside the waterfall.
//
// A job's output does not live in the session log: the log records that a job
// started, waited and finished, and the text it wrote stays in its own file
// under the store. `inspect` serves it read-only at
// `<session key>/jobs/<job>` — the durable record plus a page of that file —
// so a reader who sees a job spend forty minutes can find out what it printed
// without leaving the run.

///|
/// A job as the pane draws it: what it ran, how it ended, and how much it
/// wrote.
#derive(Eq)
priv struct JobSummary {
  command : String
  description : String?
  /// `running`, `stopping`, `exited`, `stopped` or `interrupted`.
  state : String
  exit_code : Int32?
  output_bytes : Int64
  /// The engine stopped keeping the whole file; what is on disk is not all the
  /// job printed.
  output_truncated : Bool
  output_file : String?
  invalid_utf8 : Bool
}

///|
/// One job's log as held by the pane.
#derive(Eq)
priv struct JobLog {
  summary : JobSummary
  text : String
  /// The byte offset the next page starts at, so a running job can be followed
  /// from where this page ended instead of re-reading the whole tail.
  next_offset : Int64
  size : Int64
  /// This page is the tail of a longer file: earlier output exists and is not
  /// on screen.
  head_omitted : Bool
  /// The cursor the reader sent no longer names a position in the file: it was
  /// rewritten, so the pane must read the tail again.
  stale : Bool
  /// Why there is no text to show — no output file, an unreadable one, or a
  /// cursor the file outgrew. `None` when `text` is the answer.
  problem : String?
}

///|
/// What the pane holds for one job row.
#derive(Eq)
priv enum JobPanel {
  /// The request is in flight.
  Loading
  Shown(JobLog)
  /// There is no record to read (no store beside the session, no matching
  /// record, or a malformed reply).
  Missing(String)
}

///|
/// One `/api/sessions/<key>/jobs/<job>` answer.
priv enum JobReply {
  Logged(JobLog)
  Absent(String)
}

///|
/// The affordance a job row carries: which panel it opens, and whether that
/// panel is open. Absent on rows that name no job, and on a frozen archive
/// that did not bake one.
priv struct JobToggle {
  key : String
  open : Bool
}

///|
/// The job id inside a panel key.
fn job_id_of_key(key : String) -> String {
  match key.split_once("/") {
    Some(parts) => parts.1.to_owned()
    None => key
  }
}

///|
/// The key a job's panel is held under. A run lists the same job twice — the
/// job's own span and the `job_wait` that blocked on it — and both rows open
/// the same log, so the key is the job, not the row.
fn job_panel_key(session_id : String, job_id : String) -> String {
  "\{session_id}/\{job_id}"
}

///|
/// Every job key a span names (`job_ids` for multi-job waits, falling back to
/// `job_id` for single-job spans or older JSON).
fn span_job_keys(span : @trajectory.TrajectorySpan) -> Array[String] {
  if !span.job_ids.is_empty() {
    [
      for id in span.job_ids => job_panel_key(span.session_id, id)
    ]
  } else {
    match span.job_id {
      Some(id) => [job_panel_key(span.session_id, id)]
      None => []
    }
  }
}

///|
/// Where one job's record lives, as far as the server is concerned. `start` is
/// the instant the waterfall drew the job at: a legacy counter id can repeat
/// across a session's engine runs, and the record that started then is the one
/// the reader is looking at.
fn job_url(
  session_id : String,
  job_id : String,
  start? : Int64,
  cursor? : Int64,
) -> String {
  let base = "/api/sessions/\{encode_uri_component(session_id)}/jobs/\{encode_uri_component(job_id)}"
  match (start, cursor) {
    (None, None) => base
    (start, cursor) => {
      let params = []
      if start is Some(value) {
        params.push("start=\{value}")
      }
      if cursor is Some(value) {
        params.push("cursor=\{value}")
      }
      "\{base}?\{params.join("&")}"
    }
  }
}

///|
/// Read a JSON string field leniently so records from newer engines still
/// populate what the panel understands.
fn job_json_string(json : Json, name : String) -> String? {
  match json {
    Object(fields) =>
      match fields.get(name) {
        Some(String(value)) => Some(value)
        _ => None
      }
    _ => None
  }
}

///|
fn job_json_int(json : Json, name : String) -> Int64? {
  match json {
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
fn job_json_bool(json : Json, name : String) -> Bool {
  match json {
    Object(fields) => fields.get(name) is Some(True)
    _ => false
  }
}

///|
/// The job's state as a word, and its exit code when it exited. The wire keeps
/// the state structured (`{"kind":"exited","code":0}`) so the pane can colour
/// and label it without matching display text.
fn parse_job_state(json : Json) -> (String, Int32?) {
  match json {
    { "kind": String(kind), .. } => {
      let code = match json {
        { "code": Number(value, ..), .. } => Some(value.to_int())
        _ => None
      }
      (kind, code)
    }
    _ => ("unknown", None)
  }
}

///|
/// Decode one job reply. `None` means the body was not a document this build
/// understands; the caller shows that as a failed read rather than as an empty
/// job.
fn parse_job_reply(text : String) -> JobReply? {
  let json = @json.parse(text) catch { _ => return None }
  if json is { "found": False, .. } {
    let why = match job_json_string(json, "error") {
      Some(error) => error
      None => "there is no saved record for this job"
    }
    return Some(Absent(why))
  }
  guard json is { "found": True, "job": Object(record), "output": output, .. } else {
    return None
  }
  let (state, exit_code) = parse_job_state(
    match record.get("state") {
      Some(value) => value
      None => null
    },
  )
  let summary : JobSummary = {
    command: job_json_string(Json::object(record), "command").unwrap_or(""),
    description: job_json_string(Json::object(record), "description"),
    state,
    exit_code,
    output_bytes: job_json_int(Json::object(record), "output_bytes").unwrap_or(
      0L,
    ),
    output_truncated: job_json_bool(Json::object(record), "output_truncated"),
    output_file: job_json_string(Json::object(record), "output_file"),
    invalid_utf8: job_json_bool(Json::object(record), "invalid_utf8"),
  }
  let (text, next_offset, size, head_omitted, stale, problem) = match output {
    Object(fields) =>
      match fields.get("text") {
        Some(String(page)) =>
          (
            page,
            job_json_int(output, "next_offset").unwrap_or(0L),
            job_json_int(output, "size").unwrap_or(0L),
            job_json_bool(output, "head_omitted"),
            job_json_bool(output, "stale"),
            None,
          )
        _ => {
          let why = match job_json_string(output, "error") {
            Some(error) => error
            None => "this job's output cannot be read"
          }
          ("", 0L, 0L, false, false, Some(why))
        }
      }
    _ => ("", 0L, 0L, false, false, Some("this job's output cannot be read"))
  }
  Some(
    Logged({ summary, text, next_offset, size, head_omitted, stale, problem, }),
  )
}

///|
/// Whether the pane should keep asking for a job's newer output: it is still
/// running, so the next page may hold bytes that did not exist when the last
/// one was read.
///
/// The pane cannot know whether the file grew without asking — a reply that
/// reached the end then carries the same offset a moment later — so a running
/// job is re-asked on the same tick as the trace, and a caught-up answer costs
/// one file read from the end of the file.
fn job_log_wants_more(panel : JobPanel) -> Bool {
  match panel {
    Shown(log) =>
      log.problem is None &&
      !log.stale &&
      !job_state_terminal(log.summary.state)
    _ => false
  }
}

///|
/// Whether a job state is over. A state this build does not know is treated as
/// over: guessing "still running" would poll a finished job forever.
fn job_state_terminal(state : String) -> Bool {
  match state {
    "running" | "stopping" => false
    _ => true
  }
}

///|
const MaxRetainedJobLogChars : Int32 = 524288

///|
/// The panel after one reply: a first read replaces what was there, and a
/// follow-up read appends the bytes the file gained. A cursor that does not
/// match `previous.next_offset` (for example a duplicate concurrent poll) is
/// ignored so the same slice is never appended twice.
fn job_panel_after(
  panel : JobPanel,
  cursor : Int64?,
  reply : JobReply,
) -> JobPanel {
  match reply {
    Absent(why) => Missing(why)
    Logged(log) =>
      // A cursor the file outgrew means it was rewritten under the reader: the
      // reply says so and carries no text, so the pane goes back to "reading"
      // and the tail is fetched again.
      if log.stale {
        Loading
      } else {
        match (cursor, panel) {
          (Some(sent), Shown(previous)) =>
            if sent != previous.next_offset {
              Shown(previous)
            } else {
              let combined = previous.text + log.text
              let (text, trimmed) = if combined.length() >
                MaxRetainedJobLogChars {
                (
                  combined[combined.length() - MaxRetainedJobLogChars:].to_owned(),
                  true,
                )
              } else {
                (combined, false)
              }
              Shown({
                ..log,
                text,
                head_omitted: previous.head_omitted ||
                log.head_omitted ||
                trimmed,
              })
            }
          _ => Shown(log)
        }
      }
  }
}
