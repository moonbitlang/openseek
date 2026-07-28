// Headless behavior-test harness — the MoonBit analog of vscode's
// editor/test/browser/testCodeEditor.ts. Drives a real Viewer + ViewModel +
// CursorsController over an in-memory model WITHOUT attaching a DOM view
// (mirrors TestCodeEditor._createView returning null), so tests assert on
// semantic state — positions, ranges, projected view lines, frames — instead
// of rendered pixels.
//
// The seam is `Viewer::attach_model` (attach_model.mbt): it builds the
// tokenized document, view model, and cursor context and stores
// them synchronously before `schedule_render`. Only the DOM flush is deferred,
// and `schedule_render`/`flush_render` already no-op while the model has no
// browser bundle. So an unattached viewer has fully-populated semantic state
// after `set_model` — no DOM, no requestAnimationFrame, no measurement needed.

///|
/// Builds a TextModel from raw text. The analog of `instantiateTextModel`.
fn test_model(
  text : String,
  language_id? : String = "plaintext",
) -> @model.TextModel {
  TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="model",
      path="/test-model",
    ),
    "test-model",
    language_id,
    1,
    "",
    text,
  )
}

///|
/// `withTestCodeEditor`: spin up a headless viewer over `text`, run `body`,
/// dispose. No `attach()` — no DOM view — but `set_model` still builds the
/// tokenized doc, view model, render frame, and cursor context synchronously.
///
/// The font is pinned (the macOS defaults) rather than platform-derived:
/// `editor_font_defaults`/`golden_line_height_ratio` differ per host OS
/// (12px/1.5 on macOS, 14px/1.35 elsewhere → line height 18 vs 19), and the
/// layout tests assert absolute pixel offsets. Monaco's testCodeEditor
/// likewise runs over a fixed `TestConfiguration`, not the host font.
fn with_test_viewer(
  text : String,
  body : (Viewer) -> Unit raise,
  options? : ViewerOptions = ViewerOptions(font_size=12, line_height=18),
) -> Unit raise {
  let viewer = Viewer::Viewer(options~) // NOTE: deliberately no attach()
  viewer.set_model(Some(test_model(text)))
  body(viewer)
  viewer.dispose()
}

///|
/// Installs the smallest DOM/runtime surface needed for a real attached View.
/// Timers are held until the Viewer has disposed; the fixture then drains any
/// uncancelled callback (notably the deferred squiggly-theme read) while the
/// fake DOM is still live and restores every global synchronously.
extern "js" fn install_mounted_test_browser() -> Unit =
  #| () => {
  #|   class MountedTestElement extends EventTarget {
  #|     constructor(tag = "div", ownerDocument = null) {
  #|       super();
  #|       this.nodeType = 1;
  #|       this.nodeName = tag.toUpperCase();
  #|       this.attributes = new Map();
  #|       this.childNodes = [];
  #|       this.children = this.childNodes;
  #|       this.parentNode = null;
  #|       this.ownerDocument = ownerDocument;
  #|       this.style = {
  #|         setProperty(name, value) { this[name] = value; },
  #|       };
  #|       this.scrollTop = 0;
  #|       this.scrollLeft = 0;
  #|       this.scrollWidth = 1000;
  #|       this.scrollHeight = 1000;
  #|       this.clientWidth = 100;
  #|       this.clientHeight = 100;
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
  #|       this.childNodes = this.childNodes.filter((item) => item !== child);
  #|       this.children = this.childNodes;
  #|       child.parentNode = null;
  #|       return child;
  #|     }
  #|     contains(child) {
  #|       if (child === this) return true;
  #|       return this.childNodes.some((node) =>
  #|         typeof node.contains === "function" && node.contains(child));
  #|     }
  #|     remove() {
  #|       if (this.parentNode) this.parentNode.removeChild(this);
  #|     }
  #|     focus() { this.dispatchEvent(new Event("focus")); }
  #|     blur() { this.dispatchEvent(new Event("blur")); }
  #|     getBoundingClientRect() {
  #|       return {
  #|         x: 0, y: 0, left: 0, top: 0,
  #|         right: 100, bottom: 100, width: 100, height: 100,
  #|       };
  #|     }
  #|   }
  #|   globalThis.__mountedTestOriginalDocument = globalThis.document;
  #|   globalThis.__mountedTestOriginalElement = globalThis.Element;
  #|   globalThis.__mountedTestOriginalRequestAnimationFrame =
  #|     globalThis.requestAnimationFrame;
  #|   globalThis.__mountedTestOriginalCancelAnimationFrame =
  #|     globalThis.cancelAnimationFrame;
  #|   globalThis.__mountedTestOriginalGetComputedStyle =
  #|     globalThis.getComputedStyle;
  #|   globalThis.__mountedTestOriginalSetTimeout = globalThis.setTimeout;
  #|   globalThis.__mountedTestOriginalClearTimeout = globalThis.clearTimeout;
  #|   globalThis.__mountedTestFrameNextId = 1;
  #|   globalThis.__mountedTestFrames = new Map();
  #|   globalThis.__mountedTestTimerNextId = 1;
  #|   globalThis.__mountedTestTimers = new Map();
  #|   const ownerDocument = new EventTarget();
  #|   ownerDocument.nodeType = 9;
  #|   ownerDocument.defaultView = globalThis;
  #|   ownerDocument.body = new MountedTestElement("body", ownerDocument);
  #|   ownerDocument.createElement = (tag) =>
  #|     new MountedTestElement(tag, ownerDocument);
  #|   ownerDocument.createTextNode = (value) => ({
  #|     nodeType: 3,
  #|     nodeName: "#text",
  #|     nodeValue: String(value),
  #|     parentNode: null,
  #|     ownerDocument,
  #|   });
  #|   globalThis.document = ownerDocument;
  #|   globalThis.Element = MountedTestElement;
  #|   globalThis.requestAnimationFrame = (callback) => {
  #|     const id = globalThis.__mountedTestFrameNextId++;
  #|     globalThis.__mountedTestFrames.set(id, callback);
  #|     return id;
  #|   };
  #|   globalThis.cancelAnimationFrame = (id) => {
  #|     globalThis.__mountedTestFrames.delete(id);
  #|   };
  #|   globalThis.getComputedStyle = () => ({
  #|     getPropertyValue: () => "",
  #|   });
  #|   globalThis.setTimeout = (callback, _ms) => {
  #|     const id = globalThis.__mountedTestTimerNextId++;
  #|     globalThis.__mountedTestTimers.set(id, callback);
  #|     return id;
  #|   };
  #|   globalThis.clearTimeout = (id) => {
  #|     globalThis.__mountedTestTimers.delete(id);
  #|   };
  #| }

