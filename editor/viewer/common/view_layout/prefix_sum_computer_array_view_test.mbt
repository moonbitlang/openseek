///|
fn assert_view_total(values : ArrayView[Int], expected : Int) -> Unit raise {
  let linear = @view_layout.PrefixSumComputer(values)
  let constant = @view_layout.ConstantTimePrefixSumComputer(values)
  assert_eq(linear.get_total_sum(), expected)
  assert_eq(constant.get_total_sum(), expected)
}

///|
test "prefix sum constructors accept an empty view" {
  let source = [7]
  assert_view_total(source[0:0], 0)
}

///|
test "prefix sum constructors accept a complete array view" {
  let source : ReadOnlyArray[Int] = [1, 2, 3]
  assert_view_total(source, 6)
}

///|
test "prefix sum constructors respect a non-zero slice offset" {
  let source = [100, 2, 3, 4, 100]
  assert_view_total(source[1:4], 9)
}

///|
test "prefix sum constructors own a copy of their input view" {
  let source = [100, 1, 2, 3, 100]
  let linear = @view_layout.PrefixSumComputer(source[1:4])
  let constant = @view_layout.ConstantTimePrefixSumComputer(source[1:4])
  source[2] = 200
  assert_eq(linear.get_total_sum(), 6)
  assert_eq(constant.get_total_sum(), 6)
}

///|
test "array literals use canonical view constructors" {
  assert_eq(@view_layout.PrefixSumComputer([1, 2, 3]).get_total_sum(), 6)
  assert_eq(
    @view_layout.ConstantTimePrefixSumComputer([1, 2, 3]).get_total_sum(),
    6,
  )
}
