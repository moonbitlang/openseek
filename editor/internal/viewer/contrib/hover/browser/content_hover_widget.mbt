// Ported from `vscode/src/vs/editor/contrib/hover/browser/contentHoverWidget.ts`
// (`ContentHoverWidget`) with the available-space arithmetic of its base
// `resizableContentWidget.ts` and the DOM skeleton of
// `vs/base/browser/ui/hover/hoverWidget.ts` (`HoverWidget`). The widget is a
// persistent content widget: its DOM mounts once via the editor's
// `add_content_widget` and stays in the tree; `show` rewrites the contents
// when a hover result changes, `hide` toggles the `.hidden` class — never an
// unmount, so the `fade-in` animation plays only on a genuine hidden→shown
// transition.
//
// Standing deviations:
//   - No resize sashes (`ResizableHTMLElement`'s sash/drag machinery
//     unported): the widget is not user-resizable, so `_resize`,
//     `_lastDimensions`, `_contentWidth`/`_updateMinimumWidth`, and the
//     `_findMaximumRenderingWidth`/`_findMaximumRenderingHeight` /
//     `_isHoverTextOverflowing` cluster (all only reachable from the resize
//     path) are N-A. `_resizableNode.layout` survives as direct `width`/
//     `height` writes on the wrapper.
//   - No `onDidLayoutChange` re-run of `_updateMaxDimensions` while visible;
//     the constraints refresh on the next show instead.

///|
/// Monaco `RenderedContentHover` (`contentHoverRendered.ts`), narrowed to what
/// the widget consumes: where to anchor (`showAtPosition` /
/// `showAtSecondaryPosition`, both model-space — `computeHoverPositions`'s
/// outputs), the ordered hover parts, and the active model language needed by
/// hover's shared-Markdown fenced-code callback. The browser widget owns the
/// concrete retained row DOM and its render disposables.
pub(all) struct RenderedContentHover {
  show_at_position : @base_common.Position
  show_at_secondary_position : @base_common.Position
  parts : Array[@hover.HoverPart]
  language_id : String
}

///|
/// Monaco's `RenderedContentHoverParts` prepares a detached
/// `DocumentFragment` and the lifetimes owned by those rows before a widget
/// releases its previous render. This opaque browser-only value is shared by
/// the code content widget and the DOM-anchored Markdown widget so Markdown
/// rendering policy and retained listener disposal have one implementation.
priv struct HoverRowsRender {
  fragment : @rdom.DocumentFragment
  disposables : Array[@base_common.Disposable]
  mut transferred : Bool
  mut disposed : Bool
}

///|
/// Per-render lifetime drain. Replacement, hide, and retained-widget teardown
/// all converge here so no shared Markdown listener survives the DOM it owns.
fn dispose_hover_render_disposables(
  values : Array[@base_common.Disposable],
) -> Unit {
  for disposable in values {
    disposable.dispose()
  }
  values.clear()
}

///|
/// Transfers the detached rows into exactly one widget container. The render
/// value remains alive afterwards solely to own row resources; callers never
/// receive the fragment and therefore cannot mount the same retained rows
/// twice.
fn HoverRowsRender::mount_into(
  self : HoverRowsRender,
  target : @rdom.Element,
) -> Bool {
  guard !self.disposed && !self.transferred else { return false }
  self.transferred = true
  replace_hover_contents(target, self.fragment)
  true
}

///|
/// Replacement, hide, and teardown may converge on the same retained value;
/// make that convergence explicitly idempotent.
fn HoverRowsRender::dispose(self : HoverRowsRender) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  dispose_hover_render_disposables(self.disposables)
}

