///|
test "test references partition after deduplication including mixed files" {
  let uri = @base_common.Uri::file("/workspace/a.mbt")
  let ordinary : @language.Location = {
    uri,
    range: Range(8, 1, 8, 2),
    is_test: Some(false),
  }
  let test_ref : @language.Location = {
    uri,
    range: Range(2, 1, 2, 2),
    is_test: Some(true),
  }
  let unknown : @language.Location = {
    uri: @base_common.Uri::file("/workspace/z.mbt"),
    range: Range(1, 1, 1, 2),
    is_test: None,
  }
  let input = [
    test_ref,
    unknown,
    ordinary,
    { ..test_ref, is_test: Some(false), },
  ]
  let model = ReferencesModel(input)
  assert_eq(model.references.map(item => item.range.start_line_number), [
    8, 1, 2,
  ])
  assert_eq(model.groups.map(group => group.is_test), [false, false, true])
  assert_eq(model.references.map(item => item.flat_index), [0, 1, 2])
  assert_eq(input[0].is_test, Some(true))
  assert_eq(model.references[2].location().is_test, Some(true))
  assert_eq(
    model.nearest_reference(uri, Position(2, 1), prefer_non_test=true),
    Some(model.references[0]),
  )
  assert_eq(
    model.next_reference(model.references[1]),
    Some(model.references[2]),
  )
  assert_eq(
    model.next_reference(model.references[2]),
    Some(model.references[0]),
  )
  assert_eq(
    model.previous_reference(model.references[0]),
    Some(model.references[2]),
  )
}
