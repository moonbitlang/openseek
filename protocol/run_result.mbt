///|
/// The result-file format version this module writes and reads.
pub const RunResultVersion : Int = 1

///|
/// How a one-shot `openseek run` ended. Only `Completed` means the task was
/// done; every other status is a run that stopped short, whatever it printed.
///
/// The statuses mirror how a turn can end in the session log, plus runs that
/// failed before their turn started (a missing API key, an unreachable
/// workspace), which are `Failed` too.
pub(all) enum RunStatus {
  /// The run finished. `output` is what it produced: `{"answer": String}`,
  /// the model's final message, for a general run; the preset's typed report
  /// for a `--kind` run.
  Completed(output~ : Json)
  /// A `--kind` run's turn finished without submitting the preset's report.
  /// The run did not fail, but it produced nothing the caller asked for.
  NoReport
  /// The turn filled the model's context window and was checkpointed. The work
  /// is not necessarily done; a new turn on the same session continues it.
  ContextYield(reason~ : String)
  /// The step budget ran out before the model finished.
  MaxStepsExhausted
  /// The agent stopped on purpose before finishing, e.g. a tool asked to abort.
  Aborted(reason~ : String)
  /// The run was cancelled from outside.
  Interrupted(reason~ : String)
  /// An error ended the run.
  Failed(reason~ : String)
} derive(Eq, Debug)

///|
/// What `openseek run --result-file PATH` writes to `PATH`: the one
/// authoritative account of how the run ended. See `docs/run-result.md` for
/// the file's lifecycle and the exact JSON.
pub(all) struct RunResult {
  /// The request's `request_id`, echoed; `None` when it carried none.
  request_id : String?
  /// The preset that ran; `None` for a general run.
  kind : String?
  status : RunStatus
  /// The durable session the run recorded to; `None` for `--no-session`.
  session : String?
  /// Token usage summed over the model responses of this run's turn; `None`
  /// when the run never reached its turn.
  usage : Usage?
  /// How many model responses this run's turn recorded; `None` when the run
  /// never reached its turn.
  steps : Int?
} derive(Eq, Debug)

///|
/// Why a JSON value is not a result this module can read.
pub(all) suberror RunResultError {
  /// A result from a newer (or unknown) format version.
  UnsupportedVersion(Int)
  /// A required field is missing or mistyped; names the field.
  Malformed(String)
} derive(Eq, Debug)

///|
pub impl ToJson for RunResult with fn to_json(self) {
  let fields : Map[String, Json] = { "version": RunResultVersion.to_json() }
  if self.request_id is Some(id) {
    fields["request_id"] = id.to_json()
  }
  if self.kind is Some(kind) {
    fields["kind"] = kind.to_json()
  }
  match self.status {
    Completed(output~) => {
      fields["status"] = "completed"
      fields["output"] = output
    }
    ContextYield(reason~) => {
      fields["status"] = "context_yield"
      fields["reason"] = reason.to_json()
    }
    NoReport => fields["status"] = "no_report"
    MaxStepsExhausted => fields["status"] = "max_steps_exhausted"
    Aborted(reason~) => {
      fields["status"] = "aborted"
      fields["reason"] = reason.to_json()
    }
    Interrupted(reason~) => {
      fields["status"] = "interrupted"
      fields["reason"] = reason.to_json()
    }
    Failed(reason~) => {
      fields["status"] = "failed"
      fields["reason"] = reason.to_json()
    }
  }
  if self.session is Some(session) {
    fields["session"] = session.to_json()
  }
  if self.usage is Some(usage) {
    fields["usage"] = usage.to_json()
  }
  if self.steps is Some(steps) {
    fields["steps"] = steps.to_json()
  }
  Json::object(fields)
}

///|
/// Read a result file's JSON back into a `RunResult`: the inverse of
/// `to_json`. Unknown fields are ignored, so a newer engine can add optional
/// fields without breaking this reader; an unknown `status` is `Malformed`,
/// because a reader that cannot classify a run must not guess.
pub fn parse_run_result(json : Json) -> RunResult raise RunResultError {
  guard json is Object(fields) else { raise Malformed("result") }
  guard int(fields, "version") is Some(version) else {
    raise Malformed("version")
  }
  guard version == RunResultVersion else { raise UnsupportedVersion(version) }
  fn required(key) raise RunResultError {
    guard text(fields, key) is Some(value) else { raise Malformed(key) }
    value
  }
  let status : RunStatus = match text(fields, "status") {
    Some("completed") =>
      match fields.get("output") {
        Some(output) => Completed(output~)
        None => raise Malformed("output")
      }
    Some("context_yield") => ContextYield(reason=required("reason"))
    Some("no_report") => NoReport
    Some("max_steps_exhausted") => MaxStepsExhausted
    Some("aborted") => Aborted(reason=required("reason"))
    Some("interrupted") => Interrupted(reason=required("reason"))
    Some("failed") => Failed(reason=required("reason"))
    _ => raise Malformed("status")
  }
  fn optional_text(key) raise RunResultError {
    match fields.get(key) {
      None => None
      Some(String(value)) => Some(value)
      Some(_) => raise Malformed(key)
    }
  }
  let request_id = optional_text("request_id")
  let kind = optional_text("kind")
  let session = match fields.get("session") {
    None => None
    Some(String(session)) => Some(session)
    Some(_) => raise Malformed("session")
  }
  let usage = match fields.get("usage") {
    None => None
    Some(Object(usage)) =>
      match usage_of(usage) {
        Some(usage) => Some(usage)
        None => raise Malformed("usage")
      }
    Some(_) => raise Malformed("usage")
  }
  let steps = match fields.get("steps") {
    None => None
    Some(_) =>
      match int(fields, "steps") {
        Some(steps) if steps >= 0 => Some(steps)
        _ => raise Malformed("steps")
      }
  }
  { request_id, kind, status, session, usage, steps, }
}

///|
pub extend RunStatus with Debug::{to_repr}

///|
pub extend RunStatus with Eq::{equal, not_equal}

///|
pub extend RunResult with Debug::{to_repr}

///|
pub extend RunResult with Eq::{equal, not_equal}

///|
pub extend RunResult with ToJson::{to_json}

///|
pub extend RunResultError with Debug::{to_repr}

///|
pub extend RunResultError with Eq::{equal, not_equal}
