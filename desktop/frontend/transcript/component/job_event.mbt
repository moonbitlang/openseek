///|
/// One recorded fact, never the current state of a background job. These
/// values are derived from existing log text without changing its wire format.
priv enum JobEvent {
  Backgrounded(String)
  OutputRead(RecordedJob)
  Finished(RecordedJob)
} derive(Eq)

///|
priv struct RecordedJob {
  id : String
  description : String
  status : JobStatus
} derive(Eq)

///|
priv enum JobStatus {
  Running
  Exited(Int)
  Stopped
  StoppedAtLimit(String)
  CleanupFailed(String)
  OutputCaptureFailed(String)
  Killed(String)
  // An unfamiliar output status can still carry a usable description for
  // job_wait. Display it verbatim rather than inventing a known outcome.
  Unrecognized(String)
} derive(Eq)

///|
fn JobStatus::parse(text : String) -> JobStatus {
  if text == "running" {
    Running
  } else if text == "stopped" {
    Stopped
  } else if text.strip_prefix("exit=") is Some(code) &&
    code.to_owned() =~ re"^-?[0-9]+$" {
    let code = @string.parse_int(code) catch { _ => return Unrecognized(text) }
    Exited(code)
  } else if text.strip_prefix("stopped killed_at_") is Some(reason) {
    StoppedAtLimit(reason.to_owned())
  } else if text.strip_prefix("cleanup failed: ") is Some(reason) {
    CleanupFailed(reason.to_owned())
  } else if text.strip_prefix("output capture failed: ") is Some(reason) {
    OutputCaptureFailed(reason.to_owned())
  } else if text.strip_prefix("killed: ") is Some(reason) {
    Killed(reason.to_owned())
  } else {
    Unrecognized(text)
  }
}

///|
/// Only tool metadata is decoded: never command output or a description that
/// happens to resemble a brief. Tool identity selects the accepted grammar.
fn JobEvent::from_tool_brief(name : String, brief : String) -> JobEvent? {
  if name == "mbtx" {
    guard brief.strip_prefix("mbtx → bg ") is Some(id) && !id.is_blank() else {
      return None
    }
    Some(Backgrounded(id.to_owned()))
  } else if name == "job_output" {
    guard brief.strip_prefix("job ") is Some(rest) &&
      rest.split_once(" (") is Some((id, rest)) &&
      !id.is_blank() &&
      rest.split_once("): ") is Some((status, description)) &&
      !description.is_blank() else {
      return None
    }
    Some(
      OutputRead({
        id: id.to_owned(),
        description: description.to_owned(),
        status: JobStatus::parse(status.to_owned()),
      }),
    )
  } else {
    None
  }
}

///|
/// This is the one decoder for the engine's completion-notice text. Its
/// backtick envelope holds `description · command`, followed by instructions.
/// Keep malformed or unknown notices as plain text at the call site.
fn JobEvent::from_notice(text : String) -> JobEvent? {
  guard text.strip_prefix("background job ") is Some(rest) &&
    rest.split_once(" finished (") is Some((id, rest)) &&
    !id.is_blank() &&
    rest.split_once("): ") is Some((status, label)) else {
    return None
  }
  let status = JobStatus::parse(status.to_owned())
  if status is (Running | Unrecognized(_)) {
    return None
  }
  let description = if label.strip_prefix("`") is Some(rest) {
    guard rest.rev_split_once("` — read its output with job_output (")
      is Some((label, _)) else {
      return None
    }
    label.split_once(" · ").map_or(label.to_owned(), pair => pair.0.to_owned())
  } else {
    label.to_owned()
  }
  guard !description.is_blank() else { return None }
  Some(Finished({ id: id.to_owned(), description, status, }))
}
