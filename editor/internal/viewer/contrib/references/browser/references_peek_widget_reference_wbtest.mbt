// Conformance tests for the References Peek shell and feature-local ARIA tree.
//
// Behavior port:
// - vscode/src/vs/editor/contrib/gotoSymbol/browser/peek/referencesTree.ts
// - vscode/src/vs/editor/contrib/gotoSymbol/browser/peek/referencesWidget.ts
// - vscode/src/vs/editor/contrib/gotoSymbol/browser/peek/referencesController.ts
// Pinned vscode revision: b18492a288de038fbc7643aae6de8247029d11bd.
//
// The local representation deliberately uses roving treeitem tabindex rather
// than upstream's active-descendant list infrastructure.

///|
#external
type ReferencesPeekBrowserTestHarness

///|
extern "js" fn install_references_peek_test_browser() -> ReferencesPeekBrowserTestHarness =
  #| () => {
  #|   const originals = {
  #|     document: globalThis.document,
  #|     Element: globalThis.Element,
  #|     HTMLElement: globalThis.HTMLElement,
  #|     Event: globalThis.Event,
  #|     KeyboardEvent: globalThis.KeyboardEvent,
  #|     requestAnimationFrame: globalThis.requestAnimationFrame,
  #|   };
  #|
  #|   class TestEvent {
  #|     constructor(type, options = {}) {
  #|       this.type = String(type);
  #|       this.bubbles = options.bubbles ?? true;
  #|       this.cancelable = options.cancelable ?? true;
  #|       this.defaultPrevented = false;
  #|       this.propagationStopped = false;
  #|       this.immediatePropagationStopped = false;
  #|       this.target = null;
  #|       this.currentTarget = null;
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
  #|
  #|   class TestKeyboardEvent extends TestEvent {
  #|     constructor(type, options = {}) {
  #|       super(type, options);
  #|       this.key = options.key ?? "";
  #|       this.code = options.code ?? "";
  #|       this.shiftKey = options.shiftKey ?? false;
  #|       this.altKey = options.altKey ?? false;
  #|       this.ctrlKey = options.ctrlKey ?? false;
  #|       this.metaKey = options.metaKey ?? false;
  #|       this.isComposing = false;
  #|       this.repeat = false;
  #|       this.location = 0;
  #|     }
  #|   }
  #|
  #|   class TestText {
  #|     constructor(text, ownerDocument) {
  #|       this.nodeType = 3;
  #|       this.nodeName = "#text";
  #|       this.textContent = String(text);
  #|       this.ownerDocument = ownerDocument;
  #|       this.parentNode = null;
  #|     }
  #|     get parentElement() {
  #|       return this.parentNode?.nodeType === 1 ? this.parentNode : null;
  #|     }
  #|   }
  #|
  #|   class TestElement {
  #|     constructor(tag, ownerDocument) {
  #|       this.nodeType = 1;
  #|       this.nodeName = String(tag).toUpperCase();
  #|       this.tagName = this.nodeName;
  #|       this.ownerDocument = ownerDocument;
  #|       this.parentNode = null;
  #|       this.childNodes = [];
  #|       this.children = [];
  #|       this.attributes = new Map();
  #|       this.listeners = new Map();
  #|       this.clientWidth = 0;
  #|       this.clientHeight = 0;
  #|       this.scrollWidth = 0;
  #|       this.scrollHeight = 0;
  #|       this.scrollLeft = 0;
  #|       this.scrollTop = 0;
  #|       this.scrollIntoViewCount = 0;
  #|       this.lastScrollIntoView = null;
  #|     }
  #|     get parentElement() {
  #|       return this.parentNode?.nodeType === 1 ? this.parentNode : null;
  #|     }
  #|     setAttribute(name, value) {
  #|       this.attributes.set(String(name), String(value));
  #|     }
  #|     getAttribute(name) {
  #|       return this.attributes.has(String(name))
  #|         ? this.attributes.get(String(name))
  #|         : null;
  #|     }
  #|     hasAttribute(name) { return this.attributes.has(String(name)); }
  #|     removeAttribute(name) { this.attributes.delete(String(name)); }
  #|     appendChild(child) {
  #|       child.parentNode?.removeChild(child);
  #|       this.childNodes.push(child);
  #|       if (child.nodeType === 1) this.children.push(child);
  #|       child.parentNode = this;
  #|       return child;
  #|     }
  #|     removeChild(child) {
  #|       if (child.contains?.(this.ownerDocument.activeElement)) {
  #|         this.ownerDocument.activeElement = null;
  #|       }
  #|       this.childNodes = this.childNodes.filter(value => value !== child);
  #|       this.children = this.children.filter(value => value !== child);
  #|       child.parentNode = null;
  #|       return child;
  #|     }
  #|     contains(node) {
  #|       if (!node) return false;
  #|       if (node === this) return true;
  #|       return this.childNodes.some(child =>
  #|         child === node || Boolean(child.contains?.(node))
  #|       );
  #|     }
  #|     closest(selector) {
  #|       const attr = /^\[([^\]=]+)\]$/.exec(String(selector));
  #|       const cls = /^\.([A-Za-z0-9_-]+)$/.exec(String(selector));
  #|       for (let current = this; current; current = current.parentElement) {
  #|         if (attr && current.hasAttribute(attr[1])) return current;
  #|         if (
  #|           cls &&
  #|           (current.getAttribute("class") ?? "").split(/\s+/).includes(cls[1])
  #|         ) return current;
  #|       }
  #|       return null;
  #|     }
  #|     set innerHTML(_value) {
  #|       if (this.contains(this.ownerDocument.activeElement)) {
  #|         this.ownerDocument.activeElement = null;
  #|       }
  #|       for (const child of this.childNodes) child.parentNode = null;
  #|       this.childNodes = [];
  #|       this.children = [];
  #|     }
  #|     get innerHTML() { return ""; }
  #|     addEventListener(type, listener) {
  #|       const listeners = this.listeners.get(type) ?? [];
  #|       if (!listeners.includes(listener)) listeners.push(listener);
  #|       this.listeners.set(type, listeners);
  #|     }
  #|     removeEventListener(type, listener) {
  #|       const listeners = this.listeners.get(type) ?? [];
  #|       this.listeners.set(
  #|         type,
  #|         listeners.filter(candidate => candidate !== listener),
  #|       );
  #|     }
  #|     dispatchEvent(event) {
  #|       if (!event.target) event.target = this;
  #|       event.currentTarget = this;
  #|       for (const listener of [...(this.listeners.get(event.type) ?? [])]) {
  #|         listener(event);
  #|         if (event.immediatePropagationStopped) break;
  #|       }
  #|       if (
  #|         event.bubbles &&
  #|         !event.propagationStopped &&
  #|         this.parentNode?.dispatchEvent
  #|       ) {
  #|         this.parentNode.dispatchEvent(event);
  #|       }
  #|       return !event.defaultPrevented;
  #|     }
  #|     focus(_options) { this.ownerDocument.activeElement = this; }
  #|     getBoundingClientRect() {
  #|       return {
  #|         x: 0,
  #|         y: 0,
  #|         width: this.clientWidth,
  #|         height: this.clientHeight,
  #|         top: 0,
  #|         right: this.clientWidth,
  #|         bottom: this.clientHeight,
  #|         left: 0,
  #|       };
  #|     }
  #|     scrollIntoView(options) {
  #|       this.scrollIntoViewCount += 1;
  #|       this.lastScrollIntoView = options ?? null;
  #|     }
  #|   }
  #|
  #|   const document = {
  #|     nodeType: 9,
  #|     activeElement: null,
  #|     createElement(tag) { return new TestElement(tag, document); },
  #|     createTextNode(text) { return new TestText(text, document); },
  #|   };
  #|   globalThis.document = document;
  #|   globalThis.Element = TestElement;
  #|   globalThis.HTMLElement = TestElement;
  #|   globalThis.Event = TestEvent;
  #|   globalThis.KeyboardEvent = TestKeyboardEvent;
  #|   const animationFrames = [];
  #|   globalThis.requestAnimationFrame = callback => {
  #|     animationFrames.push(callback);
  #|     return animationFrames.length;
  #|   };
  #|   return { originals, animationFrames, disposed: false };
  #| }

