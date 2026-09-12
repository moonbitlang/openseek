// Initialization-order behavior port from Monaco
// b18492a288de038fbc7643aae6de8247029d11bd:
// - `browser/config/elementSizeObserver.ts:21-28,101-119`
// - `browser/widget/codeEditor/codeEditorWidget.ts:1750-1764,1889-1920`
// - `browser/widget/codeEditor/codeEditorWidget.ts:1074-1076`
// - `workbench/contrib/files/browser/editors/textFileEditor.ts:129-156`

///|
priv struct InitializationCountingTokenizer {
  calls : Ref[Int]
}

///|
impl @syntax.LineTokenizer for InitializationCountingTokenizer with fn initial_state(
  _self,
) {
  TokenizerState()
}

///|
impl @syntax.LineTokenizer for InitializationCountingTokenizer with fn tokenize_line(
  self,
  line_text,
  state,
) {
  self.calls.val += 1
  let tokens : Array[@syntax.LineToken] = []
  if line_text.length() > 0 {
    tokens.push({ start: 0, end: 1, tag: Keyword, })
  }
  (tokens, state)
}

///|
test "headless model attach waits for explicit initialization" {
  let calls = Ref(0)
  let registration = @syntax.tokenization_registry.register(
    "initialization-order-headless",
    InitializationCountingTokenizer::{ calls, },
  )
  defer registration.dispose()
  let viewer = CodeEditorWidget::CodeEditorWidget(
    options=CodeEditorOptions(font_size=12, line_height=18),
  )
  defer viewer.dispose()
  let model = test_model(
    long_document(20),
    language_id="initialization-order-headless",
  )
  defer model.dispose()
  viewer.set_model(Some(model))
  viewer.test_set_viewport(width=200.0, height=90.0)
  assert_eq(calls.val, 0)

  viewer.handle_initialized()
  assert_true(calls.val > 1)
}

///|
test "initialization reentry does not initialize a replacement model" {
  let first_calls = Ref(0)
  let first_registration = @syntax.tokenization_registry.register(
    "initialization-order-reentry-first",
    InitializationCountingTokenizer::{ calls: first_calls, },
  )
  defer first_registration.dispose()
  let replacement_calls = Ref(0)
  let replacement_registration = @syntax.tokenization_registry.register(
    "initialization-order-reentry-replacement",
    InitializationCountingTokenizer::{ calls: replacement_calls, },
  )
  defer replacement_registration.dispose()
  let viewer = CodeEditorWidget::CodeEditorWidget()
  defer viewer.dispose()
  let first = test_model(
    long_document(4),
    language_id="initialization-order-reentry-first",
  )
  defer first.dispose()
  let replacement = test_model(
    long_document(6),
    language_id="initialization-order-reentry-replacement",
  )
  defer replacement.dispose()
  let mut replaced = false
  let subscription = debug_on_did_build_view_model(viewer, _ => {
    if !replaced && first_calls.val > 0 {
      replaced = true
      viewer.set_model(Some(replacement))
    }
  })
  defer subscription.dispose()
  viewer.set_model(Some(first))
  viewer.test_set_viewport(width=200.0, height=90.0)

  viewer.handle_initialized()
  assert_true(replaced)
  assert_true(viewer.get_model().unwrap().same(replacement))
  assert_eq(replacement_calls.val, 0)

  viewer.handle_initialized()
  assert_true(replacement_calls.val > 0)
}
