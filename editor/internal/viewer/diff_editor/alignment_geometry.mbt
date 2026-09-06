// Pure pixel geometry for diff-pane alignment. The pane producer captures
// actual model-line heights and foreign zone heights after excluding all
// managed alignment zones. This engine only compares immutable numeric axes.

///|
/// An exact rendered height override for one model line. Wrapped lines use a
/// height greater than `line_height`; hidden lines are represented separately
/// and always resolve to zero height.
pub(all) struct PaneModelLineHeight {
  line_number : Int
  height_in_px : Double
} derive(Eq, Debug)

///|
/// Extra geometry after a model line. `after_line_number == 0` represents top
/// padding before line 1. The snapshot producer must omit zones owned by the
/// current alignment transaction.
pub(all) struct PaneForeignZoneHeight {
  after_line_number : Int
  height_in_px : Double
} derive(Eq, Debug)

///|
/// Immutable geometry for one pane and one render generation. The cumulative
/// axis stores pixels after each model-line boundary, including foreign zones.
pub struct PaneGeometrySnapshot {
  line_height : Double
  viewport_width : Double
  line_heights : Array[Double]
  line_max_columns : Array[Int]?
  foreign_zone_heights : Array[PaneForeignZoneHeight]
  cumulative_pixels : Array[Double]
}

///|
fn normalized_foreign_zone_heights(
  line_count : Int,
  zones : Array[PaneForeignZoneHeight],
) -> Array[PaneForeignZoneHeight] {
  let heights = Array::make(line_count + 1, 0.0)
  for zone in zones {
    if zone.after_line_number >= 0 &&
      zone.after_line_number <= line_count &&
      zone.height_in_px > 0.0 {
      heights[zone.after_line_number] += zone.height_in_px
    }
  }
  let result : Array[PaneForeignZoneHeight] = []
  for boundary in 0..<=line_count {
    if heights[boundary] > 0.0 {
      result.push({
        after_line_number: boundary,
        height_in_px: heights[boundary],
      })
    }
  }
  result
}

///|
/// Builds a pane axis. `model_line_heights` are exact heights, not deltas;
/// `hidden_lines` are applied last so a hidden wrapped line still contributes
/// zero pixels. `line_max_columns` is optional and only enables the secondary
/// synchronization point after a character-level change.
pub fn PaneGeometrySnapshot::PaneGeometrySnapshot(
  line_count : Int,
  line_height : Double,
  model_line_heights? : Array[PaneModelLineHeight] = [],
  hidden_lines? : Array[@base_common.LineRange] = [],
  foreign_zone_heights? : Array[PaneForeignZoneHeight] = [],
  line_max_columns? : Array[Int],
  viewport_width? : Double = 0.0,
) -> PaneGeometrySnapshot {
  let line_count = line_count.max(0)
  let line_height = line_height.max(0.0)
  let line_heights = Array::make(line_count, line_height)
  for item in model_line_heights {
    if item.line_number >= 1 && item.line_number <= line_count {
      line_heights[item.line_number - 1] = item.height_in_px.max(0.0)
    }
  }
  for hidden in hidden_lines {
    let start = hidden.start_line_number.max(1)
    let end_exclusive = hidden.end_line_number_exclusive.min(line_count + 1)
    for line_number in start..<end_exclusive {
      line_heights[line_number - 1] = 0.0
    }
  }
  let foreign_zone_heights = normalized_foreign_zone_heights(
    line_count, foreign_zone_heights,
  )
  let zone_heights = Array::make(line_count + 1, 0.0)
  for zone in foreign_zone_heights {
    zone_heights[zone.after_line_number] = zone.height_in_px
  }
  let cumulative_pixels = Array::make(line_count + 1, 0.0)
  cumulative_pixels[0] = zone_heights[0]
  for line_number in 1..<=line_count {
    cumulative_pixels[line_number] = cumulative_pixels[line_number - 1] +
      line_heights[line_number - 1] +
      zone_heights[line_number]
  }
  {
    line_height,
    viewport_width: viewport_width.max(0.0),
    line_heights,
    line_max_columns: line_max_columns.map(columns => columns.copy()),
    foreign_zone_heights,
    cumulative_pixels,
  }
}

///|
pub fn PaneGeometrySnapshot::viewport_width(
  self : PaneGeometrySnapshot,
) -> Double {
  self.viewport_width
}

///|
pub fn PaneGeometrySnapshot::line_height(self : PaneGeometrySnapshot) -> Double {
  self.line_height
}

