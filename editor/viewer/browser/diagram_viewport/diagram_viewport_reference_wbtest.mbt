// Shared Editor/Desktop diagram viewport algorithm/behavior reference coverage for:
// - vscode/extensions/mermaid-markdown-features/preview-src/shared/diagramManager.ts
// - vscode/extensions/mermaid-markdown-features/preview-src/shared/diagramStyles.css
// - vscode/extensions/mermaid-markdown-features/preview-src/chat/mermaidWebview.ts
// pinned at b18492a288de038fbc7643aae6de8247029d11bd.
//
// The product deviations exercised here are the checked-in plan's true Fit
// action, fixed initial max height, zero-size initialization deferral, retained
// SVG height metadata, fit-aware 0.5 floor, owning-window drag lifetime, and
// complete disposal.
//
// SKIPPED (fixed product defaults): configurable control visibility,
// resizability, and Always/Never click-drag modes.
// SKIPPED (product boundary): preview Reset Zoom, cross-render retained state,
// SVG height-attribute removal, touch-specific gestures, fullscreen, minimap,
// export/copy, and reset-to-intrinsic controls.

///|
#external
type DiagramViewportTestHarness

///|
extern "js" fn install_diagram_viewport_test_dom() -> DiagramViewportTestHarness =
  #| () => {
  #|   // rabbita reads DOM collections through `item(index)`, so the fake ones
  #|   // are arrays carrying that method rather than bare arrays.
  #|   const collection = (items) => Object.assign(items, {
  #|     item: (index) => items[index] ?? null,
  #|   });
  #|   const harness = {
  #|     restored: false,
  #|     originals: {
  #|     document: globalThis.document,
  #|     window: globalThis.window,
  #|     Element: globalThis.Element,
  #|     MouseEvent: globalThis.MouseEvent,
  #|     WheelEvent: globalThis.WheelEvent,
  #|     KeyboardEvent: globalThis.KeyboardEvent,
  #|     requestAnimationFrame: globalThis.requestAnimationFrame,
  #|     },
  #|     frames: [],
  #|     observers: [],
  #|     wrappers: [],
  #|     svgMeasureTransforms: [],
  #|     throwOnObserve: false,
  #|     childReads: 0,
  #|   };
  #|
  #|   class TestStyle {
  #|     constructor() {
  #|       this.values = new Map();
  #|       this.priorities = new Map();
  #|     }
  #|     getPropertyValue(name) { return this.values.get(name) ?? ''; }
  #|     getPropertyPriority(name) { return this.priorities.get(name) ?? ''; }
  #|     setProperty(name, value, priority = '') {
  #|       this.values.set(name, String(value));
  #|       if (priority) this.priorities.set(name, String(priority));
  #|       else this.priorities.delete(name);
  #|     }
  #|     removeProperty(name) {
  #|       const previous = this.getPropertyValue(name);
  #|       this.values.delete(name);
  #|       this.priorities.delete(name);
  #|       return previous;
  #|     }
  #|   }
  #|
  #|   class TestTarget {
  #|     constructor() { this.__listeners = new Map(); }
  #|     addEventListener(type, listener) {
  #|       let values = this.__listeners.get(type);
  #|       if (!values) {
  #|         values = new Set();
  #|         this.__listeners.set(type, values);
  #|       }
  #|       values.add(listener);
  #|     }
  #|     removeEventListener(type, listener) {
  #|       this.__listeners.get(type)?.delete(listener);
  #|     }
  #|     listenerCount(type) { return this.__listeners.get(type)?.size ?? 0; }
  #|     dispatchEvent(event) {
  #|       if (!event.target) event.target = this;
  #|       for (let current = this; current; current = event.bubbles ? current.parentNode : null) {
  #|         event.currentTarget = current;
  #|         for (const listener of Array.from(current.__listeners?.get(event.type) ?? [])) {
  #|           listener.call(current, event);
  #|           if (event.immediatePropagationStopped) break;
  #|         }
  #|         if (event.propagationStopped) break;
  #|       }
  #|       return !event.defaultPrevented;
  #|     }
  #|   }
  #|
  #|   class TestEvent {
  #|     constructor(type, init = {}) {
  #|       this.type = type;
  #|       this.bubbles = init.bubbles ?? false;
  #|       this.cancelable = init.cancelable ?? false;
  #|       this.button = init.button ?? 0;
  #|       this.buttons = init.buttons ?? 0;
  #|       this.pointerId = init.pointerId ?? 0;
  #|       this.clientX = init.clientX ?? 0;
  #|       this.clientY = init.clientY ?? 0;
  #|       this.altKey = init.altKey ?? false;
  #|       this.shiftKey = init.shiftKey ?? false;
  #|       this.ctrlKey = init.ctrlKey ?? false;
  #|       this.deltaY = init.deltaY ?? 0;
  #|       this.key = init.key ?? '';
  #|       this.defaultPrevented = false;
  #|       this.propagationStopped = false;
  #|       this.immediatePropagationStopped = false;
  #|     }
  #|     preventDefault() {
  #|       if (this.cancelable) this.defaultPrevented = true;
  #|     }
  #|     stopPropagation() { this.propagationStopped = true; }
  #|     stopImmediatePropagation() {
  #|       this.immediatePropagationStopped = true;
  #|       this.propagationStopped = true;
  #|     }
  #|   }
  #|   class TestMouseEvent extends TestEvent {}
  #|   class TestWheelEvent extends TestMouseEvent {}
  #|   class TestKeyboardEvent extends TestEvent {}
  #|
  #|   class TestElement extends TestTarget {
  #|     constructor(ownerDocument, tag) {
  #|       super();
  #|       this.ownerDocument = ownerDocument;
  #|       this.nodeType = 1;
  #|       this.nodeName = String(tag).toUpperCase();
  #|       this.tagName = this.nodeName;
  #|       this.attributes = new Map();
  #|       this.childNodes = [];
  #|       this.parentNode = null;
  #|       this.style = new TestStyle();
  #|       this.__left = 0;
  #|       this.__top = 0;
  #|       this.__width = 0;
  #|       this.__height = 0;
  #|       this.classList = {
  #|         contains: name => this.classTokens().includes(name),
  #|         add: (...names) => {
  #|           const values = this.classTokens();
  #|           for (const name of names) if (!values.includes(name)) values.push(name);
  #|           this.setAttribute('class', values.join(' '));
  #|         },
  #|         remove: (...names) => {
  #|           const removed = new Set(names);
  #|           this.setAttribute('class', this.classTokens().filter(name => !removed.has(name)).join(' '));
  #|         },
  #|         toggle: (name, force) => {
  #|           const enabled = force === undefined ? !this.classTokens().includes(name) : Boolean(force);
  #|           if (enabled) this.classList.add(name);
  #|           else this.classList.remove(name);
  #|           return enabled;
  #|         },
  #|       };
  #|     }
  #|     classTokens() {
  #|       return (this.getAttribute('class') ?? '').split(/\s+/).filter(Boolean);
  #|     }
  #|     setAttribute(name, value) { this.attributes.set(String(name).toLowerCase(), String(value)); }
  #|     getAttribute(name) { return this.attributes.get(String(name).toLowerCase()) ?? null; }
  #|     hasAttribute(name) { return this.attributes.has(String(name).toLowerCase()); }
  #|     removeAttribute(name) { this.attributes.delete(String(name).toLowerCase()); }
  #|     get children() {
  #|       harness.childReads += 1;
  #|       return collection(this.childNodes.filter(child => child.nodeType === 1));
  #|     }
  #|     get firstChild() { return this.childNodes[0] ?? null; }
  #|     get nextSibling() {
  #|       if (!this.parentNode) return null;
  #|       const index = this.parentNode.childNodes.indexOf(this);
  #|       return this.parentNode.childNodes[index + 1] ?? null;
  #|     }
  #|     appendChild(child) {
  #|       child.parentNode?.removeChild(child);
  #|       this.childNodes.push(child);
  #|       child.parentNode = this;
  #|       return child;
  #|     }
  #|     insertBefore(child, reference) {
  #|       child.parentNode?.removeChild(child);
  #|       const index = reference === null ? -1 : this.childNodes.indexOf(reference);
  #|       if (index < 0) this.childNodes.push(child);
  #|       else this.childNodes.splice(index, 0, child);
  #|       child.parentNode = this;
  #|       return child;
  #|     }
  #|     removeChild(child) {
  #|       const index = this.childNodes.indexOf(child);
  #|       if (index >= 0) this.childNodes.splice(index, 1);
  #|       child.parentNode = null;
  #|       return child;
  #|     }
  #|     contains(other) {
  #|       for (let current = other; current; current = current.parentNode) {
  #|         if (current === this) return true;
  #|       }
  #|       return false;
  #|     }
  #|     remove() { this.parentNode?.removeChild(this); }
  #|     matchesDiagramCandidate() {
  #|       return this.classTokens().includes('moonbit-viewer-markdown-diagram') &&
  #|         this.getAttribute('data-diagram-language') === 'diago';
  #|     }
  #|     querySelectorAll(selector) {
  #|       const result = [];
  #|       const visit = node => {
  #|         for (const child of node.children ?? []) {
  #|           if (selector === '.moonbit-viewer-markdown-diagram[data-diagram-language="diago"]' &&
  #|               child.matchesDiagramCandidate()) {
  #|             result.push(child);
  #|           } else if (selector.startsWith('.') &&
  #|                      child.classTokens().includes(selector.slice(1))) {
  #|             result.push(child);
  #|           }
  #|           visit(child);
  #|         }
  #|       };
  #|       visit(this);
  #|       return collection(result);
  #|     }
  #|     getBoundingClientRect() {
  #|       if (this.tagName === 'SVG' &&
  #|           this.parentNode?.classTokens?.().includes('moonbit-viewer-markdown-diagram-content')) {
  #|         harness.svgMeasureTransforms.push(
  #|           this.parentNode.style.getPropertyValue('transform'),
  #|         );
  #|       }
  #|       const inlineHeight = Number.parseFloat(this.style.getPropertyValue('height'));
  #|       const height = Number.isFinite(inlineHeight) ? inlineHeight : this.__height;
  #|       return {
  #|         left: this.__left,
  #|         top: this.__top,
  #|         width: this.__width,
  #|         height,
  #|         right: this.__left + this.__width,
  #|         bottom: this.__top + height,
  #|       };
  #|     }
  #|   }
  #|
  #|   class TestResizeObserver {
  #|     constructor(callback) {
  #|       this.callback = callback;
  #|       this.targets = [];
  #|       this.disconnectCount = 0;
  #|       harness.observers.push(this);
  #|     }
  #|     observe(target) {
  #|       if (harness.throwOnObserve) {
  #|         harness.throwOnObserve = false;
  #|         throw new Error('injected ResizeObserver.observe failure');
  #|       }
  #|       this.targets.push(target);
  #|     }
  #|     disconnect() { this.disconnectCount += 1; }
  #|     trigger() { this.callback(this.targets.map(target => ({ target })), this); }
  #|   }
  #|
  #|   const ownerWindow = new TestTarget();
  #|   ownerWindow.parentNode = null;
  #|   ownerWindow.ResizeObserver = TestResizeObserver;
  #|   ownerWindow.innerHeight = 800;
  #|   const document = new TestTarget();
  #|   document.nodeType = 9;
  #|   document.ownerDocument = document;
  #|   document.defaultView = ownerWindow;
  #|   document.createElement = tag => new TestElement(document, tag);
  #|   document.body = document.createElement('body');
  #|   document.body.style.setProperty('cursor', 'crosshair', 'important');
  #|   ownerWindow.document = document;
  #|   globalThis.document = document;
  #|   globalThis.window = ownerWindow;
  #|   globalThis.Element = TestElement;
  #|   globalThis.MouseEvent = TestMouseEvent;
  #|   globalThis.WheelEvent = TestWheelEvent;
  #|   globalThis.KeyboardEvent = TestKeyboardEvent;
  #|   globalThis.requestAnimationFrame = callback => {
  #|     harness.frames.push(callback);
  #|     return harness.frames.length;
  #|   };
  #|   harness.document = document;
  #|   harness.window = ownerWindow;
  #|   return harness;
  #| }

