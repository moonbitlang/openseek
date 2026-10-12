///|
fn alignment_test_state(
  changes : Array[@diff.DetailedLineRangeMapping],
  ignored_mappings : Array[@diff.LineRangeMapping],
  original_line_count : Int32,
  modified_line_count : Int32,
) -> DiffState {
  ignore(original_line_count)
  ignore(modified_line_count)
  let entries = changes.map(mapping => @diff.DocumentDiffChange(mapping))
  entries.append(
    ignored_mappings.map(mapping => {
      DocumentDiffChange(
        DetailedLineRangeMapping(mapping.original, mapping.modified, None),
        kind=Ignored,
      )
    }),
  )
  entries.sort_by((left, right) => {
    let old_order = left.mapping.original.start_line_number -
      right.mapping.original.start_line_number
    if old_order != 0 {
      old_order
    } else {
      left.mapping.modified.start_line_number -
      right.mapping.modified.start_line_number
    }
  })
  DiffState::from_diff_result({ changes: entries, })
}

///|
fn alignment_test_change(
  original_start : Int32,
  original_end : Int32,
  modified_start : Int32,
  modified_end : Int32,
  inner_changes? : Array[@diff.RangeMapping],
) -> @diff.DetailedLineRangeMapping {
  DetailedLineRangeMapping(
    LineRange(original_start, original_end),
    LineRange(modified_start, modified_end),
    inner_changes,
  )
}

///|
test "geometry alignment handles unequal insert delete and replace hunks" {
  let diff_state = alignment_test_state(
    [
      alignment_test_change(3, 3, 3, 5),
      alignment_test_change(8, 11, 10, 10),
      alignment_test_change(14, 16, 13, 17),
    ],
    [],
    16,
    17,
  )
  let spacers = compute_managed_alignment_spacers(
    diff_state,
    PaneGeometrySnapshot(16, 20.0),
    PaneGeometrySnapshot(17, 20.0),
  )
  assert_eq(spacers.original(), [
    { after_line_number: 2, height_in_px: 40.0, },
    { after_line_number: 15, height_in_px: 40.0, },
  ])
  assert_eq(spacers.modified(), [{ after_line_number: 9, height_in_px: 60.0, }])
}

///|
test "wrapped model lines align from exact per-line pixel heights" {
  let diff_state = alignment_test_state([], [], 4, 4)
  let spacers = compute_managed_alignment_spacers(
    diff_state,
    PaneGeometrySnapshot(4, 20.0, model_line_heights=[
      { line_number: 2, height_in_px: 40.0, },
    ]),
    PaneGeometrySnapshot(4, 20.0),
  )
  assert_true(spacers.original().is_empty())
  assert_eq(spacers.modified(), [{ after_line_number: 2, height_in_px: 20.0, }])
}

///|
test "foreign zones align unmodified spans at their model boundaries" {
  let diff_state = alignment_test_state([], [], 10, 10)
  let spacers = compute_managed_alignment_spacers(
    diff_state,
    PaneGeometrySnapshot(10, 20.0, foreign_zone_heights=[
      { after_line_number: 3, height_in_px: 30.0, },
      { after_line_number: 8, height_in_px: 5.0, },
    ]),
    PaneGeometrySnapshot(10, 20.0, foreign_zone_heights=[
      { after_line_number: 3, height_in_px: 10.0, },
      { after_line_number: 6, height_in_px: 25.0, },
    ]),
  )
  assert_eq(spacers.original(), [{ after_line_number: 6, height_in_px: 25.0, }])
  assert_eq(spacers.modified(), [
    { after_line_number: 3, height_in_px: 20.0, },
    { after_line_number: 8, height_in_px: 5.0, },
  ])
}

