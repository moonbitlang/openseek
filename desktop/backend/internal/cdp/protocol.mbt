// Only the CDP subset used by the desktop browser. Unknown response fields
// and unrelated events are ignored; malformed supported fields are errors.

///|
pub suberror CDPError {
  Protocol(String)
  CommandFailed(code~ : Int, message~ : String, data~ : Json?)
  JavaScriptException(String)
  MissingValue
  ConcurrentRead
} derive(Debug)

///|
fn field(json : Json, key : String) -> Json? raise {
  guard json is Object(fields) else { raise Protocol("Expected a CDP object") }
  fields.get(key)
}

///|
fn[T : @json.FromJson] required(json : Json, key : String) -> T raise {
  guard field(json, key) is Some(value) else {
    raise Protocol("Missing CDP field: \{key}")
  }
  @json.from_json(value)
}

///|
fn[T : @json.FromJson] optional(json : Json, key : String) -> T? raise {
  match field(json, key) {
    None => None
    Some(value) => Some(@json.from_json(value))
  }
}

///|
pub struct BackendNodeId(Int) derive(Debug, Eq)

///|
pub struct RemoteObjectId(String) derive(Debug, Eq)

///|
/// The value is dynamic because JavaScript can return any JSON value.
/// Missing value (undefined, by-reference or unserializable) differs from null.
pub struct RemoteObject {
  object_id : RemoteObjectId?
  value : Json?
} derive(Debug, Eq)

///|
fn decode_remote_object(json : Json) -> RemoteObject raise {
  // `type` is required even when the caller only needs the value or handle.
  let _ : String = required(json, "type")
  let object_id : String? = optional(json, "objectId")
  {
    object_id: object_id.map(id => RemoteObjectId(id)),
    value: field(json, "value"),
  }
}

///|
pub struct Evaluation {
  result : RemoteObject
  exception : String?
} derive(Debug, Eq)

///|
fn decode_evaluation(json : Json) -> Evaluation raise {
  let exception = match field(json, "exceptionDetails") {
    None => None
    Some(details) => Some(required(details, "text"))
  }
  { result: decode_remote_object(required(json, "result")), exception, }
}

///|
pub fn[T : @json.FromJson] Evaluation::decode_value(
  self : Evaluation,
) -> T raise {
  if self.exception is Some(message) {
    raise JavaScriptException(message)
  }
  guard self.result.value is Some(value) else { raise MissingValue }
  @json.from_json(value)
}

///|
pub(all) enum Event {
  InspectNodeRequested(BackendNodeId)
  InspectModeCanceled
  BindingCalled(name~ : String, payload~ : String, execution_context_id~ : Int)
} derive(Debug, Eq)

///|
fn decode_event(json : Json) -> Event? raise {
  let method_ : String = required(json, "method")
  match method_ {
    "Overlay.inspectNodeRequested" => {
      let params : Json = required(json, "params")
      Some(
        InspectNodeRequested(BackendNodeId(required(params, "backendNodeId"))),
      )
    }
    "Overlay.inspectModeCanceled" => Some(InspectModeCanceled)
    "Runtime.bindingCalled" => {
      let params : Json = required(json, "params")
      Some(
        BindingCalled(
          name=required(params, "name"),
          payload=required(params, "payload"),
          execution_context_id=required(params, "executionContextId"),
        ),
      )
    }
    _ => None
  }
}

///|
priv enum Incoming {
  Reply(Int, Result[Json, CDPError])
  Notification(Event?)
}

///|
fn decode_incoming(json : Json) -> Incoming raise {
  if field(json, "id") is Some(_) {
    let id : Int = required(json, "id")
    if field(json, "error") is Some(error) {
      return Reply(
        id,
        Err(
          CommandFailed(
            code=required(error, "code"),
            message=required(error, "message"),
            data=field(error, "data"),
          ),
        ),
      )
    }
    Reply(id, Ok(required(json, "result")))
  } else {
    Notification(decode_event(json))
  }
}

///|
pub extend BackendNodeId with Debug::{to_repr}

///|
pub extend BackendNodeId with Eq::{equal, not_equal}

///|
pub extend RemoteObjectId with Debug::{to_repr}

///|
pub extend RemoteObjectId with Eq::{equal, not_equal}

///|
pub extend RemoteObject with Debug::{to_repr}

///|
pub extend RemoteObject with Eq::{equal, not_equal}

///|
pub extend Evaluation with Debug::{to_repr}

///|
pub extend Evaluation with Eq::{equal, not_equal}

///|
pub extend Event with Debug::{to_repr}

///|
pub extend Event with Eq::{equal, not_equal}

///|
pub extend CDPError with Debug::{to_repr}
