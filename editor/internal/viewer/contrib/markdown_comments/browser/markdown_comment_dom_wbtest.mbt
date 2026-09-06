///|
#external
type MarkdownCommentBrowserTestHarness

///|
extern "js" fn install_markdown_comment_browser_test_dom() -> MarkdownCommentBrowserTestHarness =
  #| () => {
  #|   const harness = {
  #|     restored: false,
  #|     originals: {
  #|       document: globalThis.document,
  #|       Element: globalThis.Element,
  #|       HTMLElement: globalThis.HTMLElement,
  #|       ResizeObserver: globalThis.ResizeObserver,
  #|       requestAnimationFrame: globalThis.requestAnimationFrame,
  #|     },
  #|     frames: [],
  #|     observers: [],
  #|     hiddenMeasureCount: 0,
  #|     // 'w' per inline style write, 'r' per hidden height read, in order.
  #|     events: [],
  #|   };
  #|
  #|   class TestStyle {
  #|     constructor() {
  #|       this.values = new Map();
  #|       this.priorities = new Map();
  #|       this.writes = [];
  #|     }
  #|     getPropertyValue(name) { return this.values.get(name) ?? ""; }
  #|     getPropertyPriority(name) { return this.priorities.get(name) ?? ""; }
  #|     setProperty(name, value, priority = "") {
  #|       this.writes.push({ operation: 'set', name: String(name) });
  #|       harness.events.push('w');
  #|       this.values.set(name, String(value));
  #|       if (priority) this.priorities.set(name, String(priority));
  #|       else this.priorities.delete(name);
  #|     }
  #|     removeProperty(name) {
  #|       this.writes.push({ operation: 'remove', name: String(name) });
  #|       harness.events.push('w');
  #|       const previous = this.getPropertyValue(name);
  #|       this.values.delete(name);
  #|       this.priorities.delete(name);
  #|       return previous;
  #|     }
  #|   }
  #|
  #|   class TestElement extends EventTarget {
  #|     constructor(ownerDocument, tag) {
  #|       super();
  #|       this.ownerDocument = ownerDocument;
  #|       this.nodeType = 1;
  #|       this.nodeName = tag.toUpperCase();
  #|       this.tagName = this.nodeName;
  #|       this.attributes = new Map();
  #|       this.childNodes = [];
  #|       this.children = this.childNodes;
  #|       this.parentNode = null;
  #|       this.isConnected = false;
  #|       this.style = new TestStyle();
  #|       this.clientWidth = 0;
  #|       this.__offsetWidth = 0;
  #|       this.__offsetHeight = 0;
  #|       this.__hiddenHeights = null;
  #|     }
  #|     get offsetWidth() { return this.__offsetWidth; }
  #|     set offsetWidth(value) { this.__offsetWidth = Number(value); }
  #|     get offsetHeight() {
  #|       if (this.__offsetHeight > 0) return this.__offsetHeight;
  #|       const outer = this.parentNode;
  #|       if (!this.__hiddenHeights || outer?.style.getPropertyValue('display') !== 'block') return 0;
  #|       harness.hiddenMeasureCount += 1;
  #|       harness.events.push('r');
  #|       const width = Math.trunc(outer.getBoundingClientRect().width);
  #|       return this.__hiddenHeights.get(width) ?? 0;
  #|     }
  #|     set offsetHeight(value) { this.__offsetHeight = Number(value); }
  #|     getBoundingClientRect() {
  #|       return {
  #|         left: 0,
  #|         right: this.__offsetWidth,
  #|         top: 0,
  #|         bottom: this.__offsetHeight,
  #|         width: this.__offsetWidth,
  #|         height: this.__offsetHeight,
  #|       };
  #|     }
  #|     setAttribute(name, value) { this.attributes.set(name, String(value)); }
  #|     getAttribute(name) { return this.attributes.get(name) ?? ""; }
  #|     hasAttribute(name) { return this.attributes.has(name); }
  #|     removeAttribute(name) { this.attributes.delete(name); }
  #|     closest(selector) {
  #|       if (!selector.startsWith('.')) return null;
  #|       const wanted = selector.slice(1);
  #|       for (let current = this; current; current = current.parentNode) {
  #|         const classes = (current.getAttribute?.('class') ?? '').split(/\s+/);
  #|         if (classes.includes(wanted)) return current;
  #|       }
  #|       return null;
  #|     }
  #|     appendChild(child) {
  #|       child.parentNode?.removeChild(child);
  #|       this.childNodes.push(child);
  #|       this.children = this.childNodes;
  #|       child.parentNode = this;
  #|       return child;
  #|     }
  #|     removeChild(child) {
  #|       this.childNodes = this.childNodes.filter(candidate => candidate !== child);
  #|       this.children = this.childNodes;
  #|       child.parentNode = null;
  #|       return child;
  #|     }
  #|   }
  #|
  #|   class TestResizeObserver {
  #|     constructor(callback) {
  #|       this.callback = callback;
  #|       this.target = null;
  #|       this.targets = [];
  #|       this.disconnectCount = 0;
  #|       harness.observers.push(this);
  #|     }
  #|     observe(target) {
  #|       this.target ??= target;
  #|       this.targets.push(target);
  #|     }
  #|     disconnect() { this.disconnectCount += 1; }
  #|     triggerLate(target = this.target) { this.callback([{ target }], this); }
  #|   }
  #|
  #|   const document = {
  #|     nodeType: 9,
  #|     createElement(tag) { return new TestElement(document, tag); },
  #|   };
  #|   globalThis.document = document;
  #|   globalThis.Element = TestElement;
  #|   globalThis.HTMLElement = TestElement;
  #|   globalThis.ResizeObserver = TestResizeObserver;
  #|   globalThis.requestAnimationFrame = callback => {
  #|     harness.frames.push(callback);
  #|     return harness.frames.length;
  #|   };
  #|   return harness;
  #| }

