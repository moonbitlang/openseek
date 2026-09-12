///|
/// The tracked execution's state. Interrupted means its owner disappeared;
/// it does not assert that every descendant process was terminated.
pub(all) enum JobState {
  Running
  Stopping
  Exited(Int)
  Stopped(String)
  Interrupted
} derive(Eq, Debug)

///|
pub(all) enum JobEventKind {
  Started
  Updated
  Finished
  Failed
} derive(Eq, Debug)

///|
pub(all) enum JobStopOutcome {
  Stopped
  AlreadyTerminal
  NotFound
  WrongRuntime
} derive(Eq, Debug)

///|
/// A durable background execution record. output_file is a basename relative
/// to jobs/<generation>; clients resolve its current host path via the store.
pub(all) struct JobRecord {
  generation : String
  id : String
  revision : Int
  command : String
  description : String?
  cwd : String?
  state : JobState
  started_at_ms : Int64
  backgrounded_at_ms : Int64
  finished_at_ms : Int64?
  last_output_at_ms : Int64?
  output_file : String?
  output_persistent : Bool
  output_bytes : Int64
  output_chars : Int
  output_truncated : Bool
  invalid_utf8 : Bool
  output_error : String?
  persistence_error : String?
  cleanup_error : String?
} derive(Eq, Debug)

///|
pub fn JobState::is_terminal(self : JobState) -> Bool {
  match self {
    Running | Stopping => false
    _ => true
  }
}

///|
pub impl ToJson for JobState with fn to_json(self) {
  match self {
    Running => { "kind": "running" }
    Stopping => { "kind": "stopping" }
    Exited(code) => { "kind": "exited", "code": code }
    Stopped(reason) => { "kind": "stopped", "reason": reason }
    Interrupted => { "kind": "interrupted" }
  }
}

///|
pub impl FromJson for JobState with fn from_json(json, path) {
  match json {
    { "kind": "running", .. } => Running
    { "kind": "stopping", .. } => Stopping
    { "kind": "interrupted", .. } => Interrupted
    { "kind": "stopped", "reason": String(reason), .. } if !reason.is_empty() =>
      Stopped(reason)
    { "kind": "exited", "code": Number(code, ..), .. } if code >= -2147483648.0 &&
      code <= 2147483647.0 &&
      code.to_int().to_double() == code => Exited(code.to_int())
    _ => raise JsonDecodeError((path, "invalid background job state"))
  }
}

///|
fn job_field(
  fields : Map[String, Json],
  name : String,
  path : @json.JsonPath,
) -> Json raise @json.JsonDecodeError {
  match fields.get(name) {
    Some(value) => value
    None => raise JsonDecodeError((path, "missing job field: " + name))
  }
}

///|
fn[T : FromJson] job_optional(
  fields : Map[String, Json],
  name : String,
  path : @json.JsonPath,
) -> T? raise @json.JsonDecodeError {
  match fields.get(name) {
    None | Some(Null) => None
    Some(value) => Some(T::from_json(value, path))
  }
}

///|
fn[T : ToJson] job_optional_json(value : T?) -> Json {
  match value {
    Some(value) => value.to_json()
    None => Json::null()
  }
}

///|
fn job_uint(
  fields : Map[String, Json],
  name : String,
  path : @json.JsonPath,
) -> Int64 raise @json.JsonDecodeError {
  match job_field(fields, name, path) {
    Number(value, ..) if value >= 0 &&
      value <= 9007199254740991.0 &&
      value.to_int64().to_double() == value => value.to_int64()
    _ =>
      raise JsonDecodeError((path, "invalid nonnegative job integer: " + name))
  }
}

///|
fn job_optional_uint(
  fields : Map[String, Json],
  name : String,
  path : @json.JsonPath,
) -> Int64? raise @json.JsonDecodeError {
  match fields.get(name) {
    None | Some(Null) => None
    Some(_) => Some(job_uint(fields, name, path))
  }
}

///|
/// An artifact component, never a path supplied by output text.
pub fn valid_job_component(value : String) -> Bool {
  !value.is_empty() &&
  value != "." &&
  value != ".." &&
  value.length() <= 200 &&
  value
  .iter()
  .all(c => {
    c is ('a'..='z' | 'A'..='Z' | '0'..='9') || c == '-' || c == '_' || c == '.'
  })
}

///|
pub impl ToJson for JobRecord with fn to_json(self) {
  {
    "schema_version": 1,
    "cleanup_error": job_optional_json(self.cleanup_error),
    "generation": self.generation.to_json(),
    "id": self.id.to_json(),
    "revision": self.revision.to_json(),
    "command": self.command.to_json(),
    "description": job_optional_json(self.description),
    "cwd": job_optional_json(self.cwd),
    "state": self.state.to_json(),
    "started_at_ms": self.started_at_ms.to_double().to_json(),
    "backgrounded_at_ms": self.backgrounded_at_ms.to_double().to_json(),
    "finished_at_ms": job_optional_json(
      self.finished_at_ms.map(value => value.to_double()),
    ),
    "last_output_at_ms": job_optional_json(
      self.last_output_at_ms.map(value => value.to_double()),
    ),
    "output_file": job_optional_json(self.output_file),
    "output_persistent": self.output_persistent.to_json(),
    "output_bytes": self.output_bytes.to_double().to_json(),
    "output_chars": self.output_chars.to_json(),
    "output_truncated": self.output_truncated.to_json(),
    "invalid_utf8": self.invalid_utf8.to_json(),
    "output_error": job_optional_json(self.output_error),
    "persistence_error": job_optional_json(self.persistence_error),
  }
}

