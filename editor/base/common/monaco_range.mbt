// Reachable subset of Monaco/VS Code's line/column `Range`; methods with no
// product caller are deferred.
//
// Source: vscode/src/vs/editor/common/core/range.ts
// (checked-in vscode submodule).
//
// `(startLineNumber, startColumn)` is normalized to be <= `(endLineNumber,
// endColumn)`. Endpoints are held as `Position` (1-based `line_number`/`column`,
// matching Monaco); the methods here are pure coordinate comparisons.

///|
/// A range in the editor. `(start_line_number, start_column)` is <=
/// `(end_line_number, end_column)`.
pub(all) struct Range {
  start_line_number : Int
  start_column : Int
  end_line_number : Int
  end_column : Int
} derive(Eq, Debug)

///|
pub fn Range::Range(
  start_line_number : Int,
  start_column : Int,
  end_line_number : Int,
  end_column : Int,
) -> Range {
  if start_line_number > end_line_number ||
    (start_line_number == end_line_number && start_column > end_column) {
    {
      start_line_number: end_line_number,
      start_column: end_column,
      end_line_number: start_line_number,
      end_column: start_column,
    }
  } else {
    { start_line_number, start_column, end_line_number, end_column }
  }
}

///|
/// Test if this range is empty.
pub fn Range::is_empty(self : Range) -> Bool {
  Range::is_empty_range(self)
}

///|
/// Test if `range` is empty.
fn Range::is_empty_range(range : Range) -> Bool {
  range.start_line_number == range.end_line_number &&
  range.start_column == range.end_column
}

///|
/// Test if position is in this range. If the position is at the edges, returns true.
fn Range::contains_position_impl(self : Range, position : Position) -> Bool {
  Range::contains_position_in(self, position)
}

///|
/// Test if position is in this range. If the position is at the edges, returns true.
pub fn Range::contains_position(self : Range, position : Position) -> Bool {
  self.contains_position_impl(position)
}

///|
fn Range::contains_position_in(range : Range, position : Position) -> Bool {
  if position.line_number < range.start_line_number ||
    position.line_number > range.end_line_number {
    return false
  }
  if position.line_number == range.start_line_number &&
    position.column < range.start_column {
    return false
  }
  if position.line_number == range.end_line_number &&
    position.column > range.end_column {
    return false
  }
  true
}

///|
/// Test if `other` is in this range. If equal, returns true.
fn Range::contains_range_impl(self : Range, other : Range) -> Bool {
  Range::contains_range_in(self, other)
}

///|
fn Range::contains_range_in(range : Range, other_range : Range) -> Bool {
  if other_range.start_line_number < range.start_line_number ||
    other_range.end_line_number < range.start_line_number {
    return false
  }
  if other_range.start_line_number > range.end_line_number ||
    other_range.end_line_number > range.end_line_number {
    return false
  }
  if other_range.start_line_number == range.start_line_number &&
    other_range.start_column < range.start_column {
    return false
  }
  if other_range.end_line_number == range.end_line_number &&
    other_range.end_column > range.end_column {
    return false
  }
  true
}

///|
/// Test if `other` is strictly in this range (must start after and end before).
fn Range::strict_contains_range_impl(self : Range, other : Range) -> Bool {
  Range::strict_contains_range_in(self, other)
}

///|
fn Range::strict_contains_range_in(range : Range, other_range : Range) -> Bool {
  if other_range.start_line_number < range.start_line_number ||
    other_range.end_line_number < range.start_line_number {
    return false
  }
  if other_range.start_line_number > range.end_line_number ||
    other_range.end_line_number > range.end_line_number {
    return false
  }
  if other_range.start_line_number == range.start_line_number &&
    other_range.start_column <= range.start_column {
    return false
  }
  if other_range.end_line_number == range.end_line_number &&
    other_range.end_column >= range.end_column {
    return false
  }
  true
}

///|
/// A reunion of the two ranges (smallest start, largest end).
fn Range::plus_range_impl(self : Range, other : Range) -> Range {
  Range::plus_range_of(self, other)
}

///|
/// A reunion of the two ranges (smallest start, largest end).
pub fn Range::plus_range(self : Range, other : Range) -> Range {
  self.plus_range_impl(other)
}

