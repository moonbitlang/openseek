// Port of `vscode/src/vs/editor/contrib/folding/browser/foldingRanges.ts`
// (checked-in vscode submodule): the
// compact `FoldingRegions` store (parallel packed u32 arrays + bit fields),
// the `FoldingRegion` accessor, `FoldRange`/`FoldSource`, and the
// `sanitizeAndMerge` reconciliation of provider ranges with user/previous
// fold state.

///|
/// A plain line range — Monaco's `ILineRange` (`foldingRanges.ts:8`).
pub(all) struct LineRange {
  start_line_number : Int
  end_line_number : Int
} derive(Eq, Debug)

///|
/// Where a fold range came from — `FoldSource` (`foldingRanges.ts:13`).
priv enum FoldSource {
  Provider
  UserDefined
  Recovered
} derive(Eq, Debug)

///|
/// One fold range with its state — Monaco's `FoldRange`
/// (`foldingRanges.ts:25`). `type_` is Monaco's `type` (a MoonBit keyword),
/// the `FoldingRangeKind` id a provider attached. `is_collapsed` and
/// `source` are mutable because `sanitizeAndMerge` rewrites them in place.
struct FoldRange {
  start_line_number : Int
  end_line_number : Int
  type_ : String?
  mut is_collapsed : Bool
  mut source : FoldSource
} derive(Eq, Debug)

///|
/// Creates a fold range for callers that compose provider ranges before
/// installing them in a `FoldingModel`.
pub fn FoldRange::FoldRange(
  start_line_number : Int,
  end_line_number : Int,
  type_? : String,
) -> FoldRange {
  {
    start_line_number,
    end_line_number,
    type_,
    is_collapsed: false,
    source: Provider,
  }
}

///|
/// The first line of this range.
pub fn FoldRange::start_line_number(self : FoldRange) -> Int {
  self.start_line_number
}

///|
/// The last line of this range.
pub fn FoldRange::end_line_number(self : FoldRange) -> Int {
  self.end_line_number
}

///|
/// Marks a host-computed outline fold whose header already contains the full
/// declaration. Its collapsed decoration keeps the chevron and optional
/// highlight but omits the ordinary trailing ellipsis.
pub const OUTLINE_BODY_FOLDING_RANGE_TYPE : String = "editor.outlineBody"

///|
/// `MAX_FOLDING_REGIONS` (`foldingRanges.ts:33`).
pub const MAX_FOLDING_REGIONS : Int = 0xFFFF

///|
/// `MAX_LINE_NUMBER` (`foldingRanges.ts:34`).
const MAX_LINE_NUMBER : Int = 0xFFFFFF

///|
/// `MASK_INDENT` (`foldingRanges.ts:36`): the top byte of each packed u32,
/// which stores half of the parent index.
const MASK_INDENT : UInt = 0xFF000000

///|
/// A packed bit set — Monaco's `BitField` (`foldingRanges.ts:38`).
priv struct BitField {
  states : FixedArray[UInt]
}

///|
fn BitField::BitField(size : Int) -> BitField {
  { states: FixedArray::make((size + 31) / 32, 0U), }
}

///|
fn BitField::get(self : BitField, index : Int) -> Bool {
  let array_index = index / 32
  let bit = index % 32
  (self.states[array_index] & (1U << bit)) != 0
}

///|
fn BitField::set(self : BitField, index : Int, new_state : Bool) -> Unit {
  let array_index = index / 32
  let bit = index % 32
  let value = self.states[array_index]
  if new_state {
    self.states[array_index] = value | (1U << bit)
  } else {
    self.states[array_index] = value & (1U << bit).lnot()
  }
}

