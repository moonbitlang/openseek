// Local schedules: required fields reject missing/null/malformed values.
// Optional fields accept missing/null and omit None when encoding.
// Unknown object fields are ignored; unknown enum tags are rejected.

///|
#derive(Eq, Debug)
pub(all) enum ScheduleTiming {
  Once(Int64)
  Every(Int32)
}

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
#derive(Eq, Debug)
pub(all) enum ScheduleRunStatus {
  Running
  Succeeded
  Failed(String)
  Stopped
  TimedOut
  Interrupted
}

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
/// Why a due occurrence of a schedule did not launch.
#derive(Eq, Debug)
pub(all) enum ScheduleSkip {
  /// The schedule's previous run had not finished.
  PreviousRunActive
  /// Every execution slot was taken by other runs.
  CapacityFull
  /// The host was late by more than a minute, e.g. after sleep.
  MissedTime
  /// The host could not name the automatic working folder.
  AutomaticFolderUnavailable
}

///|
pub impl ToJson for ScheduleSkip with fn to_json(self) {
  match self {
    PreviousRunActive => "previous_run_active"
    CapacityFull => "capacity_full"
    MissedTime => "missed_time"
    AutomaticFolderUnavailable => "automatic_folder_unavailable"
  }
}

///|
pub impl FromJson for ScheduleSkip with fn from_json(json, path) {
  match json {
    "previous_run_active" => PreviousRunActive
    "capacity_full" => CapacityFull
    "missed_time" => MissedTime
    "automatic_folder_unavailable" => AutomaticFolderUnavailable
    _ => raise JsonDecodeError((path, "unknown schedule skip reason"))
  }
}

///|
#derive(Eq, Debug)
pub(all) enum ScheduleAction {
  Pause
  Resume
  Run
  Stop
  Delete
}

///|
pub impl ToJson for ScheduleAction with fn to_json(self) {
  match self {
    Pause => "pause"
    Resume => "resume"
    Run => "run"
    Stop => "stop"
    Delete => "delete"
  }
}

///|
pub impl FromJson for ScheduleAction with fn from_json(json, path) {
  match json {
    "pause" => Pause
    "resume" => Resume
    "run" => Run
    "stop" => Stop
    "delete" => Delete
    _ => raise JsonDecodeError((path, "unknown schedule action"))
  }
}

///|
/// Why the host declined a schedule change. Each is a state the user can
/// correct; failures to read or save the store stay on the error channel.
#derive(Eq, Debug)
pub(all) enum ScheduleRefusal {
  /// Another host on this computer owns the schedules.
  ForeignOwner
  /// The schedule was deleted, e.g. from another window.
  Missing
  /// The chosen project is not attached to this host.
  UnattachedProject
  /// A one-time schedule's time has already passed.
  PastTime
  /// A run of this schedule is in progress.
  AlreadyRunning
  /// A Run now request for this schedule is waiting for a slot.
  AlreadyQueued
  /// A schedule cannot be deleted while it runs.
  StopBeforeDelete
}

///|
pub impl ToJson for ScheduleRefusal with fn to_json(self) {
  match self {
    ForeignOwner => "foreign_owner"
    Missing => "missing"
    UnattachedProject => "unattached_project"
    PastTime => "past_time"
    AlreadyRunning => "already_running"
    AlreadyQueued => "already_queued"
    StopBeforeDelete => "stop_before_delete"
  }
}

///|
pub impl FromJson for ScheduleRefusal with fn from_json(json, path) {
  match json {
    "foreign_owner" => ForeignOwner
    "missing" => Missing
    "unattached_project" => UnattachedProject
    "past_time" => PastTime
    "already_running" => AlreadyRunning
    "already_queued" => AlreadyQueued
    "stop_before_delete" => StopBeforeDelete
    _ => raise JsonDecodeError((path, "unknown schedule refusal"))
  }
}

///|
/// The reply to `schedules.save` and `schedules.action`.
#derive(Eq, Debug)
pub(all) enum ScheduleChangeReply {
  Changed(SchedulesReply)
  Refused(ScheduleRefusal)
}

///|
pub impl ToJson for ScheduleChangeReply with fn to_json(self) {
  match self {
    Changed(state) => { "status": "changed", "state": state.to_json() }
    Refused(reason) => { "status": "refused", "reason": reason.to_json() }
  }
}

///|
pub impl FromJson for ScheduleChangeReply with fn from_json(json, path) {
  let obj = JsonObject::decode(json, path, "ScheduleChangeReply")
  match obj.required_string("status") {
    "changed" =>
      Changed(
        @json.from_json(obj.required_json("state"), path=path.add_key("state")),
      )
    "refused" =>
      Refused(
        @json.from_json(
          obj.required_json("reason"),
          path=path.add_key("reason"),
        ),
      )
    _ => raise JsonDecodeError((path, "unknown schedule change status"))
  }
}