///|
extern "js" fn DiagramViewportTestHarness::dispose(
  harness : DiagramViewportTestHarness,
) -> Unit =
  #| harness => {
  #|   if (harness.restored) return;
  #|   harness.restored = true;
  #|   const originals = harness.originals;
  #|   globalThis.document = originals.document;
  #|   globalThis.window = originals.window;
  #|   globalThis.Element = originals.Element;
  #|   globalThis.MouseEvent = originals.MouseEvent;
  #|   globalThis.WheelEvent = originals.WheelEvent;
  #|   globalThis.KeyboardEvent = originals.KeyboardEvent;
  #|   globalThis.requestAnimationFrame = originals.requestAnimationFrame;
  #| }

///|
extern "js" fn diagram_viewport_test_target(
  harness : DiagramViewportTestHarness,
  mode : String,
) -> @rdom.Element =
  #| (harness, mode) => {
  #|   const document = harness.document;
  #|   const target = document.createElement('div');
  #|   target.setAttribute('class', 'moonbit-viewer-markdown-comment-content');
  #|   const add = (language, direct, width, height, svgWidth, svgHeight) => {
  #|     const wrapper = document.createElement('div');
  #|     wrapper.setAttribute('class', 'moonbit-viewer-markdown-diagram');
  #|     wrapper.setAttribute('data-diagram-language', language);
  #|     wrapper.style.setProperty('overflow', 'auto');
  #|     wrapper.__width = width;
  #|     wrapper.__height = height;
  #|     const svg = document.createElement('svg');
  #|     svg.setAttribute('height', String(svgHeight));
  #|     svg.__width = svgWidth;
  #|     svg.__height = svgHeight;
  #|     const nested = document.createElement('svg');
  #|     nested.__width = svgWidth;
  #|     nested.__height = svgHeight;
  #|     svg.appendChild(nested);
  #|     if (direct) {
  #|       wrapper.appendChild(svg);
  #|     } else {
  #|       const holder = document.createElement('div');
  #|       holder.appendChild(svg);
  #|       wrapper.appendChild(holder);
  #|     }
  #|     target.appendChild(wrapper);
  #|     harness.wrappers.push(wrapper);
  #|     return wrapper;
  #|   };
  #|   if (mode === 'none') {
  #|     target.appendChild(document.createElement('p'));
  #|   } else if (mode === 'wrong') {
  #|     add('d2', true, 400, 200, 200, 100);
  #|   } else if (mode === 'indirect') {
  #|     add('diago', false, 400, 200, 200, 100);
  #|   } else if (mode === 'two') {
  #|     add('diago', true, 400, 200, 200, 100);
  #|     add('diago', true, 300, 120, 120, 80);
  #|   } else if (mode === 'mixed') {
  #|     add('d2', true, 400, 200, 200, 100);
  #|     add('diago', false, 400, 200, 200, 100);
  #|     add('diago', true, 400, 200, 200, 100);
  #|   } else if (mode === 'mermaid') {
  #|     add('mermaid', true, 400, 200, 200, 100);
  #|   } else if (mode === 'uml') {
  #|     add('uml', true, 400, 200, 200, 100);
  #|   } else if (mode === 'mermaid-pending') {
  #|     add('mermaid', false, 400, 200, 200, 100);
  #|   } else if (mode === 'wide') {
  #|     add('diago', true, 400, 400, 800, 400);
  #|   } else if (mode === 'tall') {
  #|     add('diago', true, 400, 800, 200, 800);
  #|   } else {
  #|     add('diago', true, 400, 100, 200, 100);
  #|   }
  #|   return target;
  #| }

///|
extern "js" fn diagram_viewport_test_commit_mermaid_svg(
  harness : DiagramViewportTestHarness,
  width : Double,
  height : Double,
) -> Unit =
  #| (harness, width, height) => {
  #|   const wrapper = harness.wrappers.find(
  #|     candidate => candidate.getAttribute('data-diagram-language') === 'mermaid',
  #|   );
  #|   if (!wrapper) throw new Error('missing Mermaid wrapper');
  #|   while (wrapper.firstChild) wrapper.removeChild(wrapper.firstChild);
  #|   const svg = harness.document.createElement('svg');
  #|   svg.setAttribute('height', String(height));
  #|   svg.__width = width;
  #|   svg.__height = height;
  #|   wrapper.appendChild(svg);
  #| }

///|
extern "js" fn diagram_viewport_test_flush_frame(
  harness : DiagramViewportTestHarness,
) -> Unit =
  #| harness => {
  #|   const callback = harness.frames.shift();
  #|   if (!callback) throw new Error('missing animation frame');
  #|   callback(0);
  #| }

///|
extern "js" fn diagram_viewport_test_pending_frames(
  harness : DiagramViewportTestHarness,
) -> Int = "harness => harness.frames.length"

///|
extern "js" fn diagram_viewport_test_observer_count(
  harness : DiagramViewportTestHarness,
) -> Int = "harness => harness.observers.length"

///|
extern "js" fn diagram_viewport_test_reset_child_reads(
  harness : DiagramViewportTestHarness,
) -> Unit = "harness => { harness.childReads = 0; }"

///|
extern "js" fn diagram_viewport_test_child_reads(
  harness : DiagramViewportTestHarness,
) -> Int = "harness => harness.childReads"

///|
extern "js" fn diagram_viewport_test_fail_next_observe(
  harness : DiagramViewportTestHarness,
) -> Unit = "harness => { harness.throwOnObserve = true; }"

