///| Conformance ports and readonly adaptations from
/// `vscode/src/vs/editor/test/browser/viewModel/viewModelImpl.test.ts` in the
/// checked-in vscode source.

///|
fn view_model_impl_reference_model(
  text : String,
  path : String,
) -> @model.TextModel {
  TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="view-model-impl-reference",
      path~,
    ),
    path,
    "view-model-impl-reference",
    1,
    "reference-revision",
    text,
  )
}

///|
fn reference_range_is_valid(
  view_model : ViewModel,
  model : @model.TextModel,
) -> Bool {
  let model_range = model.get_full_model_range()
  let view_range = view_model
    .coordinates_converter()
    .model_range_to_view_range(model_range)
  let round_trip = view_model
    .coordinates_converter()
    .view_range_to_model_range(view_range)
  round_trip == model_range &&
  view_range.start_line_number >= 1 &&
  view_range.end_line_number <= view_model.line_count()
}

///|
test "view models react first to model changes" {
  let model = view_model_impl_reference_model(
    "Hello\nworld", "/react-first.mbt",
  )
  let first = ViewModel(model)
  let second = ViewModel(model)
  let observed : Array[String] = []
  let mut is_first = true
  let mut callbacks_valid = true
  let _subscription = model.on_did_change_content(event => {
    // Both registered ViewModels complete loop one before any public model
    // listener runs, including the hostile nested mutation below.
    callbacks_valid = callbacks_valid &&
      first.line_count() == model.get_line_count() &&
      second.line_count() == model.get_line_count() &&
      reference_range_is_valid(first, model) &&
      reference_range_is_valid(second, model)
    observed.push("public:\{event.version_id}:\{model.get_line_count()}")
    if is_first {
      is_first = false
      // Readonly adaptation of deleting the newline in the upstream edit:
      // nested full-buffer replacement stresses the same two-loop ordering.
      model.set_value("Helloworld!")
    }
  })
  model.set_value("Hello\nworld!")
  assert_true(observed == ["public:2:2", "public:3:1"])
  assert_true(callbacks_valid)
  assert_eq(first.line_count(), 1)
  assert_eq(second.line_count(), 1)
  assert_true(reference_range_is_valid(first, model))
  assert_true(reference_range_is_valid(second, model))
  first.dispose()
  second.dispose()
  model.dispose()
}

///|
test "issue #44805: No visible lines via API call" {
  let model = view_model_impl_reference_model(
    (
      #|line1
      #|line2
      #|line3
    ),
    "/issue-44805-api.mbt",
  )
  let view_model = ViewModel(model)
  assert_eq(view_model.line_count(), 3)
  assert_true(view_model.set_hidden_areas([Range(1, 1, 3, 1)]))
  // The readonly hidden-area contract reveals everything when a caller asks
  // to hide the whole model. The non-null MoonBit array below is the local
  // counterpart of upstream `getVisibleRanges() !== null`.
  assert_eq(view_model.line_count(), 3)
  assert_eq(view_model.get_hidden_areas().length(), 0)
  assert_true(view_model.model_position_is_visible(Position(1, 1)))
  let visible = view_model.to_model_visible_ranges(
    Range(1, 1, 3, view_model.get_line_max_column(3)),
  )
  assert_eq(visible.length(), 1)
  for range in visible {
    assert_true(model.validate_range(range) == range)
  }
  view_model.dispose()
  model.dispose()
}

// SKIPPED: issue #44805: No visible lines via undoing — readonly Viewer has
// no undo API or editable undo stack (UTM-018).

///|
test "model-token callback converts wrapped and hidden ranges before outgoing delivery" {
  let model = view_model_impl_reference_model(
    (
      #|abcdefghij
      #|hidden
      #|uvwxyz
    ),
    "/model-token-order.mbt",
  )
  let mut original : @model.ModelTokensChangedEvent? = None
  let _model_subscription = model.on_did_change_tokens(event => {
    original = Some(event)
  })
  let delivery_order : Array[String] = []
  let converted : Array[Array[ViewTokensChangedRange]] = []
  let view_model = ViewModel::with_options(
    model,
    ViewModelOptions::soft_wrap(5),
    emit_view_tokens_changed=ranges => {
      delivery_order.push("view")
      converted.push(ranges)
    },
  )
  assert_true(view_model.set_hidden_areas([Range(2, 1, 2, 1)]))
  let outgoing_events : Array[@model.ModelTokensChangedEvent] = []
  let mut outgoing_identity = false
  let _outgoing_subscription = view_model.on_model_tokens_changed(outgoing => {
    delivery_order.push("outgoing")
    match original {
      Some(source_event) =>
        outgoing_identity = physical_equal(outgoing.event, source_event)
      None => outgoing_identity = false
    }
    outgoing_events.push(outgoing.event)
  })
  let registration = @syntax.tokenization_registry.register(
    "view-model-impl-reference",
    @plain_tokenizer.PlainTokenizer(),
  )
  assert_true(delivery_order == ["view", "outgoing"])
  assert_eq(converted.length(), 1)
  assert_eq(converted[0].length(), 1)
  // Model line 1 wraps to two view lines, model line 2 is hidden, and model
  // line 3 wraps to two more. The inclusive full-model token range maps 1..4.
  assert_eq(converted[0][0].from_line_number, 1)
  assert_eq(converted[0][0].to_line_number, 4)
  assert_eq(outgoing_events.length(), 1)
  assert_true(outgoing_identity)
  assert_true(physical_equal(outgoing_events[0], original.unwrap()))
  view_model.dispose()
  registration.dispose()
  model.dispose()
}

///|
test "headless token callback defaults to no-op and disposal removes delivery" {
  let model = view_model_impl_reference_model(
    "one\ntwo", "/model-token-headless.mbt",
  )
  let view_model = ViewModel(model)
  let mut delivered = 0
  let _subscription = view_model.on_model_tokens_changed(_ => delivered += 1)
  // No browser callback was supplied: the private default sink completes as a
  // no-op, then the typed outgoing listener still observes the source event.
  let registration = @syntax.tokenization_registry.register(
    "view-model-impl-reference",
    @plain_tokenizer.PlainTokenizer(),
  )
  assert_eq(delivered, 1)
  view_model.dispose()
  registration.dispose()
  assert_eq(delivered, 1)
  model.dispose()
}
