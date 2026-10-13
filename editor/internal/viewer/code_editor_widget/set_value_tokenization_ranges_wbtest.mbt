// Flush-range projection-domain evidence for tokenization parity.
// `TextModel._emitContentChangedEvent` runs tokenization before ViewModel
// content delivery in the checked-in vscode source.

///|
fn assert_flush_token_range_domains(
  old_text : String,
  new_text : String,
  old_line_count : Int32,
  new_line_count : Int32,
  expected_token_to_line : Int32,
) -> Unit raise {
  let model = test_model(old_text, language_id="flush-range-domain")
  defer model.dispose()
  let viewer = CodeEditorWidget::CodeEditorWidget(
    options=CodeEditorOptions(font_size=12, line_height=18),
  )
  defer viewer.dispose()
  viewer.set_model(Some(model))
  viewer.test_set_viewport(width=800.0, height=800.0)
  let view_model = viewer.test_view_model()
  view_model.visible_lines_stabilized()
  assert_eq(view_model.line_count(), old_line_count)

  let token_ranges : Array[(Int32, Int32)] = []
  let view_counts_during_token_event : Array[Int32] = []
  let model_counts_during_token_event : Array[Int32] = []
  let subscription = view_model.on_model_tokens_changed(outgoing => {
    for range in outgoing.event.ranges {
      token_ranges.push((range.from_line_number, range.to_line_number))
    }
    view_counts_during_token_event.push(view_model.line_count())
    model_counts_during_token_event.push(model.get_line_count())
  })
  defer subscription.dispose()

  model.set_value(new_text)

  assert_true(token_ranges == [(1, expected_token_to_line)])
  // The token event is converted against the still-old projection, while its
  // range is also valid in the already-installed replacement model.
  assert_true(view_counts_during_token_event == [old_line_count])
  assert_true(model_counts_during_token_event == [new_line_count])
  assert_eq(view_model.line_count(), new_line_count)
}

///|
test "flush visible token ranges stay valid in old and new projection domains" {
  let registration = @syntax.tokenization_registry.register(
    "flush-range-domain",
    @plain_tokenizer.PlainTokenizer(),
  )
  defer registration.dispose()
  // Growth keeps the old visible upper bound.
  assert_flush_token_range_domains(
    "one\ntwo",
    (
      #|one
      #|two
      #|three
      #|four
    ),
    2,
    4,
    2,
  )
  // Shrink clamps the old visible upper bound to the new line count.
  assert_flush_token_range_domains(
    (
      #|one
      #|two
      #|three
      #|four
    ),
    "one\ntwo",
    4,
    2,
    2,
  )
}
