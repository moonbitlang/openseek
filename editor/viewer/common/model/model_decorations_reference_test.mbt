///| Faithful conformance port of vscode's `modelDecorations.test.ts` (pinned
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
fn dec_options(class_name : String) -> @model.ModelDecorationOptions {
  ModelDecorationOptions(class_name, description="test")
}

///|
fn create_text_model(text : String) -> @model.TextModel {
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
fn create_this_model() -> @model.TextModel {
  let text = "My First Line" +
    "\r\n" +
    "\t\tMy Second Line" +
    "\n" +
    "    Third Line" +
    "\n" +
    "" +
    "\r\n" +
    "1"
  create_text_model(text)
}

///|
/// `addDecoration`.
fn add_decoration(
  model : @model.TextModel,
  start_line_number : Int,
  start_column : Int,
  end_line_number : Int,
  end_column : Int,
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
/// `modelHasDecorations`: (range, className) rows sorted by range starts.
fn model_has_decorations(
  model : @model.TextModel,
  decorations : Array[(Int, Int, Int, Int, String)],
) -> Unit raise {
  let model_decorations = model
    .get_all_decorations()
    .map(d => (d.range, d.options.class_name))
  model_decorations.sort_by((a, b) => {
    @base_common.Range::compare_ranges_using_starts(a.0, b.0)
  })
  let actual = model_decorations.map(pair => {
    let (range, class_name) = pair
    (
      range.start_line_number,
      range.start_column,
      range.end_line_number,
      range.end_column,
      class_name,
    )
  })
  if actual != decorations {
    fail("got \{Repr(actual)}, expected \{Repr(decorations)}")
  }
}

///|
fn model_has_decoration(
  model : @model.TextModel,
  start_line_number : Int,
  start_column : Int,
  end_line_number : Int,
  end_column : Int,
  class_name : String,
) -> Unit raise {
  model_has_decorations(model, [
    (start_line_number, start_column, end_line_number, end_column, class_name),
  ])
}

///|
fn model_has_no_decorations(model : @model.TextModel) -> Unit raise {
  assert_eq(model.get_all_decorations().length(), 0)
}

///|
/// `lineHasDecorations`: (startColumn, endColumn, className) rows.
fn line_has_decorations(
  model : @model.TextModel,
  line_number : Int,
  decorations : Array[(Int, Int, String)],
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
  model : @model.TextModel,
  line_number : Int,
) -> Unit raise {
  line_has_decorations(model, line_number, [])
}

///|
fn line_has_decoration(
  model : @model.TextModel,
  line_number : Int,
  start : Int,
  end : Int,
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
test "decoration gets removed" {
  let this_model = create_this_model()
  let dec_id = add_decoration(this_model, 1, 2, 3, 2, "myType")
  model_has_decoration(this_model, 1, 2, 3, 2, "myType")
  this_model.change_decorations(accessor => (accessor.remove_decoration)(dec_id))
  model_has_no_decorations(this_model)
}

///|
test "decorations get removed" {
  let this_model = create_this_model()
  let dec_id1 = add_decoration(this_model, 1, 2, 3, 2, "myType1")
  let dec_id2 = add_decoration(this_model, 1, 2, 3, 1, "myType2")
  model_has_decorations(this_model, [
    (1, 2, 3, 1, "myType2"),
    (1, 2, 3, 2, "myType1"),
  ])
  this_model.change_decorations(accessor => {
    (accessor.remove_decoration)(dec_id1)
  })
  model_has_decorations(this_model, [(1, 2, 3, 1, "myType2")])
  this_model.change_decorations(accessor => {
    (accessor.remove_decoration)(dec_id2)
  })
  model_has_no_decorations(this_model)
}

///|
test "decoration range can be changed" {
  let this_model = create_this_model()
  let dec_id = add_decoration(this_model, 1, 2, 3, 2, "myType")
  model_has_decoration(this_model, 1, 2, 3, 2, "myType")
  this_model.change_decorations(accessor => {
    (accessor.change_decoration)(dec_id, Range(1, 1, 1, 2))
  })
  model_has_decoration(this_model, 1, 1, 1, 2, "myType")
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
test "removeAllDecorationsWithOwnerId works" {
  let this_model = create_this_model()
  let _ = this_model.delta_decorations(
    [],
    [{ range: Range(1, 2, 4, 1), options: dec_options("myType1") }],
    owner_id=1,
  )
  this_model.remove_all_decorations_with_owner_id(1)
  model_has_no_decorations(this_model)
}

// #endregion

// #region suite "deltaDecorations"

///|
/// `ILightWeightDecoration`.
priv struct LightWeightDecoration {
  id : String
  range : @base_common.Range
}

///|
fn decoration(
  id : String,
  start_line_number : Int,
  start_column : Int,
  end_line_number : Int,
  end_column : Int,
) -> LightWeightDecoration {
  {
    id,
    range: Range(start_line_number, start_column, end_line_number, end_column),
  }
}

///|
fn to_model_delta_decoration(
  dec : LightWeightDecoration,
) -> @model.ModelDeltaDecoration {
  { range: dec.range, options: dec_options(dec.id) }
}

///|
fn read_model_decorations(
  model : @model.TextModel,
  ids : Array[String],
) -> Array[(String, @base_common.Range)] {
  ids.map(id => {
    (
      model.get_decoration_options(id).unwrap().class_name,
      model.get_decoration_range(id).unwrap(),
    )
  })
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
fn assert_delta_rows_eq(
  actual : Array[(String, @base_common.Range)],
  expected : Array[(String, @base_common.Range)],
) -> Unit raise {
  if actual != expected {
    fail("got \{Repr(actual)}, expected \{Repr(expected)}")
  }
}

///|
/// `testDeltaDecorations`. The ids are single-character strings, so MoonBit's
/// length-first string compare matches JS strcmp here.
fn test_delta_decorations(
  text : Array[String],
  decorations : Array[LightWeightDecoration],
  new_decorations : Array[LightWeightDecoration],
) -> Unit raise {
  let model = create_text_model(text.join("\n"))

  // Add initial decorations & assert they are added
  let initial_ids = model.delta_decorations(
    [],
    decorations.map(to_model_delta_decoration),
  )
  let actual_decorations = read_model_decorations(model, initial_ids)
  assert_eq(initial_ids.length(), decorations.length())
  assert_eq(initial_ids.length(), model.get_all_decorations().length())
  actual_decorations.sort_by((a, b) => {
    if a.0 == b.0 {
      0
    } else if a.0 < b.0 {
      -1
    } else {
      1
    }
  })
  decorations.sort_by((a, b) => {
    if a.id == b.id {
      0
    } else if a.id < b.id {
      -1
    } else {
      1
    }
  })
  assert_delta_rows_eq(
    actual_decorations,
    decorations.map(d => (d.id, d.range)),
  )
  let new_ids = model.delta_decorations(
    initial_ids,
    new_decorations.map(to_model_delta_decoration),
  )
  assert_eq(new_ids.length(), new_decorations.length())
  assert_eq(new_ids.length(), model.get_all_decorations().length())
}

///|
test "result respects input" {
  let model = create_text_model(["Hello world,", "How are you?"].join("\n"))
  let ids = model.delta_decorations([], [
    to_model_delta_decoration(decoration("a", 1, 1, 1, 12)),
    to_model_delta_decoration(decoration("b", 2, 1, 2, 13)),
  ])
  assert_range_opt_eq(
    model.get_decoration_range(ids[0]),
    Some(Range(1, 1, 1, 12)),
  )
  assert_range_opt_eq(
    model.get_decoration_range(ids[1]),
    Some(Range(2, 1, 2, 13)),
  )
}

///|
test "deltaDecorations 1" {
  test_delta_decorations(
    [
      "This is a text", "That has multiple lines", "And is very friendly", "Towards testing",
    ],
    [
      decoration("a", 1, 1, 1, 2),
      decoration("b", 1, 1, 1, 15),
      decoration("c", 1, 1, 2, 1),
      decoration("d", 1, 1, 2, 24),
      decoration("e", 2, 1, 2, 24),
      decoration("f", 2, 1, 4, 16),
    ],
    [
      decoration("x", 1, 1, 1, 2),
      decoration("b", 1, 1, 1, 15),
      decoration("c", 1, 1, 2, 1),
      decoration("d", 1, 1, 2, 24),
      decoration("e", 2, 1, 2, 21),
      decoration("f", 2, 17, 4, 16),
    ],
  )
}

///|
test "deltaDecorations 2" {
  test_delta_decorations(
    [
      "This is a text", "That has multiple lines", "And is very friendly", "Towards testing",
    ],
    [
      decoration("a", 1, 1, 1, 2),
      decoration("b", 1, 2, 1, 3),
      decoration("c", 1, 3, 1, 4),
      decoration("d", 1, 4, 1, 5),
      decoration("e", 1, 5, 1, 6),
    ],
    [
      decoration("a", 1, 2, 1, 3),
      decoration("b", 1, 3, 1, 4),
      decoration("c", 1, 4, 1, 5),
      decoration("d", 1, 5, 1, 6),
    ],
  )
}

///|
test "deltaDecorations 3" {
  test_delta_decorations(
    [
      "This is a text", "That has multiple lines", "And is very friendly", "Towards testing",
    ],
    [
      decoration("a", 1, 1, 1, 2),
      decoration("b", 1, 2, 1, 3),
      decoration("c", 1, 3, 1, 4),
      decoration("d", 1, 4, 1, 5),
      decoration("e", 1, 5, 1, 6),
    ],
    [],
  )
}

///|
test "issue #4317: editor.setDecorations doesn't update the hover message" {
  let model = create_text_model("Hello world!")
  let ids = model.delta_decorations([], [
    {
      range: Range(1, 1, 100, 1),
      options: ModelDecorationOptions("", message="hello1", description="test"),
    },
  ])
  let ids2 = model.delta_decorations(ids, [
    {
      range: Range(1, 1, 100, 1),
      options: ModelDecorationOptions("", message="hello2", description="test"),
    },
  ])
  let actual_decoration = model.get_decoration_options(ids2[0])
  assert_true(actual_decoration.unwrap().message is Some("hello2"))
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
  assert_range_opt_eq(
    model.get_decoration_range(ids[0]),
    Some(Range(1, 1, 1, 12)),
  )
  assert_range_opt_eq(
    model.get_decoration_range(ids[1]),
    Some(Range(2, 1, 2, 13)),
  )
  let ids2 = model.delta_decorations(ids, [
    to_model_delta_decoration(decoration("a", 1, 1, 1, 12)),
    to_model_delta_decoration(decoration("b", 2, 1, 2, 13)),
  ])
  assert_range_opt_eq(
    model.get_decoration_range(ids2[0]),
    Some(Range(1, 1, 1, 12)),
  )
  assert_range_opt_eq(
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
    { range: Range(1, 1, 1, 1), options: dec_options("1") },
    { range: Range(1, 13, 1, 13), options: dec_options("2") },
    { range: Range(2, 1, 2, 1), options: dec_options("3") },
    { range: Range(2, 1, 2, 4), options: dec_options("4") },
    { range: Range(2, 8, 2, 13), options: dec_options("5") },
    { range: Range(3, 1, 4, 6), options: dec_options("6") },
    { range: Range(1, 1, 3, 6), options: dec_options("x1") },
    { range: Range(2, 5, 2, 8), options: dec_options("x2") },
    { range: Range(1, 1, 2, 8), options: dec_options("x3") },
    { range: Range(2, 5, 3, 1), options: dec_options("x4") },
  ])
  let in_range = model.get_decorations_in_range(Range(2, 6, 2, 6))
  let in_range_class_names = in_range.map(d => d.options.class_name)
  in_range_class_names.sort()
  if in_range_class_names != ["x1", "x2", "x3", "x4"] {
    fail("got \{Repr(in_range_class_names)}")
  }
}

// #endregion
