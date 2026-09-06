///|
/// Installs a small standards-shaped DOM used by the JS package tests. The
/// parser only implements the safe cmark output surface exercised here; DOM
/// policy remains product code in `install_markdown_dom`.
extern "js" fn install_markdown_test_dom() -> Unit =
  #| () => {
  #|   // rabbita reads DOM collections through `item(index)`, so the fake ones
  #|   // are arrays carrying that method rather than bare arrays.
  #|   const collection = (items) => Object.assign(items, {
  #|     item: (index) => items[index] ?? null,
  #|   });
  #|   const voidTags = new Set(["AREA", "BASE", "BR", "COL", "EMBED", "HR", "IMG", "INPUT", "LINK", "META", "PARAM", "SOURCE", "TRACK", "WBR"]);
  #|   const decode = (value) => value
  #|     .replaceAll("&quot;", "\"")
  #|     .replaceAll("&#39;", "'")
  #|     .replaceAll("&lt;", "<")
  #|     .replaceAll("&gt;", ">")
  #|     .replaceAll("&amp;", "&");
  #|
  #|   class FakeTree extends EventTarget {
  #|     constructor(ownerDocument, nodeType, nodeName) {
  #|       super();
  #|       this.ownerDocument = ownerDocument;
  #|       this.nodeType = nodeType;
  #|       this.nodeName = nodeName;
  #|       this.parentNode = null;
  #|       this.childNodes = [];
  #|       this.__listeners = new Map();
  #|     }
  #|     addEventListener(type, listener, options) {
  #|       let values = this.__listeners.get(type);
  #|       if (!values) {
  #|         values = new Set();
  #|         this.__listeners.set(type, values);
  #|       }
  #|       values.add(listener);
  #|       super.addEventListener(type, listener, options);
  #|     }
  #|     removeEventListener(type, listener, options) {
  #|       this.__listeners.get(type)?.delete(listener);
  #|       super.removeEventListener(type, listener, options);
  #|     }
  #|     listenerCount(type) { return this.__listeners.get(type)?.size ?? 0; }
  #|     appendChild(child) {
  #|       if (child.nodeType === 11) {
  #|         for (const nested of Array.from(child.childNodes)) this.appendChild(nested);
  #|         child.childNodes = [];
  #|         return child;
  #|       }
  #|       child.parentNode?.removeChild(child);
  #|       this.childNodes.push(child);
  #|       child.parentNode = this;
  #|       return child;
  #|     }
  #|     removeChild(child) {
  #|       const index = this.childNodes.indexOf(child);
  #|       if (index >= 0) this.childNodes.splice(index, 1);
  #|       child.parentNode = null;
  #|       return child;
  #|     }
  #|     replaceChildren(...children) {
  #|       for (const child of this.childNodes) child.parentNode = null;
  #|       this.childNodes = [];
  #|       for (const child of children) this.appendChild(child);
  #|     }
  #|     querySelectorAll(selector) {
  #|       const wanted = selector.split(",").map((part) => part.trim().toUpperCase());
  #|       const result = [];
  #|       const visit = (node) => {
  #|         for (const child of node.childNodes) {
  #|           if (child.nodeType === 1 && (wanted.includes("*") || wanted.includes(child.tagName))) result.push(child);
  #|           visit(child);
  #|         }
  #|       };
  #|       visit(this);
  #|       return collection(result);
  #|     }
  #|     get textContent() { return this.childNodes.map((child) => child.textContent).join(""); }
  #|   }
  #|
  #|   class FakeText extends FakeTree {
  #|     constructor(ownerDocument, value) {
  #|       super(ownerDocument, 3, "#text");
  #|       this.value = decode(value);
  #|     }
  #|     get textContent() { return this.value; }
  #|   }
  #|
  #|   const parseInto = (root, html, ownerDocument) => {
  #|     root.replaceChildren();
  #|     const stack = [root];
  #|     const tokens = html.match(/<!--[\s\S]*?-->|<\/?[A-Za-z][^>]*>|[^<]+/g) || [];
  #|     for (const token of tokens) {
  #|       if (token.startsWith("<!--")) continue;
  #|       if (!token.startsWith("<")) {
  #|         stack.at(-1).appendChild(new FakeText(ownerDocument, token));
  #|         continue;
  #|       }
  #|       if (token.startsWith("</")) {
  #|         if (stack.length > 1) stack.pop();
  #|         continue;
  #|       }
  #|       const open = token.match(/^<([A-Za-z][A-Za-z0-9-]*)([\s\S]*?)\/?\s*>$/);
  #|       if (!open) continue;
  #|       const element = ownerDocument.createElement(open[1]);
  #|       const attributes = open[2];
  #|       const attributePattern = /([^\s=/>]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?/g;
  #|       let match;
  #|       while ((match = attributePattern.exec(attributes))) {
  #|         element.setAttribute(match[1], decode(match[2] ?? match[3] ?? match[4] ?? ""));
  #|       }
  #|       stack.at(-1).appendChild(element);
  #|       if (!voidTags.has(element.tagName) && !token.endsWith("/>")) stack.push(element);
  #|     }
  #|   };
  #|
  #|   class FakeFragment extends FakeTree {
  #|     constructor(ownerDocument) { super(ownerDocument, 11, "#document-fragment"); }
  #|   }
  #|
  #|   class FakeElement extends FakeTree {
  #|     constructor(ownerDocument, tag) {
  #|       super(ownerDocument, 1, tag.toUpperCase());
  #|       this.tagName = tag.toUpperCase();
  #|       this.attributes = new Map();
  #|       this.disabled = false;
  #|       if (this.tagName === "TEMPLATE") this.content = new FakeFragment(ownerDocument);
  #|     }
  #|     setAttribute(name, value) { this.attributes.set(name.toLowerCase(), String(value)); }
  #|     getAttribute(name) { return this.attributes.get(name.toLowerCase()) ?? null; }
  #|     removeAttribute(name) { this.attributes.delete(name.toLowerCase()); }
  #|     remove() { this.parentNode?.removeChild(this); }
  #|     set innerHTML(value) { parseInto(this.tagName === "TEMPLATE" ? this.content : this, value, this.ownerDocument); }
  #|     get children() { return collection(this.childNodes.filter((child) => child.nodeType === 1)); }
  #|   }
  #|
  #|   class FakeDocument extends FakeTree {
  #|     constructor() {
  #|       super(null, 9, "#document");
  #|       this.ownerDocument = this;
  #|     }
  #|     createElement(tag) { return new FakeElement(this, tag); }
  #|     getElementById(id) {
  #|       return this.querySelectorAll("*").find(
  #|         (element) => element.getAttribute("id") === id,
  #|       ) || null;
  #|     }
  #|   }
  #|
  #|   globalThis.document = new FakeDocument();
  #|   globalThis.Element = FakeElement;
  #| }

