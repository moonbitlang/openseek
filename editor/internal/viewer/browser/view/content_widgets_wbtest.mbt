///|
extern "js" fn install_content_widgets_test_browser() -> Unit =
  #| () => {
  #|   class TestElement extends EventTarget {
  #|     constructor(tag = "div", ownerDocument = null) {
  #|       super();
  #|       this.nodeType = 1;
  #|       this.nodeName = tag.toUpperCase();
  #|       this.ownerDocument = ownerDocument;
  #|       this.parentNode = null;
  #|       this.childNodes = [];
  #|       this.children = this.childNodes;
  #|       this.attributes = new Map();
  #|       this._rect = { left: 0, top: 0, width: 10, height: 10 };
  #|       this.style = {
  #|         _owner: this,
  #|         setProperty(name, value) {
  #|           this[name] = String(value);
  #|           const id = this._owner?.getAttribute?.("widgetId") || this._owner?.getAttribute?.("data-content-widget") || this._owner?.nodeName || "node";
  #|           globalThis.__contentWidgetEvents.push(`style:${id}:${name}:${String(value)}`);
  #|         },
  #|       };
  #|     }
  #|     setAttribute(name, value) { this.attributes.set(name, String(value)); }
  #|     getAttribute(name) { return this.attributes.get(name) ?? ""; }
  #|     removeAttribute(name) { this.attributes.delete(name); }
  #|     appendChild(child) {
  #|       this.childNodes.push(child);
  #|       child.parentNode = this;
  #|       return child;
  #|     }
  #|     removeChild(child) {
  #|       this.childNodes = this.childNodes.filter(item => item !== child);
  #|       this.children = this.childNodes;
  #|       child.parentNode = null;
  #|       return child;
  #|     }
  #|     contains(candidate) {
  #|       if (candidate === this) return true;
  #|       return this.childNodes.some(child => child.contains?.(candidate));
  #|     }
  #|     getBoundingClientRect() {
  #|       globalThis.__contentWidgetRectReads += 1;
  #|       const { left, top, width, height } = this._rect;
  #|       return {
  #|         x: left, y: top, left, top,
  #|         right: left + width, bottom: top + height, width, height,
  #|       };
  #|     }
  #|   }
  #|   const ownerDocument = new EventTarget();
  #|   ownerDocument.nodeType = 9;
  #|   ownerDocument.createElement = tag => new TestElement(tag, ownerDocument);
  #|   ownerDocument.body = new TestElement("body", ownerDocument);
  #|   ownerDocument.documentElement = new TestElement("html", ownerDocument);
  #|   ownerDocument.body.clientWidth = 900;
  #|   ownerDocument.body.clientHeight = 700;
  #|   ownerDocument.body.offsetWidth = 900;
  #|   ownerDocument.documentElement.offsetWidth = 950;
  #|   ownerDocument.defaultView = { innerWidth: 1000, innerHeight: 800, scrollX: 0, scrollY: 0, document: ownerDocument };
  #|   ownerDocument.activeElement = null;
  #|   globalThis.__ContentWidgetTestElement = TestElement;
  #|   globalThis.__contentWidgetEvents = [];
  #|   globalThis.__contentWidgetRectReads = 0;
  #|   globalThis.document = ownerDocument;
  #|   globalThis.window = ownerDocument.defaultView;
  #|   globalThis.Element = TestElement;
  #| }

///|
extern "js" fn content_widgets_test_make_document(
  has_default_view : Bool,
  inner_width : Double,
  scroll_x : Double,
  scroll_y : Double,
  document_element_width : Double,
  body_width : Double,
) -> @rdom.Document =
  #| (hasDefaultView, innerWidth, scrollX, scrollY, documentElementWidth, bodyWidth) => {
  #|   const TestElement = globalThis.__ContentWidgetTestElement;
  #|   const doc = new EventTarget();
  #|   doc.nodeType = 9;
  #|   doc.createElement = tag => new TestElement(tag, doc);
  #|   doc.body = new TestElement("body", doc);
  #|   doc.documentElement = new TestElement("html", doc);
  #|   doc.body.clientWidth = bodyWidth;
  #|   doc.body.clientHeight = 600;
  #|   doc.body.offsetWidth = bodyWidth;
  #|   doc.documentElement.offsetWidth = documentElementWidth;
  #|   doc.activeElement = null;
  #|   doc.defaultView = hasDefaultView ? { innerWidth, innerHeight: 700, scrollX, scrollY, document: doc } : null;
  #|   return doc;
  #| }

///|
extern "js" fn content_widgets_test_set_rect(
  element : @rdom.Element,
  left : Double,
  top : Double,
  width : Double,
  height : Double,
) -> Unit =
  #| (element, left, top, width, height) => { element._rect = { left, top, width, height }; }

///|
extern "js" fn content_widgets_test_set_active_element(
  document : @rdom.Document,
  element : @rdom.Element,
) -> Unit =
  #| (document, element) => { document.activeElement = element; }

///|
extern "js" fn content_widgets_test_clear_active_element(
  document : @rdom.Document,
) -> Unit =
  #| (document) => { document.activeElement = null; }

///|
extern "js" fn content_widgets_test_set_main_scroll(
  scroll_x : Double,
  scroll_y : Double,
) -> Unit =
  #| (scrollX, scrollY) => { globalThis.window.scrollX = scrollX; globalThis.window.scrollY = scrollY; }

///|
extern "js" fn content_widgets_test_with_ios_visual_viewport(
  document : @rdom.Document,
  width : Double,
  height : Double,
  callback : () -> Unit,
) -> Unit =
  #| (document, width, height, callback) => {
  #|   const globalNavigatorDescriptor = Object.getOwnPropertyDescriptor(globalThis, 'navigator');
  #|   let navigator = globalThis.navigator;
  #|   if (!navigator) {
  #|     navigator = {};
  #|     Object.defineProperty(globalThis, 'navigator', {
  #|       value: navigator,
  #|       configurable: true,
  #|     });
  #|   }
  #|   const userAgentDescriptor = Object.getOwnPropertyDescriptor(navigator, 'userAgent');
  #|   const touchDescriptor = Object.getOwnPropertyDescriptor(navigator, 'maxTouchPoints');
  #|   const viewportDescriptor = Object.getOwnPropertyDescriptor(document.defaultView, 'visualViewport');
  #|   Object.defineProperty(navigator, 'userAgent', {
  #|     value: 'Mozilla/5.0 (iPhone)',
  #|     configurable: true,
  #|   });
  #|   Object.defineProperty(navigator, 'maxTouchPoints', {
  #|     value: 5,
  #|     configurable: true,
  #|   });
  #|   Object.defineProperty(document.defaultView, 'visualViewport', {
  #|     value: { width, height },
  #|     configurable: true,
  #|   });
  #|   const restore = (target, name, descriptor) => {
  #|     if (descriptor) Object.defineProperty(target, name, descriptor);
  #|     else delete target[name];
  #|   };
  #|   try {
  #|     callback();
  #|   } finally {
  #|     restore(document.defaultView, 'visualViewport', viewportDescriptor);
  #|     restore(navigator, 'maxTouchPoints', touchDescriptor);
  #|     restore(navigator, 'userAgent', userAgentDescriptor);
  #|     if (!globalNavigatorDescriptor) delete globalThis.navigator;
  #|   }
  #| }

///|
extern "js" fn content_widgets_test_clear_events() -> Unit =
  #| () => { globalThis.__contentWidgetEvents = []; }

///|
extern "js" fn content_widgets_test_log_event(event : String) -> Unit =
  #| (event) => { globalThis.__contentWidgetEvents.push(String(event)); }

///|
extern "js" fn content_widgets_test_events() -> FixedArray[String] =
  #| () => globalThis.__contentWidgetEvents.slice()

///|
extern "js" fn content_widgets_test_clear_rect_reads() -> Unit =
  #| () => { globalThis.__contentWidgetRectReads = 0; }

///|
extern "js" fn content_widgets_test_rect_reads() -> Int =
  #| () => globalThis.__contentWidgetRectReads

///|
extern "js" fn content_widgets_test_style_property(
  element : @rdom.Element,
  name : String,
) -> String =
  #| (element, name) => String(element.style[name] || "")

///|
extern "js" fn content_widgets_test_attribute(
  element : @rdom.Element,
  name : String,
) -> String =
  #| (element, name) => String(element.getAttribute(name) || "")

///|
extern "js" fn content_widgets_test_parent_is(
  element : @rdom.Element,
  parent : @rdom.Element,
) -> Bool =
  #| (element, parent) => element.parentNode === parent

