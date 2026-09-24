///|
fn[T] json_decode_error(
  path : @json.JsonPath,
  message : String,
) -> T raise @json.JsonDecodeError {
  raise JsonDecodeError((path, message))
}

///|
fn expect_object(
  json : Json,
  path : @json.JsonPath,
) -> Map[String, Json] raise @json.JsonDecodeError {
  match json {
    Object(fields) => fields
    _ => json_decode_error(path, "expected object")
  }
}

///|
fn string_field(
  fields : Map[String, Json],
  path : @json.JsonPath,
  key : String,
) -> String raise @json.JsonDecodeError {
  match fields.get(key) {
    Some(String(value)) => value
    _ => json_decode_error(path.add_key(key), "expected string")
  }
}

///|
fn int_field(
  fields : Map[String, Json],
  path : @json.JsonPath,
  key : String,
) -> Int raise @json.JsonDecodeError {
  match fields.get(key) {
    Some(Number(value, ..)) => value.to_int()
    _ => json_decode_error(path.add_key(key), "expected int")
  }
}

///|
/// Encode a `SessionId` as its raw string value.
///
/// No escaping beyond normal JSON string encoding is applied, and no filesystem
/// validation is performed here.
impl ToJson for SessionId with fn to_json(id : SessionId) -> Json {
  Json(id.value())
}

///|
/// Decode a `SessionId` from a JSON string.
///
/// Non-string JSON raises `JsonDecodeError`. The decoded id is not normalized or
/// checked for store path safety.
pub impl FromJson for SessionId with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> SessionId {
  match json {
    String(value) => SessionId(value)
    _ => json_decode_error(path, "SessionId: expected string")
  }
}

///|
/// Encode a terminal status as `{ "kind": ..., "message": ... }`.
///
/// `kind` is one of `finished`, `context_yield`, `aborted`, `interrupted`,
/// `max_steps_exhausted`, or `failed`. The variant payload is stored in
/// `message`; `max_steps_exhausted` has none. A `finished` or `failed`
/// message that reads like an older yield or step-exhaustion encoding is
/// marked `"verbatim": true`, so it decodes back unchanged.
impl ToJson for TurnTerminal with fn to_json(terminal : TurnTerminal) -> Json {
  match terminal {
    Finished(message) if message.has_prefix(ContextYieldAnswerPrefix) =>
      { "kind": "finished", "message": message, "verbatim": true }
    Finished(message) => { "kind": "finished", "message": message }
    ContextYield(message) => { "kind": "context_yield", "message": message }
    Aborted(message) => { "kind": "aborted", "message": message }
    Interrupted(message) => { "kind": "interrupted", "message": message }
    MaxStepsExhausted => { "kind": "max_steps_exhausted" }
    Failed(message) if message == MaxStepsExhaustedMessage =>
      { "kind": "failed", "message": message, "verbatim": true }
    Failed(message) => { "kind": "failed", "message": message }
  }
}

///|
/// Decode a terminal status from `{ "kind": ..., "message": ... }`.
///
/// Older logs had no `context_yield` or `max_steps_exhausted` kinds: they
/// saved a yield as `finished` with a `ContextYieldAnswerPrefix` message and
/// step exhaustion as `failed` with `"max steps exhausted"`. Both still decode
/// to the dedicated variants, unless the line is marked `"verbatim": true`:
/// current builds mark a real answer or failure that happens to read that way.
///
/// Missing or non-string fields raise `JsonDecodeError`. Unknown `kind` values
/// also raise, so persisted data cannot silently turn into the wrong terminal
/// state.
pub impl FromJson for TurnTerminal with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> TurnTerminal {
  let fields = expect_object(json, path)
  let message = () => string_field(fields, path, "message")
  let verbatim = match fields.get("verbatim") {
    None | Some(False) => false
    Some(True) => true
    Some(_) => json_decode_error(path.add_key("verbatim"), "expected bool")
  }
  match string_field(fields, path, "kind") {
    "finished" =>
      match message() {
        answer if !verbatim && answer.has_prefix(ContextYieldAnswerPrefix) =>
          ContextYield(answer)
        answer => Finished(answer)
      }
    "context_yield" => ContextYield(message())
    "aborted" => Aborted(message())
    "interrupted" => Interrupted(message())
    "max_steps_exhausted" => MaxStepsExhausted
    "failed" =>
      match message() {
        MaxStepsExhaustedMessage if !verbatim => MaxStepsExhausted
        failure => Failed(failure)
      }
    other =>
      json_decode_error(path.add_key("kind"), "unknown terminal kind: \{other}")
  }
}

