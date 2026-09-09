// The hidden-areas half of Monaco's `ViewModel`
// (`vs/editor/common/viewModel/viewModelImpl.ts`): `setHiddenAreas` with its
// per-source `HiddenAreasModel` merge and the `StableViewport`
// capture/recover pair that keeps the top of the viewport pinned while lines
// above it fold away. The folding contrib is the producer; the projected
// line collection (`view_model_lines_projected.mbt`) stores the result.

///|
/// Merges hidden-area sets contributed by independent sources — Monaco's
/// `HiddenAreasModel` (`viewModelImpl.ts:1383`). Each source (the folding
/// controller, a diff feature, ...) owns its own range list; the view model
/// consumes the union. Monaco keys sources by object identity (`unknown`);
/// the viewer keys by a caller-chosen string.
priv struct HiddenAreasModel {
  hidden_areas : Map[String, Array[@base_common.Range]]
  mut should_recompute : Bool
  mut ranges : Array[@base_common.Range]
}

///|
fn HiddenAreasModel::HiddenAreasModel() -> HiddenAreasModel {
  { hidden_areas: Map([]), should_recompute: false, ranges: [], }
}

///|
/// Replaces one source's ranges — `HiddenAreasModel.setHiddenAreas`.
fn HiddenAreasModel::set_hidden_areas(
  self : HiddenAreasModel,
  source : String,
  ranges : Array[@base_common.Range],
) -> Unit {
  if self.hidden_areas.get(source) is Some(existing) && existing == ranges {
    return
  }
  self.hidden_areas[source] = ranges
  self.should_recompute = true
}

///|
/// Tests raw per-source membership while omitting one owner. Unlike
/// `get_merged_ranges`, this read neither consumes `should_recompute` nor
/// rebuilds/replaces the cached merged union.
fn HiddenAreasModel::position_is_hidden_except_source(
  self : HiddenAreasModel,
  position : @base_common.Position,
  ignored_source : String,
) -> Bool {
  for source, ranges in self.hidden_areas {
    if source == ignored_source {
      continue
    }
    for range in ranges {
      if range.start_line_number <= position.line_number &&
        position.line_number <= range.end_line_number {
        return true
      }
    }
  }
  false
}

///|
/// The union of every source's ranges, merged into disjoint line ranges —
/// `HiddenAreasModel.getMergedRanges`. Returns the previous array when the
/// merge result is unchanged so the caller's equality check short-circuits.
fn HiddenAreasModel::get_merged_ranges(
  self : HiddenAreasModel,
) -> Array[@base_common.Range] {
  if !self.should_recompute {
    return self.ranges
  }
  self.should_recompute = false
  let new_ranges = for
    _, hidden_areas in self.hidden_areas
    new_ranges = ([] : Array[@base_common.Range]) {
    continue merge_line_range_array(new_ranges, hidden_areas)
  } nobreak {
    new_ranges
  }
  if self.ranges == new_ranges {
    return self.ranges
  }
  self.ranges = new_ranges
  self.ranges
}

///|
/// Merges two sorted disjoint line-range arrays, unioning ranges that touch
/// or overlap — `mergeLineRangeArray` (`viewModelImpl.ts:1414`).
fn merge_line_range_array(
  arr1 : Array[@base_common.Range],
  arr2 : Array[@base_common.Range],
) -> Array[@base_common.Range] {
  let result : Array[@base_common.Range] = []
  let mut i = 0
  let mut j = 0
  while i < arr1.length() && j < arr2.length() {
    let item1 = arr1[i]
    let item2 = arr2[j]
    if item1.end_line_number < item2.start_line_number - 1 {
      result.push(item1)
      i += 1
    } else if item2.end_line_number < item1.start_line_number - 1 {
      result.push(item2)
      j += 1
    } else {
      let start_line_number = item1.start_line_number.min(
        item2.start_line_number,
      )
      let end_line_number = item1.end_line_number.max(item2.end_line_number)
      result.push(Range(start_line_number, 1, end_line_number, 1))
      i += 1
      j += 1
    }
  }
  while i < arr1.length() {
    result.push(arr1[i])
    i += 1
  }
  while j < arr2.length() {
    result.push(arr2[j])
    j += 1
  }
  result
}

///|
/// Whether a validated ViewZone anchor is hidden by any source other than the
/// named owner. This is intentionally narrower than the merged coordinate
/// converter: it reads the raw source lists without mutating their cached
/// union or the projected line collection.
pub fn ViewModel::model_position_is_hidden_except_source(
  self : ViewModel,
  position : @base_common.Position,
  ignored_source : String,
) -> Bool {
  self.hidden_areas_model.position_is_hidden_except_source(
    position, ignored_source,
  )
}

///|
/// The viewport anchor captured before a hidden-area change — Monaco's
/// `StableViewport` (`viewModelImpl.ts:1458`): the model position of the
/// first view line on screen plus the scroll offset into it.
priv struct StableViewport {
  viewport_start_model_position : @base_common.Position?
  start_line_delta : Double
}

///|
/// Re-scrolls so the captured model line is back at the top of the viewport
/// — `StableViewport.recoverViewportStart`.
fn StableViewport::recover_viewport_start(
  self : StableViewport,
  lines : ViewModelLinesFromProjectedModel,
  view_layout : @view_layout.ViewLayout,
) -> Unit {
  guard self.viewport_start_model_position is Some(position) else { return }
  let view_position = lines.convert_model_position_to_view_position(
    position.line_number,
    position.column,
  )
  let view_position_top = view_layout.get_vertical_offset_for_line_number(
    view_position.line_number,
  )
  view_layout.scroll_to(scroll_top=view_position_top + self.start_line_delta)
  |> ignore
}