///|
priv struct TestContentWidget {
  id : String
  dom_node : @rdom.Element
  mut position : ContentWidgetPosition?
  allow_overflow : Bool
  use_display_none : Bool
  before_enabled : Bool
  mut before_dimension : ContentWidgetDimension?
  mut throw_before : Bool
  after_enabled : Bool
  throw_after : Bool
}

///|
priv struct GetterOrderWidget {
  dom_node : @rdom.Element
}

///|
fn GetterOrderWidget::content_widget_handle(
  self : GetterOrderWidget,
) -> ContentWidgetHandle {
  ContentWidgetHandle(
    () => {
      content_widgets_test_log_event("getter:id")
      "getter-order"
    },
    () => {
      content_widgets_test_log_event("getter:dom")
      self.dom_node
    },
    () => None,
  )
}

///|
priv suberror TestWidgetCallbackError {
  TestWidgetCallbackError
}

///|
fn TestContentWidget::before_render(
  self : TestContentWidget,
) -> ContentWidgetDimension? raise {
  content_widgets_test_log_event("before:\{self.id}")
  if self.throw_before {
    raise TestWidgetCallbackError
  }
  self.before_dimension
}

///|
fn TestContentWidget::after_render(
  self : TestContentWidget,
  position : ContentWidgetPositionPreference?,
  coordinate : ContentWidgetRenderedCoordinate?,
) -> Unit raise {
  content_widgets_test_log_event(
    "after:\{self.id}:\{callback_position_name(position)}:\{callback_coordinate_name(coordinate)}",
  )
  if self.throw_after {
    raise TestWidgetCallbackError
  }
  ()
}

///|
fn callback_position_name(
  position : ContentWidgetPositionPreference?,
) -> String {
  match position {
    Some(Above) => "above"
    Some(Below) => "below"
    Some(Exact) => "exact"
    None => "null"
  }
}

///|
fn TestContentWidget::content_widget_handle(
  self : TestContentWidget,
) -> ContentWidgetHandle {
  let before_render = if self.before_enabled {
    Some(() => self.before_render())
  } else {
    None
  }
  let after_render = if self.after_enabled {
    Some((position, coordinate) => self.after_render(position, coordinate))
  } else {
    None
  }
  ContentWidgetHandle::with_render_callbacks(
    () => self.id,
    () => self.dom_node,
    () => self.position,
    self.allow_overflow,
    self.use_display_none,
    before_render,
    after_render,
  )
}

///|
fn callback_coordinate_name(
  coordinate : ContentWidgetRenderedCoordinate?,
) -> String {
  match coordinate {
    Some(coordinate) =>
      "\{coordinate.top.to_string()},\{coordinate.left.to_string()}"
    None => "null"
  }
}

///|
fn new_test_content_widget(
  document : @rdom.Document,
  id : String,
  primary : @base_common.Position?,
  secondary : @base_common.Position?,
  allow_overflow? : Bool = false,
  use_display_none? : Bool = false,
  before_enabled? : Bool = false,
  after_enabled? : Bool = false,
  throw_after? : Bool = false,
) -> TestContentWidget {
  {
    id,
    dom_node: document.create_element("div"),
    position: Some({
      position: primary,
      secondary_position: secondary,
      preference: Some([Below]),
      position_affinity: None,
    }),
    allow_overflow,
    use_display_none,
    before_enabled,
    before_dimension: None,
    throw_before: false,
    after_enabled,
    throw_after,
  }
}

///|
test "constructor and add preserve container styles and overflow mount choice" {
  install_content_widgets_test_browser()
  let document = @rdom.document()
  let widgets = ContentWidgets::ContentWidgets(
    document,
    document.create_element("section"),
  )
  assert_eq(
    content_widgets_test_attribute(widgets.dom_node, "class"),
    "contentWidgets",
  )
  assert_eq(
    content_widgets_test_attribute(widgets.dom_node, "data-view-part"),
    "contentWidgets",
  )
  assert_eq(
    content_widgets_test_style_property(widgets.dom_node, "position"),
    "absolute",
  )
  assert_eq(content_widgets_test_style_property(widgets.dom_node, "top"), "0px")
  assert_eq(
    content_widgets_test_attribute(
      widgets.overflowing_content_widgets_dom_node,
      "class",
    ),
    "overflowingContentWidgets",
  )
  let normal = new_test_content_widget(document, "normal", None, None)
  let overflow = new_test_content_widget(
    document,
    "overflow",
    None,
    None,
    allow_overflow=true,
  )
  widgets.add_widget(normal.content_widget_handle())
  widgets.add_widget(overflow.content_widget_handle())
  assert_true(content_widgets_test_parent_is(normal.dom_node, widgets.dom_node))
  assert_true(
    content_widgets_test_parent_is(
      overflow.dom_node,
      widgets.overflowing_content_widgets_dom_node,
    ),
  )
  assert_eq(
    content_widgets_test_style_property(normal.dom_node, "position"),
    "absolute",
  )
  assert_eq(
    content_widgets_test_style_property(normal.dom_node, "display"),
    "none",
  )
  assert_eq(
    content_widgets_test_style_property(normal.dom_node, "visibility"),
    "hidden",
  )
  assert_eq(
    content_widgets_test_attribute(normal.dom_node, "widgetId"),
    "normal",
  )
}

///|
test "addWidget reads layout before handle getters in source constructor order" {
  install_content_widgets_test_browser()
  let document = @rdom.document()
  let widgets = ContentWidgets::ContentWidgets(
    document,
    document.create_element("section"),
  )
  widgets.install_live_view_context(
    () => {
      content_widgets_test_log_event("getter:layout")
      (0.0, 300.0)
    },
    position => Some(position),
  )
  let widget : GetterOrderWidget = { dom_node: document.create_element("div") }
  content_widgets_test_clear_events()
  widgets.add_widget(widget.content_widget_handle())
  let events = content_widgets_test_events()
  assert_true(events.length() >= 3)
  assert_eq(events[0], "getter:layout")
  assert_eq(events[1], "getter:dom")
  assert_eq(events[2], "getter:id")
}

///|
test "panic setWidgetPosition rejects an unknown widget id" {
  install_content_widgets_test_browser()
  let document = @rdom.document()
  let widgets = ContentWidgets::ContentWidgets(
    document,
    document.create_element("section"),
  )
  let unknown = new_test_content_widget(
    document,
    "unknown",
    Some(Position(1, 1)),
    None,
  )
  widgets.set_widget_position(unknown.content_widget_handle())
}

///|
test "configuration visits every retained widget and gates layout cache reads" {
  install_content_widgets_test_browser()
  let document = @rdom.document()
  let content_left = Ref(12.0)
  let content_width = Ref(240.0)
  let layout_reads = Ref(0)
  let widgets = ContentWidgets::ContentWidgets(
    document,
    document.create_element("section"),
  )
  widgets.install_live_view_context(
    () => {
      layout_reads.val += 1
      (content_left.val, content_width.val)
    },
    position => Some(position),
  )
  let first = new_test_content_widget(
    document,
    "first",
    Some(Position(1, 1)),
    None,
  )
  let second = new_test_content_widget(
    document,
    "second",
    Some(Position(1, 2)),
    None,
  )
  widgets.add_widget(first.content_widget_handle())
  widgets.set_widget_position(first.content_widget_handle())
  widgets.add_widget(second.content_widget_handle())
  widgets.set_widget_position(second.content_widget_handle())
  assert_eq(layout_reads.val, 2)
  let first_state = widgets.widgets["first"]
  let second_state = widgets.widgets["second"]
  assert_eq(first_state.content_left, 12.0)
  assert_eq(first_state.content_width, 240.0)
  assert_eq(first_state.max_width, 240.0)
  assert_eq(second_state.content_left, 12.0)
  assert_eq(second_state.content_width, 240.0)
  assert_eq(second_state.max_width, 240.0)

  // A non-layout configuration still delegates to both widgets, but their
  // source branch does not reread or mutate the layout caches.
  content_left.val = 30.0
  content_width.val = 500.0
  widgets.on_configuration_changed(false)
  assert_eq(layout_reads.val, 2)
  assert_eq(first_state.content_left, 12.0)
  assert_eq(first_state.content_width, 240.0)
  assert_eq(first_state.max_width, 240.0)
  assert_eq(second_state.content_left, 12.0)
  assert_eq(second_state.content_width, 240.0)
  assert_eq(second_state.max_width, 240.0)

  // The pre-text write phase only reapplies the retained maxWidth. It cannot
  // substitute for the source-time configuration branch by rereading layout.
  widgets.on_before_render_widgets(1, 1)
  widgets.prepare_render_widgets({
    vertical_offset_for_line: _ => 0.0,
    line_height_for_line: _ => 20.0,
    visible_range_for_position: position => {
      Some((position.column - 1).to_double() * 8.0)
    },
    typical_fullwidth_character_width: 16.0,
    scroll_top: 0.0,
    scroll_left: 0.0,
    viewport_width: 500.0,
    viewport_height: 200.0,
  })
  assert_eq(layout_reads.val, 2)
  assert_eq(first_state.max_width, 240.0)
  assert_eq(second_state.max_width, 240.0)

  // `layoutInfo` true visits every retained widget in key order; each reads
  // the live context and refreshes contentLeft/contentWidth/maxWidth.
  widgets.on_configuration_changed(true)
  assert_eq(layout_reads.val, 4)
  assert_eq(first_state.content_left, 30.0)
  assert_eq(first_state.content_width, 500.0)
  assert_eq(first_state.max_width, 500.0)
  assert_eq(second_state.content_left, 30.0)
  assert_eq(second_state.content_width, 500.0)
  assert_eq(second_state.max_width, 500.0)
  // Configuration refreshes the retained value; the source's following
  // onBeforeRender write applies that exact cache to the mounted node.
  assert_eq(
    content_widgets_test_style_property(first.dom_node, "max-width"),
    "240px",
  )
  widgets.on_before_render_widgets(1, 1)
  widgets.prepare_render_widgets({
    vertical_offset_for_line: _ => 0.0,
    line_height_for_line: _ => 20.0,
    visible_range_for_position: position => {
      Some((position.column - 1).to_double() * 8.0)
    },
    typical_fullwidth_character_width: 16.0,
    scroll_top: 0.0,
    scroll_left: 0.0,
    viewport_width: 500.0,
    viewport_height: 200.0,
  })
  assert_eq(
    content_widgets_test_style_property(first.dom_node, "max-width"),
    "500px",
  )
  assert_eq(
    content_widgets_test_style_property(second.dom_node, "max-width"),
    "500px",
  )
}

