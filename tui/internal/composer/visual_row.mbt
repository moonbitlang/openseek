///|
/// A single on-screen composer row produced by soft-wrapping a logical input
/// line to the editable content width.
priv struct VisualRow {
  display : @displaytext.DisplayText
  logic_start : @displaytext.TextualPosition
  logic_end : @displaytext.TextualPosition
}

///|
fn VisualRow::new(
  line : LogicLine,
  start~ : @displaytext.TextualPosition,
  end~ : @displaytext.TextualPosition,
) -> VisualRow {
  {
    display: DisplayText(line.display.view(start, end).to_owned()),
    logic_start: start,
    logic_end: end,
  }
}

///|
/// Soft-wrap cached logical lines to `content_width` display columns.
fn wrap_visual_rows(
  logical_lines : Array[LogicLine],
  content_width~ : Int,
) -> Array[VisualRow] {
  let width = content_width.max(1)
  let rows : Array[VisualRow] = []
  for line in logical_lines {
    line.row_start = rows.length()
    let mut start = line.display.start()
    let line_end = line.display.end()
    if start == line_end {
      rows.push(VisualRow::new(line, start~, end=line_end))
    } else {
      while start != line_end {
        let column = line.display.display_position(start).column()
        let target = @displaytext.DisplayPosition::new(column=column + width)
        let mut end = line.display.textual_position_at_or_before(target)
        if end == start {
          end = line.display.next(start).unwrap_or(line_end)
        }
        rows.push(VisualRow::new(line, start~, end~))
        start = end
      }
    }
    line.row_end = rows.length()
  }
  rows
}

///|
fn logic_line_at_row(logical_lines : Array[LogicLine], row_index~ : Int) -> Int {
  let last = logical_lines[logical_lines.length() - 1]
  let row_index = row_index.clamp(min=0, max=last.row_end - 1)
  for line_index, line in logical_lines {
    if row_index >= line.row_start && row_index < line.row_end {
      return line_index
    }
  }
  logical_lines.length() - 1
}

///|
/// Index of the wrapped row that should hold the cursor.
fn find_cursor_visual_row(
  logical_lines : Array[LogicLine],
  rows~ : Array[VisualRow],
  cursor~ : TextCursor,
) -> Int {
  let line = logical_lines[cursor.line]
  let mut result = line.row_start
  let cursor_column = line.display_column(position=cursor.position)
  for index in line.row_start..<line.row_end {
    let row = rows[index]
    let row_column = line.display_column(position=row.logic_start)
    if row_column <= cursor_column {
      result = index
    }
  }
  result
}

///|
fn is_row_start_at_cursor(row~ : VisualRow, cursor~ : TextCursor) -> Bool {
  row.logic_start == cursor.position
}

///|
/// Resolve the cursor to a wrapped row index.
///
/// A cursor sitting exactly on a soft-wrap boundary is ambiguous: the same text
/// position is both the end of one row and the start of the next. `at_wrap_end`
/// is the affinity bit set by vertical movement — when true the cursor renders at
/// the end of the earlier row instead of the start of the following one.
fn resolve_cursor(
  logical_lines : Array[LogicLine],
  rows~ : Array[VisualRow],
  cursor~ : TextCursor,
  at_wrap_end~ : Bool,
) -> Int {
  let index = find_cursor_visual_row(logical_lines, rows~, cursor~)
  let line = logical_lines[cursor.line]
  if at_wrap_end &&
    is_row_start_at_cursor(row=rows[index], cursor~) &&
    index > line.row_start {
    index - 1
  } else {
    index
  }
}
