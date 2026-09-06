///|
fn diff_state_test_change(
  original_start : Int,
  original_end : Int,
  modified_start : Int,
  modified_end : Int,
) -> @diff.DetailedLineRangeMapping {
  DetailedLineRangeMapping(
    LineRange(original_start, original_end),
    LineRange(modified_start, modified_end),
    None,
  )
}

///|
test "DiffState preserves canonical provider order" {
  let first = diff_state_test_change(1, 1, 1, 2)
  let second = diff_state_test_change(3, 4, 4, 5)
  let state = DiffState::from_diff_result({
    changes: [first, second],
    additional_alignments: [],
  })
  assert_eq(state.mappings[0].line_range_mapping, first)
  assert_eq(state.mappings[1].line_range_mapping, second)
}

///|
test "Accessible F7 groups mappings whose three-line contexts overlap" {
  let state = DiffState::from_diff_result({
    changes: [
      diff_state_test_change(2, 3, 2, 3),
      diff_state_test_change(7, 8, 7, 8),
    ],
    additional_alignments: [],
  })
  let groups = state.navigation_changes()
  assert_eq(state.mappings.length(), 2)
  assert_eq(groups.length(), 1)
  assert_eq(groups[0].original, LineRange(2, 8))
  assert_eq(groups[0].modified, LineRange(2, 8))
  assert_true(groups[0].inner_changes is None)
  let target = state.next_change_from_modified_line(1, 10).unwrap()
  assert_eq(target.change_index, 0)
  assert_eq(target.change_count, 1)
  assert_eq(target.change, groups[0])
}

///|
test "product hunk members exclude unchanged joined gaps" {
  let first = diff_state_test_change(2, 3, 2, 3)
  let second = diff_state_test_change(7, 8, 7, 8)
  let hunk = DiffState::from_diff_result({
      changes: [first, second],
      additional_alignments: [],
    }).hunks()[0]
  assert_eq(hunk.members, [first, second])
}

///|
test "Accessible F7 keeps mappings separate at an exact six-line gap" {
  let state = DiffState::from_diff_result({
    changes: [
      diff_state_test_change(2, 3, 2, 3),
      diff_state_test_change(9, 10, 9, 10),
    ],
    additional_alignments: [],
  })
  assert_eq(state.navigation_changes().length(), 2)
  assert_eq(
    state.next_change_from_modified_line(2, 12).unwrap().change_index,
    1,
  )
}

///|
test "grouped F7 navigation starts at the modified cursor and wraps" {
  let state = DiffState::from_diff_result({
    changes: [
      diff_state_test_change(2, 3, 2, 3),
      diff_state_test_change(6, 7, 6, 6),
      diff_state_test_change(12, 13, 12, 13),
      diff_state_test_change(19, 20, 19, 20),
    ],
    additional_alignments: [],
  })
  // The first two mappings form one group; the later exact-six-line gaps do
  // not. Selection remains relative to each group's modified start line.
  assert_eq(
    state.next_change_from_modified_line(1, 20).unwrap().change_index,
    0,
  )
  assert_eq(
    state.next_change_from_modified_line(2, 20).unwrap().change_index,
    1,
  )
  assert_eq(
    state.next_change_from_modified_line(19, 20).unwrap().change_index,
    0,
  )
  assert_eq(
    state.previous_change_from_modified_line(19).unwrap().change_index,
    1,
  )
  assert_eq(
    state.previous_change_from_modified_line(2).unwrap().change_index,
    2,
  )
  let first_group = state.previous_change_from_modified_line(7).unwrap()
  assert_eq(first_group.change_index, 0)
  assert_eq(first_group.change.modified, LineRange(2, 6))
}

///|
test "multi-diff navigation detects an item boundary without wrapping" {
  let state = DiffState::from_diff_result({
    changes: [
      diff_state_test_change(2, 3, 2, 3),
      diff_state_test_change(9, 10, 9, 10),
    ],
    additional_alignments: [],
  })
  assert_eq(
    state.next_change_from_modified_line_without_wrap(2).unwrap().change_index,
    1,
  )
  assert_true(state.next_change_from_modified_line_without_wrap(9) is None)
  assert_eq(
    state.previous_change_from_modified_line_without_wrap(9).unwrap().change_index,
    0,
  )
  assert_true(state.previous_change_from_modified_line_without_wrap(2) is None)
}

///|
test "multi-diff next includes an EOF deletion anchor" {
  let state = DiffState::from_diff_result({
    changes: [diff_state_test_change(11, 12, 11, 11)],
    additional_alignments: [],
  })
  assert_eq(
    state.next_change_from_modified_line_without_wrap(10).unwrap().change_index,
    0,
  )
}

///|
test "next F7 at the last modified line wraps before an EOF deletion anchor" {
  let state = DiffState::from_diff_result({
    changes: [
      diff_state_test_change(2, 3, 2, 3),
      diff_state_test_change(11, 12, 11, 11),
    ],
    additional_alignments: [],
  })
  assert_eq(
    state.next_change_from_modified_line(10, 10).unwrap().change_index,
    0,
  )
}

///|
test "standalone deletion navigation retains an empty modified anchor" {
  let state = DiffState::from_diff_result({
    changes: [
      diff_state_test_change(2, 3, 2, 3),
      diff_state_test_change(9, 10, 9, 9),
    ],
    additional_alignments: [],
  })
  let deletion = state.next_change_from_modified_line(2, 10).unwrap()
  assert_eq(deletion.change_index, 1)
  assert_eq(deletion.change_count, 2)
  assert_eq(deletion.change.original, LineRange(9, 10))
  assert_eq(deletion.change.modified, LineRange(9, 9))
}

///|
test "real-widget-sized navigation projection groups fifty-seven mappings into thirty-one" {
  let changes : Array[@diff.DetailedLineRangeMapping] = []
  let mut line = 1
  for group_index in 0..<31 {
    changes.push(diff_state_test_change(line, line + 1, line, line + 1))
    if group_index < 26 {
      changes.push(
        diff_state_test_change(line + 3, line + 4, line + 3, line + 4),
      )
      line += 10
    } else {
      line += 7
    }
  }
  let state = DiffState::from_diff_result({
    changes,
    additional_alignments: [],
  })
  assert_eq(state.mappings.length(), 57)
  assert_eq(state.navigation_changes().length(), 31)
  assert_eq(
    state.next_change_from_modified_line(1, line).unwrap().change_count,
    31,
  )
}

///|
test "cursor-relative navigation has no target for an empty diff" {
  let state = DiffState::from_diff_result({
    changes: [],
    additional_alignments: [],
  })
  assert_true(state.next_change_from_modified_line(1, 1) is None)
  assert_true(state.previous_change_from_modified_line(1) is None)
}

///|
test "additional alignments enter geometry only" {
  let change = diff_state_test_change(1, 2, 1, 2)
  let additional = @diff.LineRangeMapping(LineRange(3, 3), LineRange(3, 4))
  let state = DiffState::from_diff_result({
    changes: [change],
    additional_alignments: [additional],
  })
  assert_eq(state.mappings.length(), 1)
  assert_eq(state.alignments().length(), 2)
  assert_eq(state.alignments()[0].diff, Some(change))
  assert_eq(state.alignments()[1].line_range_mapping, additional)
  assert_true(state.alignments()[1].diff is None)
}