///|
extern "js" fn restore_mounted_test_browser() -> Unit =
  #| () => {
  #|   while (globalThis.__mountedTestFrames.size > 0) {
  #|     const pending = Array.from(globalThis.__mountedTestFrames.values());
  #|     globalThis.__mountedTestFrames.clear();
  #|     for (const callback of pending) callback(0);
  #|   }
  #|   while (globalThis.__mountedTestTimers.size > 0) {
  #|     const pending = Array.from(globalThis.__mountedTestTimers.values());
  #|     globalThis.__mountedTestTimers.clear();
  #|     for (const callback of pending) callback();
  #|   }
  #|   const restore = (name, value) => {
  #|     if (value === undefined) {
  #|       delete globalThis[name];
  #|     } else {
  #|       globalThis[name] = value;
  #|     }
  #|   };
  #|   restore("document", globalThis.__mountedTestOriginalDocument);
  #|   restore("Element", globalThis.__mountedTestOriginalElement);
  #|   restore(
  #|     "requestAnimationFrame",
  #|     globalThis.__mountedTestOriginalRequestAnimationFrame,
  #|   );
  #|   restore(
  #|     "cancelAnimationFrame",
  #|     globalThis.__mountedTestOriginalCancelAnimationFrame,
  #|   );
  #|   restore("getComputedStyle", globalThis.__mountedTestOriginalGetComputedStyle);
  #|   restore("setTimeout", globalThis.__mountedTestOriginalSetTimeout);
  #|   restore("clearTimeout", globalThis.__mountedTestOriginalClearTimeout);
  #|   delete globalThis.__mountedTestOriginalDocument;
  #|   delete globalThis.__mountedTestOriginalElement;
  #|   delete globalThis.__mountedTestOriginalRequestAnimationFrame;
  #|   delete globalThis.__mountedTestOriginalCancelAnimationFrame;
  #|   delete globalThis.__mountedTestOriginalGetComputedStyle;
  #|   delete globalThis.__mountedTestOriginalSetTimeout;
  #|   delete globalThis.__mountedTestOriginalClearTimeout;
  #|   delete globalThis.__mountedTestFrameNextId;
  #|   delete globalThis.__mountedTestFrames;
  #|   delete globalThis.__mountedTestTimerNextId;
  #|   delete globalThis.__mountedTestTimers;
  #| }

