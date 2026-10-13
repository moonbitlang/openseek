///| Exact local evidence for the real viewport batch seam required by
/// `viewModelImpl.getViewportViewLineRenderingData` and
/// `viewLinesViewportData.ts` in the checked-in vscode source.

///|
priv struct ViewportCountingTokenizer {
  calls : Ref[Int32]
}

///|
let viewport_counting_state : @syntax.TokenizerState = TokenizerState()

///|
impl @syntax.LineTokenizer for ViewportCountingTokenizer with fn initial_state(
  _self,
) {
  viewport_counting_state
}

///|
impl @syntax.LineTokenizer for ViewportCountingTokenizer with fn tokenize_line(
  self,
  _line_text,
  _state,
) {
  self.calls.val += 1
  ([], viewport_counting_state)
}

///|
test "real viewport uses one batch, one passive read per projected model line, and zero lexer calls" {
  let calls = Ref(0)
  let registration = @syntax.tokenization_registry.register(
    "viewport-counting",
    ViewportCountingTokenizer::{ calls, },
  )
  defer registration.dispose()
  let model = @model.TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="viewport-batch",
      path="/viewport.mbt",
    ),
    "viewport.mbt",
    "viewport-counting",
    1,
    "viewport-batch",
    (
      #|abcdefghij
      #|klmn
      #|opqr
    ),
  )
  let view_model = ViewModel::with_options(
    model,
    ViewModelOptions::soft_wrap(4),
  )
  defer view_model.dispose()
  let lines = view_model.lines()
  assert_eq(lines.get_view_line_count(), 5)
  lines.batch_call_count = 0
  lines.passive_token_read_count = 0

  let viewport = viewport_data_from_view_model(
    view_model,
    { start: 1, end: 6, },
    line_height=18,
  )

  assert_eq(viewport.lines.length(), 5)
  assert_eq(lines.batch_call_count, 1)
  assert_eq(lines.passive_token_read_count, 3)
  assert_eq(calls.val, 0)
}