///|
test "onBefore distinguishes null and empty preference and includes viewport endpoints" {
  install_content_widgets_test_browser()
  let document = @rdom.document()
  let widgets = ContentWidgets::ContentWidgets(
    document,
    document.create_element("section"),
  )
  widgets.install_live_view_context(() => (0.0, 321.0), position => {
    Some(position)
  })
  let missing_anchor = new_test_content_widget(
    document,
    "missing-anchor",
    None,
    None,
  )
  let null_preference = new_test_content_widget(
    document,
    "null-preference",
    Some(Position(3, 1)),
    None,
  )
  null_preference.position = Some({
    position: Some(Position(3, 1)),
    secondary_position: None,
    preference: None,
    position_affinity: None,
  })
  let empty_preference = new_test_content_widget(
    document,
    "empty-preference",
    Some(Position(4, 1)),
    None,
  )
  empty_preference.position = Some({
    position: Some(Position(4, 1)),
    secondary_position: None,
    preference: Some([]),
    position_affinity: None,
  })
  let before_start = new_test_content_widget(
    document,
    "before-start",
    Some(Position(2, 1)),
    None,
  )
  let at_start = new_test_content_widget(
    document,
    "at-start",
    Some(Position(3, 1)),
    None,
  )
  let at_end = new_test_content_widget(
    document,
    "at-end",
    Some(Position(5, 1)),
    None,
  )
  let after_end = new_test_content_widget(
    document,
    "after-end",
    Some(Position(6, 1)),
    None,
  )
  for
    widget in [
      missing_anchor, null_preference, empty_preference, before_start, at_start,
      at_end, after_end,
    ] {
    widgets.add_widget(widget.content_widget_handle())
    widgets.set_widget_position(widget.content_widget_handle())
  }
  content_widgets_test_clear_events()
  widgets.on_before_render_widgets(3, 5)
  // `[]` is a present preference in the source onBefore guard, while null is
  // absent. Both inclusive viewport endpoints receive the cached write.
  assert_true(
    content_widgets_test_events() ==
    [
      "style:empty-preference:max-width:321px", "style:at-start:max-width:321px",
      "style:at-end:max-width:321px",
    ],
  )
}

///|
test "mapping reprojection retains model anchors and visits widgets in key order" {
  install_content_widgets_test_browser()
  let document = @rdom.document()
  let projection_delta = Ref(10)
  let projected_model_positions : Array[@base_common.Position] = []
  let widgets = ContentWidgets::ContentWidgets(
    document,
    document.create_element("section"),
  )
  widgets.install_live_view_context(() => (8.0, 300.0), position => {
    projected_model_positions.push(position)
    Some(
      Position(
        position.line_number + projection_delta.val,
        position.column + projection_delta.val,
      ),
    )
  })
  let first = new_test_content_widget(
    document,
    "first",
    Some(Position(1, 2)),
    Some(Position(1, 4)),
  )
  let second = new_test_content_widget(
    document,
    "second",
    Some(Position(3, 1)),
    None,
  )
  widgets.add_widget(first.content_widget_handle())
  widgets.set_widget_position(first.content_widget_handle())
  widgets.add_widget(second.content_widget_handle())
  widgets.set_widget_position(second.content_widget_handle())
  projected_model_positions.clear()
  projection_delta.val = 20

  widgets.update_anchors_view_positions()
  assert_eq(projected_model_positions.length(), 3)
  assert_true(projected_model_positions[0] == Position(1, 2))
  assert_true(projected_model_positions[1] == Position(1, 4))
  assert_true(projected_model_positions[2] == Position(3, 1))
  let first_state = widgets.widgets["first"]
  let second_state = widgets.widgets["second"]
  assert_true(first_state.primary_anchor.model_position == Some(Position(1, 2)))
  assert_true(
    first_state.primary_anchor.view_position == Some(Position(21, 22)),
  )
  assert_true(
    first_state.secondary_anchor.model_position == Some(Position(1, 4)),
  )
  assert_true(
    first_state.secondary_anchor.view_position == Some(Position(21, 24)),
  )
  assert_true(
    second_state.primary_anchor.model_position == Some(Position(3, 1)),
  )
  assert_true(
    second_state.primary_anchor.view_position == Some(Position(23, 21)),
  )
}

///|
test "projection keeps original anchors while exposing clamped and hidden results" {
  install_content_widgets_test_browser()
  let document = @rdom.document()
  let projected : Array[@base_common.Position] = []
  let widgets = ContentWidgets::ContentWidgets(
    document,
    document.create_element("section"),
  )
  widgets.install_live_view_context(() => (0.0, 300.0), position => {
    projected.push(position)
    if position.line_number == 99 {
      // The integration converter validates/clamps model coordinates before
      // returning a view position. Keep the owner-supplied model value in the
      // PositionPair while retaining that converted result separately.
      Some(Position(3, 4))
    } else if position.line_number == 77 {
      // A validated model position can still be hidden by folding/mapping.
      None
    } else {
      Some(position)
    }
  })
  let clamped = new_test_content_widget(
    document,
    "clamped",
    Some(Position(99, 999)),
    Some(Position(77, 5)),
  )
  let hidden = new_test_content_widget(
    document,
    "hidden",
    Some(Position(77, 1)),
    None,
  )
  widgets.add_widget(clamped.content_widget_handle())
  widgets.set_widget_position(clamped.content_widget_handle())
  widgets.add_widget(hidden.content_widget_handle())
  widgets.set_widget_position(hidden.content_widget_handle())
  assert_true(
    projected == [Position(99, 999), Position(77, 5), Position(77, 1)],
  )
  let clamped_state = widgets.widgets["clamped"]
  assert_true(
    clamped_state.primary_anchor.model_position == Some(Position(99, 999)),
  )
  assert_true(
    clamped_state.primary_anchor.view_position == Some(Position(3, 4)),
  )
  assert_true(
    clamped_state.secondary_anchor.model_position == Some(Position(77, 5)),
  )
  assert_true(clamped_state.secondary_anchor.view_position is None)
  let hidden_state = widgets.widgets["hidden"]
  assert_true(
    hidden_state.primary_anchor.model_position == Some(Position(77, 1)),
  )
  assert_true(hidden_state.primary_anchor.view_position is None)

  let measured : Array[@base_common.Position] = []
  widgets.prepare_render_widgets({
    vertical_offset_for_line: _ => 20.0,
    line_height_for_line: _ => 20.0,
    visible_range_for_position: position => {
      measured.push(position)
      Some(41.0)
    },
    typical_fullwidth_character_width: 16.0,
    scroll_top: 0.0,
    scroll_left: 0.0,
    viewport_width: 300.0,
    viewport_height: 100.0,
  })
  // Only the clamped primary reaches DOM measurement. The hidden secondary
  // and hidden primary remain null capability results.
  assert_true(measured == [Position(3, 4)])
  assert_true(
    hidden_state.render_data is Some(OffViewport(preserve_focus=false)),
  )
}