///|
/// The compact fold-range store — Monaco's `FoldingRegions`
/// (`foldingRanges.ts:63`). Start/end line numbers live in the low 24 bits
/// of two parallel u32 arrays; once parents are computed the top byte of
/// each packs half of the region's parent index. Collapse and
/// user-defined/recovered source state live in bit fields.
struct FoldingRegions {
  start_indexes : FixedArray[UInt]
  end_indexes : FixedArray[UInt]
  collapse_states : BitField
  user_defined_states : BitField
  recovered_states : BitField
  mut parents_computed : Bool
  types : Array[String?]?
}

///|
/// The `FoldingRegions` constructor (`foldingRanges.ts:73`). Aborts on
/// mismatched or oversized inputs like the source's `throw`.
fn FoldingRegions::FoldingRegions(
  start_indexes : FixedArray[UInt],
  end_indexes : FixedArray[UInt],
  types? : Array[String?],
) -> FoldingRegions {
  if start_indexes.length() != end_indexes.length() ||
    start_indexes.length() > MAX_FOLDING_REGIONS {
    abort("invalid startIndexes or endIndexes size")
  }
  {
    start_indexes,
    end_indexes,
    collapse_states: BitField(start_indexes.length()),
    user_defined_states: BitField(start_indexes.length()),
    recovered_states: BitField(start_indexes.length()),
    parents_computed: false,
    types,
  }
}

///|
/// `ensureParentIndices` (`foldingRanges.ts:86`): lazily packs each region's
/// parent index into the top bytes of the start (low half) and end (high
/// half) words, walking the pre-sorted list with a containment stack.
fn FoldingRegions::ensure_parent_indices(self : FoldingRegions) -> Unit {
  if self.parents_computed {
    return
  }
  self.parents_computed = true
  let parent_indexes : Array[Int] = []
  let is_inside_last = (start_line_number : Int, end_line_number : Int) => {
    let index = parent_indexes[parent_indexes.length() - 1]
    self.get_start_line_number(index) <= start_line_number &&
    self.get_end_line_number(index) >= end_line_number
  }
  for i in 0..<self.start_indexes.length() {
    let start_line_number = self.start_indexes[i].reinterpret_as_int()
    let end_line_number = self.end_indexes[i].reinterpret_as_int()
    if start_line_number > MAX_LINE_NUMBER || end_line_number > MAX_LINE_NUMBER {
      abort(
        "startLineNumber or endLineNumber must not exceed \{MAX_LINE_NUMBER}",
      )
    }
    while parent_indexes.length() > 0 &&
          !is_inside_last(start_line_number, end_line_number) {
      parent_indexes.pop() |> ignore
    }
    let parent_index = if parent_indexes is [.., innermost] {
      innermost
    } else {
      -1
    }
    parent_indexes.push(i)
    self.start_indexes[i] = (start_line_number + ((parent_index & 0xFF) << 24)).reinterpret_as_uint()
    self.end_indexes[i] = (end_line_number + ((parent_index & 0xFF00) << 16)).reinterpret_as_uint()
  }
}

///|
/// Number of regions — the `length` getter (`foldingRanges.ts:111`).
pub fn FoldingRegions::length(self : FoldingRegions) -> Int {
  self.start_indexes.length()
}

///|
/// `getStartLineNumber` (`foldingRanges.ts:115`).
fn FoldingRegions::get_start_line_number(
  self : FoldingRegions,
  index : Int,
) -> Int {
  (self.start_indexes[index] & MAX_LINE_NUMBER.reinterpret_as_uint()).reinterpret_as_int()
}

///|
/// `getEndLineNumber` (`foldingRanges.ts:119`).
fn FoldingRegions::get_end_line_number(
  self : FoldingRegions,
  index : Int,
) -> Int {
  (self.end_indexes[index] & MAX_LINE_NUMBER.reinterpret_as_uint()).reinterpret_as_int()
}

///|
/// `getType` (`foldingRanges.ts:123`).
pub fn FoldingRegions::get_type(self : FoldingRegions, index : Int) -> String? {
  match self.types {
    Some(types) => types[index]
    None => None
  }
}