///|
extern "js" fn markdown_test_target() -> @rdom.Element = "() => document.createElement('div')"

///|
extern "js" fn markdown_test_count(target : @rdom.Element, tag : String) -> Int = "(target, tag) => target.querySelectorAll(tag).length"

///|
extern "js" fn markdown_test_find_text(
  target : @rdom.Element,
  tag : String,
  text : String,
) -> @rdom.Element =
  #| (target, tag, text) => target.querySelectorAll(tag).find((element) => element.textContent === text)

///|
extern "js" fn markdown_test_at(
  target : @rdom.Element,
  tag : String,
  index : Int,
) -> @rdom.Element = "(target, tag, index) => target.querySelectorAll(tag)[index]"

///|
extern "js" fn markdown_test_attribute(
  element : @rdom.Element,
  name : String,
) -> String = "(element, name) => element.getAttribute(name) ?? ''"

///|
extern "js" fn markdown_test_text_content(element : @rdom.Element) -> String = "(element) => element.textContent"

///|
extern "js" fn markdown_test_listener_count(
  element : @rdom.Element,
  event_type : String,
) -> Int = "(element, type) => element.listenerCount(type)"

///|
extern "js" fn markdown_test_set_class(
  element : @rdom.Element,
  value : String,
) -> Unit = "(element, value) => element.setAttribute('class', value)"

///|
extern "js" fn markdown_test_same_element(
  left : @rdom.Element,
  right : @rdom.Element,
) -> Bool = "(left, right) => left === right"

///|
extern "js" fn markdown_test_dispatch_mouse(
  element : @rdom.Element,
  event_type : String,
  button : Int,
) -> Bool =
  #| (element, type, button) => {
  #|   const event = new Event(type, { cancelable: true });
  #|   Object.defineProperty(event, "button", { value: button });
  #|   element.dispatchEvent(event);
  #|   return event.defaultPrevented;
  #| }

///|
extern "js" fn markdown_test_dispatch_key(
  element : @rdom.Element,
  key : String,
) -> Bool =
  #| (element, key) => {
  #|   const event = new Event("keydown", { cancelable: true });
  #|   Object.defineProperty(event, "key", { value: key });
  #|   element.dispatchEvent(event);
  #|   return event.defaultPrevented;
  #| }

///|
extern "js" fn markdown_test_dispatch_load(element : @rdom.Element) -> Unit = "(element) => element.dispatchEvent(new Event('load'))"

///|
extern "js" fn markdown_test_dispatch_vertical_wheel(
  element : @rdom.Element,
  delta_y : Int,
  scroll_top : Int,
  client_height : Int,
  scroll_height : Int,
) -> Int =
  #| (element, deltaY, scrollTop, clientHeight, scrollHeight) => {
  #|   for (const [name, value] of Object.entries({
  #|     scrollLeft: 0,
  #|     clientWidth: 100,
  #|     scrollWidth: 100,
  #|     scrollTop,
  #|     clientHeight,
  #|     scrollHeight,
  #|   })) {
  #|     Object.defineProperty(element, name, { configurable: true, value });
  #|   }
  #|   const event = new Event("wheel", { bubbles: true, cancelable: true });
  #|   Object.defineProperties(event, {
  #|     deltaX: { value: 0 },
  #|     deltaY: { value: deltaY },
  #|     shiftKey: { value: false },
  #|   });
  #|   element.dispatchEvent(event);
  #|   return (event.cancelBubble ? 1 : 0) | (event.defaultPrevented ? 2 : 0);
  #| }

///|
fn markdown_test_render_code_block(
  code_block : @markdown_core.MarkdownCodeBlock,
  active_language_id : String?,
) -> String {
  let fallback = @markdown_core.render_tokenized_code_block(
    code_block, active_language_id,
  )
  match code_block.language_id {
    Some("mermaid") =>
      (
        $|<div class="moonbit-viewer-markdown-diagram" data-diagram-language="mermaid" data-mermaid-state="fallback">
        $|\{fallback}
        $|</div>
        $|
      )
    _ => fallback
  }
}

