///| White-box conformance port of vscode's `modelDecorations.test.ts` (pinned
/// `vscode/` checked-in submodule):
/// `vscode/src/vs/editor/test/common/model/modelDecorations.test.ts`.
///
/// Ported here (against the real interval-tree decoration storage):
/// - "Editor Model - Model Decorations": the query rows (`single character
///   decoration` … `multiple line decoration`), the CRUD rows (`decoration
///   gets removed`, `decorations get removed`, `decoration range can be
///   changed`), the eventing rows (`decorations emit event on
///   add/change/remove`, `decorations do not emit event on no-op
///   deltaDecorations`), and `removeAllDecorationsWithOwnerId works`.
/// - "deltaDecorations": `result respects input`, `deltaDecorations 1/2/3`,
///   `issue #4317` (Monaco `hoverMessage` is this port's `message` option),
///   `model doesn't get confused with individual tracked ranges`,
///   `issue #16922`.
///
/// N-A cases (need `applyEdits` — the model is readonly, and the interval
/// tree's edit cluster is not ported, see `interval_tree.mbt`'s header):
/// - the ~17 `decorations are updated when inserting/deleting …` rows,
///   `decorations emit event when inserting one line text before it`,
///   `decorations are updated when changing EOL`, and `an apparently simple
///   edit`.
/// - the whole "Decorations and editing" suite (62 insert/delete/replace ×
///   collapsed × stickiness rows).
/// - `issue #41492` (collapseOnReplaceEdit through `applyEdits`).
/// - `removeAllDecorationsWithOwnerId can be called after model dispose`:
///   N-A — the readonly model has no dispose lifecycle.
///
/// Adaptation notes: Monaco `options.className: undefined` is this port's
/// `class_name: ""`; options are built through the single `ModelDecorationOptions`
/// constructor.

///|
/// Monaco `{ description: 'test', className }` options literal.
fn dec_options(class_name : String) -> ModelDecorationOptions {
  ModelDecorationOptions(class_name, description="test")
}

///|
fn create_text_model(text : String) -> TextModel {
  TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="model",
      path="/dec.mbt",
    ),
    "",
    "moonbit",
    1,
    "",
    text,
  )
}

///|
/// The suite's shared five-line model text.
fn create_this_model() -> TextModel {
  let text = "My First Line\r\n\t\tMy Second Line\n    Third Line\n\r\n1"
  create_text_model(text)
}

///|
/// `addDecoration`.
fn add_decoration(
  model : TextModel,
  start_line_number : Int32,
  start_column : Int32,
  end_line_number : Int32,
  end_column : Int32,
  class_name : String,
) -> String {
  model.change_decorations(accessor => {
    (accessor.add_decoration)(
      Range(start_line_number, start_column, end_line_number, end_column),
      dec_options(class_name),
    )
  })
}

///|
/// `lineHasDecorations`: (startColumn, endColumn, className) rows.
fn line_has_decorations(
  model : TextModel,
  line_number : Int32,
  decorations : Array[(Int32, Int32, String)],
) -> Unit raise {
  let actual = model
    .get_line_decorations(line_number)
    .map(d => (d.range.start_column, d.range.end_column, d.options.class_name))
  if actual != decorations {
    fail("Line decorations: got \{Repr(actual)}, expected \{Repr(decorations)}")
  }
}

///|
fn line_has_no_decorations(
  model : TextModel,
  line_number : Int32,
) -> Unit raise {
  line_has_decorations(model, line_number, [])
}

///|
fn line_has_decoration(
  model : TextModel,
  line_number : Int32,
  start : Int32,
  end : Int32,
  class_name : String,
) -> Unit raise {
  line_has_decorations(model, line_number, [(start, end, class_name)])
}

// #region suite "Editor Model - Model Decorations"

///|
test "single character decoration" {
  let this_model = create_this_model()
  let _ = add_decoration(this_model, 1, 1, 1, 2, "myType")
  line_has_decoration(this_model, 1, 1, 2, "myType")
  line_has_no_decorations(this_model, 2)
  line_has_no_decorations(this_model, 3)
  line_has_no_decorations(this_model, 4)
  line_has_no_decorations(this_model, 5)
}