///|
extern "js" fn diagram_viewport_test_target_wrapper_state(
  target : @rdom.Element,
) -> String =
  #| target => {
  #|   const wrapper = target.querySelectorAll(
  #|     '.moonbit-viewer-markdown-diagram[data-diagram-language="diago"]',
  #|   )[0];
  #|   return [
  #|     wrapper.getAttribute('class') ?? '',
  #|     wrapper.getAttribute('tabindex') ?? '',
  #|     wrapper.getAttribute('aria-label') ?? '',
  #|     wrapper.style.getPropertyValue('height'),
  #|     wrapper.style.getPropertyValue('overflow'),
  #|     wrapper.children.map(child => child.tagName).join(','),
  #|     wrapper.listenerCount('wheel'),
  #|   ].join('|');
  #| }

///|
extern "js" fn diagram_viewport_test_all_svg_measurements_untransformed(
  harness : DiagramViewportTestHarness,
) -> Bool =
  #| harness => {
  #|   const values = harness.svgMeasureTransforms;
  #|   return values.length > 0 && values.every(value => value === 'none');
  #| }

///|
extern "js" fn diagram_viewport_test_trigger_observer(
  harness : DiagramViewportTestHarness,
  index : Int,
) -> Unit =
  #| (harness, index) => {
  #|   const observer = harness.observers[index];
  #|   if (!observer) throw new Error(`missing observer ${index}`);
  #|   observer.trigger();
  #| }

///|
extern "js" fn diagram_viewport_test_disconnect_count(
  harness : DiagramViewportTestHarness,
  index : Int,
) -> Int =
  #| (harness, index) => harness.observers[index]?.disconnectCount ?? 0

///|
extern "js" fn diagram_viewport_test_window_listener_count(
  harness : DiagramViewportTestHarness,
  event_type : String,
) -> Int = "(harness, type) => harness.window.listenerCount(type)"

///|
extern "js" fn diagram_viewport_test_set_window_inner_height(
  harness : DiagramViewportTestHarness,
  height : Double,
) -> Unit = "(harness, height) => { harness.window.innerHeight = height; }"

///|
fn diagram_viewport_test_controller_count(
  lifetime : MarkdownDiagramViewportLifetime,
) -> Int {
  lifetime.controllers.length()
}

///|
fn diagram_viewport_test_scale(
  lifetime : MarkdownDiagramViewportLifetime,
  index : Int,
) -> Double {
  lifetime.controllers[index].scale
}

///|
fn diagram_viewport_test_translate_x(
  lifetime : MarkdownDiagramViewportLifetime,
  index : Int,
) -> Double {
  lifetime.controllers[index].translate_x
}

///|
fn diagram_viewport_test_translate_y(
  lifetime : MarkdownDiagramViewportLifetime,
  index : Int,
) -> Double {
  lifetime.controllers[index].translate_y
}

///|
fn diagram_viewport_test_interacted(
  lifetime : MarkdownDiagramViewportLifetime,
  index : Int,
) -> Bool {
  lifetime.controllers[index].has_interacted
}

///|
fn diagram_viewport_test_dragged(
  lifetime : MarkdownDiagramViewportLifetime,
  index : Int,
) -> Bool {
  lifetime.controllers[index].has_dragged
}

///|
fn diagram_viewport_test_is_panning(
  lifetime : MarkdownDiagramViewportLifetime,
  index : Int,
) -> Bool {
  lifetime.controllers[index].is_panning
}

///|
fn diagram_viewport_test_is_resizing(
  lifetime : MarkdownDiagramViewportLifetime,
  index : Int,
) -> Bool {
  lifetime.controllers[index].is_resizing
}

///|
fn diagram_viewport_test_custom_height(
  lifetime : MarkdownDiagramViewportLifetime,
  index : Int,
) -> Double {
  lifetime.controllers[index].custom_height.unwrap_or(0.0)
}

///|
fn diagram_viewport_test_node(
  lifetime : MarkdownDiagramViewportLifetime,
  index : Int,
  node_name : String,
) -> @rdom.Element {
  let controller = lifetime.controllers[index]
  match node_name {
    "wrapper" => controller.wrapper
    "content" => controller.content
    "svg" => controller.svg
    "controls" => controller.controls
    "panButton" => controller.pan_button
    "zoomOutButton" => controller.zoom_out_button
    "zoomInButton" => controller.zoom_in_button
    "fitButton" => controller.fit_button
    "resizeHandle" => controller.resize_handle
    _ => abort("unknown diagram viewport test node: \{node_name}")
  }
}

///|
fn diagram_viewport_test_attribute(
  lifetime : MarkdownDiagramViewportLifetime,
  index : Int,
  node_name : String,
  attribute : String,
) -> String {
  element_attribute_or_empty(
    diagram_viewport_test_node(lifetime, index, node_name),
    attribute,
  )
}

///|
fn diagram_viewport_test_class_contains(
  lifetime : MarkdownDiagramViewportLifetime,
  index : Int,
  node_name : String,
  class_name : String,
) -> Bool {
  element_has_class(
    diagram_viewport_test_node(lifetime, index, node_name),
    class_name,
  )
}

///|
fn diagram_viewport_test_icon_class(
  lifetime : MarkdownDiagramViewportLifetime,
  index : Int,
  node_name : String,
) -> String {
  let button = diagram_viewport_test_node(lifetime, index, node_name)
  match button.get_first_child().to_element() {
    Some(icon) => element_attribute_or_empty(icon, "class")
    None => ""
  }
}

///|
extern "js" fn diagram_viewport_test_child_classes_raw(
  wrapper : @rdom.Element,
) -> String =
  #| wrapper => wrapper.children
  #|   .map(child => child.getAttribute('class') ?? child.tagName.toLowerCase())
  #|   .join('|')

///|
fn diagram_viewport_test_child_classes(
  lifetime : MarkdownDiagramViewportLifetime,
  index : Int,
) -> String {
  diagram_viewport_test_child_classes_raw(lifetime.controllers[index].wrapper)
}

///|
fn diagram_viewport_test_transform(
  lifetime : MarkdownDiagramViewportLifetime,
  index : Int,
) -> String {
  @base_browser.element_style_value(
    lifetime.controllers[index].content,
    "transform",
  )
}

///|
fn diagram_viewport_test_wrapper_height(
  lifetime : MarkdownDiagramViewportLifetime,
  index : Int,
) -> String {
  @base_browser.element_style_value(
    lifetime.controllers[index].wrapper,
    "height",
  )
}

///|
fn diagram_viewport_test_svg_height_attribute(
  lifetime : MarkdownDiagramViewportLifetime,
  index : Int,
) -> String {
  element_attribute_or_empty(lifetime.controllers[index].svg, "height")
}

///|
extern "js" fn diagram_viewport_test_set_geometry_raw(
  wrapper : @rdom.Element,
  svg : @rdom.Element,
  viewport_width : Double,
  viewport_height : Double,
  svg_width : Double,
  svg_height : Double,
) -> Unit =
  #| (wrapper, svg, viewportWidth, viewportHeight, svgWidth, svgHeight) => {
  #|   wrapper.__width = viewportWidth;
  #|   wrapper.__height = viewportHeight;
  #|   svg.__width = svgWidth;
  #|   svg.__height = svgHeight;
  #| }

///|
fn diagram_viewport_test_set_geometry(
  lifetime : MarkdownDiagramViewportLifetime,
  index : Int,
  viewport_width : Double,
  viewport_height : Double,
  svg_width : Double,
  svg_height : Double,
) -> Unit {
  let controller = lifetime.controllers[index]
  diagram_viewport_test_set_geometry_raw(
    controller.wrapper,
    controller.svg,
    viewport_width,
    viewport_height,
    svg_width,
    svg_height,
  )
}

///|
extern "js" fn diagram_viewport_test_set_invalid_geometry_raw(
  wrapper : @rdom.Element,
  svg : @rdom.Element,
  kind : String,
) -> Unit =
  #| (wrapper, svg, kind) => {
  #|   if (kind === 'zero-viewport') wrapper.__width = 0;
  #|   else if (kind === 'infinite-viewport') wrapper.__width = Infinity;
  #|   else if (kind === 'nan-svg') svg.__width = Number.NaN;
  #| }

///|
fn diagram_viewport_test_set_invalid_geometry(
  lifetime : MarkdownDiagramViewportLifetime,
  index : Int,
  kind : String,
) -> Unit {
  let controller = lifetime.controllers[index]
  diagram_viewport_test_set_invalid_geometry_raw(
    controller.wrapper,
    controller.svg,
    kind,
  )
}

///|
extern "js" fn diagram_viewport_test_dispatch_event(
  target : @rdom.EventTarget,
  event_type : String,
  button : Int,
  buttons : Int,
  pointer_id : Int,
  client_x : Double,
  client_y : Double,
  alt_key : Bool,
  shift_key : Bool,
  ctrl_key : Bool,
  delta_y : Double,
  key : String,
) -> String =
  #| (target, type, button, buttons, pointerId, clientX, clientY, altKey, shiftKey, ctrlKey, deltaY, key) => {
  #|   const init = {
  #|     bubbles: true,
  #|     cancelable: true,
  #|     button,
  #|     buttons,
  #|     pointerId,
  #|     clientX,
  #|     clientY,
  #|     altKey,
  #|     shiftKey,
  #|     ctrlKey,
  #|     deltaY,
  #|     key,
  #|   };
  #|   const event = type === 'wheel'
  #|     ? new WheelEvent(type, init)
  #|     : (type === 'keydown' || type === 'keyup')
  #|       ? new KeyboardEvent(type, init)
  #|       : new MouseEvent(type, init);
  #|   target.dispatchEvent(event);
  #|   return `${event.defaultPrevented}|${event.propagationStopped}`;
  #| }