///|
/// Each installation creates a new loader identity so the product's
/// loader-keyed module cache cannot leak between tests.
extern "js" fn markdown_test_mermaid_loader(
  load_mode : String,
  render_mode : String,
) -> MermaidModuleLoader =
  #| (loadMode, renderMode) => {
  #|   const state = {
  #|     loadMode,
  #|     renderMode,
  #|     urls: [],
  #|     initializations: [],
  #|     renders: [],
  #|     binds: [],
  #|     pendingRenders: [],
  #|     currentTheme: "",
  #|   };
  #|   const escaped = (value) => String(value)
  #|     .replaceAll("&", "&amp;")
  #|     .replaceAll("\"", "&quot;")
  #|     .replaceAll("<", "&lt;")
  #|     .replaceAll(">", "&gt;");
  #|   const renderResult = (entry) => ({
  #|     svg:
  #|       `<svg data-test-render-index="${entry.index}" ` +
  #|       `data-test-mermaid-id="${escaped(entry.id)}" ` +
  #|       `data-test-mermaid-theme="${escaped(entry.theme)}">` +
  #|       `<text>rendered ${entry.index}</text></svg>`,
  #|     bindFunctions(wrapper) {
  #|       state.binds.push(wrapper);
  #|       wrapper.setAttribute("data-test-mermaid-bound", String(entry.index));
  #|     },
  #|   });
  #|   const api = {
  #|     initialize(config) {
  #|       state.currentTheme = String(config?.theme ?? "");
  #|       state.initializations.push(config);
  #|     },
  #|     render(id, source) {
  #|       const entry = {
  #|         index: state.renders.length,
  #|         id: String(id),
  #|         source: String(source),
  #|         theme: state.currentTheme,
  #|       };
  #|       state.renders.push(entry);
  #|       if (state.renderMode === "reject") {
  #|         return Promise.reject(new Error("test Mermaid render failure"));
  #|       }
  #|       if (state.renderMode === "defer") {
  #|         return new Promise((resolve, reject) => {
  #|           state.pendingRenders.push({ entry, resolve, reject });
  #|         });
  #|       }
  #|       return Promise.resolve(renderResult(entry));
  #|     },
  #|   };
  #|   const loader = (url) => {
  #|     state.urls.push(String(url));
  #|     if (state.loadMode === "reject") {
  #|       return Promise.reject(new Error("test Mermaid load failure"));
  #|     }
  #|     return Promise.resolve({ default: api });
  #|   };
  #|   state.renderResult = renderResult;
  #|   globalThis.__moonbitMarkdownMermaidTestState = state;
  #|   return loader;
  #| }

///|
extern "js" fn markdown_test_set_mermaid_load_mode(mode : String) -> Unit =
  #| mode => {
  #|   globalThis.__moonbitMarkdownMermaidTestState.loadMode = mode;
  #| }

///|
extern "js" fn markdown_test_set_mermaid_render_mode(mode : String) -> Unit =
  #| mode => {
  #|   globalThis.__moonbitMarkdownMermaidTestState.renderMode = mode;
  #| }

///|
/// MoonBit's focused JS tests are synchronous, while the product deliberately
/// uses real Promise chains. Node exposes this microtask checkpoint to its own
/// runtime; repeated checkpoints make every currently runnable continuation
/// observable without replacing the product queue with a synchronous fake.
extern "js" fn markdown_test_flush_mermaid_microtasks() -> Unit =
  #| () => {
  #|   for (let index = 0; index < 20; index += 1) {
  #|     process._tickCallback();
  #|   }
  #| }

///|
extern "js" fn markdown_test_mermaid_load_count() -> Int = "() => globalThis.__moonbitMarkdownMermaidTestState.urls.length"

///|
extern "js" fn markdown_test_mermaid_url(index : Int) -> String = "(index) => globalThis.__moonbitMarkdownMermaidTestState.urls[index] ?? ''"

///|
extern "js" fn markdown_test_mermaid_initialize_count() -> Int = "() => globalThis.__moonbitMarkdownMermaidTestState.initializations.length"

///|
extern "js" fn markdown_test_mermaid_config_string(
  index : Int,
  field : String,
) -> String =
  #| (index, field) => {
  #|   const value = globalThis.__moonbitMarkdownMermaidTestState.initializations[index]?.[field];
  #|   return value === undefined || value === null ? "" : String(value);
  #| }

///|
extern "js" fn markdown_test_mermaid_config_bool(
  index : Int,
  field : String,
) -> Bool =
  #| (index, field) =>
  #|   globalThis.__moonbitMarkdownMermaidTestState.initializations[index]?.[field] === true

///|
extern "js" fn markdown_test_mermaid_config_has_secure(
  index : Int,
  field : String,
) -> Bool =
  #| (index, field) => {
  #|   const secure = globalThis.__moonbitMarkdownMermaidTestState.initializations[index]?.secure;
  #|   return Array.isArray(secure) && secure.includes(field);
  #| }

///|
extern "js" fn markdown_test_mermaid_render_count() -> Int = "() => globalThis.__moonbitMarkdownMermaidTestState.renders.length"

///|
extern "js" fn markdown_test_mermaid_render_id(index : Int) -> String = "(index) => globalThis.__moonbitMarkdownMermaidTestState.renders[index]?.id ?? ''"

///|
extern "js" fn markdown_test_mermaid_render_source(index : Int) -> String = "(index) => globalThis.__moonbitMarkdownMermaidTestState.renders[index]?.source ?? ''"

///|
extern "js" fn markdown_test_mermaid_render_theme(index : Int) -> String = "(index) => globalThis.__moonbitMarkdownMermaidTestState.renders[index]?.theme ?? ''"

///|
extern "js" fn markdown_test_mermaid_bind_count() -> Int = "() => globalThis.__moonbitMarkdownMermaidTestState.binds.length"

///|
extern "js" fn markdown_test_mermaid_pending_render_count() -> Int = "() => globalThis.__moonbitMarkdownMermaidTestState.pendingRenders.length"

///|
extern "js" fn markdown_test_install_mermaid_id_collisions() -> Unit =
  #| () => {
  #|   for (const id of [
  #|     "moonbit-markdown-mermaid-collision-1",
  #|     "dmoonbit-markdown-mermaid-collision-2",
  #|     "imoonbit-markdown-mermaid-collision-3",
  #|   ]) {
  #|     const element = document.createElement("div");
  #|     element.setAttribute("id", id);
  #|     document.appendChild(element);
  #|   }
  #| }

