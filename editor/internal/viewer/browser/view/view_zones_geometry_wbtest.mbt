///|
extern "js" fn install_view_zones_geometry_test_dom() -> Unit =
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
  #|       this.style = {
  #|         _owner: this,
  #|         setProperty(name, value) {
  #|           this[name] = String(value);
  #|           const label = this._owner.getAttribute("data-test-id") || this._owner.nodeName;
  #|           globalThis.__viewZonesGeometryEvents.push(`style:${label}:${name}:${String(value)}`);
  #|         },
  #|       };
  #|     }
  #|     setAttribute(name, value) { this.attributes.set(name, String(value)); }
  #|     getAttribute(name) { return this.attributes.get(name) ?? ""; }
  #|     removeAttribute(name) { this.attributes.delete(name); }
  #|     appendChild(child) {
  #|       if (child.parentNode) child.parentNode.removeChild(child);
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
  #|     remove() { if (this.parentNode) this.parentNode.removeChild(this); }
  #|   }
  #|   const document = new EventTarget();
  #|   document.nodeType = 9;
  #|   document.createElement = tag => new TestElement(tag, document);
  #|   globalThis.document = document;
  #|   globalThis.Element = TestElement;
  #|   globalThis.__viewZonesGeometryEvents = [];
  #| }

///|
extern "js" fn clear_view_zones_geometry_events() -> Unit =
  #| () => { globalThis.__viewZonesGeometryEvents.length = 0; }

///|
extern "js" fn record_view_zones_geometry_event(value : String) -> Unit =
  #| value => { globalThis.__viewZonesGeometryEvents.push(value); }

///|
extern "js" fn view_zones_geometry_events() -> FixedArray[String] =
  #| () => [...globalThis.__viewZonesGeometryEvents]

///|
extern "js" fn view_zones_geometry_style(
  element : @rdom.Element,
  name : String,
) -> String =
  #| (element, name) => String(element.style[name] ?? "")

///|
fn geometry_event_index(events : FixedArray[String], expected : String) -> Int {
  for index, event in events {
    if event == expected {
      return index
    }
  }
  -1
}

///|
fn view_zones_geometry_fixture(
  content_width : Double,
  content_left : Double,
) -> (
  ViewZones,
  @rdom.Element,
  @rdom.Element,
  Array[@view_layout.ViewWhitespaceViewportData],
) {
  install_view_zones_geometry_test_dom()
  let document = @rdom.document()
  let part = ViewZones::ViewZones(document, read_initial_configuration=() => {
    (20, content_width, content_left)
  })
  part.dom_node.set_attribute("data-test-id", "content-container")
  part.margin_dom_node.set_attribute("data-test-id", "margin-container")
  let content_zone = document.create_element("div")
  content_zone.set_attribute("data-test-id", "content-zone")
  let margin_zone = document.create_element("div")
  margin_zone.set_attribute("data-test-id", "margin-zone")
  let delegate = @editor_browser.ViewZone::ViewZone(
    1,
    content_zone,
    height_in_px=17.0,
    margin_dom_node=margin_zone,
    on_dom_node_top=_ => record_view_zones_geometry_event("callback:top"),
  )
  let layout = @view_layout.LinesLayout(1, 20, 22, 0)
  let whitespace_id = Ref("")
  layout.change_whitespace(accessor => {
    whitespace_id.val = accessor.insert_whitespace(1, 0, 17.0, 0.0)
  })
  |> ignore
  let registered : RegisteredViewZone = {
    whitespace_id: whitespace_id.val,
    delegate,
    is_in_hidden_area: false,
    is_visible: false,
    dom_node: FastViewZoneDomNode(content_zone),
    margin_dom_node: Some(FastViewZoneDomNode(margin_zone)),
    caller_aria_hidden_present: false,
    caller_aria_hidden_value: "",
  }
  part.zones.set(whitespace_id.val, registered)
  let visible = layout.get_whitespace_viewport_data(0.0, 100.0)
  clear_view_zones_geometry_events()
  (part, content_zone, margin_zone, visible)
}

///|
fn render_geometry_zone(
  part : ViewZones,
  visible : Array[@view_layout.ViewWhitespaceViewportData],
  scroll_width : Double,
) -> Unit {
  part.render(visible, 0, 0.0, scroll_width)
}

///|
test "ViewZones width gate covers below equal above and contentLeft zero nonzero" {
  let cases : Array[(Double, Double, Double, String, String)] = [
    (100.0, 120.0, 0.0, "120px", "0px"),
    (100.0, 100.0, 17.0, "100px", "17px"),
    (120.0, 100.0, 23.0, "120px", "23px"),
  ]
  for case in cases {
    let (
      scroll_width,
      content_width,
      content_left,
      expected_width,
      expected_left,
    ) = case
    let (part, _, _, visible) = view_zones_geometry_fixture(
      content_width, content_left,
    )
    render_geometry_zone(part, visible, scroll_width)
    assert_eq(view_zones_geometry_style(part.dom_node, "width"), expected_width)
    assert_eq(
      view_zones_geometry_style(part.margin_dom_node, "width"),
      expected_left,
    )
  }
}

///|
test "ViewZones writes callbacks and zone geometry before container widths" {
  let (part, _, _, visible) = view_zones_geometry_fixture(120.0, 17.0)
  render_geometry_zone(part, visible, 100.0)
  let events = view_zones_geometry_events()
  let callback = geometry_event_index(events, "callback:top")
  let content_top = geometry_event_index(events, "style:content-zone:top:42px")
  let content_height = geometry_event_index(
    events, "style:content-zone:height:17px",
  )
  let content_display = geometry_event_index(
    events, "style:content-zone:display:block",
  )
  let margin_top = geometry_event_index(events, "style:margin-zone:top:42px")
  let margin_height = geometry_event_index(
    events, "style:margin-zone:height:17px",
  )
  let margin_display = geometry_event_index(
    events, "style:margin-zone:display:block",
  )
  let content_width = geometry_event_index(
    events, "style:content-container:width:120px",
  )
  let margin_width = geometry_event_index(
    events, "style:margin-container:width:17px",
  )
  for
    index in [
      callback, content_top, content_height, content_display, margin_top, margin_height,
      margin_display, content_width, margin_width,
    ] {
    assert_true(index >= 0)
  }
  assert_true(callback < content_top)
  assert_true(content_top < content_height && content_height < content_display)
  assert_true(content_display < margin_top)
  assert_true(margin_top < margin_height && margin_height < margin_display)
  assert_true(margin_display < content_width && content_width < margin_width)
}

///|
test "ViewZones some to none retains both container widths" {
  let (part, _, _, visible) = view_zones_geometry_fixture(120.0, 17.0)
  render_geometry_zone(part, visible, 100.0)
  assert_eq(view_zones_geometry_style(part.dom_node, "width"), "120px")
  assert_eq(view_zones_geometry_style(part.margin_dom_node, "width"), "17px")

  part.content_width = 900.0
  part.content_left = 37.0
  clear_view_zones_geometry_events()
  part.render([], 0, 50.0, 800.0)
  assert_eq(view_zones_geometry_style(part.dom_node, "width"), "120px")
  assert_eq(view_zones_geometry_style(part.margin_dom_node, "width"), "17px")
  for event in view_zones_geometry_events() {
    assert_false(event.contains(":width:"))
  }
}
