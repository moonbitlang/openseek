///|
test "report distinguishes absent, partial and real zero usage without changing legacy counts" {
  let absent_json : Json = { "choices": [{ "message": { "content": "ok" } }] }
  let absent : @deepseek.ChatResponse = @json.from_json(absent_json)
  let absent_report = @deepseek.UsageReport::from_response(absent_json)
  assert_eq(absent.usage.total_tokens, 0)
  assert_eq(absent_report.reported, false)
  assert_eq(absent_report.total_tokens, None)
  let partial_json : Json = {
    "choices": [{ "message": { "content": "ok" } }],
    "usage": { "prompt_tokens": 0, "completion_tokens": 7 },
  }
  let partial : @deepseek.ChatResponse = @json.from_json(partial_json)
  let partial_report = @deepseek.UsageReport::from_response(partial_json)
  assert_eq(partial.usage.total_tokens, 0)
  assert_eq(partial_report.reported, true)
  assert_eq(partial_report.prompt_tokens, Some(0))
  assert_eq(partial_report.completion_tokens, Some(7))
  assert_eq(partial_report.total_tokens, None)
  assert_eq(
    @deepseek.UsageReport::from_response({ "usage": {} }).reported,
    true,
  )
  let invalid = @deepseek.UsageReport::from_response({
    "usage": {
      "prompt_tokens": -1,
      "completion_tokens": 1.5,
      "total_tokens": 2147483648,
    },
  })
  assert_eq(invalid.prompt_tokens, None)
  assert_eq(invalid.completion_tokens, None)
  assert_eq(invalid.total_tokens, None)
}