///|
/// The editor/services capabilities the widget needs from `Viewer`, as
/// closures (Monaco's `this._editor` + DI services). Built once at widget
/// construction.
pub(all) struct ContentHoverWidgetHost {
  /// The editor's root node — Monaco's `this._editor.getDomNode()` /
  /// `getLayoutInfo()` box: the `_updateMaxDimensions` width/height source and
  /// the page-space reference for `_availableVerticalSpaceAbove`/`Below`.
  root : @rdom.Element
  /// `editor.layoutContentWidget(this)`: re-read `get_position()` and
  /// reposition on the next render.
  layout_content_widget : () -> Unit
  /// `editor.render()`: force a synchronous render so the freshly shown
  /// widget does not paint one frame at a stale position
  /// (`contentHoverWidget.ts:319-321`).
  render_now : () -> Unit
  /// `editor.focus()`, the `hide()` focus-restore arm.
  focus_editor : () -> Unit
  /// `getScrolledVisiblePosition(position).top`: the anchor line's top edge in
  /// editor-viewport pixels, the `_availableVerticalSpace*` input.
  scrolled_visible_position_top : (@base_common.Position) -> Double
  /// `fontInfo.lineHeight`, read live like the source's option access.
  line_height : () -> Double
  /// The pointer is on the hover widget: keep the hover open (the controller's
  /// `_shouldKeepCurrentHover` arm over the content widget).
  keep_hover_open : () -> Unit
  /// Wrapper mouseleave forwarding; the host checks whether the pointer also
  /// left the editor DOM before hiding.
  handle_mouseleave : (Double, Double) -> Unit
  /// Widget keydown resolves through the keybinding table (`hoverActions.ts`'s
  /// scroll cluster).
  handle_keydown : (@rdom.Event, @rdom.KeyboardEvent) -> Unit
  hook_scrollable_scrollbar_input : (
    @scrollbar.ScrollableElementDom,
    @scrollbar.ScrollableElementOwner,
  ) -> Unit
}

///|
/// Monaco `ContentHoverWidget`. `wrapper` is `_resizableNode.domNode`
/// (`.monaco-resizable-hover`), `hover` is the base `HoverWidget`'s
/// `containerDomNode` (`.monaco-hover.fade-in`), `scrollable` wraps its
/// `contentsDomNode` (`.monaco-hover-content`).
pub struct ContentHoverWidget {
  wrapper : @rdom.Element
  priv hover : @rdom.Element
  scrollable : @scrollbar.ScrollableElementDom
  priv host : ContentHoverWidgetHost
  mut rendered_hover : RenderedContentHover?
  priv mut position_preference : @view.ContentWidgetPositionPreference?
  priv mut hover_rows : HoverRowsRender?
}

///|
/// Monaco `ContentHoverWidget.ID`.
let content_hover_widget_id : String = "editor.contrib.resizableContentHoverWidget"

///|
/// Monaco `ContentHoverWidget.getPosition` (`contentHoverWidget.ts:324-334`).
/// The generic affinity handoff is ported, but the local hover-part pipeline
/// does not yet retain `RenderedContentHover.shouldAppearBeforeContent`; that
/// concrete producer remains an explicit deferred hover-part seam.
fn ContentHoverWidget::content_widget_position(
  self : ContentHoverWidget,
) -> @view.ContentWidgetPosition? {
  match self.rendered_hover {
    Some(rendered) =>
      Some({
        position: Some(rendered.show_at_position),
        secondary_position: Some(rendered.show_at_secondary_position),
        preference: Some([self.position_preference.unwrap_or(Above)]),
        position_affinity: None,
      })
    None => None
  }
}

///|
/// Adapts the concrete hover to Monaco's content-widget contract. Overflow is
/// the hover's sole optional field; absent render callbacks stay absent rather
/// than becoming four constant trait methods.
pub fn ContentHoverWidget::content_widget_handle(
  self : ContentHoverWidget,
) -> @view.ContentWidgetHandle {
  ContentWidgetHandle(
    () => content_hover_widget_id,
    () => self.wrapper,
    () => self.content_widget_position(),
    allow_editor_overflow=true,
  )
}

