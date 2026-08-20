// Reachable subset of Monaco/VS Code's LineRange / LineRangeSet.
//
// Source: vscode/src/vs/editor/common/core/ranges/lineRange.ts
//   with the monotonic binary-search helpers from
//   vscode/src/vs/base/common/arraysFind.ts
// (checked-in vscode submodule).
//
// Unused comparison/set helpers are deferred until a product caller needs
// them. Adaptation: upstream's constructor throws on `startLineNumber >
// endLineNumberExclusive`; this port stores the values without validating
// (callers pass valid ranges).

///|
/// A range of lines (1-based), `[start_line_number, end_line_number_exclusive)`.
pub(all) struct LineRange {
  start_line_number : Int
  end_line_number_exclusive : Int
} derive(Eq, Debug)

///|
pub fn LineRange::LineRange(
  start_line_number : Int,
  end_line_number_exclusive : Int,
) -> LineRange {
  { start_line_number, end_line_number_exclusive }
}

///|
/// Indicates if this line range is empty.
pub fn LineRange::is_empty(self : LineRange) -> Bool {
  self.start_line_number == self.end_line_number_exclusive
}

///|
/// The number of lines this line range spans.
pub fn LineRange::length(self : LineRange) -> Int {
  self.end_line_number_exclusive - self.start_line_number
}

///|
/// Combines this and the given line range into the smallest covering range.
pub fn LineRange::join(self : LineRange, other : LineRange) -> LineRange {
  LineRange(
    self.start_line_number.min(other.start_line_number),
    self.end_line_number_exclusive.max(other.end_line_number_exclusive),
  )
}

///|
pub fn LineRange::to_string(self : LineRange) -> String {
  "[\{self.start_line_number},\{self.end_line_number_exclusive})"
}

///|
pub fn LineRange::equals(self : LineRange, other : LineRange) -> Bool {
  self == other
}

///|
/// A normalized set of line ranges (sorted by start, none touching/overlapping).
struct LineRangeSet {
  normalized_ranges : Array[LineRange]
}

///|
pub fn LineRangeSet::LineRangeSet(
  normalized_ranges? : Array[LineRange] = [],
) -> LineRangeSet {
  { normalized_ranges, }
}

///|
pub fn LineRangeSet::ranges(self : LineRangeSet) -> Array[LineRange] {
  self.normalized_ranges
}

///|
pub fn LineRangeSet::add_range(self : LineRangeSet, range : LineRange) -> Unit {
  if range.length() == 0 {
    return
  }
  let ranges = self.normalized_ranges
  let join_range_start_idx = find_first_idx_monotonous_or_arr_len(ranges[:], r => {
    r.end_line_number_exclusive >= range.start_line_number
  })
  let join_range_end_idx_exclusive = find_last_idx_monotonous(ranges[:], r => {
      r.start_line_number <= range.end_line_number_exclusive
    }) +
    1
  if join_range_start_idx == join_range_end_idx_exclusive {
    ranges.insert(join_range_start_idx, range)
  } else if join_range_start_idx == join_range_end_idx_exclusive - 1 {
    let join_range = ranges[join_range_start_idx]
    ranges[join_range_start_idx] = join_range.join(range)
  } else {
    let join_range = ranges[join_range_start_idx]
      .join(ranges[join_range_end_idx_exclusive - 1])
      .join(range)
    array_splice_replace(
      ranges,
      join_range_start_idx,
      join_range_end_idx_exclusive - join_range_start_idx,
      join_range,
    )
  }
}

///|
fn LineRangeSet::get_union(
  self : LineRangeSet,
  other : LineRangeSet,
) -> LineRangeSet {
  if self.normalized_ranges.length() == 0 {
    return other
  }
  if other.normalized_ranges.length() == 0 {
    return self
  }
  let result : Array[LineRange] = []
  let current = for i1 = 0, i2 = 0, current = (None : LineRange?); i1 <
                   self.normalized_ranges.length() ||
                   i2 < other.normalized_ranges.length(); {
    let (next, next_i1, next_i2) = if i1 < self.normalized_ranges.length() &&
      i2 < other.normalized_ranges.length() {
      let line_range1 = self.normalized_ranges[i1]
      let line_range2 = other.normalized_ranges[i2]
      if line_range1.start_line_number < line_range2.start_line_number {
        (line_range1, i1 + 1, i2)
      } else {
        (line_range2, i1, i2 + 1)
      }
    } else if i1 < self.normalized_ranges.length() {
      (self.normalized_ranges[i1], i1 + 1, i2)
    } else {
      (other.normalized_ranges[i2], i1, i2 + 1)
    }
    let next_current = match current {
      None => Some(next)
      Some(cur) =>
        if cur.end_line_number_exclusive >= next.start_line_number {
          Some(
            LineRange(
              cur.start_line_number,
              cur.end_line_number_exclusive.max(next.end_line_number_exclusive),
            ),
          )
        } else {
          result.push(cur)
          Some(next)
        }
    }
    continue next_i1, next_i2, next_current
  } nobreak {
    current
  }
  if current is Some(cur) {
    result.push(cur)
  }
  LineRangeSet(normalized_ranges=result)
}

///|
fn find_first_idx_monotonous_or_arr_len(
  array : ArrayView[LineRange],
  predicate : (LineRange) -> Bool,
) -> Int {
  for i = 0, j = array.length(); i < j; {
    let k = (i + j) / 2
    if predicate(array[k]) {
      continue i, k
    } else {
      continue k + 1, j
    }
  } nobreak {
    i
  }
}

///|
fn find_last_idx_monotonous(
  array : ArrayView[LineRange],
  predicate : (LineRange) -> Bool,
) -> Int {
  let i = for i = 0, j = array.length(); i < j; {
    let k = (i + j) / 2
    if predicate(array[k]) {
      continue k + 1, j
    } else {
      continue i, k
    }
  } nobreak {
    i
  }
  i - 1
}

///|
fn array_splice_replace(
  array : Array[LineRange],
  start : Int,
  delete_count : Int,
  item : LineRange,
) -> Unit {
  let rest = [ for i in (start + delete_count)..<array.length() => array[i] ]
  while array.length() > start {
    array.pop() |> ignore
  }
  array.push(item)
  array.append(rest)
}

///|
pub extend LineRange with Debug::{to_repr}

///|
pub extend LineRange with Eq::{equal, not_equal}
