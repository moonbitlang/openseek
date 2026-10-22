///|
pub(all) enum ControlRunStatus {
  Idle
  Running
  Stopping
} derive(Eq)

///|
pub impl FromJson for ControlRunStatus with fn from_json(json, path) {
  match json {
    String("idle") => Idle
    String("running") => Running
    String("stopping") => Stopping
    _ => raise @json.JsonDecodeError((path, "invalid control run status"))
  }
}

///|
pub(all) enum SteerStatus {
  Pending
  Applied
  Dropped
  Unknown
} derive(Eq)

///|
pub impl FromJson for SteerStatus with fn from_json(json, path) {
  match json {
    String("pending") => Pending
    String("applied") => Applied
    String("dropped") => Dropped
    String("unknown") => Unknown
    _ => raise @json.JsonDecodeError((path, "invalid steer status"))
  }
}

///|
pub(all) struct QueueEntry {
  id : String
  content : @wire.Content
} derive(Eq)

///|
pub impl FromJson for QueueEntry with fn from_json(json, path) {
  guard json is { "id": String(id), "content": content, .. } else {
    raise @json.JsonDecodeError((path, "expected queued input"))
  }
  { id, content: @json.from_json(content, path=path.add_key("content")), }
}

///|
pub(all) struct SteerReceipt {
  submission_id : String
  status : SteerStatus
} derive(Eq)

///|
pub impl FromJson for SteerReceipt with fn from_json(json, path) {
  guard json is { "submission_id": String(submission_id), "status": status, .. } else {
    raise @json.JsonDecodeError((path, "expected steer receipt"))
  }
  {
    submission_id,
    status: @json.from_json(status, path=path.add_key("status")),
  }
}

///|
pub(all) struct ControlState {
  active_task_id : String?
  status : ControlRunStatus
  paused : Bool
  queue : Array[QueueEntry]
  steers : Array[SteerReceipt]
} derive(Eq)

///|
fn control_task_id(
  json : Json,
  path : @json.JsonPath,
) -> String? raise @json.JsonDecodeError {
  match json {
    Null => None
    String(id) => Some(id)
    _ => raise @json.JsonDecodeError((path, "expected task id or null"))
  }
}

///|
pub impl FromJson for ControlState with fn from_json(json, path) {
  guard json
    is {
      "active_task_id": active_task,
      "status": status,
      "paused": paused,
      "queue": queue,
      "steers": steers,
      ..
    } else {
    raise @json.JsonDecodeError((path, "expected control state"))
  }
  {
    active_task_id: control_task_id(active_task, path.add_key("active_task_id")),
    status: @json.from_json(status, path=path.add_key("status")),
    paused: @json.from_json(paused, path=path.add_key("paused")),
    queue: @json.from_json(queue, path=path.add_key("queue")),
    steers: @json.from_json(steers, path=path.add_key("steers")),
  }
}

///|
pub(all) struct ControlSnapshot {
  session_id : String
  task_id : String?
  seq : Int32
  data : ControlState
} derive(Eq)

///|
pub impl FromJson for ControlSnapshot with fn from_json(json, path) {
  guard json
    is {
      "session_id": String(session_id),
      "task_id": task_id,
      "seq": Number(seq, ..),
      "data": data,
      ..
    } &&
    seq >= 0 &&
    seq == seq.to_int().to_double() else {
    raise @json.JsonDecodeError((path, "expected control snapshot"))
  }
  {
    session_id,
    task_id: control_task_id(task_id, path.add_key("task_id")),
    seq: seq.to_int(),
    data: @json.from_json(data, path=path.add_key("data")),
  }
}

///|
pub(all) enum ControlOperation {
  Stop
  Steer(submission_id~ : String, content~ : @wire.Content)
  QueueAdd(id~ : String, content~ : @wire.Content)
  QueueEdit(id~ : String, content~ : @wire.Content)
  QueueWithdraw(id~ : String)
  QueueSteer(id~ : String)
} derive(Eq)

///|
priv struct ControlRequest {
  task_id : String
  operation : ControlOperation
}