///|
test "line decoration" {
  let this_model = create_this_model()
  let _ = add_decoration(this_model, 1, 1, 1, 14, "myType")
  line_has_decoration(this_model, 1, 1, 14, "myType")
  line_has_no_decorations(this_model, 2)
  line_has_no_decorations(this_model, 3)
  line_has_no_decorations(this_model, 4)
  line_has_no_decorations(this_model, 5)
}

///|
test "full line decoration" {
  let this_model = create_this_model()
  let _ = add_decoration(this_model, 1, 1, 2, 1, "myType")
  // Upstream queries getLineDecorations(1) twice (copy-paste); mirrored.
  let line1_decorations = this_model.get_line_decorations(1)
  assert_eq(line1_decorations.length(), 1)
  assert_eq(line1_decorations[0].options.class_name, "myType")
  let line2_decorations = this_model.get_line_decorations(1)
  assert_eq(line2_decorations.length(), 1)
  assert_eq(line2_decorations[0].options.class_name, "myType")
  line_has_no_decorations(this_model, 3)
  line_has_no_decorations(this_model, 4)
  line_has_no_decorations(this_model, 5)
}

///|
test "multiple line decoration" {
  let this_model = create_this_model()
  let _ = add_decoration(this_model, 1, 2, 3, 2, "myType")
  // Upstream queries getLineDecorations(1) for all three vars (copy-paste);
  // mirrored.
  let line1_decorations = this_model.get_line_decorations(1)
  assert_eq(line1_decorations.length(), 1)
  assert_eq(line1_decorations[0].options.class_name, "myType")
  let line2_decorations = this_model.get_line_decorations(1)
  assert_eq(line2_decorations.length(), 1)
  assert_eq(line2_decorations[0].options.class_name, "myType")
  let line3_decorations = this_model.get_line_decorations(1)
  assert_eq(line3_decorations.length(), 1)
  assert_eq(line3_decorations[0].options.class_name, "myType")
  line_has_no_decorations(this_model, 4)
  line_has_no_decorations(this_model, 5)
}

///|
test "decorations emit event on add" {
  let this_model = create_this_model()
  let listener_called = Ref(0)
  let disposable = this_model.on_did_change_decorations(_e => {
    listener_called.val += 1
  })
  let _ = add_decoration(this_model, 1, 2, 3, 2, "myType")
  assert_eq(listener_called.val, 1)
  disposable.dispose()
}

///|
test "decorations emit event on change" {
  let this_model = create_this_model()
  let listener_called = Ref(0)
  let dec_id = add_decoration(this_model, 1, 2, 3, 2, "myType")
  let disposable = this_model.on_did_change_decorations(_e => {
    listener_called.val += 1
  })
  this_model.change_decorations(accessor => {
    (accessor.change_decoration)(dec_id, Range(1, 1, 1, 2))
  })
  assert_eq(listener_called.val, 1)
  disposable.dispose()
}

///|
test "decorations emit event on remove" {
  let this_model = create_this_model()
  let listener_called = Ref(0)
  let dec_id = add_decoration(this_model, 1, 2, 3, 2, "myType")
  let disposable = this_model.on_did_change_decorations(_e => {
    listener_called.val += 1
  })
  this_model.change_decorations(accessor => (accessor.remove_decoration)(dec_id))
  assert_eq(listener_called.val, 1)
  disposable.dispose()
}

///|
test "decorations do not emit event on no-op deltaDecorations" {
  let this_model = create_this_model()
  let listener_called = Ref(0)
  let disposable = this_model.on_did_change_decorations(_e => {
    listener_called.val += 1
  })
  let _ = this_model.delta_decorations([], [])
  let _ = this_model.change_decorations(accessor => {
    (accessor.delta_decorations)([], [])
  })
  assert_eq(listener_called.val, 0)
  disposable.dispose()
}

///|
/// `ILightWeightDecoration`.
priv struct LightWeightDecoration {
  id : String
  range : @base_common.Range
}

