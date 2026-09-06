///|
/// Faithful 1:1 port of Monaco's `LinesLayout` (and `EditorWhitespace`) from
/// `vscode/src/vs/editor/common/viewLayout/linesLayout.ts` in the checked-in submodule.
///
/// Layouts objects that take vertical space (lines and the whitespaces between
/// them, i.e. view zones). Lines are addressed with Monaco's 1-based line
/// numbers; whitespaces are addressed by an opaque `id`, sorted by
/// `(afterLineNumber, ordinal)`.
///
/// DEVIATION: variable line heights (`LineHeightsManager` /
/// `lineHeights.test.ts`) are out of scope (Conditional row in the conformance
/// plan), so the port keeps a single uniform `default_line_height`. Every
/// `linesLayout.test.ts` case constructs the layout with an empty
/// `customLineHeightData` (`[]`), so this matches the upstream tests exactly;
/// the accumulated-line-height helper collapses to `lineNumber * height`.

///|
/// A whitespace (view zone) that displaces the lines after `after_line_number`.
pub struct EditorWhitespace {
  id : String
  mut after_line_number : Int
  ordinal : Int
  mut height : Int
  mut min_width : Int
  mut prefix_sum : Double
} derive(Eq, Debug)

///|
/// Constructs a whitespace; `prefix_sum` starts at 0 (lazily computed).
pub fn EditorWhitespace::EditorWhitespace(
  id : String,
  after_line_number : Int,
  ordinal : Int,
  height : Int,
  min_width : Int,
) -> EditorWhitespace {
  { id, after_line_number, ordinal, height, min_width, prefix_sum: 0.0, }
}

///|
/// Lines and relative offsets positioned between two vertical offsets — the
/// Monaco `IPartialViewLinesViewportData` shape.
pub struct PartialViewLinesViewportData {
  big_numbers_delta : Int
  start_line_number : Int
  end_line_number : Int
  relative_vertical_offset : Array[Double]
  centered_line_number : Int
  completely_visible_start_line_number : Int
  completely_visible_end_line_number : Int
  line_height : Int
} derive(Eq, Debug)

///|
/// One whitespace positioned relative to a viewport — the Monaco
/// `IViewWhitespaceViewportData` shape.
pub struct ViewWhitespaceViewportData {
  id : String
  after_line_number : Int
  vertical_offset : Double
  height : Int
} derive(Eq, Debug)

///|
priv struct PendingChange {
  id : String
  new_after_line_number : Int
  new_height : Int
  new_min_width : Int?
}

///|
priv struct PendingRemove {
  id : String
}

///|
priv struct PendingChanges {
  mut has_pending : Bool
  mut inserts : Array[EditorWhitespace]
  mut changes : Array[PendingChange]
  mut removes : Array[PendingRemove]
}

///|
fn PendingChanges::PendingChanges() -> PendingChanges {
  { has_pending: false, inserts: [], changes: [], removes: [], }
}

///|
fn PendingChanges::insert(self : PendingChanges, x : EditorWhitespace) -> Unit {
  self.has_pending = true
  self.inserts.push(x)
}

///|
fn PendingChanges::change(self : PendingChanges, x : PendingChange) -> Unit {
  self.has_pending = true
  self.changes.push(x)
}

///|
fn PendingChanges::remove(self : PendingChanges, x : PendingRemove) -> Unit {
  self.has_pending = true
  self.removes.push(x)
}

///|
fn PendingChanges::commit(
  self : PendingChanges,
  lines_layout : LinesLayout,
) -> Unit {
  if !self.has_pending {
    return
  }
  let inserts = self.inserts
  let changes = self.changes
  let removes = self.removes
  self.has_pending = false
  self.inserts = []
  self.changes = []
  self.removes = []
  lines_layout.commit_pending_changes(inserts, changes, removes)
}

///|
/// Global instance counter, mirroring Monaco's `LinesLayout.INSTANCE_COUNT`.
let lines_layout_instance_count : Ref[Int] = Ref(0)

///|
/// ECMAScript ToInt32, used by LinesLayout's public-number boundary. MoonBit's
/// `Double::to_int` saturates; JavaScript instead truncates, reduces modulo
/// 2^32, and interprets the high half as negative. NaN, infinities, and both
/// signed zeros canonicalize to integer zero.
fn javascript_to_int32(value : Double) -> Int {
  let modulus = 4294967296.0
  let signed_boundary = 2147483648.0
  let mut wrapped = value.trunc() % modulus
  if wrapped.is_nan() || wrapped == 0.0 {
    return 0
  }
  if wrapped < 0.0 {
    wrapped += modulus
  }
  if wrapped >= signed_boundary {
    (wrapped - modulus).to_int()
  } else {
    wrapped.to_int()
  }
}

