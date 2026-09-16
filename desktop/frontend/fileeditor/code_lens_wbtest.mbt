///|
fn codelens_test_model() -> @model.TextModel {
  TextModel(
    try! @common.Uri::parse("openseek://local/ws/src/main.mbt"),
    "main.mbt",
    "moonbit",
    1,
    "test-revision",
    "pub fn first() -> Int { 1 }\npub fn second() -> Int { 2 }\n",
  )
}

///|
test "Moon IDE CodeLens accepts only exact source ranges and the Source model" {
  let model = codelens_test_model()
  defer model.dispose()
  let diff = codelens_test_model()
  defer diff.dispose()
  assert_true(moon_ide_codelens_source_model_matches(model, Some(model)))
  assert_false(moon_ide_codelens_source_model_matches(diff, Some(model)))
  assert_false(moon_ide_codelens_source_model_matches(model, None))
  assert_eq(
    project_codelens_range(model, {
      start: { line: 0, character: 7, },
      end: { line: 0, character: 12, },
    }),
    Some(Range(1, 8, 1, 13)),
  )
  let invalid : Array[@protocol.LspRange] = [
    { start: { line: -1, character: 0, }, end: { line: 0, character: 0, }, },
    { start: { line: 0, character: 12, }, end: { line: 0, character: 7, }, },
    { start: { line: 99, character: 0, }, end: { line: 99, character: 0, }, },
    {
      start: { line: 0, character: 2147483647, },
      end: { line: 0, character: 2147483647, },
    },
  ]
  for range in invalid {
    assert_true(project_codelens_range(model, range) is None)
  }
}