///|
extern "js" fn ReferencesPeekBrowserTestHarness::dispose(
  self : ReferencesPeekBrowserTestHarness,
) -> Unit =
  #| harness => {
  #|   if (harness.disposed) return;
  #|   harness.disposed = true;
  #|   const restore = (name, value) => {
  #|     if (value === undefined) delete globalThis[name];
  #|     else globalThis[name] = value;
  #|   };
  #|   restore("document", harness.originals.document);
  #|   restore("Element", harness.originals.Element);
  #|   restore("HTMLElement", harness.originals.HTMLElement);
  #|   restore("Event", harness.originals.Event);
  #|   restore("KeyboardEvent", harness.originals.KeyboardEvent);
  #|   restore(
  #|     "requestAnimationFrame",
  #|     harness.originals.requestAnimationFrame,
  #|   );
  #| }

///|
extern "js" fn ReferencesPeekBrowserTestHarness::flush_animation_frames(
  self : ReferencesPeekBrowserTestHarness,
) -> Unit =
  #| harness => {
  #|   while (harness.animationFrames.length > 0) {
  #|     const callbacks = harness.animationFrames.splice(0);
  #|     for (const callback of callbacks) callback(0);
  #|   }
  #| }

///|
extern "js" fn references_peek_test_text_content(
  element : @rdom.Element,
) -> String =
  #| element => {
  #|   const read = node => node?.nodeType === 3
  #|     ? node.textContent
  #|     : (node?.childNodes ?? []).map(read).join("");
  #|   return read(element);
  #| }

///|
extern "js" fn references_peek_test_attribute(
  element : @rdom.Element,
  name : String,
) -> String =
  #| (element, name) => element.getAttribute(name) ?? ""

