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
    Some(_) => json_decode_error(path.add_key(key), "expected string")
    None => json_decode_error(path.add_key(key), "expected string")
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
    Some(_) => json_decode_error(path.add_key(key), "expected int")
    None => json_decode_error(path.add_key(key), "expected int")
  }
}

///|
/// Encode a `SessionId` as its raw string value.
///
/// No escaping beyond normal JSON string encoding is applied, and no filesystem
/// validation is performed here.
pub impl ToJson for SessionId with fn to_json(id : SessionId) -> Json {
  Json::string(id.value())
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
fn terminal_kind(terminal : TurnTerminal) -> String {
  match terminal {
    Finished(_) => "finished"
    Aborted(_) => "aborted"
    Interrupted(_) => "interrupted"
    Failed(_) => "failed"
  }
}

///|
fn terminal_message(terminal : TurnTerminal) -> String {
  match terminal {
    Finished(message)
    | Aborted(message)
    | Interrupted(message)
    | Failed(message) => message
  }
}

///|
/// Encode a terminal status as `{ "kind": ..., "message": ... }`.
///
/// `kind` is one of `finished`, `aborted`, `interrupted`, or `failed`. The
/// variant payload is stored in `message`.
pub impl ToJson for TurnTerminal with fn to_json(terminal : TurnTerminal) -> Json {
  { "kind": terminal_kind(terminal), "message": terminal_message(terminal) }
}

///|
/// Decode a terminal status from `{ "kind": ..., "message": ... }`.
///
/// Missing or non-string fields raise `JsonDecodeError`. Unknown `kind` values
/// also raise, so persisted data cannot silently turn into the wrong terminal
/// state.
pub impl FromJson for TurnTerminal with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> TurnTerminal {
  let fields = expect_object(json, path)
  let message = string_field(fields, path, "message")
  match string_field(fields, path, "kind") {
    "finished" => Finished(message)
    "aborted" => Aborted(message)
    "interrupted" => Interrupted(message)
    "failed" => Failed(message)
    other =>
      json_decode_error(path.add_key("kind"), "unknown terminal kind: \{other}")
  }
}

///|
fn item_payload(item : SessionItem) -> (String, Json) {
  match item {
    User(message) => ("user", message.to_json())
    Assistant(message) => ("assistant", message.to_json())
    Tool(result) => ("tool_result", result.to_json())
    Runtime(notice) => ("runtime_notice", notice.to_json())
    Summary(summary) => ("summary", summary.to_json())
    Terminal(terminal) => ("terminal", terminal.to_json())
  }
}

///|
/// Encode a `SessionItem` as a tagged payload object.
///
/// The JSON shape is `{ "kind": <tag>, "payload": <variant-json> }`. Tags are
/// stable storage strings such as `user`, `assistant`, `tool_result`,
/// `runtime_notice`, `summary`, and `terminal`.
pub impl ToJson for SessionItem with fn to_json(item : SessionItem) -> Json {
  let (kind, payload) = item_payload(item)
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
  let payload = match fields.get("payload") {
    Some(payload) => payload
    None => json_decode_error(path.add_key("payload"), "expected payload")
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
    "events": session.events().to_json(),
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
  let id : SessionId = match fields.get("id") {
    Some(id) => @json.from_json(id, path=path.add_key("id"))
    None => json_decode_error(path.add_key("id"), "expected id")
  }
  let events = match fields.get("events") {
    Some(Array(values)) => {
      let decoded : Array[SessionEvent] = []
      for index, value in values {
        decoded.push(
          @json.from_json(value, path=path.add_key("events").add_index(index)),
        )
      }
      @vector.from_array(decoded)
    }
    Some(_) =>
      json_decode_error(path.add_key("events"), "expected events array")
    None => @vector.new()
  }
  Session(
    id,
    system_prompt=string_field(fields, path, "system_prompt"),
    events~,
  )
}