///|
pub fn PaneGeometrySnapshot::line_count(self : PaneGeometrySnapshot) -> Int {
  self.line_heights.length()
}

///|
pub fn PaneGeometrySnapshot::content_height(
  self : PaneGeometrySnapshot,
) -> Double {
  self.cumulative_pixels[self.cumulative_pixels.length() - 1]
}

///|
pub fn PaneGeometrySnapshot::foreign_zone_heights(
  self : PaneGeometrySnapshot,
) -> Array[PaneForeignZoneHeight] {
  self.foreign_zone_heights.copy()
}

///|
fn PaneGeometrySnapshot::max_column(
  self : PaneGeometrySnapshot,
  line_number : Int,
) -> Int? {
  guard self.line_max_columns is Some(columns) else { return None }
  if line_number < 1 || line_number > columns.length() {
    None
  } else {
    Some(columns[line_number - 1])
  }
}

///|
/// A zone specification applied by the owning widget. A zero anchor places a
/// spacer before line 1, matching the editor's managed-zone coordinate system.
pub(all) struct ManagedAlignmentSpacer {
  after_line_number : Int
  height_in_px : Double
} derive(Eq, Debug)

///|
pub struct ManagedAlignmentSpacers {
  original : Array[ManagedAlignmentSpacer]
  modified : Array[ManagedAlignmentSpacer]
}

///|
pub fn ManagedAlignmentSpacers::original(
  self : ManagedAlignmentSpacers,
) -> Array[ManagedAlignmentSpacer] {
  self.original.copy()
}

///|
pub fn ManagedAlignmentSpacers::modified(
  self : ManagedAlignmentSpacers,
) -> Array[ManagedAlignmentSpacer] {
  self.modified.copy()
}

///|
fn append_managed_spacer(
  target : Array[ManagedAlignmentSpacer],
  after_line_number : Int,
  height_in_px : Double,
) -> Unit {
  if height_in_px <= 0.01 {
    return
  }
  if !target.is_empty() &&
    target[target.length() - 1].after_line_number == after_line_number {
    let previous = target[target.length() - 1]
    target[target.length() - 1] = {
      after_line_number,
      height_in_px: previous.height_in_px + height_in_px,
    }
  } else {
    target.push({ after_line_number, height_in_px, })
  }
}

///|
priv struct AdditionalLineHeight {
  line_number : Int
  height_in_px : Double
}

///|
fn compare_additional_line_height(
  left : AdditionalLineHeight,
  right : AdditionalLineHeight,
) -> Int {
  left.line_number - right.line_number
}

///|
// Exact counterpart of VS Code's getAdditionalLineHeights for wrapping and
// non-owned ViewZones, extended for an atomic hidden-source projection such as
// a rich Markdown comment. Consecutive zero-height source lines become one
// negative delta at the run's final model boundary. Its replacement ViewZone
// is anchored at that same boundary, so the pair contributes exactly
// `replacementHeight - hiddenSourceHeight` and never one blank spacer per
// hidden line.
fn additional_line_heights(
  geometry : PaneGeometrySnapshot,
) -> Array[AdditionalLineHeight] {
  let raw : Array[AdditionalLineHeight] = []
  let mut hidden_source_height = 0.0
  let mut hidden_source_end_line = 0
  for index, height in geometry.line_heights {
    let line_number = index + 1
    if height <= 0.01 && geometry.line_height > 0.01 {
      hidden_source_height += geometry.line_height
      hidden_source_end_line = line_number
      continue
    }
    if hidden_source_height > 0.01 {
      raw.push({
        line_number: hidden_source_end_line,
        height_in_px: -hidden_source_height,
      })
      hidden_source_height = 0.0
      hidden_source_end_line = 0
    }
    let delta = height - geometry.line_height
    if delta.abs() > 0.01 {
      raw.push({ line_number, height_in_px: delta, })
    }
  }
  if hidden_source_height > 0.01 {
    raw.push({
      line_number: hidden_source_end_line,
      height_in_px: -hidden_source_height,
    })
  }
  for zone in geometry.foreign_zone_heights {
    if zone.height_in_px > 0.01 {
      raw.push({
        line_number: zone.after_line_number,
        height_in_px: zone.height_in_px,
      })
    }
  }
  raw.sort_by(compare_additional_line_height)
  let result : Array[AdditionalLineHeight] = []
  for item in raw {
    if !result.is_empty() &&
      result[result.length() - 1].line_number == item.line_number {
      let previous = result[result.length() - 1]
      result[result.length() - 1] = {
        line_number: previous.line_number,
        height_in_px: previous.height_in_px + item.height_in_px,
      }
    } else {
      result.push(item)
    }
  }
  result
}

