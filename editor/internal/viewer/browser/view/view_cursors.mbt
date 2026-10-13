// Ported from `vscode/src/vs/editor/browser/viewParts/viewCursors/viewCursors.ts`
// and `viewCursor.ts` (oracle checked-in source), reduced to the arms reachable in this
// readonly single-cursor product:
//
// - one primary cursor, no `CursorPlurality`/secondary cursors;
// - `readOnly` is constant `true`, so `_getCursorBlinking`
//   (`viewCursors.ts:227-240`) collapses to `focused ? Solid : Hidden` and the
//   blink timers/animation classes are unreachable (`cursor-solid` always);
// - `cursorStyle` is Monaco's default `Line` with `cursorWidth` 0 (→ width 2)
//   and `cursorHeight` 0 (→ full line height); the Block/Underline arms and
//   the block-cursor `textContent`/token-class plumbing are not ported.
//
// Its narrow lifecycle adapter lives in
// `internal/viewer/browser/view/view_widgets_cursors_lifecycle.mbt`.

///|
/// Monaco's `ViewCursorRenderData` (`viewCursor.ts:26-36`), minus the
/// block-cursor `textContent`/`textContentClassName` (N-A for the Line style).
priv struct CursorRenderData {
  top : Double
  left : Double
  padding_left : Double
  width : Double
  height : Int32
}

///|
/// Public cursor owner for controller callers. Package-local lifecycle code
/// reads/writes its private `should_render` / `render_data` state directly.
struct ViewCursors {
  dom_node : @rdom.Element
  cursor : @rdom.Element
  mut should_render : Bool
  /// Monaco `ViewCursor._renderData`, stored by `prepare_render` and written
  /// out by `render`. `None` when the cursor's view line is outside the
  /// rendered window or its line node is not measurable yet — Monaco's
  /// "Outside viewport → null" arms (`viewCursor.ts:177-180`).
  mut render_data : CursorRenderData?
  /// The caret's view position captured alongside `render_data` — Monaco's
  /// current `ViewCursor._position`. This advances immediately on a cursor
  /// event and is used by the next prepare pass.
  mut last_position : @base_common.Position?
  /// The position paired with the currently painted `render_data`. Monaco's
  /// `ViewCursors.getLastRenderData` returns the array produced by the last
  /// `render`, so an incoming cursor event must not combine its new logical
  /// position with the previous frame's rectangle.
  mut last_rendered_position : @base_common.Position?
  /// The last cursor-state selection shape used by `_getClassName`.
  mut selection_is_empty : Bool
}

///|
/// Builds the `.cursors-layer` part with its single `.cursor` child —
/// `ViewCursors` constructor (`viewCursors.ts:74-79`) + `ViewCursor`
/// constructor (`viewCursor.ts:74-80`; `monaco-mouse-cursor-text` is Monaco's
/// `MOUSE_CURSOR_TEXT_CSS_CLASS_NAME`).
fn ViewCursors::ViewCursors(document : @rdom.Document) -> ViewCursors {
  let dom_node = document.create_element("div")
  dom_node.set_attribute("class", cursors_layer_class(false))
  dom_node.set_attribute("role", "presentation")
  dom_node.set_attribute("aria-hidden", "true")
  dom_node.set_attribute("data-view-part", "cursors-layer")
  let cursor = document.create_element("div")
  cursor.set_attribute("class", "cursor monaco-mouse-cursor-text")
  cursor.set_attribute("style", "display:none")
  dom_node.append_child(cursor.as_node())
  {
    dom_node,
    cursor,
    should_render: true,
    render_data: None,
    last_position: None,
    last_rendered_position: None,
    selection_is_empty: true,
  }
}

///|
fn ViewCursors::get_dom_node(self : ViewCursors) -> @rdom.Element {
  self.dom_node
}

///|
/// The layer class — `_getClassName` (`viewCursors.ts:286-340`) with only the
/// reachable arms: `has-selection` (`:288-290`), the `cursor-line-style`
/// default (`:292-294`), and `cursor-solid` (`_blinkingEnabled` is constant
/// `false` in the readonly product, `:333-335`). The smooth-caret-animation
/// suffix rides on an unmodeled option (off by default).
fn cursors_layer_class(has_selection : Bool) -> String {
  "cursors-layer\{(if has_selection { " has-selection" } else { "" })} cursor-line-style cursor-solid"
}