///|
extern "js" fn diagram_viewport_test_body_cursor(
  harness : DiagramViewportTestHarness,
) -> String =
  #| harness => harness.document.body.style.getPropertyValue('cursor')

///|
extern "js" fn diagram_viewport_test_body_cursor_priority(
  harness : DiagramViewportTestHarness,
) -> String =
  #| harness => harness.document.body.style.getPropertyPriority('cursor')

///|
extern "js" fn diagram_viewport_test_retain_wrapper(
  harness : DiagramViewportTestHarness,
  wrapper : @rdom.Element,
) -> Unit = "(harness, wrapper) => { harness.retainedWrapper = wrapper; }"

///|
fn diagram_viewport_test_set_original_wrapper_style(
  harness : DiagramViewportTestHarness,
  lifetime : MarkdownDiagramViewportLifetime,
  index : Int,
) -> Unit {
  // The saved styles were captured before mount. This helper only exists
  // to make retained-node assertions readable.
  diagram_viewport_test_retain_wrapper(
    harness,
    lifetime.controllers[index].wrapper,
  )
}

///|
extern "js" fn diagram_viewport_test_retained_wrapper_state(
  harness : DiagramViewportTestHarness,
) -> String =
  #| harness => {
  #|   const wrapper = harness.retainedWrapper;
  #|   return [
  #|     wrapper.getAttribute('class') ?? '',
  #|     wrapper.getAttribute('tabindex') ?? '',
  #|     wrapper.getAttribute('aria-label') ?? '',
  #|     wrapper.style.getPropertyValue('height'),
  #|     wrapper.style.getPropertyValue('overflow'),
  #|     wrapper.children.map(child => child.tagName).join(','),
  #|     wrapper.listenerCount('wheel'),
  #|   ].join('|');
  #| }

///|
fn diagram_viewport_event(
  lifetime : MarkdownDiagramViewportLifetime,
  index : Int,
  node_name : String,
  event_type : String,
  button? : Int = 0,
  buttons? : Int = 0,
  pointer_id? : Int = 1,
  client_x? : Double = 0.0,
  client_y? : Double = 0.0,
  alt_key? : Bool = false,
  shift_key? : Bool = false,
  ctrl_key? : Bool = false,
  delta_y? : Double = 0.0,
  key? : String = "",
) -> String {
  let controller = lifetime.controllers[index]
  let target = if node_name == "ownerWindow" {
    controller.owner_window.as_event_target()
  } else {
    diagram_viewport_test_node(lifetime, index, node_name).as_event_target()
  }
  diagram_viewport_test_dispatch_event(
    target, event_type, button, buttons, pointer_id, client_x, client_y, alt_key,
    shift_key, ctrl_key, delta_y, key,
  )
}

///|
fn with_diagram_viewport_test_harness(
  run : (DiagramViewportTestHarness) -> Unit raise,
) -> Unit raise {
  let harness = install_diagram_viewport_test_dom()
  defer harness.dispose()
  run(harness)
}

///|
test "empty wrong-language and indirect SVG targets are exact no-ops" {
  for mode in ["none", "wrong", "indirect"] {
    with_diagram_viewport_test_harness(harness => {
      let target = diagram_viewport_test_target(harness, mode)
      let changes = Ref(0)
      let viewports = DiagramViewports(target, () => changes.val += 1)
      defer viewports.dispose()
      assert_eq(diagram_viewport_test_controller_count(viewports.lifetime), 0)
      assert_eq(diagram_viewport_test_observer_count(harness), 0)
      assert_eq(diagram_viewport_test_pending_frames(harness), 0)
      assert_eq(
        diagram_viewport_test_window_listener_count(harness, "keydown"),
        0,
      )
      assert_eq(changes.val, 0)
      viewports.dispose()
      viewports.dispose()
    })
  }

  with_diagram_viewport_test_harness(harness => {
    let mixed_target = diagram_viewport_test_target(harness, "mixed")
    let mixed = DiagramViewports(mixed_target, () => ())
    defer mixed.dispose()
    assert_eq(diagram_viewport_test_controller_count(mixed.lifetime), 1)
    assert_eq(diagram_viewport_test_observer_count(harness), 1)
    assert_eq(diagram_viewport_test_pending_frames(harness), 1)
    mixed.dispose()
    diagram_viewport_test_flush_frame(harness)
  })
}

///|
test "refresh mounts asynchronous Mermaid SVGs and replaces stale controllers" {
  let harness = install_diagram_viewport_test_dom()
  defer harness.dispose()
  let target = diagram_viewport_test_target(harness, "mermaid-pending")
  let viewports = DiagramViewports(target, () => ())
  defer viewports.dispose()
  assert_eq(diagram_viewport_test_controller_count(viewports.lifetime), 0)
  assert_eq(diagram_viewport_test_observer_count(harness), 0)

  diagram_viewport_test_commit_mermaid_svg(harness, 200.0, 100.0)
  viewports.refresh()
  assert_eq(diagram_viewport_test_controller_count(viewports.lifetime), 1)
  assert_eq(diagram_viewport_test_observer_count(harness), 1)
  assert_eq(
    diagram_viewport_test_attribute(
      viewports.lifetime,
      0,
      "wrapper",
      "aria-label",
    ),
    "Interactive Mermaid diagram",
  )
  diagram_viewport_test_flush_frame(harness)

  // Mermaid theme rerenders replace wrapper children. Refresh must dispose
  // the now-detached controller before enhancing the new direct SVG.
  diagram_viewport_test_commit_mermaid_svg(harness, 300.0, 120.0)
  viewports.refresh()
  assert_eq(diagram_viewport_test_controller_count(viewports.lifetime), 1)
  assert_eq(diagram_viewport_test_observer_count(harness), 2)
  assert_eq(diagram_viewport_test_disconnect_count(harness, 0), 1)
  assert_eq(diagram_viewport_test_pending_frames(harness), 1)
  diagram_viewport_test_flush_frame(harness)
  assert_eq(
    diagram_viewport_test_wrapper_height(viewports.lifetime, 0),
    "120px",
  )
  viewports.dispose()
  assert_eq(diagram_viewport_test_disconnect_count(harness, 1), 1)
}

///|
test "mounts synchronous UML SVGs with UML accessibility labels" {
  let harness = install_diagram_viewport_test_dom()
  defer harness.dispose()
  let target = diagram_viewport_test_target(harness, "uml")
  let viewports = DiagramViewports(target, () => ())
  defer viewports.dispose()
  assert_eq(diagram_viewport_test_controller_count(viewports.lifetime), 1)
  assert_eq(
    diagram_viewport_test_attribute(
      viewports.lifetime,
      0,
      "wrapper",
      "aria-label",
    ),
    "Interactive UML diagram",
  )
  assert_eq(
    diagram_viewport_test_attribute(
      viewports.lifetime,
      0,
      "controls",
      "aria-label",
    ),
    "UML diagram controls",
  )
  diagram_viewport_test_flush_frame(harness)
}

///|
test "refresh preserves current state and disposes wrappers outside its target" {
  let harness = install_diagram_viewport_test_dom()
  defer harness.dispose()
  let target = diagram_viewport_test_target(harness, "uml")
  let viewports = DiagramViewports(target, () => ())
  defer viewports.dispose()
  diagram_viewport_test_flush_frame(harness)
  diagram_viewport_event(viewports.lifetime, 0, "zoomInButton", "click")
  |> ignore
  let transform = diagram_viewport_test_transform(viewports.lifetime, 0)

  // A host may refresh after an unrelated transcript or Editor render. The
  // same direct SVG keeps its controller, transform, and resize observer. Its
  // wrapper is also a scan boundary: only the target's direct children are read.
  diagram_viewport_test_reset_child_reads(harness)
  viewports.refresh()
  assert_eq(diagram_viewport_test_controller_count(viewports.lifetime), 1)
  assert_eq(diagram_viewport_test_observer_count(harness), 1)
  assert_eq(diagram_viewport_test_scale(viewports.lifetime, 0), 1.25)
  assert_eq(diagram_viewport_test_transform(viewports.lifetime, 0), transform)
  assert_eq(diagram_viewport_test_child_reads(harness), 1)

  // Keyed hosts may remove an entire row while retaining the Markdown root.
  // The detached wrapper still owns its content and SVG, so target membership
  // must participate in the controller's currentness check.
  let wrapper = viewports.lifetime.controllers[0].wrapper
  diagram_viewport_test_retain_wrapper(harness, wrapper)
  target.remove_child(wrapper.as_node())
  viewports.refresh()
  assert_eq(diagram_viewport_test_controller_count(viewports.lifetime), 0)
  assert_eq(diagram_viewport_test_disconnect_count(harness, 0), 1)
  assert_eq(diagram_viewport_test_window_listener_count(harness, "keydown"), 0)
  assert_eq(
    diagram_viewport_test_retained_wrapper_state(harness),
    "moonbit-viewer-markdown-diagram||||auto|SVG|0",
  )
}