///|
/// `isCollapsed` (`foldingRanges.ts:131`).
fn FoldingRegions::is_collapsed(self : FoldingRegions, index : Int) -> Bool {
  self.collapse_states.get(index)
}

///|
/// `setCollapsed` (`foldingRanges.ts:135`).
fn FoldingRegions::set_collapsed(
  self : FoldingRegions,
  index : Int,
  new_state : Bool,
) -> Unit {
  self.collapse_states.set(index, new_state)
}

///|
/// `getSource` (`foldingRanges.ts:155`).
fn FoldingRegions::get_source(self : FoldingRegions, index : Int) -> FoldSource {
  if self.user_defined_states.get(index) {
    UserDefined
  } else if self.recovered_states.get(index) {
    Recovered
  } else {
    Provider
  }
}

///|
/// `setSource` (`foldingRanges.ts:164`).
fn FoldingRegions::set_source(
  self : FoldingRegions,
  index : Int,
  source : FoldSource,
) -> Unit {
  self.user_defined_states.set(index, source is UserDefined)
  self.recovered_states.set(index, source is Recovered)
}

///|
/// `toRegion` (`foldingRanges.ts:190`).
fn FoldingRegions::to_region(
  self : FoldingRegions,
  index : Int,
) -> FoldingRegion {
  { ranges: self, index, }
}

///|
/// `getParentIndex` (`foldingRanges.ts:194`): reassembles the packed parent
/// from the two top bytes; `MAX_FOLDING_REGIONS` decodes back to "no parent".
fn FoldingRegions::get_parent_index(self : FoldingRegions, index : Int) -> Int {
  self.ensure_parent_indices()
  let parent = ((self.start_indexes[index] & MASK_INDENT) >> 24) +
    ((self.end_indexes[index] & MASK_INDENT) >> 16)
  if parent.reinterpret_as_int() == MAX_FOLDING_REGIONS {
    return -1
  }
  parent.reinterpret_as_int()
}

///|
/// `contains` (`foldingRanges.ts:203`).
fn FoldingRegions::contains(
  self : FoldingRegions,
  index : Int,
  line : Int,
) -> Bool {
  self.get_start_line_number(index) <= line &&
  self.get_end_line_number(index) >= line
}

///|
/// `findIndex` (`foldingRanges.ts:207`): the last region starting at or
/// before `line`, `-1` when none.
fn FoldingRegions::find_index(self : FoldingRegions, line : Int) -> Int {
  if self.start_indexes.length() == 0 {
    return -1 // no children
  }
  let (low, _high) = for low = 0, high = self.start_indexes.length(); low < high; {
    let mid = (low + high) / 2
    if line < self.get_start_line_number(mid) {
      continue low, mid
    } else {
      continue mid + 1, high
    }
  } nobreak {
    (low, high)
  }
  low - 1
}

///|
/// `findRange` (`foldingRanges.ts:223`): the innermost region containing
/// `line`, walking parents outward; `-1` when none.
fn FoldingRegions::find_range(self : FoldingRegions, line : Int) -> Int {
  let index = self.find_index(line)
  if index < 0 {
    return -1
  }
  if self.get_end_line_number(index) >= line {
    return index
  }
  for index = self.get_parent_index(index); index != -1; {
    if self.contains(index, line) {
      break index
    }
    continue self.get_parent_index(index)
  } nobreak {
    -1
  }
}

///|
/// `toFoldRange` (`foldingRanges.ts:250`).
pub fn FoldingRegions::to_fold_range(
  self : FoldingRegions,
  index : Int,
) -> FoldRange {
  {
    start_line_number: (self.start_indexes[index] &
    MAX_LINE_NUMBER.reinterpret_as_uint()).reinterpret_as_int(),
    end_line_number: (self.end_indexes[index] &
    MAX_LINE_NUMBER.reinterpret_as_uint()).reinterpret_as_int(),
    type_: self.get_type(index),
    is_collapsed: self.is_collapsed(index),
    source: self.get_source(index),
  }
}

