///|
pub enum ControlRunStatus {
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
pub enum SteerStatus {
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
pub struct QueueEntry {
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
pub struct SteerReceipt {
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
pub struct ControlState {
  active_task_id : String?
  status : ControlRunStatus
  paused : Bool
  queue : Array[QueueEntry]
  steers : Array[SteerReceipt]
  compact_queued : Bool
  compacting : Bool
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
    compact_queued: match json {
      Object(fields) if !fields.contains("compact_queued") => false
      Object(fields) =>
        @json.from_json(
          fields["compact_queued"],
          path=path.add_key("compact_queued"),
        )
      _ => false
    },
    compacting: match json {
      Object(fields) if !fields.contains("compacting") => false
      Object(fields) =>
        @json.from_json(fields["compacting"], path=path.add_key("compacting"))
      _ => false
    },
  }
}

///|
pub struct ControlSnapshot {
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
pub enum ControlOperation {
  Stop
  Steer(submission_id~ : String, content~ : @wire.Content)
  QueueAdd(id~ : String, content~ : @wire.Content)
  QueueEdit(id~ : String, content~ : @wire.Content)
  QueueWithdraw(id~ : String)
  QueueSteer(id~ : String)
} derive(Eq)

///|
priv struct CommandRequest {
  command : @wire.Command
  task_id : String?
  api_key : String?
}

///|
impl ToJson for CommandRequest with fn to_json(self) {
  let fields : Map[String, Json] = { "command": self.command.to_json() }
  if self.task_id is Some(task) {
    fields["task_id"] = Json(task)
  }
  if self.api_key is Some(key) {
    fields["api_key"] = Json(key)
  }
  Json(fields)
}

///|
priv struct QueueRequest {
  task_id : String
  action : String
  id : String
  content : @wire.Content?
}

///|
impl ToJson for QueueRequest with fn to_json(self) {
  let fields : Map[String, Json] = {
    "task_id": Json(self.task_id),
    "action": Json(self.action),
    "id": Json(self.id),
  }
  if self.content is Some(content) {
    fields["content"] = content.to_json()
  }
  Json(fields)
}

///|
pub enum ControlResult {
  Accepted
  Rejected(String)
} derive(Eq)

///|
fn QueueRequest::decode_reply(
  self : QueueRequest,
  status : Int32,
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
      task_id == self.task_id else {
      raise @cloud_client.RequestError(Malformed)
    }
    return Rejected(error)
  }
  guard json is { "accepted": True, "task_id": String(task_id), .. } &&
    task_id == self.task_id else {
    raise @cloud_client.RequestError(Malformed)
  }
  let valid = status == 200 &&
    json is { "action": String(action), "id": String(reply_id), .. } &&
    action == self.action &&
    reply_id == self.id
  guard valid else { raise @cloud_client.RequestError(Malformed) }
  Accepted
}

///|
pub enum ControlStreamEvent {
  Snapshot(ControlSnapshot)
  EngineEvent(Event)
  NativeEvent(EngineFrame)
  EngineFailed(session~ : String, seq~ : Int32, error~ : String)
} derive(Eq)

///|
/// Native events can arrive between tasks. Their payload is decoded by the
/// same OpenSeek parser as Local; the envelope owns only Cloud routing.
pub struct EngineFrame {
  session_id : String
  task_id : String?
  seq : Int32
  data : Json
} derive(Eq)

///|
impl FromJson for EngineFrame with fn from_json(json, path) {
  guard json
    is {
      "kind": "engine_event",
      "session_id": String(session_id),
      "task_id": task_id,
      "seq": Number(seq, ..),
      "data": Object(_) as data,
      ..
    } &&
    seq > 0 &&
    seq == seq.to_int().to_double() else {
    raise @json.JsonDecodeError((path, "expected native engine event"))
  }
  {
    session_id,
    task_id: control_task_id(task_id, path.add_key("task_id")),
    seq: seq.to_int(),
    data,
  }
}

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
  } else if json is { "kind": "engine_failed", .. } {
    guard json
      is {
        "session_id": String(session),
        "task_id": Null,
        "seq": Number(seq, ..),
        "data": { "error": String(error), .. },
        ..
      } &&
      seq > 0 &&
      seq == seq.to_int().to_double() else {
      raise @cloud_client.RequestError(Malformed)
    }
    EngineFailed(session~, seq=seq.to_int(), error~)
  } else if json is { "kind": "engine_event", .. } {
    NativeEvent(
      @json.from_json(json) catch {
        _ => raise @cloud_client.RequestError(Malformed)
      },
    )
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

///|
pub extend EngineFrame with Eq::{equal, not_equal}