///|
test "mount is synchronous while positive geometry waits for the shared frame" {
  let harness = install_diagram_viewport_test_dom()
  defer harness.dispose()
  let target = diagram_viewport_test_target(harness, "one")
  let changes = Ref(0)
  let viewports = DiagramViewports(target, () => changes.val += 1)
  defer viewports.dispose()
  assert_eq(diagram_viewport_test_controller_count(viewports.lifetime), 1)
  assert_eq(
    diagram_viewport_test_child_classes(viewports.lifetime, 0),
    "moonbit-viewer-markdown-diagram-content|moonbit-viewer-markdown-diagram-controls|moonbit-viewer-markdown-diagram-resize-handle",
  )
  assert_true(
    diagram_viewport_test_class_contains(
      viewports.lifetime,
      0,
      "wrapper",
      "moonbit-viewer-markdown-diagram-viewport",
    ),
  )
  assert_eq(
    diagram_viewport_test_attribute(
      viewports.lifetime,
      0,
      "wrapper",
      "aria-label",
    ),
    "Interactive Diago diagram",
  )
  assert_eq(
    diagram_viewport_test_attribute(
      viewports.lifetime,
      0,
      "wrapper",
      "tabindex",
    ),
    "0",
  )
  assert_eq(
    diagram_viewport_test_attribute(
      viewports.lifetime,
      0,
      "panButton",
      "aria-pressed",
    ),
    "false",
  )
  assert_eq(
    diagram_viewport_test_attribute(
      viewports.lifetime,
      0,
      "panButton",
      "aria-label",
    ),
    "Toggle pan mode",
  )
  assert_eq(
    diagram_viewport_test_icon_class(viewports.lifetime, 0, "panButton"),
    "codicon codicon-move",
  )
  assert_eq(
    diagram_viewport_test_attribute(
      viewports.lifetime,
      0,
      "zoomOutButton",
      "aria-label",
    ),
    "Zoom out",
  )
  assert_eq(
    diagram_viewport_test_icon_class(viewports.lifetime, 0, "zoomOutButton"),
    "codicon codicon-zoom-out",
  )
  assert_eq(
    diagram_viewport_test_attribute(
      viewports.lifetime,
      0,
      "zoomInButton",
      "aria-label",
    ),
    "Zoom in",
  )
  assert_eq(
    diagram_viewport_test_icon_class(viewports.lifetime, 0, "zoomInButton"),
    "codicon codicon-zoom-in",
  )
  assert_eq(
    diagram_viewport_test_attribute(
      viewports.lifetime,
      0,
      "fitButton",
      "aria-label",
    ),
    "Fit diagram",
  )
  assert_eq(
    diagram_viewport_test_icon_class(viewports.lifetime, 0, "fitButton"),
    "codicon codicon-screen-normal",
  )
  assert_eq(
    diagram_viewport_test_attribute(
      viewports.lifetime,
      0,
      "resizeHandle",
      "role",
    ),
    "separator",
  )
  assert_eq(
    diagram_viewport_test_attribute(
      viewports.lifetime,
      0,
      "resizeHandle",
      "aria-label",
    ),
    "Resize diagram",
  )
  assert_eq(
    diagram_viewport_test_attribute(
      viewports.lifetime,
      0,
      "resizeHandle",
      "aria-orientation",
    ),
    "horizontal",
  )
  assert_eq(
    diagram_viewport_test_attribute(
      viewports.lifetime,
      0,
      "resizeHandle",
      "tabindex",
    ),
    "0",
  )
  assert_eq(diagram_viewport_test_wrapper_height(viewports.lifetime, 0), "")
  assert_eq(diagram_viewport_test_pending_frames(harness), 1)
  assert_eq(
    diagram_viewport_event(viewports.lifetime, 0, "panButton", "pointerdown"),
    "false|true",
  )
  assert_eq(
    diagram_viewport_event(viewports.lifetime, 0, "panButton", "mousedown"),
    "false|true",
  )
  assert_eq(
    diagram_viewport_event(
      viewports.lifetime,
      0,
      "ownerWindow",
      "keydown",
      key="Alt",
      alt_key=true,
    ),
    "true|false",
  )
  assert_eq(changes.val, 0)
  diagram_viewport_test_flush_frame(harness)
  assert_eq(diagram_viewport_test_scale(viewports.lifetime, 0), 1.0)
  assert_eq(diagram_viewport_test_translate_x(viewports.lifetime, 0), 100.0)
  assert_eq(diagram_viewport_test_translate_y(viewports.lifetime, 0), 0.0)
  assert_eq(
    diagram_viewport_test_wrapper_height(viewports.lifetime, 0),
    "100px",
  )
  assert_eq(
    diagram_viewport_test_svg_height_attribute(viewports.lifetime, 0),
    "100",
  )
  assert_true(diagram_viewport_test_all_svg_measurements_untransformed(harness))
  assert_eq(changes.val, 1)
  viewports.dispose()
}

///|
test "initial tall SVG is capped to half the window and fitted with exact padding" {
  let harness = install_diagram_viewport_test_dom()
  defer harness.dispose()
  let target = diagram_viewport_test_target(harness, "tall")
  let changes = Ref(0)
  let viewports = DiagramViewports(target, () => changes.val += 1)
  defer viewports.dispose()
  diagram_viewport_test_flush_frame(harness)

  assert_eq(
    diagram_viewport_test_wrapper_height(viewports.lifetime, 0),
    "400px",
  )
  assert_true(
    (diagram_viewport_test_scale(viewports.lifetime, 0) - 0.46).abs() <
    0.0000001,
  )
  assert_eq(diagram_viewport_test_translate_x(viewports.lifetime, 0), 154.0)
  assert_eq(diagram_viewport_test_translate_y(viewports.lifetime, 0), 16.0)
  assert_false(diagram_viewport_test_interacted(viewports.lifetime, 0))
  assert_eq(changes.val, 1)
  assert_eq(diagram_viewport_test_window_listener_count(harness, "resize"), 1)

  diagram_viewport_test_set_window_inner_height(harness, 600.0)
  assert_eq(
    diagram_viewport_event(viewports.lifetime, 0, "ownerWindow", "resize"),
    "false|false",
  )
  assert_eq(
    diagram_viewport_test_wrapper_height(viewports.lifetime, 0),
    "300px",
  )
  assert_true(
    (diagram_viewport_test_scale(viewports.lifetime, 0) - 0.335).abs() <
    0.0000001,
  )
  assert_true(
    (diagram_viewport_test_translate_x(viewports.lifetime, 0) - 166.5).abs() <
    0.0000001,
  )
  assert_eq(diagram_viewport_test_translate_y(viewports.lifetime, 0), 16.0)
  assert_eq(changes.val, 2)
  viewports.dispose()
  assert_eq(diagram_viewport_test_window_listener_count(harness, "resize"), 0)
}

///|
test "zero geometry remains pending until a later observer sees positive sizes" {
  let harness = install_diagram_viewport_test_dom()
  defer harness.dispose()
  let target = diagram_viewport_test_target(harness, "one")
  let changes = Ref(0)
  let viewports = DiagramViewports(target, () => changes.val += 1)
  defer viewports.dispose()
  diagram_viewport_test_set_geometry(viewports.lifetime, 0, 0.0, 0.0, 0.0, 0.0)
  diagram_viewport_test_flush_frame(harness)
  assert_eq(diagram_viewport_test_wrapper_height(viewports.lifetime, 0), "")
  assert_eq(diagram_viewport_test_transform(viewports.lifetime, 0), "")
  assert_eq(changes.val, 0)
  diagram_viewport_test_set_geometry(
    viewports.lifetime,
    0,
    320.0,
    120.0,
    200.0,
    120.0,
  )
  diagram_viewport_test_trigger_observer(harness, 0)
  assert_eq(
    diagram_viewport_test_wrapper_height(viewports.lifetime, 0),
    "120px",
  )
  assert_eq(diagram_viewport_test_translate_x(viewports.lifetime, 0), 60.0)
  assert_eq(changes.val, 1)
  viewports.dispose()
}

