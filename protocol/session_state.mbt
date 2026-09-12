///|
/// Durable session snapshots and JSONL headers use this schema.
pub const SessionFormatVersion : Int = 2

///|
/// Origin of a model input, independent of its display text.
pub(all) enum InputOrigin {
  Human
  Command
  AutoContinue
  Delegated
} derive(Eq, Debug)

///|
pub impl ToJson for InputOrigin with fn to_json(self : InputOrigin) -> Json {
  Json(
    match self {
      Human => "human"
      Command => "command"
      AutoContinue => "auto_continue"
      Delegated => "delegated"
    },
  )
}

///|
pub impl FromJson for InputOrigin with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> InputOrigin {
  match json {
    String("human") => Human
    String("command") => Command
    String("auto_continue") => AutoContinue
    String("delegated") => Delegated
    _ => state_decode_error(path, "invalid input origin")
  }
}

///|
/// Advisory workspace anchor captured when the goal command arrives.
pub(all) struct GoalBaseline {
  sha : String
  dirty : Bool
} derive(Eq, Debug, ToJson, FromJson)

///|
pub(all) enum GoalBaselineState {
  Captured(GoalBaseline)
  Unavailable
} derive(Eq, Debug)

///|
/// A goal and its baseline are one atomic durable operation.
pub(all) enum GoalChange {
  GoalSet(String, baseline~ : GoalBaselineState)
  GoalCleared
  GoalBlocked(String)
  GoalUnblocked
} derive(Eq, Debug)

///|
/// Presentation codec: these words are model input, never state identifiers.
pub fn GoalChange::model_content(self : GoalChange) -> String {
  match self {
    GoalSet(text, ..) => "[goal]\n\{text}"
    GoalCleared => "[goal cleared]"
    GoalBlocked(reason) => "[goal blocked]\n\{reason}"
    GoalUnblocked => "[goal unblocked]"
  }
}

///|
pub impl ToJson for GoalChange with fn to_json(self : GoalChange) -> Json {
  match self {
    GoalSet(text, baseline~) =>
      { "kind": "set", "text": text, "baseline": baseline }
    GoalCleared => { "kind": "cleared" }
    GoalBlocked(reason) => { "kind": "blocked", "reason": reason }
    GoalUnblocked => { "kind": "unblocked" }
  }
}

///|
pub impl FromJson for GoalChange with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> GoalChange {
  let fields = state_object(json, path)
  match state_string(fields, path, "kind") {
    "set" => {
      let baseline : GoalBaselineState = match fields.get("baseline") {
        Some(value) => @json.from_json(value, path=path.add_key("baseline"))
        None =>
          state_decode_error(path.add_key("baseline"), "expected baseline")
      }
      GoalSet(state_string(fields, path, "text"), baseline~)
    }
    "cleared" => GoalCleared
    "blocked" => GoalBlocked(state_string(fields, path, "reason"))
    "unblocked" => GoalUnblocked
    _ => state_decode_error(path.add_key("kind"), "invalid goal change")
  }
}

///|
/// Normal completion and context exhaustion are distinct even if their text matches.
pub(all) enum TurnTerminal {
  Finished(String)
  ContextYield(String)
  Aborted(String)
  Interrupted(String)
  Failed(String)
} derive(Eq, Debug)

///|
/// Encode a terminal status as `{ "kind": ..., "message": ... }`.
///
/// `kind` is one of `finished`, `aborted`, `interrupted`, or `failed`. The
/// variant payload is stored in `message`.
pub impl ToJson for TurnTerminal with fn to_json(terminal : TurnTerminal) -> Json {
  let (kind, message) = match terminal {
    Finished(message) => ("finished", message)
    ContextYield(message) => ("context_yield", message)
    Aborted(message) => ("aborted", message)
    Interrupted(message) => ("interrupted", message)
    Failed(message) => ("failed", message)
  }
  { "kind": kind, "message": message }
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
  let fields = state_object(json, path)
  let message = state_string(fields, path, "message")
  match state_string(fields, path, "kind") {
    "context_yield" => ContextYield(message)
    "finished" => Finished(message)
    "aborted" => Aborted(message)
    "interrupted" => Interrupted(message)
    "failed" => Failed(message)
    other =>
      state_decode_error(
        path.add_key("kind"),
        "unknown terminal kind: \{other}",
      )
  }
}

///|
fn[T] state_decode_error(
  path : @json.JsonPath,
  message : String,
) -> T raise @json.JsonDecodeError {
  raise JsonDecodeError((path, message))
}

///|
fn state_object(
  json : Json,
  path : @json.JsonPath,
) -> Map[String, Json] raise @json.JsonDecodeError {
  match json {
    Object(fields) => fields
    _ => state_decode_error(path, "expected object")
  }
}

///|
fn state_string(
  fields : Map[String, Json],
  path : @json.JsonPath,
  key : String,
) -> String raise @json.JsonDecodeError {
  match fields.get(key) {
    Some(String(value)) => value
    _ => state_decode_error(path.add_key(key), "expected string")
  }
}

///|
#doc(hidden)
#deprecated
pub extend InputOrigin with Eq::{equal, not_equal}

///|
#doc(hidden)
#deprecated
pub extend InputOrigin with Debug::{to_repr}

///|
#doc(hidden)
#deprecated
pub extend InputOrigin with ToJson::{to_json}

///|
#doc(hidden)
#deprecated
pub extend InputOrigin with FromJson::{from_json}

///|
#doc(hidden)
#deprecated
pub extend GoalBaseline with Eq::{equal, not_equal}

///|
#doc(hidden)
#deprecated
pub extend GoalBaseline with Debug::{to_repr}

///|
#doc(hidden)
#deprecated
pub extend GoalBaseline with ToJson::{to_json}

///|
#doc(hidden)
#deprecated
pub extend GoalBaseline with FromJson::{from_json}

///|
#doc(hidden)
#deprecated
pub extend GoalBaselineState with Eq::{equal, not_equal}

///|
#doc(hidden)
#deprecated
pub extend GoalBaselineState with Debug::{to_repr}

///|
#doc(hidden)
#deprecated
pub extend GoalBaselineState with ToJson::{to_json}

///|
#doc(hidden)
#deprecated
pub extend GoalBaselineState with FromJson::{from_json}

///|
#doc(hidden)
#deprecated
pub extend GoalChange with Eq::{equal, not_equal}

///|
#doc(hidden)
#deprecated
pub extend GoalChange with Debug::{to_repr}

///|
#doc(hidden)
#deprecated
pub extend GoalChange with ToJson::{to_json}

///|
#doc(hidden)
#deprecated
pub extend GoalChange with FromJson::{from_json}

///|
#doc(hidden)
#deprecated
pub extend TurnTerminal with Eq::{equal, not_equal}

///|
#doc(hidden)
#deprecated
pub extend TurnTerminal with Debug::{to_repr}

///|
#doc(hidden)
#deprecated
pub extend TurnTerminal with ToJson::{to_json}

///|
#doc(hidden)
#deprecated
pub extend TurnTerminal with FromJson::{from_json}

///|
pub impl ToJson for GoalBaselineState with fn to_json(self) {
  match self {
    Captured(value) =>
      { "kind": "captured", "sha": value.sha, "dirty": value.dirty }
    Unavailable => { "kind": "unavailable" }
  }
}

///|
pub impl FromJson for GoalBaselineState with fn from_json(json, path) {
  let fields = state_object(json, path)
  match state_string(fields, path, "kind") {
    "unavailable" => Unavailable
    "captured" => Captured(@json.from_json(json, path~))
    _ => state_decode_error(path, "invalid goal baseline state")
  }
}
