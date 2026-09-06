///|
/// The line collection for every view model — Monaco's
/// `ViewModelLinesFromProjectedModel` (`viewModelLines.ts:60`), which Monaco
/// uses for all normal editors, wrapping on or off (its
/// `ViewModelLinesFromModelAsIs` is only the too-large-for-tokenization
/// escape hatch, which a readonly viewer never needs). Lines that need no
/// mapping project as `Identity` and stay allocation-free; wrapping and
/// injected text produce per-line `Projected` data.
pub struct ViewModelLinesFromProjectedModel {
  model : @model.TextModel
  mut font_info : @config.FontInfo
  mut tab_size : Int
  mut wrapping_column : Int
  mut wrapping_indent : @editor_api.WrappingIndent
  mut model_line_projections : Array[ModelLineProjection]
  /// Monaco's `projectedModelLineLineCounts` (a
  /// `ConstantTimePrefixSumComputer` over per-line view-line counts). The
  /// viewer reconstructs wholesale instead of editing incrementally, so it
  /// stores the prefix sums directly: entry `i` is the number of view lines
  /// before one-based model line `i + 1`, and the last entry is the total.
  mut projected_model_line_line_counts : Array[Int]
  /// Monaco's `hiddenAreasDecorationIds`: the hidden (folded) model ranges
  /// live as empty-options model decorations so edits keep them anchored.
  mut hidden_areas_decoration_ids : Array[String]
  // Package-private conformance counters. They make the source batch/read
  // ownership observable to white-box tests without widening the public API.
  priv mut batch_call_count : Int
  priv mut passive_token_read_count : Int
}

///|
/// Keeps the private conformance counters observable to package white-box
/// tests without leaking either field through `pkg.generated.mbti`.
fn ViewModelLinesFromProjectedModel::token_demand_counters(
  self : ViewModelLinesFromProjectedModel,
) -> (Int, Int) {
  (self.batch_call_count, self.passive_token_read_count)
}

///|
let _test_only_token_demand_counters_anchor : Unit = ignore(
  ViewModelLinesFromProjectedModel::token_demand_counters,
)

///|
/// A view line as (model line, wrapped-line index) — Monaco's `ViewLineInfo`
/// (`viewModelLines.ts:1054`).
priv struct ViewLineInfo {
  model_line_number : Int
  model_line_wrapped_line_idx : Int
}

///|
/// Builds the collection and its projections — the constructor tail of
/// Monaco's `ViewModelLinesFromProjectedModel` (`viewModelLines.ts:85-112`),
/// minus the DOM/monospace computer-factory split (the viewer is
/// monospace-only, so the monospace factory is the only one).
pub fn ViewModelLinesFromProjectedModel::ViewModelLinesFromProjectedModel(
  model : @model.TextModel,
  font_info~ : @config.FontInfo,
  tab_size~ : Int,
  wrapping_column~ : Int,
  wrapping_indent~ : @editor_api.WrappingIndent,
) -> ViewModelLinesFromProjectedModel {
  let lines = {
    model,
    font_info,
    tab_size,
    wrapping_column,
    wrapping_indent,
    model_line_projections: [],
    projected_model_line_line_counts: [0],
    hidden_areas_decoration_ids: [],
    batch_call_count: 0,
    passive_token_read_count: 0,
  }
  lines.construct_lines(reset_hidden_areas=true)
  lines
}

///|
/// Releases the owner-0 tracking decorations used for hidden areas —
/// `ViewModelLinesFromProjectedModel.dispose` (`viewModelLines.ts:114-116`).
/// Assigning the returned empty id array makes repeated disposal harmless.
pub fn ViewModelLinesFromProjectedModel::dispose(
  self : ViewModelLinesFromProjectedModel,
) -> Unit {
  self.hidden_areas_decoration_ids = self.model.delta_decorations(
    self.hidden_areas_decoration_ids,
    [],
  )
}

///|
/// Creates the coordinate converter over this collection —
/// `createCoordinatesConverter` (`viewModelLines.ts:118`).
pub fn ViewModelLinesFromProjectedModel::create_coordinates_converter(
  self : ViewModelLinesFromProjectedModel,
) -> CoordinatesConverter {
  Projected(self)
}

