// Ported from `vscode/src/vs/editor/browser/editorBrowser.ts:358-543` (vscode
// checked-in submodule): the
// `MouseTargetType` enum and the `IMouseTarget` discriminated union with its
// per-kind detail payloads.
//
// Shape notes:
//   * The `IMouseTarget*` interface family (each extending `IBaseMouseTarget`)
//     ports as one enum with labeled payloads plus accessor methods, the
//     repository's discriminated-union precedent (`HoverAnchor`). The base
//     fields (`element`, `position`, `mouseColumn`, `range`) repeat per
//     variant exactly as each source interface re-declares/narrows them.
//   * Positions/ranges are 1-based `@base_common` values (Monaco semantics).
//     Which coordinate space they carry is the producer's contract: view
//     coordinates inside the hit-test/controller pipeline, model coordinates
//     once `ViewUserInputEvents.convertViewToModelMouseTarget` has run.
//
// Omissions:
//   * `IMouseTargetTextarea` — the viewer has no textarea part (focus lives on
//     the root section); `MouseTargetType::Textarea` exists for contract
//     parity but no variant can produce it.
//   * `IMouseTargetOverviewRuler` — Monaco's `MouseTargetFactory` itself never
//     produces `OVERVIEW_RULER` (no factory exists; the region hits as
//     `SCROLLBAR`), so only the type enum keeps the slot.
//   * `IMouseTargetMarginData.glyphMarginLane` — the viewer has no glyph
//     margin lanes (`glyph_margin_width` is always 0).
//   * `IEditorMouseEvent`/`IPartialEditorMouseEvent` live beside these targets
//     in `editor_mouse_events.mbt`; the raw `editorDom.ts` event has the
//     distinct `EditorDomMouseEvent` name.

///|
/// `IMouseTargetMarginData` (editorBrowser.ts:442-449). `offset_x` is
/// editor-left-relative (`Math.abs(request.relativePos.x)`), not lane-relative.
pub(all) struct MouseTargetMarginData {
  is_after_lines : Bool
  glyph_margin_left : Double
  glyph_margin_width : Double
  line_numbers_width : Double
  offset_x : Double
} derive(Eq, Debug)

///|
/// `IMouseTargetViewZoneData` (editorBrowser.ts:456-462).
pub(all) struct MouseTargetViewZoneData {
  view_zone_id : String
  position_before : @base_common.Position?
  position_after : @base_common.Position?
  position : @base_common.Position
  after_line_number : Int
} derive(Eq, Debug)

///|
/// `IMouseTargetContentTextData` (editorBrowser.ts:469-475).
pub(all) struct MouseTargetContentTextData {
  might_be_foreign_element : Bool
  injected_text : @view_model.InjectedText?
}

///|
/// `IMouseTargetContentEmptyData` (editorBrowser.ts:482-485).
/// `horizontal_distance_to_text` is Monaco's optional number: `Some` only when
/// the hit line is rendered and the pointer sits past its text.
pub(all) struct MouseTargetContentEmptyData {
  is_after_lines : Bool
  horizontal_distance_to_text : Double?
} derive(Eq, Debug)

///|
/// `IMouseTargetOutsideEditor.outsidePosition` (editorBrowser.ts:514).
pub(all) enum OutsidePosition {
  Above
  Below
  Left
  Right
} derive(Eq, Debug)

///|
/// `IMouseTarget` (editorBrowser.ts:520-532): the discriminated union. Margin
/// and view-zone targets carry their concrete `type_` (one of the three
/// gutter types / gutter-vs-content zone) exactly as the source narrows
/// `IMouseTargetMargin.type` / `IMouseTargetViewZone.type`.
pub(all) enum MouseTarget {
  MouseTargetUnknown(
    element~ : @rdom.Element?,
    mouse_column~ : Int,
    position~ : @base_common.Position?,
    range~ : @base_common.Range?
  )
  MouseTargetMargin(
    type_~ : MouseTargetType,
    element~ : @rdom.Element?,
    mouse_column~ : Int,
    position~ : @base_common.Position,
    range~ : @base_common.Range,
    detail~ : MouseTargetMarginData
  )
  MouseTargetViewZone(
    type_~ : MouseTargetType,
    element~ : @rdom.Element?,
    mouse_column~ : Int,
    position~ : @base_common.Position,
    range~ : @base_common.Range,
    detail~ : MouseTargetViewZoneData
  )
  MouseTargetContentText(
    element~ : @rdom.Element?,
    mouse_column~ : Int,
    position~ : @base_common.Position,
    range~ : @base_common.Range,
    detail~ : MouseTargetContentTextData
  )
  MouseTargetContentEmpty(
    element~ : @rdom.Element?,
    mouse_column~ : Int,
    position~ : @base_common.Position,
    range~ : @base_common.Range,
    detail~ : MouseTargetContentEmptyData
  )
  MouseTargetContentWidget(
    element~ : @rdom.Element?,
    mouse_column~ : Int,
    detail~ : String
  )
  MouseTargetScrollbar(
    element~ : @rdom.Element?,
    mouse_column~ : Int,
    position~ : @base_common.Position,
    range~ : @base_common.Range
  )
  MouseTargetOverlayWidget(
    element~ : @rdom.Element?,
    mouse_column~ : Int,
    detail~ : String
  )
  MouseTargetOutsideEditor(
    mouse_column~ : Int,
    position~ : @base_common.Position,
    range~ : @base_common.Range,
    outside_position~ : OutsidePosition,
    outside_distance~ : Double
  )
}

