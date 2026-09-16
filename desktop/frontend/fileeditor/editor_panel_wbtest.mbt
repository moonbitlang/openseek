///|
test "in-place model replacement preserves view state" {
  let current = @common.Uri::from(
    scheme="openseek",
    authority="local",
    path="/work/src/main.mbt",
  )
  let other = @common.Uri::from(
    scheme="openseek",
    authority="local",
    path="/work/src/other.mbt",
  )
  assert_true(should_restore_view_state(false, Some(current), current))
  assert_false(should_restore_view_state(false, Some(other), current))
  assert_false(should_restore_view_state(false, None, current))
  assert_true(should_restore_view_state(true, Some(other), current))
}

///|
test "symbol navigation highlights the exact target without a selection" {
  let range = @common.Range(7, 3, 7, 12)
  let target = navigation_target_presentation(range)
  assert_eq(target.position, Position(7, 3))
  assert_eq(target.decoration.range, range)
  assert_eq(target.decoration.options.class_name, "symbolHighlight")
  assert_eq(
    target.decoration.options.description,
    "symbol-navigate-action-highlight",
  )
  assert_false(target.decoration.options.is_whole_line)
  assert_true(target.is_transient)
}

///|
test "point navigation keeps its column and highlights the whole line" {
  let target = navigation_target_presentation(Range(9, 17, 9, 17))
  assert_eq(target.position, Position(9, 17))
  assert_eq(target.decoration.range, Range(9, 1, 9, 1))
  assert_eq(target.decoration.options.class_name, "rangeHighlight")
  assert_eq(target.decoration.options.description, "point-range-line-highlight")
  assert_true(target.decoration.options.is_whole_line)
  assert_false(target.is_transient)
}

///|
/// Behavior port of VS Code
/// `searchTreeModel/fileMatch.ts::FileMatchImpl.updateHighlights` at pinned
/// revision b18492a2: every file match is decorated. OpenSeek intentionally
/// keeps one presentation for readability instead of promoting a current row.
test "workspace Search decorates every match with one readable style" {
  let decorations = search_match_decorations([
    Range(2, 1, 2, 5),
    Range(4, 7, 4, 11),
    Range(9, 3, 9, 7),
  ])
  assert_eq(decorations.length(), 3)
  assert_eq(decorations[0].range, Range(2, 1, 2, 5))
  assert_eq(decorations[0].options.class_name, "findMatch")
  assert_eq(decorations[0].options.inline_class_name, Some("findMatchInline"))
  assert_eq(decorations[0].options.z_index, 10)
  assert_eq(decorations[0].options.stickiness, NeverGrowsWhenTypingAtEdges)
  assert_eq(decorations[1].range, Range(4, 7, 4, 11))
  assert_eq(decorations[1].options.class_name, "findMatch")
  assert_eq(decorations[1].options.inline_class_name, Some("findMatchInline"))
  assert_eq(decorations[1].options.z_index, 10)
  assert_eq(decorations[2].options.class_name, "findMatch")
}