///|
extern "js" fn flush_mounted_test_frames() -> Unit =
  #| () => {
  #|   while (globalThis.__mountedTestFrames.size > 0) {
  #|     const pending = Array.from(globalThis.__mountedTestFrames.values());
  #|     globalThis.__mountedTestFrames.clear();
  #|     for (const callback of pending) callback(0);
  #|   }
  #| }

///|
extern "js" fn run_one_mounted_test_frame() -> Unit =
  #| () => {
  #|   if (globalThis.__mountedTestFrames.size === 0) {
  #|     throw new Error("expected one pending mounted-test frame");
  #|   }
  #|   const pending = Array.from(globalThis.__mountedTestFrames.values());
  #|   globalThis.__mountedTestFrames.clear();
  #|   for (const callback of pending) callback(0);
  #| }

///|
extern "js" fn mounted_test_frame_count() -> Int =
  #| () => globalThis.__mountedTestFrames.size

///|
extern "js" fn mounted_test_child_count(element : @rdom.Element) -> Int =
  #| (element) => element.childNodes.length

///|
extern "js" fn set_mounted_test_client_size(
  element : @rdom.Element,
  width : Double,
  height : Double,
) -> Unit =
  #| (element, width, height) => {
  #|   element.clientWidth = width;
  #|   element.clientHeight = height;
  #| }

///|
extern "js" fn same_mounted_test_element(
  left : @rdom.Element,
  right : @rdom.Element,
) -> Bool =
  #| (left, right) => left === right

///|
extern "js" fn mounted_test_node_value(node : @rdom.Element) -> String =
  #| (node) => node.nodeValue ?? ""

///|
/// Attached counterpart of `with_test_viewer`. The native frame queue is held,
/// so tests can inspect the browser bundle's pending render/reveal state before
/// a DOM flush consumes it.
fn with_mounted_test_viewer(
  text : String,
  body : (Viewer) -> Unit raise,
  options? : ViewerOptions = ViewerOptions(font_size=12, line_height=18),
) -> Unit raise {
  install_mounted_test_browser()
  defer restore_mounted_test_browser()
  let viewer = Viewer::Viewer(options~)
  defer viewer.dispose()
  let host = @rdom.document().create_element("div")
  viewer.attach(host)
  viewer.set_model(Some(test_model(text)))
  body(viewer)
}

///|
/// `ITestCodeEditor.getViewModel()` — whitebox read of the private field.
fn Viewer::test_view_model(self : Viewer) -> @view_model.ViewModel {
  self.get_view_model().unwrap()
}

///|
/// `ITestCodeEditor`'s cursor read — the view model's always-present
/// controller (`viewModelImpl.ts:124`).
fn Viewer::test_cursor(self : Viewer) -> @cursor.CursorsController {
  self.test_view_model().cursor
}

///|
/// The clamped view-line window the viewer would render for the layout's
/// current visible window — the headless analog of `synced_window`, which
/// only runs inside a DOM flush.
fn Viewer::test_window(self : Viewer) -> @view_layout.LineWindow {
  let view_model = self.test_view_model()
  view_model.clamp_window(view_model.view_layout.visible_window())
}

///|
/// Forces a soft-wrap column and reflows the view model, the headless analog
/// of the wrap width an attached viewer derives from its measured content box.
/// `ViewerOptions` carries no wrap-column field (the real column is measured
/// from the DOM via `soft_wrap_column_for_content_width`), so a headless wrap
/// test sets the private column directly. Requires `options.soft_wrap`.
fn Viewer::test_set_soft_wrap_column(self : Viewer, column : Int) -> Unit {
  self.configuration.commit_soft_wrap_column(column) |> ignore
  self.on_configuration_changed()
}

///|
/// Sets the viewport box the layout windows against, the headless analog of the
/// measured content box, so frame-windowing can be tested without a DOM.
fn Viewer::test_set_viewport(
  self : Viewer,
  width~ : Double,
  height~ : Double,
) -> Unit {
  self.configuration.commit_measured_size(width, height)
  let configuration = self.configuration.snapshot()
  match self.get_view_model() {
    Some(view_model) =>
      view_model.view_layout.set_viewport_size(
        width=configuration.content_width,
        height=configuration.height,
      )
      |> ignore
    None => ()
  }
}