///|
test "true Fit uses 16px padding keeps height and installs fit-aware zoom floor" {
  let harness = install_diagram_viewport_test_dom()
  defer harness.dispose()
  let target = diagram_viewport_test_target(harness, "wide")
  let changes = Ref(0)
  let viewports = DiagramViewports(target, () => changes.val += 1)
  defer viewports.dispose()
  diagram_viewport_test_flush_frame(harness)
  assert_eq(
    diagram_viewport_test_wrapper_height(viewports.lifetime, 0),
    "400px",
  )
  assert_eq(
    diagram_viewport_event(viewports.lifetime, 0, "fitButton", "click"),
    "true|true",
  )
  assert_eq(diagram_viewport_test_scale(viewports.lifetime, 0), 0.46)
  assert_eq(diagram_viewport_test_translate_x(viewports.lifetime, 0), 16.0)
  assert_eq(diagram_viewport_test_translate_y(viewports.lifetime, 0), 108.0)
  assert_true(diagram_viewport_test_interacted(viewports.lifetime, 0))
  assert_eq(
    diagram_viewport_test_wrapper_height(viewports.lifetime, 0),
    "400px",
  )

  // Zoom-out at the fitted scale must not jump up to the normal 0.5 floor.
  diagram_viewport_event(viewports.lifetime, 0, "zoomOutButton", "click")
  |> ignore
  assert_eq(diagram_viewport_test_scale(viewports.lifetime, 0), 0.46)
  assert_eq(diagram_viewport_test_translate_x(viewports.lifetime, 0), 16.0)

  diagram_viewport_event(viewports.lifetime, 0, "zoomInButton", "click")
  |> ignore
  assert_true(
    (diagram_viewport_test_scale(viewports.lifetime, 0) - 0.575).abs() <
    0.0000001,
  )
  assert_eq(diagram_viewport_test_translate_x(viewports.lifetime, 0), -30.0)
  assert_eq(diagram_viewport_test_translate_y(viewports.lifetime, 0), 85.0)
  viewports.dispose()
}

///|
test "Fit handles tall and already-small SVGs and rejects zero or nonfinite geometry" {
  let harness = install_diagram_viewport_test_dom()
  defer harness.dispose()
  let target = diagram_viewport_test_target(harness, "wide")
  let viewports = DiagramViewports(target, () => ())
  defer viewports.dispose()
  diagram_viewport_test_flush_frame(harness)

  diagram_viewport_test_set_geometry(
    viewports.lifetime,
    0,
    400.0,
    400.0,
    100.0,
    800.0,
  )
  diagram_viewport_event(viewports.lifetime, 0, "fitButton", "click") |> ignore
  assert_eq(diagram_viewport_test_scale(viewports.lifetime, 0), 0.46)
  assert_eq(diagram_viewport_test_translate_x(viewports.lifetime, 0), 177.0)
  assert_eq(diagram_viewport_test_translate_y(viewports.lifetime, 0), 16.0)

  diagram_viewport_test_set_geometry(
    viewports.lifetime,
    0,
    400.0,
    400.0,
    100.0,
    50.0,
  )
  diagram_viewport_event(viewports.lifetime, 0, "fitButton", "click") |> ignore
  assert_eq(diagram_viewport_test_scale(viewports.lifetime, 0), 1.0)
  assert_eq(diagram_viewport_test_translate_x(viewports.lifetime, 0), 150.0)
  assert_eq(diagram_viewport_test_translate_y(viewports.lifetime, 0), 175.0)
  let stable_transform = diagram_viewport_test_transform(viewports.lifetime, 0)

  diagram_viewport_test_set_invalid_geometry(viewports.lifetime, 0, "nan-svg")
  diagram_viewport_event(viewports.lifetime, 0, "fitButton", "click") |> ignore
  assert_eq(
    diagram_viewport_test_transform(viewports.lifetime, 0),
    stable_transform,
  )
  diagram_viewport_test_set_geometry(
    viewports.lifetime,
    0,
    400.0,
    400.0,
    100.0,
    50.0,
  )
  diagram_viewport_test_set_invalid_geometry(
    viewports.lifetime,
    0,
    "zero-viewport",
  )
  diagram_viewport_event(viewports.lifetime, 0, "fitButton", "click") |> ignore
  assert_eq(
    diagram_viewport_test_transform(viewports.lifetime, 0),
    stable_transform,
  )
  diagram_viewport_test_set_geometry(
    viewports.lifetime,
    0,
    400.0,
    400.0,
    100.0,
    50.0,
  )
  diagram_viewport_test_set_invalid_geometry(
    viewports.lifetime,
    0,
    "infinite-viewport",
  )
  diagram_viewport_event(viewports.lifetime, 0, "fitButton", "click") |> ignore
  assert_eq(
    diagram_viewport_test_transform(viewports.lifetime, 0),
    stable_transform,
  )
  viewports.dispose()
}

///|
test "ordinary wheel passes through while Alt and Ctrl wheel preserve the event anchor" {
  let harness = install_diagram_viewport_test_dom()
  defer harness.dispose()
  let target = diagram_viewport_test_target(harness, "one")
  let viewports = DiagramViewports(target, () => ())
  defer viewports.dispose()
  diagram_viewport_test_flush_frame(harness)
  assert_eq(
    diagram_viewport_event(
      viewports.lifetime,
      0,
      "wrapper",
      "wheel",
      client_x=100.0,
      client_y=50.0,
      delta_y=-100.0,
    ),
    "false|false",
  )
  assert_eq(diagram_viewport_test_scale(viewports.lifetime, 0), 1.0)
  assert_eq(
    diagram_viewport_event(
      viewports.lifetime,
      0,
      "wrapper",
      "wheel",
      client_x=100.0,
      client_y=50.0,
      alt_key=true,
      delta_y=-100.0,
    ),
    "true|true",
  )
  assert_eq(diagram_viewport_test_scale(viewports.lifetime, 0), 1.2)
  assert_eq(diagram_viewport_test_translate_x(viewports.lifetime, 0), 100.0)
  assert_eq(diagram_viewport_test_translate_y(viewports.lifetime, 0), -10.0)

  // Ctrl pinch uses the exact multiplier 10: delta -10 produces another 20%.
  diagram_viewport_event(
    viewports.lifetime,
    0,
    "wrapper",
    "wheel",
    client_x=100.0,
    client_y=50.0,
    ctrl_key=true,
    delta_y=-10.0,
  )
  |> ignore
  assert_eq(diagram_viewport_test_scale(viewports.lifetime, 0), 1.44)
  assert_eq(diagram_viewport_test_translate_x(viewports.lifetime, 0), 100.0)
  assert_eq(diagram_viewport_test_translate_y(viewports.lifetime, 0), -22.0)

  // A very large positive delta clamps down instead of treating factor <= 0
  // as an invalid early return.
  diagram_viewport_event(
    viewports.lifetime,
    0,
    "wrapper",
    "wheel",
    client_x=100.0,
    client_y=50.0,
    alt_key=true,
    delta_y=10000.0,
  )
  |> ignore
  assert_eq(diagram_viewport_test_scale(viewports.lifetime, 0), 0.5)
  diagram_viewport_event(
    viewports.lifetime,
    0,
    "wrapper",
    "wheel",
    client_x=100.0,
    client_y=50.0,
    alt_key=true,
    delta_y=-10000.0,
  )
  |> ignore
  assert_eq(diagram_viewport_test_scale(viewports.lifetime, 0), 10.0)
  viewports.dispose()
}