///|
/// Builds the persistent widget DOM and its listeners (Monaco's constructor +
/// `HoverWidget(fadeIn: true)`); starts hidden (`_setRenderedHover(undefined)`).
/// The caller mounts it exactly once through the editor's content-widget seam.
pub fn ContentHoverWidget::ContentHoverWidget(
  host : ContentHoverWidgetHost,
) -> ContentHoverWidget {
  let document = @rdom.document()
  let wrapper = document.create_element("div")
  wrapper.set_attribute("class", "monaco-resizable-hover")
  let hover = document.create_element("div")
  hover.set_attribute("class", "monaco-hover fade-in hidden")
  hover.set_attribute("role", "tooltip")
  hover.set_attribute("tabindex", "0")
  let scrollable = @scrollbar.ScrollableElementDom("monaco-hover-content")
  hover.append_child(scrollable.wrapper().as_node())
  wrapper.append_child(hover.as_node())
  let widget : ContentHoverWidget = {
    wrapper,
    hover,
    scrollable,
    host,
    rendered_hover: None,
    position_preference: None,
    hover_rows: None,
  }
  // Content widgets swallow pointer motion, but a hover may overlap source
  // text; non-interactive mousedown should still start editor selection at
  // the underlying coordinate.
  wrapper.add_event_listener("mousemove", event => {
    // The pointer is on the hover widget: keep it open. The editor never
    // sees this move (stop_propagation), so the controller's grace timer
    // would otherwise still fire and hide the widget out from under it.
    (host.keep_hover_open)()
    event.stop_propagation()
  })
  wrapper.add_event_listener("mouseleave", event => {
    match event.to_mouse_event() {
      Some(mouse) =>
        (host.handle_mouseleave)(
          mouse.get_client_x().to_double(),
          mouse.get_client_y().to_double(),
        )
      None => ()
    }
    event.stop_propagation()
  })
  wrapper.add_event_listener("mousedown", event => {
    // Interactive pieces (links, the copy affordance) own their click;
    // anything else bubbles to the editor's `MouseHandler`, which classifies
    // it `CONTENT_WIDGET` (fingerprint walk) and starts no selection —
    // Monaco's hover widget equally forwards nothing.
    if hover_mousedown_is_interactive(event) {
      event.stop_propagation()
    }
  })
  wrapper.add_event_listener("click", event => {
    if handle_hover_copy_click(event) {
      event.prevent_default()
    }
    event.stop_propagation()
  })
  wrapper.add_event_listener("contextmenu", event => event.stop_propagation())
  wrapper.add_event_listener("focusin", event => event.stop_propagation())
  wrapper.add_event_listener("focusout", event => event.stop_propagation())
  let on_wheel = (event : @rdom.Event) => {
    match event.to_wheel_event() {
      Some(wheel) => {
        event.prevent_default()
        event.stop_propagation()
        widget.handle_wheel(wheel)
      }
      None => event.stop_propagation()
    }
  }
  wrapper.add_event_listener("wheel", on_wheel)
  scrollable.content().add_event_listener("wheel", on_wheel)
  scrollable
  .content()
  .add_event_listener("scroll", _ => scrollable.update_from_native_content())
  (host.hook_scrollable_scrollbar_input)(scrollable, HoverScrollableElement)
  wrapper.add_event_listener("keydown", event => {
    match event.to_keyboard_event() {
      Some(keyboard) => (host.handle_keydown)(event, keyboard)
      None => event.stop_propagation()
    }
  })
  widget
}

///|
/// Monaco `isVisible` (the `hoverVisible` context key `_setRenderedHover`
/// maintains).
pub fn ContentHoverWidget::is_visible(self : ContentHoverWidget) -> Bool {
  self.rendered_hover is Some(_)
}

///|
/// Monaco `_setRenderedHover` (`contentHoverWidget.ts:278-283`): release the
/// previous rendered hover, adopt the prepared render lifetime, swap the
/// rendered state, and toggle the container's `hidden` class.
fn ContentHoverWidget::set_rendered_hover(
  self : ContentHoverWidget,
  rendered_hover : RenderedContentHover?,
  hover_rows : HoverRowsRender?,
) -> Unit {
  match self.hover_rows {
    Some(rows) => rows.dispose()
    None => ()
  }
  self.hover_rows = hover_rows
  self.rendered_hover = rendered_hover
  let hidden = if rendered_hover is Some(_) { "" } else { " hidden" }
  self.hover.set_attribute("class", "monaco-hover fade-in\{hidden}")
}

///|
/// Monaco `RenderedContentHoverParts` (`contentHoverRendered.ts:221-253`):
/// render every row and register its lifetime in a detached fragment before
/// touching the currently displayed hover. Each row receives the source's
/// `_registerListenersOnRenderedParts` `tabIndex = 0`.
fn render_hover_rows(
  parts : Array[@hover.HoverPart],
  language_id : String,
) -> HoverRowsRender {
  let fragment = @rdom.document().create_document_fragment()
  let disposables : Array[@base_common.Disposable] = []
  for part in parts {
    let row = match part {
      MarkdownHover(contents~, ..) =>
        render_markdown_hover_row(disposables, contents, language_id)
      MarkerHover(marker~, ..) => marker_hover_row(marker.message)
      LoadingHover(message~, ..) => standard_hover_row(message)
    }
    row.set_attribute("tabindex", "0")
    fragment.append_child(row.as_node())
  }
  { fragment, disposables, transferred: false, disposed: false, }
}

