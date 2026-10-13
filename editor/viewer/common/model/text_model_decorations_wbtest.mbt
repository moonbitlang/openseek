///| White-box tests for the TextModel decoration storage
/// (`text_model_decorations.mbt`): local companions for the plan's test
/// matrix rows — emitter deferred brackets + `fire`, delta id/node reuse
/// semantics, search filters (ownerId / filterOutValidation / margin /
/// overview-ruler tree routing), options normalization, and the tree0↔tree1
/// migration in `change_decoration_options`.

///|
fn wb_model(text : String) -> TextModel {
  TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="model",
      path="/wb.mbt",
    ),
    "",
    "moonbit",
    1,
    "",
    text,
  )
}

///|
fn wb_options(
  class_name : String,
  stickiness~ : TrackedRangeStickiness = AlwaysGrowsWhenTypingAtEdges,
  glyph_margin_class_name? : String,
  overview_ruler? : ModelDecorationOverviewRulerOptions,
) -> ModelDecorationOptions {
  ModelDecorationOptions(
    class_name,
    stickiness~,
    glyph_margin_class_name?,
    overview_ruler?,
    description="test",
  )
}

///|
fn assert_range_opt_eq(
  actual : @base_common.Range?,
  expected : @base_common.Range?,
) -> Unit raise {
  if actual != expected {
    fail("got \{Repr(actual)}, expected \{Repr(expected)}")
  }
}

///|
test "emitter batches one event per deferred bracket; fire() sets all flags" {
  let emitter = DidChangeDecorationsEmitter::DidChangeDecorationsEmitter()
  let events : Array[ModelDecorationsChangedEvent] = []
  let _ = emitter.actual.event(e => events.push(e))
  emitter.begin_deferred_emit()
  emitter.check_affected_and_fire(
    wb_options("a", overview_ruler={ color: Some("red"), position: Center, }),
  )
  emitter.check_affected_and_fire(wb_options("b"))
  assert_eq(events.length(), 0)
  emitter.end_deferred_emit()
  assert_eq(events.length(), 1)
  debug_inspect(
    events[0],
    content=(
      #|{
      #|  affects_minimap: false,
      #|  affects_overview_ruler: true,
      #|  affects_glyph_margin: false,
      #|  affects_injected_text: false,
      #|  affects_line_number: false,
      #|}
    ),
  )
  emitter.fire()
  assert_eq(events.length(), 2)
  debug_inspect(
    events[1],
    content=(
      #|{
      #|  affects_minimap: true,
      #|  affects_overview_ruler: true,
      #|  affects_glyph_margin: true,
      #|  affects_injected_text: true,
      #|  affects_line_number: false,
      #|}
    ),
  )
}

///|
test "options normalization: cleanClassName, defaults, relaxed range clamp" {
  let options = wb_options("my.class!x")
  assert_eq(options.class_name, "my class x")
  assert_eq(options.z_index, 0)
  assert_true(options.stickiness is AlwaysGrowsWhenTypingAtEdges)
  let model = wb_model("short")
  let ids = model.delta_decorations([], [
    { range: Range(1, 1, 100, 42), options, },
  ])
  // _validateRangeRelaxedNoAllocations clamps to the document end
  assert_range_opt_eq(
    model.get_decoration_range(ids[0]),
    Some(Range(1, 1, 1, 6)),
  )
}
