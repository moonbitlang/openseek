///|
fn view_event_test_name(event : ViewEvent) -> String {
  match event {
    ViewConfigurationChanged(_) => "configuration"
    ViewCursorStateChanged(_) => "cursor"
    ViewDecorationsChanged => "decorations"
    ViewFlushed => "flushed"
    ViewFocusChanged(_) => "focus"
    ViewLineMappingChanged => "line-mapping"
    ViewScrollChanged(_) => "scroll"
    ViewTokensChanged(_) => "tokens"
    ViewZonesChanged => "zones"
  }
}

///|
fn view_event_test_batch_name(events : Array[ViewEvent]) -> String {
  let result = StringBuilder()
  for index, event in events {
    if index > 0 {
      result.write_char('|')
    }
    result.write_string(view_event_test_name(event))
  }
  result.to_string()
}

///|
fn emit_dispatcher_test_batch(
  dispatcher : ViewEventDispatcher,
  events : Array[ViewEvent],
) -> Unit {
  let collector = dispatcher.begin()
  for event in events {
    collector.emit(event)
  }
  dispatcher.end()
}

///|
test "consumed payloads retain independent flags and array identity" {
  let configuration = ViewConfigurationChangedEvent::from_changed_options([
    LayoutInfo,
    FontInfo,
    LayoutInfo,
  ])
  assert_eq(configuration.changed_options.length(), 2)
  assert_true(configuration.has_changed(LayoutInfo))
  assert_true(configuration.has_changed(FontInfo))
  assert_false(configuration.has_changed(RenderWhitespace))

  let scroll = ViewScrollChangedEvent::ViewScrollChangedEvent(
    700.0, true, false, false, true,
  )
  assert_true(scroll.scroll_width == 700.0)
  assert_true(scroll.scroll_width_changed)
  assert_false(scroll.scroll_left_changed)
  assert_false(scroll.scroll_height_changed)
  assert_true(scroll.scroll_top_changed)

  let ranges = [ViewTokenChangeRange::ViewTokenChangeRange(4, 6)]
  let tokens = ViewTokensChangedEvent::ViewTokensChangedEvent(ranges)
  ranges.push(ViewTokenChangeRange(9, 10))
  assert_eq(tokens.ranges.length(), 2)
  assert_eq(tokens.ranges[0].from_line_number, 4)
  assert_eq(tokens.ranges[0].to_line_number, 6)

  let selection = @core.Selection(Position(1, 1), Position(1, 1))
  let selections = [selection]
  let cursor = ViewCursorStateChangedEvent::ViewCursorStateChangedEvent(
    selections,
  )
  selections.push(Selection(Position(2, 1), Position(2, 1)))
  assert_eq(cursor.selections.length(), 2)
}

///|
test "dispatcher gives every handler a whole batch before reentrant FIFO batch" {
  let deliveries : Array[String] = []
  let holder : Ref[ViewEventDispatcher?] = { val: None, }
  let did_reenter = Ref(false)
  let dispatcher = ViewEventDispatcher::ViewEventDispatcher(events => {
    let batch = view_event_test_batch_name(events)
    deliveries.push("h1:\{batch}")
    if !did_reenter.val {
      did_reenter.val = true
      match holder.val {
        Some(dispatcher) =>
          emit_dispatcher_test_batch(dispatcher, [
            ViewFocusChanged(ViewFocusChangedEvent(false)),
            ViewLineMappingChanged,
          ])
        None => abort("dispatcher test holder missing")
      }
    }
    deliveries.push("h2:\{batch}")
  })
  holder.val = Some(dispatcher)
  emit_dispatcher_test_batch(dispatcher, [ViewFlushed, ViewZonesChanged])
  assert_eq(deliveries.length(), 4)
  assert_eq(deliveries[0], "h1:flushed|zones")
  assert_eq(deliveries[1], "h2:flushed|zones")
  assert_eq(deliveries[2], "h1:focus|line-mapping")
  assert_eq(deliveries[3], "h2:focus|line-mapping")
  assert_false(dispatcher.consuming)
  assert_true(dispatcher.pending_view_events is None)
}

///|
test "ViewZones outgoing continuation waits for reentrant internal delivery" {
  let deliveries : Array[String] = []
  let holder : Ref[ViewEventDispatcher?] = { val: None, }
  let dispatcher = ViewEventDispatcher::ViewEventDispatcher(events => {
    let batch = view_event_test_batch_name(events)
    deliveries.push("h1:\{batch}")
    if batch == "line-mapping" {
      match holder.val {
        Some(dispatcher) =>
          dispatcher.emit_view_event_then(ViewZonesChanged, () => {
            deliveries.push("outgoing")
          })
        None => abort("dispatcher test holder missing")
      }
    }
    deliveries.push("h2:\{batch}")
  })
  holder.val = Some(dispatcher)
  dispatcher.emit_view_event(ViewLineMappingChanged)
  assert_true(
    deliveries ==
    ["h1:line-mapping", "h2:line-mapping", "h1:zones", "h2:zones", "outgoing"],
  )
  assert_eq(dispatcher.after_view_events.length(), 0)
  assert_false(dispatcher.consuming)
}

///|
test "nested begin shares one collector and only outer end flushes" {
  let deliveries : Array[String] = []
  let dispatcher = ViewEventDispatcher::ViewEventDispatcher(events => {
    deliveries.push(view_event_test_batch_name(events))
  })
  let outer = dispatcher.begin()
  outer.emit(ViewFocusChanged(ViewFocusChangedEvent(true)))
  let inner = dispatcher.begin()
  inner.emit(ViewFocusChanged(ViewFocusChangedEvent(false)))
  dispatcher.end()
  assert_eq(deliveries.length(), 0)
  outer.emit(ViewZonesChanged)
  dispatcher.end()
  assert_eq(deliveries.length(), 1)
  assert_eq(deliveries[0], "focus|focus|zones")
  assert_eq(dispatcher.collector_depth, 0)
  assert_true(dispatcher.collector is None)
}

///|
test "hidden-area batch delivers mapping events before recovery scroll" {
  let deliveries : Array[String] = []
  let dispatcher = ViewEventDispatcher::ViewEventDispatcher(events => {
    deliveries.push(view_event_test_batch_name(events))
  })
  let collector = dispatcher.begin()
  collector.emit(ViewFlushed)
  collector.emit(ViewLineMappingChanged)
  collector.emit(ViewDecorationsChanged)
  // The layout's synchronous recovery listener enters through the ordinary
  // dispatcher API while the ViewModel-owned outer collector is still open.
  dispatcher.emit_view_event(
    ViewScrollChanged(ViewScrollChangedEvent(400.0, false, false, false, true)),
  )
  assert_eq(deliveries.length(), 0)
  dispatcher.end()
  assert_true(deliveries == ["flushed|line-mapping|decorations|scroll"])
}

