///|
/// Whether a display unit counts as part of a word for word-wise cursor motion.
///
/// Classification looks at the unit's leading scalar: ASCII letters and
/// digits, and any non-ASCII scalar (CJK, accented letters, emoji), are word
/// characters; ASCII spaces and punctuation are delimiters.
fn is_word_unit(unit : StringView) -> Bool {
  match unit {
    [c, ..] => c.is_ascii_alphabetic() || c.is_ascii_digit() || !c.is_ascii()
    [] => false
  }
}

///|
priv struct TextCursor {
  line : Int
  position : @displaytext.TextualPosition
}

///|
fn TextCursor::new(
  logical_lines : Array[LogicLine],
  line~ : Int,
  position~ : @displaytext.TextualPosition,
) -> TextCursor {
  let line = line.clamp(min=0, max=logical_lines.length() - 1)
  let logical_line = logical_lines[line]
  let column = logical_line.display.display_position(position)
  let position = logical_line.display.textual_position_at_or_before(column)
  { line, position }
}

///|
fn TextCursor::line_start(
  logical_lines : Array[LogicLine],
  line~ : Int,
) -> TextCursor {
  let line = line.clamp(min=0, max=logical_lines.length() - 1)
  TextCursor::new(
    logical_lines,
    line~,
    position=logical_lines[line].display.start(),
  )
}

///|
fn TextCursor::line_end(
  logical_lines : Array[LogicLine],
  line~ : Int,
) -> TextCursor {
  let line = line.clamp(min=0, max=logical_lines.length() - 1)
  TextCursor::new(
    logical_lines,
    line~,
    position=logical_lines[line].display.end(),
  )
}

///|
fn TextCursor::text_end(logical_lines : Array[LogicLine]) -> TextCursor {
  let last = logical_lines.length() - 1
  TextCursor::line_end(logical_lines, line=last)
}

///|
fn TextCursor::is_line_start(
  self : TextCursor,
  logical_lines : Array[LogicLine],
) -> Bool {
  self.position == logical_lines[self.line].display.start()
}

///|
fn TextCursor::is_line_end(
  self : TextCursor,
  logical_lines : Array[LogicLine],
) -> Bool {
  self.position == logical_lines[self.line].display.end()
}

///|
fn move_cursor_left(
  logical_lines : Array[LogicLine],
  cursor : TextCursor,
) -> TextCursor {
  let line = logical_lines[cursor.line]
  if line.display.prev(cursor.position) is Some(position) {
    TextCursor::new(logical_lines, line=cursor.line, position~)
  } else if cursor.line <= 0 {
    TextCursor::line_start(logical_lines, line=0)
  } else {
    TextCursor::line_end(logical_lines, line=cursor.line - 1)
  }
}

///|
fn move_cursor_right(
  logical_lines : Array[LogicLine],
  cursor : TextCursor,
) -> TextCursor {
  let line = logical_lines[cursor.line]
  if line.display.next(cursor.position) is Some(position) {
    TextCursor::new(logical_lines, line=cursor.line, position~)
  } else if cursor.line + 1 >= logical_lines.length() {
    TextCursor::text_end(logical_lines)
  } else {
    TextCursor::line_start(logical_lines, line=cursor.line + 1)
  }
}

///|
fn TextCursor::is_text_start(
  self : TextCursor,
  logical_lines : Array[LogicLine],
) -> Bool {
  self.line == 0 && self.is_line_start(logical_lines)
}

///|
fn TextCursor::is_text_end(
  self : TextCursor,
  logical_lines : Array[LogicLine],
) -> Bool {
  self.line == logical_lines.length() - 1 && self.is_line_end(logical_lines)
}

///|
fn TextCursor::current_text(
  self : TextCursor,
  logical_lines : Array[LogicLine],
) -> StringView? {
  logical_lines[self.line].unit_text_at(position=self.position)
}

///|
fn TextCursor::previous_text(
  self : TextCursor,
  logical_lines : Array[LogicLine],
) -> StringView? {
  logical_lines[self.line].unit_text_before(position=self.position)
}

///|
priv enum CursorDirection {
  Forward
  Backward
}

///|
fn CursorDirection::at_edge(
  self : CursorDirection,
  cursor : TextCursor,
  logical_lines : Array[LogicLine],
) -> Bool {
  match self {
    Forward => cursor.is_text_end(logical_lines)
    Backward => cursor.is_text_start(logical_lines)
  }
}

///|
fn CursorDirection::unit_text(
  self : CursorDirection,
  cursor : TextCursor,
  logical_lines : Array[LogicLine],
) -> StringView? {
  match self {
    Forward => cursor.current_text(logical_lines)
    Backward => cursor.previous_text(logical_lines)
  }
}

///|
fn CursorDirection::step(
  self : CursorDirection,
  logical_lines : Array[LogicLine],
  cursor : TextCursor,
) -> TextCursor {
  match self {
    Forward => move_cursor_right(logical_lines, cursor)
    Backward => move_cursor_left(logical_lines, cursor)
  }
}

///|
fn move_cursor_word(
  logical_lines : Array[LogicLine],
  cursor : TextCursor,
  direction~ : CursorDirection,
) -> TextCursor {
  let mut cursor = cursor
  while !direction.at_edge(cursor, logical_lines) {
    if direction.unit_text(cursor, logical_lines) is Some(text) &&
      is_word_unit(text) {
      break
    } else {
      cursor = direction.step(logical_lines, cursor)
    }
  }
  while !direction.at_edge(cursor, logical_lines) {
    if direction.unit_text(cursor, logical_lines) is Some(text) &&
      is_word_unit(text) {
      cursor = direction.step(logical_lines, cursor)
    } else {
      break
    }
  }
  cursor
}

///|
fn move_cursor_word_right(
  logical_lines : Array[LogicLine],
  cursor : TextCursor,
) -> TextCursor {
  move_cursor_word(logical_lines, cursor, direction=Forward)
}

///|
fn move_cursor_word_left(
  logical_lines : Array[LogicLine],
  cursor : TextCursor,
) -> TextCursor {
  move_cursor_word(logical_lines, cursor, direction=Backward)
}