///|
extern "js" fn references_peek_test_has_attribute(
  element : @rdom.Element,
  name : String,
) -> Bool = "(element, name) => element.hasAttribute(name)"

///|
extern "js" fn references_peek_test_row(
  tree : @rdom.Element,
  kind : String,
  index : Int,
) -> @rdom.Element =
  #| (tree, kind, index) => {
  #|   const name = kind === "group"
  #|     ? "data-reference-group-index"
  #|     : "data-reference-flat-index";
  #|   const visit = node => {
  #|     if (
  #|       node?.nodeType === 1 &&
  #|       node.getAttribute("data-reference-row-kind") === kind &&
  #|       node.getAttribute(name) === String(index)
  #|     ) return node;
  #|     for (const child of node?.children ?? []) {
  #|       const found = visit(child);
  #|       if (found) return found;
  #|     }
  #|     return null;
  #|   };
  #|   const result = visit(tree);
  #|   if (!result) throw new Error(`missing ${kind} row ${index}`);
  #|   return result;
  #| }

///|
extern "js" fn references_peek_test_class_descendant(
  root : @rdom.Element,
  class_name : String,
  index : Int,
) -> @rdom.Element =
  #| (root, className, index) => {
  #|   const matches = [];
  #|   const visit = node => {
  #|     if (
  #|       node?.nodeType === 1 &&
  #|       (node.getAttribute("class") ?? "").split(/\s+/).includes(className)
  #|     ) matches.push(node);
  #|     for (const child of node?.children ?? []) visit(child);
  #|   };
  #|   visit(root);
  #|   if (!matches[index]) throw new Error(`missing class ${className} #${index}`);
  #|   return matches[index];
  #| }

///|
extern "js" fn references_peek_test_class_count(
  root : @rdom.Element,
  class_name : String,
) -> Int =
  #| (root, className) => {
  #|   let result = 0;
  #|   const visit = node => {
  #|     if (
  #|       node?.nodeType === 1 &&
  #|       (node.getAttribute("class") ?? "").split(/\s+/).includes(className)
  #|     ) result += 1;
  #|     for (const child of node?.children ?? []) visit(child);
  #|   };
  #|   visit(root);
  #|   return result;
  #| }

///|
extern "js" fn references_peek_test_visible_row_count(
  tree : @rdom.Element,
) -> Int =
  #| tree => {
  #|   const hidden = node => {
  #|     for (let current = node; current; current = current.parentElement) {
  #|       if (current.hasAttribute?.("hidden")) return true;
  #|     }
  #|     return false;
  #|   };
  #|   let result = 0;
  #|   const visit = node => {
  #|     if (
  #|       node?.nodeType === 1 &&
  #|       node.getAttribute("role") === "treeitem" &&
  #|       !hidden(node)
  #|     ) result += 1;
  #|     for (const child of node?.children ?? []) visit(child);
  #|   };
  #|   visit(tree);
  #|   return result;
  #| }

///|
extern "js" fn references_peek_test_visible_tabstop_count(
  tree : @rdom.Element,
) -> Int =
  #| tree => {
  #|   const hidden = node => {
  #|     for (let current = node; current; current = current.parentElement) {
  #|       if (current.hasAttribute?.("hidden")) return true;
  #|     }
  #|     return false;
  #|   };
  #|   let result = 0;
  #|   const visit = node => {
  #|     if (
  #|       node?.nodeType === 1 &&
  #|       node.getAttribute("role") === "treeitem" &&
  #|       node.getAttribute("tabindex") === "0" &&
  #|       !hidden(node)
  #|     ) result += 1;
  #|     for (const child of node?.children ?? []) visit(child);
  #|   };
  #|   visit(tree);
  #|   return result;
  #| }

///|
extern "js" fn references_peek_test_listener_count(
  element : @rdom.Element,
  recursive : Bool,
) -> Int =
  #| (element, recursive) => {
  #|   const count = node => {
  #|     const own = [...node.listeners.values()]
  #|       .reduce((sum, values) => sum + values.length, 0);
  #|     return own + node.children.reduce(
  #|       (sum, child) => sum + count(child),
  #|       0,
  #|     );
  #|   };
  #|   if (recursive) return count(element);
  #|   return [...element.listeners.values()]
  #|     .reduce((sum, values) => sum + values.length, 0);
  #| }

///|
extern "js" fn references_peek_test_dispatch(
  element : @rdom.Element,
  event_type : String,
) -> String =
  #| (element, eventType) => {
  #|   const event = new Event(eventType, { bubbles: true, cancelable: true });
  #|   element.dispatchEvent(event);
  #|   return `${event.defaultPrevented}:${event.propagationStopped}`;
  #| }

///|
extern "js" fn references_peek_test_dispatch_key(
  element : @rdom.Element,
  key : String,
  shift : Bool,
  ctrl : Bool,
  meta : Bool,
) -> String =
  #| (element, key, shift, ctrl, meta) => {
  #|   const event = new KeyboardEvent(
  #|     "keydown",
  #|     {
  #|       key,
  #|       shiftKey: shift,
  #|       ctrlKey: ctrl,
  #|       metaKey: meta,
  #|       bubbles: true,
  #|       cancelable: true,
  #|     },
  #|   );
  #|   element.dispatchEvent(event);
  #|   return `${event.defaultPrevented}:${event.propagationStopped}`;
  #| }

