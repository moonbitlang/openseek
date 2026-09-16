// Conformance port of Monaco/VS Code's PrefixSumComputer suite.
//
// Ports: vscode/src/vs/editor/test/common/viewModel/prefixSumComputer.test.ts
// From the checked-in vscode submodule.
//
// Like the upstream `forBoth`, every case runs against both PrefixSumComputer
// and ConstantTimePrefixSumComputer through a shared adapter.

///|
enum AnyPsc {
  Linear(@view_layout.PrefixSumComputer)
  Constant(@view_layout.ConstantTimePrefixSumComputer)
}

///|
fn AnyPsc::get_total_sum(self : AnyPsc) -> Int {
  match self {
    Linear(p) => p.get_total_sum()
    Constant(c) => c.get_total_sum()
  }
}

///|
/// Sum of the first `count` items, matching the upstream wrapped interface.
fn AnyPsc::get_prefix_sum(self : AnyPsc, count : Int) -> Int {
  match self {
    Linear(p) => if count == 0 { 0 } else { p.get_prefix_sum(count - 1) }
    Constant(c) => c.get_prefix_sum(count)
  }
}

///|
fn AnyPsc::get_index_of(
  self : AnyPsc,
  sum : Int,
) -> @view_layout.PrefixSumIndexOfResult {
  match self {
    Linear(p) => p.get_index_of(sum)
    Constant(c) => c.get_index_of(sum)
  }
}

///|
fn AnyPsc::set_value(self : AnyPsc, index : Int, value : Int) -> Unit {
  match self {
    Linear(p) => p.set_value(index, value) |> ignore
    Constant(c) => c.set_value(index, value)
  }
}

///|
fn AnyPsc::insert_values(
  self : AnyPsc,
  insert_index : Int,
  insert_arr : Array[Int],
) -> Unit {
  match self {
    Linear(p) => p.insert_values(insert_index, insert_arr) |> ignore
    Constant(c) => c.insert_values(insert_index, insert_arr)
  }
}

///|
fn AnyPsc::remove_values(
  self : AnyPsc,
  start : Int,
  delete_count : Int,
) -> Unit {
  match self {
    Linear(p) => p.remove_values(start, delete_count) |> ignore
    Constant(c) => c.remove_values(start, delete_count)
  }
}

///|
fn for_both(values : Array[Int], cb : (AnyPsc) -> Unit raise) -> Unit raise {
  cb(Linear(PrefixSumComputer(values)))
  cb(Constant(ConstantTimePrefixSumComputer(values)))
}

///|
fn res(index : Int, remainder : Int) -> @view_layout.PrefixSumIndexOfResult {
  { index, remainder, }
}

///|
fn assert_res(
  actual : @view_layout.PrefixSumIndexOfResult,
  expected : @view_layout.PrefixSumIndexOfResult,
) -> Unit raise {
  if actual != expected {
    fail(
      "getIndexOf mismatch: got (\{actual.index}, \{actual.remainder}), expected (\{expected.index}, \{expected.remainder})",
    )
  }
}