///|
extern "js" fn replace_hover_contents(
  contents : @rdom.Element,
  fragment : @rdom.DocumentFragment,
) -> Unit =
  #| (contents, fragment) => {
  #|   contents.style.paddingBottom = '';
  #|   contents.textContent = '';
  #|   contents.appendChild(fragment);
  #| }

///|
/// One Markdown participant part is one row with one `.markdown-hover` child
/// per content, matching Monaco `MarkdownHoverParticipant.renderMarkdown`.
fn render_markdown_hover_row(
  render_disposables : Array[@base_common.Disposable],
  contents : Array[@language.HoverContent],
  language_id : String,
) -> @rdom.Element {
  let document = @rdom.document()
  let row = document.create_element("div")
  row.set_attribute("class", "hover-row")
  let row_contents = document.create_element("div")
  row_contents.set_attribute("class", "hover-row-contents")
  for content in contents {
    let markdown_hover = document.create_element("div")
    markdown_hover.set_attribute("class", "markdown-hover")
    let hover_contents = document.create_element("div")
    hover_contents.set_attribute("class", "hover-contents")
    match content {
      PlainText(text) => append_hover_plaintext(hover_contents, text)
      Markdown(markdown) => {
        let options = @browser_markdown.MarkdownRenderOptions(
          language_id~,
          code_block_renderer=@hover.render_hover_code_block,
        )
        let rendered = @browser_markdown.render_markdown(
          markdown,
          options~,
          target=hover_contents,
        )
        render_disposables.push(rendered.dispose)
        hover_contents.set_attribute(
          "class",
          hover_contents_class(rendered.has_code_block),
        )
      }
    }
    markdown_hover.append_child(hover_contents.as_node())
    row_contents.append_child(markdown_hover.as_node())
  }
  row.append_child(row_contents.as_node())
  row
}

///|
/// Monaco's async code-block callback lifts the normal hover max-width cap
/// after a fenced block went through editor tokenization.
fn hover_contents_class(has_code_block : Bool) -> String {
  if has_code_block {
    "hover-contents code-hover-contents"
  } else {
    "hover-contents"
  }
}

///|
fn append_hover_plaintext(parent : @rdom.Element, text : String) -> Unit {
  let document = @rdom.document()
  let plaintext = document.create_element("div")
  plaintext.set_attribute("class", "hover-plaintext")
  plaintext.append_child(document.create_text_node(text).as_node())
  parent.append_child(plaintext.as_node())
}

///|
fn standard_hover_row(text : String) -> @rdom.Element {
  let document = @rdom.document()
  let row = document.create_element("div")
  row.set_attribute("class", "hover-row")
  let row_contents = document.create_element("div")
  row_contents.set_attribute("class", "hover-row-contents")
  let markdown_hover = document.create_element("div")
  markdown_hover.set_attribute("class", "markdown-hover")
  let hover_contents = document.create_element("div")
  hover_contents.set_attribute("class", "hover-contents")
  append_hover_plaintext(hover_contents, text)
  markdown_hover.append_child(hover_contents.as_node())
  row_contents.append_child(markdown_hover.as_node())
  row.append_child(row_contents.as_node())
  row
}

///|
/// Marker rows remain ordinary retained DOM and keep the existing diagnostic
/// copy affordance. Text nodes and attribute writes replace manual escaping.
fn marker_hover_row(text : String) -> @rdom.Element {
  let document = @rdom.document()
  let row = document.create_element("div")
  row.set_attribute("class", "hover-row hover-row-with-copy")
  let marker = document.create_element("div")
  marker.set_attribute("class", "marker hover-contents")
  marker.append_child(document.create_text_node(text).as_node())
  let copy = document.create_element("button")
  copy.set_attribute("type", "button")
  copy.set_attribute("class", "hover-copy-button")
  copy.set_attribute("aria-label", "Copy")
  copy.set_attribute("data-hover-copy", text)
  let icon = document.create_element("span")
  icon.set_attribute("class", "codicon codicon-copy")
  icon.set_attribute("aria-hidden", "true")
  copy.append_child(icon.as_node())
  row.append_child(marker.as_node())
  row.append_child(copy.as_node())
  row
}