///|
fn view_event_handler_test_name(handler : ViewEventHandlerHandle) -> String {
  match handler {
    ViewLinesHandler(_) => "view-lines"
    ViewZonesHandler(_) => "view-zones"
    ContentViewOverlaysHandler(_) => "content-overlays"
    MarginViewOverlaysHandler(_) => "margin-overlays"
    ContentWidgetsHandler(_) => "content-widgets"
    ViewCursorsHandler(_) => "view-cursors"
    OverlayWidgetsHandler(_) => "overlay-widgets"
    EditorScrollbarHandler(_) => "editor-scrollbar"
  }
}

///|
fn view_event_handler_test_dirty(handler : ViewEventHandlerHandle) -> Bool {
  match handler {
    ViewLinesHandler(part) => part.should_render
    ViewZonesHandler(part) => part.should_render()
    ContentViewOverlaysHandler(part) => part.should_render
    MarginViewOverlaysHandler(part) => part.should_render
    ContentWidgetsHandler(part) => part.should_render
    ViewCursorsHandler(part) => part.should_render
    OverlayWidgetsHandler(part) => part.should_render
    EditorScrollbarHandler(part) => part.should_render
  }
}

///|
fn view_part_handle_test_name(part : ViewPartHandle) -> String {
  match part {
    ViewZonesPart(_) => "view-zones"
    ContentViewOverlaysPart(_) => "content-overlays"
    MarginViewOverlaysPart(_) => "margin-overlays"
    ContentWidgetsPart(_) => "content-widgets"
    ViewCursorsPart(_) => "view-cursors"
    OverlayWidgetsPart(_) => "overlay-widgets"
    EditorScrollbarPart(_) => "editor-scrollbar"
  }
}

///|
test "View dispatcher retains eight handlers in source order and gives each the full batch" {
  install_view_lifecycle_test_browser()
  let view = View::View()
  let handler_names = view.view_event_handlers.map(view_event_handler_test_name)
  assert_true(
    handler_names ==
    [
      "view-lines", "view-zones", "content-overlays", "margin-overlays", "content-widgets",
      "view-cursors", "overlay-widgets", "editor-scrollbar",
    ],
  )
  assert_true(
    view.view_parts.map(view_part_handle_test_name) ==
    [
      "view-zones", "content-overlays", "margin-overlays", "content-widgets", "view-cursors",
      "overlay-widgets", "editor-scrollbar",
    ],
  )
  view.view_lines.should_render = false
  for part in view.view_parts {
    part.on_did_render()
    assert_false(part.should_render())
  }
  view.view_cursors.render_data = Some({
    top: 0.0,
    left: 0.0,
    padding_left: 0.0,
    width: 2.0,
    height: 20,
  })
  view.begin_view_event_batch()
  view.emit_view_event(ViewFocusChanged(ViewFocusChangedEvent(true)))
  view.emit_view_event(
    ViewConfigurationChanged(
      ViewConfigurationChangedEvent::from_changed_options([]),
    ),
  )
  view.end_view_event_batch()
  for handler in view.view_event_handlers {
    assert_true(view_event_handler_test_dirty(handler))
  }
  // The first event is not lost after a later event dirties every handler:
  // focus writes the prepared cursor's visible style immediately.
  assert_true(
    view_event_test_attribute(view.view_cursors.cursor, "style") !=
    "display:none",
  )
  view.dispose()
  restore_view_lifecycle_test_browser()
}

///|
priv struct CountingViewEventHandler {
  mut dirty : Bool
  mut force_count : Int
  seen : Array[String]
}

///|
fn CountingViewEventHandler::on_view_event(
  self : CountingViewEventHandler,
  event : ViewEvent,
) -> Bool {
  self.seen.push(view_event_test_name(event))
  match event {
    ViewFlushed | ViewZonesChanged => true
    _ => false
  }
}

///|
fn CountingViewEventHandler::force_should_render(
  self : CountingViewEventHandler,
) -> Unit {
  self.dirty = true
  self.force_count += 1
}

///|
test "view-event batch visits every event and accumulates sticky dirty once" {
  let handler : CountingViewEventHandler = {
    dirty: false,
    force_count: 0,
    seen: [],
  }
  handle_view_event_batch(
    [
      ViewFocusChanged(ViewFocusChangedEvent(true)),
      ViewFlushed,
      ViewZonesChanged,
    ],
    event => handler.on_view_event(event),
    () => handler.force_should_render(),
  )
  assert_eq(handler.seen.length(), 3)
  assert_true(handler.dirty)
  assert_eq(handler.force_count, 1)
  handler.dirty = false
  handle_view_event_batch(
    [
      ViewFocusChanged(ViewFocusChangedEvent(true)),
      ViewFocusChanged(ViewFocusChangedEvent(false)),
    ],
    event => handler.on_view_event(event),
    () => handler.force_should_render(),
  )
  assert_false(handler.dirty)
  assert_eq(handler.force_count, 1)
}

///|
fn dynamic_overlay_handle_test_name(
  overlay : DynamicViewOverlayHandle,
) -> String {
  match overlay {
    CurrentLine(_) => "current-line"
    Selections(_) => "selections"
    Decorations(_) => "decorations"
    CurrentLineMargin(_) => "current-line-margin"
    MarginDecorations(_) => "margin-decorations"
    LinesDecorations(_) => "lines-decorations"
    LineNumbers(_) => "line-numbers"
  }
}

///|
fn DynamicViewOverlayHandle::set_test_render_result(
  self : DynamicViewOverlayHandle,
  result : Array[String],
) -> Unit {
  match self {
    CurrentLine(overlay) => overlay.render_result = result
    Selections(overlay) => overlay.render_result = result
    Decorations(overlay) => overlay.render_result = result
    CurrentLineMargin(overlay) => overlay.render_result = result
    MarginDecorations(overlay) => overlay.render_result = result
    LinesDecorations(overlay) => overlay.render_result = result
    LineNumbers(overlay) => overlay.render_result = result
  }
}

///|
test "dynamic overlay subsets preserve registration order and line slicing" {
  install_view_lifecycle_test_browser()
  let view = View::View()
  let content = view.content_view_overlays
  let margin = view.margin_view_overlays
  assert_true(
    content.overlays.dynamic_overlays.map(dynamic_overlay_handle_test_name) ==
    ["current-line", "selections", "decorations"],
  )
  assert_true(
    margin.overlays.dynamic_overlays.map(dynamic_overlay_handle_test_name) ==
    [
      "current-line-margin", "margin-decorations", "lines-decorations", "line-numbers",
    ],
  )
  content.overlays.dynamic_overlays[0].set_test_render_result(["c10", "c11"])
  content.overlays.dynamic_overlays[1].set_test_render_result(["s10", "s11"])
  content.overlays.dynamic_overlays[2].set_test_render_result(["d10", "d11"])
  margin.overlays.dynamic_overlays[0].set_test_render_result(["m10", "m11"])
  margin.overlays.dynamic_overlays[1].set_test_render_result(["d10", "d11"])
  margin.overlays.dynamic_overlays[2].set_test_render_result(["g10", "g11"])
  margin.overlays.dynamic_overlays[3].set_test_render_result(["n10", "n11"])
  assert_eq(
    [
      for overlay in content.overlays.dynamic_overlays => overlay.render(10, 11)
    ].join("|"),
    "c11|s11|d11",
  )
  assert_eq(
    [
      for overlay in margin.overlays.dynamic_overlays => overlay.render(10, 10)
    ].join("|"),
    "m10|d10|g10|n10",
  )
  for overlay in content.overlays.dynamic_overlays {
    assert_eq(overlay.render(10, 9), "")
    assert_eq(overlay.render(10, 12), "")
  }
  view.dispose()
  restore_view_lifecycle_test_browser()
}