///|
/// Mutable accessor handed to `change_whitespace`, mirroring Monaco's
/// `IWhitespaceChangeAccessor`.
struct WhitespaceChangeAccessor {
  layout : LinesLayout
  mut had_a_change : Bool
  mut min_width_update_requested : Bool
}

///|
/// Queues a whitespace insertion; returns its freshly minted id.
pub fn WhitespaceChangeAccessor::insert_whitespace(
  self : WhitespaceChangeAccessor,
  after_line_number : Int,
  ordinal : Int,
  height_in_px : Double,
  min_width : Double,
) -> String {
  self.had_a_change = true
  // JavaScript's `| 0` is ToInt32, not MoonBit's saturating `Double::to_int`.
  // Keep public number carriers raw until this exact LinesLayout boundary.
  let height_in_px = javascript_to_int32(height_in_px)
  let min_width = javascript_to_int32(min_width)
  self.layout.last_whitespace_id += 1
  let id = "\{self.layout.instance_id}\{self.layout.last_whitespace_id}"
  self.layout.pending_changes.insert(
    EditorWhitespace(id, after_line_number, ordinal, height_in_px, min_width),
  )
  id
}

///|
/// Queues a whitespace `afterLineNumber`/`height` change.
pub fn WhitespaceChangeAccessor::change_one_whitespace(
  self : WhitespaceChangeAccessor,
  id : String,
  new_after_line_number : Int,
  new_height : Double,
  new_min_width? : Double,
) -> Unit {
  self.had_a_change = true
  if new_min_width is Some(_) {
    self.min_width_update_requested = true
  }
  let new_height = javascript_to_int32(new_height)
  self.layout.pending_changes.change({
    id,
    new_after_line_number,
    new_height,
    new_min_width: new_min_width.map(javascript_to_int32),
  })
}

///|
/// Queues a whitespace removal.
pub fn WhitespaceChangeAccessor::remove_whitespace(
  self : WhitespaceChangeAccessor,
  id : String,
) -> Unit {
  self.had_a_change = true
  self.layout.pending_changes.remove({ id, })
}

///|
/// Vertical line layout: lines (uniform `default_line_height`) and the
/// whitespaces (view zones) that push them down.
struct LinesLayout {
  instance_id : String
  pending_changes : PendingChanges
  mut last_whitespace_id : Int
  mut arr : Array[EditorWhitespace]
  mut prefix_sum_valid_index : Int
  mut min_width : Int
  mut line_count : Int
  mut padding_top : Int
  mut padding_bottom : Int
  mut default_line_height : Int
}

///|
/// Creates a lines layout. `custom_line_height_data` is accepted for shape
/// parity with Monaco but ignored (uniform heights — see file deviation).
pub fn LinesLayout::LinesLayout(
  line_count : Int,
  default_line_height : Int,
  padding_top : Int,
  padding_bottom : Int,
) -> LinesLayout {
  lines_layout_instance_count.val += 1
  {
    instance_id: @base_common.single_letter_hash(
      lines_layout_instance_count.val,
    ),
    pending_changes: PendingChanges(),
    last_whitespace_id: 0,
    arr: [],
    prefix_sum_valid_index: -1,
    min_width: -1,
    line_count,
    padding_top,
    padding_bottom,
    default_line_height,
  }
}

///|
/// Find the insertion index for a new whitespace inside a sorted array. If the
/// value is already present, the index is after the existing one.
pub fn LinesLayout::find_insertion_index(
  arr : Array[EditorWhitespace],
  after_line_number : Int,
  ordinal : Int,
) -> Int {
  for low = 0, high = arr.length(); low < high; {
    let mid = (low + high) / 2
    if after_line_number == arr[mid].after_line_number {
      if ordinal < arr[mid].ordinal {
        continue low, mid
      } else {
        continue mid + 1, high
      }
    } else if after_line_number < arr[mid].after_line_number {
      continue low, mid
    } else {
      continue mid + 1, high
    }
  } nobreak {
    low
  }
}

///|
/// Change the uniform line height in pixels.
pub fn LinesLayout::set_default_line_height(
  self : LinesLayout,
  line_height : Int,
) -> Unit {
  self.default_line_height = line_height
}

