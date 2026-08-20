///|
/// `MouseTargetType` (editorBrowser.ts:358-415). All 14 variants exist for
/// contract parity; `Textarea`, `GutterGlyphMargin` (glyph margin width is 0)
/// and `OverviewRuler` are never produced by this viewer.
pub(all) enum MouseTargetType {
  Unknown
  Textarea
  GutterGlyphMargin
  GutterLineNumbers
  GutterLineDecorations
  GutterViewZone
  ContentText
  ContentEmpty
  ContentViewZone
  ContentWidget
  OverviewRuler
  Scrollbar
  OverlayWidget
  OutsideEditor
} derive(Eq, Debug)

///|
/// `EditorMouseEvent` (editorDom.ts:105-147), named `EditorDomMouseEvent` here
/// to distinguish it from the hit-tested public wrapper: a `StandardMouseEvent` plus the
/// editor-anchored coordinate accessors. `editor_pos`/`relative_pos` are
/// computed lazily like the source's getters.
pub struct EditorDomMouseEvent {
  browser_event : @rdom.MouseEvent
  left_button : Bool
  middle_button : Bool
  right_button : Bool
  buttons : Int
  target : @rdom.Element?
  mut detail : Int
  posx : Double
  posy : Double
  ctrl_key : Bool
  shift_key : Bool
  alt_key : Bool
  meta_key : Bool
  timestamp : Double
  default_prevented : Bool
  /// If the event is a result of pointer-capture monitoring, `target` does
  /// not necessarily reflect the position in the editor.
  is_from_pointer_capture : Bool
  /// Coordinates relative to the whole document.
  pos : PageCoordinates
  priv editor_view_dom_node : @rdom.Element
  priv mut editor_pos_cache : EditorPagePosition?
  priv mut relative_pos_cache : CoordinatesRelativeToEditor?
}

///|
#deprecated
pub extend MouseTargetType with Debug::{to_repr}

///|
pub extend MouseTargetType with Eq::{equal, not_equal}
