///| Faithful movement-state ports from
/// `vscode/src/vs/editor/test/browser/controller/cursor.test.ts` in the
/// checked-in vscode source.
///
/// This file owns the 48 movement-relevant labels in the approved 59-label
/// `cursor.test.ts` set: absolute MoveTo, LTR Left/Right, wrapped vertical
/// movement, and Home/End. The remaining 11 approved labels are root Viewer
/// event/pointer/source cases and live in `viewer/cursor_reference_wbtest.mbt`.
///
/// SKIPPED — the exact buffer cluster at lines 748-826:
/// `move to beginning of buffer`;
/// `move to beginning of buffer from within first line`;
/// `move to beginning of buffer from within another line`;
/// `move to beginning of buffer from within first line selection`;
/// `move to beginning of buffer from within another line selection`;
/// `move to end of buffer`;
/// `move to end of buffer from within last line`;
/// `move to end of buffer from within another line`;
/// `move to end of buffer from within last line selection`; and
/// `move to end of buffer from within another line selection`.
/// The bound Ctrl/Cmd+Home/End surface is approved D5.
///
/// SKIPPED — `grapheme breaking` (lines 939-976): the selected surrogate-pair
/// cases below are ported, while combining/variation-selector/Tamil grapheme
/// movement is outside the present cursor capability.
///
/// SKIPPED — `Double-click on punctuation should select the character, not
/// adjacent space` (lines 2491-2523): its token-aware `//` boundary requires
/// the approved D6 `cursorWordOperations.ts` dependency.
///
/// Editing, undo, typing, paste, composition, multicursor, and column-selection
/// suites are outside the readonly source cluster.

///|
let cursor_reference_text = "    \tMy First Line\t \n\tMy Second Line\n    Third Line\u{1F436}\n\n1"

///|
fn cursor_reference_model(text : String) -> @model.TextModel {
  TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="cursor-reference",
      path="/cursor-reference.mbt",
    ),
    "cursor-reference.mbt",
    "moonbit",
    73,
    "cursor-reference",
    text,
  )
}

///|
fn cursor_reference_view_model() -> ViewModel {
  ViewModel::with_options(
    cursor_reference_model(cursor_reference_text),
    ViewModelOptions(tab_size=4),
  )
}

///|
fn cursor_reference_wrapped_view_model(
  text : String,
  column : Int32,
) -> ViewModel {
  ViewModel::with_options(
    cursor_reference_model(text),
    ViewModelOptions::soft_wrap(column, tab_size=4, wrapping_indent=Indent),
  )
}

///|
fn cursor_reference_set_position(
  view_model : ViewModel,
  line_number : Int32,
  column : Int32,
) -> Unit {
  view_model.move_cursor_to(
    Position(line_number, column),
    false,
    source="test",
    reason=NotSet,
  )
  |> ignore
}

///|
fn cursor_reference_move_left(
  view_model : ViewModel,
  select~ : Bool = false,
  value~ : Int32 = 1,
) -> Unit {
  view_model.move_cursor(
    Left,
    select,
    value~,
    unit=None,
    source="test",
    reason=Explicit,
  )
  |> ignore
}

///|
fn cursor_reference_move_right(
  view_model : ViewModel,
  select~ : Bool = false,
  value~ : Int32 = 1,
) -> Unit {
  view_model.move_cursor(
    Right,
    select,
    value~,
    unit=None,
    source="test",
    reason=Explicit,
  )
  |> ignore
}

///|
fn cursor_reference_move_up(
  view_model : ViewModel,
  select~ : Bool = false,
  value~ : Int32 = 1,
) -> Unit {
  view_model.move_cursor(
    Up,
    select,
    value~,
    unit=WrappedLine,
    source="test",
    reason=Explicit,
  )
  |> ignore
}

///|
fn cursor_reference_move_down(
  view_model : ViewModel,
  select~ : Bool = false,
  value~ : Int32 = 1,
) -> Unit {
  view_model.move_cursor(
    Down,
    select,
    value~,
    unit=WrappedLine,
    source="test",
    reason=Explicit,
  )
  |> ignore
}

///|
fn cursor_reference_home(
  view_model : ViewModel,
  select~ : Bool = false,
) -> Unit {
  view_model.move_cursor_to_line_start(select, source="test", reason=Explicit)
  |> ignore
}