///|
extern "js" fn references_peek_test_is_active(element : @rdom.Element) -> Bool = "element => element.ownerDocument.activeElement === element"

///|
extern "js" fn references_peek_test_same_element(
  left : @rdom.Element,
  right : @rdom.Element,
) -> Bool = "(left, right) => left === right"

///|
extern "js" fn references_peek_test_scroll_count(
  element : @rdom.Element,
) -> Int = "element => element.scrollIntoViewCount"

///|
extern "js" fn references_peek_test_scroll_options(
  element : @rdom.Element,
) -> String =
  #| element => {
  #|   const value = element.lastScrollIntoView ?? {};
  #|   return [
  #|     value.behavior ?? "",
  #|     value.block ?? "",
  #|     value.inline ?? "",
  #|     value.container ?? "",
  #|   ].join(":");
  #| }

///|
priv struct ReferencesPeekTestLog {
  close_count : Ref[Int]
  selected : Array[Int]
  confirmed : Array[Int]
  opened_side : Array[Int]
  next_count : Ref[Int]
  previous_count : Ref[Int]
  expanded : Array[Int]
}

///|
fn ReferencesPeekTestLog::ReferencesPeekTestLog() -> ReferencesPeekTestLog {
  {
    close_count: Ref(0),
    selected: [],
    confirmed: [],
    opened_side: [],
    next_count: Ref(0),
    previous_count: Ref(0),
    expanded: [],
  }
}

///|
fn ReferencesPeekTestLog::callbacks(
  self : ReferencesPeekTestLog,
) -> ReferencesPeekWidgetCallbacks {
  {
    on_close: () => self.close_count.val += 1,
    on_select: item => self.selected.push(item.flat_index),
    on_confirm: item => self.confirmed.push(item.flat_index),
    on_open_side: item => self.opened_side.push(item.flat_index),
    on_next: () => self.next_count.val += 1,
    on_previous: () => self.previous_count.val += 1,
    on_expand_group: group => self.expanded.push(group.group_index),
  }
}

///|
fn references_peek_test_location(
  path : String,
  line : Int,
  column : Int,
) -> @language.Location {
  {
    uri: @base_common.Uri::file(path),
    range: Range(line, column, line, column + 1),
  }
}

///|
fn references_peek_test_model(
  locations : Array[@language.Location],
) -> @references.ReferencesModel {
  ReferencesModel(locations)
}

///|
fn references_peek_test_key(element : @rdom.Element, key : String) -> String {
  references_peek_test_dispatch_key(element, key, false, false, false)
}

///|
test "mode-labelled shell exposes loading empty and stable hosts" {
  let harness = install_references_peek_test_browser()
  defer harness.dispose()
  let definition = ReferencesPeekWidget(
    Definitions,
    ReferencesPeekTestLog().callbacks(),
  )
  assert_eq(
    references_peek_test_attribute(definition.get_dom_node(), "role"),
    "dialog",
  )
  assert_eq(
    references_peek_test_attribute(definition.get_dom_node(), "aria-label"),
    "Peek Definition",
  )
  assert_eq(
    references_peek_test_class_count(
      definition.get_dom_node(),
      "moonbit-viewer-reference-results-scrollable",
    ),
    1,
  )
  assert_eq(
    references_peek_test_class_count(
      definition.get_dom_node(),
      "monaco-scrollable-element",
    ),
    1,
  )
  assert_eq(
    references_peek_test_attribute(
      references_peek_test_class_descendant(
        definition.get_dom_node(),
        "moonbit-viewer-reference-results-tree",
        0,
      ),
      "role",
    ),
    "tree",
  )
  assert_true(
    references_peek_test_text_content(definition.get_dom_node()).contains(
      "Loading definitions",
    ),
  )
  assert_eq(
    references_peek_test_attribute(definition.get_preview_host(), "aria-label"),
    "Definition preview",
  )
  definition.show_empty()
  assert_true(
    references_peek_test_text_content(definition.get_dom_node()).contains(
      "No definitions found",
    ),
  )
  definition.focus()
  assert_true(references_peek_test_is_active(definition.get_dom_node()))
  definition.dispose()

  let references = ReferencesPeekWidget(
    References,
    ReferencesPeekTestLog().callbacks(),
  )
  assert_eq(
    references_peek_test_attribute(references.get_dom_node(), "aria-label"),
    "Peek References",
  )
  assert_eq(
    references_peek_test_class_count(
      references.get_dom_node(),
      "moonbit-viewer-reference-results-scrollable",
    ),
    1,
  )
  assert_true(
    references_peek_test_text_content(references.get_dom_node()).contains(
      "Loading references",
    ),
  )
  references.show_empty()
  assert_true(
    references_peek_test_text_content(references.get_dom_node()).contains(
      "No references found",
    ),
  )
  references.dispose()
}