///|
/// Monaco `_render` (`contentHoverWidget.ts:314-322`): swap in the rendered
/// hover, write its contents, lay out, then force a synchronous editor render
/// so the widget does not really render at a stale position. (`_updateFont` is
/// N-A: the viewer's hover font comes from `hover.css`.)
fn ContentHoverWidget::render_rendered_hover(
  self : ContentHoverWidget,
  rendered_hover : RenderedContentHover,
) -> Unit {
  let hover_rows = render_hover_rows(
    rendered_hover.parts,
    rendered_hover.language_id,
  )
  self.set_rendered_hover(Some(rendered_hover), Some(hover_rows))
  hover_rows.mount_into(self.scrollable.content()) |> ignore
  self.handle_contents_changed()
  // Simply force a synchronous render on the editor
  // such that the widget does not really render with left = '0px'
  (self.host.render_now)()
}

///|
/// Monaco `show` (`contentHoverWidget.ts:336-362`): render, derive the
/// position preference from the freshly measured box, then lay out again (the
/// source's post-render second layout; the accessible-view hint and
/// keyboard-focus arms are N-A).
pub fn ContentHoverWidget::show(
  self : ContentHoverWidget,
  rendered_hover : RenderedContentHover,
) -> Unit {
  self.render_rendered_hover(rendered_hover)
  let widget_height = self.hover.get_bounding_client_rect().get_height()
  self.position_preference = Some(
    self.find_position_preference(
      widget_height,
      rendered_hover.show_at_position,
    ),
  )
  // See https://github.com/microsoft/vscode/issues/140339
  // TODO: Doing a second layout of the hover after force rendering the editor
  self.handle_contents_changed()
}

///|
/// Monaco `hide` (`contentHoverWidget.ts:364-377`): clear the rendered state
/// (the `hidden` class hides the container), reposition (the widget's
/// `get_position()` is now `None`, so the content-widget layer hides the
/// node), and give focus back to the editor when the hover had stolen it.
pub fn ContentHoverWidget::hide(self : ContentHoverWidget) -> Unit {
  guard self.rendered_hover is Some(_) else { return }
  let hover_stole_focus = @base_browser.element_contains_active_element(
    self.wrapper,
  )
  self.set_rendered_hover(None, None)
  (self.host.layout_content_widget)()
  if hover_stole_focus {
    (self.host.focus_editor)()
  }
}

///|
/// Releases the current shared-Markdown render lifetime and the retained
/// scrollbar resource. Root Viewer teardown calls this before dropping its
/// persistent widget reference. Idempotence follows both owned resources.
pub fn ContentHoverWidget::dispose(self : ContentHoverWidget) -> Unit {
  match self.hover_rows {
    Some(rows) => rows.dispose()
    None => ()
  }
  self.hover_rows = None
  self.scrollable.dispose()
}

///|
/// Monaco `handleContentsChanged` (`contentHoverWidget.ts:406-428`): release
/// the constraints and re-establish the max dimensions
/// (`_removeConstraintsRenderNormally`), measure the naturally rendered
/// contents, lock the explicit dimensions on the widget and its wrapper
/// (`_resizableNode.layout`), re-derive the position preference from the
/// measured box, then reposition and rescan the scrollbar
/// (`_layoutContentWidget`).
fn ContentHoverWidget::handle_contents_changed(
  self : ContentHoverWidget,
) -> Unit {
  self.remove_constraints_render_normally()
  let contents_dom_node = self.scrollable.content()
  let mut height = contents_dom_node.get_bounding_client_rect().get_height()
  let mut width = contents_dom_node.get_bounding_client_rect().get_width() + 2.0
  self.resizable_layout(height, width)
  self.set_hover_widget_dimensions(px(width), px(height))
  height = contents_dom_node.get_bounding_client_rect().get_height()
  width = contents_dom_node.get_bounding_client_rect().get_width()
  // `_contentWidth` / `_updateMinimumWidth` feed the resize sashes' min-size
  // bookkeeping — unported.
  self.resizable_layout(height, width)
  match self.rendered_hover {
    Some(rendered) => {
      let widget_height = self.hover.get_bounding_client_rect().get_height()
      self.position_preference = Some(
        self.find_position_preference(widget_height, rendered.show_at_position),
      )
    }
    None => ()
  }
  self.layout_content_widget()
}