///|
/// Recomputes every line's projection — Monaco's `_constructLines`
/// (`viewModelLines.ts:122`), minus previous-line-break reuse (the readonly
/// viewer rebuilds wholesale). A `None` projection is the line-breaks
/// computer's null result: a line that neither wraps nor carries injected
/// text needs no mapping and projects as `Identity`. Lines inside a hidden
/// area project invisible (`createModelLineProjection(-, false)`); the
/// hidden areas are read back from their tracking decorations, so a rebuild
/// keeps folded regions folded unless `reset_hidden_areas` clears them.
fn ViewModelLinesFromProjectedModel::construct_lines(
  self : ViewModelLinesFromProjectedModel,
  reset_hidden_areas~ : Bool,
) -> Unit {
  let model_line_projections : Array[ModelLineProjection] = []
  let prefix_sums : Array[Int] = [0]
  if reset_hidden_areas {
    self.hidden_areas_decoration_ids = self.model.delta_decorations(
      self.hidden_areas_decoration_ids,
      [],
    )
  }
  let injected_text_buckets = line_injected_text_from_decorations(self.model)
  let computer = monospace_line_breaks_computer_factory.create_line_breaks_computer(
    font_info=self.font_info,
    tab_size=self.tab_size,
    wrapping_column=self.wrapping_column,
    wrapping_indent=self.wrapping_indent,
  )
  let line_count = self.model.snapshot.line_count()
  for model_line_number in 1..<=line_count {
    computer.add_request(
      model_line_number,
      self.model.snapshot.line_text(model_line_number - 1),
      injected_text_buckets[model_line_number - 1],
    )
  }
  let line_break_data = computer.finalize()
  // The sorted hidden-area walk of `_constructLines` (`viewModelLines.ts:140`).
  let hidden_areas = self.get_hidden_areas()
  hidden_areas.sort_by((a, b) => {
    @base_common.Range::compare_ranges_using_starts(a, b)
  })
  let mut hidden_area_start = 1
  let mut hidden_area_end = 0
  let mut hidden_area_idx = -1
  let mut next_line_number_to_update_hidden_area = if hidden_area_idx + 1 <
    hidden_areas.length() {
    hidden_area_end + 1
  } else {
    line_count + 2
  }
  for model_line_number in 1..<=line_count {
    if model_line_number == next_line_number_to_update_hidden_area {
      hidden_area_idx += 1
      hidden_area_start = hidden_areas[hidden_area_idx].start_line_number
      hidden_area_end = hidden_areas[hidden_area_idx].end_line_number
      next_line_number_to_update_hidden_area = if hidden_area_idx + 1 <
        hidden_areas.length() {
        hidden_area_end + 1
      } else {
        line_count + 2
      }
    }
    let is_in_hidden_area = model_line_number >= hidden_area_start &&
      model_line_number <= hidden_area_end
    let projection = create_model_line_projection(
      line_break_data[model_line_number - 1],
      !is_in_hidden_area,
    )
    model_line_projections.push(projection)
    prefix_sums.push(
      prefix_sums[model_line_number - 1] + projection.get_view_line_count(),
    )
  }
  self.model_line_projections = model_line_projections
  self.projected_model_line_line_counts = prefix_sums
  self.ensure_at_least_one_visible_line()
}

///|
/// `_ensureAtLeastOneVisibleLine` (`viewModelLines.ts:435`): a document may
/// never hide every line; reveal the first when it would.
fn ViewModelLinesFromProjectedModel::ensure_at_least_one_visible_line(
  self : ViewModelLinesFromProjectedModel,
) -> Unit {
  if self.get_view_line_count() == 0 && self.model_line_projections.length() > 0 {
    self.model_line_projections[0] = self.model_line_projections[0].set_visible(
      true,
    )
    self.rebuild_prefix_sums()
  }
}