///|
test "comprehensive setValue and getIndexOf" {
  for_both([1, 1, 2, 1, 3], psc => {
    assert_eq(psc.get_total_sum(), 8)
    assert_eq(psc.get_prefix_sum(0), 0)
    assert_eq(psc.get_prefix_sum(1), 1)
    assert_eq(psc.get_prefix_sum(2), 2)
    assert_eq(psc.get_prefix_sum(3), 4)
    assert_eq(psc.get_prefix_sum(4), 5)
    assert_eq(psc.get_prefix_sum(5), 8)
    assert_res(psc.get_index_of(0), res(0, 0))
    assert_res(psc.get_index_of(1), res(1, 0))
    assert_res(psc.get_index_of(2), res(2, 0))
    assert_res(psc.get_index_of(3), res(2, 1))
    assert_res(psc.get_index_of(4), res(3, 0))
    assert_res(psc.get_index_of(5), res(4, 0))
    assert_res(psc.get_index_of(6), res(4, 1))
    assert_res(psc.get_index_of(7), res(4, 2))
    assert_res(psc.get_index_of(8), res(4, 3))

    // [1, 2, 2, 1, 3]
    psc.set_value(1, 2)
    assert_eq(psc.get_total_sum(), 9)
    assert_eq(psc.get_prefix_sum(1), 1)
    assert_eq(psc.get_prefix_sum(2), 3)
    assert_eq(psc.get_prefix_sum(3), 5)
    assert_eq(psc.get_prefix_sum(4), 6)
    assert_eq(psc.get_prefix_sum(5), 9)

    // [1, 0, 2, 1, 3]
    psc.set_value(1, 0)
    assert_eq(psc.get_total_sum(), 7)
    assert_eq(psc.get_prefix_sum(1), 1)
    assert_eq(psc.get_prefix_sum(2), 1)
    assert_eq(psc.get_prefix_sum(3), 3)
    assert_eq(psc.get_prefix_sum(4), 4)
    assert_eq(psc.get_prefix_sum(5), 7)
    assert_res(psc.get_index_of(0), res(0, 0))
    assert_res(psc.get_index_of(1), res(2, 0))
    assert_res(psc.get_index_of(2), res(2, 1))
    assert_res(psc.get_index_of(3), res(3, 0))
    assert_res(psc.get_index_of(4), res(4, 0))
    assert_res(psc.get_index_of(5), res(4, 1))
    assert_res(psc.get_index_of(6), res(4, 2))

    // [1, 0, 0, 1, 3]
    psc.set_value(2, 0)
    assert_eq(psc.get_total_sum(), 5)
    assert_eq(psc.get_prefix_sum(1), 1)
    assert_eq(psc.get_prefix_sum(2), 1)
    assert_eq(psc.get_prefix_sum(3), 1)
    assert_eq(psc.get_prefix_sum(4), 2)
    assert_eq(psc.get_prefix_sum(5), 5)
    assert_res(psc.get_index_of(0), res(0, 0))
    assert_res(psc.get_index_of(1), res(3, 0))
    assert_res(psc.get_index_of(2), res(4, 0))
    assert_res(psc.get_index_of(3), res(4, 1))
    assert_res(psc.get_index_of(4), res(4, 2))

    // [1, 0, 0, 0, 3]
    psc.set_value(3, 0)
    assert_eq(psc.get_total_sum(), 4)
    assert_eq(psc.get_prefix_sum(1), 1)
    assert_eq(psc.get_prefix_sum(2), 1)
    assert_eq(psc.get_prefix_sum(3), 1)
    assert_eq(psc.get_prefix_sum(4), 1)
    assert_eq(psc.get_prefix_sum(5), 4)
    assert_res(psc.get_index_of(0), res(0, 0))
    assert_res(psc.get_index_of(1), res(4, 0))
    assert_res(psc.get_index_of(2), res(4, 1))
    assert_res(psc.get_index_of(3), res(4, 2))

    // [1, 1, 0, 1, 1]
    psc.set_value(1, 1)
    psc.set_value(3, 1)
    psc.set_value(4, 1)
    assert_eq(psc.get_total_sum(), 4)
    assert_eq(psc.get_prefix_sum(1), 1)
    assert_eq(psc.get_prefix_sum(2), 2)
    assert_eq(psc.get_prefix_sum(3), 2)
    assert_eq(psc.get_prefix_sum(4), 3)
    assert_eq(psc.get_prefix_sum(5), 4)
    assert_res(psc.get_index_of(0), res(0, 0))
    assert_res(psc.get_index_of(1), res(1, 0))
    assert_res(psc.get_index_of(2), res(3, 0))
    assert_res(psc.get_index_of(3), res(4, 0))
  })
}

///|
test "getTotalSum with typical values" {
  for_both([1, 1, 2, 1, 3], psc => assert_eq(psc.get_total_sum(), 8))
  for_both([10], psc => assert_eq(psc.get_total_sum(), 10))
  for_both([5, 5, 5], psc => assert_eq(psc.get_total_sum(), 15))
}

///|
test "getTotalSum with all zeroes" {
  for_both([0, 0, 0], psc => assert_eq(psc.get_total_sum(), 0))
  for_both([0], psc => assert_eq(psc.get_total_sum(), 0))
}

///|
test "getTotalSum with empty array" {
  for_both([], psc => assert_eq(psc.get_total_sum(), 0))
}

///|
test "getTotalSum with single element" {
  for_both([0], psc => assert_eq(psc.get_total_sum(), 0))
  for_both([1], psc => assert_eq(psc.get_total_sum(), 1))
  for_both([100], psc => assert_eq(psc.get_total_sum(), 100))
}