///|
test "measured anchors preserve affinity, nullable preference, and per-line geometry" {
  install_content_widgets_test_browser()
  let document = @rdom.document()
  let seen_affinities : Array[@model.PositionAffinity?] = []
  let measured_positions : Array[@base_common.Position] = []
  let line_height_queries : Array[Int] = []
  let widget = new_test_content_widget(
    document,
    "measured",
    Some(Position(4, 1)),
    None,
    after_enabled=true,
  )
  widget.position = Some({
    position: Some(Position(4, 1)),
    secondary_position: None,
    preference: Some([Exact]),
    position_affinity: Some(LeftOfInjectedText),
  })
  let widgets = ContentWidgets::ContentWidgets(
    document,
    document.create_element("section"),
  )
  widgets.install_live_view_context_with_affinity(() => (12.0, 400.0), (
    position,
    affinity,
  ) => {
    seen_affinities.push(affinity)
    Some(position)
  })
  widgets.add_widget(widget.content_widget_handle())
  widgets.set_widget_position(widget.content_widget_handle())
  widgets.prepare_render_widgets({
    vertical_offset_for_line: line => line.to_double() * 30.0,
    line_height_for_line: line => {
      line_height_queries.push(line)
      37.0
    },
    visible_range_for_position: position => {
      measured_positions.push(position)
      Some(91.0)
    },
    typical_fullwidth_character_width: 16.0,
    scroll_top: 20.0,
    scroll_left: 0.0,
    viewport_width: 500.0,
    viewport_height: 300.0,
  })
  assert_true(seen_affinities == [Some(LeftOfInjectedText)])
  assert_true(measured_positions == [Position(4, 1)])
  assert_true(line_height_queries == [4])
  let state = widgets.widgets["measured"]
  guard state.render_data is Some(InViewport(coordinate~, position~)) else {
    fail("expected a measured in-viewport placement")
  }
  assert_true(position == Exact)
  // Column one plus LeftOfInjectedText forces zero; the uniform-width
  // estimate would have hidden whether the measured callback was consulted.
  assert_eq(coordinate.top, 100.0)
  assert_eq(coordinate.left, 0.0)
  content_widgets_test_clear_events()
  widgets.render_widgets(20.0, 5.0)
  assert_eq(
    content_widgets_test_style_property(widget.dom_node, "top"),
    "115px",
  )
  assert_eq(content_widgets_test_style_property(widget.dom_node, "left"), "0px")
  assert_true(
    content_widgets_test_events().contains("after:measured:exact:100,0"),
  )

  // A null preference exits before any anchor/DOM measurement and preserves
  // the source distinction from an empty-but-non-null preference array.
  widget.position = Some({
    position: Some(Position(4, 2)),
    secondary_position: None,
    preference: None,
    position_affinity: None,
  })
  widgets.set_widget_position(widget.content_widget_handle())
  measured_positions.clear()
  widgets.prepare_render_widgets({
    vertical_offset_for_line: _ => 0.0,
    line_height_for_line: _ => 20.0,
    visible_range_for_position: position => {
      measured_positions.push(position)
      Some(999.0)
    },
    typical_fullwidth_character_width: 16.0,
    scroll_top: 0.0,
    scroll_left: 0.0,
    viewport_width: 500.0,
    viewport_height: 300.0,
  })
  assert_eq(measured_positions.length(), 0)
  assert_true(state.render_data is None)
}

///|
test "all position affinity values forward distinctly and only LeftOfInjectedText owns column-one zero" {
  install_content_widgets_test_browser()
  let document = @rdom.document()
  let affinities : Array[@model.PositionAffinity?] = [
    None,
    Some(None),
    Some(Left),
    Some(Right),
    Some(LeftOfInjectedText),
    Some(RightOfInjectedText),
  ]
  let seen : Array[@model.PositionAffinity?] = []
  let widget = new_test_content_widget(
    document,
    "affinity-matrix",
    Some(Position(2, 1)),
    None,
    before_enabled=true,
  )
  widget.before_dimension = Some({ width: 10.0, height: 10.0 })
  let widgets = ContentWidgets::ContentWidgets(
    document,
    document.create_element("section"),
  )
  widgets.install_live_view_context_with_affinity(() => (0.0, 300.0), (
    position,
    affinity,
  ) => {
    seen.push(affinity)
    Some(position)
  })
  widgets.add_widget(widget.content_widget_handle())
  for affinity in affinities {
    widget.position = Some({
      position: Some(Position(2, 1)),
      secondary_position: None,
      preference: Some([Exact]),
      position_affinity: affinity,
    })
    widgets.set_widget_position(widget.content_widget_handle())
    widgets.prepare_render_widgets({
      vertical_offset_for_line: _ => 40.0,
      line_height_for_line: _ => 20.0,
      visible_range_for_position: _ => Some(47.0),
      typical_fullwidth_character_width: 16.0,
      scroll_top: 0.0,
      scroll_left: 0.0,
      viewport_width: 300.0,
      viewport_height: 200.0,
    })
    guard widgets.widgets["affinity-matrix"].render_data
      is Some(InViewport(coordinate~, position=Exact)) else {
      fail("expected exact placement for affinity matrix")
    }
    assert_eq(
      coordinate.left,
      if affinity == Some(LeftOfInjectedText) {
        0.0
      } else {
        47.0
      },
    )
  }
  assert_true(seen == affinities)
}

///|
test "anchor queries keep same-line secondary and use measured x at later affinity columns" {
  install_content_widgets_test_browser()
  let document = @rdom.document()
  let same_line = new_test_content_widget(
    document,
    "same-line",
    Some(Position(4, 3)),
    Some(Position(4, 8)),
    before_enabled=true,
  )
  same_line.before_dimension = Some({ width: 40.0, height: 10.0 })
  same_line.position = Some({
    position: Some(Position(4, 3)),
    secondary_position: Some(Position(4, 8)),
    preference: Some([Exact]),
    position_affinity: Some(LeftOfInjectedText),
  })
  let different_line = new_test_content_widget(
    document,
    "different-line",
    Some(Position(6, 2)),
    Some(Position(7, 9)),
    before_enabled=true,
  )
  different_line.before_dimension = Some({ width: 40.0, height: 10.0 })
  let widgets = ContentWidgets::ContentWidgets(
    document,
    document.create_element("section"),
  )
  widgets.install_live_view_context_with_affinity(() => (0.0, 500.0), (
    position,
    _affinity,
  ) => Some(position))
  widgets.add_widget(same_line.content_widget_handle())
  widgets.set_widget_position(same_line.content_widget_handle())
  widgets.add_widget(different_line.content_widget_handle())
  widgets.set_widget_position(different_line.content_widget_handle())
  let measured : Array[@base_common.Position] = []
  widgets.prepare_render_widgets({
    vertical_offset_for_line: line => line.to_double() * 20.0,
    line_height_for_line: _ => 20.0,
    visible_range_for_position: position => {
      measured.push(position)
      if position == Position(4, 3) {
        Some(37.0)
      } else if position == Position(4, 8) {
        Some(97.0)
      } else if position == Position(6, 2) {
        Some(211.0)
      } else {
        Some(999.0)
      }
    },
    typical_fullwidth_character_width: 16.0,
    scroll_top: 0.0,
    scroll_left: 0.0,
    viewport_width: 500.0,
    viewport_height: 300.0,
  })
  assert_true(measured == [Position(4, 3), Position(4, 8), Position(6, 2)])
  let same_state = widgets.widgets["same-line"]
  guard same_state.render_data
    is Some(InViewport(coordinate=same_coordinate, position=Exact)) else {
    fail("expected same-line exact placement")
  }
  // LeftOfInjectedText only forces zero at column one. A later column keeps
  // the measured primary x, and the same-line secondary then reduces it.
  assert_eq(same_coordinate.left, 61.0)
  let different_state = widgets.widgets["different-line"]
  guard different_state.render_data
    is Some(InViewport(coordinate=different_coordinate, position=Below)) else {
    fail("expected different-line placement")
  }
  assert_eq(different_coordinate.left, 211.0)
}