///|
/// Recomputes the stored prefix sums from the projections' view-line counts
/// — the viewer's stand-in for Monaco's incremental
/// `projectedModelLineLineCounts.setValue` (the collection stores the sums
/// directly and rebuilds at its wholesale granularity).
fn ViewModelLinesFromProjectedModel::rebuild_prefix_sums(
  self : ViewModelLinesFromProjectedModel,
) -> Unit {
  let prefix_sums : Array[Int] = [0]
  for i, projection in self.model_line_projections {
    prefix_sums.push(prefix_sums[i] + projection.get_view_line_count())
  }
  self.projected_model_line_line_counts = prefix_sums
}

///|
/// Merged one-based hidden model-line ranges — `getHiddenAreas`
/// (`viewModelLines.ts:168`), read back from the tracking decorations.
pub fn ViewModelLinesFromProjectedModel::get_hidden_areas(
  self : ViewModelLinesFromProjectedModel,
) -> Array[@base_common.Range] {
  self.hidden_areas_decoration_ids.filter_map(decoration_id => {
    self.model.get_decoration_range(decoration_id)
  })
}

///|
/// Applies a new hidden-area set — `setHiddenAreas` (`viewModelLines.ts:174`).
/// Returns whether the view-line mapping changed. Ranges are validated,
/// normalized into merged whole-line ranges, and diffed against the current
/// decoration-tracked set before any projection is touched.
pub fn ViewModelLinesFromProjectedModel::set_hidden_areas(
  self : ViewModelLinesFromProjectedModel,
  ranges : Array[@base_common.Range],
) -> Bool {
  let validated_ranges = ranges.map(r => self.model.validate_range(r))
  let new_ranges = normalize_line_ranges(validated_ranges[:])

  // This checks if there really was a change
  let old_ranges = self.get_hidden_areas()
  old_ranges.sort_by((a, b) => {
    @base_common.Range::compare_ranges_using_starts(a, b)
  })
  if new_ranges == old_ranges {
    return false
  }
  let new_decorations : Array[@model.ModelDeltaDecoration] = new_ranges.map(r => {
    range: r,
    options: ModelDecorationOptions("", description="empty"),
  })
  self.hidden_areas_decoration_ids = self.model.delta_decorations(
    self.hidden_areas_decoration_ids,
    new_decorations,
  )
  let hidden_areas = new_ranges
  let mut hidden_area_start = 1
  let mut hidden_area_end = 0
  let mut hidden_area_idx = -1
  let mut next_line_number_to_update_hidden_area = if hidden_area_idx + 1 <
    hidden_areas.length() {
    hidden_area_end + 1
  } else {
    self.model_line_projections.length() + 2
  }
  let mut has_visible_line = false
  for i, projection in self.model_line_projections {
    let line_number = i + 1
    if line_number == next_line_number_to_update_hidden_area {
      hidden_area_idx += 1
      hidden_area_start = hidden_areas[hidden_area_idx].start_line_number
      hidden_area_end = hidden_areas[hidden_area_idx].end_line_number
      next_line_number_to_update_hidden_area = if hidden_area_idx + 1 <
        hidden_areas.length() {
        hidden_area_end + 1
      } else {
        self.model_line_projections.length() + 2
      }
    }
    if line_number >= hidden_area_start && line_number <= hidden_area_end {
      // Line should be hidden
      if projection.is_visible() {
        self.model_line_projections[i] = projection.set_visible(false)
      }
    } else {
      has_visible_line = true
      // Line should be visible
      if !projection.is_visible() {
        self.model_line_projections[i] = projection.set_visible(true)
      }
    }
  }
  self.rebuild_prefix_sums()
  if !has_visible_line {
    // Cannot have everything be hidden => reveal everything!
    self.set_hidden_areas([]) |> ignore
  }
  true
}

///|
/// Whether a one-based model line is visible (not folded away) —
/// `modelPositionIsVisible` (`viewModelLines.ts:250`).
pub fn ViewModelLinesFromProjectedModel::model_position_is_visible(
  self : ViewModelLinesFromProjectedModel,
  model_line_number : Int,
) -> Bool {
  if model_line_number < 1 ||
    model_line_number > self.model_line_projections.length() {
    // invalid arguments
    return false
  }
  self.model_line_projections[model_line_number - 1].is_visible()
}