///|
extern "js" fn MarkdownCommentBrowserTestHarness::dispose(
  self : MarkdownCommentBrowserTestHarness,
) -> Unit =
  #| harness => {
  #|   if (harness.restored) return;
  #|   harness.restored = true;
  #|   const restore = (name, value) => {
  #|     if (value === undefined) delete globalThis[name];
  #|     else globalThis[name] = value;
  #|   };
  #|   restore('document', harness.originals.document);
  #|   restore('Element', harness.originals.Element);
  #|   restore('HTMLElement', harness.originals.HTMLElement);
  #|   restore('ResizeObserver', harness.originals.ResizeObserver);
  #|   restore('requestAnimationFrame', harness.originals.requestAnimationFrame);
  #| }

///|
extern "js" fn markdown_comment_test_attribute(
  element : @rdom.Element,
  name : String,
) -> String = "(element, name) => element.getAttribute(name)"

///|
extern "js" fn markdown_comment_test_has_attribute(
  element : @rdom.Element,
  name : String,
) -> Bool = "(element, name) => element.hasAttribute(name)"

///|
extern "js" fn markdown_comment_test_child_count(
  element : @rdom.Element,
) -> Int = "element => element.childNodes.length"

///|
extern "js" fn markdown_comment_test_first_child(
  element : @rdom.Element,
) -> @rdom.Element = "element => element.childNodes[0]"

///|
extern "js" fn markdown_comment_test_same_element(
  left : @rdom.Element,
  right : @rdom.Element,
) -> Bool = "(left, right) => left === right"

///|
extern "js" fn markdown_comment_test_child(
  element : @rdom.Element,
  index : Int,
) -> @rdom.Element = "(element, index) => element.childNodes[index]"

///|
extern "js" fn markdown_comment_test_dispatch(
  element : @rdom.Element,
  event_type : String,
) -> Unit = "(element, type) => element.dispatchEvent(new Event(type, { cancelable: true }))"

///|
extern "js" fn markdown_comment_test_set_measurement(
  element : @rdom.Element,
  connected : Bool,
  height : Double,
) -> Unit =
  #| (element, connected, height) => {
  #|   element.isConnected = connected;
  #|   element.offsetHeight = height;
  #| }

///|
extern "js" fn markdown_comment_test_trigger_resize(
  harness : MarkdownCommentBrowserTestHarness,
) -> Unit =
  #| harness => {
  #|   const observer = harness.observers.at(-1);
  #|   if (!observer) throw new Error("missing ResizeObserver");
  #|   observer.triggerLate();
  #| }