///|
test "display ownership and read phase preserve source ordering and caches" {
  install_content_widgets_test_browser()
  let document = @rdom.document()
  let widgets = ContentWidgets::ContentWidgets(
    document,
    document.create_element("section"),
  )
  widgets.install_live_view_context(() => (10.0, 300.0), position => {
    Some(position)
  })
  let first = new_test_content_widget(
    document,
    "first",
    Some(Position(1, 2)),
    None,
    before_enabled=true,
    after_enabled=true,
    throw_after=true,
  )
  first.before_dimension = Some({ width: 40.0, height: 18.0 })
  let second = new_test_content_widget(
    document,
    "second",
    Some(Position(1, 3)),
    None,
    before_enabled=true,
    after_enabled=true,
  )
  second.before_dimension = Some({ width: 50.0, height: 19.0 })
  widgets.add_widget(first.content_widget_handle())
  widgets.set_widget_position(first.content_widget_handle())
  widgets.add_widget(second.content_widget_handle())
  widgets.set_widget_position(second.content_widget_handle())
  content_widgets_test_clear_events()
  widgets.on_before_render_widgets(1, 1)
  widgets.prepare_render_widgets({
    vertical_offset_for_line: _ => 40.0,
    line_height_for_line: _ => 20.0,
    visible_range_for_position: position => {
      Some((position.column * 11).to_double())
    },
    typical_fullwidth_character_width: 16.0,
    scroll_top: 0.0,
    scroll_left: 0.0,
    viewport_width: 500.0,
    viewport_height: 300.0,
  })
  assert_true(
    content_widgets_test_events() ==
    [
      "style:first:max-width:300px", "style:second:max-width:300px", "before:first",
      "before:second",
    ],
  )
  assert_eq(widgets.widgets["first"].cached_dom_node_offset_width, 40.0)
  assert_eq(widgets.widgets["first"].cached_dom_node_offset_height, 18.0)
  content_widgets_test_clear_events()
  widgets.render_widgets(0.0, 0.0)
  let after_events = content_widgets_test_events()
  assert_true(after_events.any(event => event.has_prefix("after:first:")))
  assert_true(after_events.any(event => event.has_prefix("after:second:")))

  // Either invalid cache axis re-enters measurement and replaces both axes.
  let first_state = widgets.widgets["first"]
  first_state.cached_dom_node_offset_width = -1.0
  first_state.cached_dom_node_offset_height = 99.0
  first.before_dimension = Some({ width: 7.0, height: 8.0 })
  widgets.prepare_render_widgets({
    vertical_offset_for_line: _ => 40.0,
    line_height_for_line: _ => 20.0,
    visible_range_for_position: _ => Some(10.0),
    typical_fullwidth_character_width: 16.0,
    scroll_top: 0.0,
    scroll_left: 0.0,
    viewport_width: 500.0,
    viewport_height: 300.0,
  })
  assert_eq(first_state.cached_dom_node_offset_width, 7.0)
  assert_eq(first_state.cached_dom_node_offset_height, 8.0)

  // The symmetric height-only miss also refreshes both values instead of
  // retaining the otherwise-valid width.
  first_state.cached_dom_node_offset_width = 88.0
  first_state.cached_dom_node_offset_height = -1.0
  first.before_dimension = Some({ width: 9.0, height: 11.0 })
  widgets.prepare_render_widgets({
    vertical_offset_for_line: _ => 40.0,
    line_height_for_line: _ => 20.0,
    visible_range_for_position: _ => Some(10.0),
    typical_fullwidth_character_width: 16.0,
    scroll_top: 0.0,
    scroll_left: 0.0,
    viewport_width: 500.0,
    viewport_height: 300.0,
  })
  assert_eq(first_state.cached_dom_node_offset_width, 9.0)
  assert_eq(first_state.cached_dom_node_offset_height, 11.0)

  // With both axes valid, prepare skips both beforeRender and the DOM rect.
  // This is the source OR gate's fully cached arm.
  first.before_dimension = Some({ width: 999.0, height: 999.0 })
  content_widgets_test_clear_events()
  content_widgets_test_clear_rect_reads()
  widgets.prepare_render_widgets({
    vertical_offset_for_line: _ => 40.0,
    line_height_for_line: _ => 20.0,
    visible_range_for_position: _ => Some(10.0),
    typical_fullwidth_character_width: 16.0,
    scroll_top: 0.0,
    scroll_left: 0.0,
    viewport_width: 500.0,
    viewport_height: 300.0,
  })
  assert_eq(content_widgets_test_rect_reads(), 0)
  assert_false(
    content_widgets_test_events().any(event => event.has_prefix("before:")),
  )
  assert_eq(first_state.cached_dom_node_offset_width, 9.0)
  assert_eq(first_state.cached_dom_node_offset_height, 11.0)

  // A present callback returning null falls back to independently rounded DOM
  // dimensions.
  first.before_dimension = None
  content_widgets_test_set_rect(first.dom_node, 0.0, 0.0, 10.4, 20.5)
  widgets.set_widget_position(first.content_widget_handle())
  widgets.prepare_render_widgets({
    vertical_offset_for_line: _ => 40.0,
    line_height_for_line: _ => 20.0,
    visible_range_for_position: _ => Some(10.0),
    typical_fullwidth_character_width: 16.0,
    scroll_top: 0.0,
    scroll_left: 0.0,
    viewport_width: 500.0,
    viewport_height: 300.0,
  })
  assert_eq(first_state.cached_dom_node_offset_width, 10.0)
  assert_eq(first_state.cached_dom_node_offset_height, 21.0)

  // A throwing beforeRender is isolated and takes the same DOM fallback; the
  // next widget's callback still runs.
  first.throw_before = true
  content_widgets_test_set_rect(first.dom_node, 0.0, 0.0, 12.6, 22.4)
  widgets.set_widget_position(first.content_widget_handle())
  let second_state = widgets.widgets["second"]
  second_state.cached_dom_node_offset_width = -1.0
  second_state.cached_dom_node_offset_height = -1.0
  content_widgets_test_clear_events()
  widgets.prepare_render_widgets({
    vertical_offset_for_line: _ => 40.0,
    line_height_for_line: _ => 20.0,
    visible_range_for_position: _ => Some(10.0),
    typical_fullwidth_character_width: 16.0,
    scroll_top: 0.0,
    scroll_left: 0.0,
    viewport_width: 500.0,
    viewport_height: 300.0,
  })
  assert_eq(first_state.cached_dom_node_offset_width, 13.0)
  assert_eq(first_state.cached_dom_node_offset_height, 22.0)
  assert_true(content_widgets_test_events().contains("before:second"))

  // `useDisplayNone` selects the source's `display:none` arm and suppresses
  // outer dirtying.
  let owned_display = new_test_content_widget(
    document,
    "display-owner",
    Some(Position(1, 1)),
    None,
    use_display_none=true,
  )
  widgets.add_widget(owned_display.content_widget_handle())
  @base_browser.set_style_property(owned_display.dom_node, "display", "grid")
  widgets.should_render = false
  widgets.set_widget_position(owned_display.content_widget_handle())
  assert_false(widgets.should_render)
  assert_eq(
    content_widgets_test_style_property(owned_display.dom_node, "display"),
    "none",
  )
}

///|
test "useDisplayNone and positionability preserve the full display scheduling matrix" {
  install_content_widgets_test_browser()
  let document = @rdom.document()
  let widgets = ContentWidgets::ContentWidgets(
    document,
    document.create_element("section"),
  )
  widgets.install_live_view_context(() => (0.0, 300.0), position => {
    Some(position)
  })
  let source_positionable = new_test_content_widget(
    document,
    "source-positionable",
    Some(Position(1, 1)),
    None,
  )
  let source_unpositionable = new_test_content_widget(
    document,
    "source-unpositionable",
    None,
    None,
  )
  let owner_positionable = new_test_content_widget(
    document,
    "owner-positionable",
    Some(Position(1, 1)),
    None,
    use_display_none=true,
  )
  let owner_unpositionable = new_test_content_widget(
    document,
    "owner-unpositionable",
    None,
    None,
    use_display_none=true,
  )
  for
    widget in [
      source_positionable, source_unpositionable, owner_positionable, owner_unpositionable,
    ] {
    widgets.add_widget(widget.content_widget_handle())
  }

  widgets.should_render = false
  widgets.set_widget_position(source_positionable.content_widget_handle())
  assert_true(widgets.should_render)
  assert_eq(
    content_widgets_test_style_property(source_positionable.dom_node, "display"),
    "block",
  )

  widgets.should_render = false
  widgets.set_widget_position(source_unpositionable.content_widget_handle())
  assert_true(widgets.should_render)
  assert_eq(
    content_widgets_test_style_property(
      source_unpositionable.dom_node,
      "display",
    ),
    "none",
  )

  widgets.should_render = false
  widgets.set_widget_position(owner_positionable.content_widget_handle())
  assert_false(widgets.should_render)
  assert_eq(
    content_widgets_test_style_property(owner_positionable.dom_node, "display"),
    "none",
  )

  widgets.should_render = false
  widgets.set_widget_position(owner_unpositionable.content_widget_handle())
  assert_false(widgets.should_render)
  assert_eq(
    content_widgets_test_style_property(
      owner_unpositionable.dom_node,
      "display",
    ),
    "none",
  )
}

