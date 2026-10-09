// Conformance tests for the DOM-free References model and snippet algorithms.
//
// Ports:
// - vscode/src/vs/editor/contrib/gotoSymbol/browser/referencesModel.ts:66-145
// - vscode/src/vs/editor/contrib/gotoSymbol/browser/referencesModel.ts:147-297
// Pinned vscode revision: b18492a288de038fbc7643aae6de8247029d11bd.
//
// Selected local representations under test:
// - canonical Uri::to_string identity, including fragments;
// - caller arrays are copied before MoonBit's in-place sort;
// - snippet highlights are three strings, with line breaks normalized;
// - invalid ranges and wrong-resource models retain a one-based fallback.

///|
fn reference_location(
  uri : String,
  start_line : Int,
  start_column : Int,
  end_line : Int,
  end_column : Int,
) -> @language.Location {
  {
    is_test: None,
    uri: try! @base_common.Uri::parse(uri),
    range: Range(start_line, start_column, end_line, end_column),
  }
}

///|
fn reference_model(uri : String, text : String) -> @model.TextModel {
  TextModel(
    try! @base_common.Uri::parse(uri),
    @base_common.basename_or_authority(try! @base_common.Uri::parse(uri)),
    "moonbit",
    1,
    "revision-1",
    text,
  )
}

///|
fn reference_shape(model : ReferencesModel) -> Array[String] {
  model.references.map(reference => {
    "\{reference.uri_string}@\{reference.range.start_line_number}:\{reference.range.start_column}-\{reference.range.end_line_number}:\{reference.range.end_column}#\{reference.group_index}/\{reference.index_in_group}/\{reference.flat_index}"
  })
}

///|
test "reference model copies, sorts, groups, and exactly deduplicates" {
  let input = [
    reference_location("file:///b.mbt", 4, 5, 4, 6),
    // Reverse end order proves full-range comparison rather than caller order.
    reference_location("file:///a.mbt", 2, 3, 2, 6),
    reference_location("file:///a.mbt", 2, 3, 2, 5),
    reference_location("file:///a.mbt", 2, 3, 2, 5),
    reference_location("file:///a.mbt", 1, 9, 1, 10),
    reference_location("file:///b.mbt", 1, 1, 1, 2),
  ]
  let result = ReferencesModel(input)
  // Construction did not reorder the caller-owned array.
  assert_eq(input[0].uri.to_string(), "file:///b.mbt")
  input[0] = reference_location("file:///mutated.mbt", 1, 1, 1, 2)
  assert_eq(result.references[4].uri_string, "file:///b.mbt")
  debug_inspect(
    reference_shape(result),
    content=(
      #|[
      #|  "file:///a.mbt@1:9-1:10#0/0/0",
      #|  "file:///a.mbt@2:3-2:5#0/1/1",
      #|  "file:///a.mbt@2:3-2:6#0/2/2",
      #|  "file:///b.mbt@1:1-1:2#1/0/3",
      #|  "file:///b.mbt@4:5-4:6#1/1/4",
      #|]
    ),
  )
  assert_eq(result.groups.length(), 2)
  assert_eq(result.groups[0].references.length(), 3)
  assert_eq(result.groups[1].references.length(), 2)
  assert_eq(result.references[1].location().uri.to_string(), "file:///a.mbt")
}

///|
test "empty and one-resource inputs preserve the closed group shape" {
  let empty = ReferencesModel([])
  assert_true(empty.is_empty())
  assert_eq(empty.groups.length(), 0)
  let one = ReferencesModel([
    reference_location("file:///only.mbt", 3, 2, 3, 4),
    reference_location("file:///only.mbt", 1, 2, 1, 4),
  ])
  assert_false(one.is_empty())
  assert_eq(one.groups.length(), 1)
  assert_eq(one.groups[0].references.length(), 2)
  assert_eq(one.references[0].flat_index, 0)
  assert_eq(one.references[1].flat_index, 1)
}