///|
extern "js" fn view_event_test_attribute(
  element : @rdom.Element,
  name : String,
) -> String =
  #| (element, name) => element.getAttribute(name) || ""

///|
extern "js" fn view_event_test_attribute_write_count(
  element : @rdom.Element,
  name : String,
) -> Int =
  #| (element, name) => element.attributeWriteCount?.get(name) ?? 0

///|
extern "js" fn view_event_test_style_width(element : @rdom.Element) -> String =
  #| (element) => String(element.style.width || "")

///|
extern "js" fn view_event_test_style_top(element : @rdom.Element) -> String =
  #| (element) => String(element.style.top || "")

///|
extern "js" fn view_event_test_has_parent(
  child : @rdom.Element,
  parent : @rdom.Element,
) -> Bool =
  #| (child, parent) => child.parentNode === parent

///|
extern "js" fn view_event_test_same_node(
  left : @rdom.Element,
  right : @rdom.Element,
) -> Bool =
  #| (left, right) => left === right

///|
extern "js" fn view_event_test_reset_dom_metrics() -> Unit =
  #| () => {
  #|   globalThis.__moonbitViewerScrollMetrics = {
  #|     styleWrites: 0,
  #|     viewLayer: {},
  #|   };
  #| }

///|
extern "js" fn view_event_test_style_write_count() -> Int =
  #| () => globalThis.__moonbitViewerScrollMetrics?.styleWrites ?? 0

///|
extern "js" fn view_event_test_view_layer_mutation_count() -> Int =
  #| () => Object.values(globalThis.__moonbitViewerScrollMetrics?.viewLayer ?? {})
  #|   .reduce((total, value) => total + Number(value), 0)

///|
extern "js" fn view_event_test_clear_dom_metrics() -> Unit =
  #| () => { delete globalThis.__moonbitViewerScrollMetrics; }

///|
fn view_event_test_line_input(
  content : String,
  render_whitespace : @editor_api.RenderWhitespace,
  space_width? : Double = 7.2,
  middot_width? : Double = 7.2,
  wsmiddot_width? : Double = 7.2,
  use_monospace_optimizations? : Bool = true,
) -> @view_layout.RenderLineInput {
  @view_layout.RenderLineInput::from_view_line(
    {
      min_column: 1,
      max_column: content.length() + 1,
      content,
      continues_with_wrapped_line: false,
      contains_rtl: false,
      is_basic_ascii: true,
      tokens: [],
      inline_decorations: [],
      tab_size: 2,
      start_visible_column: 0,
      text_direction: LTR,
      has_variable_fonts: false,
    },
    space_width~,
    middot_width~,
    wsmiddot_width~,
    use_monospace_optimizations~,
    render_whitespace~,
  )
}

///|
fn view_event_test_retained_line(
  parent : @rdom.Element,
  input : @view_layout.RenderLineInput,
) -> (ViewLine, @rdom.Element) raise {
  let line = ViewLine::ViewLine()
  assert_true(line.render_line(1, input, 0, 20, StringBuilder()))
  let node = @rdom.document().create_element("div")
  parent.append_child(node.as_node())
  line.set_dom_node(node)
  (line, node)
}

///|
test "ViewLines propagates changed token decoration option and selection invalidators per retained row" {
  install_view_lifecycle_test_browser()
  let view = View::View()
  let lines = view.view_lines
  let live_configuration = Ref(ViewLinesConfiguration::ViewLinesConfiguration())
  lines.install_live_configuration_reader(() => live_configuration.val)
  let parent = lines.get_dom_node()
  let input_a = view_event_test_line_input("alpha", None)
  let input_b = view_event_test_line_input("bravo", Selection)
  let input_c = view_event_test_line_input("charlie", None)
  let (line_a, _) = view_event_test_retained_line(parent, input_a)
  let (line_b, _) = view_event_test_retained_line(parent, input_b)
  let (line_c, _) = view_event_test_retained_line(parent, input_c)
  lines.window = { start: 10, end: 13, }
  lines.lines = [line_a, line_b, line_c]

  // Nested VisibleLinesCollection predicates stay independently observable:
  // layout info does not flush, scroll is top-only, and zones always dirty.
  assert_false(lines.on_visible_configuration_changed(false))
  assert_true(lines.on_visible_configuration_changed(true))
  assert_eq(lines.lines.length(), 3)
  assert_false(lines.on_visible_scroll_changed(false))
  assert_true(lines.on_visible_scroll_changed(true))
  assert_true(lines.on_visible_zones_changed())

  // Token ranges clip inclusively and invalidate only retained endpoints.
  assert_false(
    view_lines_on_view_event(
      lines,
      ViewTokensChanged(ViewTokensChangedEvent([ViewTokenChangeRange(1, 9)])),
    ),
  )
  assert_true(
    view_lines_on_view_event(
      lines,
      ViewTokensChanged(ViewTokensChangedEvent([ViewTokenChangeRange(9, 10)])),
    ),
  )
  let input_a2 = view_event_test_line_input("alpha tokenized", None)
  assert_true(line_a.render_line(10, input_a2, 0, 20, StringBuilder()))
  assert_false(
    line_c.render_line(
      12,
      view_event_test_line_input("charlie ignored", None),
      40,
      20,
      StringBuilder(),
    ),
  )

  // Decorations visit every retained row. Consume the sticky bits with the
  // unchanged normalized inputs, proving DOM replacement is still gated.
  assert_true(view_lines_on_view_event(lines, ViewDecorationsChanged))
  assert_false(line_a.render_line(10, input_a2, 0, 20, StringBuilder()))
  assert_false(line_b.render_line(11, input_b, 20, 20, StringBuilder()))
  assert_false(line_c.render_line(12, input_c, 40, 20, StringBuilder()))

  // Unrelated configuration still dirties the outer ViewPart, but exact
  // reduced ViewLineOptions equality does not latch retained rows.
  assert_true(
    view_lines_on_view_event(
      lines,
      ViewConfigurationChanged(
        ViewConfigurationChangedEvent::from_changed_options([ReadOnly]),
      ),
    ),
  )
  let input_a3 = view_event_test_line_input("alpha option", None)
  assert_false(line_a.render_line(10, input_a3, 0, 20, StringBuilder()))
  live_configuration.val = ViewLinesConfiguration(render_whitespace=All)
  assert_true(
    view_lines_on_view_event(
      lines,
      ViewConfigurationChanged(
        ViewConfigurationChangedEvent::from_changed_options([RenderWhitespace]),
      ),
    ),
  )
  assert_true(line_a.render_line(10, input_a3, 0, 20, StringBuilder()))
  assert_false(line_b.render_line(11, input_b, 20, 20, StringBuilder()))
  assert_false(line_c.render_line(12, input_c, 40, 20, StringBuilder()))

  // Cache-only changes are reread in source order but do not masquerade as a
  // `ViewLineOptions.equals` change.
  live_configuration.val = ViewLinesConfiguration(
    typical_halfwidth_character_width=8.0,
    is_viewport_wrapping=true,
    can_use_layer_hinting=false,
    render_whitespace=All,
  )
  assert_true(
    view_lines_on_view_event(
      lines,
      ViewConfigurationChanged(
        ViewConfigurationChangedEvent::from_changed_options([
          FontInfo,
          WrappingInfo,
        ]),
      ),
    ),
  )
  assert_true(lines.typical_halfwidth_character_width == 8.0)
  assert_true(lines.is_viewport_wrapping)
  assert_false(lines.can_use_layer_hinting)
  assert_false(
    line_a.render_line(
      10,
      view_event_test_line_input("cache-only ignored", None),
      0,
      20,
      StringBuilder(),
    ),
  )

  // Line height belongs to the retained option identity and therefore latches
  // every row even when the event payload is otherwise minimal.
  live_configuration.val = ViewLinesConfiguration(
    line_height=21,
    typical_halfwidth_character_width=8.0,
    is_viewport_wrapping=true,
    can_use_layer_hinting=false,
    render_whitespace=All,
  )
  assert_true(
    view_lines_on_view_event(
      lines,
      ViewConfigurationChanged(
        ViewConfigurationChangedEvent::from_changed_options([LineHeight]),
      ),
    ),
  )
  assert_eq(lines.view_line_options.line_height, 21)
  let line_height_input = view_event_test_line_input("line-height", None)
  assert_true(line_a.render_line(10, line_height_input, 0, 21, StringBuilder()))
  assert_false(line_b.render_line(11, input_b, 21, 21, StringBuilder()))
  assert_false(line_c.render_line(12, input_c, 42, 21, StringBuilder()))

  // Selection walks all rows but returns true only from a row whose own last
  // rendered input used Selection whitespace.
  assert_true(view_lines_on_view_event(lines, view_event_test_cursor([])))
  assert_false(
    line_a.render_line(
      10,
      view_event_test_line_input("alpha selection ignored", None),
      0,
      20,
      StringBuilder(),
    ),
  )
  assert_true(
    line_b.render_line(
      11,
      view_event_test_line_input("bravo selection", Selection),
      20,
      20,
      StringBuilder(),
    ),
  )

  let width_only = ViewScrollChangedEvent::ViewScrollChangedEvent(
    420.0, true, false, false, false,
  )
  assert_false(view_lines_on_view_event(lines, ViewScrollChanged(width_only)))
  assert_eq(view_event_test_style_width(parent), "420px")
  view.dispose()
  restore_view_lifecycle_test_browser()
}