///|
test "getPrefixSum with typical values" {
  for_both([1, 1, 2, 1, 3], psc => {
    assert_eq(psc.get_prefix_sum(0), 0)
    assert_eq(psc.get_prefix_sum(1), 1)
    assert_eq(psc.get_prefix_sum(2), 2)
    assert_eq(psc.get_prefix_sum(3), 4)
    assert_eq(psc.get_prefix_sum(4), 5)
    assert_eq(psc.get_prefix_sum(5), 8)
  })
}

///|
test "getPrefixSum with all zeroes" {
  for_both([0, 0, 0], psc => {
    assert_eq(psc.get_prefix_sum(0), 0)
    assert_eq(psc.get_prefix_sum(1), 0)
    assert_eq(psc.get_prefix_sum(2), 0)
    assert_eq(psc.get_prefix_sum(3), 0)
  })
}

///|
test "getPrefixSum with single element" {
  for_both([7], psc => {
    assert_eq(psc.get_prefix_sum(0), 0)
    assert_eq(psc.get_prefix_sum(1), 7)
  })
}

///|
test "getPrefixSum with empty array" {
  for_both([], psc => assert_eq(psc.get_prefix_sum(0), 0))
}

///|
test "getPrefixSum with leading/trailing zeroes" {
  for_both([0, 0, 3, 0, 0], psc => {
    assert_eq(psc.get_prefix_sum(0), 0)
    assert_eq(psc.get_prefix_sum(1), 0)
    assert_eq(psc.get_prefix_sum(2), 0)
    assert_eq(psc.get_prefix_sum(3), 3)
    assert_eq(psc.get_prefix_sum(4), 3)
    assert_eq(psc.get_prefix_sum(5), 3)
  })
}

///|
test "getIndexOf with typical values" {
  for_both([1, 1, 2, 1, 3], psc => {
    assert_res(psc.get_index_of(0), res(0, 0))
    assert_res(psc.get_index_of(1), res(1, 0))
    assert_res(psc.get_index_of(2), res(2, 0))
    assert_res(psc.get_index_of(3), res(2, 1))
    assert_res(psc.get_index_of(4), res(3, 0))
    assert_res(psc.get_index_of(5), res(4, 0))
    assert_res(psc.get_index_of(6), res(4, 1))
    assert_res(psc.get_index_of(7), res(4, 2))
    assert_res(psc.get_index_of(8), res(4, 3))
  })
}

///|
test "getIndexOf with all zeroes" {
  for_both([0, 0, 0], psc => assert_res(psc.get_index_of(0), res(2, 0)))
}

///|
test "getIndexOf with single zero" {
  for_both([0], psc => assert_res(psc.get_index_of(0), res(0, 0)))
}

///|
test "getIndexOf with single element" {
  for_both([5], psc => {
    assert_res(psc.get_index_of(0), res(0, 0))
    assert_res(psc.get_index_of(1), res(0, 1))
    assert_res(psc.get_index_of(4), res(0, 4))
  })
}

///|
test "getIndexOf with leading zeroes" {
  for_both([0, 0, 3], psc => {
    assert_res(psc.get_index_of(0), res(2, 0))
    assert_res(psc.get_index_of(1), res(2, 1))
    assert_res(psc.get_index_of(2), res(2, 2))
  })
}

///|
test "getIndexOf with trailing zeroes" {
  for_both([3, 0, 0], psc => {
    assert_res(psc.get_index_of(0), res(0, 0))
    assert_res(psc.get_index_of(1), res(0, 1))
    assert_res(psc.get_index_of(2), res(0, 2))
  })
}

///|
test "getIndexOf with interleaved zeroes" {
  for_both([0, 1, 0, 2, 0], psc => {
    assert_res(psc.get_index_of(0), res(1, 0))
    assert_res(psc.get_index_of(1), res(3, 0))
    assert_res(psc.get_index_of(2), res(3, 1))
  })
}

///|
test "getIndexOf with all ones" {
  for_both([1, 1, 1, 1, 1], psc => {
    for i in 0..<5 {
      assert_res(psc.get_index_of(i), res(i, 0))
    }
  })
}