///|
test "canonical URI fragments remain separate resource groups" {
  let model = ReferencesModel([
    reference_location("file:///same.mbt#two", 1, 1, 1, 2),
    reference_location("file:///same.mbt#one", 1, 1, 1, 2),
    reference_location("file:///same.mbt#one", 1, 1, 1, 2),
  ])
  assert_eq(model.groups.length(), 2)
  assert_eq(model.references.length(), 2)
  assert_eq(model.groups[0].uri_string, "file:///same.mbt#one")
  assert_eq(model.groups[1].uri_string, "file:///same.mbt#two")
}

///|
test "nearest reference prefers URI prefix then weighted position distance" {
  let model = ReferencesModel([
    reference_location("file:///out/obj/can", 20, 5, 20, 6),
    reference_location("file:///out/obj/can2", 30, 5, 30, 6),
    reference_location("file:///src/can", 90, 5, 90, 6),
  ])
  let exact = model
    .nearest_reference(
      try! @base_common.Uri::parse("file:///src/can"),
      Position(1, 1),
    )
    .unwrap()
  assert_eq(exact.uri_string, "file:///src/can")
  let longest_prefix = model
    .nearest_reference(
      try! @base_common.Uri::parse("file:///out/obj/can2222"),
      Position(1, 1),
    )
    .unwrap()
  assert_eq(longest_prefix.uri_string, "file:///out/obj/can2")

  let positions = ReferencesModel([
    reference_location("file:///same.mbt", 11, 1, 11, 2),
    reference_location("file:///same.mbt", 10, 20, 10, 21),
    reference_location("file:///same.mbt", 9, 1, 9, 2),
  ])
  let weighted = positions
    .nearest_reference(
      try! @base_common.Uri::parse("file:///same.mbt"),
      Position(10, 1),
    )
    .unwrap()
  // Nineteen columns is nearer than one line under the pinned `* 100` rule.
  assert_eq(weighted.range, Range(10, 20, 10, 21))
  let line_column_tie = ReferencesModel([
    // Caller order is the reverse of canonical range order.
    reference_location("file:///same.mbt", 11, 1, 11, 2),
    reference_location("file:///same.mbt", 10, 101, 10, 102),
  ])
  let stable_tie = line_column_tie
    .nearest_reference(
      try! @base_common.Uri::parse("file:///same.mbt"),
      Position(10, 1),
    )
    .unwrap()
  // One line and 100 columns both score 100; stable sorted order wins.
  assert_eq(stable_tie.range, Range(10, 101, 10, 102))
}

///|
test "nearest reference keeps sorted stability for non-ASCII URI ties" {
  let model = ReferencesModel([
    reference_location("file:///工作/乙.mbt", 11, 1, 11, 2),
    reference_location("file:///工作/甲.mbt", 9, 1, 9, 2),
  ])
  let nearest = model
    .nearest_reference(
      try! @base_common.Uri::parse("file:///工作/"),
      Position(10, 1),
    )
    .unwrap()
  // Equal prefix and equal weighted distance retain canonical sorted order.
  assert_eq(nearest.uri_string, model.references[0].uri_string)
}

///|
test "nearest reference retains stable sorted order on final distance tie" {
  let model = ReferencesModel([
    reference_location("file:///same.mbt", 11, 1, 11, 2),
    reference_location("file:///same.mbt", 9, 1, 9, 2),
  ])
  let nearest = model
    .nearest_reference(
      try! @base_common.Uri::parse("file:///same.mbt"),
      Position(10, 1),
    )
    .unwrap()
  assert_eq(nearest.range, Range(9, 1, 9, 2))
}

///|
test "next and previous navigation wrap through the flat sequence" {
  let model = ReferencesModel([
    reference_location("file:///b.mbt", 1, 1, 1, 2),
    reference_location("file:///a.mbt", 2, 1, 2, 2),
    reference_location("file:///a.mbt", 1, 1, 1, 2),
  ])
  let first = model.references[0]
  let second = model.next_reference(first).unwrap()
  let third = model.next_reference(second).unwrap()
  assert_eq(second, model.references[1])
  assert_eq(third, model.references[2])
  assert_eq(model.next_reference(third), Some(first))
  assert_eq(model.previous_reference(first), Some(third))
  assert_eq(model.previous_reference(third), Some(second))
  let foreign = { ..first, range: Range(99, 1, 99, 2), }
  assert_eq(model.next_reference(foreign), None)
  assert_eq(ReferencesModel([]).next_reference(first), None)
}