///|
pub impl FromJson for JobRecord with fn from_json(json, path) {
  guard json is Object(fields) &&
    fields.get("schema_version") is Some(Number(1, ..)) else {
    raise JsonDecodeError((path, "expected background job schema version 1"))
  }
  let cleanup_error : String? = job_optional(fields, "cleanup_error", path)
  let generation : String = FromJson::from_json(
    job_field(fields, "generation", path),
    path,
  )
  let id : String = FromJson::from_json(job_field(fields, "id", path), path)
  let revision = job_uint(fields, "revision", path)
  let command : String = FromJson::from_json(
    job_field(fields, "command", path),
    path,
  )
  let description : String? = job_optional(fields, "description", path)
  let cwd : String? = job_optional(fields, "cwd", path)
  let state : JobState = FromJson::from_json(
    job_field(fields, "state", path),
    path,
  )
  let started_at_ms = job_uint(fields, "started_at_ms", path)
  let backgrounded_at_ms = job_uint(fields, "backgrounded_at_ms", path)
  let finished_at_ms : Int64? = job_optional_uint(
    fields, "finished_at_ms", path,
  )
  let last_output_at_ms : Int64? = job_optional_uint(
    fields, "last_output_at_ms", path,
  )
  let output_file : String? = job_optional(fields, "output_file", path)
  let output_persistent : Bool = FromJson::from_json(
    job_field(fields, "output_persistent", path),
    path,
  )
  let output_bytes = job_uint(fields, "output_bytes", path)
  let output_chars = job_uint(fields, "output_chars", path)
  let output_truncated : Bool = FromJson::from_json(
    job_field(fields, "output_truncated", path),
    path,
  )
  let invalid_utf8 : Bool = FromJson::from_json(
    job_field(fields, "invalid_utf8", path),
    path,
  )
  let output_error : String? = job_optional(fields, "output_error", path)
  let persistence_error : String? = job_optional(
    fields, "persistence_error", path,
  )
  guard valid_job_component(generation) &&
    valid_job_component(id) &&
    revision > 0 &&
    revision <= 2147483647L &&
    output_chars <= 2147483647L &&
    (match output_file {
      Some(file) => valid_job_component(file)
      None => true
    }) else {
    raise JsonDecodeError((path, "invalid background job identity or count"))
  }
  {
    generation,
    cleanup_error,
    id,
    revision: revision.to_int(),
    command,
    description,
    cwd,
    state,
    started_at_ms,
    backgrounded_at_ms,
    finished_at_ms,
    last_output_at_ms,
    output_file,
    output_persistent,
    output_bytes,
    output_chars: output_chars.to_int(),
    output_truncated,
    invalid_utf8,
    output_error,
    persistence_error,
  }
}

///|
pub extend JobState with Eq::{equal, not_equal}

///|
pub extend JobState with Debug::{to_repr}

///|
pub extend JobRecord with Eq::{equal, not_equal}

///|
pub extend JobRecord with Debug::{to_repr}

///|
pub extend JobEventKind with Eq::{equal, not_equal}

///|
pub extend JobEventKind with Debug::{to_repr}

///|
pub extend JobStopOutcome with Eq::{equal, not_equal}

///|
pub extend JobStopOutcome with Debug::{to_repr}

///|
pub impl ToJson for JobEventKind with fn to_json(self) {
  match self {
    Started => "started".to_json()
    Updated => "updated".to_json()
    Finished => "finished".to_json()
    Failed => "failed".to_json()
  }
}

///|
pub impl FromJson for JobEventKind with fn from_json(json, path) {
  match json {
    String("started") => Started
    String("updated") => Updated
    String("finished") => Finished
    String("failed") => Failed
    _ => raise JsonDecodeError((path, "invalid JobEventKind"))
  }
}

///|
pub impl ToJson for JobStopOutcome with fn to_json(self) {
  match self {
    Stopped => "stopped".to_json()
    AlreadyTerminal => "already_terminal".to_json()
    NotFound => "not_found".to_json()
    WrongRuntime => "wrong_runtime".to_json()
  }
}

///|
pub impl FromJson for JobStopOutcome with fn from_json(json, path) {
  match json {
    String("stopped") => Stopped
    String("already_terminal") => AlreadyTerminal
    String("not_found") => NotFound
    String("wrong_runtime") => WrongRuntime
    _ => raise JsonDecodeError((path, "invalid JobStopOutcome"))
  }
}

///|
pub extend JobRecord with ToJson::{to_json}

///|
pub extend JobState with ToJson::{to_json}

///|
pub extend JobEventKind with ToJson::{to_json}

///|
pub extend JobStopOutcome with ToJson::{to_json}

///|
pub extend JobState with FromJson::{from_json}

///|
pub extend JobRecord with FromJson::{from_json}

///|
pub extend JobEventKind with FromJson::{from_json}

///|
pub extend JobStopOutcome with FromJson::{from_json}
