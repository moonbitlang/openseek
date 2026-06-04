///|
fn display_text_string(line : @displaytext.DisplayText) -> String {
  line.text()
}

///|
fn visible_row_text(model : @composer.Model, row : Int) -> String {
  if model.visible_line(row) is Some(line) {
    display_text_string(line)
  } else {
    ""
  }
}

///|
test "insert_user_text sanitizes pasted terminal controls" {
  // A pasted screen-clear escape must never reach the model verbatim: the ESC
  // is dropped and only its inert tail survives, so the live echo cannot mutate
  // the terminal.
  let model = @composer.Model::new("")
  model.insert_user_text("a\u{1b}[2Jb")
  inspect(model.text(), content="a[2Jb")
  // A lone CR becomes a hard line break and a tab expands to the next stop.
  let normalized = @composer.Model::new("")
  normalized.insert_user_text("x\ry\tz")
  inspect(
    normalized.text(),
    content=(
      #|x
      #|y       z
    ),
  )
  // The shell-prefix shortcut also sees sanitized text.
  let shell = @composer.Model::new("")
  shell.insert_user_text("!a\u{1b}b")
  inspect(shell.text(), content="ab")
  inspect(shell.mode().is_shell(), content="true")
}

///|
test "input prefix marks only the first logical input line" {
  inspect(@composer.Model::new("").input_prefix(0).text(), content="❯ ")
  let shell = @composer.Model::new("")
  shell.insert_user_text("!")
  inspect(shell.input_prefix(0).text(), content="! ")
  inspect(@composer.Model::new("").input_prefix(1).text(), content="  ")
  inspect(
    @composer.Model::new("a\nb\nc", max_text_rows=2).input_prefix(0).text(),
    content="  ",
  )
}

///|
test "input cursor offset accounts for prompt and display width" {
  inspect(@composer.Model::new("").cursor_offset(), content="2")
  inspect(@composer.Model::new("abc").cursor_offset(), content="5")
  inspect(@composer.Model::new("你好").cursor_offset(), content="6")
  let moved_left = @composer.Model::new("abc")
  moved_left.move_left()
  inspect(moved_left.cursor_offset(), content="4")
  inspect(@composer.Model::new("a\nb").cursor_offset(), content="3")
  // A long line wrapped to a content width of 3 puts the cursor at the end of
  // its second wrapped row: prompt (2) + display width of "def" (3).
  let narrow = @composer.Model::new("abcdef")
  narrow.resize(cols=5)
  inspect(narrow.cursor_offset(), content="5")
  let shell = @composer.Model::new("")
  shell.insert_user_text("!abc")
  inspect(shell.cursor_offset(), content="5")
}

///|
test "long line soft-wraps across visible rows" {
  // cols 7 leaves a content width of 5, so "abcdefghij" wraps to two rows.
  let model = @composer.Model::new("abcdefghij")
  model.resize(cols=7)
  inspect(model.visible_text_rows(), content="2")
  inspect(visible_row_text(model, 0), content="abcde")
  inspect(visible_row_text(model, 1), content="fghij")
  // Only the first wrapped row keeps the prompt; the continuation is indented.
  inspect(model.input_prefix(0).text(), content="❯ ")
  inspect(model.input_prefix(1).text(), content="  ")
  // The cursor sits at the end of the second wrapped row.
  inspect(model.cursor_row(), content="1")
  inspect(model.cursor_offset(), content="7")
}

///|
test "insert into non-additive boundary places cursor correctly" {
  // "ل" + "ا" → "لا" (lam-alef ligature, width 1 not 2). Inserting "ا" after
  // "ل" in "لx" must leave the cursor after the combined unit, not after "x".
  let model = @composer.Model::new("\u{644}x") // "لx"
  model.move_left() // cursor between "ل" and "x"
  model.insert("\u{627}") // insert "ا"
  inspect(model.text(), content="\u{644}\u{627}x") // "لاx"
  // cursor_offset = PromptWidth(2) + display-col-after-"لا"(1) = 3, not 4
  inspect(model.cursor_offset(), content="3")
}

