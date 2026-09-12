///|
extern "js" fn install_view_lifecycle_test_browser() -> Unit =
  #| () => {
  #|   class TestElement extends EventTarget {
  #|     constructor(tag = "div") {
  #|       super();
  #|       this.nodeType = 1;
  #|       this.nodeName = tag.toUpperCase();
  #|       this.attributes = new Map();
  #|       this.childNodes = [];
  #|       this.children = this.childNodes;
  #|       this.parentNode = null;
  #|       this.style = {
  #|         setProperty(name, value) { this[name] = value; },
  #|       };
  #|       this.scrollTop = 0;
  #|       this.scrollLeft = 0;
  #|       this.scrollWidth = 1000;
  #|       this.scrollHeight = 1000;
  #|     }
  #|     setAttribute(name, value) {
  #|       this.attributes.set(name, String(value));
  #|       this.attributeWriteCount ??= new Map();
  #|       this.attributeWriteCount.set(name, (this.attributeWriteCount.get(name) ?? 0) + 1);
  #|     }
  #|     getAttribute(name) { return this.attributes.get(name) ?? ""; }
  #|     removeAttribute(name) { this.attributes.delete(name); }
  #|     appendChild(child) {
  #|       if (child.parentNode) child.parentNode.removeChild(child);
  #|       this.childNodes.push(child);
  #|       child.parentNode = this;
  #|       return child;
  #|     }
  #|     removeChild(child) {
  #|       this.childNodes = this.childNodes.filter((item) => item !== child);
  #|       this.children = this.childNodes;
  #|       child.parentNode = null;
  #|       return child;
  #|     }
  #|     getBoundingClientRect() {
  #|       return {
  #|         x: 0, y: 0, left: 0, top: 0,
  #|         right: 100, bottom: 100, width: 100, height: 100,
  #|       };
  #|     }
  #|   }
  #|   const ownerDocument = new EventTarget();
  #|   ownerDocument.nodeType = 9;
  #|   ownerDocument.createElement = (tag) => new TestElement(tag);
  #|   globalThis.document = ownerDocument;
  #|   globalThis.Element = TestElement;
  #|   globalThis.__viewLifecycleOriginalSetTimeout = globalThis.setTimeout;
  #|   globalThis.__viewLifecycleOriginalClearTimeout = globalThis.clearTimeout;
  #|   globalThis.__viewLifecycleTimerNextId = 1;
  #|   globalThis.__viewLifecycleTimers = new Map();
  #|   globalThis.__viewLifecycleClearCount = 0;
  #|   globalThis.setTimeout = (callback, _ms) => {
  #|     const id = globalThis.__viewLifecycleTimerNextId++;
  #|     globalThis.__viewLifecycleTimers.set(id, callback);
  #|     return id;
  #|   };
  #|   globalThis.clearTimeout = (id) => {
  #|     globalThis.__viewLifecycleClearCount += 1;
  #|     globalThis.__viewLifecycleTimers.delete(id);
  #|   };
  #| }

///|
extern "js" fn restore_view_lifecycle_test_browser() -> Unit =
  #| () => {
  #|   globalThis.setTimeout = globalThis.__viewLifecycleOriginalSetTimeout;
  #|   globalThis.clearTimeout = globalThis.__viewLifecycleOriginalClearTimeout;
  #| }

///|
extern "js" fn view_lifecycle_test_clear_count() -> Int =
  #| () => globalThis.__viewLifecycleClearCount

///|
extern "js" fn view_lifecycle_test_has_parent(
  child : @rdom.Element,
  parent : @rdom.Element,
) -> Bool =
  #| (child, parent) => child.parentNode === parent

///|
extern "js" fn view_lifecycle_test_child_index(
  parent : @rdom.Element,
  child : @rdom.Element,
) -> Int =
  #| (parent, child) => parent.childNodes.indexOf(child)