///|
test "hidden source projection is one atomic geometry event at its final boundary" {
  let diff_state = alignment_test_state([], [], 4, 4)
  let hidden_only = compute_managed_alignment_spacers(
    diff_state,
    PaneGeometrySnapshot(4, 20.0, hidden_lines=[LineRange(2, 3)]),
    PaneGeometrySnapshot(4, 20.0),
  )
  assert_eq(hidden_only.original(), [
    { after_line_number: 2, height_in_px: 20.0, },
  ])
  assert_true(hidden_only.modified().is_empty())

  let hidden_with_zone = compute_managed_alignment_spacers(
    diff_state,
    PaneGeometrySnapshot(4, 20.0, hidden_lines=[LineRange(2, 3)], foreign_zone_heights=[
      { after_line_number: 2, height_in_px: 50.0, },
    ]),
    PaneGeometrySnapshot(4, 20.0),
  )
  assert_true(hidden_with_zone.original().is_empty())
  assert_eq(hidden_with_zone.modified(), [
    { after_line_number: 2, height_in_px: 30.0, },
  ])
}

///|
test "Markdown comment replacement subtracts the complete hidden source block once" {
  let diff_state = alignment_test_state([], [], 6, 6)
  let taller_rich_comment = compute_managed_alignment_spacers(
    diff_state,
    PaneGeometrySnapshot(6, 20.0),
    PaneGeometrySnapshot(6, 20.0, hidden_lines=[LineRange(2, 5)], foreign_zone_heights=[
      { after_line_number: 4, height_in_px: 90.0, },
    ]),
  )
  assert_eq(taller_rich_comment.original(), [
    { after_line_number: 4, height_in_px: 30.0, },
  ])
  assert_true(taller_rich_comment.modified().is_empty())

  let shorter_rich_comment = compute_managed_alignment_spacers(
    diff_state,
    PaneGeometrySnapshot(6, 20.0),
    PaneGeometrySnapshot(6, 20.0, hidden_lines=[LineRange(2, 5)], foreign_zone_heights=[
      { after_line_number: 4, height_in_px: 40.0, },
    ]),
  )
  assert_true(shorter_rich_comment.original().is_empty())
  assert_eq(shorter_rich_comment.modified(), [
    { after_line_number: 4, height_in_px: 20.0, },
  ])
}

///|
test "SideBySide replacement aligns rich comment zones instead of hidden source lengths" {
  let diff_state = alignment_test_state(
    [alignment_test_change(2, 5, 2, 6)],
    [],
    6,
    7,
  )
  let spacers = compute_managed_alignment_spacers(
    diff_state,
    PaneGeometrySnapshot(6, 20.0, hidden_lines=[LineRange(2, 5)], foreign_zone_heights=[
      { after_line_number: 4, height_in_px: 50.0, },
    ]),
    PaneGeometrySnapshot(7, 20.0, hidden_lines=[LineRange(2, 6)], foreign_zone_heights=[
      { after_line_number: 5, height_in_px: 80.0, },
    ]),
  )
  assert_eq(spacers.original(), [{ after_line_number: 4, height_in_px: 30.0, }])
  assert_true(spacers.modified().is_empty())
}

///|
test "ignored changes align omitted geometry without visible differences" {
  let additional = @diff.LineRangeMapping(LineRange(2, 2), LineRange(2, 3))
  let diff_state = alignment_test_state([], [additional], 3, 4)
  assert_eq(diff_state.visible_mappings().length(), 0)
  let spacers = compute_managed_alignment_spacers(
    diff_state,
    PaneGeometrySnapshot(3, 20.0),
    PaneGeometrySnapshot(4, 20.0),
  )
  assert_eq(spacers.original(), [{ after_line_number: 1, height_in_px: 20.0, }])
  assert_true(spacers.modified().is_empty())
}

///|
test "character mappings add synchronization points inside a real hunk" {
  let original_inner = @base_common.Range(2, 5, 3, 4)
  let modified_inner = @base_common.Range(2, 5, 4, 4)
  let change = alignment_test_change(2, 6, 2, 8, inner_changes=[
    RangeMapping(original_inner, modified_inner),
  ])
  let diff_state = alignment_test_state([change], [], 7, 9)
  let spacers = compute_managed_alignment_spacers(
    diff_state,
    PaneGeometrySnapshot(7, 20.0, line_max_columns=Array::make(7, 100)),
    PaneGeometrySnapshot(9, 20.0),
  )
  assert_eq(spacers.original(), [
    { after_line_number: 2, height_in_px: 20.0, },
    { after_line_number: 5, height_in_px: 20.0, },
  ])
  assert_true(spacers.modified().is_empty())
}

