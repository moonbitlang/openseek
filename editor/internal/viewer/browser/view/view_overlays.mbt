// Ported from `vscode/src/vs/editor/browser/view/viewOverlays.ts`
// (`ViewOverlays`, `ViewOverlayLine`, `ContentViewOverlays`) and
// `dynamicViewOverlay.ts` (`DynamicViewOverlay`), checked-in vscode submodule. Replaces the flat-overlay
// deviation: overlays now render per-line HTML strings composed into one
// absolutely positioned row div per rendered view line, exactly Monaco's
// shape (rows recycled the way `ViewLines` recycles text lines —
// `VisibleLinesCollection`'s role; content rewritten only when a row's
// concatenated HTML changed, `ViewOverlayLine._renderedContent`'s dedupe).
//
// Deviations:
// - Registration is Monaco's `addDynamicOverlay` array, but the per-overlay
//   `ViewEventHandler` dirtiness is folded into the owning part's frame
//   events: the frame-based model re-prepares every registered overlay when
//   the part renders (the row-content dedupe keeps DOM writes minimal).
// - Package-local lifecycle wiring feeds the focused overlays' pure per-line
//   builders from the private `RenderingContext`.

///|
/// The complete set of overlays owned by `View`. Monaco's class-based array
/// is closed at this construction boundary, so retain the concrete variant
/// instead of erasing every overlay into a trait object.
priv enum DynamicViewOverlayHandle {
  CurrentLine(CurrentLineHighlightOverlay)
  Selections(SelectionsOverlay)
  Decorations(DecorationsOverlay)
  CurrentLineMargin(CurrentLineMarginHighlightOverlay)
  MarginDecorations(MarginDecorationsOverlay)
  LinesDecorations(LinesDecorationsOverlay)
  LineNumbers(LineNumbersOverlay)
}

///|
fn DynamicViewOverlayHandle::prepare_render(
  self : DynamicViewOverlayHandle,
  context : RenderingContext,
) -> Unit {
  match self {
    CurrentLine(overlay) => prepare_current_line_overlay(overlay, context)
    Selections(overlay) => prepare_selections_overlay(overlay, context)
    Decorations(overlay) => prepare_decorations_overlay(overlay, context)
    CurrentLineMargin(overlay) =>
      prepare_current_line_margin_overlay(overlay, context)
    MarginDecorations(overlay) =>
      prepare_margin_decorations_overlay(overlay, context)
    LinesDecorations(overlay) =>
      prepare_lines_decorations_overlay(overlay, context)
    LineNumbers(overlay) => prepare_line_numbers_overlay(overlay, context)
  }
}

///|
fn DynamicViewOverlayHandle::render(
  self : DynamicViewOverlayHandle,
  start_line_number : Int,
  line_number : Int,
) -> String {
  let render_result = match self {
    CurrentLine(overlay) => overlay.render_result
    Selections(overlay) => overlay.render_result
    Decorations(overlay) => overlay.render_result
    CurrentLineMargin(overlay) => overlay.render_result
    MarginDecorations(overlay) => overlay.render_result
    LinesDecorations(overlay) => overlay.render_result
    LineNumbers(overlay) => overlay.render_result
  }
  render_result_slice(render_result, start_line_number, line_number)
}

///|
/// The shared `render(startLineNumber, lineNumber)` slice every Monaco
/// overlay implements over its `_renderResult`.
fn render_result_slice(
  render_result : Array[String],
  start_line_number : Int,
  line_number : Int,
) -> String {
  let line_index = line_number - start_line_number
  if line_index < 0 || line_index >= render_result.length() {
    return ""
  }
  render_result[line_index]
}

///|
/// `ViewOverlays` (`viewOverlays.ts:19`): a rows container — one absolutely
/// positioned div per rendered view line, whose innerHTML is the registered
/// overlays' output for that line concatenated in registration order.
priv struct ViewOverlays {
  dom_node : @scrollbar.CachedDomNode
  dynamic_overlays : Array[DynamicViewOverlayHandle]
  mut lines : Array[ViewOverlayLine]
  mut window : @view_layout.LineWindow
  // `ViewOverlays._isFocused` (`viewOverlays.ts:24,76-79,128`): focus is
  // retained when the event is handled and consumed later by `render`.
  mut is_focused : Bool
}

///|
/// Complete Monaco `ViewOverlayLine` retained row
/// (`viewOverlays.ts:133-197`).
priv struct ViewOverlayLine {
  dynamic_overlays : Array[DynamicViewOverlayHandle]
  mut dom_node : @scrollbar.CachedDomNode?
  mut rendered_content : String?
}

