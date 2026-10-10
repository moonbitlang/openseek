///|
/// One auxiliary request against the live engine's exact durable snapshot.
/// Required fields reject missing/null/malformed values; unknown keys are ignored.
pub(all) struct PredictionPayload {
  session : String
  request_id : String
  source_sequence : Int
} derive(Eq, Debug)

///|
pub impl FromJson for PredictionPayload with fn from_json(json, path) {
  let obj = JsonObject::decode(json, path, "PredictionPayload")
  let session : String = @json.from_json(
    obj.required_json("session"),
    path=path.add_key("session"),
  )
  let request_id : String = @json.from_json(
    obj.required_json("request_id"),
    path=path.add_key("request_id"),
  )
  let n = jobs_uint(
    obj.required_json("source_sequence"),
    path.add_key("source_sequence"),
  )
  guard !session.is_empty() &&
    !request_id.is_empty() &&
    request_id.length() <= 128 &&
    n > 0L &&
    n <= 2147483647L else {
    raise JsonDecodeError((path, "invalid prediction identity"))
  }
  { session, request_id, source_sequence: n.to_int(), }
}

///|
pub impl ToJson for PredictionPayload with fn to_json(self) {
  {
    "session": self.session,
    "request_id": self.request_id,
    "source_sequence": self.source_sequence,
  }
}

///|
pub(all) struct PredictionReply {
  outcome : @wire.PredictionOutcome
} derive(Eq, Debug)

///|
pub impl FromJson for PredictionReply with fn from_json(json, path) {
  let obj = JsonObject::decode(json, path, "PredictionReply")
  {
    outcome: @json.from_json(
      obj.required_json("outcome"),
      path=path.add_key("outcome"),
    ),
  }
}

///|
pub impl ToJson for PredictionReply with fn to_json(self) {
  { "outcome": self.outcome.to_json() }
}

///|
pub extend PredictionPayload with Eq::{equal, not_equal}

///|
pub extend PredictionPayload with Debug::{to_repr}

///|
pub extend PredictionPayload with ToJson::{to_json}

///|
pub extend PredictionPayload with FromJson::{from_json}

///|
pub extend PredictionReply with Eq::{equal, not_equal}

///|
pub extend PredictionReply with Debug::{to_repr}

///|
pub extend PredictionReply with ToJson::{to_json}

///|
pub extend PredictionReply with FromJson::{from_json}