///|
/// Changes the padding used to calculate vertical offsets.
pub fn LinesLayout::set_padding(
  self : LinesLayout,
  padding_top : Int,
  padding_bottom : Int,
) -> Unit {
  self.padding_top = padding_top
  self.padding_bottom = padding_bottom
}

///|
/// Set the number of lines (Monaco's `onFlushed`).
pub fn LinesLayout::on_flushed(self : LinesLayout, line_count : Int) -> Unit {
  self.line_count = line_count
}

///|
/// Run `callback` with a whitespace-change accessor, then commit the batch.
/// Returns whether anything changed.
pub fn LinesLayout::change_whitespace(
  self : LinesLayout,
  callback : (WhitespaceChangeAccessor) -> Unit raise?,
) -> Bool raise? {
  let (had_a_change, _) = self.change_whitespace_with_width(callback)
  had_a_change
}

///|
fn LinesLayout::change_whitespace_with_width(
  self : LinesLayout,
  callback : (WhitespaceChangeAccessor) -> Unit raise?,
) -> (Bool, Bool) raise? {
  let accessor = {
    layout: self,
    had_a_change: false,
    min_width_update_requested: false,
  }
  // Monaco commits in `finally`: queued work survives a callback failure, and
  // the queues are cleared before that failure continues to the caller.
  defer self.pending_changes.commit(self)
  callback(accessor)
  (accessor.had_a_change, accessor.min_width_update_requested)
}

///|
fn LinesLayout::commit_pending_changes(
  self : LinesLayout,
  inserts : Array[EditorWhitespace],
  changes : Array[PendingChange],
  removes : Array[PendingRemove],
) -> Unit {
  if inserts.length() > 0 ||
    removes.length() > 0 ||
    changes.any(change => change.new_min_width is Some(_)) {
    self.min_width = -1
  }
  if inserts.length() + changes.length() + removes.length() <= 1 {
    // when only one thing happened, handle it "delicately"
    for insert in inserts {
      self.insert_whitespace(insert)
    }
    for change in changes {
      self.change_one_whitespace(
        change.id,
        change.new_after_line_number,
        change.new_height,
        change.new_min_width,
      )
    }
    for remove in removes {
      let index = self.find_whitespace_index(remove.id)
      if index == -1 {
        continue
      }
      self.remove_whitespace(index)
    }
    return
  }

  // simply rebuild the entire datastructure
  let to_remove : Map[String, Bool] = Map([])
  for remove in removes {
    to_remove[remove.id] = true
  }
  let to_change : Map[String, PendingChange] = Map([])
  for change in changes {
    to_change[change.id] = change
  }
  let apply_remove_and_change = fn(
    whitespaces : Array[EditorWhitespace],
  ) -> Array[EditorWhitespace] {
    let result : Array[EditorWhitespace] = []
    for whitespace in whitespaces {
      if to_remove.contains(whitespace.id) {
        continue
      }
      if to_change.get(whitespace.id) is Some(change) {
        whitespace.after_line_number = change.new_after_line_number
        whitespace.height = change.new_height
        if change.new_min_width is Some(min_width) {
          whitespace.min_width = min_width
        }
      }
      result.push(whitespace)
    }
    result
  }
  let result = apply_remove_and_change(self.arr)
  for w in apply_remove_and_change(inserts) {
    result.push(w)
  }
  // ECMAScript Array.prototype.sort is stable. Preserve the source array's
  // old-before-inserts sequence explicitly because MoonBit's backend sort is
  // not required to keep equal-key elements in their original order.
  let original_sequence : Map[String, Int] = Map([])
  for index, whitespace in result {
    original_sequence[whitespace.id] = index
  }
  result.sort_by((a, b) => {
    match a.after_line_number.compare(b.after_line_number) {
      0 =>
        match a.ordinal.compare(b.ordinal) {
          0 => original_sequence[a.id].compare(original_sequence[b.id])
          ordinal_order => ordinal_order
        }
      line_order => line_order
    }
  })
  self.arr = result
  self.prefix_sum_valid_index = -1
}

///|
fn LinesLayout::insert_whitespace(
  self : LinesLayout,
  whitespace : EditorWhitespace,
) -> Unit {
  let insert_index = LinesLayout::find_insertion_index(
    self.arr,
    whitespace.after_line_number,
    whitespace.ordinal,
  )
  self.arr.insert(insert_index, whitespace)
  self.prefix_sum_valid_index = self.prefix_sum_valid_index.min(
    insert_index - 1,
  )
}