///|
priv struct LineRangeAlignment {
  original_range : @base_common.LineRange
  modified_range : @base_common.LineRange
  original_height_in_px : Double
  modified_height_in_px : Double
  /// The canonical diff that produced this alignment. Geometry-only
  /// alignments (wrapping, foreign ViewZones, and additional alignments) keep
  /// this empty so Inline projection never mistakes them for deleted code.
  diff : @diff.DetailedLineRangeMapping?
}

///|
// Direct port of VS Code's computeRangeAlignment. The only addition is that
// DiffState::alignments also yields geometry-only `additional_alignments` with
// `diff=None`; the algorithm itself is otherwise shared.
fn compute_range_alignments(
  diff_state : DiffState,
  original_geometry : PaneGeometrySnapshot,
  modified_geometry : PaneGeometrySnapshot,
  inner_hunk_alignment? : Bool = true,
) -> Array[LineRangeAlignment] {
  let original_overrides = additional_line_heights(original_geometry)
  let modified_overrides = additional_line_heights(modified_geometry)
  let mut original_override_index = 0
  let mut modified_override_index = 0
  let mut last_original_line_number = 0
  let mut last_modified_line_number = 0
  let result : Array[LineRangeAlignment] = []

  let handle_alignments_outside_diffs = fn(
    until_original_line_number_exclusive : Int,
    until_modified_line_number_exclusive : Int,
  ) {
    while true {
      let original_next = if original_override_index <
        original_overrides.length() &&
        original_overrides[original_override_index].line_number <
        until_original_line_number_exclusive {
        Some(original_overrides[original_override_index])
      } else {
        None
      }
      let modified_next = if modified_override_index <
        modified_overrides.length() &&
        modified_overrides[modified_override_index].line_number <
        until_modified_line_number_exclusive {
        Some(modified_overrides[modified_override_index])
      } else {
        None
      }
      if original_next is None && modified_next is None {
        break
      }
      let original_distance = match original_next {
        Some(item) => item.line_number - last_original_line_number
        None => 2147483647
      }
      let modified_distance = match modified_next {
        Some(item) => item.line_number - last_modified_line_number
        None => 2147483647
      }
      let (original_item, modified_item) = if original_distance <
        modified_distance {
        guard original_next is Some(original_item) else { break }
        original_override_index += 1
        (
          original_item,
          (
            {
              line_number: last_modified_line_number + original_distance,
              height_in_px: 0.0,
            } : AdditionalLineHeight),
        )
      } else if original_distance > modified_distance {
        guard modified_next is Some(modified_item) else { break }
        modified_override_index += 1
        (
          (
            {
              line_number: last_original_line_number + modified_distance,
              height_in_px: 0.0,
            } : AdditionalLineHeight),
          modified_item,
        )
      } else {
        guard (original_next, modified_next)
          is (Some(original_item), Some(modified_item)) else {
          break
        }
        original_override_index += 1
        modified_override_index += 1
        (original_item, modified_item)
      }
      result.push({
        original_range: LineRange(
          original_item.line_number,
          original_item.line_number + 1,
        ),
        modified_range: LineRange(
          modified_item.line_number,
          modified_item.line_number + 1,
        ),
        original_height_in_px: original_geometry.line_height +
        original_item.height_in_px,
        modified_height_in_px: modified_geometry.line_height +
        modified_item.height_in_px,
        diff: None,
      })
    }
  }

  for alignment in diff_state.alignments() {
    let mapping = alignment.line_range_mapping
    handle_alignments_outside_diffs(
      mapping.original.start_line_number,
      mapping.modified.start_line_number,
    )
    let mut first = true
    let mut last_original_in_hunk = mapping.original.start_line_number
    let mut last_modified_in_hunk = mapping.modified.start_line_number
    let emit_alignment = fn(
      original_line_number_exclusive : Int,
      modified_line_number_exclusive : Int,
      force_alignment : Bool,
    ) {
      if original_line_number_exclusive < last_original_in_hunk ||
        modified_line_number_exclusive < last_modified_in_hunk {
        return
      }
      if first {
        first = false
      } else if !force_alignment &&
        (
          original_line_number_exclusive == last_original_in_hunk ||
          modified_line_number_exclusive == last_modified_in_hunk
        ) {
        return
      }
      let original_range = @base_common.LineRange(
        last_original_in_hunk, original_line_number_exclusive,
      )
      let modified_range = @base_common.LineRange(
        last_modified_in_hunk, modified_line_number_exclusive,
      )
      if original_range.is_empty() && modified_range.is_empty() {
        return
      }
      let mut original_additional_height = 0.0
      while original_override_index < original_overrides.length() &&
            original_overrides[original_override_index].line_number <
            original_line_number_exclusive {
        original_additional_height += original_overrides[original_override_index].height_in_px
        original_override_index += 1
      }
      let mut modified_additional_height = 0.0
      while modified_override_index < modified_overrides.length() &&
            modified_overrides[modified_override_index].line_number <
            modified_line_number_exclusive {
        modified_additional_height += modified_overrides[modified_override_index].height_in_px
        modified_override_index += 1
      }
      result.push({
        original_range,
        modified_range,
        original_height_in_px: original_range.length().to_double() *
        original_geometry.line_height +
        original_additional_height,
        modified_height_in_px: modified_range.length().to_double() *
        modified_geometry.line_height +
        modified_additional_height,
        diff: alignment.diff,
      })
      last_original_in_hunk = original_line_number_exclusive
      last_modified_in_hunk = modified_line_number_exclusive
    }
    if inner_hunk_alignment &&
      alignment.diff is Some(change) &&
      change.inner_changes is Some(inner_changes) {
      for inner in inner_changes {
        if inner.original.start_column > 1 && inner.modified.start_column > 1 {
          emit_alignment(
            inner.original.start_line_number,
            inner.modified.start_line_number,
            false,
          )
        }
        if original_geometry.max_column(inner.original.end_line_number)
          is Some(max_column) &&
          inner.original.end_column < max_column {
          emit_alignment(
            inner.original.end_line_number,
            inner.modified.end_line_number,
            false,
          )
        }
      }
    }
    emit_alignment(
      mapping.original.end_line_number_exclusive,
      mapping.modified.end_line_number_exclusive,
      true,
    )
    last_original_line_number = mapping.original.end_line_number_exclusive
    last_modified_line_number = mapping.modified.end_line_number_exclusive
  }
  handle_alignments_outside_diffs(2147483647, 2147483647)
  result
}