///|
impl ToJson for ControlRequest with fn to_json(self) {
  let task_id = self.task_id
  match self.operation {
    Stop => { "task_id": task_id }
    Steer(submission_id~, content~) =>
      {
        "task_id": task_id,
        "submission_id": submission_id,
        "content": content.to_json(),
      }
    QueueAdd(id~, content~) | QueueEdit(id~, content~) =>
      {
        "task_id": task_id,
        "action": self.operation.queue_action().unwrap(),
        "id": id,
        "content": content.to_json(),
      }
    QueueWithdraw(id~) | QueueSteer(id~) =>
      {
        "task_id": task_id,
        "action": self.operation.queue_action().unwrap(),
        "id": id,
      }
  }
}

///|
fn ControlOperation::queue_action(self : ControlOperation) -> String? {
  match self {
    QueueAdd(..) => Some("add")
    QueueEdit(..) => Some("edit")
    QueueWithdraw(..) => Some("withdraw")
    QueueSteer(..) => Some("steer")
    Stop | Steer(..) => None
  }
}

///|
pub(all) enum ControlResult {
  Accepted
  Rejected(String)
} derive(Eq)

///|
fn ControlOperation::decode_reply(
  self : ControlOperation,
  status : Int32,
  task : String,
  json : Json,
) -> ControlResult raise RequestError {
  if status == 409 {
    guard json
      is {
        "accepted": False,
        "error": String(error),
        "task_id": String(task_id),
        ..
      } &&
      task_id == task else {
      raise @cloud_client.RequestError(Malformed)
    }
    return Rejected(error)
  }
  guard json is { "accepted": True, "task_id": String(task_id), .. } &&
    task_id == task else {
    raise @cloud_client.RequestError(Malformed)
  }
  let valid = match self {
    Stop => status == 202
    Steer(submission_id~, ..) =>
      status == 202 &&
      json is { "submission_id": String(id), .. } &&
      id == submission_id
    QueueAdd(id~, ..)
    | QueueEdit(id~, ..)
    | QueueWithdraw(id~)
    | QueueSteer(id~) =>
      status == 200 &&
      json is { "action": String(action), "id": String(reply_id), .. } &&
      Some(action) == self.queue_action() &&
      reply_id == id
  }
  guard valid else { raise @cloud_client.RequestError(Malformed) }
  Accepted
}

///|
pub(all) enum ControlStreamEvent {
  Snapshot(ControlSnapshot)
  EngineEvent(Event)
} derive(Eq)

///|
fn decode_control_event(
  event_name : String,
  json : Json,
) -> ControlStreamEvent raise RequestError {
  if event_name is ("control_state" | "queue_changed") ||
    json is { "kind": String("queue_changed"), .. } {
    let snapshot : ControlSnapshot = @json.from_json(json) catch {
      _ => raise @cloud_client.RequestError(Malformed)
    }
    Snapshot(snapshot)
  } else {
    EngineEvent(decode_event(json))
  }
}

///|
pub extend ControlRunStatus with Eq::{equal, not_equal}

///|
pub extend ControlRunStatus with FromJson::{from_json}

///|
pub extend SteerStatus with Eq::{equal, not_equal}

///|
pub extend SteerStatus with FromJson::{from_json}

///|
pub extend QueueEntry with Eq::{equal, not_equal}

///|
pub extend QueueEntry with FromJson::{from_json}

///|
pub extend SteerReceipt with Eq::{equal, not_equal}

///|
pub extend SteerReceipt with FromJson::{from_json}

///|
pub extend ControlState with Eq::{equal, not_equal}

///|
pub extend ControlState with FromJson::{from_json}

///|
pub extend ControlSnapshot with Eq::{equal, not_equal}

///|
pub extend ControlSnapshot with FromJson::{from_json}

///|
pub extend ControlOperation with Eq::{equal, not_equal}

///|
pub extend ControlResult with Eq::{equal, not_equal}

///|
pub extend ControlStreamEvent with Eq::{equal, not_equal}