///|
/// Sorts and merges touching/overlapping line ranges into whole-line ranges
/// — `normalizeLineRanges` (`viewModelLines.ts:1024`).
fn normalize_line_ranges(
  ranges : ArrayView[@base_common.Range],
) -> Array[@base_common.Range] {
  if ranges.length() == 0 {
    return []
  }
  let sorted_ranges = ranges.to_owned()
  sorted_ranges.sort_by((a, b) => {
    @base_common.Range::compare_ranges_using_starts(a, b)
  })
  let result : Array[@base_common.Range] = []
  let (current_range_start, current_range_end) = for
    range in sorted_ranges[1:]
    current_range_start = sorted_ranges[0].start_line_number,
    current_range_end = sorted_ranges[0].end_line_number {
    if range.start_line_number > current_range_end + 1 {
      result.push(Range(current_range_start, 1, current_range_end, 1))
      continue range.start_line_number, range.end_line_number
    } else if range.end_line_number > current_range_end {
      continue current_range_start, range.end_line_number
    }
  } nobreak {
    (current_range_start, current_range_end)
  }
  result.push(Range(current_range_start, 1, current_range_end, 1))
  result
}

///|
/// Applies changed wrapping settings in place — `setWrappingSettings`
/// (`viewModelLines.ts:277`, which equally takes the `fontInfo` whose
/// full-width/half-width ratio feeds the break widths). Returns whether the
/// view-line mapping changed.
pub fn ViewModelLinesFromProjectedModel::set_wrapping_settings(
  self : ViewModelLinesFromProjectedModel,
  font_info : @config.FontInfo,
  wrapping_column : Int,
  wrapping_indent : @editor_api.WrappingIndent,
) -> Bool {
  if self.font_info == font_info &&
    self.wrapping_column == wrapping_column &&
    self.wrapping_indent == wrapping_indent {
    return false
  }
  self.font_info = font_info
  self.wrapping_column = wrapping_column
  self.wrapping_indent = wrapping_indent
  self.construct_lines(reset_hidden_areas=false)
  true
}

///|
/// Applies a changed tab size in place — `setTabSize`
/// (`viewModelLines.ts:266`). Returns whether the view-line mapping changed.
pub fn ViewModelLinesFromProjectedModel::set_tab_size(
  self : ViewModelLinesFromProjectedModel,
  new_tab_size : Int,
) -> Bool {
  if self.tab_size == new_tab_size {
    return false
  }
  self.tab_size = new_tab_size
  self.construct_lines(reset_hidden_areas=false)
  true
}

///|
/// Reprojects after the document was replaced — `onModelFlushed`
/// (`viewModelLines.ts:325`): `constructLines(resetHiddenAreas=true)`. A
/// flush replaces the document, so hidden (folded) areas reset; the stale
/// `hidden_areas_decoration_ids` left by the model-side decoration wipe
/// delta-remove as a no-op (`delta_decorations` skips unknown ids), exactly
/// the source's tolerance.
pub fn ViewModelLinesFromProjectedModel::on_model_flushed(
  self : ViewModelLinesFromProjectedModel,
) -> Unit {
  self.construct_lines(reset_hidden_areas=true)
}

///|
/// Reprojects after an injected-text delta. Deviation: Monaco routes
/// injected-text changes through per-line `onModelLineChanged` events
/// (`viewModelLines.ts:352`), which keep hidden areas; the viewer's
/// granularity is the whole-document reproject, so this is the per-line
/// path's whole-document stand-in — hidden areas survive, unlike
/// `on_model_flushed`.
pub fn ViewModelLinesFromProjectedModel::on_injected_text_changed(
  self : ViewModelLinesFromProjectedModel,
) -> Unit {
  self.construct_lines(reset_hidden_areas=false)
}

///|
/// Total number of view lines — `getViewLineCount`.
pub fn ViewModelLinesFromProjectedModel::get_view_line_count(
  self : ViewModelLinesFromProjectedModel,
) -> Int {
  let prefix_sums = self.projected_model_line_line_counts
  prefix_sums[prefix_sums.length() - 1]
}

///|
/// Clamps a view line number into the document — `_toValidViewLineNumber`.
fn ViewModelLinesFromProjectedModel::to_valid_view_line_number(
  self : ViewModelLinesFromProjectedModel,
  view_line_number : Int,
) -> Int {
  view_line_number.clamp(min=1, max=self.get_view_line_count())
}