///|
fn markdown_test_seed_mermaid_id_collisions() -> Unit {
  mermaid_runtime.id_nonce = "collision"
  mermaid_runtime.next_diagram_id = 0
  markdown_test_install_mermaid_id_collisions()
}

///|
extern "js" fn markdown_test_document_has_id(id : String) -> Bool = "(id) => document.getElementById(id) !== null"

///|
extern "js" fn markdown_test_resolve_next_mermaid_render() -> Unit =
  #| () => {
  #|   const state = globalThis.__moonbitMarkdownMermaidTestState;
  #|   const pending = state.pendingRenders.shift();
  #|   if (!pending) throw new Error("no pending Mermaid render");
  #|   pending.resolve(state.renderResult(pending.entry));
  #| }

///|
extern "js" fn markdown_test_count_mermaid_wrappers(
  target : @rdom.Element,
) -> Int =
  #| target => target.querySelectorAll("div").filter((element) => {
  #|   const classes = (element.getAttribute("class") || "").split(/\s+/);
  #|   return classes.includes("moonbit-viewer-markdown-diagram") &&
  #|     element.getAttribute("data-diagram-language") === "mermaid";
  #| }).length

///|
extern "js" fn markdown_test_mermaid_wrapper_at(
  target : @rdom.Element,
  index : Int,
) -> @rdom.Element =
  #| (target, index) => target.querySelectorAll("div").filter((element) => {
  #|   const classes = (element.getAttribute("class") || "").split(/\s+/);
  #|   return classes.includes("moonbit-viewer-markdown-diagram") &&
  #|     element.getAttribute("data-diagram-language") === "mermaid";
  #| })[index]

///|
extern "js" fn markdown_test_count_tokenized_fallbacks(
  target : @rdom.Element,
) -> Int =
  #| target => target.querySelectorAll("div").filter((element) => {
  #|   const classes = (element.getAttribute("class") || "").split(/\s+/);
  #|   return classes.includes("monaco-tokenized-source");
  #| }).length

///|
test "safe DOM and native-link URI policy resolve only allowed schemes" {
  install_markdown_test_dom()
  let target = markdown_test_target()
  let options = MarkdownRenderOptions(
    base_uri=try! @base_common.Uri::parse(
      "https://docs.example.test/base/index.html",
    ),
  )
  ignore(
    render_markdown(
      (
        #|<a href="https://raw.example">raw</a>
        #|
        #|[absolute](https://example.test/a) [relative](guide) [mail](mailto:dev@example.test) [file](file:///tmp/a) [command](command:test) [javascript](javascript:alert(1)) [data](data:text/plain,x)
      ),
      options~,
      target~,
    ),
  )
  // Raw HTML is omitted by the pure safe renderer; only Markdown anchors exist.
  assert_eq(markdown_test_count(target, "a"), 7)
  let absolute = markdown_test_find_text(target, "a", "absolute")
  assert_eq(markdown_test_attribute(absolute, "href"), "https://example.test/a")
  assert_eq(markdown_test_attribute(absolute, "target"), "_blank")
  assert_eq(markdown_test_attribute(absolute, "rel"), "noopener noreferrer")
  let relative = markdown_test_find_text(target, "a", "relative")
  assert_eq(
    markdown_test_attribute(relative, "href"),
    "https://docs.example.test/base/guide",
  )
  let mail = markdown_test_find_text(target, "a", "mail")
  assert_eq(markdown_test_attribute(mail, "href"), "mailto:dev@example.test")
  for text in ["file", "command", "javascript", "data"] {
    let inert = markdown_test_find_text(target, "a", text)
    assert_eq(markdown_test_attribute(inert, "href"), "")
    assert_eq(markdown_test_attribute(inert, "target"), "")
  }
}

///|
test "action links use only the handler for mouse and keyboard activation" {
  install_markdown_test_dom()
  let target = markdown_test_target()
  let activations : Array[String] = []
  let rendered = render_markdown(
    "[run](./run)",
    options=MarkdownRenderOptions(
      base_uri=try! @base_common.Uri::parse("https://example.test/docs/page"),
      action_handler=uri => activations.push(uri),
    ),
    target~,
  )
  let anchor = markdown_test_at(target, "a", 0)
  assert_eq(markdown_test_attribute(anchor, "href"), "")
  assert_eq(markdown_test_attribute(anchor, "role"), "link")
  assert_eq(markdown_test_attribute(anchor, "tabindex"), "0")
  assert_true(markdown_test_dispatch_mouse(anchor, "click", 0))
  assert_true(markdown_test_dispatch_mouse(anchor, "auxclick", 1))
  assert_true(markdown_test_dispatch_key(anchor, "Enter"))
  assert_true(markdown_test_dispatch_key(anchor, " "))
  assert_true(markdown_test_dispatch_key(anchor, "Space"))
  assert_eq(activations.length(), 5)
  for uri in activations {
    assert_eq(uri, "https://example.test/docs/run")
  }
  rendered.dispose.dispose()
  rendered.dispose.dispose()
  assert_eq(markdown_test_listener_count(anchor, "click"), 0)
  assert_false(markdown_test_dispatch_mouse(anchor, "click", 0))
  assert_eq(activations.length(), 5)
}

