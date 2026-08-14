// Local schedules: required fields reject missing/null/malformed values.
// Optional fields accept missing/null and omit None when encoding.
// Unknown object fields are ignored; unknown enum tags are rejected.

///|
pub(all) enum ScheduleTiming {
  Once(Int64)
  Every(Int)
} derive(Eq, Debug)

///|
pub impl ToJson for ScheduleTiming with fn to_json(self) {
  match self {
    Once(at) => { "kind": "once", "at": at.to_double() }
    Every(minutes) => { "kind": "every", "minutes": minutes }
  }
}

///|
pub impl FromJson for ScheduleTiming with fn from_json(json, path) {
  let obj = JsonObject::decode(json, path, "ScheduleTiming")
  match obj.required_string("kind") {
    "once" => Once(jobs_uint(obj.required_json("at"), path.add_key("at")))
    "every" => {
      let minutes = jobs_uint(
        obj.required_json("minutes"),
        path.add_key("minutes"),
      )
      guard minutes >= 1 && minutes <= 525600 else {
        raise JsonDecodeError((path, "interval must be 1–525600 minutes"))
      }
      Every(minutes.to_int())
    }
    _ => raise JsonDecodeError((path, "unknown schedule timing"))
  }
}

///|
pub(all) enum ScheduleRunStatus {
  Running
  Succeeded
  Failed(String)
  Stopped
  TimedOut
  Interrupted
} derive(Eq, Debug)

///|
pub impl ToJson for ScheduleRunStatus with fn to_json(self) {
  match self {
    Running => { "kind": "running" }
    Succeeded => { "kind": "succeeded" }
    Failed(message) => { "kind": "failed", "message": message }
    Stopped => { "kind": "stopped" }
    TimedOut => { "kind": "timed_out" }
    Interrupted => { "kind": "interrupted" }
  }
}

///|
pub impl FromJson for ScheduleRunStatus with fn from_json(json, path) {
  let obj = JsonObject::decode(json, path, "ScheduleRunStatus")
  match obj.required_string("kind") {
    "running" => Running
    "succeeded" => Succeeded
    "failed" => Failed(obj.required_string("message"))
    "stopped" => Stopped
    "timed_out" => TimedOut
    "interrupted" => Interrupted
    _ => raise JsonDecodeError((path, "unknown schedule run status"))
  }
}

///|
pub(all) struct ScheduleSpec {
  name : String
  workspace : String?
  task : String
  model : String?
  timing : ScheduleTiming
  timeout_minutes : Int
} derive(Eq, Debug)

///|
pub impl FromJson for ScheduleSpec with fn from_json(json, path) {
  let obj = JsonObject::decode(json, path, "ScheduleSpec")
  let name : String = @json.from_json(
    obj.required_json("name"),
    path=path.add_key("name"),
  )
  let workspace : String? = match obj.optional_json("workspace") {
    None => None
    Some(value) => Some(@json.from_json(value, path=path.add_key("workspace")))
  }
  let task : String = @json.from_json(
    obj.required_json("task"),
    path=path.add_key("task"),
  )
  let model : String? = match obj.optional_json("model") {
    None => None
    Some(value) => Some(@json.from_json(value, path=path.add_key("model")))
  }
  let timing : ScheduleTiming = @json.from_json(
    obj.required_json("timing"),
    path=path.add_key("timing"),
  )
  let timeout_minutes : Int = @json.from_json(
    obj.required_json("timeout_minutes"),
    path=path.add_key("timeout_minutes"),
  )
  guard !name.trim().is_empty() &&
    (
      workspace is None ||
      (workspace is Some(value) && !value.trim().is_empty())
    ) &&
    !task.trim().is_empty() &&
    timeout_minutes >= 1 &&
    timeout_minutes <= 1440 else {
    raise JsonDecodeError(
      (
        path, "name, workspace and task are required; timeout must be 1–1440 minutes",
      ),
    )
  }
  { name, workspace, task, model, timing, timeout_minutes, }
}

///|
pub impl ToJson for ScheduleSpec with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["name"] = self.name.to_json()
  if self.workspace is Some(value) {
    fields["workspace"] = value.to_json()
  }
  fields["task"] = self.task.to_json()
  if self.model is Some(value) {
    fields["model"] = value.to_json()
  }
  fields["timing"] = self.timing.to_json()
  fields["timeout_minutes"] = self.timeout_minutes.to_json()
  fields.to_json()
}