///|
test "ViewLines option equality catches same-space font render axes" {
  install_view_lifecycle_test_browser()
  let view = View::View()
  let lines = view.view_lines
  let live_configuration = Ref(ViewLinesConfiguration::ViewLinesConfiguration())
  lines.install_live_configuration_reader(() => live_configuration.val)
  let original_input = view_event_test_line_input("font axes", None)
  let (line, _) = view_event_test_retained_line(
    lines.get_dom_node(),
    original_input,
  )
  lines.window = { start: 1, end: 2, }
  lines.lines = [line]
  live_configuration.val = ViewLinesConfiguration(
    space_width=7.2,
    middot_width=8.0,
    wsmiddot_width=9.0,
    use_monospace_optimizations=false,
  )
  assert_true(
    view_lines_on_view_event(
      lines,
      ViewConfigurationChanged(
        ViewConfigurationChangedEvent::from_changed_options([FontInfo]),
      ),
    ),
  )
  assert_true(
    line.render_line(
      1,
      view_event_test_line_input(
        "font axes",
        None,
        space_width=7.2,
        middot_width=8.0,
        wsmiddot_width=9.0,
        use_monospace_optimizations=false,
      ),
      0,
      20,
      StringBuilder(),
    ),
  )
  view.dispose()
  restore_view_lifecycle_test_browser()
}

///|
test "ViewLines empty flush resets to one and defers ordinary DOM replacement" {
  install_view_lifecycle_test_browser()
  let view = View::View()
  let lines = view.view_lines
  let parent = lines.get_dom_node()
  assert_eq(lines.window.start, 1)
  assert_eq(lines.window.end, 1)
  assert_eq(lines.lines.length(), 0)
  let input = view_event_test_line_input("stale", None)
  let (stale_line, stale_node) = view_event_test_retained_line(parent, input)
  lines.window = { start: 50, end: 51, }
  lines.lines = [stale_line]

  assert_true(view_lines_on_view_event(lines, ViewFlushed))
  assert_eq(lines.lines.length(), 0)
  assert_eq(lines.window.start, 1)
  assert_eq(lines.window.end, 1)
  assert_true(view_event_test_has_parent(stale_node, parent))
  assert_false(
    view_lines_on_view_event(
      lines,
      ViewTokensChanged(ViewTokensChangedEvent([ViewTokenChangeRange(1, 1)])),
    ),
  )
  assert_eq(lines.window.start, 1)
  assert_eq(lines.window.end, 1)
  view.dispose()
  restore_view_lifecycle_test_browser()
}

///|
test "cursor state then focus uses new selection shape and focus returns false" {
  install_view_lifecycle_test_browser()
  let cursors = ViewCursors::ViewCursors(@rdom.document())
  cursors.render_data = Some(prepare_cursor_render_data(10.0, 0, 18, 1.0))
  cursors.last_position = Some(Position(1, 1))
  cursors.last_rendered_position = Some(Position(1, 1))
  let selection = @core.Selection(Position(1, 1), Position(1, 2))
  assert_true(
    view_cursors_on_view_event(
      cursors,
      ViewCursorStateChanged(ViewCursorStateChangedEvent([selection])),
    ),
  )
  assert_false(cursors.selection_is_empty)
  let painted = cursors.get_last_render_data()
  assert_eq(painted.length(), 1)
  assert_true(painted[0].position == Position(1, 1))
  assert_true(cursors.last_position == Some(Position(1, 2)))
  assert_eq(
    view_event_test_attribute(cursors.dom_node, "class"),
    "cursors-layer has-selection cursor-line-style cursor-solid",
  )
  let class_writes = view_event_test_attribute_write_count(
    cursors.dom_node,
    "class",
  )
  let moved_selection = @core.Selection(Position(2, 1), Position(2, 2))
  assert_true(
    view_cursors_on_view_event(
      cursors,
      ViewCursorStateChanged(ViewCursorStateChangedEvent([moved_selection])),
    ),
  )
  assert_eq(
    view_event_test_attribute_write_count(cursors.dom_node, "class"),
    class_writes,
  )
  assert_false(
    view_cursors_on_view_event(
      cursors,
      ViewFocusChanged(ViewFocusChangedEvent(true)),
    ),
  )
  assert_eq(
    view_event_test_attribute(cursors.dom_node, "class"),
    "cursors-layer has-selection cursor-line-style cursor-solid",
  )
  assert_true(
    view_event_test_attribute(cursors.cursor, "style").contains(
      "visibility:inherit",
    ),
  )
  cursors.should_render = false
  ViewEventHandlerHandle::handle_view_events(ViewCursorsHandler(cursors), [
    ViewFocusChanged(ViewFocusChangedEvent(false)),
  ])
  assert_false(cursors.should_render)
  assert_true(
    view_event_test_attribute(cursors.cursor, "style").contains(
      "visibility:hidden",
    ),
  )
  restore_view_lifecycle_test_browser()
}