///|
fn LinesLayout::find_whitespace_index(self : LinesLayout, id : String) -> Int {
  self.arr.search_by(whitespace => whitespace.id == id).unwrap_or(-1)
}

///|
fn LinesLayout::change_one_whitespace(
  self : LinesLayout,
  id : String,
  new_after_line_number : Int,
  new_height : Int,
  new_min_width : Int?,
) -> Unit {
  let index = self.find_whitespace_index(id)
  if index == -1 {
    return
  }
  if self.arr[index].height != new_height {
    self.arr[index].height = new_height
    self.prefix_sum_valid_index = self.prefix_sum_valid_index.min(index - 1)
  }
  if new_min_width is Some(min_width) && self.arr[index].min_width != min_width {
    self.arr[index].min_width = min_width
    self.min_width = -1
  }
  if self.arr[index].after_line_number != new_after_line_number {
    // `afterLineNumber` changed: removing then re-inserting may reorder it.
    let whitespace = self.arr[index]
    self.remove_whitespace(index)
    whitespace.after_line_number = new_after_line_number
    self.insert_whitespace(whitespace)
  }
}

///|
fn LinesLayout::remove_whitespace(
  self : LinesLayout,
  remove_index : Int,
) -> Unit {
  self.arr.remove(remove_index) |> ignore
  self.prefix_sum_valid_index = self.prefix_sum_valid_index.min(
    remove_index - 1,
  )
}

///|
/// Notify that a continuous zone of lines was deleted (inclusive bounds).
pub fn LinesLayout::on_lines_deleted(
  self : LinesLayout,
  from_line_number : Int,
  to_line_number : Int,
) -> Unit {
  self.line_count -= to_line_number - from_line_number + 1
  for i in 0..<self.arr.length() {
    let after_line_number = self.arr[i].after_line_number
    if from_line_number <= after_line_number &&
      after_line_number <= to_line_number {
      // The line this whitespace was after has been deleted
      //  => move whitespace to before first deleted line
      self.arr[i].after_line_number = from_line_number - 1
    } else if after_line_number > to_line_number {
      // The line this whitespace was after has been moved up
      //  => move whitespace up
      self.arr[i].after_line_number -= to_line_number - from_line_number + 1
    }
  }
}

///|
/// Notify that a continuous zone of lines was inserted (inclusive bounds).
pub fn LinesLayout::on_lines_inserted(
  self : LinesLayout,
  from_line_number : Int,
  to_line_number : Int,
) -> Unit {
  self.line_count += to_line_number - from_line_number + 1
  for i in 0..<self.arr.length() {
    let after_line_number = self.arr[i].after_line_number
    if from_line_number <= after_line_number {
      self.arr[i].after_line_number += to_line_number - from_line_number + 1
    }
  }
}

///|
/// The sum of all whitespace heights.
pub fn LinesLayout::get_whitespaces_total_height(self : LinesLayout) -> Double {
  if self.arr.length() == 0 {
    return 0.0
  }
  self.get_whitespaces_accumulated_height(self.arr.length() - 1)
}

///|
/// Sum of the heights of whitespaces in `[0..index]` (inclusive of `index`).
pub fn LinesLayout::get_whitespaces_accumulated_height(
  self : LinesLayout,
  index : Int,
) -> Double {
  let mut start_index = (0).max(self.prefix_sum_valid_index + 1)
  if start_index == 0 {
    self.arr[0].prefix_sum = self.arr[0].height.to_double()
    start_index += 1
  }
  for i in start_index..<=index {
    self.arr[i].prefix_sum = self.arr[i - 1].prefix_sum +
      self.arr[i].height.to_double()
  }
  self.prefix_sum_valid_index = self.prefix_sum_valid_index.max(index)
  self.arr[index].prefix_sum
}

///|
/// The sum of heights for all objects (lines + whitespaces + padding).
pub fn LinesLayout::get_lines_total_height(self : LinesLayout) -> Double {
  let lines_height = self.accumulated_line_heights_including_line_number(
    self.line_count,
  )
  let whitespaces_height = self.get_whitespaces_total_height()
  lines_height +
  whitespaces_height +
  self.padding_top.to_double() +
  self.padding_bottom.to_double()
}