///|
/// `fromFoldRanges` (`foldingRanges.ts:260`).
pub fn FoldingRegions::from_fold_ranges(
  ranges : Array[FoldRange],
) -> FoldingRegions {
  let ranges_length = ranges.length()
  let start_indexes = FixedArray::make(ranges_length, 0U)
  let end_indexes = FixedArray::make(ranges_length, 0U)
  let types : Array[String?] = [ for range in ranges => range.type_ ]
  for i, range in ranges {
    start_indexes[i] = range.start_line_number.reinterpret_as_uint()
    end_indexes[i] = range.end_line_number.reinterpret_as_uint()
  }
  let regions = FoldingRegions(
    start_indexes,
    end_indexes,
    types?=if types.any(t => t is Some(_)) { Some(types) } else { None },
  )
  for i, range in ranges {
    if range.is_collapsed {
      regions.set_collapsed(i, true)
    }
    regions.set_source(i, range.source)
  }
  regions
}

///|
/// The `FoldingRegions | FoldRange[]` parameter union of `sanitizeAndMerge`
/// (`foldingRanges.ts:302-303`), made explicit for MoonBit.
priv enum FoldRangesOrRegions {
  Regions(FoldingRegions)
  Ranges(Array[FoldRange])
}

///|
fn FoldRangesOrRegions::at(self : FoldRangesOrRegions, i : Int) -> FoldRange? {
  match self {
    Regions(regions) =>
      if i < regions.length() {
        Some(regions.to_fold_range(i))
      } else {
        None
      }
    Ranges(ranges) => if i < ranges.length() { Some(ranges[i]) } else { None }
  }
}

///|
/// `sanitizeAndMerge` (`foldingRanges.ts:301`): merges the provider list
/// (`ranges_a`, always complete) with the previously-collapsed/user list
/// (`ranges_b`, which wins on overlap), dropping invalid entries — see the
/// source's contract comment. Both inputs must be pre-sorted on
/// `start_line_number`.
fn FoldingRegions::sanitize_and_merge(
  ranges_a : FoldRangesOrRegions,
  ranges_b : FoldRangesOrRegions,
  max_line_number : Int?,
  selection? : SelectedLines,
) -> Array[FoldRange] {
  // `maxLineNumber ?? Number.MAX_VALUE`: any Int line number qualifies.
  let max_line_number = max_line_number.unwrap_or(0x7FFFFFFF)
  let mut index_a = 0
  let mut index_b = 0
  let mut next_a = ranges_a.at(0)
  let mut next_b = ranges_b.at(0)
  let stacked_ranges : Array[FoldRange] = []
  let mut top_stacked_range : FoldRange? = None
  let mut prev_line_number = 0
  let result_ranges : Array[FoldRange] = []
  while next_a is Some(_) || next_b is Some(_) {
    let mut use_range : FoldRange? = None
    // `nextB && (!nextA || nextA.startLineNumber >= nextB.startLineNumber)`
    let b_is_next = match (next_a, next_b) {
      (_, None) => false
      (None, Some(_)) => true
      (Some(a_range), Some(b_range)) =>
        a_range.start_line_number >= b_range.start_line_number
    }
    if b_is_next {
      guard next_b is Some(b) else { break }
      if next_a is Some(a_range) &&
        a_range.start_line_number == b.start_line_number {
        if b.source == UserDefined {
          // a user defined range (possibly unfolded)
          use_range = Some(b)
        } else {
          // a previously folded range or a (possibly unfolded) recovered
          // range
          use_range = Some(a_range)
          // stays collapsed if the range still has the same number of
          // lines or the selection is not in the range or after it
          a_range.is_collapsed = b.is_collapsed &&
            (
              a_range.end_line_number == b.end_line_number ||
              !(selection is Some(sel) &&
              (sel.starts_inside)(
                a_range.start_line_number + 1,
                a_range.end_line_number + 1,
              ))
            )
          a_range.source = Provider
        }
        index_a += 1 // not necessary, just for speed
        next_a = ranges_a.at(index_a)
      } else {
        use_range = Some(b)
        if b.is_collapsed && b.source == Provider {
          // a previously collapsed range
          b.source = Recovered
        }
      }
      index_b += 1
      next_b = ranges_b.at(index_b)
    } else {
      guard next_a is Some(a_range) else { break }
      // nextA is next. The user folded B set takes precedence and we
      // sometimes need to look ahead in it to check for an upcoming
      // conflict.
      let mut scan_index = index_b
      let mut prescan_b = next_b
      for ;; {
        match prescan_b {
          None => {
            use_range = Some(a_range)
            break // no conflict, use this nextA
          }
          Some(b_range) => {
            if b_range.start_line_number > a_range.end_line_number {
              use_range = Some(a_range)
              break // no conflict, use this nextA
            }
            if b_range.source == UserDefined &&
              b_range.end_line_number > a_range.end_line_number {
              // we found a user folded range, it wins
              break // without setting use_range, so this nextA gets skipped
            }
            scan_index += 1
            prescan_b = ranges_b.at(scan_index)
          }
        }
      }
      index_a += 1
      next_a = ranges_a.at(index_a)
    }
    if use_range is Some(range) {
      while top_stacked_range is Some(top) &&
            top.end_line_number < range.start_line_number {
        top_stacked_range = stacked_ranges.pop()
      }
      if range.end_line_number > range.start_line_number &&
        range.start_line_number > prev_line_number &&
        range.end_line_number <= max_line_number &&
        !(top_stacked_range is Some(top) &&
        top.end_line_number < range.end_line_number) {
        result_ranges.push(range)
        prev_line_number = range.start_line_number
        if top_stacked_range is Some(top) {
          stacked_ranges.push(top)
        }
        top_stacked_range = Some(range)
      }
    }
  }
  result_ranges
}

