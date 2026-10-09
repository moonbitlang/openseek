///|
fn test_location(uri : String, line : Int, column : Int) -> @language.Location {
  {
    is_test: None,
    uri: try! @base_common.Uri::parse(uri),
    range: Range(line, column, line, column + 1),
  }
}

///|
test "definition locations preserve provider order and remove exact duplicates" {
  let first = test_location("file:///first.mbt", 2, 3)
  let duplicate = test_location("file:///first.mbt", 2, 3)
  let second = test_location("file:///second.mbt", 4, 5)
  let normalized = normalize_definition_locations([first, duplicate, second])
  assert_eq(normalized.length(), 2)
  assert_eq(normalized[0].uri.to_string(), "file:///first.mbt")
  assert_eq(normalized[1].uri.to_string(), "file:///second.mbt")
}

///|
test "definition target freshness includes model identity version and generation" {
  let model = @model.TextModel(
    try! @base_common.Uri::parse("file:///source.mbt"),
    "source.mbt",
    "moonbit",
    1,
    "revision-1",
    "let answer = value",
  )
  let position = @base_common.Position(1, 6)
  let word = model.get_word_at_position(position).unwrap()
  let target = DefinitionTargetFingerprint::from_model(model, 7, position, word)
  let same_word = DefinitionTargetFingerprint::from_model(
    model,
    7,
    Position(1, 9),
    model.get_word_at_position(Position(1, 9)).unwrap(),
  )
  assert_true(target.is_current(model, 7))
  assert_true(target.same_word(same_word))
  assert_false(target.is_current(model, 8))
  model.set_value("let answer = changed")
  assert_false(target.is_current(model, 7))
  model.dispose()
}
