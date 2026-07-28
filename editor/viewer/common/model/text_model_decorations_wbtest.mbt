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
  stickiness? : TrackedRangeStickiness = AlwaysGrowsWhenTypingAtEdges,
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
fn assert_names_eq(
  actual : Array[String],
  expected : Array[String],
) -> Unit raise {
  if actual != expected {
    fail("got \{Repr(actual)}, expected \{Repr(expected)}")
  }
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
  let emitter = DidChangeDecorationsEmitter::new()
  let events : Array[ModelDecorationsChangedEvent] = []
  let _ = emitter.actual.event(e => events.push(e))
  emitter.begin_deferred_emit()
  emitter.check_affected_and_fire(
    wb_options("a", overview_ruler={ color: Some("red"), position: Center }),
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
test "delta semantics: unknown old ids skipped, node reuse keeps the id" {
  let model = wb_model("alpha beta\ngamma")
  let first = model.delta_decorations([], [
    { range: Range(1, 1, 1, 3), options: wb_options("one") },
  ])
  // unknown old ids are skipped
  let second = model.delta_decorations(["not-a-real-id"], [
    { range: Range(2, 1, 2, 3), options: wb_options("two") },
  ])
  assert_eq(model.get_all_decorations().length(), 2)
  // node reuse: replacing via the old id returns the same id
  let third = model.delta_decorations(first, [
    { range: Range(1, 4, 1, 6), options: wb_options("three") },
  ])
  if third != first {
    fail("expected node reuse to keep ids")
  }
  assert_range_opt_eq(
    model.get_decoration_range(first[0]),
    Some(Range(1, 4, 1, 6)),
  )
  assert_eq(model.get_decoration_options(first[0]).unwrap().class_name, "three")
  // removing without replacement drops the id from the map
  let _ = model.delta_decorations(second, [])
  assert_eq(model.get_all_decorations().length(), 1)
  assert_true(model.get_decoration_range(second[0]) is None)
}

///|
test "re-entrant deltaDecorations still lands both decorations" {
  // The recursion warning itself goes to the console (as in the source);
  // asserted behavior is that the nested call is not lost.
  let model = wb_model("alpha")
  let re_entered = Ref(false)
  let _ = model.on_did_change_decorations(_e => {
    if !re_entered.val {
      re_entered.val = true
      let _ = model.delta_decorations([], [
        { range: Range(1, 2, 1, 3), options: wb_options("nested") },
      ])
    }
  })
  let _ = model.delta_decorations([], [
    { range: Range(1, 1, 1, 2), options: wb_options("outer") },
  ])
  assert_eq(model.get_all_decorations().length(), 2)
}

///|
test "search filters: ownerId, filterOutValidation, margin, overview-ruler routing" {
  let model = wb_model("alpha beta gamma\ndelta")
  let _ = model.delta_decorations([], [
    { range: Range(1, 1, 1, 3), options: wb_options("plain-owner0") },
  ])
  let _ = model.delta_decorations(
    [],
    [
      { range: Range(1, 4, 1, 6), options: wb_options("owner1") },
      { range: Range(1, 7, 1, 9), options: wb_options("squiggly-error") },
      {
        range: Range(1, 10, 1, 12),
        options: wb_options("margin", glyph_margin_class_name="glyph"),
      },
    ],
    owner_id=1,
  )
  let _ = model.delta_decorations(
    [],
    [
      {
        range: Range(2, 1, 2, 3),
        options: wb_options("ruler", overview_ruler={
          color: Some("red"),
          position: Center,
        }),
      },
    ],
    owner_id=2,
  )

  // no filters: all 5
  assert_eq(model.get_all_decorations().length(), 5)
  // ownerId filter keeps ownerId-0 nodes and drops other owners
  let owner1 = model
    .get_all_decorations(owner_id=1)
    .map(d => d.options.class_name)
  owner1.sort()
  assert_names_eq(owner1, ["margin", "owner1", "plain-owner0", "squiggly-error"])
  // filterOutValidation drops squiggly-error/warning/info class names only
  let no_validation = model
    .get_all_decorations(filter_out_validation=true)
    .map(d => d.options.class_name)
  // MoonBit String sort is length-first, hence "ruler" leading
  no_validation.sort()
  assert_names_eq(no_validation, ["ruler", "margin", "owner1", "plain-owner0"])
  // margin-only keeps the glyph-margin node
  assert_names_eq(
    model.get_all_margin_decorations().map(d => d.options.class_name),
    ["margin"],
  )
  // overview-ruler-only reads tree1 exclusively
  assert_names_eq(
    model.get_overview_ruler_decorations().map(d => d.options.class_name),
    ["ruler"],
  )
  // interval query path applies the same filters
  let line1 = model.get_line_decorations(
    1,
    owner_id=1,
    filter_out_validation=true,
  )
  let line1_names = line1.map(d => d.options.class_name)
  line1_names.sort()
  assert_names_eq(line1_names, ["margin", "owner1", "plain-owner0"])
}

///|
test "options normalization: cleanClassName, defaults, relaxed range clamp" {
  let options = wb_options("my.class!x")
  assert_eq(options.class_name, "my class x")
  assert_eq(options.z_index, 0)
  assert_true(options.stickiness is AlwaysGrowsWhenTypingAtEdges)
  let model = wb_model("short")
  let ids = model.delta_decorations([], [
    { range: Range(1, 1, 100, 42), options },
  ])
  // _validateRangeRelaxedNoAllocations clamps to the document end
  assert_range_opt_eq(
    model.get_decoration_range(ids[0]),
    Some(Range(1, 1, 1, 6)),
  )
}

///|
test "changeDecorationOptions migrates between tree0 and tree1" {
  let model = wb_model("alpha")
  let id = model.change_decorations(accessor => {
    (accessor.add_decoration)(Range(1, 1, 1, 3), wb_options("plain"))
  })
  assert_eq(model.get_overview_ruler_decorations().length(), 0)
  model.change_decorations(accessor => {
    (accessor.change_decoration_options)(
      id,
      wb_options("now-ruler", overview_ruler={
        color: Some("red"),
        position: Center,
      }),
    )
  })
  assert_names_eq(
    model.get_overview_ruler_decorations().map(d => d.options.class_name),
    ["now-ruler"],
  )
  assert_eq(model.get_all_decorations().length(), 1)
  model.change_decorations(accessor => {
    (accessor.change_decoration_options)(id, wb_options("plain-again"))
  })
  assert_eq(model.get_overview_ruler_decorations().length(), 0)
  assert_names_eq(model.get_all_decorations().map(d => d.options.class_name), [
    "plain-again",
  ])
}