///|
extern "js" fn markdown_comment_test_trigger_resize_for(
  harness : MarkdownCommentBrowserTestHarness,
  element : @rdom.Element,
) -> Unit =
  #| (harness, element) => {
  #|   const observer = harness.observers
  #|     .findLast(candidate => candidate.targets.includes(element));
  #|   if (!observer) throw new Error("missing ResizeObserver");
  #|   observer.triggerLate(element);
  #| }

///|
extern "js" fn markdown_comment_test_observes(
  harness : MarkdownCommentBrowserTestHarness,
  element : @rdom.Element,
) -> Bool =
  #| (harness, element) => harness.observers
  #|   .some(observer => observer.targets.includes(element))

///|
extern "js" fn markdown_comment_test_observer_count(
  harness : MarkdownCommentBrowserTestHarness,
) -> Int = "harness => harness.observers.length"

///|
extern "js" fn markdown_comment_test_observer_target_count(
  harness : MarkdownCommentBrowserTestHarness,
  index : Int,
) -> Int =
  #| (harness, index) => harness.observers[index]?.targets.length ?? 0

///|
extern "js" fn markdown_comment_test_mount_offscreen(
  outer : @rdom.Element,
  content : @rdom.Element,
  viewport_width : Int,
  wide_height : Int,
  narrow_width : Int,
  narrow_height : Int,
) -> @rdom.Element =
  #| (outer, content, viewportWidth, wideHeight, narrowWidth, narrowHeight) => {
  #|   const viewport = document.createElement('div');
  #|   viewport.setAttribute('class', 'editor-scrollable');
  #|   viewport.clientWidth = viewportWidth;
  #|   viewport.isConnected = true;
  #|   viewport.__markdownCommentOuter = outer;
  #|   viewport.appendChild(outer);
  #|   outer.isConnected = true;
  #|   const pinnedWidth = Math.max(0, viewportWidth - 14);
  #|   const narrowPinnedWidth = Math.max(0, narrowWidth - 14);
  #|   outer.offsetWidth = pinnedWidth;
  #|   content.isConnected = true;
  #|   outer.style.setProperty('display', 'none');
  #|   outer.style.setProperty('height', '0px');
  #|   outer.style.setProperty('top', '7px');
  #|   content.__hiddenHeights = new Map([
  #|     [pinnedWidth, wideHeight],
  #|     [narrowPinnedWidth, narrowHeight],
  #|   ]);
  #|   return viewport;
  #| }

///|
extern "js" fn markdown_comment_test_set_viewport_width(
  viewport : @rdom.Element,
  width : Int,
) -> Unit =
  #| (viewport, width) => {
  #|   viewport.clientWidth = width;
  #|   if (viewport.__markdownCommentOuter) {
  #|     viewport.__markdownCommentOuter.offsetWidth =
  #|       Math.max(0, width - 14);
  #|   }
  #| }

///|
extern "js" fn markdown_comment_test_offset_width(
  element : @rdom.Element,
) -> Int = "element => Math.trunc(element.offsetWidth)"

///|
extern "js" fn markdown_comment_test_style(
  element : @rdom.Element,
  name : String,
) -> String = "(element, name) => element.style.getPropertyValue(name)"

///|
extern "js" fn markdown_comment_test_clear_style_writes(
  element : @rdom.Element,
) -> Unit = "element => { element.style.writes.length = 0; }"

///|
extern "js" fn markdown_comment_test_style_write_count(
  element : @rdom.Element,
  name : String,
) -> Int =
  #| (element, name) => element.style.writes
  #|   .filter(write => write.name === name).length

///|
extern "js" fn markdown_comment_test_set_style(
  element : @rdom.Element,
  name : String,
  value : String,
) -> Unit = "(element, name, value) => element.style.setProperty(name, value)"

///|
extern "js" fn markdown_comment_test_outer_style(
  element : @rdom.Element,
) -> String =
  #| element => ['display', 'visibility', 'pointer-events', 'height', 'width', 'top', 'left']
  #|   .map(name => `${name}=${element.style.getPropertyValue(name)}!${element.style.getPropertyPriority(name)}`)
  #|   .join(';')

///|
extern "js" fn markdown_comment_test_hidden_measure_count(
  harness : MarkdownCommentBrowserTestHarness,
) -> Int = "harness => harness.hiddenMeasureCount"

///|
extern "js" fn markdown_comment_test_events(
  harness : MarkdownCommentBrowserTestHarness,
) -> String = "harness => harness.events.join('')"