///|
test "getIndexOf with large value in single element" {
  for_both([1000], psc => {
    assert_res(psc.get_index_of(0), res(0, 0))
    assert_res(psc.get_index_of(500), res(0, 500))
    assert_res(psc.get_index_of(999), res(0, 999))
  })
}

///|
test "setValue no-op when value unchanged" {
  for_both([1, 2, 3], psc => {
    assert_eq(psc.get_total_sum(), 6)
    psc.set_value(1, 2)
    assert_eq(psc.get_total_sum(), 6)
  })
}

///|
test "setValue increase" {
  for_both([1, 2, 3], psc => {
    psc.set_value(1, 5)
    assert_eq(psc.get_total_sum(), 9)
    assert_eq(psc.get_prefix_sum(2), 6)
    assert_eq(psc.get_prefix_sum(3), 9)
    assert_res(psc.get_index_of(0), res(0, 0))
    assert_res(psc.get_index_of(1), res(1, 0))
    assert_res(psc.get_index_of(5), res(1, 4))
    assert_res(psc.get_index_of(6), res(2, 0))
  })
}

///|
test "setValue decrease" {
  for_both([1, 5, 3], psc => {
    psc.set_value(1, 2)
    assert_eq(psc.get_total_sum(), 6)
    assert_res(psc.get_index_of(1), res(1, 0))
    assert_res(psc.get_index_of(2), res(1, 1))
    assert_res(psc.get_index_of(3), res(2, 0))
  })
}

///|
test "setValue to zero" {
  for_both([1, 2, 3], psc => {
    psc.set_value(1, 0)
    assert_eq(psc.get_total_sum(), 4)
    assert_eq(psc.get_prefix_sum(2), 1)
    assert_res(psc.get_index_of(0), res(0, 0))
    assert_res(psc.get_index_of(1), res(2, 0))
  })
}

///|
test "setValue from zero" {
  for_both([0, 0, 0], psc => {
    psc.set_value(1, 3)
    assert_eq(psc.get_total_sum(), 3)
    assert_res(psc.get_index_of(0), res(1, 0))
    assert_res(psc.get_index_of(2), res(1, 2))
  })
}

///|
test "setValue on first element" {
  for_both([1, 2, 3], psc => {
    psc.set_value(0, 10)
    assert_eq(psc.get_total_sum(), 15)
    assert_eq(psc.get_prefix_sum(1), 10)
    assert_res(psc.get_index_of(0), res(0, 0))
    assert_res(psc.get_index_of(9), res(0, 9))
    assert_res(psc.get_index_of(10), res(1, 0))
  })
}

///|
test "setValue on last element" {
  for_both([1, 2, 3], psc => {
    psc.set_value(2, 10)
    assert_eq(psc.get_total_sum(), 13)
    assert_res(psc.get_index_of(3), res(2, 0))
    assert_res(psc.get_index_of(12), res(2, 9))
  })
}

///|
test "set all values to zero then restore" {
  for_both([1, 2, 3], psc => {
    psc.set_value(0, 0)
    psc.set_value(1, 0)
    psc.set_value(2, 0)
    assert_eq(psc.get_total_sum(), 0)
    assert_res(psc.get_index_of(0), res(2, 0))
    psc.set_value(0, 4)
    assert_eq(psc.get_total_sum(), 4)
    assert_res(psc.get_index_of(0), res(0, 0))
    assert_res(psc.get_index_of(3), res(0, 3))
  })
}

///|
test "setValue multiple times on same index" {
  for_both([1, 1, 1], psc => {
    psc.set_value(1, 5)
    psc.set_value(1, 2)
    psc.set_value(1, 10)
    assert_eq(psc.get_total_sum(), 12)
    assert_res(psc.get_index_of(0), res(0, 0))
    assert_res(psc.get_index_of(1), res(1, 0))
    assert_res(psc.get_index_of(10), res(1, 9))
    assert_res(psc.get_index_of(11), res(2, 0))
  })
}

///|
test "insertValues at beginning" {
  for_both([3, 4], psc => {
    psc.insert_values(0, [1, 2])
    assert_eq(psc.get_total_sum(), 10)
    assert_eq(psc.get_prefix_sum(1), 1)
    assert_eq(psc.get_prefix_sum(2), 3)
    assert_eq(psc.get_prefix_sum(3), 6)
    assert_eq(psc.get_prefix_sum(4), 10)
    assert_res(psc.get_index_of(0), res(0, 0))
    assert_res(psc.get_index_of(1), res(1, 0))
    assert_res(psc.get_index_of(3), res(2, 0))
  })
}