///|
test "focused off-viewport widgets park without hiding and hidden writes are gated" {
  install_content_widgets_test_browser()
  let document = @rdom.document()
  let widget = new_test_content_widget(
    document,
    "focus",
    Some(Position(1, 1)),
    None,
    after_enabled=true,
  )
  let focus_child = document.create_element("button")
  widget.dom_node.append_child(focus_child.as_node())
  let widgets = ContentWidgets::ContentWidgets(
    document,
    document.create_element("section"),
  )
  widgets.install_live_view_context(() => (0.0, 300.0), position => {
    Some(position)
  })
  widgets.add_widget(widget.content_widget_handle())
  widgets.set_widget_position(widget.content_widget_handle())
  let measurable = Ref(true)
  let ctx : ContentWidgetsRenderContext = {
    vertical_offset_for_line: _ => 50.0,
    line_height_for_line: _ => 20.0,
    visible_range_for_position: _ => {
      if measurable.val {
        Some(10.0)
      } else {
        None
      }
    },
    typical_fullwidth_character_width: 16.0,
    scroll_top: 0.0,
    scroll_left: 0.0,
    viewport_width: 300.0,
    viewport_height: 200.0,
  }
  widgets.prepare_render_widgets(ctx)
  widgets.render_widgets(0.0, 0.0)
  assert_eq(
    content_widgets_test_style_property(widget.dom_node, "visibility"),
    "inherit",
  )
  content_widgets_test_set_active_element(document, focus_child)
  measurable.val = false
  widgets.prepare_render_widgets(ctx)
  content_widgets_test_clear_events()
  widgets.render_widgets(0.0, 0.0)
  assert_eq(
    content_widgets_test_style_property(widget.dom_node, "top"),
    "-1000px",
  )
  assert_eq(
    content_widgets_test_style_property(widget.dom_node, "visibility"),
    "inherit",
  )
  assert_true(
    content_widgets_test_events() ==
    ["style:focus:top:-1000px", "after:focus:null:null"],
  )
  // Once hidden, the same result performs no visibility/top mutation, but
  // hidden afterRender still runs before the early return.
  content_widgets_test_clear_events()
  widgets.render_widgets(0.0, 0.0)
  assert_true(content_widgets_test_events() == ["after:focus:null:null"])

  // Re-enter, then leave without focus: this branch hides instead of parks.
  measurable.val = true
  widgets.prepare_render_widgets(ctx)
  widgets.render_widgets(0.0, 0.0)
  content_widgets_test_clear_active_element(document)
  measurable.val = false
  widgets.prepare_render_widgets(ctx)
  widgets.render_widgets(0.0, 0.0)
  assert_eq(
    content_widgets_test_style_property(widget.dom_node, "visibility"),
    "hidden",
  )
}

///|
test "preference traversal uses first-pass fit then second-pass first option" {
  install_content_widgets_test_browser()
  let document = @rdom.document()
  let widget = new_test_content_widget(
    document,
    "preference",
    Some(Position(1, 2)),
    None,
    before_enabled=true,
  )
  widget.before_dimension = Some({ width: 60.0, height: 50.0 })
  widget.position = Some({
    position: Some(Position(1, 2)),
    secondary_position: None,
    preference: Some([Below, Above]),
    position_affinity: None,
  })
  let widgets = ContentWidgets::ContentWidgets(
    document,
    document.create_element("section"),
  )
  widgets.install_live_view_context(() => (0.0, 300.0), position => {
    Some(position)
  })
  widgets.add_widget(widget.content_widget_handle())
  widgets.set_widget_position(widget.content_widget_handle())
  let state = widgets.widgets["preference"]

  // Neither vertical candidate fits, so pass two picks the first preference.
  widgets.prepare_render_widgets({
    vertical_offset_for_line: _ => 20.0,
    line_height_for_line: _ => 20.0,
    visible_range_for_position: _ => Some(90.0),
    typical_fullwidth_character_width: 16.0,
    scroll_top: 0.0,
    scroll_left: 0.0,
    viewport_width: 100.0,
    viewport_height: 60.0,
  })
  guard state.render_data is Some(InViewport(coordinate~, position~)) else {
    fail("expected pass-two placement")
  }
  assert_true(position == Below)
  assert_eq(coordinate.top, 40.0)
  // Right clamp runs before the left clamp: 90+60 overflows a 100px box.
  assert_eq(coordinate.left, 40.0)

  // Below does not fit, but Above does: pass one continues to the second
  // preference and returns it instead of using pass-two fallback.
  widgets.set_widget_position(widget.content_widget_handle())
  widgets.prepare_render_widgets({
    vertical_offset_for_line: _ => 55.0,
    line_height_for_line: _ => 20.0,
    visible_range_for_position: _ => Some(10.0),
    typical_fullwidth_character_width: 16.0,
    scroll_top: 0.0,
    scroll_left: 0.0,
    viewport_width: 100.0,
    viewport_height: 80.0,
  })
  guard state.render_data
    is Some(InViewport(coordinate=coordinate2, position=position2)) else {
    fail("expected first-pass above placement")
  }
  assert_true(position2 == Above)
  assert_eq(coordinate2.top, 5.0)

  // With both fitting, the first ordered preference wins immediately.
  widgets.set_widget_position(widget.content_widget_handle())
  widgets.prepare_render_widgets({
    vertical_offset_for_line: _ => 80.0,
    line_height_for_line: _ => 20.0,
    visible_range_for_position: _ => Some(10.0),
    typical_fullwidth_character_width: 16.0,
    scroll_top: 0.0,
    scroll_left: 0.0,
    viewport_width: 100.0,
    viewport_height: 200.0,
  })
  guard state.render_data is Some(InViewport(coordinate=_, position=position3)) else {
    fail("expected ordered fitting placement")
  }
  assert_true(position3 == Below)
}

///|
test "empty single and mixed preferences preserve source order" {
  install_content_widgets_test_browser()
  let document = @rdom.document()
  let widget = new_test_content_widget(
    document,
    "preference-matrix",
    Some(Position(1, 2)),
    None,
    before_enabled=true,
  )
  widget.before_dimension = Some({ width: 10.0, height: 10.0 })
  let widgets = ContentWidgets::ContentWidgets(
    document,
    document.create_element("section"),
  )
  widgets.install_live_view_context(() => (0.0, 300.0), position => {
    Some(position)
  })
  widgets.add_widget(widget.content_widget_handle())
  let query_count = Ref(0)
  let ctx : ContentWidgetsRenderContext = {
    vertical_offset_for_line: _ => 50.0,
    line_height_for_line: _ => 20.0,
    visible_range_for_position: _ => {
      query_count.val += 1
      Some(30.0)
    },
    typical_fullwidth_character_width: 16.0,
    scroll_top: 0.0,
    scroll_left: 0.0,
    viewport_width: 200.0,
    viewport_height: 200.0,
  }

  widget.position = Some({
    position: Some(Position(1, 2)),
    secondary_position: None,
    preference: Some([]),
    position_affinity: None,
  })
  widgets.set_widget_position(widget.content_widget_handle())
  widgets.prepare_render_widgets(ctx)
  assert_true(widgets.widgets["preference-matrix"].render_data is None)
  assert_eq(query_count.val, 0)

  widget.position = Some({
    position: Some(Position(1, 2)),
    secondary_position: None,
    preference: Some([Above]),
    position_affinity: None,
  })
  widgets.set_widget_position(widget.content_widget_handle())
  widgets.prepare_render_widgets(ctx)
  guard widgets.widgets["preference-matrix"].render_data
    is Some(InViewport(coordinate=above_coordinate, position=Above)) else {
    fail("expected single ABOVE preference")
  }
  assert_eq(above_coordinate.top, 40.0)

  widget.position = Some({
    position: Some(Position(1, 2)),
    secondary_position: None,
    preference: Some([Below]),
    position_affinity: None,
  })
  widgets.set_widget_position(widget.content_widget_handle())
  widgets.prepare_render_widgets(ctx)
  guard widgets.widgets["preference-matrix"].render_data
    is Some(InViewport(coordinate=below_coordinate, position=Below)) else {
    fail("expected single BELOW preference")
  }
  assert_eq(below_coordinate.top, 70.0)

  widget.position = Some({
    position: Some(Position(1, 2)),
    secondary_position: None,
    preference: Some([Exact]),
    position_affinity: None,
  })
  widgets.set_widget_position(widget.content_widget_handle())
  widgets.prepare_render_widgets(ctx)
  guard widgets.widgets["preference-matrix"].render_data
    is Some(InViewport(coordinate=exact_coordinate, position=Exact)) else {
    fail("expected single EXACT preference")
  }
  assert_eq(exact_coordinate.top, 50.0)
  assert_eq(exact_coordinate.left, 30.0)

  widget.position = Some({
    position: Some(Position(1, 2)),
    secondary_position: None,
    preference: Some([Above, Below]),
    position_affinity: None,
  })
  widgets.set_widget_position(widget.content_widget_handle())
  widgets.prepare_render_widgets(ctx)
  guard widgets.widgets["preference-matrix"].render_data
    is Some(InViewport(coordinate=_, position=mixed_above)) else {
    fail("expected mixed ABOVE-first preference")
  }
  assert_true(mixed_above == Above)

  widget.position = Some({
    position: Some(Position(1, 2)),
    secondary_position: None,
    preference: Some([Below, Above]),
    position_affinity: None,
  })
  widgets.set_widget_position(widget.content_widget_handle())
  widgets.prepare_render_widgets(ctx)
  guard widgets.widgets["preference-matrix"].render_data
    is Some(InViewport(coordinate=_, position=mixed_below)) else {
    fail("expected mixed BELOW-first preference")
  }
  assert_true(mixed_below == Below)
}