///|
extern "js" fn markdown_comment_test_clear_events(
  harness : MarkdownCommentBrowserTestHarness,
) -> Unit = "harness => { harness.events.length = 0; }"

///|
extern "js" fn markdown_comment_test_disconnect_count(
  harness : MarkdownCommentBrowserTestHarness,
) -> Int =
  #| harness => harness.observers
  #|   .reduce((sum, observer) => sum + observer.disconnectCount, 0)

///|
extern "js" fn markdown_comment_test_pending_frame_count(
  harness : MarkdownCommentBrowserTestHarness,
) -> Int = "harness => harness.frames.length"

///|
extern "js" fn markdown_comment_test_flush_frame(
  harness : MarkdownCommentBrowserTestHarness,
) -> Unit =
  #| harness => {
  #|   const callback = harness.frames.shift();
  #|   if (!callback) throw new Error("missing animation frame");
  #|   callback(0);
  #| }

///|
test "MarkdownCommentDom creates the stable half-open ViewZone target shape" {
  let harness = install_markdown_comment_browser_test_dom()
  defer harness.dispose()
  let dom = MarkdownCommentDom(3, 7)
  assert_eq(
    markdown_comment_test_attribute(dom.outer, "class"),
    "moonbit-viewer-markdown-comment",
  )
  assert_eq(markdown_comment_test_attribute(dom.outer, "data-start-line"), "3")
  assert_eq(markdown_comment_test_attribute(dom.outer, "data-end-line"), "7")
  assert_eq(
    markdown_comment_test_attribute(dom.content, "class"),
    "moonbit-viewer-markdown-comment-content",
  )
  assert_eq(markdown_comment_test_child_count(dom.outer), 3)
  assert_true(
    markdown_comment_test_same_element(
      markdown_comment_test_first_child(dom.outer),
      dom.source_toggle,
    ),
  )
  assert_true(
    markdown_comment_test_same_element(
      markdown_comment_test_child(dom.outer, 1),
      dom.toggle,
    ),
  )
  assert_true(
    markdown_comment_test_same_element(
      markdown_comment_test_child(dom.outer, 2),
      dom.content,
    ),
  )
  assert_eq(markdown_comment_test_child_count(dom.content), 3)
  assert_true(
    markdown_comment_test_same_element(
      markdown_comment_test_child(dom.content, 0),
      dom.full,
    ),
  )
  assert_true(
    markdown_comment_test_same_element(
      markdown_comment_test_child(dom.content, 1),
      dom.preview,
    ),
  )
  assert_true(
    markdown_comment_test_same_element(
      markdown_comment_test_child(dom.content, 2),
      dom.source,
    ),
  )
  assert_eq(
    markdown_comment_test_attribute(dom.outer, "data-documentation-foldable"),
    "false",
  )
  assert_eq(markdown_comment_test_attribute(dom.toggle, "hidden"), "")
  assert_eq(
    markdown_comment_test_attribute(dom.source_toggle, "aria-label"),
    "Original source",
  )
  assert_eq(
    markdown_comment_test_attribute(dom.source_toggle, "aria-pressed"),
    "false",
  )
  assert_eq(
    markdown_comment_test_attribute(dom.margin, "class"),
    "moonbit-viewer-markdown-comment-margin",
  )
  assert_eq(markdown_comment_test_child_count(dom.margin), 1)
  assert_true(
    markdown_comment_test_same_element(
      markdown_comment_test_first_child(dom.margin),
      dom.margin_toggle,
    ),
  )
  assert_eq(
    markdown_comment_test_attribute(dom.margin_toggle, "class"),
    "moonbit-viewer-markdown-comment-margin-toggle cldr codicon codicon-folding-collapsed",
  )
  assert_eq(markdown_comment_test_attribute(dom.margin_toggle, "hidden"), "")
  dom.set_margin_fold_lane_width(28)
  assert_eq(markdown_comment_test_style(dom.margin_toggle, "width"), "28px")
  dom.outer.set_attribute("aria-hidden", "true")
  dom.expose_accessible_content()
  assert_false(markdown_comment_test_has_attribute(dom.outer, "aria-hidden"))
}