///|
/// Accumulated height of whitespaces strictly before `line_number`.
pub fn LinesLayout::get_whitespace_accumulated_height_before_line_number(
  self : LinesLayout,
  line_number : Int,
) -> Double {
  let last_whitespace_before = self.find_last_whitespace_before_line_number(
    line_number,
  )
  if last_whitespace_before == -1 {
    return 0.0
  }
  self.get_whitespaces_accumulated_height(last_whitespace_before)
}

///|
fn LinesLayout::find_last_whitespace_before_line_number(
  self : LinesLayout,
  line_number : Int,
) -> Int {
  let arr = self.arr
  for low = 0, high = arr.length() - 1; low <= high; {
    let delta = high - low
    let half_delta = delta / 2
    let mid = low + half_delta
    if arr[mid].after_line_number < line_number {
      if mid + 1 >= arr.length() ||
        arr[mid + 1].after_line_number >= line_number {
        break mid
      } else {
        continue mid + 1, high
      }
    } else {
      continue low, mid - 1
    }
  } nobreak {
    -1
  }
}

///|
fn LinesLayout::find_first_whitespace_after_line_number(
  self : LinesLayout,
  line_number : Int,
) -> Int {
  let last_whitespace_before = self.find_last_whitespace_before_line_number(
    line_number,
  )
  let first_whitespace_after = last_whitespace_before + 1
  if first_whitespace_after < self.arr.length() {
    return first_whitespace_after
  }
  -1
}

///|
/// Index of the first whitespace with `afterLineNumber` >= `line_number`,
/// or -1 if there is none.
pub fn LinesLayout::get_first_whitespace_index_after_line_number(
  self : LinesLayout,
  line_number : Int,
) -> Int {
  self.find_first_whitespace_after_line_number(line_number)
}

///|
/// Vertical offset (sum of heights of everything above) of `line_number`.
pub fn LinesLayout::get_vertical_offset_for_line_number(
  self : LinesLayout,
  line_number : Int,
  include_view_zones? : Bool = false,
) -> Double {
  let previous_lines_height = if line_number > 1 {
    self.accumulated_line_heights_including_line_number(line_number - 1)
  } else {
    0.0
  }
  let previous_whitespaces_height = self.get_whitespace_accumulated_height_before_line_number(
    line_number - (if include_view_zones { 1 } else { 0 }),
  )
  previous_lines_height +
  previous_whitespaces_height +
  self.padding_top.to_double()
}

///|
/// The (uniform) height of `line_number`.
pub fn LinesLayout::get_line_height_for_line_number(
  self : LinesLayout,
  _line_number : Int,
) -> Int {
  self.default_line_height
}

///|
/// Vertical offset including `line_number`'s own height.
pub fn LinesLayout::get_vertical_offset_after_line_number(
  self : LinesLayout,
  line_number : Int,
  include_view_zones? : Bool = false,
) -> Double {
  let previous_lines_height = self.accumulated_line_heights_including_line_number(
    line_number,
  )
  let previous_whitespaces_height = self.get_whitespace_accumulated_height_before_line_number(
    line_number + (if include_view_zones { 1 } else { 0 }),
  )
  previous_lines_height +
  previous_whitespaces_height +
  self.padding_top.to_double()
}

///|
/// Whether there is any whitespace in the document.
pub fn LinesLayout::has_whitespace(self : LinesLayout) -> Bool {
  self.get_whitespaces_count() > 0
}

///|
/// The maximum min width over all whitespaces.
pub fn LinesLayout::get_whitespace_min_width(self : LinesLayout) -> Int {
  if self.min_width == -1 {
    self.min_width = self.arr.fold(init=0, (widest, whitespace) => {
      widest.max(whitespace.min_width)
    })
  }
  self.min_width
}

///|
/// Whether `vertical_offset` is below all lines.
pub fn LinesLayout::is_after_lines(
  self : LinesLayout,
  vertical_offset : Double,
) -> Bool {
  vertical_offset > self.get_lines_total_height()
}

///|
/// Whether `vertical_offset` falls in the top padding.
pub fn LinesLayout::is_in_top_padding(
  self : LinesLayout,
  vertical_offset : Double,
) -> Bool {
  if self.padding_top == 0 {
    return false
  }
  vertical_offset < self.padding_top.to_double()
}

///|
/// Whether `vertical_offset` falls in the bottom padding.
pub fn LinesLayout::is_in_bottom_padding(
  self : LinesLayout,
  vertical_offset : Double,
) -> Bool {
  if self.padding_bottom == 0 {
    return false
  }
  vertical_offset >=
  self.get_lines_total_height() - self.padding_bottom.to_double()
}