///|
/// The discriminant, `IMouseTarget.type`.
pub fn MouseTarget::type_(self : MouseTarget) -> MouseTargetType {
  match self {
    MouseTargetUnknown(..) => Unknown
    MouseTargetMargin(type_~, ..) => type_
    MouseTargetViewZone(type_~, ..) => type_
    MouseTargetContentText(..) => ContentText
    MouseTargetContentEmpty(..) => ContentEmpty
    MouseTargetContentWidget(..) => ContentWidget
    MouseTargetScrollbar(..) => Scrollbar
    MouseTargetOverlayWidget(..) => OverlayWidget
    MouseTargetOutsideEditor(..) => OutsideEditor
  }
}

///|
/// `IBaseMouseTarget.element`.
pub fn MouseTarget::element(self : MouseTarget) -> @rdom.Element? {
  match self {
    MouseTargetUnknown(element~, ..)
    | MouseTargetMargin(element~, ..)
    | MouseTargetViewZone(element~, ..)
    | MouseTargetContentText(element~, ..)
    | MouseTargetContentEmpty(element~, ..)
    | MouseTargetContentWidget(element~, ..)
    | MouseTargetScrollbar(element~, ..)
    | MouseTargetOverlayWidget(element~, ..) => element
    MouseTargetOutsideEditor(..) => None
  }
}

///|
/// `IBaseMouseTarget.position` ('approximate' editor position; `None` for the
/// widget kinds whose source interfaces pin `position: null`).
pub fn MouseTarget::position(self : MouseTarget) -> @base_common.Position? {
  match self {
    MouseTargetUnknown(position~, ..) => position
    MouseTargetMargin(position~, ..)
    | MouseTargetViewZone(position~, ..)
    | MouseTargetContentText(position~, ..)
    | MouseTargetContentEmpty(position~, ..)
    | MouseTargetScrollbar(position~, ..)
    | MouseTargetOutsideEditor(position~, ..) => Some(position)
    MouseTargetContentWidget(..) | MouseTargetOverlayWidget(..) => None
  }
}

///|
/// `IBaseMouseTarget.mouseColumn`: the desired 1-based visual column (e.g.
/// when the position column got clamped to the text length).
pub fn MouseTarget::mouse_column(self : MouseTarget) -> Int {
  match self {
    MouseTargetUnknown(mouse_column~, ..)
    | MouseTargetMargin(mouse_column~, ..)
    | MouseTargetViewZone(mouse_column~, ..)
    | MouseTargetContentText(mouse_column~, ..)
    | MouseTargetContentEmpty(mouse_column~, ..)
    | MouseTargetContentWidget(mouse_column~, ..)
    | MouseTargetScrollbar(mouse_column~, ..)
    | MouseTargetOverlayWidget(mouse_column~, ..)
    | MouseTargetOutsideEditor(mouse_column~, ..) => mouse_column
  }
}

///|
/// `IBaseMouseTarget.range`.
pub fn MouseTarget::range(self : MouseTarget) -> @base_common.Range? {
  match self {
    MouseTargetUnknown(range~, ..) => range
    MouseTargetMargin(range~, ..)
    | MouseTargetViewZone(range~, ..)
    | MouseTargetContentText(range~, ..)
    | MouseTargetContentEmpty(range~, ..)
    | MouseTargetScrollbar(range~, ..)
    | MouseTargetOutsideEditor(range~, ..) => Some(range)
    MouseTargetContentWidget(..) | MouseTargetOverlayWidget(..) => None
  }
}

///|
#deprecated
pub extend MouseTargetContentEmptyData with Debug::{to_repr}

///|
pub extend MouseTargetContentEmptyData with Eq::{equal, not_equal}

///|
#deprecated
pub extend MouseTargetMarginData with Debug::{to_repr}

///|
pub extend MouseTargetMarginData with Eq::{equal, not_equal}

///|
#deprecated
pub extend MouseTargetViewZoneData with Debug::{to_repr}

///|
pub extend MouseTargetViewZoneData with Eq::{equal, not_equal}

///|
#deprecated
pub extend OutsidePosition with Debug::{to_repr}

///|
pub extend OutsidePosition with Eq::{equal, not_equal}