///|
/// Monaco `_removeConstraintsRenderNormally` (`contentHoverWidget.ts:379-385`):
/// spread the wrapper over the whole editor box and let the (absolutely
/// positioned, shrink-to-fit) hover render at its natural size under only the
/// max-dimension caps, so the follow-up measurement is unconstrained by the
/// widget's previous box or anchor position.
fn ContentHoverWidget::remove_constraints_render_normally(
  self : ContentHoverWidget,
) -> Unit {
  // Added because otherwise the initial size of the hover content is smaller
  // than should be
  let layout_info = self.host.root.get_bounding_client_rect()
  self.resizable_layout(layout_info.get_height(), layout_info.get_width())
  self.set_hover_widget_dimensions("auto", "auto")
  self.update_max_dimensions()
}

///|
/// Monaco `_updateMaxDimensions` (`contentHoverWidget.ts:307-312`): the hover
/// may grow to two thirds of the editor width but never has a cap below
/// 750×250 — the floor that keeps the hover readable in a narrow editor
/// (`_lastDimensions` is resize-sash memory, unported).
fn ContentHoverWidget::update_max_dimensions(self : ContentHoverWidget) -> Unit {
  let layout_info = self.host.root.get_bounding_client_rect()
  let height = hover_max_height(layout_info.get_height())
  let width = hover_max_width(layout_info.get_width())
  self.set_hover_widget_max_dimensions(px(width), px(height))
}

///|
/// Monaco `_updateMaxDimensions`' width arm:
/// `Math.max(this._editor.getLayoutInfo().width * 0.66, 750)`.
fn hover_max_width(editor_width : Double) -> Double {
  (editor_width * 0.66).max(750.0)
}

///|
/// Monaco `_updateMaxDimensions`' height arm:
/// `Math.max(this._editor.getLayoutInfo().height / 4, 250)`.
fn hover_max_height(editor_height : Double) -> Double {
  (editor_height / 4.0).max(250.0)
}

///|
/// Monaco `_setHoverWidgetDimensions` (`contentHoverWidget.ts:135-140`) over
/// `_applyDimensions`: explicit `width`/`height` on the container
/// (`.monaco-hover`), the scrollable element, and the contents.
fn ContentHoverWidget::set_hover_widget_dimensions(
  self : ContentHoverWidget,
  width : String,
  height : String,
) -> Unit {
  apply_dimensions(self.hover, width, height)
  apply_dimensions(self.scrollable.wrapper(), width, height)
  apply_dimensions(self.scrollable.content(), width, height)
  self.layout_content_widget()
}

///|
fn apply_dimensions(
  container : @rdom.Element,
  width : String,
  height : String,
) -> Unit {
  @base_browser.set_style_property(container, "width", width)
  @base_browser.set_style_property(container, "height", height)
}

///|
/// Monaco `_setHoverWidgetMaxDimensions` (`contentHoverWidget.ts:149-155`)
/// over `_applyMaxDimensions`, plus the `--vscode-hover-maxWidth` custom
/// property `.markdown-hover .hover-contents` reads (`hover.css`).
fn ContentHoverWidget::set_hover_widget_max_dimensions(
  self : ContentHoverWidget,
  width : String,
  height : String,
) -> Unit {
  apply_max_dimensions(self.scrollable.content(), width, height)
  apply_max_dimensions(self.scrollable.wrapper(), width, height)
  apply_max_dimensions(self.hover, width, height)
  @base_browser.set_style_property(self.hover, "--vscode-hover-maxWidth", width)
  self.layout_content_widget()
}

///|
fn apply_max_dimensions(
  container : @rdom.Element,
  width : String,
  height : String,
) -> Unit {
  @base_browser.set_style_property(container, "max-width", width)
  @base_browser.set_style_property(container, "max-height", height)
}

///|
/// Monaco `this._resizableNode.layout(height, width)` (`resizable.ts`
/// `ResizableHTMLElement.layout`): explicit `height`/`width` on the wrapper.
/// Property-level writes coexist with the content-widget layer's positioning
/// writes on the same node.
fn ContentHoverWidget::resizable_layout(
  self : ContentHoverWidget,
  height : Double,
  width : Double,
) -> Unit {
  @base_browser.set_style_property(self.wrapper, "height", px(height))
  @base_browser.set_style_property(self.wrapper, "width", px(width))
}

///|
/// Monaco `_layoutContentWidget` (`contentHoverWidget.ts:302-305`):
/// reposition through the editor, then `this._hover.onContentsChanged()` —
/// rescan the widget's scroll box.
fn ContentHoverWidget::layout_content_widget(self : ContentHoverWidget) -> Unit {
  (self.host.layout_content_widget)()
  self.scrollable.update_from_native_content()
}