///|
test "Inline alignment keeps one canonical diff per hunk" {
  let change = alignment_test_change(2, 6, 2, 8, inner_changes=[
    RangeMapping(Range(2, 5, 3, 4), Range(2, 5, 4, 4)),
  ])
  let additional = @diff.LineRangeMapping(LineRange(9, 9), LineRange(11, 12))
  let alignments = compute_inline_range_alignments(
    alignment_test_state([change], [additional], 10, 13),
    PaneGeometrySnapshot(10, 20.0),
    PaneGeometrySnapshot(13, 20.0),
  )
  assert_eq(alignments.length(), 2)
  assert_true(alignments[0].diff is Some(_))
  assert_eq(alignments[0].original_range, LineRange(2, 6))
  assert_eq(alignments[0].modified_range, LineRange(2, 8))
  assert_true(alignments[1].diff is None)
}

///|
test "Inline balances a final-line diff inside compact rich Markdown geometry" {
  let change = alignment_test_change(6, 7, 6, 7)
  let alignments = compute_inline_range_alignments(
    alignment_test_state([change], [], 8, 8),
    PaneGeometrySnapshot(8, 20.0),
    PaneGeometrySnapshot(8, 20.0, hidden_lines=[LineRange(2, 7)], foreign_zone_heights=[
      { after_line_number: 6, height_in_px: 20.0, },
    ]),
  )
  assert_eq(alignments.length(), 1)
  assert_true(alignments[0].diff is Some(_))
  assert_eq(alignments[0].original_height_in_px, 20.0)
  // Five hidden source lines contribute -100px and their initial one-line
  // rich ViewZone contributes +20px. Charging that atomic -80px delta to the
  // final one-line hunk makes its signed modified height -60px.
  assert_eq(alignments[0].modified_height_in_px, -60.0)
  let (original_companion, modified_compensation) = inline_companion_spacer_heights(
    alignments[0].modified_height_in_px,
  )
  assert_eq(original_companion, 0.0)
  assert_eq(modified_compensation, 60.0)
}

///|
test "final-line geometry is an ordinary boundary not a tail correction" {
  let diff_state = alignment_test_state([], [], 3, 3)
  let original = PaneGeometrySnapshot(
    3,
    20.0,
    model_line_heights=[{ line_number: 3, height_in_px: 60.0, }],
    foreign_zone_heights=[{ after_line_number: 3, height_in_px: 10.0, }],
  )
  let modified = PaneGeometrySnapshot(3, 20.0)
  let spacers = compute_managed_alignment_spacers(
    diff_state, original, modified,
  )
  assert_true(spacers.original().is_empty())
  assert_eq(spacers.modified(), [{ after_line_number: 3, height_in_px: 50.0, }])
  assert_eq(
    original.content_height(),
    modified.content_height() + spacers.modified()[0].height_in_px,
  )
}

///|
test "snapshot normalizes duplicate foreign zones and excludes invalid input" {
  let geometry = PaneGeometrySnapshot(3, 20.0, foreign_zone_heights=[
    { after_line_number: 0, height_in_px: 7.0, },
    { after_line_number: 2, height_in_px: 8.0, },
    { after_line_number: 2, height_in_px: 12.0, },
    { after_line_number: 4, height_in_px: 99.0, },
    { after_line_number: 1, height_in_px: -3.0, },
  ])
  assert_eq(geometry.foreign_zone_heights(), [
    { after_line_number: 0, height_in_px: 7.0, },
    { after_line_number: 2, height_in_px: 20.0, },
  ])
  assert_eq(geometry.content_height(), 87.0)
}