///|
/// First line number at or after vertical offset `vertical_offset`.
pub fn LinesLayout::get_line_number_at_or_after_vertical_offset(
  self : LinesLayout,
  vertical_offset : Double,
) -> Int {
  let vertical_offset = javascript_to_int32(vertical_offset)
  if vertical_offset < 0 {
    return 1
  }
  let lines_count = self.line_count
  let min_line_number = for min_line_number = 1, max_line_number = lines_count; min_line_number <
                           max_line_number; {
    let mid_line_number = min_line_number +
      (max_line_number - min_line_number) / 2
    let line_height = self.get_line_height_for_line_number(mid_line_number)
    let mid_line_number_vertical_offset = javascript_to_int32(
      self.get_vertical_offset_for_line_number(mid_line_number),
    )
    if vertical_offset.to_double() >=
      mid_line_number_vertical_offset.to_double() + line_height.to_double() {
      // vertical offset is after mid line number
      continue mid_line_number + 1, max_line_number
    } else if vertical_offset >= mid_line_number_vertical_offset {
      // Hit
      break mid_line_number
    } else {
      // vertical offset is before mid line number, but it could still be it
      continue min_line_number, mid_line_number
    }
  } nobreak {
    min_line_number
  }
  if min_line_number > lines_count {
    return lines_count
  }
  min_line_number
}

///|
/// All lines (and their relative vertical offsets) positioned between
/// `vertical_offset1` and `vertical_offset2`.
pub fn LinesLayout::get_lines_viewport_data(
  self : LinesLayout,
  vertical_offset1 : Double,
  vertical_offset2 : Double,
) -> PartialViewLinesViewportData {
  let vertical_offset1 = javascript_to_int32(vertical_offset1)
  let vertical_offset2 = javascript_to_int32(vertical_offset2)
  // Find first line number (it might start before or after verticalOffset1).
  let start_line_number = self.get_line_number_at_or_after_vertical_offset(
    vertical_offset1.to_double(),
  )
  let start_line_number_vertical_offset = javascript_to_int32(
    self.get_vertical_offset_for_line_number(start_line_number),
  )
  let mut end_line_number = self.line_count

  // Also keep track of what whitespace we've got.
  let mut whitespace_index = self.get_first_whitespace_index_after_line_number(
    start_line_number,
  )
  let whitespace_count = self.get_whitespaces_count()
  let mut current_whitespace_height = 0
  let mut current_whitespace_after_line_number : Int? = None
  if whitespace_index == -1 {
    whitespace_index = whitespace_count
    current_whitespace_height = 0
  } else {
    current_whitespace_after_line_number = Some(
      self.get_after_line_number_for_whitespace_index(whitespace_index),
    )
    current_whitespace_height = self.get_height_for_whitespace_index(
      whitespace_index,
    )
  }
  let mut current_vertical_offset = start_line_number_vertical_offset.to_double()
  let mut current_line_relative_offset = current_vertical_offset

  // IE cannot handle units above ~1.5M px, so step down past 500k px.
  let step_size = 500000
  let mut big_numbers_delta = 0
  if start_line_number_vertical_offset >= step_size {
    big_numbers_delta = start_line_number_vertical_offset /
      step_size *
      step_size
    big_numbers_delta = big_numbers_delta /
      self.default_line_height *
      self.default_line_height
    current_line_relative_offset -= big_numbers_delta.to_double()
  }
  let lines_offsets : Array[Double] = []
  let vertical_center = vertical_offset1.to_double() +
    (vertical_offset2.to_double() - vertical_offset1.to_double()) / 2.0
  let mut centered_line_number = -1

  // Figure out how far the lines go.
  let mut line_number = start_line_number
  while line_number <= end_line_number {
    let line_height = self.get_line_height_for_line_number(line_number)
    if centered_line_number == -1 {
      let current_line_top = current_vertical_offset
      let current_line_bottom = current_vertical_offset +
        line_height.to_double()
      if (
          current_line_top <= vertical_center &&
          vertical_center < current_line_bottom
        ) ||
        current_line_top > vertical_center {
        centered_line_number = line_number
      }
    }

    // Count current line height in the vertical offsets.
    current_vertical_offset += line_height.to_double()
    lines_offsets.push(current_line_relative_offset)

    // Next line starts immediately after this one.
    current_line_relative_offset += line_height.to_double()
    while current_whitespace_after_line_number == Some(line_number) {
      // Push down next line with the height of the current whitespace.
      current_line_relative_offset += current_whitespace_height.to_double()

      // Count current whitespace in the vertical offsets.
      current_vertical_offset += current_whitespace_height.to_double()
      whitespace_index += 1
      if whitespace_index >= whitespace_count {
        current_whitespace_after_line_number = None
      } else {
        current_whitespace_after_line_number = Some(
          self.get_after_line_number_for_whitespace_index(whitespace_index),
        )
        current_whitespace_height = self.get_height_for_whitespace_index(
          whitespace_index,
        )
      }
    }
    if current_vertical_offset >= vertical_offset2.to_double() {
      // We have covered the entire viewport area, time to stop.
      end_line_number = line_number
      break
    }
    if line_number == end_line_number {
      break
    }
    line_number += 1
  }
  if centered_line_number == -1 {
    centered_line_number = end_line_number
  }
  let end_line_number_vertical_offset = javascript_to_int32(
    self.get_vertical_offset_for_line_number(end_line_number),
  )
  let mut completely_visible_start_line_number = start_line_number
  let mut completely_visible_end_line_number = end_line_number
  if completely_visible_start_line_number < completely_visible_end_line_number {
    if start_line_number_vertical_offset < vertical_offset1 {
      completely_visible_start_line_number += 1
    }
  }
  if completely_visible_start_line_number < completely_visible_end_line_number {
    let end_line_height = self.get_line_height_for_line_number(end_line_number)
    if end_line_number_vertical_offset.to_double() + end_line_height.to_double() >
      vertical_offset2.to_double() {
      completely_visible_end_line_number -= 1
    }
  }
  {
    big_numbers_delta,
    start_line_number,
    end_line_number,
    relative_vertical_offset: lines_offsets,
    centered_line_number,
    completely_visible_start_line_number,
    completely_visible_end_line_number,
    line_height: self.default_line_height,
  }
}

