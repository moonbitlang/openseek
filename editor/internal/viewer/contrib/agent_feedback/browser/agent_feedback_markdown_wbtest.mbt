///|
/// Installs the minimum DOM needed by the feedback widget and the shared
/// browser Markdown renderer. Template contents retain the safe HTML string;
/// renderer policy details have their own focused package tests.
extern "js" fn install_agent_feedback_markdown_test_browser() -> Unit =
  #| () => {
  #|   globalThis.__agentFeedbackMarkdownOriginals = {
  #|     document: globalThis.document,
  #|     Element: globalThis.Element,
  #|     HTMLElement: globalThis.HTMLElement,
  #|     KeyboardEvent: globalThis.KeyboardEvent,
  #|   };
  #|
  #|   class TestFragment {
  #|     constructor(ownerDocument) {
  #|       this.ownerDocument = ownerDocument;
  #|       this._innerHTML = "";
  #|       this.childNodes = [];
  #|     }
  #|     querySelectorAll(_selector) { return []; }
  #|   }
  #|
  #|   class TestElement extends EventTarget {
  #|     constructor(tag, ownerDocument) {
  #|       super();
  #|       this.nodeType = 1;
  #|       this.nodeName = tag.toUpperCase();
  #|       this.tagName = this.nodeName;
  #|       this.ownerDocument = ownerDocument;
  #|       this.attributes = new Map();
  #|       this.childNodes = [];
  #|       this.children = this.childNodes;
  #|       this.parentNode = null;
  #|       this._innerHTML = "";
  #|       this.value = "";
  #|       this.scrollHeight = 22;
  #|       this.scrollWidth = 120;
  #|       this.offsetHeight = 22;
  #|       this.offsetWidth = 280;
  #|       this.style = {
  #|         setProperty(name, value) { this[name] = value; },
  #|       };
  #|     }
  #|     setAttribute(name, value) { this.attributes.set(name, String(value)); }
  #|     getAttribute(name) { return this.attributes.get(name) ?? ""; }
  #|     removeAttribute(name) { this.attributes.delete(name); }
  #|     appendChild(child) {
  #|       if (child.parentNode) child.parentNode.removeChild(child);
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
  #|     replaceChildren(...children) {
  #|       for (const child of this.childNodes) child.parentNode = null;
  #|       this.childNodes = [];
  #|       this.children = this.childNodes;
  #|       this._innerHTML = "";
  #|       for (const child of children) {
  #|         if (child instanceof TestFragment) {
  #|           this._innerHTML += child._innerHTML;
  #|         } else {
  #|           this.appendChild(child);
  #|         }
  #|       }
  #|     }
  #|     set innerHTML(value) {
  #|       for (const child of this.childNodes) child.parentNode = null;
  #|       this.childNodes = [];
  #|       this.children = this.childNodes;
  #|       this._innerHTML = String(value);
  #|     }
  #|     get innerHTML() { return this._innerHTML; }
  #|     remove() {
  #|       if (this.parentNode) this.parentNode.removeChild(this);
  #|     }
  #|     contains(candidate) {
  #|       if (candidate === this) return true;
  #|       return this.childNodes.some(child => child.contains?.(candidate));
  #|     }
  #|     closest(selector) {
  #|       const className = selector.startsWith(".") ? selector.slice(1) : "";
  #|       let current = this;
  #|       while (current) {
  #|         const classes = (current.getAttribute?.("class") ?? "").split(/\s+/);
  #|         if (className && classes.includes(className)) return current;
  #|         current = current.parentNode;
  #|       }
  #|       return null;
  #|     }
  #|     focus(_options) { this.ownerDocument.activeElement = this; }
  #|     setSelectionRange() {}
  #|     getBoundingClientRect() {
  #|       return {
  #|         x: 0, y: 0, left: 0, top: 0,
  #|         right: this.offsetWidth, bottom: this.offsetHeight,
  #|         width: this.offsetWidth, height: this.offsetHeight,
  #|       };
  #|     }
  #|   }
  #|
  #|   class TestTemplate extends TestElement {
  #|     constructor(ownerDocument) {
  #|       super("template", ownerDocument);
  #|       this.content = new TestFragment(ownerDocument);
  #|     }
  #|     set innerHTML(value) { this.content._innerHTML = String(value); }
  #|     get innerHTML() { return this.content._innerHTML; }
  #|   }
  #|
  #|   class TestKeyboardEvent extends Event {
  #|     constructor(type, options = {}) {
  #|       super(type, { bubbles: true, cancelable: true });
  #|       this.key = options.key ?? "";
  #|       this.shiftKey = options.shiftKey ?? false;
  #|       this.altKey = options.altKey ?? false;
  #|       this.ctrlKey = options.ctrlKey ?? false;
  #|       this.metaKey = options.metaKey ?? false;
  #|     }
  #|   }
  #|
  #|   const document = {
  #|     nodeType: 9,
  #|     activeElement: null,
  #|     defaultView: { getSelection: () => null },
  #|     createElement(tag) {
  #|       return tag.toLowerCase() === "template"
  #|         ? new TestTemplate(document)
  #|         : new TestElement(tag, document);
  #|     },
  #|   };
  #|   globalThis.document = document;
  #|   globalThis.Element = TestElement;
  #|   globalThis.HTMLElement = TestElement;
  #|   globalThis.KeyboardEvent = TestKeyboardEvent;
  #| }

