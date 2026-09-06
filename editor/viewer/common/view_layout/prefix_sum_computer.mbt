// Port of Monaco/VS Code's prefix-sum helpers used by the view model to map
// between view-line indexes and accumulated heights.
//
// Source: vscode/src/vs/editor/common/model/prefixSumComputer.ts
// (checked-in vscode submodule).

///|
/// Result of `PrefixSumComputer::get_index_of`: the index whose range contains
/// the queried sum, plus the remainder into that index.
pub(all) struct PrefixSumIndexOfResult {
  index : Int
  remainder : Int
} derive(Eq, Debug)

///|
/// Incrementally-cached prefix-sum computer over a mutable array of values.
/// `get_index_of` is O(log n); mutations invalidate only the affected suffix of
/// the cached prefix sums.
pub struct PrefixSumComputer {
  mut values : Array[Int]
  mut prefix_sum : Array[Int]
  mut prefix_sum_valid_index : Int
}

///|
pub fn PrefixSumComputer::PrefixSumComputer(values : ArrayView[Int]) -> Self {
  let owned = values.to_owned()
  {
    values: owned,
    prefix_sum: Array::make(owned.length(), 0),
    prefix_sum_valid_index: -1,
  }
}

///|
pub fn PrefixSumComputer::get_count(self : Self) -> Int {
  self.values.length()
}

///|
pub fn PrefixSumComputer::insert_values(
  self : Self,
  insert_index : Int,
  insert_values : Array[Int],
) -> Bool {
  let old_values = self.values
  let old_prefix_sum = self.prefix_sum
  let insert_values_len = insert_values.length()
  if insert_values_len == 0 {
    return false
  }
  let new_values = Array::make(old_values.length() + insert_values_len, 0)
  for i in 0..<insert_index {
    new_values[i] = old_values[i]
  }
  for i in insert_index..<old_values.length() {
    new_values[i + insert_values_len] = old_values[i]
  }
  for i in 0..<insert_values_len {
    new_values[insert_index + i] = insert_values[i]
  }
  self.values = new_values
  if insert_index - 1 < self.prefix_sum_valid_index {
    self.prefix_sum_valid_index = insert_index - 1
  }
  self.prefix_sum = Array::make(self.values.length(), 0)
  if self.prefix_sum_valid_index >= 0 {
    for i in 0..<=self.prefix_sum_valid_index {
      self.prefix_sum[i] = old_prefix_sum[i]
    }
  }
  true
}

///|
pub fn PrefixSumComputer::set_value(
  self : Self,
  index : Int,
  value : Int,
) -> Bool {
  if self.values[index] == value {
    return false
  }
  self.values[index] = value
  if index - 1 < self.prefix_sum_valid_index {
    self.prefix_sum_valid_index = index - 1
  }
  true
}

///|
pub fn PrefixSumComputer::remove_values(
  self : Self,
  start_index : Int,
  count : Int,
) -> Bool {
  let old_values = self.values
  let old_prefix_sum = self.prefix_sum
  if start_index >= old_values.length() {
    return false
  }
  let max_count = old_values.length() - start_index
  let count = count.min(max_count)
  if count == 0 {
    return false
  }
  let new_values = Array::make(old_values.length() - count, 0)
  for i in 0..<start_index {
    new_values[i] = old_values[i]
  }
  for i in (start_index + count)..<old_values.length() {
    new_values[i - count] = old_values[i]
  }
  self.values = new_values
  self.prefix_sum = Array::make(self.values.length(), 0)
  if start_index - 1 < self.prefix_sum_valid_index {
    self.prefix_sum_valid_index = start_index - 1
  }
  if self.prefix_sum_valid_index >= 0 {
    for i in 0..<=self.prefix_sum_valid_index {
      self.prefix_sum[i] = old_prefix_sum[i]
    }
  }
  true
}

///|
pub fn PrefixSumComputer::get_total_sum(self : Self) -> Int {
  if self.values.length() == 0 {
    return 0
  }
  self.compute_prefix_sum(self.values.length() - 1)
}

///|
/// Returns the sum of the first `index + 1` many items, i.e.
/// `SUM(0 <= j <= index, values[j])`. A negative `index` yields 0.
pub fn PrefixSumComputer::get_prefix_sum(self : Self, index : Int) -> Int {
  if index < 0 {
    return 0
  }
  self.compute_prefix_sum(index)
}

///|
fn PrefixSumComputer::compute_prefix_sum(self : Self, index : Int) -> Int {
  if index <= self.prefix_sum_valid_index {
    return self.prefix_sum[index]
  }
  let mut start_index = self.prefix_sum_valid_index + 1
  if start_index == 0 {
    self.prefix_sum[0] = self.values[0]
    start_index += 1
  }
  let mut index = index
  if index >= self.values.length() {
    index = self.values.length() - 1
  }
  for i in start_index..<=index {
    self.prefix_sum[i] = self.prefix_sum[i - 1] + self.values[i]
  }
  if index > self.prefix_sum_valid_index {
    self.prefix_sum_valid_index = index
  }
  self.prefix_sum[index]
}