///|
test "insertValues at end" {
  for_both([1, 2], psc => {
    psc.insert_values(2, [3, 4])
    assert_eq(psc.get_total_sum(), 10)
    assert_eq(psc.get_prefix_sum(3), 6)
    assert_eq(psc.get_prefix_sum(4), 10)
  })
}

///|
test "insertValues in the middle" {
  for_both([1, 4], psc => {
    psc.insert_values(1, [2, 3])
    assert_eq(psc.get_total_sum(), 10)
    assert_eq(psc.get_prefix_sum(1), 1)
    assert_eq(psc.get_prefix_sum(2), 3)
    assert_eq(psc.get_prefix_sum(3), 6)
    assert_eq(psc.get_prefix_sum(4), 10)
  })
}

///|
test "insertValues with zeroes" {
  for_both([1, 2], psc => {
    psc.insert_values(1, [0, 0])
    assert_eq(psc.get_total_sum(), 3)
    assert_eq(psc.get_prefix_sum(1), 1)
    assert_eq(psc.get_prefix_sum(2), 1)
    assert_eq(psc.get_prefix_sum(3), 1)
    assert_eq(psc.get_prefix_sum(4), 3)
  })
}

///|
test "insertValues into all-zeroes" {
  for_both([0, 0, 0], psc => {
    psc.insert_values(1, [2, 3])
    assert_eq(psc.get_total_sum(), 5)
    assert_eq(psc.get_prefix_sum(1), 0)
    assert_eq(psc.get_prefix_sum(2), 2)
    assert_eq(psc.get_prefix_sum(3), 5)
    assert_res(psc.get_index_of(0), res(1, 0))
    assert_res(psc.get_index_of(2), res(2, 0))
    assert_res(psc.get_index_of(4), res(2, 2))
  })
}

///|
test "insertValues into empty computer" {
  for_both([], psc => {
    psc.insert_values(0, [5, 3])
    assert_eq(psc.get_total_sum(), 8)
    assert_res(psc.get_index_of(0), res(0, 0))
    assert_res(psc.get_index_of(4), res(0, 4))
    assert_res(psc.get_index_of(5), res(1, 0))
  })
}

///|
test "removeValues from beginning" {
  for_both([1, 2, 3, 4], psc => {
    psc.remove_values(0, 2)
    assert_eq(psc.get_total_sum(), 7)
    assert_eq(psc.get_prefix_sum(1), 3)
    assert_eq(psc.get_prefix_sum(2), 7)
    assert_res(psc.get_index_of(0), res(0, 0))
    assert_res(psc.get_index_of(3), res(1, 0))
  })
}

///|
test "removeValues from end" {
  for_both([1, 2, 3, 4], psc => {
    psc.remove_values(2, 2)
    assert_eq(psc.get_total_sum(), 3)
    assert_eq(psc.get_prefix_sum(1), 1)
    assert_eq(psc.get_prefix_sum(2), 3)
  })
}

///|
test "removeValues from the middle" {
  for_both([1, 2, 3, 4], psc => {
    psc.remove_values(1, 2)
    assert_eq(psc.get_total_sum(), 5)
    assert_eq(psc.get_prefix_sum(1), 1)
    assert_eq(psc.get_prefix_sum(2), 5)
    assert_res(psc.get_index_of(0), res(0, 0))
    assert_res(psc.get_index_of(1), res(1, 0))
    assert_res(psc.get_index_of(4), res(1, 3))
  })
}

///|
test "removeValues all" {
  for_both([1, 2, 3], psc => {
    psc.remove_values(0, 3)
    assert_eq(psc.get_total_sum(), 0)
  })
}

///|
test "removeValues single element" {
  for_both([5, 10, 15], psc => {
    psc.remove_values(1, 1)
    assert_eq(psc.get_total_sum(), 20)
    assert_res(psc.get_index_of(0), res(0, 0))
    assert_res(psc.get_index_of(5), res(1, 0))
    assert_res(psc.get_index_of(19), res(1, 14))
  })
}

