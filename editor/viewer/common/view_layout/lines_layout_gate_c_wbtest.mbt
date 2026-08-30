///|
fn gate_c_insert_whitespace(
  layout : LinesLayout,
  after_line_number : Int,
  ordinal : Int,
  height : Int,
  min_width : Int,
) -> String {
  let id = Ref("")
  layout.change_whitespace(accessor => {
    id.val = accessor.insert_whitespace(
      after_line_number,
      ordinal,
      height.to_double(),
      min_width.to_double(),
    )
  })
  |> ignore
  id.val
}

///|
fn gate_c_assert_rows(
  layout : LinesLayout,
  expected_ids : Array[String],
  expected_after_line_numbers : Array[Int],
  expected_ordinals : Array[Int],
  expected_heights : Array[Int],
) -> Unit raise {
  let rows = layout.get_whitespaces()
  assert_eq(rows.length(), expected_ids.length())
  assert_eq(rows.length(), expected_after_line_numbers.length())
  assert_eq(rows.length(), expected_ordinals.length())
  assert_eq(rows.length(), expected_heights.length())
  for i in 0..<rows.length() {
    assert_eq(rows[i].id, expected_ids[i])
    assert_eq(rows[i].after_line_number, expected_after_line_numbers[i])
    assert_eq(rows[i].ordinal, expected_ordinals[i])
    assert_eq(rows[i].height, expected_heights[i])
  }
}

///|
test "LinesLayout setters update line geometry, padding, and whitespace state" {
  let layout = LinesLayout(3, 10, 2, 3)
  assert_false(layout.has_whitespace())
  assert_eq(layout.get_line_height_for_line_number(2), 10)
  assert_eq(layout.get_lines_total_height(), 35)
  assert_eq(layout.get_vertical_offset_for_line_number(1), 2)
  assert_eq(layout.get_vertical_offset_after_line_number(3), 32)
  assert_true(layout.is_in_top_padding(0))
  assert_true(layout.is_in_top_padding(1))
  assert_false(layout.is_in_top_padding(2))
  assert_false(layout.is_in_bottom_padding(31))
  assert_true(layout.is_in_bottom_padding(32))

  layout.set_default_line_height(7)
  layout.set_padding(5, 11)
  assert_eq(layout.get_line_height_for_line_number(2), 7)
  assert_eq(layout.get_lines_total_height(), 37)
  assert_eq(layout.get_vertical_offset_for_line_number(1), 5)
  assert_eq(layout.get_vertical_offset_for_line_number(2), 12)
  assert_eq(layout.get_vertical_offset_after_line_number(3), 26)
  assert_true(layout.is_in_top_padding(4))
  assert_false(layout.is_in_top_padding(5))
  assert_false(layout.is_in_bottom_padding(25))
  assert_true(layout.is_in_bottom_padding(26))

  let id = gate_c_insert_whitespace(layout, 1, 0, 4, 0)
  assert_true(layout.has_whitespace())
  assert_eq(layout.get_lines_total_height(), 41)
  assert_eq(layout.get_vertical_offset_for_line_number(2), 16)
  assert_true(
    layout.change_whitespace(accessor => accessor.remove_whitespace(id)),
  )
  assert_false(layout.has_whitespace())
  assert_eq(layout.get_lines_total_height(), 37)
}

///|
test "LinesLayout min-width cache hits and invalidates on inserts and removes" {
  let layout = LinesLayout(4, 10, 0, 0)
  assert_eq(layout.min_width, -1)
  assert_eq(layout.get_whitespace_min_width(), 0)
  assert_eq(layout.min_width, 0)
  assert_eq(layout.get_whitespace_min_width(), 0)
  assert_eq(layout.min_width, 0)

  let low = gate_c_insert_whitespace(layout, 1, 0, 12, 12)
  assert_eq(layout.min_width, -1)
  let high_a = gate_c_insert_whitespace(layout, 2, 0, 13, 40)
  let high_b = gate_c_insert_whitespace(layout, 3, 0, 14, 40)
  let medium = gate_c_insert_whitespace(layout, 4, 0, 15, 25)
  assert_eq(layout.min_width, -1)
  assert_eq(layout.get_whitespace_min_width(), 40)
  assert_eq(layout.min_width, 40)

  // A height/anchor-only change must take the already-computed cache hit.
  assert_true(
    layout.change_whitespace(accessor => {
      accessor.change_one_whitespace(low, 1, 22.0)
    }),
  )
  assert_eq(layout.min_width, 40)
  assert_eq(layout.get_whitespace_min_width(), 40)

  assert_true(
    layout.change_whitespace(accessor => accessor.remove_whitespace(high_a)),
  )
  assert_eq(layout.min_width, -1)
  // Removing one of multiple maxima keeps the other maximum after recompute.
  assert_eq(layout.get_whitespace_min_width(), 40)
  assert_true(
    layout.change_whitespace(accessor => accessor.remove_whitespace(high_b)),
  )
  assert_eq(layout.min_width, -1)
  assert_eq(layout.get_whitespace_min_width(), 25)

  let peak = gate_c_insert_whitespace(layout, 0, 0, 1, 60)
  assert_eq(layout.min_width, -1)
  assert_eq(layout.get_whitespace_min_width(), 60)
  assert_true(
    layout.change_whitespace(accessor => accessor.remove_whitespace(peak)),
  )
  assert_eq(layout.min_width, -1)
  assert_eq(layout.get_whitespace_min_width(), 25)
  assert_eq(layout.get_whitespaces_count(), 2)
  assert_true(layout.get_whitespaces().any(row => row.id == low))
  assert_true(layout.get_whitespaces().any(row => row.id == medium))
}