///|
pub fn PrefixSumComputer::get_index_of(
  self : Self,
  sum : Int,
) -> PrefixSumIndexOfResult {
  // Compute all sums (to get a fully valid prefix sum).
  let _ = self.get_total_sum()
  let mut low = 0
  let mut high = self.values.length() - 1
  let mut mid = 0
  let mut mid_stop = 0
  let mut mid_start = 0
  while low <= high {
    mid = low + (high - low) / 2
    mid_stop = self.prefix_sum[mid]
    mid_start = mid_stop - self.values[mid]
    if sum < mid_start {
      high = mid - 1
    } else if sum >= mid_stop {
      low = mid + 1
    } else {
      break
    }
  }
  { index: mid, remainder: sum - mid_start, }
}

///|
/// O(1) amortized `get_index_of` variant that materializes a full index-by-sum
/// table on first query and re-builds it lazily after mutations.
pub struct ConstantTimePrefixSumComputer {
  mut values : Array[Int]
  mut is_valid : Bool
  mut valid_end_index : Int
  mut prefix_sum : Array[Int]
  mut index_by_sum : Array[Int]
}

///|
pub fn ConstantTimePrefixSumComputer::ConstantTimePrefixSumComputer(
  values : ArrayView[Int],
) -> Self {
  let owned = values.to_owned()
  {
    values: owned,
    is_valid: false,
    valid_end_index: -1,
    prefix_sum: [],
    index_by_sum: [],
  }
}

///|
pub fn ConstantTimePrefixSumComputer::get_total_sum(self : Self) -> Int {
  self.ensure_valid()
  self.index_by_sum.length()
}

///|
/// Returns the sum of the first `count` many items: `SUM(0 <= j < count, values[j])`.
pub fn ConstantTimePrefixSumComputer::get_prefix_sum(
  self : Self,
  count : Int,
) -> Int {
  self.ensure_valid()
  if count == 0 {
    return 0
  }
  self.prefix_sum[count - 1]
}

///|
pub fn ConstantTimePrefixSumComputer::get_index_of(
  self : Self,
  sum : Int,
) -> PrefixSumIndexOfResult {
  self.ensure_valid()
  // A faithful re-build always fills [0, totalSum), so an out-of-range sum is
  // the "undefined entry" case in the upstream sparse array.
  if sum < 0 || sum >= self.index_by_sum.length() {
    let last_idx = (self.values.length() - 1).max(0)
    let last_prefix_sum = if last_idx > 0 {
      self.prefix_sum[last_idx - 1]
    } else {
      0
    }
    return { index: last_idx, remainder: sum - last_prefix_sum, }
  }
  let idx = self.index_by_sum[sum]
  let view_lines_above = if idx > 0 { self.prefix_sum[idx - 1] } else { 0 }
  { index: idx, remainder: sum - view_lines_above, }
}

///|
pub fn ConstantTimePrefixSumComputer::remove_values(
  self : Self,
  start : Int,
  delete_count : Int,
) -> Unit {
  let delete_end = start + delete_count
  self.values = [ for i, v in self.values if i < start || i >= delete_end => v ]
  self.invalidate(start)
}

///|
pub fn ConstantTimePrefixSumComputer::insert_values(
  self : Self,
  insert_index : Int,
  insert_arr : Array[Int],
) -> Unit {
  self.values = [
    ..self.values[:insert_index],
    ..insert_arr,
    ..self.values[insert_index:],
  ]
  self.invalidate(insert_index)
}

///|
pub fn ConstantTimePrefixSumComputer::set_value(
  self : Self,
  index : Int,
  value : Int,
) -> Unit {
  if self.values[index] == value {
    return
  }
  self.values[index] = value
  self.invalidate(index)
}

///|
fn ConstantTimePrefixSumComputer::invalidate(self : Self, index : Int) -> Unit {
  self.is_valid = false
  if index - 1 < self.valid_end_index {
    self.valid_end_index = index - 1
  }
}

///|
fn ConstantTimePrefixSumComputer::ensure_valid(self : Self) -> Unit {
  if self.is_valid {
    return
  }
  let len = self.values.length()
  let prefix_sum = Array::make(len, 0)
  let total = self.values.fold(init=0, (sum, value) => sum + value)
  let index_by_sum = Array::make(total, 0)
  for i in 0..<len {
    let value = self.values[i]
    let sum_above = if i > 0 { prefix_sum[i - 1] } else { 0 }
    prefix_sum[i] = sum_above + value
    for j in 0..<value {
      index_by_sum[sum_above + j] = i
    }
  }
  self.prefix_sum = prefix_sum
  self.index_by_sum = index_by_sum
  self.is_valid = true
  self.valid_end_index = len - 1
}

///|
pub extend PrefixSumIndexOfResult with Debug::{to_repr}

///|
pub extend PrefixSumIndexOfResult with Eq::{equal, not_equal}
