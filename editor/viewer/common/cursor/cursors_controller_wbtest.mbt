///|
priv struct CursorTestConverter {
  column_delta : Int32
  range_delta : Int32
}

///|
fn CursorTestConverter::model_position_to_view_position(
  self : CursorTestConverter,
  position : @base_common.Position,
) -> @base_common.Position {
  Position(position.line_number, position.column + self.column_delta)
}

///|
fn CursorTestConverter::view_position_to_model_position(
  self : CursorTestConverter,
  position : @base_common.Position,
) -> @base_common.Position {
  Position(position.line_number, position.column - self.column_delta)
}

///|
fn CursorTestConverter::view_range_to_model_range(
  self : CursorTestConverter,
  range : @base_common.Range,
) -> @base_common.Range {
  Range(
    range.start_line_number,
    range.start_column - self.range_delta,
    range.end_line_number,
    range.end_column - self.range_delta,
  )
}

///|
fn CursorTestConverter::context(self : CursorTestConverter) -> CursorContext {
  CursorContext(
    view_to_model=position => self.view_position_to_model_position(position),
    view_range_to_model=range => self.view_range_to_model_range(range),
    model_to_view=position => self.model_position_to_view_position(position),
  )
}

///|
fn cursor_controller_test_model(text~ : String = "abc") -> @model.TextModel {
  TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="cursor-controller",
      path="/model.mbt",
    ),
    "cursor-controller",
    "plaintext",
    1,
    "",
    text,
  )
}

///|
test "partial cursor-state constructors retain exact present and absent sides" {
  let model_state = SingleCursorState(
    Position(1, 2),
    Position(1, 2),
    Simple,
    Position(1, 3),
  )
  let view_state = SingleCursorState(
    Position(1, 3),
    Position(1, 3),
    Simple,
    Position(1, 4),
  )
  let model_only = PartialModelCursorState(model_state)
  assert_true(model_only.model_state == model_state)
  assert_true(model_only.view_state is None)
  let view_only = PartialViewCursorState(view_state)
  assert_true(view_only.model_state is None)
  assert_true(view_only.view_state == view_state)

  let full = FullCursorState(CursorState(model_state, view_state))
  assert_true(full.model_state() == Some(model_state))
  assert_true(full.view_state() == Some(view_state))
  let from_model = CursorState::from_model_state(model_state)
  assert_true(from_model.model_state() == Some(model_state))
  assert_true(from_model.view_state() is None)
  let from_view = CursorState::from_view_state(view_state)
  assert_true(from_view.model_state() is None)
  assert_true(from_view.view_state() == Some(view_state))
}

///|
test "model selections become collapsed Simple anchors in source order" {
  let first = @core.Selection(Position(1, 3), Position(1, 1))
  let second = @core.Selection(Position(1, 1), Position(1, 2))
  let states = CursorState::from_model_selections([first, second])
  assert_eq(states.length(), 2)
  guard states[0].model_state() is Some(first_state) else {
    fail("first model state must be present")
  }
  guard states[1].model_state() is Some(second_state) else {
    fail("second model state must be present")
  }
  assert_true(first_state.selection_start_start == Position(1, 3))
  assert_true(first_state.selection_start_end == Position(1, 3))
  assert_true(first_state.selection_start_kind == Simple)
  assert_true(first_state.position == Position(1, 1))
  assert_eq(first_state.selection_start_leftover_visible_columns, 0)
  assert_eq(first_state.leftover_visible_columns, 0)
  assert_true(second_state.selection_start_start == Position(1, 1))
  assert_true(second_state.position == Position(1, 2))
}

///|
test "central partial transition covers null model view and full shapes" {
  let model = cursor_controller_test_model()
  let converter = CursorTestConverter::{ column_delta: 1, range_delta: 1, }
  let raw_cursor = Cursor()
  let raw_before = raw_cursor.as_cursor_state()
  assert_false(raw_cursor.set_state(converter.context(), None, None))
  assert_true(raw_cursor.as_cursor_state() == raw_before)
  let controller = CursorsController(model, converter.context())

  assert_true(controller.set_cursor_state(None) is None)
  assert_true(controller.model_state().position == Position(1, 1))
  assert_true(controller.view_state().position == Position(1, 1))

  let model_state = SingleCursorState::collapsed(Position(1, 2))
  assert_true(
    controller.set_cursor_state(
      Some(CursorState::from_model_state(model_state)),
    )
    is Some(_),
  )
  assert_true(controller.model_state().position == Position(1, 2))
  assert_true(controller.view_state().position == Position(1, 3))

  let view_state = SingleCursorState(
    Position(1, 4),
    Position(1, 4),
    Simple,
    Position(1, 4),
    selection_start_leftover_visible_columns=5,
    leftover_visible_columns=7,
  )
  assert_true(
    controller.set_cursor_state(Some(CursorState::from_view_state(view_state)))
    is Some(_),
  )
  assert_true(controller.model_state().position == Position(1, 3))
  assert_true(controller.view_state().position == Position(1, 4))
  assert_eq(controller.model_state().leftover_visible_columns, 7)

  // The approved ONE-028 reduction makes the full-state path model
  // authoritative instead of accepting an inconsistent supplied view side.
  let inconsistent_view = SingleCursorState::collapsed(Position(1, 99))
  assert_true(
    controller.set_cursor_state(
      Some(FullCursorState(CursorState(model_state, inconsistent_view))),
    )
    is Some(_),
  )
  assert_true(controller.model_state().position == Position(1, 2))
  assert_true(controller.view_state().position == Position(1, 3))
}