///|
fn cursor_reference_end(view_model : ViewModel, select~ : Bool = false) -> Unit {
  view_model.move_cursor_to_line_end(select, source="test", reason=Explicit)
  |> ignore
}

///|
fn cursor_reference_assert_cursor(
  view_model : ViewModel,
  selection_line : Int32,
  selection_column : Int32,
  position_line : Int32,
  position_column : Int32,
) -> Unit raise {
  let selection = view_model.cursor.get_model_selection()
  let start = selection.get_selection_start()
  let position = selection.get_position()
  assert_eq(start.line_number, selection_line)
  assert_eq(start.column, selection_column)
  assert_eq(position.line_number, position_line)
  assert_eq(position.column, position_column)
  let view_selection = view_model.cursor.get_view_selection()
  let view_start = view_selection.get_selection_start()
  let view_position = view_selection.get_position()
  assert_eq(view_start.line_number, selection_line)
  assert_eq(view_start.column, selection_column)
  assert_eq(view_position.line_number, position_line)
  assert_eq(view_position.column, position_column)
}

///|
fn cursor_reference_assert_position(
  view_model : ViewModel,
  line_number : Int32,
  column : Int32,
) -> Unit raise {
  cursor_reference_assert_cursor(
    view_model, line_number, column, line_number, column,
  )
}

///|
fn cursor_reference_assert_view_position(
  view_model : ViewModel,
  line_number : Int32,
  column : Int32,
) -> Unit raise {
  let position = view_model.cursor.get_view_selection().get_position()
  assert_eq(position.line_number, line_number)
  assert_eq(position.column, column)
}

///|
test "cursor initialized" {
  cursor_reference_assert_position(cursor_reference_view_model(), 1, 1)
}

///|
test "no move" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 1, 1)
  cursor_reference_assert_position(view_model, 1, 1)
}

///|
test "move" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 1, 2)
  cursor_reference_assert_position(view_model, 1, 2)
}

///|
test "move in selection mode" {
  let view_model = cursor_reference_view_model()
  view_model.move_cursor_to(
    Position(1, 2),
    true,
    source="test",
    reason=Explicit,
  )
  |> ignore
  cursor_reference_assert_cursor(view_model, 1, 1, 1, 2)
}

///|
test "move beyond line end" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 1, 25)
  cursor_reference_assert_position(view_model, 1, 21)
}

///|
test "move empty line" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 4, 20)
  cursor_reference_assert_position(view_model, 4, 1)
}

///|
test "move one char line" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 5, 20)
  cursor_reference_assert_position(view_model, 5, 2)
}

///|
test "selection down" {
  let view_model = cursor_reference_view_model()
  view_model.move_cursor_to(
    Position(2, 1),
    true,
    source="test",
    reason=Explicit,
  )
  |> ignore
  cursor_reference_assert_cursor(view_model, 1, 1, 2, 1)
}

///|
test "move and then select" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 2, 3)
  view_model.move_cursor_to(
    Position(2, 15),
    true,
    source="test",
    reason=Explicit,
  )
  |> ignore
  cursor_reference_assert_cursor(view_model, 2, 3, 2, 15)
  view_model.move_cursor_to(
    Position(1, 2),
    true,
    source="test",
    reason=Explicit,
  )
  |> ignore
  cursor_reference_assert_cursor(view_model, 2, 3, 1, 2)
}

///|
test "move left on top left position" {
  let view_model = cursor_reference_view_model()
  cursor_reference_move_left(view_model)
  cursor_reference_assert_position(view_model, 1, 1)
}

///|
test "move left" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 1, 3)
  cursor_reference_move_left(view_model)
  cursor_reference_assert_position(view_model, 1, 2)
}

///|
test "move left with surrogate pair" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 3, 17)
  cursor_reference_move_left(view_model)
  cursor_reference_assert_position(view_model, 3, 15)
}

///|
test "move left goes to previous row" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 2, 1)
  cursor_reference_move_left(view_model)
  cursor_reference_assert_position(view_model, 1, 21)
}

///|
test "move left selection" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 2, 1)
  cursor_reference_move_left(view_model, select=true)
  cursor_reference_assert_cursor(view_model, 2, 1, 1, 21)
}

///|
test "move right on bottom right position" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 5, 2)
  cursor_reference_move_right(view_model)
  cursor_reference_assert_position(view_model, 5, 2)
}