///|
#derive(Eq, Debug)
pub(all) struct ScheduleSpec {
  name : String
  workspace : String?
  task : String
  model : String?
  timing : ScheduleTiming
  timeout_minutes : Int32
}

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
  let timeout_minutes : Int32 = @json.from_json(
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
  fields["name"] = Json(self.name)
  if self.workspace is Some(value) {
    fields["workspace"] = Json(value)
  }
  fields["task"] = Json(self.task)
  if self.model is Some(value) {
    fields["model"] = Json(value)
  }
  fields["timing"] = self.timing.to_json()
  fields["timeout_minutes"] = Json(self.timeout_minutes)
  Json(fields)
}

///|
#derive(Eq, Debug)
pub(all) struct ScheduleEntry {
  id : String
  spec : ScheduleSpec
  enabled : Bool
  run_requested : Bool
  // Why the most recent occurrence did not launch, until the next one does.
  skipped : ScheduleSkip?
  next_at : Int64?
}

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
  // A store saved before `skipped` existed carries a free-text `notice`,
  // which decoding ignores like any unknown field.
  let skipped : ScheduleSkip? = match obj.optional_json("skipped") {
    None => None
    Some(value) => Some(@json.from_json(value, path=path.add_key("skipped")))
  }
  { id, spec, enabled, run_requested, skipped, next_at, }
}

///|
pub impl ToJson for ScheduleEntry with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["id"] = Json(self.id)
  fields["spec"] = self.spec.to_json()
  fields["enabled"] = Json(self.enabled)
  fields["run_requested"] = Json(self.run_requested)
  if self.skipped is Some(value) {
    fields["skipped"] = value.to_json()
  }
  if self.next_at is Some(value) {
    fields["next_at"] = Json(value.to_double())
  }
  Json(fields)
}

///|
#derive(Eq, Debug)
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
}

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
  fields["id"] = Json(self.id)
  fields["schedule_id"] = Json(self.schedule_id)
  fields["name"] = Json(self.name)
  fields["workspace"] = Json(self.workspace)
  fields["session"] = Json(self.session)
  fields["started_at"] = Json(self.started_at.to_double())
  if self.finished_at is Some(value) {
    fields["finished_at"] = Json(value.to_double())
  }
  fields["status"] = self.status.to_json()
  fields["log_path"] = Json(self.log_path)
  Json(fields)
}

///|
#derive(Eq, Debug)
pub(all) struct SchedulesReply {
  entries : Array[ScheduleEntry]
  runs : Array[ScheduleRun]
}

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
  fields["entries"] = Json(self.entries)
  fields["runs"] = Json(self.runs)
  Json(fields)
}

///|
#derive(Eq, Debug)
pub(all) struct ScheduleSavePayload {
  id : String?
  spec : ScheduleSpec
  run_now : Bool
}

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
    fields["id"] = Json(value)
  }
  fields["spec"] = self.spec.to_json()
  fields["run_now"] = Json(self.run_now)
  Json(fields)
}

///|
#derive(Eq, Debug)
pub(all) struct ScheduleActionPayload {
  id : String
  action : ScheduleAction
}

///|
pub impl FromJson for ScheduleActionPayload with fn from_json(json, path) {
  let obj = JsonObject::decode(json, path, "ScheduleActionPayload")
  let id : String = @json.from_json(
    obj.required_json("id"),
    path=path.add_key("id"),
  )
  let action : ScheduleAction = @json.from_json(
    obj.required_json("action"),
    path=path.add_key("action"),
  )
  { id, action, }
}

///|
pub impl ToJson for ScheduleActionPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["id"] = Json(self.id)
  fields["action"] = self.action.to_json()
  Json(fields)
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

///|
pub extend ScheduleSkip with Eq::{equal, not_equal}

///|
pub extend ScheduleSkip with Debug::{to_repr}

///|
pub extend ScheduleSkip with ToJson::{to_json}

///|
pub extend ScheduleSkip with FromJson::{from_json}

///|
pub extend ScheduleAction with Eq::{equal, not_equal}

///|
pub extend ScheduleAction with Debug::{to_repr}

///|
pub extend ScheduleAction with ToJson::{to_json}

///|
pub extend ScheduleAction with FromJson::{from_json}

///|
pub extend ScheduleRefusal with Eq::{equal, not_equal}

///|
pub extend ScheduleRefusal with Debug::{to_repr}

///|
pub extend ScheduleRefusal with ToJson::{to_json}

///|
pub extend ScheduleRefusal with FromJson::{from_json}

///|
pub extend ScheduleChangeReply with Eq::{equal, not_equal}

///|
pub extend ScheduleChangeReply with Debug::{to_repr}

///|
pub extend ScheduleChangeReply with ToJson::{to_json}

///|
pub extend ScheduleChangeReply with FromJson::{from_json}