///|
test "target reuse replaces children and releases every prior listener" {
  install_markdown_test_dom()
  let target = markdown_test_target()
  let activations : Array[String] = []
  let options = MarkdownRenderOptions(action_handler=uri => {
    activations.push(uri)
  })
  let first = render_markdown(
    "[first](https://example.test/first)",
    options~,
    target~,
  )
  let first_anchor = markdown_test_at(target, "a", 0)
  assert_eq(markdown_test_listener_count(first_anchor, "click"), 1)
  assert_eq(markdown_test_listener_count(first_anchor, "auxclick"), 1)
  assert_eq(markdown_test_listener_count(first_anchor, "keydown"), 1)

  let second = render_markdown(
    "[second](https://example.test/second)",
    options~,
    target~,
  )
  assert_true(markdown_test_same_element(first.element, second.element))
  assert_eq(markdown_test_count(target, "a"), 1)
  let second_anchor = markdown_test_at(target, "a", 0)
  assert_eq(markdown_test_listener_count(first_anchor, "click"), 0)
  assert_false(markdown_test_dispatch_mouse(first_anchor, "click", 0))
  first.dispose.dispose()
  // Disposing the superseded result cannot tear down the current lifetime.
  assert_eq(markdown_test_listener_count(second_anchor, "click"), 1)
  assert_true(markdown_test_dispatch_mouse(second_anchor, "click", 0))
  assert_eq(activations, ["https://example.test/second"])

  let third = render_markdown(
    "[third](https://example.test/third)",
    options~,
    target~,
  )
  let third_anchor = markdown_test_at(target, "a", 0)
  assert_eq(markdown_test_listener_count(second_anchor, "click"), 0)
  assert_eq(markdown_test_listener_count(third_anchor, "click"), 1)
  second.dispose.dispose()
  assert_eq(markdown_test_listener_count(third_anchor, "click"), 1)
  third.dispose.dispose()
  third.dispose.dispose()
  assert_eq(markdown_test_listener_count(third_anchor, "click"), 0)
}

///|
test "diagram wheel ownership follows the dynamic viewport marker and listener lifetime" {
  install_markdown_test_dom()
  let target = markdown_test_target()
  let rendered = render_markdown(
    (
      #|```graph
      #|source
      #|```
    ),
    options=MarkdownRenderOptions(code_block_renderer=fn(_block, _language) {
      "<div class=\"moonbit-viewer-markdown-diagram\" data-diagram-language=\"diago\"><svg></svg></div>"
    }),
    target~,
  )
  let diagram = markdown_test_at(target, "div", 0)
  assert_eq(markdown_test_listener_count(diagram, "wheel"), 1)
  // Downward motion inside the available range stays with the diagram and is
  // not preventDefault-ed, so the browser retains its native scrolling.
  assert_eq(markdown_test_dispatch_vertical_wheel(diagram, 120, 0, 100, 300), 1)
  assert_eq(
    markdown_test_dispatch_vertical_wheel(diagram, -120, 100, 100, 300),
    1,
  )
  // At either boundary the event is handed back to the owning surface.
  assert_eq(
    markdown_test_dispatch_vertical_wheel(diagram, -120, 0, 100, 300),
    0,
  )
  assert_eq(
    markdown_test_dispatch_vertical_wheel(diagram, 120, 200, 100, 300),
    0,
  )
  // The Markdown-comment controller mounts after this generic listener.
  // Event-time marker reads hand every ordinary wheel delta back to the
  // interactive component/editor without changing other Markdown consumers.
  markdown_test_set_class(
    diagram, "moonbit-viewer-markdown-diagram moonbit-viewer-markdown-diagram-viewport",
  )
  assert_eq(markdown_test_dispatch_vertical_wheel(diagram, 120, 0, 100, 300), 0)
  markdown_test_set_class(diagram, "moonbit-viewer-markdown-diagram")
  assert_eq(markdown_test_dispatch_vertical_wheel(diagram, 120, 0, 100, 300), 1)
  rendered.dispose.dispose()
  assert_eq(markdown_test_listener_count(diagram, "wheel"), 0)
  assert_eq(markdown_test_dispatch_vertical_wheel(diagram, 120, 0, 100, 300), 0)
}

///|
test "remote images are opt-in and load callbacks become inert after dispose" {
  install_markdown_test_dom()
  let target = markdown_test_target()
  ignore(
    render_markdown(
      "![denied](image.png)",
      options=MarkdownRenderOptions(
        base_uri=try! @base_common.Uri::parse("https://img.example.test/docs/"),
      ),
      target~,
    ),
  )
  assert_eq(markdown_test_count(target, "img"), 0)

  let size_changes = Ref(0)
  let allowed = render_markdown(
    "![allowed](image.png)",
    options=MarkdownRenderOptions(
      base_uri=try! @base_common.Uri::parse("https://img.example.test/docs/"),
      on_size_changed=() => size_changes.val += 1,
      allow_remote_images=true,
    ),
    target~,
  )
  assert_eq(markdown_test_count(target, "img"), 1)
  let image = markdown_test_at(target, "img", 0)
  assert_eq(
    markdown_test_attribute(image, "src"),
    "https://img.example.test/docs/image.png",
  )
  assert_eq(markdown_test_listener_count(image, "load"), 1)
  markdown_test_dispatch_load(image)
  assert_eq(size_changes.val, 1)
  allowed.dispose.dispose()
  assert_eq(markdown_test_listener_count(image, "load"), 0)
  markdown_test_dispatch_load(image)
  assert_eq(size_changes.val, 1)
}

///|
test "postprocess removes non-checkbox inputs and disables task checkboxes" {
  install_markdown_test_dom()
  let target = markdown_test_target()
  ignore(
    render_markdown(
      (
        #|```
        #|ignored
        #|```
      ),
      options=MarkdownRenderOptions(code_block_renderer=fn(_block, _language) {
        "<input type=\"text\"><input type=\"checkbox\">"
      }),
      target~,
    ),
  )
  assert_eq(markdown_test_count(target, "input"), 1)
  let checkbox = markdown_test_at(target, "input", 0)
  assert_eq(markdown_test_attribute(checkbox, "type"), "checkbox")
  // Boolean disabled attributes serialize as the empty string in the fake DOM.
  assert_eq(markdown_test_attribute(checkbox, "disabled"), "")
}

