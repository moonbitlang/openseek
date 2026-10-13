// Stabilized-visible-range producer/oracle closure (STB-001..005).
//
// Pinned Monaco source clusters:
// - browser/widget/codeEditor/codeEditorWidget.ts:1074-1076
//   sha256 18dd294ed185a29c590df75656f18f27d0cefc8d4d778559db946d447130e5d8
// - browser/view.ts:673-679
//   sha256 22edb04795705b7fc8675ba40d89c448a62141201f1a16b1f20d8b26e82771e2

///|
priv struct RestoreStateCountingTokenizer {
  calls : Ref[Int32]
}

///|
impl @syntax.LineTokenizer for RestoreStateCountingTokenizer with fn initial_state(
  _self,
) {
  TokenizerState()
}

///|
impl @syntax.LineTokenizer for RestoreStateCountingTokenizer with fn tokenize_line(
  self,
  _line_text,
  state,
) {
  self.calls.val += 1
  ([], state)
}

///|
/// STB-003..005: `View.restoreState` commits both immediate-scroll axes first,
/// the ViewModel-owned scroll listener publishes unstable ranges, and only
/// then the restore producer publishes one stabilized update for the restored
/// viewport. The headless attachment has no scheduler, so the false arm cannot
/// lex; the true arm's synchronous lexer work is the ordering oracle.
test "restore view state commits scroll before stabilized visible lines" {
  let calls = Ref(0)
  let registration = @syntax.tokenization_registry.register(
    "restore-view-state-test",
    RestoreStateCountingTokenizer::{ calls, },
  )
  defer registration.dispose()
  let viewer = CodeEditorWidget::CodeEditorWidget(
    options=CodeEditorOptions(font_size=12, line_height=18),
  )
  defer viewer.dispose()
  let model = test_model(
    long_document(200),
    language_id="restore-view-state-test",
  )
  defer model.dispose()
  viewer.set_model(Some(model))

  let layout = viewer.test_view_model().view_layout
  layout.set_viewport_size(width=90.0, height=36.0) |> ignore
  layout.set_content_width(2000.0) |> ignore
  calls.val = 0

  let scroll_positions : Array[(Double, Double)] = []
  let lexer_calls_during_scroll : Array[Int32] = []
  let listener = layout.on_did_scroll(_change => {
    let position = layout.position()
    scroll_positions.push((position.scroll_top, position.scroll_left))
    lexer_calls_during_scroll.push(calls.val)
  })
  defer listener.dispose()

  viewer.restore_view_state(
    Some({ scroll_top: 180.0, scroll_left: 120.0, folding_state: None, }),
  )

  assert_eq(scroll_positions.length(), 1)
  assert_eq(scroll_positions[0].0, 180.0)
  assert_eq(scroll_positions[0].1, 120.0)
  assert_true(lexer_calls_during_scroll == [0])
  assert_true(calls.val > 0)
}

///|
/// The `None` restore arm is a no-op. After an unstable scroll, a stray
/// stabilized publication would synchronously invoke the counting tokenizer;
/// repeated generic render flushes must remain passive too.
test "None restore and repeated render do not publish stabilized visible lines" {
  let calls = Ref(0)
  let registration = @syntax.tokenization_registry.register(
    "restore-view-state-none-test",
    RestoreStateCountingTokenizer::{ calls, },
  )
  defer registration.dispose()
  let viewer = CodeEditorWidget::CodeEditorWidget(
    options=CodeEditorOptions(font_size=12, line_height=18),
  )
  defer viewer.dispose()
  let model = test_model(
    long_document(80),
    language_id="restore-view-state-none-test",
  )
  defer model.dispose()
  viewer.set_model(Some(model))
  viewer.test_set_viewport(width=90.0, height=36.0)
  viewer.set_scroll_top(180.0)
  calls.val = 0

  viewer.restore_view_state(None)
  assert_eq(viewer.get_scroll_top(), 180.0)

  viewer.flush_render()
  viewer.flush_render()
  assert_eq(calls.val, 0)
}

///|
/// STB-002: once the model is absent, even a concrete restore state is a no-op.
/// Attached count, lexer calls, and public scroll getters make the no-model
/// branch observable without exporting the attached-view state carrier.
test "restore view state is a no-op without a model" {
  let calls = Ref(0)
  let registration = @syntax.tokenization_registry.register(
    "restore-view-state-detached-test",
    RestoreStateCountingTokenizer::{ calls, },
  )
  defer registration.dispose()
  let viewer = CodeEditorWidget::CodeEditorWidget(
    options=CodeEditorOptions(font_size=12, line_height=18),
  )
  defer viewer.dispose()
  let model = test_model(
    long_document(80),
    language_id="restore-view-state-detached-test",
  )
  defer model.dispose()
  viewer.set_model(Some(model))
  viewer.test_set_viewport(width=90.0, height=36.0)
  viewer.set_scroll_top(180.0)
  calls.val = 0

  viewer.set_model(None)
  viewer.restore_view_state(
    Some({ scroll_top: 360.0, scroll_left: 70.0, folding_state: None, }),
  )
  viewer.flush_render()
  viewer.flush_render()

  assert_eq(calls.val, 0)
  assert_eq(viewer.get_scroll_top(), -1.0)
  assert_eq(viewer.get_scroll_left(), -1.0)
}