///|
/// Monaco `dom.computeScreenAwareSize`: snaps a CSS pixel size onto the device
/// pixel grid, `max(1, floor(dpr * css_px)) / dpr`.
fn compute_screen_aware_size(
  device_pixel_ratio : Double,
  css_px : Double,
) -> Double {
  let screen_px = device_pixel_ratio * css_px
  let snapped = screen_px.floor()
  snapped.max(1.0) / device_pixel_ratio
}

///|
/// The Line-style arm of `ViewCursor._prepareRender` (`viewCursor.ts:175-203`)
/// for a caret already measured at `measured_left` on its rendered line:
/// width is `computeScreenAwareSize(2)` (`cursorWidth` 0 → the `2` default,
/// `:185`), and a caret at least 1px in shifts left by a 1px `padding-left`
/// so the bar straddles the character boundary (`:196-200`). Height is the
/// full line height (`cursorHeight` 0 → `lineHeight`, `:168-173`, so the
/// centering adjustment is zero).
fn prepare_cursor_render_data(
  measured_left : Double,
  top : Double,
  line_height : Int32,
  device_pixel_ratio : Double,
) -> CursorRenderData {
  let width = compute_screen_aware_size(device_pixel_ratio, 2.0)
  let mut left = measured_left
  let mut padding_left = 0.0
  if width >= 2.0 && left >= 1.0 {
    padding_left = 1.0
    left -= padding_left
  }
  { top, left, padding_left, width, height: line_height, }
}

///|
/// Writes the prepared `render_data` out — `ViewCursors.render` +
/// `ViewCursor.render` (`viewCursor.ts:254-282`) plus the show/hide half of
/// `_updateBlinking` (`viewCursors.ts:242-256`): in this readonly product the
/// blinking style is `focused ? Solid : Hidden`, and with no blink timers the
/// visibility flip happens here rather than between renders.
fn ViewCursors::render_cursor(
  self : ViewCursors,
  has_selection~ : Bool,
  editor_has_focus~ : Bool,
) -> Unit {
  self.selection_is_empty = !has_selection
  self.dom_node.set_attribute("class", cursors_layer_class(has_selection))
  match self.render_data {
    None => self.cursor.set_attribute("style", "display:none")
    Some(data) =>
      self.cursor.set_attribute(
        "style",
        cursor_style(data, visible=editor_has_focus),
      )
  }
}

///|
/// `ViewCursors.onFocusChanged` + `_updateBlinking` for the readonly
/// `Solid`/`Hidden` state machine.  This is deliberately an immediate DOM
/// side effect: the source handler returns `false`, so no render follows from
/// focus alone.
fn ViewCursors::on_focus_changed(self : ViewCursors, is_focused : Bool) -> Unit {
  self.dom_node.set_attribute(
    "class",
    cursors_layer_class(!self.selection_is_empty),
  )
  match self.render_data {
    None => self.cursor.set_attribute("style", "display:none")
    Some(data) =>
      self.cursor.set_attribute("style", cursor_style(data, visible=is_focused))
  }
}

///|
/// The inline style `ViewCursor.render` writes field-by-field through
/// `FastDomNode` (`viewCursor.ts:267-273`), with the `show`/`hide` visibility
/// (`:115-127`) folded in.
fn cursor_style(data : CursorRenderData, visible~ : Bool) -> String {
  "display:block;visibility:\{(if visible { "inherit" } else { "hidden" })};top:\{data.top}px;left:\{data.left}px;padding-left:\{data.padding_left}px;width:\{data.width}px;height:\{data.height}px;line-height:\{data.height}px"
}

///|
/// Monaco's `IViewCursorRenderData` (`viewCursor.ts:18-24`): the painted
/// caret facts the mouse hit test reads (`_hitTestViewCursor`). `position` is
/// a view position; `content_left` is the caret's x in content space
/// (`ViewCursor.render` returns `contentLeft: this._renderData.left`,
/// `viewCursor.ts:274-281`); `width` is the source's hardcoded `2`.
pub struct ViewCursorRenderData {
  dom_node : @rdom.Element
  position : @base_common.Position
  content_left : Double
  width : Double
  height : Int32
}

///|
/// `ViewCursors.getLastRenderData` (`viewCursors.ts:386-388`), collapsed to
/// the single primary cursor: one entry while the caret has prepared render
/// data (i.e. its line is rendered), empty otherwise.
pub fn ViewCursors::get_last_render_data(
  self : ViewCursors,
) -> Array[ViewCursorRenderData] {
  match (self.render_data, self.last_rendered_position) {
    (Some(data), Some(position)) =>
      [
        {
          dom_node: self.cursor,
          position,
          content_left: data.left,
          width: 2.0,
          height: data.height,
        },
      ]
    _ => []
  }
}
