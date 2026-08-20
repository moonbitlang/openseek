///|
/// A position in the editor, the viewer-used subset of Monaco/VS Code's `Position`
/// (`vs/editor/common/core/position.ts`). One-based on both axes:
/// `line_number` starts at 1 and `column` starts at 1 (the first character on a
/// line sits between column 1 and column 2). Field names use the repo's
/// snake_case convention (`line_number`), matching `Range::start_line_number`.
pub(all) struct Position {
  line_number : Int
  column : Int
} derive(Eq, Debug)

///|
/// A range of offsets (0-based), half-open `[start, end_exclusive)`. A subset
/// port of Monaco's `OffsetRange` (`core/ranges/offsetRange.ts`) containing the
/// operations used by the viewer; field names use the repo's snake_case
/// (`end_exclusive`). The name `Range` is reserved for
/// Monaco's line/column range (see `monaco_range.mbt`).
pub struct OffsetRange {
  start : Int
  end_exclusive : Int
} derive(Eq, Debug)

///|
/// Builds a position without normalization; callers decide the coordinate
/// space before conversion through a snapshot.
pub fn Position::Position(line_number : Int, column : Int) -> Position {
  { line_number, column }
}

///|
/// Whether this position equals `other`. Mirrors Monaco's `Position.equals`.
pub fn Position::equals(self : Position, other : Position) -> Bool {
  self.line_number == other.line_number && self.column == other.column
}

///|
/// Whether this position is strictly before `other` (equal positions return
/// false). Mirrors Monaco's `Position.isBefore`.
pub fn Position::is_before(self : Position, other : Position) -> Bool {
  if self.line_number < other.line_number {
    return true
  }
  if other.line_number < self.line_number {
    return false
  }
  self.column < other.column
}

///|
/// Whether this position is before or equal to `other`. Mirrors Monaco's
/// `Position.isBeforeOrEqual`.
pub fn Position::is_before_or_equal(self : Position, other : Position) -> Bool {
  if self.line_number < other.line_number {
    return true
  }
  if other.line_number < self.line_number {
    return false
  }
  self.column <= other.column
}

///|
/// Builds a half-open offset range. Monaco's constructor throws a
/// `BugIndicatingError` when `start > end_exclusive`; the readonly viewer avoids
/// panics, so this normalizes by swapping instead. For valid inputs
/// (`start <= end_exclusive`) the swap is a no-op, so every other method keeps
/// Monaco's behavior.
pub fn OffsetRange::OffsetRange(
  start : Int,
  end_exclusive : Int,
) -> OffsetRange {
  if start <= end_exclusive {
    { start, end_exclusive }
  } else {
    { start: end_exclusive, end_exclusive: start }
  }
}

///|
/// `[start, end_exclusive)`. Mirrors Monaco's static `OffsetRange.fromTo`.
pub fn OffsetRange::from_to(start : Int, end_exclusive : Int) -> OffsetRange {
  OffsetRange(start, end_exclusive)
}

///|
/// `[0, length)`. Mirrors Monaco's static `OffsetRange.ofLength`.
pub fn OffsetRange::of_length(length : Int) -> OffsetRange {
  OffsetRange(0, length)
}

///|
/// The empty range `[offset, offset)`. Mirrors Monaco's `OffsetRange.emptyAt`.
pub fn OffsetRange::empty_at(offset : Int) -> OffsetRange {
  OffsetRange(offset, offset)
}

///|
/// Whether the range contains no offsets. Mirrors Monaco's `isEmpty` getter.
pub fn OffsetRange::is_empty(self : OffsetRange) -> Bool {
  self.start == self.end_exclusive
}

///|
/// The number of offsets in the range. Mirrors Monaco's `length` getter.
pub fn OffsetRange::length(self : OffsetRange) -> Int {
  self.end_exclusive - self.start
}

///|
/// Whether this range equals `other`. Mirrors Monaco's `equals`.
pub fn OffsetRange::equals(self : OffsetRange, other : OffsetRange) -> Bool {
  self.start == other.start && self.end_exclusive == other.end_exclusive
}

///|
/// Whether `offset` falls inside the half-open range. Mirrors Monaco's
/// `contains`.
pub fn OffsetRange::contains(self : OffsetRange, offset : Int) -> Bool {
  self.start <= offset && offset < self.end_exclusive
}

///|
/// Inserts `range` into `sorted_ranges`, merging it with any ranges it touches
/// or overlaps so the array stays sorted and non-overlapping. Mirrors Monaco's
/// static `OffsetRange.addRange`.
pub fn OffsetRange::add_range(
  range : OffsetRange,
  sorted_ranges : Array[OffsetRange],
) -> Unit {
  let i = for i = 0; i < sorted_ranges.length() &&
             sorted_ranges[i].end_exclusive < range.start; {
    continue i + 1
  } nobreak {
    i
  }
  let j = for j = i; j < sorted_ranges.length() &&
             sorted_ranges[j].start <= range.end_exclusive; {
    continue j + 1
  } nobreak {
    j
  }
  if i == j {
    sorted_ranges.insert(i, range)
  } else {
    let start = range.start.min(sorted_ranges[i].start)
    let end = range.end_exclusive.max(sorted_ranges[j - 1].end_exclusive)
    for _ in 0..<(j - i) {
      sorted_ranges.remove(i) |> ignore
    }
    sorted_ranges.insert(i, OffsetRange(start, end))
  }
}

///|
#deprecated
pub extend OffsetRange with Debug::{to_repr}

///|
pub extend OffsetRange with Eq::{equal, not_equal}

///|
#deprecated
pub extend Position with Debug::{to_repr}

///|
pub extend Position with Eq::{equal, not_equal}