///|
test "ABOVE and BELOW write visible coordinates before afterRender callbacks" {
  install_content_widgets_test_browser()
  let document = @rdom.document()
  let above = new_test_content_widget(
    document,
    "callback-above",
    Some(Position(1, 2)),
    None,
    before_enabled=true,
    after_enabled=true,
  )
  above.before_dimension = Some({ width: 10.0, height: 10.0 })
  above.position = Some({
    position: Some(Position(1, 2)),
    secondary_position: None,
    preference: Some([Above]),
    position_affinity: None,
  })
  let below = new_test_content_widget(
    document,
    "callback-below",
    Some(Position(1, 2)),
    None,
    before_enabled=true,
    after_enabled=true,
  )
  below.before_dimension = Some({ width: 10.0, height: 10.0 })
  below.position = Some({
    position: Some(Position(1, 2)),
    secondary_position: None,
    preference: Some([Below]),
    position_affinity: None,
  })
  let widgets = ContentWidgets::ContentWidgets(
    document,
    document.create_element("section"),
  )
  widgets.install_live_view_context(() => (0.0, 300.0), position => {
    Some(position)
  })
  widgets.add_widget(above.content_widget_handle())
  widgets.set_widget_position(above.content_widget_handle())
  widgets.add_widget(below.content_widget_handle())
  widgets.set_widget_position(below.content_widget_handle())
  widgets.prepare_render_widgets({
    vertical_offset_for_line: _ => 50.0,
    line_height_for_line: _ => 20.0,
    visible_range_for_position: _ => Some(25.0),
    typical_fullwidth_character_width: 16.0,
    scroll_top: 10.0,
    scroll_left: 0.0,
    viewport_width: 300.0,
    viewport_height: 200.0,
  })
  content_widgets_test_clear_events()
  widgets.render_widgets(10.0, 3.0)
  assert_true(
    content_widgets_test_events() ==
    [
      "style:callback-above:top:37px", "style:callback-above:left:25px", "style:callback-above:visibility:inherit",
      "after:callback-above:above:30,25", "style:callback-below:top:67px", "style:callback-below:left:25px",
      "style:callback-below:visibility:inherit", "after:callback-below:below:60,25",
    ],
  )
}

///|
fn assert_anchor_coordinate(
  actual : AnchorCoordinate,
  top : Double,
  left : Double,
  height : Double,
) -> Unit raise {
  assert_eq(actual.top, top)
  assert_eq(actual.left, left)
  assert_eq(actual.height, height)
}

///|
test "secondary anchor reduction preserves primary contact boundaries" {
  let primary : AnchorCoordinate = { top: 10.0, left: 100.0, height: 20.0 }
  assert_anchor_coordinate(
    reduce_anchor_coordinates(primary, None, 80.0, 16.0),
    10.0,
    100.0,
    20.0,
  )
  assert_anchor_coordinate(
    reduce_anchor_coordinates(
      primary,
      Some({ top: 10.0, left: 0.0, height: 20.0 }),
      80.0,
      16.0,
    ),
    10.0,
    36.0,
    20.0,
  )
  assert_anchor_coordinate(
    reduce_anchor_coordinates(
      primary,
      Some({ top: 10.0, left: 100.0, height: 20.0 }),
      80.0,
      16.0,
    ),
    10.0,
    100.0,
    20.0,
  )
  assert_anchor_coordinate(
    reduce_anchor_coordinates(
      primary,
      Some({ top: 10.0, left: 200.0, height: 20.0 }),
      80.0,
      16.0,
    ),
    10.0,
    164.0,
    20.0,
  )
  // At exactly one fullwidth glyph of widget width, either side collapses to
  // the primary anchor.
  assert_anchor_coordinate(
    reduce_anchor_coordinates(
      primary,
      Some({ top: 10.0, left: 50.0, height: 20.0 }),
      16.0,
      16.0,
    ),
    10.0,
    100.0,
    20.0,
  )
  assert_anchor_coordinate(
    reduce_anchor_coordinates(
      primary,
      Some({ top: 10.0, left: 150.0, height: 20.0 }),
      16.0,
      16.0,
    ),
    10.0,
    100.0,
    20.0,
  )
}

///|
test "viewport layout clamps a nonzero scroll window at inclusive edges" {
  let ctx : ContentWidgetsRenderContext = {
    vertical_offset_for_line: _ => 0.0,
    line_height_for_line: _ => 10.0,
    visible_range_for_position: _ => None,
    typical_fullwidth_character_width: 16.0,
    scroll_top: 0.0,
    scroll_left: 40.0,
    viewport_width: 100.0,
    viewport_height: 50.0,
  }
  let vertical_equality = layout_box_in_viewport(
    { top: 20.0, left: 60.0, height: 10.0 },
    20.0,
    20.0,
    ctx,
  )
  assert_true(vertical_equality.fits_above)
  assert_true(vertical_equality.fits_below)
  assert_eq(vertical_equality.above_top, 0.0)
  assert_eq(vertical_equality.below_top, 30.0)
  assert_eq(vertical_equality.left, 60.0)

  // Equality at either horizontal edge does not enter a strict clamp.
  let left_equality = layout_box_in_viewport(
    { top: 20.0, left: 40.0, height: 10.0 },
    20.0,
    10.0,
    ctx,
  )
  assert_eq(left_equality.left, 40.0)
  let right_equality = layout_box_in_viewport(
    { top: 20.0, left: 120.0, height: 10.0 },
    20.0,
    10.0,
    ctx,
  )
  assert_eq(right_equality.left, 120.0)

  let left_underflow = layout_box_in_viewport(
    { top: 20.0, left: 39.0, height: 10.0 },
    20.0,
    10.0,
    ctx,
  )
  assert_eq(left_underflow.left, 40.0)
  let right_overflow = layout_box_in_viewport(
    { top: 20.0, left: 121.0, height: 10.0 },
    20.0,
    10.0,
    ctx,
  )
  assert_eq(right_overflow.left, 120.0)

  // Source order is right clamp then left clamp. A wider-than-viewport box
  // first moves left of the window and is then pinned back to scrollLeft.
  let wider = layout_box_in_viewport(
    { top: 20.0, left: 100.0, height: 10.0 },
    120.0,
    10.0,
    ctx,
  )
  assert_eq(wider.left, 40.0)
}