///|
/// Decomposes a view line into (model line, wrapped-line index) —
/// `getViewLineInfo` (`viewModelLines.ts:478`), the prefix-sum `getIndexOf`
/// as a binary search over the stored sums.
fn ViewModelLinesFromProjectedModel::get_view_line_info(
  self : ViewModelLinesFromProjectedModel,
  view_line_number : Int,
) -> ViewLineInfo {
  let view_index = self.to_valid_view_line_number(view_line_number) - 1
  let prefix_sums = self.projected_model_line_line_counts
  // Greatest model-line index whose first view line is at or before
  // `view_index`.
  let low = for low = 0, high = self.model_line_projections.length() - 1; low <
               high; {
    let mid = (low + high + 1) / 2
    if prefix_sums[mid] <= view_index {
      continue mid, high
    } else {
      continue low, mid - 1
    }
  } nobreak {
    low
  }
  {
    model_line_number: low + 1,
    model_line_wrapped_line_idx: view_index - prefix_sums[low],
  }
}

///|
/// Returns text for a one-based view line — `getViewLineContent`.
pub fn ViewModelLinesFromProjectedModel::get_view_line_content(
  self : ViewModelLinesFromProjectedModel,
  view_line_number : Int,
) -> String {
  let info = self.get_view_line_info(view_line_number)
  self.model_line_projections[info.model_line_number - 1].get_view_line_content(
    self.model,
    info.model_line_number,
    info.model_line_wrapped_line_idx,
  )
}

///|
/// Minimum one-based column for a view line — `getViewLineMinColumn`.
pub fn ViewModelLinesFromProjectedModel::get_view_line_min_column(
  self : ViewModelLinesFromProjectedModel,
  view_line_number : Int,
) -> Int {
  let info = self.get_view_line_info(view_line_number)
  self.model_line_projections[info.model_line_number - 1].get_view_line_min_column(
    info.model_line_wrapped_line_idx,
  )
}

///|
/// Maximum one-based column for a view line — `getViewLineMaxColumn`.
pub fn ViewModelLinesFromProjectedModel::get_view_line_max_column(
  self : ViewModelLinesFromProjectedModel,
  view_line_number : Int,
) -> Int {
  let info = self.get_view_line_info(view_line_number)
  self.model_line_projections[info.model_line_number - 1].get_view_line_max_column(
    self.model,
    info.model_line_number,
    info.model_line_wrapped_line_idx,
  )
}

///|
/// Maps a one-based view line to its one-based model line — the line-number
/// half of Monaco's `getViewLineInfo`, kept as the viewer's shorthand for
/// consumers that only need the line.
pub fn ViewModelLinesFromProjectedModel::model_line_number_of_view_line(
  self : ViewModelLinesFromProjectedModel,
  view_line_number : Int,
) -> Int {
  self.get_view_line_info(view_line_number).model_line_number
}

///|
/// The view-line data of a one-based view line — `getViewLineData`.
pub fn ViewModelLinesFromProjectedModel::get_view_line_data(
  self : ViewModelLinesFromProjectedModel,
  view_line_number : Int,
) -> ViewLineData {
  let info = self.get_view_line_info(view_line_number)
  let base_view_line_number = self.projected_model_line_line_counts[info.model_line_number -
    1] +
    1
  self.model_line_projections[info.model_line_number - 1].get_view_line_data(
    self.model,
    info.model_line_number,
    info.model_line_wrapped_line_idx,
    base_view_line_number,
  )
}