///|
test "View mounts both ViewZones containers at the source relative positions" {
  install_view_lifecycle_test_browser()
  let view = View::View()
  let margin = view.margin_view_overlays.get_dom_node()
  assert_eq(
    view_lifecycle_test_child_index(margin, view.view_zones.margin_dom_node()),
    0,
  )
  assert_eq(
    view_lifecycle_test_child_index(
      margin,
      view.margin_view_overlays.overlays.dom_node.element(),
    ),
    1,
  )
  let lines_content = view.view_lines.lines_content.element()
  assert_true(
    view_lifecycle_test_child_index(
      lines_content,
      view.content_view_overlays.get_dom_node(),
    ) <
    view_lifecycle_test_child_index(lines_content, view.view_zones.dom_node()),
  )
  assert_true(
    view_lifecycle_test_child_index(lines_content, view.view_zones.dom_node()) <
    view_lifecycle_test_child_index(
      lines_content,
      view.view_lines.get_dom_node(),
    ),
  )
  assert_eq(
    view.view_zones.dom_node().get_attribute("role"),
    Some("presentation"),
  )
  // The lightweight DOM binding normalizes an absent attribute to `Some("")`.
  assert_eq(view.view_zones.dom_node().get_attribute("aria-hidden"), Some(""))
  assert_eq(
    view.view_zones.margin_dom_node().get_attribute("class"),
    Some("margin-view-zones"),
  )
  assert_eq(
    view.view_zones.margin_dom_node().get_attribute("aria-hidden"),
    Some("true"),
  )
  restore_view_lifecycle_test_browser()
}

///|
test "View disposes ViewParts before its lifetime store exactly once" {
  install_view_lifecycle_test_browser()
  let view = View::View()
  assert_true(
    view_lifecycle_test_has_parent(
      view.content_widgets.overflowing_content_widgets_dom_node(),
      view.root,
    ),
  )
  assert_true(
    view_lifecycle_test_has_parent(
      view.overlay_widgets.overflowing_overlay_widgets_dom_node(),
      view.root,
    ),
  )
  let scrollable = view.editor_scrollbar.scrollable()
  scrollable.update_from_model(
    {
      width: 100.0,
      scroll_width: 1000.0,
      height: 100.0,
      scroll_height: 1000.0,
    },
    { scroll_left: 0.0, scroll_top: 0.0, },
  )
  scrollable.reveal_for_scroll()
  assert_eq(
    scrollable.track(true).get_attribute("class"),
    Some("visible scrollbar vertical"),
  )
  scrollable.set_slider_active(vertical=true, true)
  let vertical_slider = scrollable.slider(true)
  assert_eq(vertical_slider.get_attribute("class"), Some("slider active"))

  let mut base_dispose_count = 0
  let mut scrollbar_was_already_disposed = false
  view.add_disposable(
    @base_common.Disposable::from(() => {
      base_dispose_count += 1
      scrollbar_was_already_disposed = vertical_slider.get_attribute("class") ==
        Some("slider")
    }),
  )
  view.dispose()
  assert_true(view.disposed)
  assert_eq(vertical_slider.get_attribute("class"), Some("slider"))
  assert_true(scrollbar_was_already_disposed)
  assert_eq(base_dispose_count, 1)
  assert_eq(view_lifecycle_test_clear_count(), 1)
  assert_true(view.lifetime_disposables.is_empty())

  // Repeated disposal neither re-runs a ViewPart nor drains the base store a
  // second time. Late registration is released immediately.
  view.dispose()
  assert_eq(base_dispose_count, 1)
  assert_eq(view_lifecycle_test_clear_count(), 1)
  let mut late_dispose_count = 0
  view.add_disposable(
    @base_common.Disposable::from(() => late_dispose_count += 1),
  )
  assert_eq(late_dispose_count, 1)
  assert_true(view.lifetime_disposables.is_empty())
  restore_view_lifecycle_test_browser()
}