///|
test "delayed results transfer only exact dialog-root loading focus" {
  let harness = install_references_peek_test_browser()
  defer harness.dispose()
  let widget = ReferencesPeekWidget(
    References,
    ReferencesPeekTestLog().callbacks(),
  )
  let model = references_peek_test_model([
    references_peek_test_location("/workspace/a.mbt", 1, 1),
    references_peek_test_location("/workspace/a.mbt", 2, 2),
  ])

  widget.focus()
  assert_true(references_peek_test_is_active(widget.get_dom_node()))
  widget.set_results(model, Some(model.references[1]))
  let selected = references_peek_test_row(
    references_peek_test_class_descendant(
      widget.get_dom_node(),
      "moonbit-viewer-reference-results-tree",
      0,
    ),
    "reference",
    1,
  )
  assert_true(references_peek_test_is_active(selected))

  let close = references_peek_test_class_descendant(
    widget.get_dom_node(),
    "moonbit-viewer-references-peek-close",
    0,
  )
  @base_browser.focus_prevent_scroll(close)
  widget.show_loading()
  widget.set_results(model, Some(model.references[0]))
  assert_true(references_peek_test_is_active(close))

  let preview_input = @rdom.document().create_element("textarea")
  widget.get_preview_host().append_child(preview_input.as_node())
  @base_browser.focus_prevent_scroll(preview_input)
  widget.show_loading()
  widget.set_results(model, Some(model.references[0]))
  assert_true(references_peek_test_is_active(preview_input))

  let outside = @rdom.document().create_element("button")
  @base_browser.focus_prevent_scroll(outside)
  widget.show_loading()
  widget.set_results(model, Some(model.references[0]))
  assert_true(references_peek_test_is_active(outside))
  widget.dispose()
}

///|
test "preview status transitions retain tree selection and busy state" {
  let harness = install_references_peek_test_browser()
  defer harness.dispose()
  let widget = ReferencesPeekWidget(
    Definitions,
    ReferencesPeekTestLog().callbacks(),
  )
  let model = references_peek_test_model([
    references_peek_test_location("/workspace/a.mbt", 1, 1),
  ])
  widget.set_results(model, Some(model.references[0]))
  let tree = references_peek_test_class_descendant(
    widget.get_dom_node(),
    "moonbit-viewer-reference-results-tree",
    0,
  )
  let row = references_peek_test_row(tree, "reference", 0)
  let status = references_peek_test_class_descendant(
    widget.get_dom_node(),
    "moonbit-viewer-references-peek-status",
    0,
  )

  widget.show_preview_loading()
  assert_eq(
    references_peek_test_attribute(widget.get_preview_host(), "aria-busy"),
    "true",
  )
  assert_false(references_peek_test_has_attribute(tree, "hidden"))
  assert_false(references_peek_test_has_attribute(status, "hidden"))
  assert_true(
    references_peek_test_text_content(status).contains("Loading preview"),
  )
  assert_true(
    references_peek_test_same_element(
      row,
      references_peek_test_row(tree, "reference", 0),
    ),
  )
  assert_eq(references_peek_test_attribute(row, "aria-selected"), "true")

  widget.show_preview_unavailable("No preview available")
  assert_false(
    references_peek_test_has_attribute(widget.get_preview_host(), "aria-busy"),
  )
  assert_eq(references_peek_test_text_content(status), "No preview available")
  assert_false(references_peek_test_has_attribute(tree, "hidden"))
  assert_eq(references_peek_test_attribute(row, "aria-selected"), "true")

  widget.show_preview_ready()
  assert_true(references_peek_test_has_attribute(status, "hidden"))
  assert_eq(references_peek_test_text_content(status), "")
  assert_false(
    references_peek_test_has_attribute(widget.get_preview_host(), "aria-busy"),
  )
  assert_true(
    references_peek_test_same_element(
      row,
      references_peek_test_row(tree, "reference", 0),
    ),
  )
  assert_eq(references_peek_test_attribute(row, "aria-selected"), "true")
  widget.dispose()
}