///|
fn view_event_test_configuration() -> ViewEvent {
  ViewConfigurationChanged(
    ViewConfigurationChangedEvent::from_changed_options([]),
  )
}

///|
fn view_event_test_scroll(
  width : Bool,
  left : Bool,
  height : Bool,
  top : Bool,
) -> ViewEvent {
  ViewScrollChanged(ViewScrollChangedEvent(700.0, width, left, height, top))
}

///|
fn view_event_test_cursor(selections : Array[@core.Selection]) -> ViewEvent {
  ViewCursorStateChanged(ViewCursorStateChangedEvent(selections))
}

///|
priv struct ViewEventContentWidget {
  dom_node : @rdom.Element
}

///|
fn ViewEventContentWidget::content_widget_handle(
  self : ViewEventContentWidget,
) -> ContentWidgetHandle {
  ContentWidgetHandle(() => "event-widget", () => self.dom_node, () => {
    Some({
      position: Some(Position(2, 3)),
      secondary_position: None,
      preference: Some([Below]),
      position_affinity: None,
    })
  })
}

///|
test "ContentWidgets handlers refresh layout and reproject every mapping event" {
  install_view_lifecycle_test_browser()
  let view = View::View()
  let widgets = view.content_widgets
  let layout_reads = Ref(0)
  let projections = Ref(0)
  widgets.install_live_view_context(
    () => {
      layout_reads.val += 1
      (14.0, 420.0)
    },
    position => {
      projections.val += 1
      Some(position)
    },
  )
  let widget : ViewEventContentWidget = {
    dom_node: @rdom.document().create_element("div"),
  }
  widgets.add_widget(widget.content_widget_handle())
  widgets.set_widget_position(widget.content_widget_handle())
  assert_eq(layout_reads.val, 1)
  assert_eq(projections.val, 1)

  // Outer Configuration always invalidates. Only its exact LayoutInfo bit is
  // forwarded to the retained widgets' cache-refresh branch.
  assert_true(
    content_widgets_on_view_event(
      widgets,
      ViewConfigurationChanged(
        ViewConfigurationChangedEvent::from_changed_options([FontInfo]),
      ),
    ),
  )
  assert_eq(layout_reads.val, 1)
  assert_true(
    content_widgets_on_view_event(
      widgets,
      ViewConfigurationChanged(
        ViewConfigurationChangedEvent::from_changed_options([LayoutInfo]),
      ),
    ),
  )
  assert_eq(layout_reads.val, 2)

  projections.val = 0
  assert_true(content_widgets_on_view_event(widgets, ViewLineMappingChanged))
  assert_eq(projections.val, 1)
  view.dispose()
  restore_view_lifecycle_test_browser()
}

///|
test "ContentWidgets and ViewZones source handler matrices" {
  install_view_lifecycle_test_browser()
  let view = View::View()
  let widgets = view.content_widgets
  assert_true(content_widgets_on_view_event(widgets, ViewFlushed))
  assert_true(
    content_widgets_on_view_event(widgets, view_event_test_configuration()),
  )
  assert_true(content_widgets_on_view_event(widgets, ViewDecorationsChanged))
  assert_true(content_widgets_on_view_event(widgets, ViewLineMappingChanged))
  assert_true(
    content_widgets_on_view_event(
      widgets,
      view_event_test_scroll(false, false, false, false),
    ),
  )
  assert_true(content_widgets_on_view_event(widgets, ViewZonesChanged))
  assert_false(
    content_widgets_on_view_event(widgets, view_event_test_cursor([])),
  )
  assert_false(
    content_widgets_on_view_event(
      widgets,
      ViewTokensChanged(ViewTokensChangedEvent([])),
    ),
  )
  assert_false(
    content_widgets_on_view_event(
      widgets,
      ViewFocusChanged(ViewFocusChangedEvent(true)),
    ),
  )

  let zones = view.view_zones
  assert_true(view_zones_on_view_event(zones, view_event_test_configuration()))
  // `viewZones.ts:122-124` returns the exact
  // `_recomputeWhitespacesProps()` result. With an empty zone registry there
  // is no changed whitespace, so the source handler is not dirty.
  assert_false(view_zones_on_view_event(zones, ViewLineMappingChanged))
  assert_true(
    view_zones_on_view_event(
      zones,
      view_event_test_scroll(true, false, false, false),
    ),
  )
  assert_true(
    view_zones_on_view_event(
      zones,
      view_event_test_scroll(false, false, false, true),
    ),
  )
  assert_false(
    view_zones_on_view_event(
      zones,
      view_event_test_scroll(false, true, false, false),
    ),
  )
  assert_false(
    view_zones_on_view_event(
      zones,
      view_event_test_scroll(false, false, true, false),
    ),
  )
  assert_true(view_zones_on_view_event(zones, ViewZonesChanged))
  assert_false(view_zones_on_view_event(zones, ViewFlushed))
  view.dispose()
  restore_view_lifecycle_test_browser()
}