///|
extern "js" fn restore_agent_feedback_markdown_test_browser() -> Unit =
  #| () => {
  #|   const originals = globalThis.__agentFeedbackMarkdownOriginals;
  #|   globalThis.document = originals.document;
  #|   globalThis.Element = originals.Element;
  #|   globalThis.HTMLElement = originals.HTMLElement;
  #|   globalThis.KeyboardEvent = originals.KeyboardEvent;
  #|   delete globalThis.__agentFeedbackMarkdownOriginals;
  #| }

///|
extern "js" fn agent_feedback_test_find_class(
  root : @rdom.Element,
  class_name : String,
) -> @rdom.Element =
  #| (root, className) => {
  #|   const visit = node => {
  #|     const classes = (node.getAttribute?.("class") ?? "").split(/\s+/);
  #|     if (classes.includes(className)) return node;
  #|     for (const child of node.childNodes ?? []) {
  #|       const found = visit(child);
  #|       if (found) return found;
  #|     }
  #|     return null;
  #|   };
  #|   const found = visit(root);
  #|   if (!found) throw new Error(`missing .${className}`);
  #|   return found;
  #| }

///|
extern "js" fn agent_feedback_test_inner_html(
  element : @rdom.Element,
) -> String = "(element) => element.innerHTML"

///|
extern "js" fn agent_feedback_test_first_child(
  element : @rdom.Element,
) -> @rdom.Element =
  #| (element) => {
  #|   if (!element.childNodes[0]) throw new Error("missing first child");
  #|   return element.childNodes[0];
  #| }

///|
extern "js" fn agent_feedback_test_dispatch_escape(
  element : @rdom.Element,
) -> Unit =
  #| element => element.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }))

///|
extern "js" fn agent_feedback_test_dispatch_blur(
  element : @rdom.Element,
) -> Unit =
  #| element => element.dispatchEvent(new Event("blur"))

///|
fn agent_feedback_test_comment(
  id : String,
  line : Int,
  text : String,
  replies : Array[String],
) -> @agent_feedback.SessionEditorComment {
  let feedback : @agent_feedback_api.AgentFeedback = {
    id,
    kind: AgentReview,
    resource: @base_common.Uri::file("/feedback/\{id}.mbt"),
    range: Range(line, 1, line, 2),
    selected_text: None,
    text,
    replies,
    state: Accepted,
  }
  @agent_feedback.get_session_editor_comments([feedback])[0]
}

///|
fn agent_feedback_test_host(
  layout_count : Ref[Int],
) -> AgentFeedbackEditorWidgetHost {
  {
    on_remove: _ => (),
    on_accept: _ => (),
    on_edit: (_, _) => (),
    on_reply: (_, _) => (),
    on_click: _ => (),
    on_hover: _ => (),
    on_hover_end: () => (),
    on_did_expand: _ => (),
    on_layout: _ => layout_count.val += 1,
  }
}

///|
fn AgentFeedbackEditorWidget::test_wrap_markdown_disposable(
  self : AgentFeedbackEditorWidget,
  key : String,
  dispose_count : Ref[Int],
) -> Unit {
  guard self.markdown_disposables.get(key) is Some(original) else {
    abort("missing Markdown target \{key}")
  }
  self.markdown_disposables.set(
    key,
    @base_common.Disposable::from(() => {
      dispose_count.val += 1
      original.dispose()
    }),
  )
}

///|
test "feedback comments and replies use the shared safe Markdown output" {
  install_agent_feedback_markdown_test_browser()
  let comment = agent_feedback_test_comment(
    "safe",
    1,
    "<img src=x onerror=alert(1)> [unsafe](javascript:alert(1)) **safe**",
    [
      (
        #|**reply**
        #|
        #|<script>alert(2)</script>
      ),
    ],
  )
  let widget = AgentFeedbackEditorWidget(
    agent_feedback_test_host(Ref(0)),
    "widget-safe",
    [comment],
    Map([]),
  )
  guard widget.item_nodes.get(comment.id) is Some(item) else {
    fail("missing safe-output item")
  }
  let body = agent_feedback_test_find_class(item, "agent-feedback-widget-text")
  let reply = agent_feedback_test_find_class(
    item, "agent-feedback-widget-reply-text",
  )
  let body_html = agent_feedback_test_inner_html(body)
  let reply_html = agent_feedback_test_inner_html(reply)
  assert_true(body_html.contains("<strong>safe</strong>"))
  assert_false(body_html.contains("<img"))
  assert_false(body_html.contains("onerror"))
  assert_false(body_html.contains("javascript:"))
  assert_true(reply_html.contains("<strong>reply</strong>"))
  assert_false(reply_html.contains("<script"))
  widget.mark_disposed()
  restore_agent_feedback_markdown_test_browser()
}