///|
test "one resource flattens rows and renders exact snippet parts" {
  let harness = install_references_peek_test_browser()
  defer harness.dispose()
  let log = ReferencesPeekTestLog()
  let widget = ReferencesPeekWidget(References, log.callbacks())
  let model = references_peek_test_model([
    references_peek_test_location("/workspace/a.mbt", 2, 3),
    references_peek_test_location("/workspace/a.mbt", 4, 5),
  ])
  widget.set_results(model, Some(model.references[1]))
  let tree = references_peek_test_class_descendant(
    widget.get_dom_node(),
    "moonbit-viewer-reference-results-tree",
    0,
  )
  assert_eq(references_peek_test_visible_row_count(tree), 2)
  assert_eq(references_peek_test_visible_tabstop_count(tree), 1)
  assert_eq(log.expanded, [0])
  let first = references_peek_test_row(tree, "reference", 0)
  let second = references_peek_test_row(tree, "reference", 1)
  assert_eq(references_peek_test_attribute(first, "aria-level"), "1")
  assert_eq(references_peek_test_attribute(first, "aria-posinset"), "1")
  assert_eq(references_peek_test_attribute(first, "aria-setsize"), "2")
  assert_eq(references_peek_test_attribute(first, "aria-selected"), "false")
  assert_eq(references_peek_test_attribute(first, "tabindex"), "-1")
  assert_eq(references_peek_test_attribute(second, "aria-selected"), "true")
  assert_eq(references_peek_test_attribute(second, "tabindex"), "0")
  assert_eq(
    references_peek_test_class_count(
      tree, "moonbit-viewer-reference-results-file",
    ),
    0,
  )

  widget.set_group_previews(0, [
    Snippet({ before: "let ", matched: "value", after: " = 1", }),
    LocationFallback("a.mbt:4:5"),
  ])
  let rendered_first = references_peek_test_row(tree, "reference", 0)
  assert_false(references_peek_test_same_element(first, rendered_first))
  assert_eq(references_peek_test_text_content(rendered_first), "let value = 1")
  assert_eq(
    references_peek_test_class_count(
      rendered_first, "moonbit-viewer-reference-results-snippet",
    ),
    1,
  )
  assert_eq(
    references_peek_test_class_count(
      rendered_first, "moonbit-viewer-reference-results-snippet-match",
    ),
    1,
  )
  assert_eq(
    references_peek_test_text_content(
      references_peek_test_class_descendant(
        rendered_first, "moonbit-viewer-reference-results-snippet-match", 0,
      ),
    ),
    "value",
  )
  let rendered_second = references_peek_test_row(tree, "reference", 1)
  assert_eq(references_peek_test_text_content(rendered_second), "a.mbt:4:5")
  assert_eq(references_peek_test_attribute(rendered_second, "role"), "treeitem")
  assert_eq(
    references_peek_test_attribute(tree, "aria-label"),
    "Found 2 results in file:///workspace/a.mbt",
  )
  widget.dispose()
}

///|
test "multiple resources expose grouped ARIA rows and lazy expansion" {
  let harness = install_references_peek_test_browser()
  defer harness.dispose()
  let log = ReferencesPeekTestLog()
  let widget = ReferencesPeekWidget(Definitions, log.callbacks())
  let model = references_peek_test_model([
    references_peek_test_location("/workspace/a.mbt", 1, 1),
    references_peek_test_location("/workspace/a.mbt", 2, 2),
    references_peek_test_location("/workspace/src/b.mbt", 3, 3),
  ])
  widget.set_results(model, Some(model.references[2]))
  let tree = references_peek_test_class_descendant(
    widget.get_dom_node(),
    "moonbit-viewer-reference-results-tree",
    0,
  )
  let first_group = references_peek_test_row(tree, "group", 0)
  let second_group = references_peek_test_row(tree, "group", 1)
  assert_eq(references_peek_test_visible_row_count(tree), 3)
  assert_eq(references_peek_test_visible_tabstop_count(tree), 1)
  assert_eq(references_peek_test_attribute(first_group, "aria-level"), "1")
  assert_eq(references_peek_test_attribute(first_group, "aria-posinset"), "1")
  assert_eq(references_peek_test_attribute(first_group, "aria-setsize"), "2")
  assert_eq(
    references_peek_test_attribute(first_group, "aria-expanded"),
    "false",
  )
  assert_eq(
    references_peek_test_attribute(second_group, "aria-expanded"),
    "true",
  )
  assert_eq(
    references_peek_test_text_content(first_group),
    "\u{25b6}a.mbt/workspace2",
  )
  assert_eq(
    references_peek_test_text_content(second_group),
    "\u{25b6}b.mbt/workspace/src1",
  )
  assert_eq(
    references_peek_test_class_count(
      first_group, "moonbit-viewer-reference-results-twistie",
    ),
    1,
  )
  assert_eq(log.expanded, [1])
  let selected = references_peek_test_row(tree, "reference", 2)
  assert_eq(references_peek_test_attribute(selected, "aria-level"), "2")
  assert_eq(references_peek_test_attribute(selected, "aria-posinset"), "1")
  assert_eq(references_peek_test_attribute(selected, "aria-setsize"), "1")
  assert_eq(references_peek_test_attribute(selected, "aria-selected"), "true")

  assert_eq(references_peek_test_dispatch(first_group, "click"), "true:true")
  assert_eq(
    references_peek_test_attribute(first_group, "aria-expanded"),
    "true",
  )
  assert_eq(references_peek_test_visible_row_count(tree), 5)
  assert_eq(log.expanded, [1, 0])
  assert_eq(references_peek_test_dispatch(first_group, "click"), "true:true")
  assert_eq(
    references_peek_test_attribute(first_group, "aria-expanded"),
    "false",
  )
  assert_eq(references_peek_test_visible_row_count(tree), 3)
  assert_eq(references_peek_test_dispatch(first_group, "click"), "true:true")
  // Re-expansion does not trigger a second root resolution request.
  assert_eq(log.expanded, [1, 0])
  assert_eq(references_peek_test_visible_tabstop_count(tree), 1)
  widget.dispose()
}