///|
test "Mermaid is exact-lowercase and the option controls all module work" {
  install_markdown_test_dom()
  let mermaid_loader = markdown_test_mermaid_loader("resolve", "resolve")
  let target = markdown_test_target()
  let source = "<script>alert('escaped')</script>&"
  let markdown =
    $|```mermaid
    $|\{source}
    $|```
    $|
    $|```Mermaid
    $|case-sensitive
    $|```
    $|
    $|```mermaid-extra
    $|other
    $|```
  let rendered = render_markdown_with_mermaid_loader(
    markdown,
    mermaid_loader,
    options=MarkdownRenderOptions(
      code_block_renderer=markdown_test_render_code_block,
    ),
    target~,
  )
  assert_eq(markdown_test_count_mermaid_wrappers(target), 1)
  assert_eq(markdown_test_count_tokenized_fallbacks(target), 3)
  assert_eq(markdown_test_count(target, "script"), 0)
  let wrapper = markdown_test_mermaid_wrapper_at(target, 0)
  assert_true(markdown_test_text_content(wrapper).contains(source))
  markdown_test_flush_mermaid_microtasks()
  assert_eq(markdown_test_mermaid_load_count(), 0)
  assert_eq(markdown_test_count(target, "svg"), 0)

  // A renderer created without the option stays opted out even if a caller
  // later asks its generic lifetime to rerender.
  rendered.rerender_mermaid(Dark)
  markdown_test_flush_mermaid_microtasks()
  assert_eq(markdown_test_mermaid_load_count(), 0)
  assert_eq(markdown_test_count(target, "svg"), 0)
  rendered.dispose.dispose()

  let enabled_target = markdown_test_target()
  let enabled = render_markdown_with_mermaid_loader(
    markdown,
    mermaid_loader,
    options=MarkdownRenderOptions(
      code_block_renderer=markdown_test_render_code_block,
      mermaid_theme=Light,
    ),
    target=enabled_target,
  )
  assert_eq(markdown_test_count_mermaid_wrappers(enabled_target), 1)
  assert_eq(markdown_test_count_tokenized_fallbacks(enabled_target), 3)
  assert_eq(markdown_test_count(enabled_target, "script"), 0)
  markdown_test_flush_mermaid_microtasks()
  assert_eq(markdown_test_mermaid_load_count(), 1)
  assert_eq(markdown_test_mermaid_render_count(), 1)
  assert_eq(markdown_test_mermaid_render_source(0), "\{source}\n")
  assert_eq(markdown_test_count(enabled_target, "svg"), 1)
  enabled.dispose.dispose()
}

///|
test "successful Mermaid commits use the local module config unique ids and size callback" {
  install_markdown_test_dom()
  let mermaid_loader = markdown_test_mermaid_loader("resolve", "resolve")
  let target = markdown_test_target()
  let size_changes = Ref(0)
  let rendered = render_markdown_with_mermaid_loader(
    (
      #|```mermaid
      #|graph TD
      #|  A --> B
      #|```
      #|
      #|```mermaid
      #|sequenceDiagram
      #|  A->>B: hello
      #|```
    ),
    mermaid_loader,
    options=MarkdownRenderOptions(
      code_block_renderer=markdown_test_render_code_block,
      on_size_changed=() => size_changes.val += 1,
      mermaid_theme=Light,
    ),
    target~,
  )
  // Safe source remains visible while the asynchronous renderer is pending.
  assert_eq(markdown_test_count_tokenized_fallbacks(target), 2)
  assert_eq(markdown_test_count(target, "svg"), 0)
  assert_eq(size_changes.val, 0)
  markdown_test_flush_mermaid_microtasks()

  assert_eq(markdown_test_mermaid_load_count(), 1)
  assert_eq(markdown_test_mermaid_url(0), "mermaid/mermaid.esm.min.mjs")
  assert_eq(markdown_test_mermaid_initialize_count(), 2)
  assert_eq(markdown_test_mermaid_render_count(), 2)
  assert_eq(markdown_test_mermaid_bind_count(), 2)
  assert_eq(markdown_test_count(target, "svg"), 2)
  assert_eq(size_changes.val, 2)
  assert_eq(markdown_test_mermaid_config_string(0, "startOnLoad"), "false")
  assert_eq(markdown_test_mermaid_config_string(0, "securityLevel"), "strict")
  assert_true(markdown_test_mermaid_config_bool(0, "suppressErrorRendering"))
  assert_eq(markdown_test_mermaid_config_string(0, "theme"), "default")
  assert_true(markdown_test_mermaid_config_has_secure(0, "theme"))
  assert_true(markdown_test_mermaid_config_has_secure(0, "themeVariables"))
  assert_true(markdown_test_mermaid_config_has_secure(0, "themeCSS"))
  assert_true(markdown_test_mermaid_config_has_secure(0, "darkMode"))
  assert_eq(
    markdown_test_mermaid_render_source(0),
    (
      #|graph TD
      #|  A --> B
      #|
    ),
  )
  assert_eq(
    markdown_test_mermaid_render_source(1),
    (
      #|sequenceDiagram
      #|  A->>B: hello
      #|
    ),
  )
  assert_false(
    markdown_test_mermaid_render_id(0) == markdown_test_mermaid_render_id(1),
  )
  assert_true(
    markdown_test_mermaid_render_id(0).contains("moonbit-markdown-mermaid-"),
  )
  rendered.dispose.dispose()
}

