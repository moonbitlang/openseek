///|
/// Auxiliary completion, distinct from a durable conversation event.
pub(all) enum PredictionOutcome {
  Completed(text~ : String?, input_tokens~ : Int, output_tokens~ : Int)
  Skipped
  Cancelled
  Failed(String)
} derive(Eq, Debug)

///|
pub extend PredictionOutcome with Eq::{equal, not_equal}

///|
pub extend PredictionOutcome with Debug::{to_repr}

///|
pub extend PredictionOutcome with ToJson::{to_json}

///|
pub extend PredictionOutcome with FromJson::{from_json}

///|
pub impl ToJson for PredictionOutcome with fn to_json(self) {
  match self {
    Completed(text~, input_tokens~, output_tokens~) =>
      {
        "kind": "completed",
        "text": or_null(text),
        "input_tokens": input_tokens,
        "output_tokens": output_tokens,
      }
    Skipped => { "kind": "skipped" }
    Cancelled => { "kind": "cancelled" }
    Failed(message) => { "kind": "failed", "message": message }
  }
}

///|
pub impl FromJson for PredictionOutcome with fn from_json(json, path) {
  match json {
    {
      "kind": "completed",
      "text": text,
      "input_tokens": input,
      "output_tokens": output,
      ..
    } => {
      let text : String? = match text {
        Null => None
        String(text) if !text.is_empty() => Some(text)
        _ =>
          raise JsonDecodeError(
            (path.add_key("text"), "expected nonempty text or null"),
          )
      }
      let input_tokens : Int = @json.from_json(
        input,
        path=path.add_key("input_tokens"),
      )
      let output_tokens : Int = @json.from_json(
        output,
        path=path.add_key("output_tokens"),
      )
      guard input_tokens >= 0 && output_tokens >= 0 else {
        raise JsonDecodeError((path, "negative token usage"))
      }
      Completed(text~, input_tokens~, output_tokens~)
    }
    { "kind": "skipped", .. } => Skipped
    { "kind": "cancelled", .. } => Cancelled
    { "kind": "failed", "message": String(message), .. } => Failed(message)
    _ => raise JsonDecodeError((path, "invalid prediction outcome"))
  }
}

///|
/// Durable auxiliary result, saved only after a prediction completes.
pub(all) struct PredictionRecord {
  source_sequence : Int
  request_id : String
  outcome : PredictionOutcome
} derive(Eq, Debug)

///|
pub impl ToJson for PredictionRecord with fn to_json(self) {
  {
    "version": 1,
    "source_sequence": self.source_sequence,
    "request_id": self.request_id,
    "outcome": self.outcome.to_json(),
  }
}

///|
pub impl FromJson for PredictionRecord with fn from_json(json, path) {
  guard json
    is {
      "version": 1,
      "source_sequence": Number(n, ..),
      "request_id": String(request_id),
      "outcome": outcome,
      ..
    } &&
    n > 0 &&
    n <= 2147483647.0 &&
    n.to_int().to_double() == n &&
    !request_id.is_empty() &&
    request_id.length() <= 128 else {
    raise JsonDecodeError((path, "invalid prediction record"))
  }
  {
    source_sequence: n.to_int(),
    request_id,
    outcome: @json.from_json(outcome, path=path.add_key("outcome")),
  }
}

///|
pub extend PredictionRecord with Eq::{equal, not_equal}

///|
pub extend PredictionRecord with Debug::{to_repr}

///|
pub extend PredictionRecord with ToJson::{to_json}

///|
pub extend PredictionRecord with FromJson::{from_json}