///|
test "snippet uses eight-column word context and keeps three exact parts" {
  let model = reference_model(
    "file:///snippet.mbt", "one two three target rest",
  )
  let snippet = reference_snippet(model, Range(1, 15, 1, 21)).unwrap()
  assert_eq(snippet.before, "two three ")
  assert_eq(snippet.matched, "target")
  assert_eq(snippet.after, " rest")
  assert_eq(snippet.display_text(), "two three target rest")
}

///|
test "snippet trims row edges and normalizes multiline matches" {
  let model = reference_model(
    "file:///multiline.mbt", "  before TARGET\n  continued END  \n",
  )
  let snippet = reference_snippet(model, Range(1, 10, 2, 12)).unwrap()
  assert_eq(snippet.before, "before ")
  assert_eq(snippet.matched, "TARGET   continued")
  assert_eq(snippet.after, " END")
  assert_false(snippet.display_text().contains("\n"))
}

///|
test "snippet preserves non-BMP UTF-16 match boundaries" {
  let model = reference_model("file:///unicode.mbt", "  alpha 🤣 omega  ")
  // The emoji occupies UTF-16 columns 9..<11.
  let snippet = reference_snippet(model, Range(1, 9, 1, 11)).unwrap()
  assert_eq(snippet.before, "alpha ")
  assert_eq(snippet.matched, "🤣")
  assert_eq(snippet.after, " omega")
}

///|
test "invalid empty and surrogate-splitting ranges retain fallback" {
  let model = reference_model("file:///fallback.mbt", "🤣\n\nvalue")
  assert_eq(reference_snippet(model, Range(2, 1, 2, 1)), None)
  assert_eq(reference_snippet(model, Range(90, 1, 90, 2)), None)
  let reversed : @base_common.Range = {
    start_line_number: 3,
    start_column: 4,
    end_line_number: 2,
    end_column: 1,
  }
  assert_eq(reference_snippet(model, reversed), None)
  // Column 2 splits the emoji's UTF-16 surrogate pair.
  assert_eq(reference_snippet(model, Range(1, 2, 1, 3)), None)
  let item = ReferencesModel([
      reference_location("file:///fallback.mbt", 90, 7, 90, 8),
    ]).references[0]
  assert_eq(
    item.row_preview(Some(model)),
    LocationFallback("fallback.mbt:90:7"),
  )
  assert_eq(item.row_preview(None), LocationFallback("fallback.mbt:90:7"))
}

///|
test "wrong-resource and disposed models retain selectable fallback" {
  let item = ReferencesModel([
      reference_location("file:///target.mbt", 1, 2, 1, 4),
    ]).references[0]
  let wrong = reference_model("file:///wrong.mbt", "target")
  assert_eq(item.row_preview(Some(wrong)), LocationFallback("target.mbt:1:2"))
  let target = reference_model("file:///target.mbt", "target")
  target.dispose()
  assert_eq(item.row_preview(Some(target)), LocationFallback("target.mbt:1:2"))
}

///|
test "valid row preview returns the exact snippet variant" {
  let item = ReferencesModel([
      reference_location("file:///target.mbt", 1, 5, 1, 11),
    ]).references[0]
  let model = reference_model("file:///target.mbt", "let target = 1")
  assert_eq(
    item.row_preview(Some(model)),
    Snippet({ before: "let ", matched: "target", after: " = 1", }),
  )
}

///|
test "session key captures identity generation version and exact anchor" {
  let model = reference_model("file:///source.mbt", "let value = 1")
  let key = ReferencesSessionKey::from_model(model, 7, Position(1, 5))
  let same = ReferencesSessionKey::from_model(model, 7, Position(1, 5))
  let other_anchor = ReferencesSessionKey::from_model(model, 7, Position(1, 6))
  assert_eq(key, same)
  assert_true(key != other_anchor)
  assert_true(key.is_current(model, 7))
  assert_false(key.is_current(model, 8))
  model.set_value("let value = 2")
  assert_false(key.is_current(model, 7))
}