///|
fn px(value : Double) -> String {
  "\{value.to_string()}px"
}

///|
/// The hover's `DomScrollableElement` wheel path: the same `_onMouseWheel`
/// delta pipeline as the editor, at `resolveOptions` defaults, applied to the
/// widget's native scroll offsets.
fn ContentHoverWidget::handle_wheel(
  self : ContentHoverWidget,
  wheel : @rdom.WheelEvent,
) -> Unit {
  let (delta_left, delta_top) = @scrollbar.mouse_wheel_scroll_deltas(
    StandardWheelEvent(wheel),
    alt_key=wheel.get_alt_key(),
    shift_key=wheel.get_shift_key(),
  )
  self.scrollable.native_scroll_by(delta_left~, delta_top~)
}

///|
/// Monaco `contentHoverWidget.ts` `HORIZONTAL_SCROLLING_BY`: the fixed pixel
/// step the hover scrolls left/right per arrow press.
let hover_horizontal_scrolling_by : Double = 30.0

///|
/// Monaco `ContentHoverWidget.scrollUp`: `scrollTop -= fontInfo.lineHeight`.
pub fn ContentHoverWidget::scroll_up(self : ContentHoverWidget) -> Unit {
  self.scrollable.native_scroll_by(delta_top=-(self.host.line_height)())
}

///|
/// Monaco `ContentHoverWidget.scrollDown`: `scrollTop += fontInfo.lineHeight`.
pub fn ContentHoverWidget::scroll_down(self : ContentHoverWidget) -> Unit {
  self.scrollable.native_scroll_by(delta_top=(self.host.line_height)())
}

///|
/// Monaco `ContentHoverWidget.scrollLeft`: `scrollLeft -= HORIZONTAL_SCROLLING_BY`.
pub fn ContentHoverWidget::scroll_left(self : ContentHoverWidget) -> Unit {
  self.scrollable.native_scroll_by(delta_left=-hover_horizontal_scrolling_by)
}

///|
/// Monaco `ContentHoverWidget.scrollRight`: `scrollLeft += HORIZONTAL_SCROLLING_BY`.
pub fn ContentHoverWidget::scroll_right(self : ContentHoverWidget) -> Unit {
  self.scrollable.native_scroll_by(delta_left=hover_horizontal_scrolling_by)
}

///|
/// Monaco `ContentHoverWidget.pageUp`: `scrollTop -= getScrollDimensions().height`
/// (the visible content height).
pub fn ContentHoverWidget::page_up(self : ContentHoverWidget) -> Unit {
  self.scrollable.native_scroll_by(
    delta_top=-self.scrollable.native_page_delta(),
  )
}

///|
/// Monaco `ContentHoverWidget.pageDown`: `scrollTop += getScrollDimensions().height`.
pub fn ContentHoverWidget::page_down(self : ContentHoverWidget) -> Unit {
  self.scrollable.native_scroll_by(
    delta_top=self.scrollable.native_page_delta(),
  )
}

///|
/// Monaco `ContentHoverWidget.goToTop`: `scrollTop = 0`.
pub fn ContentHoverWidget::go_to_top(self : ContentHoverWidget) -> Unit {
  self.scrollable.native_scroll_to(vertical=true, 0.0)
}

///|
/// Monaco `ContentHoverWidget.goToBottom`: `scrollTop = getScrollDimensions().scrollHeight`.
pub fn ContentHoverWidget::go_to_bottom(self : ContentHoverWidget) -> Unit {
  self.scrollable.native_scroll_to(
    vertical=true,
    self.scrollable.content().get_scroll_height(),
  )
}

///|
/// Monaco `resizableContentWidget.ts` `TOP_HEIGHT` / `BOTTOM_HEIGHT`: the margin
/// kept between the hover and the editor top / bottom edge when measuring how
/// much vertical room each side has.
let hover_top_height : Double = 30.0

///|
let hover_bottom_height : Double = 24.0

///|
/// `editor.hover.above`'s VS Code default: prefer rendering the hover above the
/// anchor line when it fits there.
let hover_prefer_above_default : Bool = true

