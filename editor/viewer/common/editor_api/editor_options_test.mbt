///|
test "RenderWhitespace exposes every canonical mode" {
  let modes : Array[@editor_api.RenderWhitespace] = [
    None,
    Boundary,
    Selection,
    Trailing,
    All,
  ]
  assert_eq(modes.length(), 5)
  assert_eq(modes[0], None)
  assert_eq(modes[1], Boundary)
  assert_eq(modes[2], Selection)
  assert_eq(modes[3], Trailing)
  assert_eq(modes[4], All)
}

///|
test "RenderLineHighlight exposes every canonical mode" {
  let modes : Array[@editor_api.RenderLineHighlight] = [None, Gutter, Line, All]
  assert_eq(modes.length(), 4)
  assert_eq(modes[0], None)
  assert_eq(modes[1], Gutter)
  assert_eq(modes[2], Line)
  assert_eq(modes[3], All)
}

///|
test "WrappingIndent exposes every canonical mode" {
  let modes : Array[@editor_api.WrappingIndent] = [
    None,
    Same,
    Indent,
    DeepIndent,
  ]
  assert_eq(modes.length(), 4)
  assert_eq(modes[0], None)
  assert_eq(modes[1], Same)
  assert_eq(modes[2], Indent)
  assert_eq(modes[3], DeepIndent)
}

///|
test "RenderValidationDecorations exposes every canonical mode" {
  let modes : Array[@editor_api.RenderValidationDecorations] = [
    Editable,
    On,
    Off,
  ]
  assert_eq(modes.length(), 3)
  assert_eq(modes[0], Editable)
  assert_eq(modes[1], On)
  assert_eq(modes[2], Off)
}

///|
test "ShowFoldingControls exposes every canonical mode" {
  let modes : Array[@editor_api.ShowFoldingControls] = [
    Always,
    Never,
    Mouseover,
  ]
  assert_eq(modes.length(), 3)
  assert_eq(modes[0], Always)
  assert_eq(modes[1], Never)
  assert_eq(modes[2], Mouseover)
}