///|
test "move right" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 1, 3)
  cursor_reference_move_right(view_model)
  cursor_reference_assert_position(view_model, 1, 4)
}

///|
test "move right with surrogate pair" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 3, 15)
  cursor_reference_move_right(view_model)
  cursor_reference_assert_position(view_model, 3, 17)
}

///|
test "move right goes to next row" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 1, 21)
  cursor_reference_move_right(view_model)
  cursor_reference_assert_position(view_model, 2, 1)
}

///|
test "move right selection" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 1, 21)
  cursor_reference_move_right(view_model, select=true)
  cursor_reference_assert_cursor(view_model, 1, 21, 2, 1)
}

///|
test "move down" {
  let view_model = cursor_reference_view_model()
  cursor_reference_move_down(view_model)
  cursor_reference_assert_position(view_model, 2, 1)
  cursor_reference_move_down(view_model)
  cursor_reference_assert_position(view_model, 3, 1)
  cursor_reference_move_down(view_model)
  cursor_reference_assert_position(view_model, 4, 1)
  cursor_reference_move_down(view_model)
  cursor_reference_assert_position(view_model, 5, 1)
  cursor_reference_move_down(view_model)
  cursor_reference_assert_position(view_model, 5, 2)
}

///|
test "move down with selection" {
  let view_model = cursor_reference_view_model()
  cursor_reference_move_down(view_model, select=true)
  cursor_reference_assert_cursor(view_model, 1, 1, 2, 1)
  cursor_reference_move_down(view_model, select=true)
  cursor_reference_assert_cursor(view_model, 1, 1, 3, 1)
  cursor_reference_move_down(view_model, select=true)
  cursor_reference_assert_cursor(view_model, 1, 1, 4, 1)
  cursor_reference_move_down(view_model, select=true)
  cursor_reference_assert_cursor(view_model, 1, 1, 5, 1)
  cursor_reference_move_down(view_model, select=true)
  cursor_reference_assert_cursor(view_model, 1, 1, 5, 2)
}

///|
test "move down with tabs" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 1, 5)
  cursor_reference_move_down(view_model)
  cursor_reference_assert_position(view_model, 2, 2)
  cursor_reference_move_down(view_model)
  cursor_reference_assert_position(view_model, 3, 5)
  cursor_reference_move_down(view_model)
  cursor_reference_assert_position(view_model, 4, 1)
  cursor_reference_move_down(view_model)
  cursor_reference_assert_position(view_model, 5, 2)
}

///|
test "move up" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 3, 5)
  cursor_reference_move_up(view_model)
  cursor_reference_assert_position(view_model, 2, 2)
  cursor_reference_move_up(view_model)
  cursor_reference_assert_position(view_model, 1, 5)
}

///|
test "move up with selection" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 3, 5)
  cursor_reference_move_up(view_model, select=true)
  cursor_reference_assert_cursor(view_model, 3, 5, 2, 2)
  cursor_reference_move_up(view_model, select=true)
  cursor_reference_assert_cursor(view_model, 3, 5, 1, 5)
}

///|
test "move up and down with tabs" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 1, 5)
  for _ in 0..<4 {
    cursor_reference_move_down(view_model)
  }
  cursor_reference_assert_position(view_model, 5, 2)
  cursor_reference_move_up(view_model)
  cursor_reference_assert_position(view_model, 4, 1)
  cursor_reference_move_up(view_model)
  cursor_reference_assert_position(view_model, 3, 5)
  cursor_reference_move_up(view_model)
  cursor_reference_assert_position(view_model, 2, 2)
  cursor_reference_move_up(view_model)
  cursor_reference_assert_position(view_model, 1, 5)
}

///|
test "move up and down with end of lines starting from a long one" {
  let view_model = cursor_reference_view_model()
  cursor_reference_end(view_model)
  cursor_reference_assert_position(view_model, 1, 21)
  cursor_reference_end(view_model)
  cursor_reference_move_down(view_model)
  cursor_reference_assert_position(view_model, 2, 16)
  cursor_reference_move_down(view_model)
  cursor_reference_assert_position(view_model, 3, 17)
  cursor_reference_move_down(view_model)
  cursor_reference_assert_position(view_model, 4, 1)
  cursor_reference_move_down(view_model)
  cursor_reference_assert_position(view_model, 5, 2)
  for _ in 0..<4 {
    cursor_reference_move_up(view_model)
  }
  cursor_reference_assert_position(view_model, 1, 21)
}

