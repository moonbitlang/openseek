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
  from : Int32,
  to : Int32,
  collapsed~ : Bool = false,
  source~ : FoldSource = Provider,
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