///|
test "MarkdownCommentDom toggles one source target independently and releases listeners" {
  let harness = install_markdown_comment_browser_test_dom()
  defer harness.dispose()
  let dom = MarkdownCommentDom(3, 7)
  let source_visible = Ref(false)
  let toggles = Ref(0)
  let lifetime = dom.enable_source_toggle(source_visible, () => toggles.val += 1)
  assert_eq(
    markdown_comment_test_attribute(dom.outer, "data-source-visible"),
    "false",
  )
  assert_eq(
    markdown_comment_test_attribute(dom.margin, "data-source-visible"),
    "false",
  )
  assert_eq(
    markdown_comment_test_attribute(dom.source_toggle, "aria-label"),
    "Original source",
  )
  assert_eq(
    markdown_comment_test_attribute(dom.source_toggle, "title"),
    "Show original source",
  )

  markdown_comment_test_dispatch(dom.source_toggle, "click")
  assert_true(source_visible.val)
  assert_eq(toggles.val, 1)
  assert_eq(
    markdown_comment_test_attribute(dom.outer, "data-source-visible"),
    "true",
  )
  assert_eq(
    markdown_comment_test_attribute(dom.margin, "data-source-visible"),
    "true",
  )
  assert_eq(
    markdown_comment_test_attribute(dom.source_toggle, "aria-pressed"),
    "true",
  )
  assert_eq(
    markdown_comment_test_attribute(dom.source_toggle, "aria-label"),
    "Original source",
  )
  assert_eq(
    markdown_comment_test_attribute(dom.source_toggle, "title"),
    "Show rendered documentation",
  )

  markdown_comment_test_dispatch(dom.source_toggle, "click")
  assert_false(source_visible.val)
  assert_eq(toggles.val, 2)
  lifetime.dispose()
  lifetime.dispose()
  markdown_comment_test_dispatch(dom.source_toggle, "click")
  assert_false(source_visible.val)
  assert_eq(toggles.val, 2)
}

///|
test "MarkdownCommentDom toggles accessible folding state and releases listeners" {
  let harness = install_markdown_comment_browser_test_dom()
  defer harness.dispose()
  let dom = MarkdownCommentDom(3, 7)
  let expanded = Ref(false)
  let toggles = Ref(0)
  let lifetime = dom.enable_folding(expanded, () => toggles.val += 1)
  assert_eq(
    markdown_comment_test_attribute(dom.outer, "data-documentation-foldable"),
    "true",
  )
  assert_eq(
    markdown_comment_test_attribute(dom.outer, "data-documentation-expanded"),
    "false",
  )
  assert_eq(
    markdown_comment_test_attribute(dom.toggle, "aria-expanded"),
    "false",
  )
  assert_eq(
    markdown_comment_test_attribute(dom.toggle, "aria-label"),
    "Expand API documentation",
  )
  assert_eq(
    markdown_comment_test_attribute(dom.toggle_icon, "class"),
    "codicon codicon-chevron-right",
  )
  assert_false(markdown_comment_test_has_attribute(dom.margin_toggle, "hidden"))
  assert_eq(
    markdown_comment_test_attribute(dom.margin_toggle, "class"),
    "moonbit-viewer-markdown-comment-margin-toggle cldr codicon codicon-folding-collapsed",
  )
  assert_eq(
    markdown_comment_test_attribute(dom.margin_toggle, "title"),
    "Expand API documentation",
  )

  markdown_comment_test_dispatch(dom.margin_toggle, "click")
  assert_true(expanded.val)
  assert_eq(toggles.val, 1)
  assert_eq(
    markdown_comment_test_attribute(dom.outer, "data-documentation-expanded"),
    "true",
  )
  assert_eq(
    markdown_comment_test_attribute(dom.toggle, "aria-expanded"),
    "true",
  )
  assert_eq(
    markdown_comment_test_attribute(dom.toggle, "aria-label"),
    "Collapse API documentation",
  )
  assert_eq(
    markdown_comment_test_attribute(dom.toggle_icon, "class"),
    "codicon codicon-chevron-down",
  )
  assert_eq(
    markdown_comment_test_attribute(dom.margin_toggle, "class"),
    "moonbit-viewer-markdown-comment-margin-toggle cldr codicon codicon-folding-expanded",
  )
  assert_eq(
    markdown_comment_test_attribute(dom.margin_toggle, "title"),
    "Collapse API documentation",
  )

  markdown_comment_test_dispatch(dom.toggle, "click")
  assert_false(expanded.val)
  assert_eq(toggles.val, 2)
  lifetime.dispose()
  lifetime.dispose()
  markdown_comment_test_dispatch(dom.toggle, "click")
  markdown_comment_test_dispatch(dom.margin_toggle, "click")
  assert_false(expanded.val)
  assert_eq(toggles.val, 2)

  dom.disable_folding()
  assert_eq(
    markdown_comment_test_attribute(dom.outer, "data-documentation-foldable"),
    "false",
  )
  assert_eq(
    markdown_comment_test_attribute(dom.outer, "data-documentation-expanded"),
    "true",
  )
  assert_eq(markdown_comment_test_attribute(dom.toggle, "aria-hidden"), "true")
  assert_eq(markdown_comment_test_attribute(dom.margin_toggle, "hidden"), "")
  assert_false(markdown_comment_test_has_attribute(dom.margin_toggle, "title"))
}