///|
/// Captures the viewport anchor — `ViewModel._captureStableViewport`
/// (`viewModelImpl.ts:263`), "but only if the scroll position is not at the
/// top of the file". Monaco reads its continuously tracked `ViewportStart`;
/// the viewer derives the same anchor (view line at the current scroll top,
/// pixel delta into it) from the layout on demand.
fn ViewModel::capture_stable_viewport(self : ViewModel) -> StableViewport {
  let scroll_top = self.view_layout.get_current_scroll_top()
  if scroll_top > 0 && self.line_count() > 0 {
    let view_line_number = self.view_layout.line_at_vertical_offset(scroll_top)
    let previous_viewport_start_view_position : @base_common.Position = Position(
      view_line_number,
      self.get_line_min_column(view_line_number),
    )
    let previous_viewport_start_model_position = self.lines.convert_view_position_to_model_position(
      previous_viewport_start_view_position.line_number,
      previous_viewport_start_view_position.column,
    )
    let start_line_delta = scroll_top -
      self.view_layout.get_vertical_offset_for_line_number(view_line_number)
    return {
      viewport_start_model_position: Some(
        previous_viewport_start_model_position,
      ),
      start_line_delta,
    }
  }
  { viewport_start_model_position: None, start_line_delta: 0, }
}

///|
/// Applies one source's hidden-area set — `ViewModel.setHiddenAreas`
/// (`viewModelImpl.ts:592`). Merges all sources, short-circuits when the
/// union is unchanged (unless `force_update`), pushes the result into the
/// line collection, and re-points everything hanging off the view-line axis:
/// the cursor (`_cursor.onLineMappingChanged`), the decoration caches
/// (`_decorations.onLineMappingChanged`), and the layout's line count
/// (`viewLayout.onFlushed` + `onHeightMaybeChanged`). The viewport stays
/// pinned to its first visible model line unless that line itself was
/// hidden. Returns whether the view-line mapping changed — Monaco's
/// `ViewFlushedEvent`/`ViewLineMappingChangedEvent`/`HiddenAreasChangedEvent`
/// emissions, which the frame-based caller turns into a re-render.
///
/// ```mermaid
/// flowchart LR
///   A[Replace one<br>source range set] --> B[Merge every source]
///   B --> C{Union changed<br>or forced?}
///   C -->|no| D[Return false]
///   C -->|yes| E[Capture top anchor,<br>apply projected ranges]
///   E --> F{Line mapping<br>changed?}
///   F -->|yes| G[Re-point cursor,<br>decorations, layout]
///   F -->|no| H[Keep mapping]
///   G --> I[Restore visible<br>viewport anchor]
///   H --> I
///   I --> J[Emit changed-only<br>outgoing event]
/// ```
pub fn ViewModel::set_hidden_areas(
  self : ViewModel,
  ranges : Array[@base_common.Range],
  source? : String = "",
  force_update? : Bool = false,
  with_event_batch? : (() -> Bool) -> Bool,
  on_line_mapping_changed? : (() -> Unit) -> Unit,
) -> Bool {
  self.hidden_areas_model.set_hidden_areas(source, ranges)
  let merged_ranges = self.hidden_areas_model.get_merged_ranges()
  if merged_ranges == self.previous_hidden_areas && !force_update {
    return false
  }
  self.previous_hidden_areas = merged_ranges.copy()
  let stable_viewport = self.capture_stable_viewport()
  let apply_hidden_areas = () => {
    let line_mapping_changed = self.lines.set_hidden_areas(merged_ranges)
    if line_mapping_changed {
      // Browser ViewEvents live above this common package. Hand the owner one
      // exact source phase around cursor reprojection: Flushed/Mapping/
      // Decorations are appended before `reproject_cursor`, and the cursor
      // event immediately after it. Headless callers take the default direct
      // continuation. Layout flush and stable-viewport recovery intentionally
      // remain below the phase so their synchronous Scroll event is appended
      // later in the same outer collector.
      let reproject_cursor = () => {
        self.cursor.set_context(self.coordinates_converter.cursor_context())
      }
      match on_line_mapping_changed {
        Some(callback) => callback(reproject_cursor)
        None => reproject_cursor()
      }
      self.decorations.on_line_mapping_changed()
      self.view_layout.on_flushed(self.line_count())
      self.view_layout.on_height_maybe_changed() |> ignore
    }
    let first_model_line_is_hidden = match
      stable_viewport.viewport_start_model_position {
      Some(position) =>
        merged_ranges.any(range => {
          range.start_line_number <= position.line_number &&
          position.line_number <= range.end_line_number
        })
      None => false
    }
    if !first_model_line_is_hidden {
      stable_viewport.recover_viewport_start(self.lines, self.view_layout)
    }
    line_mapping_changed
  }
  let line_mapping_changed = match with_event_batch {
    Some(run) => run(apply_hidden_areas)
    None => apply_hidden_areas()
  }
  // Monaco publishes the outgoing fact only after the generic ViewEvent batch
  // has ended. For the root Viewer, returning from `run` also completes its
  // deferred collector flush, including layout and stable-viewport Scroll.
  if line_mapping_changed {
    self.cursor_event_dispatcher.emit_hidden_areas_changed(
      HiddenAreasChangedOutgoingEvent(),
    )
  }
  line_mapping_changed
}
