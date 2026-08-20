// Deliberate exports with no in-repo production consumer (see
// shrink_package.md): test seams, round-trip/protocol surface, and
// future-proof API kept on purpose. Each entry documents its reason.

///|
/// Public so wire consumers (the TUI decodes the engine's `usage` log event)
/// can round-trip the same schema `ToJson` emits. Absent counters decode as 0;
/// malformed counters or a non-object value raise `JsonDecodeError`.
pub impl FromJson for Usage with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> Usage {
  Usage::parse_json(json, path)
}

///|
pub extend Usage with FromJson::{from_json}