///|
test "MarkdownCommentDom pins outer geometry to ViewLines viewport variables" {
  let harness = install_markdown_comment_browser_test_dom()
  defer harness.dispose()
  let dom = MarkdownCommentDom(3, 7)
  // Simulate the ordinary ViewZone add write that this helper must replace.
  markdown_comment_test_set_style(dom.outer, "left", "0px")
  markdown_comment_test_set_style(dom.outer, "width", "100%")
  dom.pin_to_content_viewport()
  assert_eq(
    markdown_comment_test_style(dom.outer, "left"),
    "var(--moonbit-viewer-rendered-scroll-left, 0px)",
  )
  assert_eq(
    markdown_comment_test_style(dom.outer, "width"),
    "var(--moonbit-viewer-visible-content-width, 0px)",
  )
}

///|
test "size observation coalesces and reports positive changed integer heights" {
  let harness = install_markdown_comment_browser_test_dom()
  defer harness.dispose()
  let dom = MarkdownCommentDom(1, 2)
  let observed : Array[Int] = []
  let batch = MarkdownCommentMeasureBatch(on_pass_complete=() => ())
  let lifetime = dom.observe_size(batch, height => observed.push(height))
  assert_true(markdown_comment_test_observes(harness, dom.content))
  assert_eq(markdown_comment_test_observer_count(harness), 1)
  assert_eq(markdown_comment_test_observer_target_count(harness, 0), 1)
  markdown_comment_test_set_measurement(dom.content, true, 18.9)
  markdown_comment_test_trigger_resize(harness)
  markdown_comment_test_trigger_resize(harness)
  markdown_comment_test_trigger_resize(harness)
  assert_eq(markdown_comment_test_pending_frame_count(harness), 1)
  // The frame reads the latest geometry, not the first observer payload.
  markdown_comment_test_set_measurement(dom.content, true, 27.9)
  markdown_comment_test_flush_frame(harness)
  assert_eq(observed, [27])

  markdown_comment_test_trigger_resize(harness)
  markdown_comment_test_flush_frame(harness)
  assert_eq(observed, [27])

  markdown_comment_test_set_measurement(dom.content, true, 31.0)
  markdown_comment_test_trigger_resize(harness)
  markdown_comment_test_trigger_resize(harness)
  assert_eq(markdown_comment_test_pending_frame_count(harness), 1)
  markdown_comment_test_flush_frame(harness)
  assert_eq(observed, [27, 31])
  lifetime.dispose()
  lifetime.dispose()
  assert_eq(markdown_comment_test_disconnect_count(harness), 1)
}