///|
test "overlay aggregates, OverlayWidgets, and EditorScrollbar handler matrix" {
  install_view_lifecycle_test_browser()
  let view = View::View()
  let content = view.content_view_overlays
  let margin = view.margin_view_overlays
  for
    overlays in [
      ContentViewOverlaysHandler(content),
      MarginViewOverlaysHandler(margin),
    ] {
    assert_true(ViewEventHandlerHandle::on_view_event(overlays, ViewFlushed))
    assert_true(
      ViewEventHandlerHandle::on_view_event(
        overlays,
        view_event_test_configuration(),
      ),
    )
    assert_true(
      ViewEventHandlerHandle::on_view_event(overlays, ViewDecorationsChanged),
    )
    assert_true(
      ViewEventHandlerHandle::on_view_event(overlays, ViewLineMappingChanged),
    )
    assert_true(
      ViewEventHandlerHandle::on_view_event(
        overlays,
        ViewTokensChanged(ViewTokensChangedEvent([ViewTokenChangeRange(1, 1)])),
      ),
    )
    assert_true(
      ViewEventHandlerHandle::on_view_event(
        overlays,
        view_event_test_cursor([]),
      ),
    )
    assert_true(
      ViewEventHandlerHandle::on_view_event(
        overlays,
        ViewFocusChanged(ViewFocusChangedEvent(true)),
      ),
    )
    assert_true(
      ViewEventHandlerHandle::on_view_event(overlays, ViewZonesChanged),
    )
    // Base `ViewOverlays.onScrollChanged` always invalidates the retained
    // visible rows.  Each independent flag therefore reaches both grouped
    // aggregates without being conflated.
    assert_true(
      ViewEventHandlerHandle::on_view_event(
        overlays,
        view_event_test_scroll(true, false, false, false),
      ),
    )
    assert_true(
      ViewEventHandlerHandle::on_view_event(
        overlays,
        view_event_test_scroll(false, true, false, false),
      ),
    )
    assert_true(
      ViewEventHandlerHandle::on_view_event(
        overlays,
        view_event_test_scroll(false, false, true, false),
      ),
    )
    assert_true(
      ViewEventHandlerHandle::on_view_event(
        overlays,
        view_event_test_scroll(false, false, false, true),
      ),
    )
  }

  let overlay_widgets = view.overlay_widgets
  assert_true(
    overlay_widgets_on_view_event(
      overlay_widgets,
      view_event_test_configuration(),
    ),
  )
  assert_true(
    overlay_widgets_on_view_event(
      overlay_widgets,
      view_event_test_scroll(true, false, false, false),
    ),
  )
  assert_true(
    overlay_widgets_on_view_event(
      overlay_widgets,
      view_event_test_scroll(false, false, true, false),
    ),
  )
  assert_false(
    overlay_widgets_on_view_event(
      overlay_widgets,
      view_event_test_scroll(false, true, false, false),
    ),
  )
  assert_false(
    overlay_widgets_on_view_event(
      overlay_widgets,
      view_event_test_scroll(false, false, false, true),
    ),
  )
  assert_false(overlay_widgets_on_view_event(overlay_widgets, ViewFlushed))

  let scrollbar = view.editor_scrollbar
  assert_true(
    editor_scrollbar_on_view_event(scrollbar, view_event_test_configuration()),
  )
  assert_true(
    editor_scrollbar_on_view_event(
      scrollbar,
      view_event_test_scroll(false, false, false, false),
    ),
  )
  assert_false(editor_scrollbar_on_view_event(scrollbar, ViewFlushed))
  view.dispose()
  restore_view_lifecycle_test_browser()
}

///|
test "ViewLines and ViewCursors cover four scroll flags and token endpoints" {
  install_view_lifecycle_test_browser()
  let view = View::View()
  let lines = view.view_lines
  lines.window = { start: 10, end: 13, }
  lines.lines = [ViewLine(), ViewLine(), ViewLine()]
  assert_false(
    view_lines_on_view_event(
      lines,
      view_event_test_scroll(true, false, false, false),
    ),
  )
  assert_true(
    view_lines_on_view_event(
      lines,
      view_event_test_scroll(false, true, false, false),
    ),
  )
  assert_false(
    view_lines_on_view_event(
      lines,
      view_event_test_scroll(false, false, true, false),
    ),
  )
  assert_true(
    view_lines_on_view_event(
      lines,
      view_event_test_scroll(false, false, false, true),
    ),
  )
  assert_false(
    view_lines_on_view_event(
      lines,
      ViewTokensChanged(
        ViewTokensChangedEvent([
          ViewTokenChangeRange(1, 9),
          ViewTokenChangeRange(13, 20),
        ]),
      ),
    ),
  )
  assert_true(
    view_lines_on_view_event(
      lines,
      ViewTokensChanged(
        ViewTokensChangedEvent([
          ViewTokenChangeRange(1, 9),
          ViewTokenChangeRange(12, 20),
        ]),
      ),
    ),
  )
  assert_true(
    view_lines_on_view_event(
      lines,
      ViewTokensChanged(ViewTokensChangedEvent([ViewTokenChangeRange(10, 10)])),
    ),
  )

  let cursors = view.view_cursors
  cursors.last_position = Some(Position(5, 2))
  assert_false(
    view_cursors_on_view_event(
      cursors,
      ViewTokensChanged(
        ViewTokensChangedEvent([
          ViewTokenChangeRange(1, 4),
          ViewTokenChangeRange(6, 9),
        ]),
      ),
    ),
  )
  assert_true(
    view_cursors_on_view_event(
      cursors,
      ViewTokensChanged(
        ViewTokensChangedEvent([
          ViewTokenChangeRange(1, 4),
          ViewTokenChangeRange(5, 5),
        ]),
      ),
    ),
  )
  assert_true(
    view_cursors_on_view_event(
      cursors,
      ViewTokensChanged(ViewTokensChangedEvent([ViewTokenChangeRange(5, 8)])),
    ),
  )
  assert_true(
    view_cursors_on_view_event(
      cursors,
      view_event_test_scroll(true, false, false, false),
    ),
  )
  assert_true(
    view_cursors_on_view_event(
      cursors,
      view_event_test_scroll(false, true, false, false),
    ),
  )
  assert_true(
    view_cursors_on_view_event(
      cursors,
      view_event_test_scroll(false, false, true, false),
    ),
  )
  assert_true(
    view_cursors_on_view_event(
      cursors,
      view_event_test_scroll(false, false, false, true),
    ),
  )
  view.dispose()
  restore_view_lifecycle_test_browser()
}

///|
test "current-line predicate ignores same-line column moves but tracks emptiness" {
  let state = CurrentLineHighlightState::CurrentLineHighlightState()
  let collapsed_line_3_column_1 = @core.Selection(
    Position(3, 1),
    Position(3, 1),
  )
  assert_true(state.on_cursor_state_changed([collapsed_line_3_column_1]))
  let collapsed_line_3_column_9 = @core.Selection(
    Position(3, 9),
    Position(3, 9),
  )
  assert_false(state.on_cursor_state_changed([collapsed_line_3_column_9]))
  assert_true(state.selections[0] == collapsed_line_3_column_9)
  let selected_on_line_3 = @core.Selection(Position(3, 2), Position(3, 9))
  assert_true(state.on_cursor_state_changed([selected_on_line_3]))
  assert_false(state.selection_is_empty)
  let collapsed_line_4 = @core.Selection(Position(4, 1), Position(4, 1))
  assert_true(
    state.on_cursor_state_changed([
      collapsed_line_4, collapsed_line_3_column_9, collapsed_line_4,
    ]),
  )
  assert_true(state.cursor_line_numbers == [3, 4])
  assert_true(state.selection_is_empty)
  assert_false(
    state.on_cursor_state_changed([collapsed_line_3_column_9, collapsed_line_4]),
  )

  let configuration : Ref[
    (@editor_api.RenderLineHighlight, Bool, Bool, Double, Double),
  ] = Ref((Line, false, false, 10.0, 100.0))
  state.install_configuration_reader(() => configuration.val)
  assert_false(state.on_focus_changed(true))
  assert_false(state.focused)
  configuration.val = (All, true, true, 41.0, 520.0)
  state.on_configuration_changed()
  assert_true(state.render_line_highlight == All)
  assert_true(state.render_line_highlight_only_when_focus)
  assert_true(state.word_wrap)
  assert_true(state.content_left == 41.0)
  assert_true(state.content_width == 520.0)
  assert_true(state.on_focus_changed(true))
  assert_true(state.focused)
  configuration.val = (Gutter, false, false, 42.0, 530.0)
  state.on_configuration_changed()
  assert_false(state.on_focus_changed(false))
  assert_true(state.focused)
  assert_true(
    current_line_scroll_changed(
      match view_event_test_scroll(true, false, false, false) {
        ViewScrollChanged(event) => event
        _ => abort("scroll test helper returned non-scroll event")
      },
    ),
  )
  assert_false(
    current_line_scroll_changed(
      match view_event_test_scroll(false, true, true, false) {
        ViewScrollChanged(event) => event
        _ => abort("scroll test helper returned non-scroll event")
      },
    ),
  )
  assert_true(
    current_line_scroll_changed(
      match view_event_test_scroll(false, false, false, true) {
        ViewScrollChanged(event) => event
        _ => abort("scroll test helper returned non-scroll event")
      },
    ),
  )
}