///|
/// Vertical offset of the whitespace at `whitespace_index`.
pub fn LinesLayout::get_vertical_offset_for_whitespace_index(
  self : LinesLayout,
  whitespace_index : Int,
) -> Double {
  let after_line_number = self.get_after_line_number_for_whitespace_index(
    whitespace_index,
  )
  let previous_lines_height = if after_line_number >= 1 {
    self.accumulated_line_heights_including_line_number(after_line_number)
  } else {
    0.0
  }
  let previous_whitespaces_height = if whitespace_index > 0 {
    self.get_whitespaces_accumulated_height(whitespace_index - 1)
  } else {
    0.0
  }
  previous_lines_height +
  previous_whitespaces_height +
  self.padding_top.to_double()
}

///|
/// Index of the first whitespace at or after vertical offset `vertical_offset`,
/// or -1 if there is none.
pub fn LinesLayout::get_whitespace_index_at_or_after_vertical_offset(
  self : LinesLayout,
  vertical_offset : Double,
) -> Int {
  let vertical_offset = javascript_to_int32(vertical_offset).to_double()
  let max_whitespace_index = self.get_whitespaces_count() - 1
  if max_whitespace_index < 0 {
    return -1
  }
  // Special case: nothing to be found.
  let max_whitespace_vertical_offset = self.get_vertical_offset_for_whitespace_index(
    max_whitespace_index,
  )
  let max_whitespace_height = self.get_height_for_whitespace_index(
    max_whitespace_index,
  )
  if vertical_offset >=
    max_whitespace_vertical_offset + max_whitespace_height.to_double() {
    return -1
  }
  for min_whitespace_index = 0, max_whitespace_index = max_whitespace_index; min_whitespace_index <
     max_whitespace_index; {
    let mid_whitespace_index = min_whitespace_index +
      (max_whitespace_index - min_whitespace_index) / 2
    let mid_whitespace_vertical_offset = self.get_vertical_offset_for_whitespace_index(
      mid_whitespace_index,
    )
    let mid_whitespace_height = self.get_height_for_whitespace_index(
      mid_whitespace_index,
    )
    if vertical_offset >=
      mid_whitespace_vertical_offset + mid_whitespace_height.to_double() {
      // vertical offset is after whitespace
      continue mid_whitespace_index + 1, max_whitespace_index
    } else if vertical_offset >= mid_whitespace_vertical_offset {
      // Hit
      break mid_whitespace_index
    } else {
      // before whitespace, but mid index could still be the answer
      continue min_whitespace_index, mid_whitespace_index
    }
  } nobreak {
    min_whitespace_index
  }
}