///|
/// Batch view-line data (`viewModelLines.ts:763-795`). The needed mask is
/// indexed from `view_start_line_number`; hidden model lines are skipped and
/// each participating projected model line shares one passive token read.
pub fn ViewModelLinesFromProjectedModel::get_view_lines_data(
  self : ViewModelLinesFromProjectedModel,
  view_start_line_number : Int,
  view_end_line_number : Int,
  needed : Array[Bool],
) -> Array[ViewLineData?] {
  self.batch_call_count += 1
  let view_start_line_number = self.to_valid_view_line_number(
    view_start_line_number,
  )
  let view_end_line_number = self.to_valid_view_line_number(
    view_end_line_number,
  )
  let count = view_end_line_number - view_start_line_number + 1
  if needed.length() != count {
    abort("get_view_lines_data needed mask length mismatch")
  }
  let result : Array[ViewLineData?] = [ for _ in 0..<count => None ]
  let start = self.get_view_line_info(view_start_line_number)
  let start_model_line_index = start.model_line_number - 1
  let mut view_line_number = view_start_line_number
  for
    model_line_index in start_model_line_index..<self.model_line_projections.length() {
    let projection = self.model_line_projections[model_line_index]
    if !projection.is_visible() {
      continue
    }
    let from_view_line_index = if model_line_index == start_model_line_index {
      start.model_line_wrapped_line_idx
    } else {
      0
    }
    let mut remaining_view_line_count = projection.get_view_line_count() -
      from_view_line_index
    let mut last_line = false
    if view_line_number + remaining_view_line_count > view_end_line_number {
      last_line = true
      remaining_view_line_count = view_end_line_number - view_line_number + 1
    }
    let base_view_line_number = self.projected_model_line_line_counts[model_line_index] +
      1
    let read_tokens = projection.get_view_lines_data(
      self.model,
      model_line_index + 1,
      from_view_line_index,
      remaining_view_line_count,
      base_view_line_number,
      view_line_number - view_start_line_number,
      needed,
      result,
    )
    if read_tokens {
      self.passive_token_read_count += 1
    }
    view_line_number += remaining_view_line_count
    if last_line {
      break
    }
  }
  result
}

///|
/// Builds line-renderer input data for a one-based view line — the viewer's
/// bridge to `ViewLineRenderingData` (Monaco builds it in
/// `ViewModel.getViewLineRenderingData`).
pub fn ViewModelLinesFromProjectedModel::view_line_rendering_data(
  self : ViewModelLinesFromProjectedModel,
  view_line_number : Int,
  line_decorations? : Array[@view_layout.LineDecoration] = [],
) -> @view_layout.ViewLineRenderingData {
  view_line_rendering_data_from_view_line_data(
    self.get_view_line_data(view_line_number),
    line_decorations~,
    tab_size=self.tab_size,
  )
}

///|
/// The injected-text source index at a 0-based view column of a
/// view line, or `-1` for source text — the index-valued form of Monaco's
/// `getInjectedTextAt` (`viewModelLines.ts:991`).
pub fn ViewModelLinesFromProjectedModel::injected_text_index_at(
  self : ViewModelLinesFromProjectedModel,
  view_line_number : Int,
  column : Int,
) -> Int {
  let info = self.get_view_line_info(view_line_number)
  self.model_line_projections[info.model_line_number - 1].injected_text_index_at(
    info.model_line_wrapped_line_idx,
    column,
  )
}

///|
/// Snaps a view position at injected-text/wrap boundaries per the affinity —
/// `normalizePosition` (`viewModelLines.ts:996`).
pub fn ViewModelLinesFromProjectedModel::normalize_position(
  self : ViewModelLinesFromProjectedModel,
  position : @base_common.Position,
  affinity : @model.PositionAffinity,
) -> @base_common.Position {
  let info = self.get_view_line_info(position.line_number)
  self.model_line_projections[info.model_line_number - 1].normalize_position(
    info.model_line_wrapped_line_idx,
    position,
    affinity,
  )
}

///|
/// Converts a view position to model coordinates —
/// `convertViewPositionToModelPosition` (`viewModelLines.ts:834`).
pub fn ViewModelLinesFromProjectedModel::convert_view_position_to_model_position(
  self : ViewModelLinesFromProjectedModel,
  view_line_number : Int,
  view_column : Int,
) -> @base_common.Position {
  let info = self.get_view_line_info(view_line_number)
  let input_column = self.model_line_projections[info.model_line_number - 1].get_model_column_of_view_position(
    info.model_line_wrapped_line_idx,
    view_column,
  )
  self.model.validate_position(Position(info.model_line_number, input_column))
}