///|
test "LinesLayout delicate missing-id changes and removes are harmless" {
  let layout = LinesLayout(3, 10, 0, 0)
  let present = gate_c_insert_whitespace(layout, 1, 7, 9, 21)
  assert_eq(layout.get_whitespaces_accumulated_height(0), 9)
  assert_eq(layout.prefix_sum_valid_index, 0)
  assert_eq(layout.get_whitespace_min_width(), 21)

  assert_true(
    layout.change_whitespace(accessor => {
      accessor.change_one_whitespace("missing-change", 3, 99.0)
    }),
  )
  assert_eq(layout.get_whitespaces_count(), 1)
  assert_eq(layout.get_id_for_whitespace_index(0), present)
  assert_eq(layout.get_after_line_number_for_whitespace_index(0), 1)
  assert_eq(layout.get_height_for_whitespace_index(0), 9)
  assert_eq(layout.prefix_sum_valid_index, 0)
  assert_eq(layout.min_width, 21)

  assert_true(
    layout.change_whitespace(accessor => {
      accessor.remove_whitespace("missing-remove")
    }),
  )
  assert_eq(layout.get_whitespaces_count(), 1)
  assert_eq(layout.get_id_for_whitespace_index(0), present)
  assert_eq(layout.get_whitespaces_accumulated_height(0), 9)
  assert_eq(layout.prefix_sum_valid_index, 0)
  // Monaco invalidates min-width for every queued remove, even a missing id.
  assert_eq(layout.min_width, -1)
  assert_eq(layout.get_whitespace_min_width(), 21)
}