///|
test "Mermaid ids avoid host and temporary-element collisions" {
  install_markdown_test_dom()
  let mermaid_loader = markdown_test_mermaid_loader("resolve", "resolve")
  markdown_test_seed_mermaid_id_collisions()
  let target = markdown_test_target()
  let rendered = render_markdown_with_mermaid_loader(
    (
      #|```mermaid
      #|graph TD
      #|  A --> B
      #|```
    ),
    mermaid_loader,
    options=MarkdownRenderOptions(
      code_block_renderer=markdown_test_render_code_block,
      mermaid_theme=Light,
    ),
    target~,
  )
  markdown_test_flush_mermaid_microtasks()
  assert_eq(
    markdown_test_mermaid_render_id(0),
    "moonbit-markdown-mermaid-collision-4",
  )
  assert_true(
    markdown_test_document_has_id("moonbit-markdown-mermaid-collision-1"),
  )
  assert_true(
    markdown_test_document_has_id("dmoonbit-markdown-mermaid-collision-2"),
  )
  assert_true(
    markdown_test_document_has_id("imoonbit-markdown-mermaid-collision-3"),
  )
  rendered.dispose.dispose()
}

///|
test "Mermaid load and syntax failures keep fallback and retry cleanly" {
  install_markdown_test_dom()
  let load_mermaid_loader = markdown_test_mermaid_loader("reject", "resolve")
  let load_target = markdown_test_target()
  let load_size_changes = Ref(0)
  let load_failure = render_markdown_with_mermaid_loader(
    (
      #|```mermaid
      #|graph TD
      #|  offline --> fallback
      #|```
    ),
    load_mermaid_loader,
    options=MarkdownRenderOptions(
      code_block_renderer=markdown_test_render_code_block,
      on_size_changed=() => load_size_changes.val += 1,
      mermaid_theme=Light,
    ),
    target=load_target,
  )
  markdown_test_flush_mermaid_microtasks()
  assert_eq(markdown_test_mermaid_load_count(), 1)
  assert_eq(markdown_test_mermaid_render_count(), 0)
  assert_eq(markdown_test_count(load_target, "svg"), 0)
  assert_eq(markdown_test_count_tokenized_fallbacks(load_target), 1)
  assert_eq(load_size_changes.val, 0)

  // A rejected module promise is evicted, so the same loader identity can
  // succeed when a later theme rerender retries it.
  markdown_test_set_mermaid_load_mode("resolve")
  load_failure.rerender_mermaid(Dark)
  markdown_test_flush_mermaid_microtasks()
  assert_eq(markdown_test_mermaid_load_count(), 2)
  assert_eq(markdown_test_mermaid_render_count(), 1)
  assert_eq(markdown_test_mermaid_render_theme(0), "dark")
  assert_eq(markdown_test_count(load_target, "svg"), 1)
  assert_eq(load_size_changes.val, 1)
  load_failure.dispose.dispose()

  let syntax_mermaid_loader = markdown_test_mermaid_loader("resolve", "reject")
  let syntax_target = markdown_test_target()
  let syntax_size_changes = Ref(0)
  let syntax_failure = render_markdown_with_mermaid_loader(
    (
      #|```mermaid
      #|this is invalid Mermaid
      #|```
    ),
    syntax_mermaid_loader,
    options=MarkdownRenderOptions(
      code_block_renderer=markdown_test_render_code_block,
      on_size_changed=() => syntax_size_changes.val += 1,
      mermaid_theme=Light,
    ),
    target=syntax_target,
  )
  markdown_test_flush_mermaid_microtasks()
  assert_eq(markdown_test_mermaid_load_count(), 1)
  assert_eq(markdown_test_mermaid_render_count(), 1)
  assert_eq(markdown_test_count(syntax_target, "svg"), 0)
  assert_eq(markdown_test_count_tokenized_fallbacks(syntax_target), 1)
  assert_eq(syntax_size_changes.val, 0)

  // A render rejection does not poison either the module cache or render
  // queue; the next request uses the cached module and succeeds.
  markdown_test_set_mermaid_render_mode("resolve")
  syntax_failure.rerender_mermaid(Dark)
  markdown_test_flush_mermaid_microtasks()
  assert_eq(markdown_test_mermaid_load_count(), 1)
  assert_eq(markdown_test_mermaid_initialize_count(), 2)
  assert_eq(markdown_test_mermaid_render_count(), 2)
  assert_eq(markdown_test_mermaid_render_theme(1), "dark")
  assert_eq(markdown_test_count(syntax_target, "svg"), 1)
  assert_eq(syntax_size_changes.val, 1)
  syntax_failure.dispose.dispose()
}