///|
/// Converts a view range to model coordinates —
/// `convertViewRangeToModelRange` (`viewModelLines.ts:842`).
pub fn ViewModelLinesFromProjectedModel::convert_view_range_to_model_range(
  self : ViewModelLinesFromProjectedModel,
  view_range : @base_common.Range,
) -> @base_common.Range {
  let start = self.convert_view_position_to_model_position(
    view_range.start_line_number,
    view_range.start_column,
  )
  let end = self.convert_view_position_to_model_position(
    view_range.end_line_number,
    view_range.end_column,
  )
  Range(start.line_number, start.column, end.line_number, end.column)
}

///|
/// Converts a model position to view coordinates —
/// `convertModelPositionToViewPosition` (`viewModelLines.ts:848`). A position
/// on a hidden (folded) line walks up to the nearest visible line's end —
/// or, with `below_hidden_ranges`, down to the next visible line's start.
/// The affinity picks the boundary side at injected text and wrap breaks;
/// absent it behaves as Monaco's default `None`.
pub fn ViewModelLinesFromProjectedModel::convert_model_position_to_view_position(
  self : ViewModelLinesFromProjectedModel,
  model_line_number : Int,
  model_column : Int,
  affinity? : @model.PositionAffinity,
  allow_zero_line_number? : Bool = false,
  below_hidden_ranges? : Bool = false,
) -> @base_common.Position {
  let valid_position = self.model.validate_position(
    Position(model_line_number, model_column),
  )
  // `TextModel::set_value` swaps its snapshot before it flushes registered
  // view models. Monaco suppresses the matching token-change notification
  // until `_lines.onModelFlushed()` has rebuilt this array, but the viewer's
  // current whole-document tokenizer can synchronously expose that narrow
  // window. Keep the source validation above, and address only projections
  // that are committed so an early observer cannot index past the old array.
  let input_line_number = valid_position.line_number.clamp(
    min=1,
    max=self.model_line_projections.length(),
  )
  let input_column = valid_position.column
  let original_line_index = input_line_number - 1
  let line_index = if below_hidden_ranges {
    for line_index = original_line_index; line_index <
       self.model_line_projections.length() &&
       !self.model_line_projections[line_index].is_visible(); {
      continue line_index + 1
    } nobreak {
      line_index
    }
  } else {
    for line_index = original_line_index; line_index > 0 &&
       !self.model_line_projections[line_index].is_visible(); {
      continue line_index - 1
    } nobreak {
      line_index
    }
  }
  let line_index_changed = line_index != original_line_index
  if line_index == 0 && !self.model_line_projections[line_index].is_visible() {
    // Could not reach a real line
    return Position(if allow_zero_line_number { 0 } else { 1 }, 1)
  }
  let delta_line_number = 1 + self.projected_model_line_line_counts[line_index]
  if line_index_changed {
    if below_hidden_ranges {
      self.model_line_projections[line_index].get_view_position_of_model_position(
        delta_line_number,
        1,
        affinity?,
      )
    } else {
      self.model_line_projections[line_index].get_view_position_of_model_position(
        delta_line_number,
        self.model.snapshot.get_line_max_column(line_index + 1),
        affinity?,
      )
    }
  } else {
    self.model_line_projections[input_line_number - 1].get_view_position_of_model_position(
      delta_line_number,
      input_column,
      affinity?,
    )
  }
}

///|
/// Converts a model range to view coordinates —
/// `convertModelRangeToViewRange` (`viewModelLines.ts:892-901`): the default
/// affinity is `Left` and only applies to empty ranges; a non-empty range
/// excludes injected text at its edges (start `Right`, end `Left`).
pub fn ViewModelLinesFromProjectedModel::convert_model_range_to_view_range(
  self : ViewModelLinesFromProjectedModel,
  model_range : @base_common.Range,
  affinity? : @model.PositionAffinity,
) -> @base_common.Range {
  if model_range.is_empty() {
    let affinity = affinity.unwrap_or(Left)
    let start = self.convert_model_position_to_view_position(
      model_range.start_line_number,
      model_range.start_column,
      affinity~,
    )
    Range(start.line_number, start.column, start.line_number, start.column)
  } else {
    let start = self.convert_model_position_to_view_position(
      model_range.start_line_number,
      model_range.start_column,
      affinity=Right,
    )
    let end = self.convert_model_position_to_view_position(
      model_range.end_line_number,
      model_range.end_column,
      affinity=Left,
    )
    Range(start.line_number, start.column, end.line_number, end.column)
  }
}

