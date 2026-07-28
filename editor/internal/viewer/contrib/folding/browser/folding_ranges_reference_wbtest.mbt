// Conformance port of Monaco/VS Code's FoldingRanges suite.
//
// Ports: vscode/src/vs/editor/contrib/folding/test/browser/foldingRanges.test.ts
// From the checked-in vscode submodule.
//
// The `computeRanges`-backed cases of the suite (`test max folding regions`,
// `findRange`, `setCollapsed`) live with the indent-range-provider port in
// `indent_range_provider_reference_wbtest.mbt`.

///|
/// The suite's `assertEqualRanges`, over the derived `Eq`/`Debug`.
fn assert_equal_ranges(
  range1 : FoldRange,
  range2 : FoldRange,
  msg : String,
) -> Unit raise {
  if range1 != range2 {
    fail("\{msg}: \{Repr(range1)} != \{Repr(range2)}")
  }
}

///|
/// The suite's `foldRange` literal helper.
fn fold_range(
  from : Int,
  to : Int,
  collapsed? : Bool = false,
  source? : FoldSource = Provider,
  type_? : String,
) -> FoldRange {
  {
    start_line_number: from,
    end_line_number: to,
    type_,
    is_collapsed: collapsed,
    source,
  }
}

///|
test "sanitizeAndMerge1" {
  let region_set1 : Array[FoldRange] = [
    fold_range(0, 100), // invalid, should be removed
    fold_range(1, 100, type_="A"), // valid
    fold_range(1, 100, type_="Z"), // invalid, duplicate start
    fold_range(10, 10), // invalid, should be removed
    fold_range(20, 80, type_="C1"), // valid inside 'B'
    fold_range(22, 80, collapsed=true, type_="D1"), // valid inside 'C1'
    fold_range(90, 101), // invalid, should be removed
  ]
  let region_set2 : Array[FoldRange] = [
    fold_range(20, 80, collapsed=true), // should merge with C1
    fold_range(18, 80, collapsed=true), // invalid, out of order
    fold_range(21, 81, collapsed=true, type_="Z"), // invalid, overlapping
    fold_range(22, 80, collapsed=true, type_="D2"), // should merge with D1
  ]
  let result = FoldingRegions::sanitize_and_merge(
    Ranges(region_set1),
    Ranges(region_set2),
    Some(100),
  )
  assert_eq(result.length(), 3)
  assert_equal_ranges(result[0], fold_range(1, 100, type_="A"), "A1")
  assert_equal_ranges(
    result[1],
    fold_range(20, 80, collapsed=true, type_="C1"),
    "C1",
  )
  assert_equal_ranges(
    result[2],
    fold_range(22, 80, collapsed=true, type_="D1"),
    "D1",
  )
}

///|
test "sanitizeAndMerge2" {
  let region_set1 : Array[FoldRange] = [
    fold_range(1, 100, type_="a1"), // valid
    fold_range(2, 100, type_="a2"), // valid
    fold_range(3, 19, type_="a3"), // valid
    fold_range(20, 71, type_="a4"), // overlaps b3
    fold_range(21, 29, type_="a5"), // valid
    fold_range(81, 91, type_="a6"), // overlaps b4
  ]
  let region_set2 : Array[FoldRange] = [
    fold_range(30, 39, collapsed=true, type_="b1"), // valid, will be recovered
    fold_range(40, 49, collapsed=true, source=UserDefined, type_="b2"), // valid
    fold_range(50, 100, collapsed=true, source=UserDefined, type_="b3"), // overlaps a4
    fold_range(80, 90, collapsed=true, source=UserDefined, type_="b4"), // overlaps a6
    fold_range(92, 100, collapsed=true, source=UserDefined, type_="b5"), // valid
  ]
  let result = FoldingRegions::sanitize_and_merge(
    Ranges(region_set1),
    Ranges(region_set2),
    Some(100),
  )
  assert_eq(result.length(), 9)
  assert_equal_ranges(result[0], fold_range(1, 100, type_="a1"), "P1")
  assert_equal_ranges(result[1], fold_range(2, 100, type_="a2"), "P2")
  assert_equal_ranges(result[2], fold_range(3, 19, type_="a3"), "P3")
  assert_equal_ranges(result[3], fold_range(21, 29, type_="a5"), "P4")
  assert_equal_ranges(
    result[4],
    fold_range(30, 39, collapsed=true, source=Recovered, type_="b1"),
    "P5",
  )
  assert_equal_ranges(
    result[5],
    fold_range(40, 49, collapsed=true, source=UserDefined, type_="b2"),
    "P6",
  )
  assert_equal_ranges(
    result[6],
    fold_range(50, 100, collapsed=true, source=UserDefined, type_="b3"),
    "P7",
  )
  assert_equal_ranges(
    result[7],
    fold_range(80, 90, collapsed=true, source=UserDefined, type_="b4"),
    "P8",
  )
  assert_equal_ranges(
    result[8],
    fold_range(92, 100, collapsed=true, source=UserDefined, type_="b5"),
    "P9",
  )
}