///|
pub(all) struct ScheduleEntry {
  id : String
  spec : ScheduleSpec
  enabled : Bool
  run_requested : Bool
  notice : String?
  next_at : Int64?
} derive(Eq, Debug)

///|
pub impl FromJson for ScheduleEntry with fn from_json(json, path) {
  let obj = JsonObject::decode(json, path, "ScheduleEntry")
  let id : String = @json.from_json(
    obj.required_json("id"),
    path=path.add_key("id"),
  )
  let spec : ScheduleSpec = @json.from_json(
    obj.required_json("spec"),
    path=path.add_key("spec"),
  )
  let enabled : Bool = @json.from_json(
    obj.required_json("enabled"),
    path=path.add_key("enabled"),
  )
  let next_at : Int64? = match obj.optional_json("next_at") {
    None => None
    Some(value) => Some(jobs_uint(value, path.add_key("next_at")))
  }
  let run_requested : Bool = @json.from_json(
    obj.required_json("run_requested"),
    path=path.add_key("run_requested"),
  )
  let notice : String? = match obj.optional_json("notice") {
    None => None
    Some(value) => Some(@json.from_json(value, path=path.add_key("notice")))
  }
  { id, spec, enabled, run_requested, notice, next_at, }
}

///|
pub impl ToJson for ScheduleEntry with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["id"] = self.id.to_json()
  fields["spec"] = self.spec.to_json()
  fields["enabled"] = self.enabled.to_json()
  fields["run_requested"] = self.run_requested.to_json()
  if self.notice is Some(value) {
    fields["notice"] = value.to_json()
  }
  if self.next_at is Some(value) {
    fields["next_at"] = value.to_double().to_json()
  }
  fields.to_json()
}

///|
pub(all) struct ScheduleRun {
  id : String
  schedule_id : String
  name : String
  workspace : String
  session : String
  started_at : Int64
  finished_at : Int64?
  status : ScheduleRunStatus
  log_path : String
} derive(Eq, Debug)

///|
pub impl FromJson for ScheduleRun with fn from_json(json, path) {
  let obj = JsonObject::decode(json, path, "ScheduleRun")
  let id : String = @json.from_json(
    obj.required_json("id"),
    path=path.add_key("id"),
  )
  let schedule_id : String = @json.from_json(
    obj.required_json("schedule_id"),
    path=path.add_key("schedule_id"),
  )
  let name : String = @json.from_json(
    obj.required_json("name"),
    path=path.add_key("name"),
  )
  let workspace : String = @json.from_json(
    obj.required_json("workspace"),
    path=path.add_key("workspace"),
  )
  let session : String = @json.from_json(
    obj.required_json("session"),
    path=path.add_key("session"),
  )
  let started_at : Int64 = jobs_uint(
    obj.required_json("started_at"),
    path.add_key("started_at"),
  )
  let finished_at : Int64? = match obj.optional_json("finished_at") {
    None => None
    Some(value) => Some(jobs_uint(value, path.add_key("finished_at")))
  }
  let status : ScheduleRunStatus = @json.from_json(
    obj.required_json("status"),
    path=path.add_key("status"),
  )
  let log_path : String = @json.from_json(
    obj.required_json("log_path"),
    path=path.add_key("log_path"),
  )
  {
    id,
    schedule_id,
    name,
    workspace,
    session,
    started_at,
    finished_at,
    status,
    log_path,
  }
}

///|
pub impl ToJson for ScheduleRun with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["id"] = self.id.to_json()
  fields["schedule_id"] = self.schedule_id.to_json()
  fields["name"] = self.name.to_json()
  fields["workspace"] = self.workspace.to_json()
  fields["session"] = self.session.to_json()
  fields["started_at"] = self.started_at.to_double().to_json()
  if self.finished_at is Some(value) {
    fields["finished_at"] = value.to_double().to_json()
  }
  fields["status"] = self.status.to_json()
  fields["log_path"] = self.log_path.to_json()
  fields.to_json()
}

///|
pub(all) struct SchedulesReply {
  entries : Array[ScheduleEntry]
  runs : Array[ScheduleRun]
} derive(Eq, Debug)

///|
pub impl FromJson for SchedulesReply with fn from_json(json, path) {
  let obj = JsonObject::decode(json, path, "SchedulesReply")
  let entries : Array[ScheduleEntry] = @json.from_json(
    obj.required_json("entries"),
    path=path.add_key("entries"),
  )
  let runs : Array[ScheduleRun] = @json.from_json(
    obj.required_json("runs"),
    path=path.add_key("runs"),
  )
  { entries, runs, }
}