///|
/// A document of `line_count` distinct one-line entries, for windowing tests.
fn long_document(line_count : Int) -> String {
  let out = StringBuilder()
  for i in 0..<line_count {
    if i > 0 {
      out.write_char('\n')
    }
    out.write_string("line ")
    out.write_string(i.to_string())
  }
  out.to_string()
}

///|
/// Component-wise position equality. `@base_common.Position` derives `Eq`/`Debug`
/// but not `Show`, so `assert_eq` on it cannot format a failure message; the
/// rest of this package's tests compare `line_number`/`column` (both `Int`,
/// which has `Show`) the same way.
fn assert_position(
  actual : @base_common.Position,
  expected : @base_common.Position,
) -> Unit raise {
  assert_eq(actual.line_number, expected.line_number)
  assert_eq(actual.column, expected.column)
}

///|
/// Selection equality by endpoints (anchor + active), for the same `Show` reason
/// as `assert_position`.
fn assert_selection_eq(
  actual : @core.Selection,
  expected : @core.Selection,
) -> Unit raise {
  assert_position(actual.get_selection_start(), expected.get_selection_start())
  assert_position(actual.get_position(), expected.get_position())
}

///|
/// `assertCursor`: compare the controller's model selection to an expected one.
fn assert_cursor(viewer : Viewer, expected : @core.Selection) -> Unit raise {
  assert_selection_eq(viewer.test_cursor().get_model_selection(), expected)
}

///|
/// The seam this harness rests on: an unattached viewer (no `attach()`, no DOM
/// view) still has a fully-populated view model synchronously after
/// `set_model`. With a measured viewport the whole short document is the
/// window.
test "set_model populates the view model without attaching" {
  with_test_viewer("alpha\nbeta\ngamma", viewer => {
    viewer.test_set_viewport(width=800.0, height=400.0)
    let window = viewer.test_window()
    assert_eq(window.start, 1)
    assert_eq(window.end, 4)
    assert_eq(viewer.test_view_model().line_count(), 3)
  })
}

///|
/// Step 2 (worked example): the view-axis / soft-wrap projection the memory
/// note flags as previously regressing undetected, now a fast precise harness
/// test instead of a broad/brittle Playwright assertion. Routes a model column
/// through the full Viewer -> ViewModel -> CoordinatesConverter stack.
test "soft wrap maps a model column to the correct view position" {
  let options = ViewerOptions(soft_wrap=true)
  with_test_viewer(
    "abcdefghij",
    viewer => {
      viewer.test_set_soft_wrap_column(6)
      let converter = viewer.test_view_model().coordinates_converter()
      // wrap col 6: view line 1 = "abcdef" (model cols 1-6), view line 2 = "ghij"
      // (model cols 7-10). Model col 9 ('i') projects onto view line 2, col 3.
      let view_pos = converter.model_position_to_view_position(Position(1, 9))
      assert_position(view_pos, Position(2, 3))
      // The wrap boundary itself: model col 7 ('g') starts the continuation line.
      let boundary = converter.model_position_to_view_position(Position(1, 7))
      assert_position(boundary, Position(2, 1))
    },
    options~,
  )
}

///|
/// Step 2 (worked example): the render frame windows to the scrolled viewport
/// while the document height is retained — the semantic core of the
/// "windows the rendered lines while keeping the document height" Playwright
/// spec, now deterministic and DOM-free.
test "render frame windows to the visible range, not the whole document" {
  with_test_viewer(long_document(200), viewer => {
    viewer.test_set_viewport(width=800.0, height=400.0)
    viewer.set_scroll_top(720.0)
    let window = viewer.test_window()
    // Document height is retained...
    assert_eq(viewer.test_view_model().line_count(), 200)
    // ...but only the lines intersecting the viewport are rendered.
    // scroll_top 720 = 40 lines * 18px line height: line 41 is the first
    // visible line.
    assert_eq(window.start, 41)
    assert_true(
      window.end - window.start < viewer.test_view_model().line_count(),
    )
  })
}