///|
test "pan toggle Alt drag and strict per-move threshold keep click semantics" {
  let harness = install_diagram_viewport_test_dom()
  defer harness.dispose()
  let target = diagram_viewport_test_target(harness, "one")
  let viewports = DiagramViewports(target, () => ())
  defer viewports.dispose()
  diagram_viewport_test_flush_frame(harness)

  // Four 1px moves translate content but never exceed the source's strict
  // single-move threshold, so the following Alt click still zooms.
  diagram_viewport_event(
    viewports.lifetime,
    0,
    "wrapper",
    "pointerdown",
    buttons=1,
    client_x=10.0,
    client_y=10.0,
    alt_key=true,
  )
  |> ignore
  for coordinate in [11.0, 12.0, 13.0, 14.0] {
    diagram_viewport_event(
      viewports.lifetime,
      0,
      "ownerWindow",
      "pointermove",
      buttons=1,
      client_x=coordinate,
      client_y=10.0,
      alt_key=true,
    )
    |> ignore
  }
  assert_false(diagram_viewport_test_dragged(viewports.lifetime, 0))
  diagram_viewport_event(
    viewports.lifetime,
    0,
    "ownerWindow",
    "pointerup",
    client_x=14.0,
    client_y=10.0,
    alt_key=true,
  )
  |> ignore
  let before_click = diagram_viewport_test_scale(viewports.lifetime, 0)
  diagram_viewport_event(
    viewports.lifetime,
    0,
    "wrapper",
    "click",
    client_x=14.0,
    client_y=10.0,
    alt_key=true,
  )
  |> ignore
  assert_eq(
    diagram_viewport_test_scale(viewports.lifetime, 0),
    before_click * 1.25,
  )
  let before_shift_click = diagram_viewport_test_scale(viewports.lifetime, 0)
  diagram_viewport_event(
    viewports.lifetime,
    0,
    "wrapper",
    "click",
    client_x=14.0,
    client_y=10.0,
    alt_key=true,
    shift_key=true,
  )
  |> ignore
  assert_true(
    (diagram_viewport_test_scale(viewports.lifetime, 0) -
    before_shift_click * 0.8).abs() <
    0.0000001,
  )

  // One 4px move is a drag and suppresses Alt-click zoom.
  diagram_viewport_event(
    viewports.lifetime,
    0,
    "wrapper",
    "pointerdown",
    buttons=1,
    client_x=20.0,
    client_y=20.0,
    alt_key=true,
  )
  |> ignore
  diagram_viewport_event(
    viewports.lifetime,
    0,
    "ownerWindow",
    "pointermove",
    buttons=1,
    client_x=24.0,
    client_y=20.0,
    alt_key=true,
  )
  |> ignore
  assert_true(diagram_viewport_test_dragged(viewports.lifetime, 0))
  diagram_viewport_event(
    viewports.lifetime,
    0,
    "ownerWindow",
    "pointerup",
    client_x=24.0,
    client_y=20.0,
    alt_key=true,
  )
  |> ignore
  let after_drag = diagram_viewport_test_scale(viewports.lifetime, 0)
  diagram_viewport_event(
    viewports.lifetime,
    0,
    "wrapper",
    "click",
    client_x=24.0,
    client_y=20.0,
    alt_key=true,
  )
  |> ignore
  assert_eq(diagram_viewport_test_scale(viewports.lifetime, 0), after_drag)

  // Toggle enables plain primary-button pan and exposes its pressed state.
  diagram_viewport_event(viewports.lifetime, 0, "panButton", "click") |> ignore
  assert_eq(
    diagram_viewport_test_attribute(
      viewports.lifetime,
      0,
      "panButton",
      "aria-pressed",
    ),
    "true",
  )
  assert_true(
    diagram_viewport_test_class_contains(
      viewports.lifetime,
      0,
      "panButton",
      "active",
    ),
  )
  let plain_start_x = diagram_viewport_test_translate_x(viewports.lifetime, 0)
  diagram_viewport_event(
    viewports.lifetime,
    0,
    "wrapper",
    "pointerdown",
    buttons=1,
    pointer_id=12,
    client_x=30.0,
    client_y=30.0,
  )
  |> ignore
  diagram_viewport_event(
    viewports.lifetime,
    0,
    "ownerWindow",
    "pointermove",
    buttons=1,
    pointer_id=12,
    client_x=40.0,
    client_y=30.0,
  )
  |> ignore
  diagram_viewport_event(
    viewports.lifetime,
    0,
    "ownerWindow",
    "pointerup",
    pointer_id=12,
    client_x=40.0,
    client_y=30.0,
  )
  |> ignore
  assert_eq(
    diagram_viewport_test_translate_x(viewports.lifetime, 0),
    plain_start_x + 10.0,
  )

  // A move delivered by the owning window with buttons=0 terminates the
  // gesture even when release happened outside the viewport.
  diagram_viewport_event(
    viewports.lifetime,
    0,
    "wrapper",
    "pointerdown",
    buttons=1,
    pointer_id=13,
    client_x=40.0,
    client_y=30.0,
  )
  |> ignore
  assert_true(diagram_viewport_test_is_panning(viewports.lifetime, 0))
  diagram_viewport_event(
    viewports.lifetime,
    0,
    "ownerWindow",
    "pointermove",
    buttons=0,
    pointer_id=13,
    client_x=41.0,
    client_y=30.0,
  )
  |> ignore
  assert_false(diagram_viewport_test_is_panning(viewports.lifetime, 0))
  viewports.dispose()
}

///|
test "resize pointer and keyboard branches honor 100px and 10/50px steps" {
  let harness = install_diagram_viewport_test_dom()
  defer harness.dispose()
  let target = diagram_viewport_test_target(harness, "one")
  let changes = Ref(0)
  let viewports = DiagramViewports(target, () => changes.val += 1)
  defer viewports.dispose()
  diagram_viewport_test_flush_frame(harness)
  assert_eq(changes.val, 1)
  assert_eq(
    diagram_viewport_event(
      viewports.lifetime,
      0,
      "resizeHandle",
      "pointerdown",
      buttons=1,
      pointer_id=7,
      client_y=100.0,
    ),
    "true|true",
  )
  assert_eq(diagram_viewport_test_body_cursor(harness), "ns-resize")
  diagram_viewport_event(
    viewports.lifetime,
    0,
    "ownerWindow",
    "pointermove",
    buttons=1,
    pointer_id=7,
    client_y=40.0,
  )
  |> ignore
  assert_eq(diagram_viewport_test_custom_height(viewports.lifetime, 0), 100.0)
  diagram_viewport_event(
    viewports.lifetime,
    0,
    "ownerWindow",
    "pointermove",
    buttons=1,
    pointer_id=7,
    client_y=150.0,
  )
  |> ignore
  assert_eq(diagram_viewport_test_custom_height(viewports.lifetime, 0), 150.0)
  diagram_viewport_event(
    viewports.lifetime,
    0,
    "ownerWindow",
    "pointerup",
    pointer_id=7,
    client_y=150.0,
  )
  |> ignore
  assert_eq(diagram_viewport_test_body_cursor(harness), "crosshair")
  assert_eq(diagram_viewport_test_body_cursor_priority(harness), "important")

  diagram_viewport_event(
    viewports.lifetime,
    0,
    "resizeHandle",
    "keydown",
    key="ArrowUp",
  )
  |> ignore
  assert_eq(diagram_viewport_test_custom_height(viewports.lifetime, 0), 140.0)
  diagram_viewport_event(
    viewports.lifetime,
    0,
    "resizeHandle",
    "keydown",
    shift_key=true,
    key="ArrowDown",
  )
  |> ignore
  assert_eq(diagram_viewport_test_custom_height(viewports.lifetime, 0), 190.0)
  // The first clamped pointer move keeps the existing 100px height and does
  // not report a redundant inline-height write.
  assert_eq(changes.val, 4)

  // buttons=0 and pointercancel both release an outside resize gesture and
  // restore the owner-document cursor lease.
  diagram_viewport_event(
    viewports.lifetime,
    0,
    "resizeHandle",
    "pointerdown",
    buttons=1,
    pointer_id=8,
    client_y=190.0,
  )
  |> ignore
  assert_true(diagram_viewport_test_is_resizing(viewports.lifetime, 0))
  diagram_viewport_event(
    viewports.lifetime,
    0,
    "ownerWindow",
    "pointermove",
    buttons=0,
    pointer_id=8,
    client_y=200.0,
  )
  |> ignore
  assert_false(diagram_viewport_test_is_resizing(viewports.lifetime, 0))
  assert_eq(diagram_viewport_test_body_cursor(harness), "crosshair")

  diagram_viewport_event(
    viewports.lifetime,
    0,
    "resizeHandle",
    "pointerdown",
    buttons=1,
    pointer_id=9,
    client_y=190.0,
  )
  |> ignore
  diagram_viewport_event(
    viewports.lifetime,
    0,
    "ownerWindow",
    "pointercancel",
    pointer_id=9,
    client_y=190.0,
  )
  |> ignore
  assert_false(diagram_viewport_test_is_resizing(viewports.lifetime, 0))
  assert_eq(diagram_viewport_test_body_cursor(harness), "crosshair")

  // Fit is one-shot and does not discard the custom height. A later host/SVG
  // resize preserves both the interacted origin and the 190px user height.
  diagram_viewport_event(viewports.lifetime, 0, "fitButton", "click") |> ignore
  assert_eq(
    diagram_viewport_test_wrapper_height(viewports.lifetime, 0),
    "190px",
  )
  diagram_viewport_test_set_geometry(
    viewports.lifetime,
    0,
    600.0,
    190.0,
    300.0,
    150.0,
  )
  diagram_viewport_test_trigger_observer(harness, 0)
  assert_eq(
    diagram_viewport_test_wrapper_height(viewports.lifetime, 0),
    "190px",
  )
  assert_eq(changes.val, 4)
  viewports.dispose()
}

///|
test "host resize recenters naturally then preserves the interacted SVG origin" {
  let harness = install_diagram_viewport_test_dom()
  defer harness.dispose()
  let target = diagram_viewport_test_target(harness, "one")
  let changes = Ref(0)
  let viewports = DiagramViewports(target, () => changes.val += 1)
  defer viewports.dispose()
  diagram_viewport_test_flush_frame(harness)
  assert_eq(changes.val, 1)
  diagram_viewport_test_set_geometry(
    viewports.lifetime,
    0,
    600.0,
    150.0,
    300.0,
    150.0,
  )
  diagram_viewport_test_trigger_observer(harness, 0)
  assert_eq(diagram_viewport_test_scale(viewports.lifetime, 0), 1.0)
  assert_eq(diagram_viewport_test_translate_x(viewports.lifetime, 0), 150.0)
  assert_eq(
    diagram_viewport_test_wrapper_height(viewports.lifetime, 0),
    "150px",
  )
  assert_eq(changes.val, 2)

  // Alt wheel at the origin changes both scale and translation.
  diagram_viewport_event(
    viewports.lifetime,
    0,
    "wrapper",
    "wheel",
    client_x=0.0,
    client_y=0.0,
    alt_key=true,
    delta_y=-100.0,
  )
  |> ignore
  assert_eq(diagram_viewport_test_scale(viewports.lifetime, 0), 1.2)
  assert_eq(diagram_viewport_test_translate_x(viewports.lifetime, 0), 180.0)

  // Old SVG origin is -150 at scale 1.2, or -50% of width. Doubling the
  // intrinsic SVG width keeps that percentage at the viewport origin.
  diagram_viewport_test_set_geometry(
    viewports.lifetime,
    0,
    800.0,
    300.0,
    600.0,
    300.0,
  )
  diagram_viewport_test_trigger_observer(harness, 0)
  assert_eq(diagram_viewport_test_translate_x(viewports.lifetime, 0), 360.0)
  assert_eq(
    diagram_viewport_test_wrapper_height(viewports.lifetime, 0),
    "300px",
  )
  assert_eq(changes.val, 3)
  let stable_transform = diagram_viewport_test_transform(viewports.lifetime, 0)
  diagram_viewport_test_trigger_observer(harness, 0)
  diagram_viewport_test_trigger_observer(harness, 0)
  assert_eq(
    diagram_viewport_test_transform(viewports.lifetime, 0),
    stable_transform,
  )
  assert_eq(diagram_viewport_test_translate_x(viewports.lifetime, 0), 360.0)
  assert_eq(changes.val, 3)
  assert_true(diagram_viewport_test_all_svg_measurements_untransformed(harness))
  viewports.dispose()
}