///|
/// Derives per-model-line injected text from the backing model's
/// injected-text decorations — `LineInjectedText.fromDecorations`
/// (`textModelEvents.ts`): `before` lands at the range start (order 0),
/// `after` at the range end (order 1); sorted by line, column, order.
/// Positions convert to the 0-based line/column space
/// `ProjectedTextLine::from_injected_text` consumes.
fn line_injected_text_from_decorations(
  model : @model.TextModel,
) -> Array[Array[InjectedText]] {
  let snapshot = model.snapshot
  let buckets : Array[Array[InjectedText]] = []
  for _ in 0..<snapshot.line_count() {
    buckets.push([])
  }
  let entries : Array[(Int, Int, Int, @model.InjectedTextOptions)] = []
  for decoration in model.get_injected_text_decorations() {
    if decoration.options.before is Some(before) &&
      before.content().length() > 0 {
      entries.push(
        (
          decoration.range.start_line_number,
          decoration.range.start_column,
          0,
          before,
        ),
      )
    }
    if decoration.options.after is Some(after) && after.content().length() > 0 {
      entries.push(
        (
          decoration.range.end_line_number,
          decoration.range.end_column,
          1,
          after,
        ),
      )
    }
  }
  entries.sort_by((left, right) => {
    let (l_line, l_column, l_order, _) = left
    let (r_line, r_column, r_order, _) = right
    if l_line != r_line {
      l_line - r_line
    } else if l_column != r_column {
      l_column - r_column
    } else {
      l_order - r_order
    }
  })
  for entry in entries {
    let (line_number, column, _, options) = entry
    let line = (line_number - 1).clamp(min=0, max=snapshot.line_count() - 1)
    let line_text = snapshot.line_text(line)
    let column0 = (column - 1).clamp(min=0, max=line_text.length())
    buckets[line].push(
      InjectedText(
        Position(line, column0),
        options.content(),
        options.inline_class_name().unwrap_or(""),
        source_index=options.attached_index(),
      ),
    )
  }
  buckets
}

///|
/// The injected texts of one 1-based model line — the single-line form of
/// `line_injected_text_from_decorations` (same derivation, same clamping,
/// filtered to the line and sorted by column then before/after order).
fn injected_text_for_model_line(
  model : @model.TextModel,
  model_line_number : Int,
) -> Array[InjectedText] {
  let snapshot = model.snapshot
  if snapshot.line_count() == 0 {
    return []
  }
  let target_line0 = (model_line_number - 1).clamp(
    min=0,
    max=snapshot.line_count() - 1,
  )
  let entries : Array[(Int, Int, @model.InjectedTextOptions)] = []
  for decoration in model.get_injected_text_decorations() {
    if decoration.options.before is Some(before) &&
      before.content().length() > 0 &&
      (decoration.range.start_line_number - 1).clamp(
        min=0,
        max=snapshot.line_count() - 1,
      ) ==
      target_line0 {
      entries.push((decoration.range.start_column, 0, before))
    }
    if decoration.options.after is Some(after) &&
      after.content().length() > 0 &&
      (decoration.range.end_line_number - 1).clamp(
        min=0,
        max=snapshot.line_count() - 1,
      ) ==
      target_line0 {
      entries.push((decoration.range.end_column, 1, after))
    }
  }
  entries.sort_by((left, right) => {
    let (l_column, l_order, _) = left
    let (r_column, r_order, _) = right
    if l_column != r_column {
      l_column - r_column
    } else {
      l_order - r_order
    }
  })
  let line_text = snapshot.line_text(target_line0)
  let out : Array[InjectedText] = []
  for entry in entries {
    let (column, _, options) = entry
    let column0 = (column - 1).clamp(min=0, max=line_text.length())
    out.push(
      InjectedText(
        Position(target_line0, column0),
        options.content(),
        options.inline_class_name().unwrap_or(""),
        source_index=options.attached_index(),
      ),
    )
  }
  out
}
