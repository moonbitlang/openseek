// Behavior tests for the `DedupOverlay._render` / `LinesDecorationsOverlay.
// _getDecorations` port (`margin_decorations.mbt`). Monaco ships no unit
// tests for these units; the cases mirror the source branches directly.

///|
fn test_decoration(
  start_line : Int32,
  end_line : Int32,
  class_name : String,
  z_index~ : Int32 = 0,
) -> DecorationToRender {
  {
    start_line_number: start_line,
    end_line_number: end_line,
    class_name,
    z_index,
  }
}

///|
test "lines_decorations_to_render filters on lines_decorations_class_name" {
  let with_lane : ViewModelDecoration = {
    range: Range(2, 1, 2, 1),
    options: ModelDecorationOptions(
      "",
      lines_decorations_class_name="comment-range-glyph comment-diff-added",
      is_whole_line=true,
      z_index=3,
    ),
  }
  let without_lane : ViewModelDecoration = {
    range: Range(3, 1, 3, 5),
    options: ModelDecorationOptions("squiggly-error"),
  }
  let rendered = lines_decorations_to_render([without_lane, with_lane])
  assert_eq(rendered.length(), 1)
  assert_eq(rendered[0].start_line_number, 2)
  assert_eq(rendered[0].end_line_number, 2)
  assert_eq(rendered[0].class_name, "comment-range-glyph comment-diff-added")
  assert_eq(rendered[0].z_index, 3)
}

///|
test "dedup expands a multi-line decoration across visible lines" {
  let output = dedup_margin_decorations(1, 5, [
    test_decoration(2, 4, "comment-range-glyph"),
  ])
  assert_eq(output.length(), 5)
  assert_eq(output[0].join(","), "")
  assert_eq(output[1].join(","), "comment-range-glyph")
  assert_eq(output[2].join(","), "comment-range-glyph")
  assert_eq(output[3].join(","), "comment-range-glyph")
  assert_eq(output[4].join(","), "")
}

///|
test "dedup clamps decorations that overflow the visible window" {
  let output = dedup_margin_decorations(3, 4, [test_decoration(1, 9, "glyph")])
  assert_eq(output.length(), 2)
  assert_eq(output[0].join(","), "glyph")
  assert_eq(output[1].join(","), "glyph")
}

///|
test "dedup skips re-rendering the same class on an already covered line" {
  // Two same-class decorations overlapping on line 3: the second starts at
  // `prevEndLineIndex + 1`, so line 3 gets the class once.
  let output = dedup_margin_decorations(1, 4, [
    test_decoration(2, 3, "glyph"),
    test_decoration(3, 4, "glyph"),
  ])
  assert_eq(output[0].join(","), "")
  assert_eq(output[1].join(","), "glyph")
  assert_eq(output[2].join(","), "glyph")
  assert_eq(output[3].join(","), "glyph")
}

///|
test "dedup keeps different classes on the same line" {
  let output = dedup_margin_decorations(1, 2, [
    test_decoration(1, 1, "comment-range-glyph line-hover"),
    test_decoration(1, 1, "comment-range-glyph comment-thread"),
  ])
  assert_eq(output[0].length(), 2)
  assert_true(output[0].contains("comment-range-glyph line-hover"))
  assert_true(output[0].contains("comment-range-glyph comment-thread"))
  assert_eq(output[1].join(","), "")
}
