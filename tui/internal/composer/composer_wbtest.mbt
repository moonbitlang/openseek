///|
test "model starts at end and keeps cursor visible" {
  let model = Model::from_text("a\nb\nc")
  let point = model.cursor_point()
  inspect(point.line, content="2")
  inspect(point.grapheme_column, content="1")
  inspect(model.visible_text_rows(), content="3")
  inspect(model.cursor_row(), content="2")
  inspect(model.view_start, content="0")
}

///|
test "model up down moves cursor and visible line window" {
  let model = Model::from_text("one\ntwo\nthree")
  inspect(model.cursor_point().line, content="2")
  inspect(model.view_start, content="0")
  model.move_vertical(-1)
  inspect(model.cursor_point().line, content="1")
  inspect(model.cursor_point().grapheme_column, content="3")
  inspect(model.view_start, content="0")
  model.move_vertical(-1)
  inspect(model.cursor_point().line, content="0")
  inspect(model.cursor_point().grapheme_column, content="3")
  inspect(model.view_start, content="0")
  model.move_vertical(1)
  inspect(model.cursor_point().line, content="1")
  inspect(model.view_start, content="0")
  model.move_vertical(1)
  inspect(model.cursor_point().line, content="2")
  inspect(model.view_start, content="0")
}

///|
test "model scrolls visible window after max rows" {
  let model = Model::from_text("a\nb\nc\nd\ne")
  inspect(model.visible_text_rows(), content="4")
  inspect(model.cursor_row(), content="3")
  inspect(model.view_start, content="1")
  model.move_vertical(-3)
  inspect(model.cursor_point().line, content="1")
  inspect(model.view_start, content="1")
  model.move_vertical(-1)
  inspect(model.cursor_point().line, content="0")
  inspect(model.view_start, content="0")
}

///|
test "model inserts and deletes at cursor" {
  let inserted = Model::from_text("ab")
  inserted.move_left()
  inserted.insert("X")
  inspect(inserted.text, content="aXb")
  inspect(inserted.cursor, content="2")
  let deleted_before = Model::from_text("a👨‍👩‍👧‍👦b")
  deleted_before.move_left()
  deleted_before.delete_before()
  inspect(deleted_before.text, content="ab")
  inspect(deleted_before.cursor_point().grapheme_column, content="1")
  let deleted_after = Model::from_text("ab")
  deleted_after.move_home()
  deleted_after.delete_after()
  inspect(deleted_after.text, content="b")
  inspect(deleted_after.cursor, content="0")
}

///|
test "model shell mode keeps marker out of text" {
  let shell = Model::new()
  shell.insert_user_text("!echo hi")
  assert_true(shell.mode().is_shell())
  inspect(shell.text, content="echo hi")
  inspect(shell.cursor, content="7")
  let normal = Model::new()
  normal.insert_user_text("!")
  normal.delete_before()
  assert_true(normal.mode().is_input())
  inspect(normal.text, content="")
}

///|
test "model home end moves within logical line" {
  let model = Model::from_text("ab\ncd")
  model.move_home()
  inspect(model.cursor_point().line, content="1")
  inspect(model.cursor_point().grapheme_column, content="0")
  model.move_end()
  inspect(model.cursor_point().line, content="1")
  inspect(model.cursor_point().grapheme_column, content="2")
}

///|
test "model kills before and after cursor within logical line" {
  let before = Model::from_text("ab\ncd")
  before.kill_before()
  inspect(before.text, content="ab\n")
  inspect(before.cursor_point().line, content="1")
  inspect(before.cursor_point().grapheme_column, content="0")
  let after = Model::from_text("ab\ncd")
  after.move_home()
  after.kill_after()
  inspect(after.text, content="ab\n")
  inspect(after.cursor_point().line, content="1")
  inspect(after.cursor_point().grapheme_column, content="0")
}

///|
test "kill after removes empty lines and joins lines" {
  // On an empty middle line, kill-line removes the forward line break.
  let middle = Model::from_text("ab\n\ncd")
  middle.move_vertical(-1)
  inspect(middle.cursor_point().line, content="1")
  inspect(middle.cursor_point().grapheme_column, content="0")
  middle.kill_after()
  inspect(middle.text, content="ab\ncd")
  // At the end of a non-empty line it likewise joins the next line up.
  let joined = Model::from_text("ab\ncd")
  joined.move_vertical(-1)
  joined.move_end()
  joined.kill_after()
  inspect(joined.text, content="abcd")
  // A trailing empty line (e.g. from an extra Shift+Enter) has nothing forward,
  // so kill-line removes the empty line by deleting the preceding break.
  let trailing = Model::from_text("ab\n")
  inspect(trailing.cursor_point().line, content="1")
  trailing.kill_after()
  inspect(trailing.text, content="ab")
}

///|
test "model kill keeps shell mode active" {
  let shell = Model::new()
  shell.insert_user_text("!pwd")
  shell.kill_before()
  assert_true(shell.mode().is_shell())
  inspect(shell.text, content="")
}