///|
/// Inline uses one alignment per canonical hunk. This is the same
/// `computeRangeAlignment(..., innerHunkAlignment=false)` projection as the
/// pinned VS Code DiffEditor.
fn compute_inline_range_alignments(
  diff_state : DiffState,
  original_geometry : PaneGeometrySnapshot,
  modified_geometry : PaneGeometrySnapshot,
) -> Array[LineRangeAlignment] {
  compute_range_alignments(
    diff_state,
    original_geometry,
    modified_geometry,
    inner_hunk_alignment=false,
  )
}

///|
fn compute_managed_alignment_spacers(
  diff_state : DiffState,
  original_geometry : PaneGeometrySnapshot,
  modified_geometry : PaneGeometrySnapshot,
  inner_hunk_alignment? : Bool = true,
) -> ManagedAlignmentSpacers {
  let original_spacers : Array[ManagedAlignmentSpacer] = []
  let modified_spacers : Array[ManagedAlignmentSpacer] = []
  let alignments = compute_range_alignments(
    diff_state,
    original_geometry,
    modified_geometry,
    inner_hunk_alignment~,
  )
  for alignment in alignments {
    let delta = alignment.modified_height_in_px -
      alignment.original_height_in_px
    if delta > 0.01 {
      append_managed_spacer(
        original_spacers,
        alignment.original_range.end_line_number_exclusive - 1,
        delta,
      )
    } else if delta < -0.01 {
      append_managed_spacer(
        modified_spacers,
        alignment.modified_range.end_line_number_exclusive - 1,
        -delta,
      )
    }
  }
  { original: original_spacers, modified: modified_spacers, }
}

///|
pub extend ManagedAlignmentSpacer with Debug::{to_repr}

///|
pub extend ManagedAlignmentSpacer with Eq::{equal, not_equal}

///|
pub extend PaneForeignZoneHeight with Debug::{to_repr}

///|
pub extend PaneForeignZoneHeight with Eq::{equal, not_equal}

///|
pub extend PaneModelLineHeight with Debug::{to_repr}

///|
pub extend PaneModelLineHeight with Eq::{equal, not_equal}
