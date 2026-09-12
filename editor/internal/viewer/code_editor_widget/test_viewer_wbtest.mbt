///|
/// The seam this harness rests on: an unattached viewer (no `attach()`, no DOM
/// view) still has a fully-populated view model synchronously after
/// `set_model`. With a measured viewport the whole short document is the
/// window.
test "set_model populates the view model without attaching" {
  with_test_viewer(
    (
      #|alpha
      #|beta
      #|gamma
    ),
    viewer => {
      viewer.test_set_viewport(width=800.0, height=400.0)
      let window = viewer.test_window()
      assert_eq(window.start, 1)
      assert_eq(window.end, 4)
      assert_eq(viewer.test_view_model().line_count(), 3)
    },
  )
}

///|
/// Step 2 (worked example): the view-axis / soft-wrap projection the memory
/// note flags as previously regressing undetected, now a fast precise harness
/// test instead of a broad/brittle Playwright assertion. Routes a model column
/// through the full CodeEditorWidget -> ViewModel -> CoordinatesConverter stack.
test "soft wrap maps a model column to the correct view position" {
  let options = CodeEditorOptions(soft_wrap=true)
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
  let viewer = CodeEditorWidget::CodeEditorWidget()
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
    { start: 1, end: 3, },
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
  let viewer = CodeEditorWidget::CodeEditorWidget()
  let model = test_model("alpha beta")
  viewer.set_model(Some(model))
  // Model-level decoration (ownerId 0): visible to the scoped query.
  let _ = model.delta_decorations([], [
    {
      range: Range(1, 1, 1, 3),
      options: ModelDecorationOptions("model-level"),
    },
  ])
  // Foreign editor's decoration: filtered out.
  let _ = model.delta_decorations(
    [],
    [{ range: Range(1, 4, 1, 6), options: ModelDecorationOptions("foreign"), }],
    owner_id=viewer.editor_id + 1000,
  )
  let names = viewer.get_line_decorations(1).map(d => d.options.class_name)
  if names != ["model-level"] {
    fail("got \{Repr(names)}")
  }
}

///|
test "editor ids are process-unique and preincrement in construction order" {
  let first = CodeEditorWidget::CodeEditorWidget()
  let second = CodeEditorWidget::CodeEditorWidget()
  assert_eq(second.editor_id, first.editor_id + 1)
  first.dispose()
  second.dispose()
}

///|
test "model change fires before outgoing owner decorations are swept" {
  let viewer = CodeEditorWidget::CodeEditorWidget()
  let model = test_model("alpha")
  viewer.set_model(Some(model))
  let ids = viewer.delta_decorations([], [
    {
      range: Range(1, 1, 1, 3),
      options: ModelDecorationOptions("owned", description="ordering"),
    },
  ])
  assert_eq(ids.length(), 1)
  let mut decorations_seen_in_event = -1
  let subscription = viewer.on_did_change_model(_ => {
    decorations_seen_in_event = model
      .get_decorations_in_range(
        model.get_full_model_range(),
        owner_id=viewer.editor_id,
      )
      .length()
  })

  viewer.set_model(None)
  assert_eq(decorations_seen_in_event, 1)
  assert_eq(
    model
    .get_decorations_in_range(
      model.get_full_model_range(),
      owner_id=viewer.editor_id,
    )
    .length(),
    0,
  )
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
let first_char_toy_state : @syntax.TokenizerState = TokenizerState()

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
  let tokens : Array[@syntax.LineToken] = [{ start: 0, end: 1, tag: Keyword, }]
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
  let viewer = CodeEditorWidget::CodeEditorWidget()
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
  let viewer = CodeEditorWidget::CodeEditorWidget()
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
  viewer.test_set_viewport(width=800.0, height=180.0)
  viewer.test_view_model().visible_lines_stabilized()
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
  let viewer = CodeEditorWidget::CodeEditorWidget()
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
  let viewer = CodeEditorWidget::CodeEditorWidget()
  let first = test_model("one")
  viewer.set_model(Some(first))
  let second = test_model("two")
  viewer.set_model(Some(second))
  first.dispose()
  assert_eq(viewer.get_model().unwrap().get_value(), "two")
  viewer.dispose()
  second.dispose()
}