///|
test "insert combining with suffix places cursor before combined unit" {
  // Inserting "ل" at the start of "اx" creates "لاx" where "لا" is one
  // display unit. The cursor should land before the combined unit (before
  // the suffix's "ا"), not after it.
  let model = @composer.Model::new("\u{627}x") // "اx"
  model.move_home()
  model.insert("\u{644}") // insert "ل" → text becomes "لاx"
  inspect(model.text(), content="\u{644}\u{627}x") // "لاx"
  // cursor sits before the combined "لا" unit: prompt(2) + col(0) = 2
  inspect(model.cursor_offset(), content="2")
}

///|
test "delete at non-additive boundary keeps cursor before combined unit" {
  // Deleting the newline in "ل\nا" joins them into "لا" (lam-alef, width 1).
  // The cursor was at the end of "ل"; after joining it should land before the
  // combined unit, not after it.
  let model = @composer.Model::new("\u{644}\n\u{627}") // "ل\nا"
  model.move_vertical(-1) // cursor on the "ل" line
  model.move_end() // cursor at end of "ل"
  model.delete_after() // kill the line break, joining the lines
  inspect(model.text(), content="\u{644}\u{627}") // "لا"
  // cursor before the combined "لا" unit: prompt(2) + col(0) = 2
  inspect(model.cursor_offset(), content="2")
}

///|
test "model shell mode keeps marker out of text" {
  let shell = @composer.Model::new("")
  shell.insert_user_text("!echo hi")
  assert_true(shell.mode().is_shell())
  inspect(shell.text(), content="echo hi")
  // cursor at end of "echo hi" in shell mode: "! ".width()(2) + "echo hi".width()(7) = 9
  inspect(shell.cursor_offset(), content="9")
  let normal = @composer.Model::new("")
  normal.insert_user_text("!")
  normal.delete_before()
  assert_true(normal.mode().is_input())
  inspect(normal.text(), content="")
}

///|
test "model kill keeps shell mode active" {
  let shell = @composer.Model::new("")
  shell.insert_user_text("!pwd")
  shell.kill_before()
  assert_true(shell.mode().is_shell())
  inspect(shell.text(), content="")
}

///|
test "model replace restores text mode and cursor" {
  let shell = @composer.Model::new("")
  shell.insert_user_text("!pwd")
  let model = @composer.Model::new("draft")
  model.replace(shell.text(), mode=shell.mode())
  inspect(model.text(), content="pwd")
  assert_true(model.mode().is_shell())
  // cursor at end of "pwd" in shell mode: "! ".width()(2) + "pwd".width()(3) = 5
  inspect(model.cursor_offset(), content="5")
  inspect(model.input_prefix(0).text(), content="! ")
}

///|
test "soft wrap keeps non additive display units intact" {
  let model = @composer.Model::new("\u{644}\u{627}x")
  model.resize(cols=3)
  inspect(model.visible_text_rows(), content="2")
  inspect(visible_row_text(model, 0), content="لا")
  inspect(visible_row_text(model, 1), content="x")
}

///|
test "model reports cursor visual-row boundaries" {
  let model = @composer.Model::new("one\ntwo")
  assert_false(model.cursor_at_first_visual_row())
  assert_true(model.cursor_at_last_visual_row())
  model.move_home()
  assert_false(model.cursor_at_first_visual_row())
  assert_true(model.cursor_at_last_visual_row())
  model.move_vertical(-1)
  assert_true(model.cursor_at_first_visual_row())
  assert_false(model.cursor_at_last_visual_row())
}

///|
test "resize caps visible rows to the terminal budget and keeps the cursor" {
  let model = @composer.Model::new("a\nb\nc\nd", max_text_rows=4)
  model.resize(cols=20)
  // Four logical lines, no cap below the configured ceiling: all four show.
  inspect(model.visible_text_rows(), content="4")
  // A tighter budget narrows the visible window...
  model.resize(cols=20, max_rows=2)
  inspect(model.visible_text_rows(), content="2")
  // ...and the cursor (on the last line) stays inside it.
  assert_true(model.cursor_row() < 2)
  // The budget never raises the configured ceiling.
  model.resize(cols=20, max_rows=10)
  inspect(model.visible_text_rows(), content="4")
}