///|
fn view_event_test_overlay_render_context(
  view_model : @view_model.ViewModel,
  layout : @view_layout.ViewLayout,
  view_lines : ViewLines,
  cursor_column : Int,
) -> (RenderingContext, RestrictedRenderingContext) {
  let selection = @core.Selection(
    Position(1, cursor_column),
    Position(1, cursor_column),
  )
  let input : ViewRenderInput = {
    window: { start: 1, end: 2, },
    view_model,
    layout,
    selection_view_range: None,
    view_selection: Some(selection),
    // Deliberately disagree with the retained layout caches. Render must use
    // contentLeft=40/contentWidth=120 installed below, not these frame facts.
    gutter_width: 99.0,
    line_decorations_width: 10.0,
    space_width: 8.0,
    typical_fullwidth_character_width: 16.0,
    // Deliberately false after the retained focus event has stored true.
    editor_has_focus: false,
    word_wrap: false,
    render_line_highlight: Line,
    render_line_highlight_only_when_focus: false,
    show_unused: true,
    show_deprecated: true,
  }
  let view_context : ViewContext = {
    measure_line_selection: (_line, _start, _end) => [],
    measure_line_decorations: (_line, _start, _end) => [],
    offset_for_column: (_line, _column) => 0.0,
    model_position_to_view_position: position => position,
  }
  let rendering = RenderingContext::from_viewport(
    view_context,
    input,
    view_lines,
    RenderingContext::viewport_from_input(input),
  )
  let restricted : RestrictedRenderingContext = {
    input: rendering.input,
    viewport: rendering.viewport,
    gutter_width: rendering.gutter_width,
    position: rendering.position,
    dimensions: {
      width: 80.0,
      scroll_width: 80.0,
      height: 20.0,
      // Exercise MarginViewOverlays' exact `Math.min(..., 1000000)` cap.
      scroll_height: 2000000.0,
    },
    margin_transform: rendering.margin_transform(),
  }
  (rendering, restricted)
}

///|
test "View renders text before prepare and completes all prepares before writes" {
  install_view_lifecycle_test_browser()
  let model = @model.TextModel(
    @base_common.Uri::file("/view-lifecycle-order-test.mbt"),
    "view-lifecycle-order-test.mbt",
    "moonbit",
    1,
    "rev-1",
    "alpha",
  )
  let view_model = @view_model.ViewModel(model)
  let layout = @view_layout.ViewLayout(line_height=20, line_count=1)
  layout.set_viewport_size(width=80.0, height=20.0) |> ignore
  layout.set_content_width(80.0) |> ignore
  let view = View::View()
  let (retained_line, _) = view_event_test_retained_line(
    view.view_lines.get_dom_node(),
    view_event_test_line_input("alpha", None),
  )
  view.view_lines.window = { start: 1, end: 2, }
  view.view_lines.lines = [retained_line]
  for part in view.view_parts {
    part.on_did_render()
  }
  view.view_lines.should_render = true
  view.view_zones.force_should_render()
  view.view_cursors.should_render = true
  let cursor_prepare_seen = Ref(false)
  let text_was_complete = Ref(false)
  let ordinary_write_was_pending = Ref(false)
  let view_context : ViewContext = {
    measure_line_selection: (_line, _start, _end) => [],
    measure_line_decorations: (_line, _start, _end) => [],
    offset_for_column: (_line, _column) => {
      // Cursor prepare follows ViewZones prepare in the ordinary-part
      // order. Text completion is already visible, but no ordinary render
      // may have written its DOM yet.
      text_was_complete.val = !view.view_lines.should_render
      ordinary_write_was_pending.val = view_event_test_style_top(
          view.view_zones.margin_dom_node(),
        ) ==
        ""
      cursor_prepare_seen.val = true
      0.0
    },
    model_position_to_view_position: position => position,
  }
  let selection = @core.Selection(Position(1, 1), Position(1, 1))
  let input : ViewRenderInput = {
    window: { start: 1, end: 2, },
    view_model,
    layout,
    selection_view_range: None,
    view_selection: Some(selection),
    gutter_width: 0.0,
    line_decorations_width: 0.0,
    space_width: 8.0,
    typical_fullwidth_character_width: 16.0,
    editor_has_focus: true,
    word_wrap: false,
    render_line_highlight: Line,
    render_line_highlight_only_when_focus: false,
    show_unused: true,
    show_deprecated: true,
  }
  view.render(view_context, input)
  assert_true(cursor_prepare_seen.val)
  assert_true(text_was_complete.val)
  assert_true(ordinary_write_was_pending.val)
  assert_true(
    view_event_test_style_top(view.view_zones.margin_dom_node()) != "",
  )
  assert_false(view.view_lines.should_render)
  for part in view.view_parts {
    assert_false(part.should_render())
  }
  view.dispose()
  layout.dispose()
  view_model.dispose()
  model.dispose()
  restore_view_lifecycle_test_browser()
}

///|
fn view_event_test_seed_overlay_row(
  overlays : ViewOverlays,
  viewport : @view_layout.ViewportData,
) -> @rdom.Element raise {
  let line = ViewOverlayLine::ViewOverlayLine(overlays.dynamic_overlays)
  let builder = StringBuilder()
  assert_true(
    line.render_line(
      viewport.start_line_number,
      viewport.relative_vertical_offset[0],
      viewport.line_height,
      viewport,
      builder,
    ),
  )
  let node = @rdom.document().create_element("div")
  overlays.dom_node.element().append_child(node.as_node())
  line.set_dom_node(node)
  overlays.lines = [line]
  overlays.window = {
    start: viewport.start_line_number,
    end: viewport.end_line_number + 1,
  }
  node
}