///|
test "LinesLayout mixed bulk commit resolves conflicts, stably sorts, and resets prefixes" {
  let layout = LinesLayout(10, 10, 0, 0)
  let old_primary_before = gate_c_insert_whitespace(layout, 2, 9, 50, 0)
  let old_ordinal_before = gate_c_insert_whitespace(layout, 4, 1, 51, 0)
  let old_peers : Array[String] = []
  for i in 0..<20 {
    old_peers.push(gate_c_insert_whitespace(layout, 4, 2, i + 1, 0))
  }
  let old_primary_after = gate_c_insert_whitespace(layout, 6, 0, 52, 0)
  assert_eq(layout.get_whitespaces_total_height(), 363)
  assert_eq(layout.prefix_sum_valid_index, 22)

  let inserted_peers : Array[String] = []
  let inserted_primary_before = Ref("")
  let inserted_ordinal_before = Ref("")
  let inserted_ordinal_after = Ref("")
  let inserted_primary_after = Ref("")
  assert_true(
    layout.change_whitespace(accessor => {
      for i in 0..<20 {
        inserted_peers.push(
          accessor.insert_whitespace(4, 2, (1000 + i).to_double(), 0.0),
        )
      }
      inserted_primary_before.val = accessor.insert_whitespace(3, 99, 60.0, 0.0)
      inserted_ordinal_before.val = accessor.insert_whitespace(4, 0, 61.0, 0.0)
      inserted_ordinal_after.val = accessor.insert_whitespace(4, 3, 62.0, 0.0)
      inserted_primary_after.val = accessor.insert_whitespace(7, -9, 63.0, 0.0)

      // Zero operations: peer[0]. One operation: peer[1]. More than one:
      // peer[2] (last change wins), peer[3]/peer[4] (remove wins).
      accessor.change_one_whitespace(old_peers[1], 4, 101.0)
      accessor.change_one_whitespace(old_peers[2], 4, 201.0)
      accessor.change_one_whitespace(old_peers[2], 4, 202.0)
      accessor.change_one_whitespace(old_peers[3], 4, 303.0)
      accessor.remove_whitespace(old_peers[3])
      accessor.remove_whitespace(old_peers[4])
      accessor.remove_whitespace(old_peers[4])
      accessor.change_one_whitespace(old_peers[4], 4, 404.0)
      accessor.change_one_whitespace(old_primary_after, 6, 152.0)

      accessor.change_one_whitespace(inserted_peers[1], 4, 1101.0)
      accessor.change_one_whitespace(inserted_peers[2], 4, 1201.0)
      accessor.change_one_whitespace(inserted_peers[2], 4, 1202.0)
      accessor.change_one_whitespace(inserted_peers[3], 4, 1303.0)
      accessor.remove_whitespace(inserted_peers[3])
      accessor.remove_whitespace(inserted_peers[4])
      accessor.remove_whitespace(inserted_peers[4])
      accessor.change_one_whitespace(inserted_peers[4], 4, 1404.0)

      accessor.change_one_whitespace("missing", 1, 1.0)
      accessor.change_one_whitespace("missing", 9, 9.0)
      accessor.remove_whitespace("missing")
      accessor.remove_whitespace("missing")
    }),
  )

  // Every bulk commit replaces the array and invalidates the whole prefix
  // cache before the first post-commit accumulated-height query.
  assert_eq(layout.prefix_sum_valid_index, -1)
  let expected_ids : Array[String] = [
    old_primary_before,
    inserted_primary_before.val,
    inserted_ordinal_before.val,
    old_ordinal_before,
  ]
  let expected_after_line_numbers : Array[Int] = [2, 3, 4, 4]
  let expected_ordinals : Array[Int] = [9, 99, 0, 1]
  let expected_heights : Array[Int] = [50, 60, 61, 51]
  for i in 0..<20 {
    if i != 3 && i != 4 {
      expected_ids.push(old_peers[i])
      expected_after_line_numbers.push(4)
      expected_ordinals.push(2)
      expected_heights.push(
        if i == 1 {
          101
        } else if i == 2 {
          202
        } else {
          i + 1
        },
      )
    }
  }
  for i in 0..<20 {
    if i != 3 && i != 4 {
      expected_ids.push(inserted_peers[i])
      expected_after_line_numbers.push(4)
      expected_ordinals.push(2)
      expected_heights.push(
        if i == 1 {
          1101
        } else if i == 2 {
          1202
        } else {
          1000 + i
        },
      )
    }
  }
  expected_ids.push(inserted_ordinal_after.val)
  expected_after_line_numbers.push(4)
  expected_ordinals.push(3)
  expected_heights.push(62)
  expected_ids.push(old_primary_after)
  expected_after_line_numbers.push(6)
  expected_ordinals.push(0)
  expected_heights.push(152)
  expected_ids.push(inserted_primary_after.val)
  expected_after_line_numbers.push(7)
  expected_ordinals.push(-9)
  expected_heights.push(63)
  gate_c_assert_rows(
    layout, expected_ids, expected_after_line_numbers, expected_ordinals, expected_heights,
  )

  let mut running_height = 0.0
  for i, height in expected_heights {
    running_height += height.to_double()
    assert_eq(layout.get_whitespaces_accumulated_height(i), running_height)
    assert_eq(layout.arr[i].prefix_sum, running_height)
  }
  assert_eq(layout.prefix_sum_valid_index, expected_heights.length() - 1)
  assert_eq(layout.get_whitespaces_total_height(), running_height)
}

///|
test "LinesLayout bulk ordering matches delicate inserts at Int extremes" {
  let entries : Array[(Int, Int, Int)] = [
    (2147483647, 2147483647, 1),
    (-2147483648, 2147483647, 2),
    (0, 2147483647, 3),
    (0, -2147483648, 4),
    (-2147483648, -2147483648, 5),
    (2147483647, -2147483648, 6),
    (0, 0, 7),
    (0, 0, 8),
  ]
  let delicate = LinesLayout(1, 10, 0, 0)
  for entry in entries {
    let (after_line_number, ordinal, height) = entry
    gate_c_insert_whitespace(delicate, after_line_number, ordinal, height, 0)
    |> ignore
  }
  let bulk = LinesLayout(1, 10, 0, 0)
  bulk.change_whitespace(accessor => {
    for entry in entries {
      let (after_line_number, ordinal, height) = entry
      accessor.insert_whitespace(
        after_line_number,
        ordinal,
        height.to_double(),
        0.0,
      )
      |> ignore
    }
  })
  |> ignore

  let delicate_rows = delicate.get_whitespaces()
  let bulk_rows = bulk.get_whitespaces()
  assert_eq(delicate_rows.length(), entries.length())
  assert_eq(bulk_rows.length(), entries.length())
  for i in 0..<entries.length() {
    assert_eq(
      bulk_rows[i].after_line_number,
      delicate_rows[i].after_line_number,
    )
    assert_eq(bulk_rows[i].ordinal, delicate_rows[i].ordinal)
    // Heights uniquely identify input order, including the equal-key pair.
    assert_eq(bulk_rows[i].height, delicate_rows[i].height)
  }
}
