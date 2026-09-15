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