///|
test "disconnected zero queued and late observer callbacks are inert" {
  let harness = install_markdown_comment_browser_test_dom()
  defer harness.dispose()
  let dom = MarkdownCommentDom(5, 6)
  let observed : Array[Int] = []
  let batch = MarkdownCommentMeasureBatch(on_pass_complete=() => ())
  let lifetime = dom.observe_size(batch, height => observed.push(height))

  markdown_comment_test_set_measurement(dom.content, false, 20.0)
  markdown_comment_test_trigger_resize(harness)
  markdown_comment_test_flush_frame(harness)
  assert_true(observed.is_empty())

  markdown_comment_test_set_measurement(dom.content, true, 0.0)
  markdown_comment_test_trigger_resize(harness)
  markdown_comment_test_flush_frame(harness)
  assert_true(observed.is_empty())

  markdown_comment_test_set_measurement(dom.content, true, 22.0)
  markdown_comment_test_trigger_resize(harness)
  markdown_comment_test_flush_frame(harness)
  assert_eq(observed, [22])

  markdown_comment_test_set_measurement(dom.content, true, 40.0)
  markdown_comment_test_trigger_resize(harness)
  assert_eq(markdown_comment_test_pending_frame_count(harness), 1)
  lifetime.dispose()
  lifetime.dispose()
  assert_eq(markdown_comment_test_disconnect_count(harness), 1)
  // The native frame still drains the shared coordinator, whose canceled
  // registration and disposed guard both keep the root callback inert.
  markdown_comment_test_flush_frame(harness)
  assert_eq(observed, [22])

  // Simulate a browser-delivered ResizeObserver callback that was already
  // queued when disconnect ran.
  markdown_comment_test_trigger_resize(harness)
  assert_eq(markdown_comment_test_pending_frame_count(harness), 0)
  assert_eq(observed, [22])
}

///|
test "offscreen measurement retains pinned width and offset and avoids zero feedback" {
  let harness = install_markdown_comment_browser_test_dom()
  defer harness.dispose()
  let dom = MarkdownCommentDom(81, 91)
  dom.pin_to_content_viewport()
  let viewport = markdown_comment_test_mount_offscreen(
    dom.outer,
    dom.content,
    320,
    96,
    180,
    154,
  )
  // The editor viewport is 320px, but the already-pinned Markdown surface
  // excludes the fixed 14px vertical rail.
  assert_eq(markdown_comment_test_offset_width(dom.outer), 306)
  let original_style = markdown_comment_test_outer_style(dom.outer)
  let observed : Array[Int] = []
  let batch = MarkdownCommentMeasureBatch(on_pass_complete=() => ())
  let observer = dom.observe_size(batch, height => observed.push(height))
  let viewport_observer = dom.observe_viewport_width(() => {
    observer.request_measure()
  })
  assert_true(markdown_comment_test_observes(harness, dom.content))
  assert_true(markdown_comment_test_observes(harness, viewport))
  assert_eq(markdown_comment_test_observer_count(harness), 2)
  assert_eq(markdown_comment_test_observer_target_count(harness, 0), 1)
  assert_eq(markdown_comment_test_observer_target_count(harness, 1), 1)
  markdown_comment_test_clear_style_writes(dom.outer)

  observer.request_measure()
  observer.request_measure()
  assert_eq(markdown_comment_test_pending_frame_count(harness), 1)
  markdown_comment_test_flush_frame(harness)
  assert_eq(observed, [96])
  assert_eq(markdown_comment_test_hidden_measure_count(harness), 1)
  assert_eq(markdown_comment_test_outer_style(dom.outer), original_style)
  assert_eq(markdown_comment_test_style_write_count(dom.outer, "width"), 0)
  assert_eq(markdown_comment_test_style_write_count(dom.outer, "left"), 0)

  // The zero-size target callback caused by restoring `display:none` must not
  // enter the forced hidden path again or produce a frame-to-frame loop.
  markdown_comment_test_trigger_resize_for(harness, dom.content)
  markdown_comment_test_flush_frame(harness)
  assert_eq(observed, [96])
  assert_eq(markdown_comment_test_hidden_measure_count(harness), 1)

  // A viewport observation is an explicit width invalidation even while the
  // ViewZone remains display:none.
  markdown_comment_test_set_viewport_width(viewport, 180)
  markdown_comment_test_trigger_resize_for(harness, viewport)
  markdown_comment_test_flush_frame(harness)
  assert_eq(markdown_comment_test_offset_width(dom.outer), 166)
  assert_eq(observed, [96, 154])
  assert_eq(markdown_comment_test_hidden_measure_count(harness), 2)
  assert_eq(markdown_comment_test_outer_style(dom.outer), original_style)
  assert_eq(markdown_comment_test_style_write_count(dom.outer, "width"), 0)
  assert_eq(markdown_comment_test_style_write_count(dom.outer, "left"), 0)

  // An equal positive width is deduplicated by the shared observer.
  markdown_comment_test_trigger_resize_for(harness, viewport)
  assert_eq(markdown_comment_test_pending_frame_count(harness), 0)

  // Zero is remembered but not measured. Restoring the same positive width
  // still invalidates because content may have laid out while the host was
  // collapsed.
  markdown_comment_test_set_viewport_width(viewport, 0)
  markdown_comment_test_trigger_resize_for(harness, viewport)
  assert_eq(markdown_comment_test_pending_frame_count(harness), 0)
  markdown_comment_test_set_viewport_width(viewport, 180)
  markdown_comment_test_trigger_resize_for(harness, viewport)
  assert_eq(markdown_comment_test_pending_frame_count(harness), 1)
  markdown_comment_test_flush_frame(harness)
  assert_eq(observed, [96, 154])
  assert_eq(markdown_comment_test_hidden_measure_count(harness), 3)
  assert_eq(markdown_comment_test_style_write_count(dom.outer, "width"), 0)
  assert_eq(markdown_comment_test_style_write_count(dom.outer, "left"), 0)

  viewport_observer.dispose()
  viewport_observer.dispose()
  observer.dispose()
  observer.request_measure()
  assert_eq(markdown_comment_test_pending_frame_count(harness), 0)
  assert_eq(markdown_comment_test_disconnect_count(harness), 2)

  // Browser-delivered callbacks already queued before disconnect are inert.
  markdown_comment_test_set_viewport_width(viewport, 240)
  markdown_comment_test_trigger_resize_for(harness, viewport)
  assert_eq(markdown_comment_test_pending_frame_count(harness), 0)
}