///|
test "rebuilding feedback items disposes every old Markdown target first" {
  install_agent_feedback_markdown_test_browser()
  let comment = agent_feedback_test_comment("replace", 2, "first", ["old reply"])
  let widget = AgentFeedbackEditorWidget(
    agent_feedback_test_host(Ref(0)),
    "widget-replace",
    [comment],
    Map([]),
  )
  let body_disposed = Ref(0)
  let reply_disposed = Ref(0)
  widget.test_wrap_markdown_disposable(
    feedback_comment_target_key(comment.id),
    body_disposed,
  )
  widget.test_wrap_markdown_disposable(
    feedback_reply_target_key(comment.id, 0),
    reply_disposed,
  )
  widget.build_items()
  assert_eq(body_disposed.val, 1)
  assert_eq(reply_disposed.val, 1)
  assert_eq(widget.markdown_disposables.length(), 2)
  assert_true(
    widget.markdown_disposables.get(feedback_comment_target_key(comment.id))
    is Some(_),
  )
  assert_true(
    widget.markdown_disposables.get(feedback_reply_target_key(comment.id, 0))
    is Some(_),
  )
  widget.mark_disposed()
  restore_agent_feedback_markdown_test_browser()
}

///|
test "editing one comment isolates its Markdown target and restores once" {
  install_agent_feedback_markdown_test_browser()
  let first = agent_feedback_test_comment("first", 1, "first body", [
    "first reply",
  ])
  let second = agent_feedback_test_comment("second", 3, "second body", [
    "second reply",
  ])
  let layout_count = Ref(0)
  let widget = AgentFeedbackEditorWidget(
    agent_feedback_test_host(layout_count),
    "widget-edit",
    [first, second],
    Map([]),
  )
  let first_body_disposed = Ref(0)
  let first_reply_disposed = Ref(0)
  let second_body_disposed = Ref(0)
  let second_reply_disposed = Ref(0)
  widget.test_wrap_markdown_disposable(
    feedback_comment_target_key(first.id),
    first_body_disposed,
  )
  widget.test_wrap_markdown_disposable(
    feedback_reply_target_key(first.id, 0),
    first_reply_disposed,
  )
  widget.test_wrap_markdown_disposable(
    feedback_comment_target_key(second.id),
    second_body_disposed,
  )
  widget.test_wrap_markdown_disposable(
    feedback_reply_target_key(second.id, 0),
    second_reply_disposed,
  )
  guard widget.item_nodes.get(first.id) is Some(first_item) else {
    fail("missing first edit item")
  }
  let first_body = agent_feedback_test_find_class(
    first_item, "agent-feedback-widget-text",
  )
  widget.start_editing(first, first_body)
  assert_eq(first_body_disposed.val, 1)
  assert_eq(first_reply_disposed.val, 0)
  assert_eq(second_body_disposed.val, 0)
  assert_eq(second_reply_disposed.val, 0)
  assert_eq(widget.markdown_disposables.length(), 3)
  assert_true(
    widget.markdown_disposables.get(feedback_comment_target_key(first.id))
    is None,
  )
  let textarea = agent_feedback_test_first_child(first_body)
  let layout_after_open = layout_count.val
  agent_feedback_test_dispatch_escape(textarea)
  assert_eq(widget.markdown_disposables.length(), 4)
  assert_true(
    widget.markdown_disposables.get(feedback_comment_target_key(first.id))
    is Some(_),
  )
  assert_eq(layout_count.val, layout_after_open + 1)
  agent_feedback_test_dispatch_blur(textarea)
  assert_eq(widget.markdown_disposables.length(), 4)
  assert_eq(layout_count.val, layout_after_open + 1)
  widget.mark_disposed()
  restore_agent_feedback_markdown_test_browser()
}

///|
test "feedback teardown disposes all Markdown targets exactly once" {
  install_agent_feedback_markdown_test_browser()
  let comment = agent_feedback_test_comment("dispose", 1, "body", [
    "reply one", "reply two",
  ])
  let widget = AgentFeedbackEditorWidget(
    agent_feedback_test_host(Ref(0)),
    "widget-dispose",
    [comment],
    Map([]),
  )
  let dispose_count = Ref(0)
  widget.test_wrap_markdown_disposable(
    feedback_comment_target_key(comment.id),
    dispose_count,
  )
  widget.test_wrap_markdown_disposable(
    feedback_reply_target_key(comment.id, 0),
    dispose_count,
  )
  widget.test_wrap_markdown_disposable(
    feedback_reply_target_key(comment.id, 1),
    dispose_count,
  )
  widget.mark_disposed()
  widget.mark_disposed()
  assert_true(widget.disposed)
  assert_eq(dispose_count.val, 3)
  assert_true(widget.markdown_disposables.is_empty())
  restore_agent_feedback_markdown_test_browser()
}