///|
/// Exactly the whitespace layouted at `vertical_offset`, or `None`.
pub fn LinesLayout::get_whitespace_at_vertical_offset(
  self : LinesLayout,
  vertical_offset : Double,
) -> ViewWhitespaceViewportData? {
  let vertical_offset = javascript_to_int32(vertical_offset)
  let candidate_index = self.get_whitespace_index_at_or_after_vertical_offset(
    vertical_offset.to_double(),
  )
  if candidate_index < 0 {
    return None
  }
  if candidate_index >= self.get_whitespaces_count() {
    return None
  }
  let candidate_top = self.get_vertical_offset_for_whitespace_index(
    candidate_index,
  )
  if candidate_top > vertical_offset.to_double() {
    return None
  }
  let candidate_height = self.get_height_for_whitespace_index(candidate_index)
  let candidate_id = self.get_id_for_whitespace_index(candidate_index)
  let candidate_after_line_number = self.get_after_line_number_for_whitespace_index(
    candidate_index,
  )
  Some({
    id: candidate_id,
    after_line_number: candidate_after_line_number,
    vertical_offset: candidate_top,
    height: candidate_height,
  })
}

///|
/// All whitespaces positioned between `vertical_offset1` and `vertical_offset2`.
pub fn LinesLayout::get_whitespace_viewport_data(
  self : LinesLayout,
  vertical_offset1 : Double,
  vertical_offset2 : Double,
) -> Array[ViewWhitespaceViewportData] {
  let vertical_offset1 = javascript_to_int32(vertical_offset1)
  let vertical_offset2 = javascript_to_int32(vertical_offset2)
  let start_index = self.get_whitespace_index_at_or_after_vertical_offset(
    vertical_offset1.to_double(),
  )
  let end_index = self.get_whitespaces_count() - 1
  if start_index < 0 {
    return []
  }
  let result : Array[ViewWhitespaceViewportData] = []
  for i in start_index..<=end_index {
    let top = self.get_vertical_offset_for_whitespace_index(i)
    let height = self.get_height_for_whitespace_index(i)
    if top >= vertical_offset2.to_double() {
      break
    }
    result.push({
      id: self.get_id_for_whitespace_index(i),
      after_line_number: self.get_after_line_number_for_whitespace_index(i),
      vertical_offset: top,
      height,
    })
  }
  result
}

///|
/// All whitespaces (a copy).
pub fn LinesLayout::get_whitespaces(
  self : LinesLayout,
) -> Array[EditorWhitespace] {
  self.arr.copy()
}

///|
/// The number of whitespaces.
pub fn LinesLayout::get_whitespaces_count(self : LinesLayout) -> Int {
  self.arr.length()
}

///|
/// The `id` of the whitespace at `index`.
pub fn LinesLayout::get_id_for_whitespace_index(
  self : LinesLayout,
  index : Int,
) -> String {
  self.arr[index].id
}

///|
/// The `afterLineNumber` of the whitespace at `index`.
pub fn LinesLayout::get_after_line_number_for_whitespace_index(
  self : LinesLayout,
  index : Int,
) -> Int {
  self.arr[index].after_line_number
}

///|
/// The `height` of the whitespace at `index`.
pub fn LinesLayout::get_height_for_whitespace_index(
  self : LinesLayout,
  index : Int,
) -> Int {
  self.arr[index].height
}

///|
/// Uniform-height accumulation: sum of line heights for lines `1..=line_number`
/// (`0` for `line_number <= 0`). Replaces Monaco's `LineHeightsManager`.
fn LinesLayout::accumulated_line_heights_including_line_number(
  self : LinesLayout,
  line_number : Int,
) -> Double {
  if line_number <= 0 {
    0.0
  } else {
    line_number.to_double() * self.default_line_height.to_double()
  }
}

///|
pub extend EditorWhitespace with Debug::{to_repr}

///|
pub extend EditorWhitespace with Eq::{equal, not_equal}

///|
pub extend PartialViewLinesViewportData with Debug::{to_repr}

///|
pub extend PartialViewLinesViewportData with Eq::{equal, not_equal}

///|
pub extend ViewWhitespaceViewportData with Debug::{to_repr}

///|
pub extend ViewWhitespaceViewportData with Eq::{equal, not_equal}