///|
test "target reuse and dispose reject late Mermaid render commits" {
  install_markdown_test_dom()
  let mermaid_loader = markdown_test_mermaid_loader("resolve", "defer")
  let target = markdown_test_target()
  let first_size_changes = Ref(0)
  let first = render_markdown_with_mermaid_loader(
    (
      #|```mermaid
      #|graph TD
      #|  old --> stale
      #|```
    ),
    mermaid_loader,
    options=MarkdownRenderOptions(
      code_block_renderer=markdown_test_render_code_block,
      on_size_changed=() => first_size_changes.val += 1,
      mermaid_theme=Light,
    ),
    target~,
  )
  markdown_test_flush_mermaid_microtasks()
  assert_eq(markdown_test_mermaid_pending_render_count(), 1)
  let first_wrapper = markdown_test_mermaid_wrapper_at(target, 0)

  let second_size_changes = Ref(0)
  let second = render_markdown_with_mermaid_loader(
    (
      #|```mermaid
      #|graph TD
      #|  current --> visible
      #|```
    ),
    mermaid_loader,
    options=MarkdownRenderOptions(
      code_block_renderer=markdown_test_render_code_block,
      on_size_changed=() => second_size_changes.val += 1,
      mermaid_theme=Dark,
    ),
    target~,
  )
  assert_true(markdown_test_same_element(first.element, second.element))
  let second_wrapper = markdown_test_mermaid_wrapper_at(target, 0)
  assert_false(markdown_test_same_element(first_wrapper, second_wrapper))

  // The global queue is still waiting for the old target lifetime.
  markdown_test_flush_mermaid_microtasks()
  assert_eq(markdown_test_mermaid_pending_render_count(), 1)
  markdown_test_resolve_next_mermaid_render()
  markdown_test_flush_mermaid_microtasks()
  assert_eq(first_size_changes.val, 0)
  assert_eq(markdown_test_count(target, "svg"), 0)
  assert_eq(markdown_test_mermaid_pending_render_count(), 1)

  // The current target lifetime may commit normally after the stale work has
  // drained.
  markdown_test_resolve_next_mermaid_render()
  markdown_test_flush_mermaid_microtasks()
  assert_eq(second_size_changes.val, 1)
  assert_eq(markdown_test_count(target, "svg"), 1)
  assert_eq(markdown_test_mermaid_bind_count(), 1)
  assert_eq(markdown_test_mermaid_render_count(), 2)
  assert_false(
    markdown_test_mermaid_render_id(0) == markdown_test_mermaid_render_id(1),
  )

  let third_size_changes = Ref(0)
  let third = render_markdown_with_mermaid_loader(
    (
      #|```mermaid
      #|graph TD
      #|  disposed --> fallback
      #|```
    ),
    mermaid_loader,
    options=MarkdownRenderOptions(
      code_block_renderer=markdown_test_render_code_block,
      on_size_changed=() => third_size_changes.val += 1,
      mermaid_theme=Light,
    ),
    target~,
  )
  markdown_test_flush_mermaid_microtasks()
  assert_eq(markdown_test_mermaid_pending_render_count(), 1)
  third.dispose.dispose()
  third.dispose.dispose()
  markdown_test_resolve_next_mermaid_render()
  markdown_test_flush_mermaid_microtasks()
  assert_eq(third_size_changes.val, 0)
  assert_eq(markdown_test_count(target, "svg"), 0)
  assert_eq(markdown_test_count_tokenized_fallbacks(target), 1)
  assert_eq(markdown_test_mermaid_bind_count(), 1)

  // Superseded handles remain idempotent and cannot dispose another lifetime.
  first.dispose.dispose()
  second.dispose.dispose()
  assert_eq(markdown_test_count_tokenized_fallbacks(target), 1)
}

///|
test "theme rerender keeps the last SVG until the newest epoch succeeds" {
  install_markdown_test_dom()
  let mermaid_loader = markdown_test_mermaid_loader("resolve", "resolve")
  let target = markdown_test_target()
  let size_changes = Ref(0)
  let rendered = render_markdown_with_mermaid_loader(
    (
      #|```mermaid
      #|graph TD
      #|  theme --> redraw
      #|```
    ),
    mermaid_loader,
    options=MarkdownRenderOptions(
      code_block_renderer=markdown_test_render_code_block,
      on_size_changed=() => size_changes.val += 1,
      mermaid_theme=Light,
    ),
    target~,
  )
  markdown_test_flush_mermaid_microtasks()
  assert_eq(markdown_test_count(target, "svg"), 1)
  assert_eq(size_changes.val, 1)
  let initial_svg = markdown_test_at(target, "svg", 0)
  let initial_render = markdown_test_attribute(
    initial_svg, "data-test-render-index",
  )
  assert_eq(
    markdown_test_attribute(initial_svg, "data-test-mermaid-theme"),
    "default",
  )

  // A failed dark redraw retains the last successful light SVG and does not
  // report a size change.
  markdown_test_set_mermaid_render_mode("reject")
  rendered.rerender_mermaid(Dark)
  markdown_test_flush_mermaid_microtasks()
  assert_eq(markdown_test_count(target, "svg"), 1)
  assert_eq(
    markdown_test_attribute(
      markdown_test_at(target, "svg", 0),
      "data-test-render-index",
    ),
    initial_render,
  )
  assert_eq(size_changes.val, 1)

  // Two rapid redraws serialize through Mermaid, but only the newest epoch may
  // replace the SVG after both promises eventually resolve.
  markdown_test_set_mermaid_render_mode("defer")
  rendered.rerender_mermaid(Dark)
  markdown_test_flush_mermaid_microtasks()
  assert_eq(markdown_test_mermaid_pending_render_count(), 1)
  rendered.rerender_mermaid(Light)
  markdown_test_resolve_next_mermaid_render()
  markdown_test_flush_mermaid_microtasks()
  assert_eq(markdown_test_mermaid_pending_render_count(), 1)
  assert_eq(
    markdown_test_attribute(
      markdown_test_at(target, "svg", 0),
      "data-test-render-index",
    ),
    initial_render,
  )
  assert_eq(size_changes.val, 1)

  markdown_test_resolve_next_mermaid_render()
  markdown_test_flush_mermaid_microtasks()
  let final_svg = markdown_test_at(target, "svg", 0)
  assert_false(
    markdown_test_attribute(final_svg, "data-test-render-index") ==
    initial_render,
  )
  assert_eq(
    markdown_test_attribute(final_svg, "data-test-mermaid-theme"),
    "default",
  )
  assert_eq(size_changes.val, 2)
  assert_eq(markdown_test_mermaid_bind_count(), 2)
  assert_eq(markdown_test_mermaid_render_count(), 4)
  assert_eq(markdown_test_mermaid_render_theme(1), "dark")
  assert_eq(markdown_test_mermaid_render_theme(2), "dark")
  assert_eq(markdown_test_mermaid_render_theme(3), "default")
  assert_false(
    markdown_test_mermaid_render_id(2) == markdown_test_mermaid_render_id(3),
  )

  rendered.dispose.dispose()
  rendered.dispose.dispose()
  rendered.rerender_mermaid(Dark)
  markdown_test_flush_mermaid_microtasks()
  assert_eq(markdown_test_mermaid_render_count(), 4)
  assert_eq(markdown_test_count(target, "svg"), 1)
}