///|
test "tree keyboard navigation clamps expands and couples reference selection" {
  let harness = install_references_peek_test_browser()
  defer harness.dispose()
  let log = ReferencesPeekTestLog()
  let widget = ReferencesPeekWidget(References, log.callbacks())
  let model = references_peek_test_model([
    references_peek_test_location("/workspace/a.mbt", 1, 1),
    references_peek_test_location("/workspace/a.mbt", 2, 2),
    references_peek_test_location("/workspace/b.mbt", 3, 3),
  ])
  widget.set_results(model, Some(model.references[2]))
  let tree = references_peek_test_class_descendant(
    widget.get_dom_node(),
    "moonbit-viewer-reference-results-tree",
    0,
  )
  let first_group = references_peek_test_row(tree, "group", 0)
  let second_group = references_peek_test_row(tree, "group", 1)
  let selected = references_peek_test_row(tree, "reference", 2)
  widget.focus()
  assert_true(references_peek_test_is_active(selected))

  assert_eq(references_peek_test_key(selected, "Home"), "true:true")
  assert_true(references_peek_test_is_active(first_group))
  assert_eq(references_peek_test_visible_tabstop_count(tree), 1)
  // The first visible-row boundary clamps.
  assert_eq(references_peek_test_key(first_group, "ArrowUp"), "true:true")
  assert_true(references_peek_test_is_active(first_group))
  assert_eq(references_peek_test_key(first_group, "ArrowRight"), "true:true")
  assert_eq(
    references_peek_test_attribute(first_group, "aria-expanded"),
    "true",
  )
  assert_true(references_peek_test_is_active(first_group))
  assert_eq(references_peek_test_key(first_group, "ArrowRight"), "true:true")
  let first_reference = references_peek_test_row(tree, "reference", 0)
  assert_true(references_peek_test_is_active(first_reference))
  assert_eq(log.selected.last(), Some(0))
  assert_eq(references_peek_test_key(first_reference, "ArrowDown"), "true:true")
  let second_reference = references_peek_test_row(tree, "reference", 1)
  assert_true(references_peek_test_is_active(second_reference))
  assert_eq(log.selected.last(), Some(1))
  assert_eq(
    references_peek_test_key(second_reference, "ArrowDown"),
    "true:true",
  )
  assert_true(references_peek_test_is_active(second_group))
  assert_eq(references_peek_test_key(second_group, "End"), "true:true")
  assert_true(references_peek_test_is_active(selected))
  assert_eq(log.selected.last(), Some(2))
  let selection_count = log.selected.length()
  // The last visible-row boundary clamps.
  assert_eq(references_peek_test_key(selected, "ArrowDown"), "true:true")
  assert_true(references_peek_test_is_active(selected))
  assert_eq(log.selected.length(), selection_count)
  assert_eq(references_peek_test_key(selected, "ArrowLeft"), "true:true")
  assert_true(references_peek_test_is_active(second_group))
  assert_eq(references_peek_test_key(second_group, "ArrowLeft"), "true:true")
  assert_eq(
    references_peek_test_attribute(second_group, "aria-expanded"),
    "false",
  )
  assert_eq(references_peek_test_visible_tabstop_count(tree), 1)
  widget.dispose()
}

///|
test "pointer activation session commands and side open respect focus domains" {
  let harness = install_references_peek_test_browser()
  defer harness.dispose()
  let log = ReferencesPeekTestLog()
  let widget = ReferencesPeekWidget(References, log.callbacks())
  let model = references_peek_test_model([
    references_peek_test_location("/workspace/a.mbt", 1, 1),
    references_peek_test_location("/workspace/a.mbt", 2, 2),
  ])
  widget.set_results(model, Some(model.references[0]))
  let tree = references_peek_test_class_descendant(
    widget.get_dom_node(),
    "moonbit-viewer-reference-results-tree",
    0,
  )
  let first = references_peek_test_row(tree, "reference", 0)
  let second = references_peek_test_row(tree, "reference", 1)
  let nested = references_peek_test_class_descendant(
    second, "moonbit-viewer-reference-results-fallback", 0,
  )
  assert_eq(references_peek_test_dispatch(nested, "click"), "true:true")
  assert_eq(log.selected, [1])
  assert_true(references_peek_test_is_active(second))
  assert_eq(references_peek_test_dispatch(nested, "dblclick"), "true:true")
  assert_eq(log.confirmed, [1])

  assert_eq(references_peek_test_key(second, "Enter"), "true:true")
  assert_eq(log.confirmed, [1, 1])
  assert_eq(
    references_peek_test_dispatch_key(second, "Enter", false, true, false),
    "true:true",
  )
  assert_eq(log.opened_side, [1])
  assert_eq(
    references_peek_test_dispatch_key(second, "Enter", false, false, true),
    "true:true",
  )
  assert_eq(log.opened_side, [1, 1])

  let preview_input = @rdom.document().create_element("textarea")
  widget.get_preview_host().append_child(preview_input.as_node())
  @base_browser.focus_prevent_scroll(preview_input)
  assert_eq(references_peek_test_key(preview_input, "Enter"), "false:true")
  assert_eq(log.confirmed, [1, 1])
  assert_eq(references_peek_test_key(preview_input, "F4"), "true:true")
  assert_eq(log.next_count.val, 1)
  assert_eq(
    references_peek_test_dispatch_key(preview_input, "F4", true, false, false),
    "true:true",
  )
  assert_eq(log.previous_count.val, 1)
  assert_eq(references_peek_test_key(first, "Escape"), "true:true")
  assert_eq(log.close_count.val, 1)
  widget.dispose()
}