///|
test "sanitizeAndMerge3" {
  let region_set1 : Array[FoldRange] = [
    fold_range(1, 100, type_="a1"), // valid
    fold_range(10, 29, type_="a2"), // matches manual hidden
    fold_range(35, 39, collapsed=true, source=Recovered, type_="a3"), // valid
  ]
  let region_set2 : Array[FoldRange] = [
    fold_range(10, 29, collapsed=true, source=Recovered, type_="b1"), // matches a
    fold_range(20, 28, collapsed=true, type_="b2"), // should remain
    fold_range(30, 39, collapsed=true, source=Recovered, type_="b3"), // should remain
  ]
  let result = FoldingRegions::sanitize_and_merge(
    Ranges(region_set1),
    Ranges(region_set2),
    Some(100),
  )
  assert_eq(result.length(), 5)
  assert_equal_ranges(result[0], fold_range(1, 100, type_="a1"), "R1")
  assert_equal_ranges(
    result[1],
    fold_range(10, 29, collapsed=true, type_="a2"),
    "R2",
  )
  assert_equal_ranges(
    result[2],
    fold_range(20, 28, collapsed=true, source=Recovered, type_="b2"),
    "R3",
  )
  assert_equal_ranges(
    result[3],
    fold_range(30, 39, collapsed=true, source=Recovered, type_="b3"),
    "R3",
  )
  assert_equal_ranges(
    result[4],
    fold_range(35, 39, collapsed=true, source=Recovered, type_="a3"),
    "R4",
  )
}

///|
test "sanitizeAndMerge4" {
  let region_set1 : Array[FoldRange] = [
    fold_range(1, 100, type_="a1"), // valid
  ]
  let region_set2 : Array[FoldRange] = [
    fold_range(20, 28, collapsed=true, type_="b1"), // hidden
    fold_range(30, 38, collapsed=true, type_="b2"), // hidden
  ]
  let result = FoldingRegions::sanitize_and_merge(
    Ranges(region_set1),
    Ranges(region_set2),
    Some(100),
  )
  assert_eq(result.length(), 3)
  assert_equal_ranges(result[0], fold_range(1, 100, type_="a1"), "R1")
  assert_equal_ranges(
    result[1],
    fold_range(20, 28, collapsed=true, source=Recovered, type_="b1"),
    "R2",
  )
  assert_equal_ranges(
    result[2],
    fold_range(30, 38, collapsed=true, source=Recovered, type_="b2"),
    "R3",
  )
}

///|
test "fromFoldRanges round-trips ranges, state, and the debug string" {
  let ranges : Array[FoldRange] = [
    fold_range(1, 10, collapsed=true, type_="comment"),
    fold_range(3, 6, source=UserDefined),
    fold_range(12, 20, collapsed=true, source=Recovered),
  ]
  let regions = FoldingRegions::from_fold_ranges(ranges)
  assert_eq(regions.length(), 3)
  assert_true(regions.has_types())
  for i in 0..<3 {
    assert_equal_ranges(regions.to_fold_range(i), ranges[i], "round-trip \{i}")
  }
  // `toString` format: `[<source><+|->] <start>/<end>`.
  assert_eq(regions.to_string(), "[ +] 1/10, [u-] 3/6, [r+] 12/20")
  // Parent linking: region 1 nests inside region 0; 2 is a root.
  assert_eq(regions.get_parent_index(0), -1)
  assert_eq(regions.get_parent_index(1), 0)
  assert_eq(regions.get_parent_index(2), -1)
  // Region accessor.
  let region = regions.to_region(1)
  assert_eq(region.start_line_number(), 3)
  assert_eq(region.end_line_number(), 6)
  assert_eq(region.parent_index(), 0)
  assert_false(region.is_collapsed())
  assert_true(
    region.contained_by({ start_line_number: 1, end_line_number: 10 }),
  )
  assert_true(region.contains_line(3))
  assert_false(region.hides_line(3))
  assert_true(region.hides_line(4))
}

///|
test "fromFoldRanges without types reports has_types false" {
  let regions = FoldingRegions::from_fold_ranges([
    fold_range(1, 4),
    fold_range(6, 9),
  ])
  assert_false(regions.has_types())
  assert_true(regions.get_type(0) is None)
  assert_eq(regions.find_range(2), 0)
  assert_eq(regions.find_range(5), -1)
  assert_eq(regions.find_range(9), 1)
  assert_eq(regions.find_range(10), -1)
}
