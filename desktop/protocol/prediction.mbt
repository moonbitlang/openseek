///|
/// A completed engine-owned prediction, broadcast to every connected client.
pub(all) struct PredictionReadyPayload {
  session : String
  prediction : @wire.PredictionRecord
} derive(Eq, Debug)

///|
pub impl FromJson for PredictionReadyPayload with fn from_json(json, path) {
  let obj = JsonObject::decode(json, path, "PredictionReadyPayload")
  let session : String = @json.from_json(
    obj.required_json("session"),
    path=path.add_key("session"),
  )
  let prediction : @wire.PredictionRecord = @json.from_json(
    obj.required_json("prediction"),
    path=path.add_key("prediction"),
  )
  guard !session.is_empty() && prediction.outcome is Completed(..) else {
    raise JsonDecodeError((path, "expected a completed session prediction"))
  }
  { session, prediction, }
}

///|
pub impl ToJson for PredictionReadyPayload with fn to_json(self) {
  { "session": self.session, "prediction": self.prediction.to_json() }
}

///|
pub extend PredictionReadyPayload with Eq::{equal, not_equal}

///|
pub extend PredictionReadyPayload with Debug::{to_repr}

///|
pub extend PredictionReadyPayload with FromJson::{from_json}

///|
pub extend PredictionReadyPayload with ToJson::{to_json}