///|
pub impl ToJson for SchedulesReply with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["entries"] = self.entries.to_json()
  fields["runs"] = self.runs.to_json()
  fields.to_json()
}

///|
pub(all) struct ScheduleSavePayload {
  id : String?
  spec : ScheduleSpec
  run_now : Bool
} derive(Eq, Debug)

///|
pub impl FromJson for ScheduleSavePayload with fn from_json(json, path) {
  let obj = JsonObject::decode(json, path, "ScheduleSavePayload")
  let id : String? = match obj.optional_json("id") {
    None => None
    Some(value) => Some(@json.from_json(value, path=path.add_key("id")))
  }
  let spec : ScheduleSpec = @json.from_json(
    obj.required_json("spec"),
    path=path.add_key("spec"),
  )
  let run_now : Bool = @json.from_json(
    obj.required_json("run_now"),
    path=path.add_key("run_now"),
  )
  { id, spec, run_now, }
}

///|
pub impl ToJson for ScheduleSavePayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  if self.id is Some(value) {
    fields["id"] = value.to_json()
  }
  fields["spec"] = self.spec.to_json()
  fields["run_now"] = self.run_now.to_json()
  fields.to_json()
}

///|
pub(all) struct ScheduleActionPayload {
  id : String
  action : String
} derive(Eq, Debug)

///|
pub impl FromJson for ScheduleActionPayload with fn from_json(json, path) {
  let obj = JsonObject::decode(json, path, "ScheduleActionPayload")
  let id : String = @json.from_json(
    obj.required_json("id"),
    path=path.add_key("id"),
  )
  let action : String = @json.from_json(
    obj.required_json("action"),
    path=path.add_key("action"),
  )
  guard action is ("pause" | "resume" | "run" | "stop" | "delete") else {
    raise JsonDecodeError((path, "unknown schedule action"))
  }
  { id, action, }
}

///|
pub impl ToJson for ScheduleActionPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["id"] = self.id.to_json()
  fields["action"] = self.action.to_json()
  fields.to_json()
}

///|
pub extend ScheduleTiming with Eq::{equal, not_equal}

///|
pub extend ScheduleTiming with Debug::{to_repr}

///|
pub extend ScheduleTiming with ToJson::{to_json}

///|
pub extend ScheduleTiming with FromJson::{from_json}

///|
pub extend ScheduleRunStatus with Eq::{equal, not_equal}

///|
pub extend ScheduleRunStatus with Debug::{to_repr}

///|
pub extend ScheduleRunStatus with ToJson::{to_json}

///|
pub extend ScheduleRunStatus with FromJson::{from_json}

///|
pub extend ScheduleSpec with Eq::{equal, not_equal}

///|
pub extend ScheduleSpec with Debug::{to_repr}

///|
pub extend ScheduleSpec with ToJson::{to_json}

///|
pub extend ScheduleSpec with FromJson::{from_json}

///|
pub extend ScheduleEntry with Eq::{equal, not_equal}

///|
pub extend ScheduleEntry with Debug::{to_repr}

///|
pub extend ScheduleEntry with ToJson::{to_json}

///|
pub extend ScheduleEntry with FromJson::{from_json}

///|
pub extend ScheduleRun with Eq::{equal, not_equal}

///|
pub extend ScheduleRun with Debug::{to_repr}

///|
pub extend ScheduleRun with ToJson::{to_json}

///|
pub extend ScheduleRun with FromJson::{from_json}

///|
pub extend SchedulesReply with Eq::{equal, not_equal}

///|
pub extend SchedulesReply with Debug::{to_repr}

///|
pub extend SchedulesReply with ToJson::{to_json}

///|
pub extend SchedulesReply with FromJson::{from_json}

///|
pub extend ScheduleSavePayload with Eq::{equal, not_equal}

///|
pub extend ScheduleSavePayload with Debug::{to_repr}

///|
pub extend ScheduleSavePayload with ToJson::{to_json}

///|
pub extend ScheduleSavePayload with FromJson::{from_json}

///|
pub extend ScheduleActionPayload with Eq::{equal, not_equal}

///|
pub extend ScheduleActionPayload with Debug::{to_repr}

///|
pub extend ScheduleActionPayload with ToJson::{to_json}

///|
pub extend ScheduleActionPayload with FromJson::{from_json}
