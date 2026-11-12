///|
test "pattern repair payload carries the selected model" {
  let payload : @protocol.PatternRepairPayload = @json.from_json({
    "root": "/work/project",
    "pattern": "broken",
    "instruction": "repair syntax",
    "model": "deepseek-v4-flash",
    "generation": 3,
  })
  // The retired flash alias decodes to the same model and re-encodes under
  // its canonical name.
  assert_eq(payload.model, Deepseek(V4Flash))
  @debug.assert_eq(payload.to_json(), {
    "root": "/work/project",
    "pattern": "broken",
    "instruction": "repair syntax",
    "model": "deepseek-flash",
    "generation": 3,
  })

  let selected : @protocol.PatternRepairPayload = @json.from_json({
    "root": "/work/project",
    "pattern": "broken",
    "instruction": "repair syntax",
    "model": "glm-5.3",
    "generation": 4,
  })
  assert_eq(selected.model, Glm(G53))
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
    "validation_status": "unavailable",
    "message": "Pattern Repair settings are unavailable.",
    "trace": ["Agent step 1"],
  })
  assert_true(reply.validation_status is Unavailable)
  assert_true(reply.candidate_pattern is Some("inspect($_)"))
  assert_eq(reply.trace, ["Agent step 1"])
  @debug.assert_eq(reply.to_json(), {
    "root": "/work/project",
    "generation": 3,
    "candidate_pattern": "inspect($_)",
    "validation_status": "unavailable",
    "message": "Pattern Repair settings are unavailable.",
    "trace": ["Agent step 1"],
  })
}

///|
test "pattern repair reply preserves a timeout as a distinct outcome" {
  let reply : @protocol.PatternRepairReply = @json.from_json({
    "root": "/work/project",
    "generation": 3,
    "candidate_pattern": "inspect($_)",
    "validation_status": "timed_out",
    "message": "Pattern Repair Agent timed out after 120 seconds. Try again.",
    "trace": ["validate_pattern: failed — expected expression"],
  })
  assert_true(reply.validation_status is TimedOut)
}

///|
test "pattern repair failure replies may omit an unsubmitted candidate" {
  let reply : @protocol.PatternRepairReply = @json.from_json({
    "root": "/work/project",
    "generation": 3,
    "validation_status": "failed",
    "message": "max_steps_exhausted",
    "trace": ["Agent step limit exhausted"],
  })
  assert_true(reply.candidate_pattern is None)
  assert_eq(reply.trace, ["Agent step limit exhausted"])
  @debug.assert_eq(reply.to_json(), {
    "root": "/work/project",
    "generation": 3,
    "validation_status": "failed",
    "message": "max_steps_exhausted",
    "trace": ["Agent step limit exhausted"],
  })
}