///|
/// Monaco `ResizableContentWidget._availableVerticalSpaceAbove`
/// (`resizableContentWidget.ts:64-72`): the page-space room above the anchor
/// line, `editorBox.top + mouseBox.top - TOP_HEIGHT`. Page-based because the
/// overflowing hover may extend past the editor box.
fn hover_available_space_above(
  editor_box_top : Double,
  mouse_box_top : Double,
) -> Double {
  editor_box_top + mouse_box_top - hover_top_height
}

///|
/// Monaco `ResizableContentWidget._availableVerticalSpaceBelow`
/// (`resizableContentWidget.ts:74-84`): the page-space room below the anchor
/// line, `bodyBox.height - mouseBottom - BOTTOM_HEIGHT`.
fn hover_available_space_below(
  body_height : Double,
  editor_box_top : Double,
  mouse_box_top : Double,
  mouse_box_height : Double,
) -> Double {
  body_height -
  (editor_box_top + mouse_box_top + mouse_box_height) -
  hover_bottom_height
}

///|
fn ContentHoverWidget::available_vertical_space_above(
  self : ContentHoverWidget,
  position : @base_common.Position,
) -> Double {
  hover_available_space_above(
    dom_node_page_top(self.host.root),
    (self.host.scrolled_visible_position_top)(position),
  )
}

///|
fn ContentHoverWidget::available_vertical_space_below(
  self : ContentHoverWidget,
  position : @base_common.Position,
) -> Double {
  hover_available_space_below(
    body_client_height(self.host.root),
    dom_node_page_top(self.host.root),
    (self.host.scrolled_visible_position_top)(position),
    (self.host.line_height)(),
  )
}

///|
/// Monaco `ResizableContentWidget._findPositionPreference`
/// (`resizableContentWidget.ts:86-105`); the sash-enable arms are N-A.
fn ContentHoverWidget::find_position_preference(
  self : ContentHoverWidget,
  widget_height : Double,
  show_at_position : @base_common.Position,
) -> @view.ContentWidgetPositionPreference {
  let space_above = self.available_vertical_space_above(show_at_position)
  let space_below = self.available_vertical_space_below(show_at_position)
  if hover_prefer_above(
      widget_height, space_above, space_below, hover_prefer_above_default,
    ) {
    Above
  } else {
    Below
  }
}

///|
/// Monaco `ResizableContentWidget._findPositionPreference`'s fit math: choose
/// ABOVE vs BELOW. Returns `true` for ABOVE. `prefer_above` mirrors
/// `editor.hover.above`.
fn hover_prefer_above(
  widget_height : Double,
  space_above : Double,
  space_below : Double,
  prefer_above : Bool,
) -> Bool {
  let max_above = space_above.min(widget_height)
  let max_below = space_below.min(widget_height)
  let max_height = max_above.max(max_below).min(widget_height)
  let height = widget_height.min(max_height)
  if prefer_above {
    height <= max_above
  } else {
    !(height <= max_below)
  }
}

///|
/// Monaco `dom.getDomNodePagePosition(editorDomNode).top`: client-rect top
/// plus the window's vertical scroll.
fn dom_node_page_top(node : @rdom.Element) -> Double {
  node.get_bounding_client_rect().get_top() +
  @rdom.window().scroll_y().to_double()
}

///|
extern "js" fn handle_hover_copy_click(event : @rdom.Event) -> Bool =
  #| (event) => {
  #|   const target = event?.target;
  #|   const button = target?.closest?.(".hover-copy-button");
  #|   if (!button || !button.closest?.('.monaco-resizable-hover')) {
  #|     return false;
  #|   }
  #|   const row = button.closest(".hover-row");
  #|   const content = button.getAttribute("data-hover-copy") || row?.innerText || "";
  #|   try {
  #|     const write = globalThis.navigator?.clipboard?.writeText;
  #|     if (typeof write === "function") {
  #|       write.call(globalThis.navigator.clipboard, content).catch(() => {});
  #|     }
  #|   } catch {
  #|   }
  #|   return true;
  #| }

///|
extern "js" fn hover_mousedown_is_interactive(event : @rdom.Event) -> Bool =
  #| (event) => {
  #|   const target = event?.target;
  #|   return Boolean(target?.closest?.("button, a, input, textarea, select, [role='button'], .hover-copy-button"));
  #| }

///|
/// Monaco `dom.getClientArea(editorDomNode.ownerDocument.body).height`
/// (`resizableContentWidget.ts:81`).
extern "js" fn body_client_height(node : @rdom.Element) -> Double =
  #| (node) => node.ownerDocument.body.clientHeight
