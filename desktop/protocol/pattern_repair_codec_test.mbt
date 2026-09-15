///|
test "pattern repair payload carries the optional selected model" {
  let legacy : @protocol.PatternRepairPayload = @json.from_json({
    "root": "/work/project",
    "pattern": "broken",
    "instruction": "repair syntax",
    "generation": 3,
  })
  assert_eq(legacy.model, None)
  @debug.assert_eq(legacy.to_json(), {
    "root": "/work/project",
    "pattern": "broken",
    "instruction": "repair syntax",
    "generation": 3,
  })

  let selected : @protocol.PatternRepairPayload = @json.from_json({
    "root": "/work/project",
    "pattern": "broken",
    "instruction": "repair syntax",
    "model": "glm-5.3",
    "generation": 4,
  })
  assert_eq(selected.model, Some("glm-5.3"))
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
  assert_true(
    reply.validation_status is @protocol.PatternRepairStatus::Unavailable,
  )
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
  assert_true(
    reply.validation_status is @protocol.PatternRepairStatus::TimedOut,
  )
}
