///|
test "pattern repair payload carries the selected model" {
  let payload : @protocol.PatternRepairPayload = @json.from_json({
    "root": "/work/project",
    "pattern": "broken",
    "instruction": "repair syntax",
    "model": "deepseek-v4-flash",
    "generation": 3,
  })
  assert_eq(payload.model, "deepseek-v4-flash")
  @debug.assert_eq(payload.to_json(), {
    "root": "/work/project",
    "pattern": "broken",
    "instruction": "repair syntax",
    "model": "deepseek-v4-flash",
    "generation": 3,
  })

  let selected : @protocol.PatternRepairPayload = @json.from_json({
    "root": "/work/project",
    "pattern": "broken",
    "instruction": "repair syntax",
    "model": "glm-5.3",
    "generation": 4,
  })
  assert_eq(selected.model, "glm-5.3")
  @debug.assert_eq(selected.to_json(), {
    "root": "/work/project",
    "pattern": "broken",
    "instruction": "repair syntax",
    "model": "glm-5.3",
    "generation": 4,
  })
}

///|
test "pattern repair reply decodes its closed status" {
  let reply : @protocol.PatternRepairReply = @json.from_json({
    "root": "/work/project",
    "generation": 3,
    "candidate_pattern": "inspect($_)",
    "valid": false,
    "validation_status": "unavailable",
    "message": "Pattern Repair settings are unavailable.",
  })
  assert_true(reply.validation_status is Unavailable)
  assert_true(reply.candidate_pattern is Some("inspect($_)"))
  @debug.assert_eq(reply.to_json(), {
    "root": "/work/project",
    "generation": 3,
    "candidate_pattern": "inspect($_)",
    "valid": false,
    "validation_status": "unavailable",
    "message": "Pattern Repair settings are unavailable.",
  })
}

///|
test "pattern repair reply preserves a timeout as a distinct outcome" {
  let reply : @protocol.PatternRepairReply = @json.from_json({
    "root": "/work/project",
    "generation": 3,
    "candidate_pattern": "inspect($_)",
    "valid": false,
    "validation_status": "timed_out",
    "message": "Pattern repair timed out while contacting the AI provider. Check your connection or provider endpoint, then retry.",
  })
  assert_true(reply.validation_status is TimedOut)
}

///|
test "pattern repair failure replies may omit an unsubmitted candidate" {
  let reply : @protocol.PatternRepairReply = @json.from_json({
    "root": "/work/project",
    "generation": 3,
    "valid": false,
    "validation_status": "failed",
    "message": "max_steps_exhausted",
  })
  assert_true(reply.candidate_pattern is None)
  @debug.assert_eq(reply.to_json(), {
    "root": "/work/project",
    "generation": 3,
    "valid": false,
    "validation_status": "failed",
    "message": "max_steps_exhausted",
  })
}