///|
test "removeValues zero-valued elements" {
  for_both([0, 0, 5, 0, 0], psc => {
    psc.remove_values(0, 2)
    assert_eq(psc.get_total_sum(), 5)
    assert_res(psc.get_index_of(0), res(0, 0))
    assert_res(psc.get_index_of(4), res(0, 4))
  })
}

///|
test "insert then remove" {
  for_both([1, 2, 3], psc => {
    psc.insert_values(1, [10, 20])
    assert_eq(psc.get_total_sum(), 36)
    psc.remove_values(1, 2)
    assert_eq(psc.get_total_sum(), 6)
    assert_res(psc.get_index_of(0), res(0, 0))
    assert_res(psc.get_index_of(1), res(1, 0))
    assert_res(psc.get_index_of(3), res(2, 0))
  })
}

///|
test "remove then insert at same position" {
  for_both([1, 2, 3], psc => {
    psc.remove_values(1, 1)
    psc.insert_values(1, [5])
    assert_eq(psc.get_total_sum(), 9)
    assert_res(psc.get_index_of(1), res(1, 0))
    assert_res(psc.get_index_of(5), res(1, 4))
    assert_res(psc.get_index_of(6), res(2, 0))
  })
}

///|
test "setValue then insert then remove" {
  for_both([1, 1, 1], psc => {
    psc.set_value(0, 5)
    psc.insert_values(1, [10])
    psc.remove_values(3, 1)
    // [5, 10, 1]
    assert_eq(psc.get_total_sum(), 16)
    assert_res(psc.get_index_of(0), res(0, 0))
    assert_res(psc.get_index_of(4), res(0, 4))
    assert_res(psc.get_index_of(5), res(1, 0))
    assert_res(psc.get_index_of(14), res(1, 9))
    assert_res(psc.get_index_of(15), res(2, 0))
  })
}

///|
test "multiple queries between mutations are consistent" {
  for_both([2, 3, 5], psc => {
    assert_eq(psc.get_total_sum(), 10)
    assert_res(psc.get_index_of(0), res(0, 0))
    psc.set_value(1, 0)
    assert_eq(psc.get_total_sum(), 7)
    assert_res(psc.get_index_of(2), res(2, 0))
    psc.set_value(1, 3)
    assert_eq(psc.get_total_sum(), 10)
    assert_res(psc.get_index_of(2), res(1, 0))
  })
}

///|
test "large values" {
  for_both([100, 200, 300], psc => {
    assert_eq(psc.get_total_sum(), 600)
    assert_eq(psc.get_prefix_sum(1), 100)
    assert_eq(psc.get_prefix_sum(2), 300)
    assert_eq(psc.get_prefix_sum(3), 600)
    assert_res(psc.get_index_of(0), res(0, 0))
    assert_res(psc.get_index_of(99), res(0, 99))
    assert_res(psc.get_index_of(100), res(1, 0))
    assert_res(psc.get_index_of(299), res(1, 199))
    assert_res(psc.get_index_of(300), res(2, 0))
    assert_res(psc.get_index_of(599), res(2, 299))
  })
}

///|
test "many elements" {
  for_both(Array::make(100, 1), psc => {
    assert_eq(psc.get_total_sum(), 100)
    assert_eq(psc.get_prefix_sum(50), 50)
    for i in 0..<100 {
      assert_res(psc.get_index_of(i), res(i, 0))
    }
  })
}

///|
test "many elements all zeroes" {
  for_both(Array::make(100, 0), psc => {
    assert_eq(psc.get_total_sum(), 0)
    for i in 0..<=100 {
      assert_eq(psc.get_prefix_sum(i), 0)
    }
    assert_res(psc.get_index_of(0), res(99, 0))
  })
}

///|
test "setValue between queries re-validates correctly" {
  for_both([1, 1, 1, 1, 1], psc => {
    assert_eq(psc.get_total_sum(), 5)
    psc.set_value(2, 10)
    assert_eq(psc.get_total_sum(), 14)
    assert_eq(psc.get_prefix_sum(3), 12)
    assert_res(psc.get_index_of(2), res(2, 0))
    assert_res(psc.get_index_of(11), res(2, 9))
    assert_res(psc.get_index_of(12), res(3, 0))
    assert_res(psc.get_index_of(13), res(4, 0))
    psc.set_value(0, 0)
    assert_eq(psc.get_total_sum(), 13)
    assert_res(psc.get_index_of(0), res(1, 0))
  })
}