///|
/// ModelDecorationOptions plan Phase 5 headless proof: `delta_decorations` from a host
/// makes decorations queryable through the public API and carries them into
/// the render inputs (the viewport's line-span chain and the
/// DecorationsOverlay's viewport collection), including the
/// `ViewModelDecorations` cache invalidation on decoration change.
test "host delta_decorations flows through query API and render inputs" {
  let viewer = Viewer::Viewer()
  viewer.set_model(Some(test_model("alpha beta\ngamma")))
  let view_model = viewer.get_view_model().unwrap()
  // Prime the viewport cache before the host adds decorations, so the second
  // query proves onDidChangeDecorations invalidates it.
  let viewport_range : @base_common.Range = Range(1, 1, 2, 6)
  let before = view_model
    .decorations()
    .get_decorations_viewport_data(viewport_range)
  assert_eq(before.decorations.length(), 0)
  let ids = viewer.delta_decorations([], [
    {
      range: Range(1, 1, 1, 6),
      options: ModelDecorationOptions("myHighlight", description="host"),
    },
    {
      range: Range(2, 1, 2, 3),
      options: ModelDecorationOptions(
        "",
        inline_class_name="host-inline",
        description="host",
      ),
    },
  ])
  assert_eq(ids.length(), 2)
  // Queryable back through the public API (ownerId-scoped).
  assert_eq(viewer.get_line_decorations(1).length(), 1)
  assert_eq(viewer.get_line_decorations(1)[0].options.class_name, "myHighlight")
  assert_eq(viewer.get_decorations_in_range(Range(1, 1, 2, 6)).length(), 2)
  // The same viewport range now resolves the new decorations (cache dropped).
  let after = view_model
    .decorations()
    .get_decorations_viewport_data(viewport_range)
  assert_eq(after.decorations.length(), 2)
  assert_true(after.decorations.any(d => d.options.class_name == "myHighlight"))
  // Render inputs: the inline chain produces the line span; the className
  // decoration is the DecorationsOverlay's input, never a line span.
  let viewport = @view_model.viewport_data_from_view_model(
    view_model,
    { start: 1, end: 3 },
    line_height=18,
  )
  assert_true(
    viewport.line_decorations[1].any(d => d.class_name == "host-inline"),
  )
  assert_false(
    viewport.line_decorations[0].any(d => d.class_name == "myHighlight"),
  )
  // removeDecorations drops them everywhere.
  viewer.remove_decorations(ids)
  assert_eq(viewer.get_line_decorations(1).length(), 0)
  assert_eq(viewer.get_decorations_in_range(Range(1, 1, 2, 6)).length(), 0)
}

///|
/// The editor-id ownership filter: another editor's decorations (a different
/// ownerId) stay invisible to this viewer's scoped queries, while ownerId-0
/// (model-level, e.g. markers) decorations are included.
test "decoration queries are scoped by editor id like Monaco" {
  let viewer = Viewer::Viewer()
  let model = test_model("alpha beta")
  viewer.set_model(Some(model))
  // Model-level decoration (ownerId 0): visible to the scoped query.
  let _ = model.delta_decorations([], [
    { range: Range(1, 1, 1, 3), options: ModelDecorationOptions("model-level") },
  ])
  // Foreign editor's decoration: filtered out.
  let _ = model.delta_decorations(
    [],
    [{ range: Range(1, 4, 1, 6), options: ModelDecorationOptions("foreign") }],
    owner_id=viewer.editor_id + 1000,
  )
  let names = viewer.get_line_decorations(1).map(d => d.options.class_name)
  if names != ["model-level"] {
    fail("got \{Repr(names)}")
  }
}

///|
test "editor ids are process-unique and preincrement in construction order" {
  let first = Viewer::Viewer()
  let second = Viewer::Viewer()
  assert_eq(second.editor_id, first.editor_id + 1)
  first.dispose()
  second.dispose()
}

///|
test "model change fires before outgoing owner decorations are swept" {
  let viewer = Viewer::Viewer()
  let model = test_model("alpha")
  viewer.set_model(Some(model))
  let ids = viewer.delta_decorations([], [
    {
      range: Range(1, 1, 1, 3),
      options: ModelDecorationOptions("owned", description="ordering"),
    },
  ])
  assert_eq(ids.length(), 1)
  let decorations_seen_in_event = Ref(-1)
  let subscription = viewer.on_did_change_model(_ => {
    decorations_seen_in_event.val = model
      .get_all_decorations(owner_id=viewer.editor_id)
      .length()
  })

  viewer.set_model(None)
  assert_eq(decorations_seen_in_event.val, 1)
  assert_eq(model.get_all_decorations(owner_id=viewer.editor_id).length(), 0)
  subscription.dispose()
  viewer.dispose()
  model.dispose()
}

///|
/// Single-state toy tokenizer tagging the first character as a keyword — the
/// encoder's gap fill makes every non-empty line exactly two tokens, so the
/// token count discriminates a registry hit (2) from the null fallback (1).
priv struct FirstCharKeywordToy {
  calls : Ref[Int]
}