///|
test "two diagrams have independent transforms observers and controls" {
  let harness = install_diagram_viewport_test_dom()
  defer harness.dispose()
  let target = diagram_viewport_test_target(harness, "two")
  let viewports = DiagramViewports(target, () => ())
  defer viewports.dispose()
  assert_eq(diagram_viewport_test_controller_count(viewports.lifetime), 2)
  assert_eq(diagram_viewport_test_observer_count(harness), 2)
  assert_eq(diagram_viewport_test_pending_frames(harness), 1)
  diagram_viewport_test_flush_frame(harness)
  assert_eq(diagram_viewport_test_translate_x(viewports.lifetime, 0), 100.0)
  assert_eq(diagram_viewport_test_translate_x(viewports.lifetime, 1), 90.0)
  diagram_viewport_event(viewports.lifetime, 0, "zoomInButton", "click")
  |> ignore
  assert_eq(diagram_viewport_test_scale(viewports.lifetime, 0), 1.25)
  assert_eq(diagram_viewport_test_scale(viewports.lifetime, 1), 1.0)
  viewports.dispose()
  assert_eq(diagram_viewport_test_disconnect_count(harness, 0), 1)
  assert_eq(diagram_viewport_test_disconnect_count(harness, 1), 1)
}

///|
test "owner-document resize cursor lease admits only one live group" {
  let harness = install_diagram_viewport_test_dom()
  defer harness.dispose()
  let first_target = diagram_viewport_test_target(harness, "one")
  let second_target = diagram_viewport_test_target(harness, "one")
  let first = DiagramViewports(first_target, () => ())
  let second = DiagramViewports(second_target, () => ())
  defer first.dispose()
  defer second.dispose()
  diagram_viewport_test_flush_frame(harness)

  diagram_viewport_event(
    first.lifetime,
    0,
    "resizeHandle",
    "pointerdown",
    buttons=1,
    pointer_id=21,
    client_y=100.0,
  )
  |> ignore
  assert_true(diagram_viewport_test_is_resizing(first.lifetime, 0))
  assert_eq(diagram_viewport_test_body_cursor(harness), "ns-resize")
  diagram_viewport_event(
    second.lifetime,
    0,
    "resizeHandle",
    "pointerdown",
    buttons=1,
    pointer_id=22,
    client_y=100.0,
  )
  |> ignore
  assert_false(diagram_viewport_test_is_resizing(second.lifetime, 0))

  first.dispose()
  assert_eq(diagram_viewport_test_body_cursor(harness), "crosshair")
  diagram_viewport_event(
    second.lifetime,
    0,
    "resizeHandle",
    "pointerdown",
    buttons=1,
    pointer_id=22,
    client_y=100.0,
  )
  |> ignore
  assert_true(diagram_viewport_test_is_resizing(second.lifetime, 0))
  assert_eq(diagram_viewport_test_body_cursor(harness), "ns-resize")
  first.dispose()
  assert_eq(diagram_viewport_test_body_cursor(harness), "ns-resize")
  diagram_viewport_event(
    second.lifetime,
    0,
    "ownerWindow",
    "pointercancel",
    pointer_id=22,
    client_y=100.0,
  )
  |> ignore
  assert_eq(diagram_viewport_test_body_cursor(harness), "crosshair")
  second.dispose()
  assert_eq(diagram_body_cursor_coordinators.length(), 0)
}

///|
test "parent lifetime restores its wrapper without DOM expando ownership" {
  let harness = install_diagram_viewport_test_dom()
  defer harness.dispose()
  let target = diagram_viewport_test_target(harness, "one")
  let viewports = DiagramViewports(target, () => ())
  defer viewports.dispose()
  diagram_viewport_test_flush_frame(harness)
  diagram_viewport_test_set_original_wrapper_style(
    harness,
    viewports.lifetime,
    0,
  )
  viewports.dispose()
  assert_eq(diagram_viewport_test_disconnect_count(harness, 0), 1)
  assert_eq(
    diagram_viewport_test_window_listener_count(harness, "pointermove"),
    0,
  )
  assert_eq(
    diagram_viewport_test_retained_wrapper_state(harness),
    "moonbit-viewer-markdown-diagram||||auto|SVG|0",
  )
}

///|
test "observer setup failure rolls back the provisional mount" {
  let harness = install_diagram_viewport_test_dom()
  defer harness.dispose()
  let target = diagram_viewport_test_target(harness, "one")
  let changes = Ref(0)
  diagram_viewport_test_fail_next_observe(harness)
  let viewports = DiagramViewports(target, () => changes.val += 1)
  defer viewports.dispose()
  assert_eq(diagram_viewport_test_controller_count(viewports.lifetime), 0)
  assert_eq(changes.val, 0)
  assert_eq(diagram_viewport_test_observer_count(harness), 1)
  assert_eq(diagram_viewport_test_disconnect_count(harness, 0), 1)
  assert_eq(diagram_viewport_test_pending_frames(harness), 0)
  assert_eq(diagram_viewport_test_window_listener_count(harness, "keydown"), 0)
  assert_eq(
    diagram_viewport_test_window_listener_count(harness, "pointermove"),
    0,
  )
  assert_eq(
    diagram_viewport_test_target_wrapper_state(target),
    "moonbit-viewer-markdown-diagram||||auto|SVG|0",
  )
  viewports.dispose()
}

///|
test "dispose cancels pending layout restores retained DOM and cursor and is idempotent" {
  let harness = install_diagram_viewport_test_dom()
  defer harness.dispose()
  let target = diagram_viewport_test_target(harness, "one")
  let changes = Ref(0)
  let viewports = DiagramViewports(target, () => changes.val += 1)
  defer viewports.dispose()
  diagram_viewport_test_set_original_wrapper_style(
    harness,
    viewports.lifetime,
    0,
  )
  diagram_viewport_event(
    viewports.lifetime,
    0,
    "resizeHandle",
    "pointerdown",
    buttons=1,
    pointer_id=9,
    client_y=100.0,
  )
  |> ignore
  assert_eq(diagram_viewport_test_body_cursor(harness), "ns-resize")
  assert_eq(diagram_viewport_test_window_listener_count(harness, "keydown"), 1)
  assert_eq(
    diagram_viewport_test_window_listener_count(harness, "pointermove"),
    1,
  )
  viewports.dispose()
  viewports.dispose()
  assert_eq(diagram_viewport_test_controller_count(viewports.lifetime), 0)
  assert_eq(diagram_viewport_test_disconnect_count(harness, 0), 1)
  assert_eq(diagram_viewport_test_body_cursor(harness), "crosshair")
  assert_eq(diagram_viewport_test_body_cursor_priority(harness), "important")
  assert_eq(diagram_viewport_test_window_listener_count(harness, "keydown"), 0)
  assert_eq(diagram_viewport_test_window_listener_count(harness, "keyup"), 0)
  assert_eq(
    diagram_viewport_test_window_listener_count(harness, "pointermove"),
    0,
  )
  assert_eq(
    diagram_viewport_test_window_listener_count(harness, "pointerup"),
    0,
  )
  assert_eq(
    diagram_viewport_test_window_listener_count(harness, "pointercancel"),
    0,
  )
  assert_eq(
    diagram_viewport_test_retained_wrapper_state(harness),
    "moonbit-viewer-markdown-diagram||||auto|SVG|0",
  )
  // The native coordinator frame still drains, but the canceled registration
  // cannot write height or invoke the owner callback.
  assert_eq(diagram_viewport_test_pending_frames(harness), 1)
  diagram_viewport_test_flush_frame(harness)
  assert_eq(changes.val, 1)
  diagram_viewport_test_trigger_observer(harness, 0)
  assert_eq(changes.val, 1)
  assert_eq(diagram_body_cursor_coordinators.length(), 0)
}