///|
test "owner document supplies max width, page scroll, and paired clamps" {
  install_content_widgets_test_browser()
  let owner = content_widgets_test_make_document(
    true, 700.0, 40.0, 60.0, 650.0, 600.0,
  )
  let node = owner.create_element("div")
  let owner_focus = owner.create_element("button")
  node.append_child(owner_focus.as_node())
  content_widgets_test_set_active_element(owner, owner_focus)
  assert_true(@base_browser.element_contains_active_element(node))
  content_widgets_test_clear_active_element(owner)
  assert_false(@base_browser.element_contains_active_element(node))
  assert_eq(content_widget_max_width(node, true, 123.0), 700.0)
  let (owner_width, owner_height) = body_client_area(node)
  assert_eq(owner_width, 700.0)
  assert_eq(owner_height, 700.0)
  let zero_inner = content_widgets_test_make_document(
    true, 0.0, 4.0, 6.0, 650.0, 600.0,
  )
  assert_eq(
    content_widget_max_width(zero_inner.create_element("div"), true, 123.0),
    650.0,
  )
  let body_fallback = content_widgets_test_make_document(
    true, 0.0, 4.0, 6.0, 0.0, 600.0,
  )
  assert_eq(
    content_widget_max_width(body_fallback.create_element("div"), true, 123.0),
    600.0,
  )
  assert_eq(content_widget_max_width(node, false, 123.0), 123.0)

  content_widgets_test_set_rect(node, 100.0, 200.0, 200.0, 100.0)
  let page = dom_node_page_position(node)
  assert_eq(page.left, 140.0)
  assert_eq(page.top, 260.0)
  let (inside_left, inside_absolute) = layout_horizontal_segment_in_page(
    500.0, page, 40.0, 100.0, 80.0,
  )
  assert_eq(inside_left, 100.0)
  assert_eq(inside_absolute, 200.0)
  let (right_left, right_absolute) = layout_horizontal_segment_in_page(
    500.0, page, 40.0, 400.0, 80.0,
  )
  assert_eq(right_left, 240.0)
  assert_eq(right_absolute, 340.0)
  let (left_left, left_absolute) = layout_horizontal_segment_in_page(
    500.0, page, 40.0, -200.0, 80.0,
  )
  assert_eq(left_left, -40.0)
  assert_eq(left_absolute, 60.0)

  let detached = content_widgets_test_make_document(
    false, 999.0, 999.0, 999.0, 500.0, 450.0,
  )
  let detached_node = detached.create_element("div")
  content_widgets_test_set_rect(detached_node, 12.0, 34.0, 56.0, 78.0)
  content_widgets_test_set_main_scroll(17.0, 23.0)
  let detached_page = dom_node_page_position(detached_node)
  assert_eq(detached_page.left, 29.0)
  assert_eq(detached_page.top, 57.0)
  let (detached_width, detached_height) = body_client_area(detached_node)
  assert_eq(detached_width, 450.0)
  assert_eq(detached_height, 600.0)
  let detached_zero = content_widgets_test_make_document(
    false, 999.0, 999.0, 999.0, 888.0, 0.0,
  )
  let (detached_zero_width, detached_zero_height) = body_client_area(
    detached_zero.create_element("div"),
  )
  assert_eq(detached_zero_width, 0.0)
  assert_eq(detached_zero_height, 600.0)
}

///|
test "iOS owner visual viewport precedes inner and document client areas" {
  install_content_widgets_test_browser()
  let owner = content_widgets_test_make_document(
    true, 700.0, 0.0, 0.0, 650.0, 600.0,
  )
  let node = owner.create_element("div")
  let visual_width = Ref(-1.0)
  let visual_height = Ref(-1.0)
  content_widgets_test_with_ios_visual_viewport(owner, 321.0, 123.0, () => {
    let (width, height) = body_client_area(node)
    visual_width.val = width
    visual_height.val = height
  })
  assert_eq(visual_width.val, 321.0)
  assert_eq(visual_height.val, 123.0)
  let (restored_width, restored_height) = body_client_area(node)
  assert_eq(restored_width, 700.0)
  assert_eq(restored_height, 700.0)
}

///|
test "detached owner scroll helpers and page layout use explicit zero fallbacks" {
  install_content_widgets_test_browser()
  content_widgets_test_set_main_scroll(17.0, 23.0)
  let detached = content_widgets_test_make_document(
    false, 999.0, 999.0, 999.0, 500.0, 500.0,
  )
  let root = detached.create_element("section")
  content_widgets_test_set_rect(root, 100.0, 200.0, 200.0, 100.0)
  assert_eq(owner_window_scroll_x(root), 0.0)
  assert_eq(owner_window_scroll_y(root), 0.0)
  // The external DOM page-position helper deliberately has the different
  // fallback: it uses the registered main window when defaultView is absent.
  assert_eq(dom_helper_window_scroll_x(root), 17.0)
  assert_eq(dom_helper_window_scroll_y(root), 23.0)
  let page = dom_node_page_position(root)
  assert_eq(page.left, 117.0)
  assert_eq(page.top, 223.0)
  let ctx : ContentWidgetsRenderContext = {
    vertical_offset_for_line: _ => 0.0,
    line_height_for_line: _ => 20.0,
    visible_range_for_position: _ => None,
    typical_fullwidth_character_width: 16.0,
    scroll_top: 0.0,
    scroll_left: 0.0,
    viewport_width: 500.0,
    viewport_height: 600.0,
  }
  let placement = layout_box_in_page(
    { top: -171.0, left: 290.0, height: 20.0 },
    80.0,
    30.0,
    ctx,
    root,
    0.0,
  )
  // Explicit owner scroll zero makes absoluteAboveTop exactly the inclusive
  // 22px boundary. Horizontal clamping uses the same zero and therefore
  // shifts relative left by 90px (a global-scroll fallback would yield 217).
  assert_true(placement.fits_above)
  assert_true(placement.fits_below)
  assert_eq(placement.above_top, -201.0)
  assert_eq(placement.below_top, -151.0)
  assert_eq(placement.left, 200.0)
}

///|
test "page layout keeps 15px and 22px equality boundaries and wide boxes" {
  install_content_widgets_test_browser()
  let owner = content_widgets_test_make_document(
    true, 500.0, 0.0, 0.0, 500.0, 500.0,
  )
  let root = owner.create_element("section")
  content_widgets_test_set_rect(root, 40.0, 100.0, 100.0, 400.0)
  let page = dom_node_page_position(root)

  // Exact 15px left clearance is inclusive; one pixel below it clamps both
  // relative and absolute coordinates by the same delta.
  let (left_equal, left_absolute_equal) = layout_horizontal_segment_in_page(
    500.0, page, 0.0, -25.0, 80.0,
  )
  assert_eq(left_equal, -25.0)
  assert_eq(left_absolute_equal, 15.0)
  let (left_under, left_absolute_under) = layout_horizontal_segment_in_page(
    500.0, page, 0.0, -26.0, 80.0,
  )
  assert_eq(left_under, -25.0)
  assert_eq(left_absolute_under, 15.0)

  // Make the page's 15px right clearance, rather than the editor-width
  // allowance, the active maximum.
  let right_page : DomNodePagePosition = { top: 0.0, left: 100.0, width: 350.0 }
  let (right_equal, right_absolute_equal) = layout_horizontal_segment_in_page(
    500.0, right_page, 0.0, 305.0, 80.0,
  )
  assert_eq(right_equal, 305.0)
  assert_eq(right_absolute_equal, 405.0)
  let (right_over, right_absolute_over) = layout_horizontal_segment_in_page(
    500.0, right_page, 0.0, 306.0, 80.0,
  )
  assert_eq(right_over, 305.0)
  assert_eq(right_absolute_over, 405.0)

  // A widget wider than both the editor and page cannot fit. The source's
  // right-then-left sequence leaves its left edge at the 15px minimum while
  // preserving the relative/absolute offset.
  let wide_page : DomNodePagePosition = { top: 0.0, left: 100.0, width: 200.0 }
  let (wide_left, wide_absolute) = layout_horizontal_segment_in_page(
    500.0, wide_page, 0.0, 0.0, 600.0,
  )
  assert_eq(wide_left, -85.0)
  assert_eq(wide_absolute, 15.0)

  let ctx : ContentWidgetsRenderContext = {
    vertical_offset_for_line: _ => 0.0,
    line_height_for_line: _ => 20.0,
    visible_range_for_position: _ => None,
    typical_fullwidth_character_width: 16.0,
    scroll_top: 0.0,
    scroll_left: 0.0,
    viewport_width: 500.0,
    viewport_height: 700.0,
  }
  let top_equal = layout_box_in_page(
    { top: -48.0, left: 0.0, height: 20.0 },
    80.0,
    30.0,
    ctx,
    root,
    0.0,
  )
  assert_true(top_equal.fits_above)
  assert_true(top_equal.fits_below)
  assert_eq(top_equal.above_top, -78.0)
  let top_outside = layout_box_in_page(
    { top: -49.0, left: 0.0, height: 20.0 },
    80.0,
    30.0,
    ctx,
    root,
    0.0,
  )
  assert_false(top_outside.fits_above)
  assert_true(top_outside.fits_below)

  let bottom_equal = layout_box_in_page(
    { top: 528.0, left: 0.0, height: 20.0 },
    80.0,
    30.0,
    ctx,
    root,
    0.0,
  )
  assert_true(bottom_equal.fits_above)
  assert_true(bottom_equal.fits_below)
  assert_eq(bottom_equal.below_top, 548.0)
  let bottom_outside = layout_box_in_page(
    { top: 529.0, left: 0.0, height: 20.0 },
    80.0,
    30.0,
    ctx,
    root,
    0.0,
  )
  assert_true(bottom_outside.fits_above)
  assert_false(bottom_outside.fits_below)

  let neither = layout_box_in_page(
    { top: 0.0, left: 0.0, height: 20.0 },
    80.0,
    700.0,
    ctx,
    root,
    0.0,
  )
  assert_false(neither.fits_above)
  assert_false(neither.fits_below)
}