///|
let first_char_toy_state : @syntax.TokenizerState = TokenizerState("s")

///|
impl @syntax.LineTokenizer for FirstCharKeywordToy with fn initial_state(_self) {
  first_char_toy_state
}

///|
impl @syntax.LineTokenizer for FirstCharKeywordToy with fn tokenize_line(
  self,
  line_text,
  state,
) {
  self.calls.val += 1
  ignore(line_text)
  let tokens : Array[@syntax.LineToken] = [{ start: 0, end: 1, tag: Keyword }]
  (tokens, state)
}

///|
/// Both build-observation `token_count` producer paths are passive:
/// the headless initial-build telemetry reads the default store without
/// lexing, then a stabilized visible refresh lexes once and its token-change
/// telemetry observes that stored result without another lexer call.
test "initial-build and token-change telemetry read token counts passively" {
  let calls = Ref(0)
  let registration = @syntax.tokenization_registry.register(
    "telemetry-passive-toy",
    FirstCharKeywordToy::{ calls, },
  )
  defer registration.dispose()
  let viewer = Viewer::Viewer()
  defer viewer.dispose()
  let model = test_model(
    "alpha beta\ngamma delta",
    language_id="telemetry-passive-toy",
  )
  defer model.dispose()
  let lexer_calls_at_event : Array[Int] = []
  let token_counts : Array[Int] = []
  let subscription = debug_on_did_build_view_model(viewer, event => {
    lexer_calls_at_event.push(calls.val)
    token_counts.push(event.token_count)
  })
  defer subscription.dispose()

  viewer.set_model(Some(model))
  viewer.test_set_viewport(width=800.0, height=180.0)
  viewer.test_view_model().visible_lines_stabilized()

  assert_true(lexer_calls_at_event == [0, 2])
  assert_true(token_counts == [2, 4])
  assert_eq(calls.val, 2)
}

///|
/// Tokenizer (re)registration reaches the ViewModel event spine without
/// re-warming. Passive telemetry reads defaults; explicit demand owns lexing.
test "tokenizer registration stays passive until explicit demand" {
  let viewer = Viewer::Viewer()
  viewer.set_model(
    Some(test_model("alpha beta\ngamma delta", language_id="recolor-toy")),
  )
  let model = viewer.get_model().unwrap()
  // Attach and telemetry are passive; registry miss yields one default token
  // per line.
  assert_eq(model.tokenization.token_count(), 2)
  let calls = Ref(0)
  let registration = @syntax.tokenization_registry.register("recolor-toy", FirstCharKeywordToy::{
    calls,
  })
  // Registry change emits view/outgoing events, but neither they nor the
  // Build-observation `token_count` telemetry must not invoke the lexer.
  assert_eq(calls.val, 0)
  assert_eq(model.tokenization.token_count(), 2)
  assert_eq(calls.val, 0)
  let demand_view = model.on_before_attached()
  demand_view.set_visible_lines(
    [{ start_line_number: 1, end_line_number: 2 }],
    true,
  )
  model.on_before_detached(demand_view)
  assert_eq(model.tokenization.token_count(), 4)
  assert_eq(calls.val, 2)
  // Deregistration resets back to passive fallback without a lexer call.
  registration.dispose()
  assert_eq(model.tokenization.token_count(), 2)
  assert_eq(calls.val, 2)
  viewer.dispose()
  model.dispose()
}

///|
/// A disposed model detaches itself from the viewer —
/// `model.onWillDispose(() => this.setModel(null))` (`codeEditorWidget.ts:1787`).
test "disposing the installed model detaches it from the viewer" {
  let viewer = Viewer::Viewer()
  let model = test_model("alpha")
  viewer.set_model(Some(model))
  let mut model_change_events = 0
  viewer.on_did_change_model(_ => model_change_events += 1) |> ignore
  model.dispose()
  assert_true(viewer.get_model() is None)
  assert_eq(model_change_events, 1)
  assert_true(model.is_disposed())
  viewer.dispose()
}

///|
/// Swapping models rotates the will-dispose subscription: disposing the
/// replaced model must not detach the current one.
test "disposing a replaced model leaves the current model attached" {
  let viewer = Viewer::Viewer()
  let first = test_model("one")
  viewer.set_model(Some(first))
  let second = test_model("two")
  viewer.set_model(Some(second))
  first.dispose()
  assert_eq(viewer.get_model().unwrap().get_value(), "two")
  viewer.dispose()
  second.dispose()
}