///|
fn ViewOverlayLine::ViewOverlayLine(
  dynamic_overlays : Array[DynamicViewOverlayHandle],
) -> ViewOverlayLine {
  { dynamic_overlays, dom_node: None, rendered_content: None, }
}

///|
fn ViewOverlayLine::get_dom_node(self : ViewOverlayLine) -> @rdom.Element? {
  self.dom_node.map(node => node.element())
}

///|
fn ViewOverlayLine::set_dom_node(
  self : ViewOverlayLine,
  dom_node : @rdom.Element,
) -> Unit {
  self.dom_node = Some(CachedDomNode(dom_node))
}

///|
fn ViewOverlayLine::on_content_changed(_self : ViewOverlayLine) -> Unit {
  // Nothing (`viewOverlays.ts:156-158`).
}

///|
fn ViewOverlayLine::on_tokens_changed(_self : ViewOverlayLine) -> Unit {
  // Nothing (`viewOverlays.ts:159-161`).
}

///|
fn ViewOverlayLine::render_line(
  self : ViewOverlayLine,
  line_number : Int,
  delta_top : Double,
  line_height : Int,
  viewport : @view_layout.ViewportData,
  builder : StringBuilder,
) -> Bool {
  let content = StringBuilder()
  for overlay in self.dynamic_overlays {
    content.write_string(
      overlay.render(viewport.start_line_number, line_number),
    )
  }
  let content = content.to_string()
  if self.rendered_content == Some(content) {
    return false
  }
  self.rendered_content = Some(content)
  builder <+
    $|<div style="top:\{delta_top}px;height:\{line_height}px;line-height:\{line_height}px;">\{content}</div>
  true
}

///|
fn ViewOverlayLine::layout_line(
  self : ViewOverlayLine,
  _line_number : Int,
  delta_top : Double,
  line_height : Int,
) -> Unit {
  match self.dom_node {
    Some(node) => {
      node.set_top(Pixels(delta_top))
      node.set_height(Pixels(line_height.to_double()))
      node.set_line_height(Pixels(line_height.to_double()))
    }
    None => ()
  }
}

///|
fn ViewOverlays::ViewOverlays(
  document : @rdom.Document,
  class_name : String,
) -> ViewOverlays {
  let dom_element = document.create_element("div")
  dom_element.set_attribute("class", class_name)
  dom_element.set_attribute("data-view-part", class_name)
  {
    dom_node: CachedDomNode(dom_element),
    dynamic_overlays: [],
    lines: [],
    window: { start: 0, end: 0, },
    is_focused: false,
  }
}

///|
/// `addDynamicOverlay` (`viewOverlays.ts:69`): registration order is row
/// concatenation order (Monaco's `view.ts:218-231` z-order).
fn ViewOverlays::add_dynamic_overlay(
  self : ViewOverlays,
  overlay : DynamicViewOverlayHandle,
) -> Unit {
  self.dynamic_overlays.push(overlay)
}

///|
/// `ViewOverlays.prepareRender` (`viewOverlays.ts:113-121`) without the
/// per-overlay `shouldRender` filter (header deviation): every registered
/// overlay prepares its per-line render result.
fn ViewOverlays::prepare_overlays(
  self : ViewOverlays,
  context : RenderingContext,
) -> Unit {
  for overlay in self.dynamic_overlays {
    overlay.prepare_render(context)
  }
}

///|
fn ViewOverlays::on_content_or_tokens_changed(self : ViewOverlays) -> Unit {
  for line in self.lines {
    line.on_content_changed()
    line.on_tokens_changed()
  }
}

///|
/// `ViewOverlays.onFocusChanged` (`viewOverlays.ts:76-79`).
fn ViewOverlays::on_focus_changed(
  self : ViewOverlays,
  is_focused : Bool,
) -> Unit {
  self.is_focused = is_focused
}

///|
/// `ViewOverlays.render`'s equality-gated focused-class write. The source uses
/// `FastDomNode.toggleClassName`; the retained Bool, not frame-final input,
/// decides the class.
fn ViewOverlays::render_focused_class(
  self : ViewOverlays,
  base_class_name : String,
) -> Unit {
  let element = self.dom_node.element()
  let class_name = if self.is_focused {
    "\{base_class_name} focused"
  } else {
    base_class_name
  }
  if element.get_attribute("class") != Some(class_name) {
    element.set_attribute("class", class_name)
  }
}

