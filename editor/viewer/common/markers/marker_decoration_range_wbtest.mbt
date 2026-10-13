///|
/// Builds a marker with explicit span and optional tags for transform tests.
fn make_marker(
  severity : MarkerSeverity,
  start_line_number : Int32,
  start_column : Int32,
  end_line_number : Int32,
  end_column : Int32,
  tags? : Array[MarkerTag],
) -> Marker {
  {
    owner: "o",
    resource: try! @base_common.Uri::from(
      scheme="inmemory",
      authority="model",
      path="/range.mbt",
    ),
    severity,
    code: None,
    message: "m",
    source: None,
    start_column,
    start_line_number,
    end_line_number,
    end_column,
    model_version_id: None,
    related_information: None,
    tags,
    origin: None,
  }
}

///|
fn wb_range_model(text : String) -> @model.TextModel {
  TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="model",
      path="/markers.mbt",
    ),
    "",
    "moonbit",
    1,
    "",
    text,
  )
}

///|
test "create_decoration_range branch 1: hint truncated to start line +2" {
  let model = wb_range_model(
    (
      #|hello world
      #|second
      #|third
    ),
  )
  // multi-line hint, no tags → single line, endColumn = startColumn + 2
  let marker = make_marker(Hint, 1, 3, 3, 5)
  assert_true(create_decoration_range(model, marker) == Range(1, 3, 1, 5))
}

///|
test "create_decoration_range branch 3: empty range expands to word" {
  let model = wb_range_model("hello world")
  let marker = make_marker(Error, 1, 3, 1, 3)
  assert_true(create_decoration_range(model, marker) == Range(1, 1, 1, 6))
}

///|
test "create_decoration_range branch 3: empty range on empty line kept 1ch" {
  let model = wb_range_model(
    (
      #|hello
      #|
      #|world
    ),
  )
  let marker = make_marker(Error, 2, 1, 2, 1)
  assert_true(create_decoration_range(model, marker) == Range(2, 1, 2, 1))
}

///|
test "create_decoration_range branch 3: empty range behind eol kept 1ch" {
  let model = wb_range_model("hello")
  let marker = make_marker(Error, 1, 6, 1, 6)
  assert_true(create_decoration_range(model, marker) == Range(1, 6, 1, 6))
}

///|
test "create_decoration_range branch 4: full-line marker snaps to first non-ws" {
  let model = wb_range_model("    code here")
  let marker = make_marker(Error, 1, 1, 1, max_value_column)
  let ret = create_decoration_range(model, marker)
  // line max column is 14 ("    code here" is 13 chars); start snaps to col 5.
  assert_true(ret == Range(1, 5, 1, 14))
  // Monaco mutates rawMarker.startColumn (markerDecorationsService.ts:220)
  assert_eq(marker.start_column, 5)
}