///|
/// A region handle over the compact store — Monaco's `FoldingRegion`
/// (`foldingRanges.ts:395`).
struct FoldingRegion {
  ranges : FoldingRegions
  index : Int
}

///|
/// The `startLineNumber` getter.
pub fn FoldingRegion::start_line_number(self : FoldingRegion) -> Int {
  self.ranges.get_start_line_number(self.index)
}

///|
/// The `endLineNumber` getter.
pub fn FoldingRegion::end_line_number(self : FoldingRegion) -> Int {
  self.ranges.get_end_line_number(self.index)
}

///|
/// The `regionIndex` getter.
fn FoldingRegion::region_index(self : FoldingRegion) -> Int {
  self.index
}

///|
/// The `parentIndex` getter.
fn FoldingRegion::parent_index(self : FoldingRegion) -> Int {
  self.ranges.get_parent_index(self.index)
}

///|
/// The `isCollapsed` getter.
pub fn FoldingRegion::is_collapsed(self : FoldingRegion) -> Bool {
  self.ranges.is_collapsed(self.index)
}

///|
/// `containedBy` (`foldingRanges.ts:420`).
pub fn FoldingRegion::contained_by(
  self : FoldingRegion,
  range : LineRange,
) -> Bool {
  range.start_line_number <= self.start_line_number() &&
  range.end_line_number >= self.end_line_number()
}

///|
/// `containsLine` (`foldingRanges.ts:423`).
fn FoldingRegion::contains_line(
  self : FoldingRegion,
  line_number : Int,
) -> Bool {
  self.start_line_number() <= line_number &&
  line_number <= self.end_line_number()
}

///|
pub extend FoldRange with Debug::{to_repr}

///|
pub extend FoldRange with Eq::{equal, not_equal}

///|
pub extend LineRange with Debug::{to_repr}

///|
pub extend LineRange with Eq::{equal, not_equal}
