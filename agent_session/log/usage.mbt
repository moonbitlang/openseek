///|
/// Decode an accounting line, returning None for conversation records. Invalid
/// recognized metadata raises instead of being silently treated as a message.
pub fn usage_record(json : Json) -> @agent_session.UsageRecord? raise {
  match json {
    { "type": "model_usage", "record": record, .. } =>
      Some(@json.from_json(record))
    { "type": "model_usage", .. } =>
      fail("model_usage record is missing its payload")
    _ => None
  }
}
