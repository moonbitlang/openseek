// Ported from `vscode/src/vs/editor/browser/view/viewUserInputEvents.ts`
// (checked-in vscode submodule): the
// view→model coordinate conversion applied to every mouse target before it
// reaches the public `ICodeEditor` events.
//
// Deviation: the source's `ViewUserInputEvents` class also holds the
// nullable `onMouseDown`/… callbacks `CodeEditorWidget` assigns; the
// viewer's `Viewer` emitters play that role, so only the conversion
// functions are ported (`convertViewToModelMouseTarget`,
// `convertViewToModelViewZoneData`). The object spread becomes a
// match-rebuild.

///|
/// `ViewUserInputEvents.convertViewToModelMouseTarget`
/// (viewUserInputEvents.ts:96-108).
pub fn convert_view_to_model_mouse_target(
  target : @editor_browser.MouseTarget,
  converter : @view_model.CoordinatesConverter,
) -> @editor_browser.MouseTarget {
  let convert_position = (position : @base_common.Position) => {
    converter.view_position_to_model_position(position)
  }
  let convert_range = (range : @base_common.Range) => {
    converter.view_range_to_model_range(range)
  }
  match target {
    MouseTargetUnknown(element~, mouse_column~, position~, range~) =>
      MouseTargetUnknown(
        element~,
        mouse_column~,
        position=position.map(convert_position),
        range=range.map(convert_range),
      )
    MouseTargetMargin(
      type_~,
      element~,
      mouse_column~,
      position~,
      range~,
      detail~,
    ) =>
      MouseTargetMargin(
        type_~,
        element~,
        mouse_column~,
        position=convert_position(position),
        range=convert_range(range),
        detail~,
      )
    MouseTargetViewZone(
      type_~,
      element~,
      mouse_column~,
      position~,
      range~,
      detail~,
    ) =>
      MouseTargetViewZone(
        type_~,
        element~,
        mouse_column~,
        position=convert_position(position),
        range=convert_range(range),
        detail=convert_view_to_model_view_zone_data(detail, converter),
      )
    MouseTargetContentText(element~, mouse_column~, position~, range~, detail~) =>
      MouseTargetContentText(
        element~,
        mouse_column~,
        position=convert_position(position),
        range=convert_range(range),
        detail~,
      )
    MouseTargetContentEmpty(element~, mouse_column~, position~, range~, detail~) =>
      MouseTargetContentEmpty(
        element~,
        mouse_column~,
        position=convert_position(position),
        range=convert_range(range),
        detail~,
      )
    MouseTargetContentWidget(_) as widget => widget
    MouseTargetOverlayWidget(_) as widget => widget
    MouseTargetScrollbar(element~, mouse_column~, position~, range~) =>
      MouseTargetScrollbar(
        element~,
        mouse_column~,
        position=convert_position(position),
        range=convert_range(range),
      )
    MouseTargetOutsideEditor(
      mouse_column~,
      position~,
      range~,
      outside_position~,
      outside_distance~,
    ) =>
      MouseTargetOutsideEditor(
        mouse_column~,
        position=convert_position(position),
        range=convert_range(range),
        outside_position~,
        outside_distance~,
      )
  }
}

///|
/// `ViewUserInputEvents.convertViewToModelViewZoneData`
/// (viewUserInputEvents.ts:110-118).
fn convert_view_to_model_view_zone_data(
  data : @editor_browser.MouseTargetViewZoneData,
  converter : @view_model.CoordinatesConverter,
) -> @editor_browser.MouseTargetViewZoneData {
  {
    view_zone_id: data.view_zone_id,
    position_before: data.position_before.map(position => {
      converter.view_position_to_model_position(position)
    }),
    position_after: data.position_after.map(position => {
      converter.view_position_to_model_position(position)
    }),
    position: converter.view_position_to_model_position(data.position),
    after_line_number: data.after_line_number,
  }
}
