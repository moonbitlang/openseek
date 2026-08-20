///|
/// Token counts for one model response, as the `usage` event carries them.
///
/// Structurally identical to `@deepseek.Usage` — same field names, same order,
/// so the same JSON — but owned here on purpose. This type IS the wire format
/// for the event; leaving it as the vendor's response struct meant renaming a
/// DeepSeek field silently changed the contract every client parses, and it
/// would tie this module to the engine's provider layer. The engine converts at
/// the one site that reports usage.
///
/// `ToJson` but deliberately **not** `FromJson`: the derive reads a JSON number
/// into an `Int` by truncating, so `@json.from_json` would accept a
/// `prompt_tokens` of `1.5` as `1` while `parse` rejects that same line. A
/// public second decoder that disagrees with the canonical one is the exact
/// failure this module exists to prevent, and a fabricated token count is worse
/// than a dropped line — the counters feed the context-ceiling guard. `parse`
/// decodes them field by field through `int`, which rejects a fractional value.
pub(all) struct Usage {
  prompt_tokens : Int
  completion_tokens : Int
  total_tokens : Int
  prompt_cache_hit_tokens : Int
  prompt_cache_miss_tokens : Int
} derive(Eq, Debug, ToJson)

///|
pub extend Usage with Debug::{to_repr}

///|
pub extend Usage with Eq::{equal, not_equal}

///|
pub extend Usage with ToJson::{to_json}