///|
/// Encode a `SessionItem` as a tagged payload object.
///
/// The JSON shape is `{ "kind": <tag>, "payload": <variant-json> }`. Tags are
/// stable storage strings such as `user`, `assistant`, `tool_result`,
/// `runtime_notice`, `summary`, and `terminal`.
impl ToJson for SessionItem with fn to_json(item : SessionItem) -> Json {
  let (kind, payload) = match item {
    User(message) => ("user", ToJson::to_json(message))
    Assistant(message) => ("assistant", ToJson::to_json(message))
    Tool(result) => ("tool_result", ToJson::to_json(result))
    Runtime(notice) => ("runtime_notice", ToJson::to_json(notice))
    Summary(summary) => ("summary", ToJson::to_json(summary))
    Terminal(terminal) => ("terminal", ToJson::to_json(terminal))
  }
  { "kind": kind, "payload": payload }
}

///|
/// Decode a tagged `SessionItem`.
///
/// The decoder requires both `kind` and `payload`. Unknown tags raise
/// `JsonDecodeError`; they are not ignored because the event log must replay to
/// the exact durable event vocabulary understood by this package.
pub impl FromJson for SessionItem with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> SessionItem {
  let fields = expect_object(json, path)
  let payload = match fields {
    { "payload": payload, .. } => payload
    _ => json_decode_error(path.add_key("payload"), "expected payload")
  }
  match string_field(fields, path, "kind") {
    "user" => User(@json.from_json(payload, path=path.add_key("payload")))
    "assistant" =>
      Assistant(@json.from_json(payload, path=path.add_key("payload")))
    "tool_result" =>
      Tool(@json.from_json(payload, path=path.add_key("payload")))
    "runtime_notice" =>
      Runtime(@json.from_json(payload, path=path.add_key("payload")))
    "summary" => Summary(@json.from_json(payload, path=path.add_key("payload")))
    "terminal" =>
      Terminal(@json.from_json(payload, path=path.add_key("payload")))
    other =>
      json_decode_error(
        path.add_key("kind"),
        "unknown session item kind: \{other}",
      )
  }
}

///|
/// Encode a complete `Session` snapshot.
///
/// The JSON shape is versioned and contains `id`, `system_prompt`, and the
/// complete `events` vector. `last_sequence` is intentionally not stored; it is
/// recomputed by `Session::Session` from event sequence numbers when decoded.
pub impl ToJson for Session with fn to_json(session : Session) -> Json {
  {
    "version": 1,
    "id": session.id(),
    "system_prompt": session.system_prompt(),
    "events": @json.to_json(session.events()),
  }
}

///|
/// Decode a complete `Session` snapshot.
///
/// Only version `1` is accepted. Missing `events` is treated as an empty event
/// log for compatibility with older or minimal snapshots. Event order is kept
/// exactly as encoded; the constructor recomputes `last_sequence` from the
/// highest event sequence but does not validate contiguity.
pub impl FromJson for Session with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> Session {
  let fields = expect_object(json, path)
  match int_field(fields, path, "version") {
    1 => ()
    other =>
      json_decode_error(
        path.add_key("version"),
        "unsupported session version: \{other}",
      )
  }
  let id : SessionId = match fields {
    { "id": id, .. } => @json.from_json(id, path=path.add_key("id"))
    _ => json_decode_error(path.add_key("id"), "expected id")
  }
  let events = match fields {
    { "events": Array(values), .. } => {
      let decoded : Array[SessionEvent] = [
        for index, value in values => {
          @json.from_json(value, path=path.add_key("events").add_index(index))
        }
      ]
      @vector.from_array(decoded)
    }
    { "events": _, .. } =>
      json_decode_error(path.add_key("events"), "expected events array")
    _ => @vector.new()
  }
  Session(
    id,
    system_prompt=string_field(fields, path, "system_prompt"),
    events~,
  )
}

///|
#doc(hidden)
#deprecated
pub extend Session with FromJson::{from_json}

///|
#doc(hidden)
#deprecated
pub extend Session with ToJson::{to_json}

///|
#doc(hidden)
#deprecated
pub extend SessionId with FromJson::{from_json}

///|
#doc(hidden)
#deprecated
pub extend SessionItem with FromJson::{from_json}

///|
#doc(hidden)
#deprecated
pub extend TurnTerminal with FromJson::{from_json}