///|
test "grouped same-line cursor over-render retains caches and performs zero DOM writes" {
  install_view_lifecycle_test_browser()
  let model = @model.TextModel(
    @base_common.Uri::file("/view-overlays-retained-cache-test.mbt"),
    "view-overlays-retained-cache-test.mbt",
    "moonbit",
    1,
    "rev-1",
    "alpha",
  )
  let view_model = @view_model.ViewModel(model)
  let layout = @view_layout.ViewLayout(line_height=20, line_count=1)
  layout.set_viewport_size(width=80.0, height=20.0) |> ignore
  layout.set_content_width(80.0) |> ignore
  let view = View::View()
  let configuration : Ref[
    (@editor_api.RenderLineHighlight, Bool, Bool, Double, Double),
  ] = Ref((Line, false, false, 40.0, 120.0))
  view.install_current_line_configuration_reader(() => configuration.val)
  let content = view.content_view_overlays
  let margin = view.margin_view_overlays
  let content_part = ContentViewOverlaysPart(content)
  let margin_part = MarginViewOverlaysPart(margin)
  let content_handler = ContentViewOverlaysHandler(content)
  let margin_handler = MarginViewOverlaysHandler(margin)
  assert_true(content.content_width == 120.0)
  assert_true(margin.content_left == 40.0)

  // Configuration updates every aggregate cache at event time, independently
  // from the nested current-line states.
  configuration.val = (All, true, true, 41.0, 121.0)
  assert_true(
    content_view_overlays_on_view_event(
      content,
      view_event_test_configuration(),
    ),
  )
  assert_true(
    margin_view_overlays_on_view_event(margin, view_event_test_configuration()),
  )
  assert_true(content.content_width == 121.0)
  assert_true(margin.content_left == 41.0)
  assert_true(content.current_line.state.content_width == 121.0)
  assert_true(margin.current_line_margin.state.content_left == 41.0)
  configuration.val = (Line, false, false, 40.0, 120.0)
  content_view_overlays_on_view_event(content, view_event_test_configuration())
  |> ignore
  margin_view_overlays_on_view_event(margin, view_event_test_configuration())
  |> ignore

  // Base ViewOverlays retains focus even though CurrentLineHighlight's
  // focus-only early return deliberately leaves its own `_focused` unchanged.
  let focus_event = ViewFocusChanged(ViewFocusChangedEvent(true))
  assert_true(content_view_overlays_on_view_event(content, focus_event))
  assert_true(margin_view_overlays_on_view_event(margin, focus_event))
  assert_true(content.overlays.is_focused)
  assert_true(margin.overlays.is_focused)
  assert_false(content.current_line.state.focused)
  assert_false(margin.current_line_margin.state.focused)

  let (first_rendering, first_restricted) = view_event_test_overlay_render_context(
    view_model,
    layout,
    view.view_lines,
    1,
  )
  content_part.prepare_render(first_rendering)
  margin_part.prepare_render(first_rendering)
  let content_row = view_event_test_seed_overlay_row(
    content.overlays,
    first_rendering.viewport,
  )
  let margin_row = view_event_test_seed_overlay_row(
    margin.overlays,
    first_rendering.viewport,
  )
  // Prime every retained DOM/style cache through the real ViewPart render.
  content_part.render(first_restricted)
  margin_part.render(first_restricted)
  content_part.on_did_render()
  margin_part.on_did_render()
  assert_eq(
    view_event_test_attribute(content.overlays.dom_node.element(), "class"),
    "view-overlays focused",
  )
  assert_eq(
    view_event_test_attribute(margin.overlays.dom_node.element(), "class"),
    "margin-view-overlays focused",
  )
  assert_eq(
    view_event_test_style_width(content.overlays.dom_node.element()),
    "120px",
  )
  assert_eq(view_event_test_attribute(margin.dom_node, "style"), "width:40px")
  assert_true(
    view_event_test_attribute(margin.overlays.dom_node.element(), "style").contains(
      "width:40px;height:1000000px",
    ),
  )

  let content_class_writes = view_event_test_attribute_write_count(
    content.overlays.dom_node.element(),
    "class",
  )
  let margin_class_writes = view_event_test_attribute_write_count(
    margin.overlays.dom_node.element(),
    "class",
  )
  let margin_style_writes = view_event_test_attribute_write_count(
    margin.overlays.dom_node.element(),
    "style",
  )
  let margin_outer_style_writes = view_event_test_attribute_write_count(
    margin.dom_node,
    "style",
  )
  view_event_test_reset_dom_metrics()

  // Absolute line numbers plus a current-line state whose line set and
  // emptiness are unchanged both return false in the pinned sources. The
  // grouped local handles intentionally still render; prove that bounded
  // overwork cannot replace a row or write any retained style/class.
  let column_only = @core.Selection(Position(1, 2), Position(1, 2))
  let cursor_event = view_event_test_cursor([column_only])
  content_handler.handle_view_events([cursor_event])
  margin_handler.handle_view_events([cursor_event])
  assert_true(content_part.should_render())
  assert_true(margin_part.should_render())
  assert_true(content.current_line.state.cursor_line_numbers == [1])
  assert_true(margin.current_line_margin.state.cursor_line_numbers == [1])
  assert_true(content.current_line.state.selection_is_empty)
  assert_true(margin.current_line_margin.state.selection_is_empty)
  let (second_rendering, second_restricted) = view_event_test_overlay_render_context(
    view_model,
    layout,
    view.view_lines,
    2,
  )
  content_part.prepare_render(second_rendering)
  margin_part.prepare_render(second_rendering)
  content_part.render(second_restricted)
  margin_part.render(second_restricted)
  content_part.on_did_render()
  margin_part.on_did_render()

  assert_eq(view_event_test_style_write_count(), 0)
  assert_eq(view_event_test_view_layer_mutation_count(), 0)
  assert_eq(
    view_event_test_attribute_write_count(
      content.overlays.dom_node.element(),
      "class",
    ),
    content_class_writes,
  )
  assert_eq(
    view_event_test_attribute_write_count(
      margin.overlays.dom_node.element(),
      "class",
    ),
    margin_class_writes,
  )
  assert_eq(
    view_event_test_attribute_write_count(
      margin.overlays.dom_node.element(),
      "style",
    ),
    margin_style_writes,
  )
  assert_eq(
    view_event_test_attribute_write_count(margin.dom_node, "style"),
    margin_outer_style_writes,
  )
  assert_true(
    view_event_test_same_node(
      content.overlays.lines[0].get_dom_node().unwrap(),
      content_row,
    ),
  )
  assert_true(
    view_event_test_same_node(
      margin.overlays.lines[0].get_dom_node().unwrap(),
      margin_row,
    ),
  )

  view_event_test_clear_dom_metrics()
  view.dispose()
  layout.dispose()
  view_model.dispose()
  model.dispose()
  restore_view_lifecycle_test_browser()
}