///|
fn decoration(
  id : String,
  start_line_number : Int32,
  start_column : Int32,
  end_line_number : Int32,
  end_column : Int32,
) -> LightWeightDecoration {
  {
    id,
    range: Range(start_line_number, start_column, end_line_number, end_column),
  }
}

///|
fn to_model_delta_decoration(
  dec : LightWeightDecoration,
) -> ModelDeltaDecoration {
  { range: dec.range, options: dec_options(dec.id), }
}

///|
fn assert_reference_range_opt_eq(
  actual : @base_common.Range?,
  expected : @base_common.Range?,
) -> Unit raise {
  if actual != expected {
    fail("got \{Repr(actual)}, expected \{Repr(expected)}")
  }
}

///|
test "result respects input" {
  let model = create_text_model(["Hello world,", "How are you?"].join("\n"))
  let ids = model.delta_decorations([], [
    to_model_delta_decoration(decoration("a", 1, 1, 1, 12)),
    to_model_delta_decoration(decoration("b", 2, 1, 2, 13)),
  ])
  assert_reference_range_opt_eq(
    model.get_decoration_range(ids[0]),
    Some(Range(1, 1, 1, 12)),
  )
  assert_reference_range_opt_eq(
    model.get_decoration_range(ids[1]),
    Some(Range(2, 1, 2, 13)),
  )
}

///|
test "model doesn't get confused with individual tracked ranges" {
  let model = create_text_model(["Hello world,", "How are you?"].join("\n"))
  let tracked_range_id = model.change_decorations(accessor => {
    (accessor.add_decoration)(
      Range(1, 1, 1, 1),
      ModelDecorationOptions(
        "",
        stickiness=AlwaysGrowsWhenTypingAtEdges,
        description="test",
      ),
    )
  })
  model.change_decorations(accessor => {
    (accessor.remove_decoration)(tracked_range_id)
  })
  let ids = model.delta_decorations([], [
    to_model_delta_decoration(decoration("a", 1, 1, 1, 12)),
    to_model_delta_decoration(decoration("b", 2, 1, 2, 13)),
  ])
  assert_reference_range_opt_eq(
    model.get_decoration_range(ids[0]),
    Some(Range(1, 1, 1, 12)),
  )
  assert_reference_range_opt_eq(
    model.get_decoration_range(ids[1]),
    Some(Range(2, 1, 2, 13)),
  )
  let ids2 = model.delta_decorations(ids, [
    to_model_delta_decoration(decoration("a", 1, 1, 1, 12)),
    to_model_delta_decoration(decoration("b", 2, 1, 2, 13)),
  ])
  assert_reference_range_opt_eq(
    model.get_decoration_range(ids2[0]),
    Some(Range(1, 1, 1, 12)),
  )
  assert_reference_range_opt_eq(
    model.get_decoration_range(ids2[1]),
    Some(Range(2, 1, 2, 13)),
  )
}

///|
test "issue #16922: Clicking on link doesn't seem to do anything" {
  let model = create_text_model(
    ["Hello world,", "How are you?", "Fine.", "Good."].join("\n"),
  )
  let _ = model.delta_decorations([], [
    { range: Range(1, 1, 1, 1), options: dec_options("1"), },
    { range: Range(1, 13, 1, 13), options: dec_options("2"), },
    { range: Range(2, 1, 2, 1), options: dec_options("3"), },
    { range: Range(2, 1, 2, 4), options: dec_options("4"), },
    { range: Range(2, 8, 2, 13), options: dec_options("5"), },
    { range: Range(3, 1, 4, 6), options: dec_options("6"), },
    { range: Range(1, 1, 3, 6), options: dec_options("x1"), },
    { range: Range(2, 5, 2, 8), options: dec_options("x2"), },
    { range: Range(1, 1, 2, 8), options: dec_options("x3"), },
    { range: Range(2, 5, 3, 1), options: dec_options("x4"), },
  ])
  let in_range = model.get_decorations_in_range(Range(2, 6, 2, 6))
  let in_range_class_names = in_range.map(d => d.options.class_name)
  in_range_class_names.sort()
  if in_range_class_names != ["x1", "x2", "x3", "x4"] {
    fail("got \{Repr(in_range_class_names)}")
  }
}

// #endregion