///|
/// `VisibleLinesCollection.renderLines` + `ViewOverlayLine`, through the same
/// source-ordered renderer used by text rows.
fn ViewOverlays::render_lines(
  self : ViewOverlays,
  viewport : @view_layout.ViewportData,
) -> Unit {
  let renderer = ViewLayerRenderer::ViewLayerRenderer(
    self.dom_node.element(),
    () => ViewOverlayLine::ViewOverlayLine(self.dynamic_overlays),
    line => line.get_dom_node(),
    (line, node) => line.set_dom_node(node),
    (line, line_number, delta_top, line_height) => {
      line.layout_line(line_number, delta_top, line_height)
    },
    (line, line_number, delta_top, line_height, viewport, builder) => {
      line.render_line(line_number, delta_top, line_height, viewport, builder)
    },
    viewport,
    _line_number => viewport.line_height,
  )
  let result = renderer.render(
    {
      rend_line_number_start: self.window.start,
      lines: self.lines,
      lines_length: self.lines.length(),
    },
    viewport.start_line_number,
    viewport.end_line_number,
    viewport.relative_vertical_offset,
  )
  self.lines = result.lines
  self.window = viewport_window(viewport)
}

///|
/// `ContentViewOverlays` (`viewOverlays.ts:204`): the content-side rows
/// container hosting the current-line, selection, and decoration overlays in
/// Monaco's registration order (`view.ts:218-221`). `View` owns and constructs
/// it, and the `ViewPart` implementation accesses `should_render` in this
/// package, so both the owner and its state remain private.
priv struct ContentViewOverlays {
  overlays : ViewOverlays
  current_line : CurrentLineHighlightOverlay
  mut should_render : Bool
  // `ContentViewOverlays._contentWidth` (`viewOverlays.ts:204,210-213,226`).
  mut content_width : Double
  mut read_content_width : () -> Double
}

///|
fn ContentViewOverlays::ContentViewOverlays(
  document : @rdom.Document,
) -> ContentViewOverlays {
  let overlays = ViewOverlays::ViewOverlays(document, "view-overlays")
  let current_line = CurrentLineHighlightOverlay::CurrentLineHighlightOverlay()
  let selections = SelectionsOverlay::SelectionsOverlay()
  let decorations = DecorationsOverlay::DecorationsOverlay()
  overlays.add_dynamic_overlay(CurrentLine(current_line))
  overlays.add_dynamic_overlay(Selections(selections))
  overlays.add_dynamic_overlay(Decorations(decorations))
  {
    overlays,
    current_line,
    should_render: true,
    content_width: 0.0,
    read_content_width: () => 0.0,
  }
}

///|
/// Installs the local `ViewContext.configuration.options.layoutInfo` seam and
/// performs the constructor-time `_contentWidth` read.
fn ContentViewOverlays::install_content_width_reader(
  self : ContentViewOverlays,
  read_content_width : () -> Double,
) -> Unit {
  self.read_content_width = read_content_width
  self.on_configuration_changed()
}

///|
/// `ContentViewOverlays.onConfigurationChanged`'s retained layout read.
fn ContentViewOverlays::on_configuration_changed(
  self : ContentViewOverlays,
) -> Unit {
  self.content_width = (self.read_content_width)()
}

///|
fn ContentViewOverlays::get_dom_node(
  self : ContentViewOverlays,
) -> @rdom.Element {
  self.overlays.dom_node.element()
}

///|
/// Monaco `ViewOverlays.render` (`viewOverlays.ts:125`):
/// `toggleClassName('focused', this._isFocused)` on the overlay container —
/// selection colors key off `.focused .selected-text` (`selections.css`).
fn ContentViewOverlays::set_focused(
  self : ContentViewOverlays,
  focused : Bool,
) -> Unit {
  // Retain the public helper's existing signature; production render passes
  // only `overlays.is_focused`, the source event cache.
  let element = self.overlays.dom_node.element()
  let class_name = if focused {
    "view-overlays focused"
  } else {
    "view-overlays"
  }
  if element.get_attribute("class") != Some(class_name) {
    element.set_attribute("class", class_name)
  }
}

///|
/// Installs the model-scoped live configuration reader used by both concrete
/// current-line overlays. Each state reads it immediately and again in its
/// source-time `ViewConfigurationChanged` handler.
pub fn View::install_current_line_configuration_reader(
  self : View,
  read_configuration : () -> (
    @editor_api.RenderLineHighlight,
    Bool,
    Bool,
    Double,
    Double,
  ),
) -> Unit {
  self.content_view_overlays.install_content_width_reader(() => {
    let (_, _, _, _, content_width) = read_configuration()
    content_width
  })
  self.margin_view_overlays.install_content_left_reader(() => {
    let (_, _, _, content_left, _) = read_configuration()
    content_left
  })
  self.content_view_overlays.current_line.state.install_configuration_reader(
    read_configuration,
  )
  self.margin_view_overlays.current_line_margin.state.install_configuration_reader(
    read_configuration,
  )
}