///|
test "issue #44465: cursor position not correct when move" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 1, 5)
  cursor_reference_move_up(view_model)
  cursor_reference_assert_position(view_model, 1, 1)
  cursor_reference_move_down(view_model)
  cursor_reference_assert_position(view_model, 2, 2)
  cursor_reference_move_up(view_model)
  cursor_reference_assert_position(view_model, 1, 5)
  cursor_reference_move_up(view_model)
  cursor_reference_assert_position(view_model, 1, 1)
  cursor_reference_move_up(view_model)
  cursor_reference_assert_position(view_model, 1, 1)
  cursor_reference_move_down(view_model)
  cursor_reference_assert_position(view_model, 2, 1)
}

///|
test "issue #144041: Cursor up/down works" {
  let view_model = cursor_reference_wrapped_view_model(
    "Word1 Word2 Word3 Word4\nWord5 Word6 Word7 Word8", 20,
  )
  cursor_reference_assert_view_position(view_model, 1, 1)
  cursor_reference_move_down(view_model)
  cursor_reference_assert_view_position(view_model, 2, 5)
  cursor_reference_move_down(view_model)
  cursor_reference_assert_view_position(view_model, 3, 1)
  cursor_reference_move_down(view_model)
  cursor_reference_assert_view_position(view_model, 4, 5)
  cursor_reference_move_down(view_model)
  cursor_reference_assert_view_position(view_model, 4, 10)
  cursor_reference_move_up(view_model)
  cursor_reference_assert_view_position(view_model, 3, 1)
  cursor_reference_move_up(view_model)
  cursor_reference_assert_view_position(view_model, 2, 5)
  cursor_reference_move_up(view_model)
  cursor_reference_assert_view_position(view_model, 1, 1)
  cursor_reference_move_up(view_model)
  cursor_reference_assert_view_position(view_model, 1, 1)
}

///|
test "issue #140195: Cursor up/down makes progress" {
  let model = cursor_reference_model(
    "Word1 Word2 Word3 Word4\nWord5 Word6 Word7 Word8",
  )
  model.delta_decorations([], [
    {
      range: Range(1, 22, 1, 22),
      options: ModelDecorationOptions(
        "",
        description="test",
        show_if_collapsed=true,
        after=InjectedTextOptions(
          "some very very very very very very very very long text",
        ),
      ),
    },
  ])
  |> ignore
  let view_model = ViewModel::with_options(
    model,
    ViewModelOptions::soft_wrap(20, tab_size=4, wrapping_indent=Indent),
  )
  cursor_reference_assert_view_position(view_model, 1, 1)
  cursor_reference_move_down(view_model)
  cursor_reference_assert_view_position(view_model, 2, 5)
  cursor_reference_move_down(view_model)
  cursor_reference_assert_view_position(view_model, 5, 19)
  cursor_reference_move_down(view_model)
  cursor_reference_assert_view_position(view_model, 6, 1)
  cursor_reference_move_down(view_model)
  cursor_reference_assert_view_position(view_model, 7, 5)
  cursor_reference_move_up(view_model)
  cursor_reference_assert_view_position(view_model, 6, 1)
  cursor_reference_move_up(view_model)
  cursor_reference_assert_view_position(view_model, 2, 8)
  cursor_reference_move_up(view_model)
  cursor_reference_assert_view_position(view_model, 1, 1)
  cursor_reference_move_up(view_model)
  cursor_reference_assert_view_position(view_model, 1, 1)
}

///|
test "move to beginning of line" {
  let view_model = cursor_reference_view_model()
  cursor_reference_home(view_model)
  cursor_reference_assert_position(view_model, 1, 6)
  cursor_reference_home(view_model)
  cursor_reference_assert_position(view_model, 1, 1)
}

///|
test "move to beginning of line from within line" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 1, 8)
  cursor_reference_home(view_model)
  cursor_reference_assert_position(view_model, 1, 6)
  cursor_reference_home(view_model)
  cursor_reference_assert_position(view_model, 1, 1)
}

///|
test "move to beginning of line from whitespace at beginning of line" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 1, 2)
  cursor_reference_home(view_model)
  cursor_reference_assert_position(view_model, 1, 6)
  cursor_reference_home(view_model)
  cursor_reference_assert_position(view_model, 1, 1)
}