///|
test "host selection preserves preview focus reveals and rerenders one group" {
  let harness = install_references_peek_test_browser()
  defer harness.dispose()
  let log = ReferencesPeekTestLog()
  let widget = ReferencesPeekWidget(References, log.callbacks())
  let model = references_peek_test_model([
    references_peek_test_location("/workspace/a.mbt", 1, 1),
    references_peek_test_location("/workspace/b.mbt", 2, 2),
  ])
  widget.set_results(model, Some(model.references[0]))
  let tree = references_peek_test_class_descendant(
    widget.get_dom_node(),
    "moonbit-viewer-reference-results-tree",
    0,
  )
  let first_group = references_peek_test_row(tree, "group", 0)
  let second_group = references_peek_test_row(tree, "group", 1)
  let first = references_peek_test_row(tree, "reference", 0)
  let hidden_second = references_peek_test_row(tree, "reference", 1)

  widget.focus()
  assert_true(references_peek_test_is_active(first))
  widget.set_selected(model.references[1])
  let second = references_peek_test_row(tree, "reference", 1)
  assert_true(references_peek_test_is_active(second))
  assert_eq(
    references_peek_test_attribute(second_group, "aria-expanded"),
    "true",
  )
  assert_eq(references_peek_test_scroll_count(second), 1)
  assert_eq(
    references_peek_test_scroll_options(second),
    "auto:nearest:nearest:nearest",
  )
  assert_true(references_peek_test_same_element(hidden_second, second))

  widget.set_group_previews(1, [
    Snippet({ before: "let ", matched: "b", after: " = 2", }),
  ])
  let focused_second = references_peek_test_row(tree, "reference", 1)
  assert_false(references_peek_test_same_element(second, focused_second))
  assert_true(references_peek_test_is_active(focused_second))

  let preview_input = @rdom.document().create_element("textarea")
  widget.get_preview_host().append_child(preview_input.as_node())
  @base_browser.focus_prevent_scroll(preview_input)
  widget.set_selected(model.references[0])
  assert_true(references_peek_test_is_active(preview_input))
  assert_eq(references_peek_test_scroll_count(first), 1)

  let untouched_second = focused_second
  widget.set_group_previews(0, [
    Snippet({ before: "let ", matched: "a", after: " = 1", }),
  ])
  let rerendered_first = references_peek_test_row(tree, "reference", 0)
  assert_true(
    references_peek_test_same_element(
      first_group,
      references_peek_test_row(tree, "group", 0),
    ),
  )
  assert_true(
    references_peek_test_same_element(
      second_group,
      references_peek_test_row(tree, "group", 1),
    ),
  )
  assert_false(references_peek_test_same_element(first, rerendered_first))
  assert_true(
    references_peek_test_same_element(
      untouched_second,
      references_peek_test_row(tree, "reference", 1),
    ),
  )
  assert_false(references_peek_test_same_element(hidden_second, focused_second))
  assert_true(references_peek_test_is_active(preview_input))
  widget.dispose()
}

///|
test "replacement and disposal leave no stale row or listener callbacks" {
  let harness = install_references_peek_test_browser()
  defer harness.dispose()
  let log = ReferencesPeekTestLog()
  let widget = ReferencesPeekWidget(References, log.callbacks())
  let first_model = references_peek_test_model([
    references_peek_test_location("/workspace/a.mbt", 1, 1),
  ])
  widget.set_results(first_model, Some(first_model.references[0]))
  let tree = references_peek_test_class_descendant(
    widget.get_dom_node(),
    "moonbit-viewer-reference-results-tree",
    0,
  )
  let stale = references_peek_test_row(tree, "reference", 0)
  assert_eq(references_peek_test_listener_count(stale, false), 0)
  let second_model = references_peek_test_model([
    references_peek_test_location("/workspace/b.mbt", 2, 2),
  ])
  widget.set_results(second_model, Some(second_model.references[0]))
  assert_eq(references_peek_test_dispatch(stale, "click"), "false:false")
  assert_eq(log.selected, [])

  widget.dispose()
  widget.dispose()
  assert_eq(references_peek_test_listener_count(widget.get_dom_node(), true), 0)
  let current_tree = references_peek_test_class_descendant(
    widget.get_dom_node(),
    "moonbit-viewer-reference-results-tree",
    0,
  )
  let current = references_peek_test_row(current_tree, "reference", 0)
  assert_eq(references_peek_test_dispatch(current, "click"), "false:false")
  assert_eq(log.selected, [])
}