///|
fn Range::plus_range_of(a : Range, b : Range) -> Range {
  let mut start_line_number = 0
  let mut start_column = 0
  let mut end_line_number = 0
  let mut end_column = 0
  if b.start_line_number < a.start_line_number {
    start_line_number = b.start_line_number
    start_column = b.start_column
  } else if b.start_line_number == a.start_line_number {
    start_line_number = b.start_line_number
    start_column = b.start_column.min(a.start_column)
  } else {
    start_line_number = a.start_line_number
    start_column = a.start_column
  }
  if b.end_line_number > a.end_line_number {
    end_line_number = b.end_line_number
    end_column = b.end_column
  } else if b.end_line_number == a.end_line_number {
    end_line_number = b.end_line_number
    end_column = b.end_column.max(a.end_column)
  } else {
    end_line_number = a.end_line_number
    end_column = a.end_column
  }
  Range(start_line_number, start_column, end_line_number, end_column)
}

///|
/// An intersection of the two ranges, or `None` if they do not intersect.
fn Range::intersect_ranges_impl(self : Range, other : Range) -> Range? {
  Range::intersect_ranges_of(self, other)
}

///|
/// An intersection of the two ranges, or `None` if they do not intersect.
pub fn Range::intersect_ranges(self : Range, other : Range) -> Range? {
  self.intersect_ranges_impl(other)
}

///|
fn Range::intersect_ranges_of(a : Range, b : Range) -> Range? {
  let mut result_start_line_number = a.start_line_number
  let mut result_start_column = a.start_column
  let mut result_end_line_number = a.end_line_number
  let mut result_end_column = a.end_column
  let other_start_line_number = b.start_line_number
  let other_start_column = b.start_column
  let other_end_line_number = b.end_line_number
  let other_end_column = b.end_column
  if result_start_line_number < other_start_line_number {
    result_start_line_number = other_start_line_number
    result_start_column = other_start_column
  } else if result_start_line_number == other_start_line_number {
    result_start_column = result_start_column.max(other_start_column)
  }
  if result_end_line_number > other_end_line_number {
    result_end_line_number = other_end_line_number
    result_end_column = other_end_column
  } else if result_end_line_number == other_end_line_number {
    result_end_column = result_end_column.min(other_end_column)
  }
  if result_start_line_number > result_end_line_number {
    return None
  }
  if result_start_line_number == result_end_line_number &&
    result_start_column > result_end_column {
    return None
  }
  Some(
    Range(
      result_start_line_number, result_start_column, result_end_line_number, result_end_column,
    ),
  )
}

///|
/// The start position (before or equal to the end position).
pub fn Range::get_start_position(self : Range) -> Position {
  Position(self.start_line_number, self.start_column)
}

///|
/// New range with this range's start and the given end position.
pub fn Range::set_end_position(
  self : Range,
  end_line_number : Int,
  end_column : Int,
) -> Range {
  Range(self.start_line_number, self.start_column, end_line_number, end_column)
}

///|
/// Build a range from two positions.
pub fn Range::from_positions(start : Position, end : Position) -> Range {
  Range(start.line_number, start.column, end.line_number, end.column)
}

///|
/// Test if the two ranges are touching in any way.
pub fn Range::are_intersecting_or_touching(a : Range, b : Range) -> Bool {
  if a.end_line_number < b.start_line_number ||
    (a.end_line_number == b.start_line_number && a.end_column < b.start_column) {
    return false
  }
  if b.end_line_number < a.start_line_number ||
    (b.end_line_number == a.start_line_number && b.end_column < a.start_column) {
    return false
  }
  true
}

///|
/// Test if the two ranges are intersecting. Touching ranges are not intersecting.
fn Range::are_intersecting_impl(a : Range, b : Range) -> Bool {
  if a.end_line_number < b.start_line_number ||
    (a.end_line_number == b.start_line_number && a.end_column <= b.start_column) {
    return false
  }
  if b.end_line_number < a.start_line_number ||
    (b.end_line_number == a.start_line_number && b.end_column <= a.start_column) {
    return false
  }
  true
}

///|
/// Compare ranges by start position, then end position.
pub fn Range::compare_ranges_using_starts(a : Range, b : Range) -> Int {
  if a.start_line_number == b.start_line_number {
    if a.start_column == b.start_column {
      if a.end_line_number == b.end_line_number {
        return a.end_column - b.end_column
      }
      return a.end_line_number - b.end_line_number
    }
    return a.start_column - b.start_column
  }
  a.start_line_number - b.start_line_number
}

///|
/// Transform to a user-presentable string representation.
pub fn Range::to_string(self : Range) -> String {
  "[\{self.start_line_number},\{self.start_column} -> \{self.end_line_number},\{self.end_column}]"
}

///|
#deprecated
pub extend Range with Debug::{to_repr}

///|
pub extend Range with Eq::{equal, not_equal}