///|
test "move to beginning of line from within line selection" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 1, 8)
  cursor_reference_home(view_model, select=true)
  cursor_reference_assert_cursor(view_model, 1, 8, 1, 6)
  cursor_reference_home(view_model, select=true)
  cursor_reference_assert_cursor(view_model, 1, 8, 1, 1)
}

///|
test "move to beginning of line with selection multiline forward" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 1, 8)
  view_model.move_cursor_to(Position(3, 9), true) |> ignore
  cursor_reference_home(view_model)
  cursor_reference_assert_position(view_model, 3, 5)
}

///|
test "move to beginning of line with selection multiline backward" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 3, 9)
  view_model.move_cursor_to(Position(1, 8), true) |> ignore
  cursor_reference_home(view_model)
  cursor_reference_assert_position(view_model, 1, 6)
}

///|
test "move to beginning of line with selection single line forward" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 3, 2)
  view_model.move_cursor_to(Position(3, 9), true) |> ignore
  cursor_reference_home(view_model)
  cursor_reference_assert_position(view_model, 3, 5)
}

///|
test "move to beginning of line with selection single line backward" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 3, 9)
  view_model.move_cursor_to(Position(3, 2), true) |> ignore
  cursor_reference_home(view_model)
  cursor_reference_assert_position(view_model, 3, 5)
}

///|
test "issue #15401: \"End\" key is behaving weird when text is selected part 1" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 1, 8)
  view_model.move_cursor_to(Position(3, 9), true) |> ignore
  cursor_reference_home(view_model)
  cursor_reference_assert_position(view_model, 3, 5)
}

///|
test "issue #17011: Shift+home/end now go to the end of the selection start's line, not the selection's end" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 1, 8)
  view_model.move_cursor_to(Position(3, 9), true) |> ignore
  cursor_reference_home(view_model, select=true)
  cursor_reference_assert_cursor(view_model, 1, 8, 3, 5)
}

///|
test "move to end of line" {
  let view_model = cursor_reference_view_model()
  cursor_reference_end(view_model)
  cursor_reference_assert_position(view_model, 1, 21)
  cursor_reference_end(view_model)
  cursor_reference_assert_position(view_model, 1, 21)
}

///|
test "move to end of line from within line" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 1, 6)
  cursor_reference_end(view_model)
  cursor_reference_assert_position(view_model, 1, 21)
  cursor_reference_end(view_model)
  cursor_reference_assert_position(view_model, 1, 21)
}

///|
test "move to end of line from whitespace at end of line" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 1, 20)
  cursor_reference_end(view_model)
  cursor_reference_assert_position(view_model, 1, 21)
  cursor_reference_end(view_model)
  cursor_reference_assert_position(view_model, 1, 21)
}

///|
test "move to end of line from within line selection" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 1, 6)
  cursor_reference_end(view_model, select=true)
  cursor_reference_assert_cursor(view_model, 1, 6, 1, 21)
  cursor_reference_end(view_model, select=true)
  cursor_reference_assert_cursor(view_model, 1, 6, 1, 21)
}

///|
test "move to end of line with selection multiline forward" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 1, 1)
  view_model.move_cursor_to(Position(3, 9), true) |> ignore
  cursor_reference_end(view_model)
  cursor_reference_assert_position(view_model, 3, 17)
}

///|
test "move to end of line with selection multiline backward" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 3, 9)
  view_model.move_cursor_to(Position(1, 1), true) |> ignore
  cursor_reference_end(view_model)
  cursor_reference_assert_position(view_model, 1, 21)
}

///|
test "move to end of line with selection single line forward" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 3, 1)
  view_model.move_cursor_to(Position(3, 9), true) |> ignore
  cursor_reference_end(view_model)
  cursor_reference_assert_position(view_model, 3, 17)
}

///|
test "move to end of line with selection single line backward" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 3, 9)
  view_model.move_cursor_to(Position(3, 1), true) |> ignore
  cursor_reference_end(view_model)
  cursor_reference_assert_position(view_model, 3, 17)
}

///|
test "issue #15401: \"End\" key is behaving weird when text is selected part 2" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 1, 1)
  view_model.move_cursor_to(Position(3, 9), true) |> ignore
  cursor_reference_end(view_model)
  cursor_reference_assert_position(view_model, 3, 17)
}
