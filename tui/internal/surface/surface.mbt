// The render-data vocabulary shared between the UI and the terminal renderer.
//
// These are passive, terminal-agnostic value types describing *what* to draw:
// styled `Span`s form a `Line`, lines plus a `Cursor` form a `Surface` (one
// rendered frame). The `Ui` builds them from semantic state; the `viewport`
// engine consumes them to paint a real terminal. Nothing here performs IO.

///|
/// Terminal styling applied while a span is written.
struct Style {
  foreground : @color.Color
  background : @color.Color
  underline : Bool
} derive(Eq)

///|
/// A string fragment with an associated style.
struct Span {
  text : String
  style : Style
} derive(Eq)

///|
/// One rendered row: a sequence of styled spans.
struct Line {
  spans : Array[Span]
} derive(Eq)

///|
/// A cursor position within a surface, as a 0-based (row, col) cell offset.
struct Cursor {
  row : Int
  col : Int
}

///|
/// Render output for one viewport frame.
///
/// `Ui` builds a fresh `Surface` from semantic state such as composer text,
/// status text, and terminal width, then passes it to `Viewport` for placement
/// and terminal drawing. `Viewport` does not build surfaces because it should
/// not own composer/status state, but it does cache the last drawn surface so
/// redraws can diff physical terminal rows and skip unchanged content.
///
/// A `Surface` always has a cursor. `Ui` produces one for the interactive
/// composer, and `Viewport` places that surface on the terminal.
///
/// Invariant: `width >= 1`, `cursor.row` is inside `rows` when any row exists,
/// and `cursor.col` is inside `width`. Construction normalizes these values so
/// terminal drawing does not need to defensively adjust them again.
struct Surface {
  width : Int
  rows : Array[Line]
  cursor : Cursor
}

///|
/// Build a style. With no arguments, the unstyled default (terminal default
/// colors, no underline).
pub fn Style::new(
  foreground? : @color.Color = Default,
  background? : @color.Color = Default,
  underline? : Bool = false,
) -> Style {
  { foreground, background, underline }
}

///|
/// Foreground color of the style.
pub fn Style::foreground(self : Style) -> @color.Color {
  self.foreground
}

///|
/// Background color of the style.
pub fn Style::background(self : Style) -> @color.Color {
  self.background
}

///|
/// Whether the style underlines its text.
pub fn Style::underline(self : Style) -> Bool {
  self.underline
}

///|
/// Build a span from text and an optional style (default: unstyled).
pub fn Span::new(text : String, style? : Style = Style::new()) -> Span {
  { text, style }
}

///|
/// Text of the span.
pub fn Span::text(self : Span) -> String {
  self.text
}

///|
/// Style of the span.
pub fn Span::style(self : Span) -> Style {
  self.style
}

///|
/// Build a line from its styled spans, in left-to-right order.
pub fn Line::new(spans : Array[Span]) -> Line {
  { spans, }
}

///|
/// The styled spans that make up the line, in order.
pub fn Line::spans(self : Line) -> Array[Span] {
  self.spans
}

///|
/// The line's text content with styling stripped.
pub fn Line::text(self : Line) -> String {
  let builder = StringBuilder()
  for span in self.spans {
    builder.write_string(span.text)
  }
  builder.to_string()
}

///|
/// Build a cursor at a 0-based (row, col) cell offset.
pub fn Cursor::new(row~ : Int, col~ : Int) -> Cursor {
  { row, col }
}

///|
/// The cursor's 0-based row offset.
pub fn Cursor::row(self : Cursor) -> Int {
  self.row
}

///|
/// The cursor's 0-based column offset.
pub fn Cursor::col(self : Cursor) -> Int {
  self.col
}

///|
fn normalize_surface_width(width : Int) -> Int {
  if width < 1 {
    1
  } else {
    width
  }
}

///|
fn normalize_surface_index(value : Int, max_value : Int) -> Int {
  value.clamp(min=0, max=max_value)
}

///|
fn normalize_surface_cursor(
  rows : Array[Line],
  width : Int,
  cursor : Cursor,
) -> Cursor {
  let max_row = if rows.length() == 0 { 0 } else { rows.length() - 1 }
  let max_col = if width <= 1 { 0 } else { width - 1 }
  {
    row: normalize_surface_index(cursor.row, max_row),
    col: normalize_surface_index(cursor.col, max_col),
  }
}

///|
/// Build a surface frame, normalizing invariants: `width` is forced to `>= 1`
/// and the cursor is clamped inside the rows and width so the renderer never
/// has to re-validate.
pub fn Surface::new(
  width~ : Int,
  rows~ : Array[Line],
  cursor~ : Cursor,
) -> Surface {
  let width = normalize_surface_width(width)
  let cursor = normalize_surface_cursor(rows, width, cursor)
  { width, rows, cursor }
}

///|
/// Number of rows in the surface.
pub fn Surface::height(self : Surface) -> Int {
  self.rows.length()
}

///|
/// The surface's normalized cursor position.
pub fn Surface::cursor(self : Surface) -> Cursor {
  self.cursor
}

///|
/// Return the first `max_rows` rows of the surface as a new surface, preserving
/// width and cursor. Used to fit a surface into a bounded terminal region; the
/// caller decides the bound.
pub fn Surface::with_max_rows(self : Surface, max_rows : Int) -> Surface {
  let row_count = if max_rows < 0 {
    0
  } else if max_rows > self.rows.length() {
    self.rows.length()
  } else {
    max_rows
  }
  let rows : Array[Line] = []
  for index in 0..<row_count {
    rows.push(self.rows[index])
  }
  Surface::new(width=self.width, rows~, cursor=self.cursor)
}

///|
/// The line at `row`, or an empty line when `row` is out of range.
pub fn Surface::line_at(self : Surface, row : Int) -> Line {
  if self.rows.get(row) is Some(line) {
    line
  } else {
    Line::new([])
  }
}