///|
test "input prefix marks only the first logical input line" {
  inspect(Model::new().input_prefix(0), content="> ")
  let shell = Model::new()
  shell.insert_user_text("!")
  inspect(shell.input_prefix(0), content="! ")
  inspect(Model::new().input_prefix(1), content="  ")
  inspect(
    Model::from_text("a\nb\nc", max_text_rows=2).input_prefix(0),
    content="  ",
  )
}

///|
test "input cursor offset accounts for prompt and display width" {
  inspect(Model::new().cursor_offset(), content="2")
  inspect(Model::from_text("abc").cursor_offset(), content="5")
  inspect(Model::from_text("你好").cursor_offset(), content="6")
  let moved_left = Model::from_text("abc")
  moved_left.move_left()
  inspect(moved_left.cursor_offset(), content="4")
  inspect(Model::from_text("a\nb").cursor_offset(), content="3")
  // A long line wrapped to a content width of 3 puts the cursor at the end of
  // its second wrapped row: prompt (2) + display width of "def" (3).
  let narrow = Model::from_text("abcdef")
  narrow.resize(cols=5)
  inspect(narrow.cursor_offset(), content="5")
  let shell = Model::new()
  shell.insert_user_text("!abc")
  inspect(shell.cursor_offset(), content="5")
}

///|
test "long line soft-wraps across visible rows" {
  // cols 7 leaves a content width of 5, so "abcdefghij" wraps to two rows.
  let model = Model::from_text("abcdefghij")
  model.resize(cols=7)
  inspect(model.visible_text_rows(), content="2")
  inspect(model.visible_line(0), content="abcde")
  inspect(model.visible_line(1), content="fghij")
  // Only the first wrapped row keeps the prompt; the continuation is indented.
  inspect(model.input_prefix(0), content="> ")
  inspect(model.input_prefix(1), content="  ")
  // The cursor sits at the end of the second wrapped row.
  inspect(model.cursor_row(), content="1")
  inspect(model.cursor_offset(), content="7")
}

///|
test "soft-wrapped line scrolls when it exceeds max rows" {
  // cols 3 leaves a content width of 1, so "abcdef" wraps to six rows and the
  // four-row window scrolls to keep the trailing cursor visible.
  let model = Model::from_text("abcdef", max_text_rows=4)
  model.resize(cols=3)
  inspect(model.visible_text_rows(), content="4")
  inspect(model.cursor_row(), content="3")
  inspect(model.view_start, content="2")
  inspect(model.visible_line(0), content="c")
  inspect(model.visible_line(3), content="f")
}

///|
test "vertical movement steps through wrapped rows of one logical line" {
  // content width 5 splits "abcdefghij" into "abcde" / "fghij"; the cursor
  // starts at the end of the second wrapped row.
  let model = Model::from_text("abcdefghij")
  model.resize(cols=7)
  inspect(model.cursor_row(), content="1")
  // Up moves within the single logical line to the first wrapped row, landing on
  // the wrap boundary so it renders at the end of that row (offset 2 + 5).
  model.move_vertical(-1)
  inspect(model.cursor_row(), content="0")
  inspect(model.cursor_point().line, content="0")
  inspect(model.cursor_offset(), content="7")
  inspect(model.cursor_at_first_visual_row(), content="true")
  // Down returns to the end of the second wrapped row.
  model.move_vertical(1)
  inspect(model.cursor_row(), content="1")
  inspect(model.cursor_offset(), content="7")
}

///|
test "word motion steps across word boundaries" {
  let model = Model::from_text("foo bar.baz")
  model.move_home()
  inspect(model.cursor, content="0")
  model.move_word_right()
  inspect(model.cursor, content="3")
  model.move_word_right()
  inspect(model.cursor, content="7")
  model.move_word_right()
  inspect(model.cursor, content="11")
  model.move_word_right()
  inspect(model.cursor, content="11")
  model.move_word_left()
  inspect(model.cursor, content="8")
  model.move_word_left()
  inspect(model.cursor, content="4")
  model.move_word_left()
  inspect(model.cursor, content="0")
  model.move_word_left()
  inspect(model.cursor, content="0")
}

///|
test "word motion treats non-ascii runs as words" {
  let model = Model::from_text("你好 world")
  model.move_home()
  model.move_word_right()
  inspect(model.cursor, content="2")
  model.move_word_right()
  inspect(model.cursor, content="8")
}

///|
test "model replace restores text mode and cursor" {
  let shell = Model::new()
  shell.insert_user_text("!pwd")
  let model = Model::from_text("draft")
  model.replace(shell.text(), mode=shell.mode())
  inspect(model.text(), content="pwd")
  assert_true(model.mode().is_shell())
  inspect(model.cursor, content="3")
  inspect(model.input_prefix(0), content="! ")
}

///|
test "model reports cursor visual-row boundaries" {
  let model = Model::from_text("one\ntwo")
  assert_false(model.cursor_at_first_visual_row())
  assert_true(model.cursor_at_last_visual_row())
  model.move_home()
  assert_false(model.cursor_at_first_visual_row())
  assert_true(model.cursor_at_last_visual_row())
  model.move_vertical(-1)
  assert_true(model.cursor_at_first_visual_row())
  assert_false(model.cursor_at_last_visual_row())
}