///|
test "a batch lays out every offscreen zone in one frame and completes once" {
  let harness = install_markdown_comment_browser_test_dom()
  defer harness.dispose()
  let first = MarkdownCommentDom(1, 3)
  let second = MarkdownCommentDom(10, 12)
  first.pin_to_content_viewport()
  second.pin_to_content_viewport()
  markdown_comment_test_mount_offscreen(
    first.outer,
    first.content,
    320,
    40,
    180,
    60,
  )
  |> ignore
  markdown_comment_test_mount_offscreen(
    second.outer,
    second.content,
    320,
    70,
    180,
    90,
  )
  |> ignore
  let first_style = markdown_comment_test_outer_style(first.outer)
  let second_style = markdown_comment_test_outer_style(second.outer)
  let completed = Ref(0)
  let observed : Array[(Int, Int)] = []
  let batch = MarkdownCommentMeasureBatch(on_pass_complete=() => {
    completed.val += 1
  })
  let first_observer = first.observe_size(batch, height => {
    // Reports run after every zone's styles are restored, inside the pass.
    assert_true(batch.in_pass()) catch {
      _ => abort("report outside the measurement pass")
    }
    if markdown_comment_test_style(second.outer, "display") != "none" {
      abort("report before every zone's styles were restored")
    }
    observed.push((1, height))
  })
  let second_observer = second.observe_size(batch, height => {
    observed.push((2, height))
  })
  markdown_comment_test_clear_events(harness)
  first_observer.request_measure()
  second_observer.request_measure()
  second_observer.request_measure()
  // Both zones share one animation frame.
  assert_eq(markdown_comment_test_pending_frame_count(harness), 1)
  assert_false(batch.in_pass())
  markdown_comment_test_flush_frame(harness)
  assert_eq(observed, [(1, 40), (2, 70)])
  assert_eq(completed.val, 1)
  assert_false(batch.in_pass())
  assert_eq(markdown_comment_test_hidden_measure_count(harness), 2)
  // Every hidden zone is shown before any height is read, and every style is
  // restored afterwards: five writes per zone, then one read per zone, then
  // five restores per zone.
  assert_eq(
    markdown_comment_test_events(harness),
    "wwwwwwwwww" + "rr" + "wwwwwwwwww",
  )
  assert_eq(markdown_comment_test_outer_style(first.outer), first_style)
  assert_eq(markdown_comment_test_outer_style(second.outer), second_style)

  // A disposed batch ignores later requests without scheduling frames.
  batch.dispose()
  batch.dispose()
  first_observer.request_measure()
  assert_eq(markdown_comment_test_pending_frame_count(harness), 0)
  first_observer.dispose()
  second_observer.dispose()
  assert_eq(markdown_comment_test_disconnect_count(harness), 2)
  assert_eq(completed.val, 1)
}
