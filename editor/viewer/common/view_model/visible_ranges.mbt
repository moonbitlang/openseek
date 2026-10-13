// Backing for the public read-API visible-range cluster, the `ViewModel` side
// of Monaco's `CodeEditorWidget.getVisibleRanges` / `getPosition` delegators
// (`vs/editor/common/viewModel/viewModelImpl.ts`). The completely-visible view
// line range is computed by the owner from its `ViewLayout` (Monaco's
// `getCompletelyVisibleViewRange`); this file ports the view→model conversion
// with the hidden-area split (`_toModelVisibleRanges`) plus the column/visibility
// helpers it needs.

///|
/// Merged one-based hidden model-line intervals, Monaco's
/// `ViewModel.getHiddenAreas` (`this._lines.getHiddenAreas()`).
pub fn ViewModel::get_hidden_areas(
  self : ViewModel,
) -> Array[@base_common.Range] {
  self.lines.get_hidden_areas()
}

///|
/// Whether a model position lands on a visible (non-hidden) line, Monaco's
/// `CoordinatesConverter.modelPositionIsVisible`. The read API gates
/// `getLineHeightForPosition` on this.
pub fn ViewModel::model_position_is_visible(
  self : ViewModel,
  position : @base_common.Position,
) -> Bool {
  self.coordinates_converter.model_position_is_visible(position)
}

///|
/// Validates a model position before ViewZones derives its before/after
/// position — `TextModel.validatePosition` at `viewZones.ts:159-173`.
pub fn ViewModel::validate_model_position(
  self : ViewModel,
  position : @base_common.Position,
) -> @base_common.Position {
  self.model.validate_position(position)
}

///|
/// Converts one validated-or-untrusted model position to view coordinates,
/// forwarding the ViewZones affinity and `allowZeroLineNumber` seam exactly.
/// The projected collection performs source-shaped model validation first.
pub fn ViewModel::model_position_to_view_position(
  self : ViewModel,
  position : @base_common.Position,
  affinity? : @model.PositionAffinity,
  allow_zero_line_number~ : Bool = false,
) -> @base_common.Position {
  self.lines.convert_model_position_to_view_position(
    position.line_number,
    position.column,
    affinity?,
    allow_zero_line_number~,
  )
}

///|
/// Minimum one-based column of a view line, Monaco's `getLineMinColumn`.
pub fn ViewModel::get_line_min_column(
  self : ViewModel,
  view_line_number : Int32,
) -> Int32 {
  self.lines.get_view_line_min_column(view_line_number)
}

///|
/// Maximum one-based column of a view line, Monaco's `getLineMaxColumn`.
pub fn ViewModel::get_line_max_column(
  self : ViewModel,
  view_line_number : Int32,
) -> Int32 {
  self.lines.get_view_line_max_column(view_line_number)
}

///|
/// Maximum one-based column of a model line, Monaco's `model.getLineMaxColumn`
/// (`content length + 1`). Used to close a split visible range at a hidden
/// region's boundary line.
pub fn ViewModel::model_line_max_column(
  self : ViewModel,
  model_line_number : Int32,
) -> Int32 {
  self.model.snapshot.line_text(model_line_number - 1).length() + 1
}

///|
/// Splits a completely-visible *view* range into the model ranges it covers,
/// Monaco's `ViewModelImpl._toModelVisibleRanges`
/// (`viewModelImpl.ts:655`). With no hidden regions the converted model range is
/// returned whole; otherwise each hidden region carves the visible span into the
/// model ranges actually on screen above/below it.
pub fn ViewModel::to_model_visible_ranges(
  self : ViewModel,
  visible_view_range : @base_common.Range,
) -> Array[@base_common.Range] {
  let visible = self.coordinates_converter.view_range_to_model_range(
    visible_view_range,
  )
  let hidden_areas = self.get_hidden_areas()
  if hidden_areas.length() == 0 {
    return [visible]
  }
  let result : Array[@base_common.Range] = []
  let mut start_line_number = visible.start_line_number
  let mut start_column = visible.start_column
  let end_line_number = visible.end_line_number
  let end_column = visible.end_column
  for hidden in hidden_areas {
    let hidden_start_line_number = hidden.start_line_number
    let hidden_end_line_number = hidden.end_line_number
    if hidden_end_line_number < start_line_number {
      continue
    }
    if hidden_start_line_number > end_line_number {
      continue
    }
    if start_line_number < hidden_start_line_number {
      result.push(
        Range(
          start_line_number,
          start_column,
          hidden_start_line_number - 1,
          self.model_line_max_column(hidden_start_line_number - 1),
        ),
      )
    }
    start_line_number = hidden_end_line_number + 1
    start_column = 1
  }
  if start_line_number < end_line_number ||
    (start_line_number == end_line_number && start_column < end_column) {
    result.push(
      Range(start_line_number, start_column, end_line_number, end_column),
    )
  }
  result
}
