///|
fn cursor_line_prefix(model : Model) -> String {
  let point = model.cursor
  let line = model.logical_lines[point.line]
  line.display.view(line.display.start(), point.position).to_owned()
}

///|
fn cursor_column(model : Model) -> Int {
  let point = model.cursor
  model.logical_lines[point.line].display_column(position=point.position)
}

///|
fn display_text_string(line : @displaytext.DisplayText) -> String {
  line.text()
}

///|
fn visible_row_text(model : Model, row : Int) -> String {
  if model.visible_line(row) is Some(line) {
    display_text_string(line)
  } else {
    ""
  }
}

///|
test "model starts at end and keeps cursor visible" {
  let model = Model::new("a\nb\nc")
  let point = model.cursor
  inspect(point.line, content="2")
  inspect(cursor_column(model), content="1")
  inspect(model.visible_text_rows(), content="3")
  inspect(model.cursor_row(), content="2")
  inspect(model.view_start, content="0")
}

///|
test "model up down moves cursor and visible line window" {
  let model = Model::new("one\ntwo\nthree")
  inspect(model.cursor.line, content="2")
  inspect(model.view_start, content="0")
  model.move_vertical(-1)
  inspect(model.cursor.line, content="1")
  inspect(cursor_column(model), content="3")
  inspect(model.view_start, content="0")
  model.move_vertical(-1)
  inspect(model.cursor.line, content="0")
  inspect(cursor_column(model), content="3")
  inspect(model.view_start, content="0")
  model.move_vertical(1)
  inspect(model.cursor.line, content="1")
  inspect(model.view_start, content="0")
  model.move_vertical(1)
  inspect(model.cursor.line, content="2")
  inspect(model.view_start, content="0")
}

///|
test "model scrolls visible window after max rows" {
  let model = Model::new("a\nb\nc\nd\ne")
  inspect(model.visible_text_rows(), content="4")
  inspect(model.cursor_row(), content="3")
  inspect(model.view_start, content="1")
  model.move_vertical(-3)
  inspect(model.cursor.line, content="1")
  inspect(model.view_start, content="1")
  model.move_vertical(-1)
  inspect(model.cursor.line, content="0")
  inspect(model.view_start, content="0")
}

///|
test "model inserts and deletes at cursor" {
  let inserted = Model::new("ab")
  inserted.move_left()
  inserted.insert("X")
  inspect(inserted.text, content="aXb")
  inspect(cursor_line_prefix(inserted), content="aX")
  let deleted_before = Model::new("a👨‍👩‍👧‍👦b")
  deleted_before.move_left()
  deleted_before.delete_before()
  inspect(deleted_before.text, content="ab")
  inspect(cursor_line_prefix(deleted_before), content="a")
  let deleted_after = Model::new("ab")
  deleted_after.move_home()
  deleted_after.delete_after()
  inspect(deleted_after.text, content="b")
  inspect(cursor_line_prefix(deleted_after), content="")
}

///|
test "model home end moves within logical line" {
  let model = Model::new("ab\ncd")
  model.move_home()
  inspect(model.cursor.line, content="1")
  inspect(cursor_column(model), content="0")
  model.move_end()
  inspect(model.cursor.line, content="1")
  inspect(cursor_column(model), content="2")
}

///|
test "model kills before and after cursor within logical line" {
  let before = Model::new("ab\ncd")
  before.kill_before()
  inspect(before.text, content="ab\n")
  inspect(before.cursor.line, content="1")
  inspect(cursor_column(before), content="0")
  let after = Model::new("ab\ncd")
  after.move_home()
  after.kill_after()
  inspect(after.text, content="ab\n")
  inspect(after.cursor.line, content="1")
  inspect(cursor_column(after), content="0")
}

///|
test "kill after removes empty lines and joins lines" {
  // On an empty middle line, kill-line removes the forward line break.
  let middle = Model::new("ab\n\ncd")
  middle.move_vertical(-1)
  inspect(middle.cursor.line, content="1")
  inspect(cursor_column(middle), content="0")
  middle.kill_after()
  inspect(middle.text, content="ab\ncd")
  // At the end of a non-empty line it likewise joins the next line up.
  let joined = Model::new("ab\ncd")
  joined.move_vertical(-1)
  joined.move_end()
  joined.kill_after()
  inspect(joined.text, content="abcd")
  // A trailing empty line (e.g. from an extra Shift+Enter) has nothing forward,
  // so kill-line removes the empty line by deleting the preceding break.
  let trailing = Model::new("ab\n")
  inspect(trailing.cursor.line, content="1")
  trailing.kill_after()
  inspect(trailing.text, content="ab")
}

///|
test "soft-wrapped line scrolls when it exceeds max rows" {
  // cols 3 leaves a content width of 1, so "abcdef" wraps to six rows and the
  // four-row window scrolls to keep the trailing cursor visible.
  let model = Model::new("abcdef", max_text_rows=4)
  model.resize(cols=3)
  inspect(model.visible_text_rows(), content="4")
  inspect(model.cursor_row(), content="3")
  inspect(model.view_start, content="2")
  inspect(visible_row_text(model, 0), content="c")
  inspect(visible_row_text(model, 3), content="f")
}

///|
test "vertical movement steps through wrapped rows of one logical line" {
  // content width 5 splits "abcdefghij" into "abcde" / "fghij"; the cursor
  // starts at the end of the second wrapped row.
  let model = Model::new("abcdefghij")
  model.resize(cols=7)
  inspect(model.cursor_row(), content="1")
  // Up moves within the single logical line to the first wrapped row, landing on
  // the wrap boundary so it renders at the end of that row (offset 2 + 5).
  model.move_vertical(-1)
  inspect(model.cursor_row(), content="0")
  inspect(model.cursor.line, content="0")
  inspect(model.cursor_offset(), content="7")
  inspect(model.cursor_at_first_visual_row(), content="true")
  // Down returns to the end of the second wrapped row.
  model.move_vertical(1)
  inspect(model.cursor_row(), content="1")
  inspect(model.cursor_offset(), content="7")
}

///|
test "word motion steps across word boundaries" {
  let model = Model::new("foo bar.baz")
  model.move_home()
  inspect(cursor_line_prefix(model), content="")
  model.move_word_right()
  inspect(cursor_line_prefix(model), content="foo")
  model.move_word_right()
  inspect(cursor_line_prefix(model), content="foo bar")
  model.move_word_right()
  inspect(cursor_line_prefix(model), content="foo bar.baz")
  model.move_word_right()
  inspect(cursor_line_prefix(model), content="foo bar.baz")
  model.move_word_left()
  inspect(cursor_line_prefix(model), content="foo bar.")
  model.move_word_left()
  inspect(cursor_line_prefix(model), content="foo ")
  model.move_word_left()
  inspect(cursor_line_prefix(model), content="")
  model.move_word_left()
  inspect(cursor_line_prefix(model), content="")
}

///|
test "word motion treats non-ascii runs as words" {
  let model = Model::new("你好 world")
  model.move_home()
  model.move_word_right()
  inspect(cursor_line_prefix(model), content="你好")
  model.move_word_right()
  inspect(cursor_line_prefix(model), content="你好 world")
}
