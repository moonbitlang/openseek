///|
/// Provider reporting facts, separate from legacy zero-filled usage fields.
/// None means no valid nonnegative integer was reported for that field.
/// `reported` distinguishes a usage object (including an empty one) from absence.
pub struct UsageReport {
  reported : Bool
  prompt_tokens : Int32?
  completion_tokens : Int32?
  total_tokens : Int32?
  prompt_cache_hit_tokens : Int32?
  prompt_cache_miss_tokens : Int32?
} derive(Eq, Debug, ToJson, FromJson)

///|
/// Read reporting facts without decoding the response's message or tool calls.
pub fn UsageReport::from_response(response : Json) -> UsageReport {
  let usage = match response {
    { "usage": Object(fields), .. } => Some(fields)
    _ => None
  }
  fn count(key : String) -> Int32? {
    guard usage is Some(fields) else { return None }
    match fields.get(key) {
      Some(Number(value, ..)) if value >= 0 &&
        value <= 2147483647 &&
        value == value.to_int().to_double() => Some(value.to_int())
      _ => None
    }
  }
  {
    reported: usage is Some(_),
    prompt_tokens: count("prompt_tokens"),
    completion_tokens: count("completion_tokens"),
    total_tokens: count("total_tokens"),
    prompt_cache_hit_tokens: count("prompt_cache_hit_tokens"),
    prompt_cache_miss_tokens: count("prompt_cache_miss_tokens"),
  }
}

///|
#doc(hidden)
#deprecated
pub extend UsageReport with Eq::{equal, not_equal}

///|
#doc(hidden)
#deprecated
pub extend UsageReport with Debug::{to_repr}

///|
#doc(hidden)
#deprecated
pub extend UsageReport with ToJson::{to_json}

///|
#doc(hidden)
#deprecated
pub extend UsageReport with FromJson::{from_json}
