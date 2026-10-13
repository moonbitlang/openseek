///|
fn widget_navigation_test_change(
  original_start : Int32,
  original_end : Int32,
  modified_start : Int32,
  modified_end : Int32,
) -> @diff.DetailedLineRangeMapping {
  DetailedLineRangeMapping(
    LineRange(original_start, original_end),
    LineRange(modified_start, modified_end),
    None,
  )
}

///|
test "Inline navigation always uses the modified pane and clamps deletion anchors" {
  let deletion = widget_navigation_test_change(6, 7, 6, 6)
  let plan = diff_navigation_reveal_plan(Inline, deletion, 7, 5).unwrap()
  assert_true(plan.pane is ModifiedNavigationPane)
  assert_eq(plan.range, Range(5, 1, 5, 1))
  assert_true(plan.range.is_empty())

  let empty_document_plan = diff_navigation_reveal_plan(
    Inline,
    widget_navigation_test_change(1, 2, 1, 1),
    1,
    0,
  ).unwrap()
  assert_true(empty_document_plan.pane is ModifiedNavigationPane)
  assert_eq(empty_document_plan.range, Range(1, 1, 1, 1))
}

///|
test "side-by-side navigation always uses the modified pane" {
  let deletion = diff_navigation_reveal_plan(
    SideBySide,
    widget_navigation_test_change(2, 3, 2, 2),
    4,
    3,
  ).unwrap()
  assert_true(deletion.pane is ModifiedNavigationPane)
  assert_eq(deletion.range, Range(2, 1, 2, 1))

  let insertion = diff_navigation_reveal_plan(
    SideBySide,
    widget_navigation_test_change(3, 3, 3, 4),
    3,
    4,
  ).unwrap()
  assert_true(insertion.pane is ModifiedNavigationPane)
  assert_eq(insertion.range, Range(3, 1, 4, 1))

  let modification = diff_navigation_reveal_plan(
    SideBySide,
    widget_navigation_test_change(4, 5, 4, 5),
    5,
    5,
  ).unwrap()
  assert_true(modification.pane is ModifiedNavigationPane)
  assert_eq(modification.range, Range(4, 1, 5, 1))
}

///|
test "navigation announcements name insertion and deletion anchors" {
  let deletion = widget_navigation_test_change(6, 7, 6, 6)
  assert_eq(
    diff_navigation_announcement({
      change_index: 0,
      change_count: 2,
      change: deletion,
    }),
    "Change 1 of 2; original lines 6 through 6; modified deletion anchor at line 6",
  )

  let insertion = widget_navigation_test_change(3, 3, 3, 4)
  assert_eq(
    diff_navigation_announcement({
      change_index: 1,
      change_count: 2,
      change: insertion,
    }),
    "Change 2 of 2; original insertion anchor at line 3; modified lines 3 through 3",
  )
}

///|
test "grouped navigation reveals and announces the joined mapping" {
  let grouped = widget_navigation_test_change(20, 32, 24, 37)
  let plan = diff_navigation_reveal_plan(SideBySide, grouped, 100, 100).unwrap()
  assert_true(plan.pane is ModifiedNavigationPane)
  assert_eq(plan.range, Range(24, 1, 37, 1))
  assert_eq(
    diff_navigation_announcement({
      change_index: 12,
      change_count: 31,
      change: grouped,
    }),
    "Change 13 of 31; original lines 20 through 31; modified lines 24 through 36",
  )
}
