///|
const MinTextRows : Int = 1

///|
/// Default cap on how many editable rows the composer grows to before it
/// scrolls instead of growing further.
pub const DefaultMaxTextRows : Int = 4

///|
fn line_count(text : String) -> Int {
  @text.split_lines(text).length()
}

///|
fn normalize_max_text_rows(max_text_rows : Int) -> Int {
  if max_text_rows < MinTextRows {
    MinTextRows
  } else {
    max_text_rows
  }
}

///|
fn is_newline_grapheme(grapheme : StringView) -> Bool {
  grapheme.to_owned() == "\n"
}

///|
/// Whether a grapheme counts as part of a word for word-wise cursor motion.
///
/// Classification looks at the grapheme's leading scalar: ASCII letters and
/// digits, and any non-ASCII scalar (CJK, accented letters, emoji), are word
/// characters; ASCII spaces and punctuation are delimiters.
fn is_word_grapheme(grapheme : StringView) -> Bool {
  match grapheme {
    [c, ..] => c.is_ascii_alphabetic() || c.is_ascii_digit() || !c.is_ascii()
    [] => false
  }
}

///|
fn line_display_width(lines : Array[String], line : Int) -> Int {
  @text.display_width(@text.line_at(lines, line))
}

///|
/// Display width of the prompt prefix (`> `, `! `, or the `  ` continuation),
/// which is always two columns. Every wrapped composer row reserves this much.
const PromptWidth : Int = 2

///|
/// Editable content width for a composer rendered at `cols` terminal columns,
/// i.e. the room left once the two-column prompt prefix is reserved.
fn content_width_for(cols~ : Int) -> Int {
  let width = cols - PromptWidth
  if width < 1 {
    1
  } else {
    width
  }
}

///|
/// Content width assumed before the composer has been laid out against a real
/// terminal. The renderer calls `Model::resize` on every frame, so this only
/// governs editing that happens before the first draw.
const DefaultContentWidth : Int = 78

///|
/// Number of editable rows to render for `total` wrapped rows, clamped between
/// one and `max_text_rows`.
fn visible_count(total : Int, max_text_rows : Int) -> Int {
  let max_text_rows = normalize_max_text_rows(max_text_rows)
  if total < MinTextRows {
    MinTextRows
  } else if total > max_text_rows {
    max_text_rows
  } else {
    total
  }
}

///|
/// A single on-screen composer row produced by soft-wrapping a logical input
/// line to the editable content width. `start_column` is the grapheme offset
/// within the logical line where this segment begins, used to map the cursor
/// onto the correct wrapped row.
priv struct VisualRow {
  logical_line : Int
  start_column : Int
  text : String
}

///|
/// Soft-wrap every logical line of `text` to `content_width` display columns.
///
/// Each logical line yields at least one row (an empty line yields one empty
/// row) so the cursor always has a row to sit on. Wrapping is by grapheme and
/// display width, matching how each row is later measured on screen.
fn visual_rows_for(text : String, content_width : Int) -> Array[VisualRow] {
  let width = if content_width < 1 { 1 } else { content_width }
  let rows : Array[VisualRow] = []
  let lines = @text.split_lines(text)
  for line_index in 0..<lines.length() {
    let line = lines[line_index]
    let mut column = 0
    let mut segment_start = 0
    let mut segment = StringBuilder()
    let mut segment_width = 0
    let mut segment_filled = false
    for grapheme in @grapheme.grapheme_iter(line) {
      let grapheme_width = @unicodewidth.str_width(grapheme)
      if segment_filled && segment_width + grapheme_width > width {
        rows.push({
          logical_line: line_index,
          start_column: segment_start,
          text: segment.to_string(),
        })
        segment = StringBuilder()
        segment_width = 0
        segment_filled = false
        segment_start = column
      }
      segment.write_stringview(grapheme)
      segment_width = segment_width + grapheme_width
      segment_filled = true
      column = column + 1
    }
    rows.push({
      logical_line: line_index,
      start_column: segment_start,
      text: segment.to_string(),
    })
  }
  rows
}

///|
/// Index of the wrapped row that should hold the cursor at `point`.
///
/// Within the cursor's logical line this picks the last segment whose
/// `start_column` is at or before the cursor, so a cursor resting exactly on a
/// wrap boundary appears at the start of the following row.
fn cursor_visual_row(rows : Array[VisualRow], point : CursorPoint) -> Int {
  let mut result = 0
  for index in 0..<rows.length() {
    let row = rows[index]
    if row.logical_line > point.line {
      break
    }
    if row.logical_line == point.line &&
      row.start_column <= point.grapheme_column {
      result = index
    }
  }
  result
}

///|
/// Grapheme offset within `segment` whose left edge is nearest to but not past
/// `target` display columns. Used to preserve a preferred column when moving the
/// cursor vertically between wrapped rows of differing content.
fn place_display_column(segment : String, target : Int) -> Int {
  let mut offset = 0
  let mut width = 0
  for grapheme in @grapheme.grapheme_iter(segment) {
    let grapheme_width = @unicodewidth.str_width(grapheme)
    if width + grapheme_width > target {
      break
    }
    width = width + grapheme_width
    offset = offset + 1
  }
  offset
}

///|
/// Resolve the cursor to a wrapped row index and the grapheme offset within that
/// row's segment.
///
/// A cursor sitting exactly on a soft-wrap boundary is ambiguous: the same text
/// position is both the end of one row and the start of the next. `at_wrap_end`
/// is the affinity bit set by vertical movement — when true the cursor renders at
/// the end of the earlier row instead of the start of the following one.
fn resolve_cursor(
  rows : Array[VisualRow],
  point : CursorPoint,
  at_wrap_end : Bool,
) -> (Int, Int) {
  let index = cursor_visual_row(rows, point)
  if at_wrap_end &&
    rows[index].start_column == point.grapheme_column &&
    rows[index].start_column > 0 {
    let previous = index - 1
    (previous, point.grapheme_column - rows[previous].start_column)
  } else {
    (index, point.grapheme_column - rows[index].start_column)
  }
}

///|
priv struct CursorPoint {
  line : Int
  grapheme_column : Int
}

///|
/// Semantic mode for the live composer.
///
/// `Input` is normal agent-steering text. `Shell` changes the first prompt to
/// `! ` and makes the submitted text become a shell command.
enum Mode {
  Input
  Shell
} derive(Eq)

///|
fn Mode::prompt_prefix(self : Mode) -> String {
  match self {
    Input => "> "
    Shell => "! "
  }
}

///|
/// Whether the composer is in normal agent-steering input mode.
pub fn Mode::is_input(self : Mode) -> Bool {
  self == Input
}

///|
/// Whether the composer is in shell mode, where submitted text runs as a
/// shell command and the first prompt shows `! `.
pub fn Mode::is_shell(self : Mode) -> Bool {
  self == Shell
}

///|
fn cursor_point_for(text : String, cursor : Int) -> CursorPoint {
  let target = cursor.clamp(min=0, max=@text.grapheme_count(text))
  let mut index = 0
  let mut line = 0
  let mut grapheme_column = 0
  for grapheme in @grapheme.grapheme_iter(text) {
    if index >= target {
      break
    }
    if is_newline_grapheme(grapheme) {
      line = line + 1
      grapheme_column = 0
    } else {
      grapheme_column = grapheme_column + 1
    }
    index = index + 1
  }
  { line, grapheme_column }
}

///|
fn line_start_cursor(text : String, line : Int) -> Int {
  let line = line.clamp(min=0, max=line_count(text) - 1)
  if line == 0 {
    0
  } else {
    let mut index = 0
    let mut current_line = 0
    for grapheme in @grapheme.grapheme_iter(text) {
      index = index + 1
      if is_newline_grapheme(grapheme) {
        current_line = current_line + 1
        if current_line == line {
          break
        }
      }
    }
    index
  }
}

///|
fn cursor_for_line_display_column(
  text : String,
  line : Int,
  display_column : Int,
) -> Int {
  let lines = @text.split_lines(text)
  let line = line.clamp(min=0, max=lines.length() - 1)
  let target = display_column.clamp(min=0, max=line_display_width(lines, line))
  let mut grapheme_column = 0
  let mut width = 0
  for grapheme in @grapheme.grapheme_iter(@text.line_at(lines, line)) {
    let next_width = @unicodewidth.str_width(grapheme)
    if width + next_width > target {
      break
    }
    width = width + next_width
    grapheme_column = grapheme_column + 1
  }
  line_start_cursor(text, line) + grapheme_column
}

///|
/// Mutable state model for the multiline composer.
///
/// `Model` owns the user-editable text, cursor position, semantic mode, the
/// editable content width, the maximum rows the composer may grow to, and the
/// first visible wrapped row. Because it knows its own width it soft-wraps long
/// logical lines and navigates by on-screen row like a text editor. It does not
/// emit terminal sequences; terminal anchoring and rendering belong to `Ui`.
struct Model {
  mut text : String
  mut cursor : Int
  mut preferred_column : Int?
  mut view_start : Int
  // Affinity for a cursor that lands on a soft-wrap boundary: when true the
  // cursor belongs to the end of the earlier wrapped row, not the start of the
  // next one. Set by vertical movement, reset by every other edit.
  mut at_wrap_end : Bool
  mut content_width : Int
  max_text_rows : Int
  mut mode : Mode
}

///|
fn make_model(
  text : String,
  cursor : Int,
  preferred_column : Int?,
  view_start : Int,
  max_text_rows? : Int = DefaultMaxTextRows,
  mode? : Mode = Input,
  content_width? : Int = DefaultContentWidth,
) -> Model {
  let max_text_rows = normalize_max_text_rows(max_text_rows)
  let cursor = cursor.clamp(min=0, max=@text.grapheme_count(text))
  let content_width = if content_width < 1 { 1 } else { content_width }
  let model = {
    text,
    cursor,
    preferred_column,
    view_start: if view_start < 0 {
      0
    } else {
      view_start
    },
    at_wrap_end: false,
    content_width,
    max_text_rows,
    mode,
  }
  // The scroll offset depends on how the text wraps, so resolve it once now and
  // keep it current after every edit and resize.
  model.reclamp_view()
  model
}

///|
/// Create an empty composer in `Input` mode whose editable area grows to at
/// most `max_text_rows` wrapped rows.
pub fn Model::new(max_text_rows? : Int = DefaultMaxTextRows) -> Model {
  Model::from_text("", max_text_rows~)
}

///|
fn Model::from_text(
  text : String,
  max_text_rows? : Int = DefaultMaxTextRows,
) -> Model {
  make_model(text, @text.grapheme_count(text), None, 0, max_text_rows~)
}

///|
/// Clear the composer back to empty `Input` mode, resetting the cursor and
/// scroll window.
pub fn Model::reset(self : Model) -> Unit {
  self.set_state("", 0, None, 0, mode=Input)
}

///|
/// Replace the entire buffer with `text` in `mode`, placing the cursor at the
/// end and scrolling the view back to the top. Used to load history entries.
pub fn Model::replace(self : Model, text : String, mode~ : Mode) -> Unit {
  self.set_state(text, @text.grapheme_count(text), None, 0, mode~)
}

///|
fn Model::cursor_point(self : Model) -> CursorPoint {
  cursor_point_for(self.text, self.cursor)
}

///|
/// Return the current text that should be submitted to the caller.
///
/// In shell mode, the leading `!` prompt marker is not part of this text.
pub fn Model::text(self : Model) -> String {
  self.text
}

///|
/// Return the semantic mode for the current composer text.
///
/// `Input` mode submits normal agent-steering text. `Shell` mode keeps the
/// leading `!` marker out of editable text and submits a command.
pub fn Model::mode(self : Model) -> Mode {
  self.mode
}

///|
/// Current number of editable rows that should be rendered.
///
/// The composer starts at one row and grows as hard newlines and soft-wrapped
/// long lines add wrapped rows, stopping at `max_text_rows`. When the text wraps
/// to more rows than this value, `view_start` scrolls the visible window instead
/// of growing further.
pub fn Model::visible_text_rows(self : Model) -> Int {
  visible_count(
    visual_rows_for(self.text, self.content_width).length(),
    self.max_text_rows,
  )
}

///|
/// Return the wrapped input segment displayed at a composer row.
///
/// `row` is relative to the visible composer text area, not the terminal. A
/// missing row returns an empty string so renderers can draw a fixed surface for
/// the current frame without special-casing short buffers.
pub fn Model::visible_line(self : Model, row : Int) -> String {
  let rows = visual_rows_for(self.text, self.content_width)
  let index = self.view_start + row
  if index < 0 || index >= rows.length() {
    ""
  } else {
    rows[index].text
  }
}

///|
/// Return the prompt prefix for a visible composer row at `cols` columns.
///
/// Only the very first wrapped row of the first logical input line gets `> ` or
/// `! `. Every other row — later logical lines and soft-wrapped continuations
/// alike — uses two spaces so wrapped content lines up with the editable text.
pub fn Model::input_prefix(self : Model, row : Int) -> String {
  let rows = visual_rows_for(self.text, self.content_width)
  let index = self.view_start + row
  if index >= 0 &&
    index < rows.length() &&
    rows[index].logical_line == 0 &&
    rows[index].start_column == 0 {
    self.mode.prompt_prefix()
  } else {
    "  "
  }
}

///|
/// Cursor row within the visible composer text area.
///
/// The row is measured in wrapped rows and clamped to the current visible row
/// count, so terminal renderers can move relative to the current composer
/// surface even when the underlying cursor is temporarily outside the window.
pub fn Model::cursor_row(self : Model) -> Int {
  let rows = visual_rows_for(self.text, self.content_width)
  let visible = visible_count(rows.length(), self.max_text_rows)
  let (index, _) = resolve_cursor(rows, self.cursor_point(), self.at_wrap_end)
  let row = index - self.view_start
  if row < 0 {
    0
  } else if row >= visible {
    visible - 1
  } else {
    row
  }
}

///|
/// Whether the cursor is on the first wrapped row of the composer.
///
/// Vertical-up at this row hands off to history recall rather than moving within
/// the buffer, so wrapped continuation rows count as interior rows here.
pub fn Model::cursor_at_first_visual_row(self : Model) -> Bool {
  let rows = visual_rows_for(self.text, self.content_width)
  let (index, _) = resolve_cursor(rows, self.cursor_point(), self.at_wrap_end)
  index == 0
}

///|
/// Whether the cursor is on the last wrapped row of the composer.
pub fn Model::cursor_at_last_visual_row(self : Model) -> Bool {
  let rows = visual_rows_for(self.text, self.content_width)
  let (index, _) = resolve_cursor(rows, self.cursor_point(), self.at_wrap_end)
  index == rows.length() - 1
}

///|
/// Cursor column offset within the terminal row that contains the cursor.
///
/// The result is a display-cell offset from column 1, including the prompt
/// prefix width, and is measured within the cursor's wrapped segment so it stays
/// correct when a long line soft-wraps. It is based on grapheme/display-width
/// measurement, not byte length.
pub fn Model::cursor_offset(self : Model) -> Int {
  let rows = visual_rows_for(self.text, self.content_width)
  let (index, offset) = resolve_cursor(
    rows,
    self.cursor_point(),
    self.at_wrap_end,
  )
  let before_cursor = @text.grapheme_slice(rows[index].text, 0, offset)
  PromptWidth + @text.display_width(before_cursor)
}

///|
fn Model::set_state(
  self : Model,
  text : String,
  cursor : Int,
  preferred_column : Int?,
  view_start : Int,
  mode? : Mode = Input,
  at_wrap_end? : Bool = false,
) -> Unit {
  let cursor = cursor.clamp(min=0, max=@text.grapheme_count(text))
  self.text = text
  self.cursor = cursor
  self.preferred_column = preferred_column
  self.view_start = if view_start < 0 { 0 } else { view_start }
  self.mode = mode
  self.at_wrap_end = at_wrap_end
  // The text or cursor may have moved; pull the scroll window back over the
  // cursor for the current width.
  self.reclamp_view()
}

///|
/// Re-clamp `view_start` so the cursor's wrapped row stays visible at the
/// current content width. Called after every edit, move, and resize.
fn Model::reclamp_view(self : Model) -> Unit {
  let rows = visual_rows_for(self.text, self.content_width)
  let total = rows.length()
  let visible = visible_count(total, self.max_text_rows)
  let max_start = if total - visible > 0 { total - visible } else { 0 }
  let (cursor_index, _) = resolve_cursor(
    rows,
    self.cursor_point(),
    self.at_wrap_end,
  )
  let mut start = self.view_start.clamp(min=0, max=max_start)
  if cursor_index < start {
    start = cursor_index
  } else if cursor_index >= start + visible {
    start = cursor_index - visible + 1
  }
  self.view_start = start.clamp(min=0, max=max_start)
}

///|
/// Lay the composer out for a terminal `cols` columns wide. The renderer calls
/// this each frame so soft-wrapping and vertical movement track the live width.
pub fn Model::resize(self : Model, cols~ : Int) -> Unit {
  self.content_width = content_width_for(cols~)
  self.reclamp_view()
}

///|
fn Model::move_to_cursor(
  self : Model,
  cursor : Int,
  preferred_column : Int?,
) -> Unit {
  self.set_state(
    self.text,
    cursor,
    preferred_column,
    self.view_start,
    mode=self.mode,
  )
}

///|
fn Model::delete_range(self : Model, start : Int, end : Int) -> Unit {
  let length = @text.grapheme_count(self.text)
  let start = start.clamp(min=0, max=length)
  let end = end.clamp(min=start, max=length)
  let prefix = @text.grapheme_slice(self.text, 0, start)
  let suffix = @text.grapheme_slice(self.text, end, length)
  self.set_state(prefix + suffix, start, None, self.view_start, mode=self.mode)
}

///|
/// Insert `text` at the cursor and advance the cursor past it. Inserted text is
/// counted by graphemes, so multi-byte characters move the cursor one step each.
pub fn Model::insert(self : Model, text : String) -> Unit {
  let prefix = @text.grapheme_slice(self.text, 0, self.cursor)
  let suffix = @text.grapheme_slice(
    self.text,
    self.cursor,
    @text.grapheme_count(self.text),
  )
  self.set_state(
    prefix + text + suffix,
    self.cursor + @text.grapheme_count(text),
    None,
    self.view_start,
    mode=self.mode,
  )
}

///|
/// Insert text typed by the user, applying the shell-mode shortcut.
///
/// When the buffer is empty, the cursor is at the start, and the mode is
/// `Input`, a leading `!` switches the composer into `Shell` mode and is
/// dropped from the editable text (only the text after it is inserted).
/// Otherwise this behaves like `insert`.
pub fn Model::insert_user_text(self : Model, text : String) -> Unit {
  if self.mode.is_input() && self.text.length() == 0 && self.cursor == 0 {
    match text {
      [.. "!", .. rest] => {
        let rest_text = rest.to_owned()
        self.set_state(
          rest_text,
          @text.grapheme_count(rest_text),
          None,
          self.view_start,
          mode=Shell,
        )
      }
      _ => self.insert(text)
    }
  } else {
    self.insert(text)
  }
}

///|
/// Delete the one grapheme before the cursor (Backspace). At the start of the
/// buffer this is a no-op that also normalizes the mode back to `Input`.
pub fn Model::delete_before(self : Model) -> Unit {
  if self.cursor <= 0 {
    self.set_state(self.text, 0, None, self.view_start, mode=Input)
  } else {
    let prefix = @text.grapheme_slice(self.text, 0, self.cursor - 1)
    let suffix = @text.grapheme_slice(
      self.text,
      self.cursor,
      @text.grapheme_count(self.text),
    )
    self.set_state(
      prefix + suffix,
      self.cursor - 1,
      None,
      self.view_start,
      mode=self.mode,
    )
  }
}

///|
/// Delete the one grapheme at the cursor (Delete / Ctrl-D). At the end of the
/// buffer this is a no-op.
pub fn Model::delete_after(self : Model) -> Unit {
  let length = @text.grapheme_count(self.text)
  if self.cursor >= length {
    self.set_state(
      self.text,
      self.cursor,
      None,
      self.view_start,
      mode=self.mode,
    )
  } else {
    let prefix = @text.grapheme_slice(self.text, 0, self.cursor)
    let suffix = @text.grapheme_slice(self.text, self.cursor + 1, length)
    self.set_state(
      prefix + suffix,
      self.cursor,
      None,
      self.view_start,
      mode=self.mode,
    )
  }
}

///|
/// Move the cursor one grapheme left, crossing line breaks. Clamped at the
/// start of the buffer.
pub fn Model::move_left(self : Model) -> Unit {
  self.move_to_cursor(self.cursor - 1, None)
}

///|
/// Move the cursor one grapheme right, crossing line breaks. Clamped at the end
/// of the buffer.
pub fn Model::move_right(self : Model) -> Unit {
  self.move_to_cursor(self.cursor + 1, None)
}

///|
/// Move the cursor to the end of the next word: skip any leading delimiters,
/// then the run of word graphemes. Matches readline's `forward-word` (Alt-F).
pub fn Model::move_word_right(self : Model) -> Unit {
  let graphemes = @grapheme.graphemes(self.text)
  let length = graphemes.length()
  let mut cursor = self.cursor
  while cursor < length && !is_word_grapheme(graphemes[cursor]) {
    cursor = cursor + 1
  }
  while cursor < length && is_word_grapheme(graphemes[cursor]) {
    cursor = cursor + 1
  }
  self.move_to_cursor(cursor, None)
}

///|
/// Move the cursor to the start of the previous word: skip any trailing
/// delimiters, then the run of word graphemes. Matches readline's `backward-word`
/// (Alt-B).
pub fn Model::move_word_left(self : Model) -> Unit {
  let graphemes = @grapheme.graphemes(self.text)
  let mut cursor = self.cursor
  while cursor > 0 && !is_word_grapheme(graphemes[cursor - 1]) {
    cursor = cursor - 1
  }
  while cursor > 0 && is_word_grapheme(graphemes[cursor - 1]) {
    cursor = cursor - 1
  }
  self.move_to_cursor(cursor, None)
}

///|
/// Move the cursor to the start of its current logical line (Home / Ctrl-A),
/// not the start of the wrapped row.
pub fn Model::move_home(self : Model) -> Unit {
  let point = self.cursor_point()
  self.move_to_cursor(line_start_cursor(self.text, point.line), None)
}

///|
/// Move the cursor to the end of its current logical line (End / Ctrl-E), past
/// any soft-wrapped rows of that line.
pub fn Model::move_end(self : Model) -> Unit {
  let point = self.cursor_point()
  let lines = @text.split_lines(self.text)
  self.move_to_cursor(
    cursor_for_line_display_column(
      self.text,
      point.line,
      line_display_width(lines, point.line),
    ),
    None,
  )
}

///|
/// Delete from the start of the current logical line up to the cursor (Ctrl-U).
pub fn Model::kill_before(self : Model) -> Unit {
  let point = self.cursor_point()
  self.delete_range(line_start_cursor(self.text, point.line), self.cursor)
}

///|
/// Delete from the cursor to the end of the current logical line (Ctrl-K).
///
/// When the cursor is already at the line's end, kill the following line break
/// so the next line joins up; on a trailing empty line with nothing ahead,
/// remove the line itself by deleting the preceding break. On a fully empty
/// buffer this is a no-op.
pub fn Model::kill_after(self : Model) -> Unit {
  let point = self.cursor_point()
  let lines = @text.split_lines(self.text)
  let line_end = cursor_for_line_display_column(
    self.text,
    point.line,
    line_display_width(lines, point.line),
  )
  if self.cursor < line_end {
    // Kill to the end of the current line's content.
    self.delete_range(self.cursor, line_end)
  } else if self.cursor < @text.grapheme_count(self.text) {
    // Already at the end of the line (an empty line is its own end): kill the
    // line break so the next line joins up, matching readline/emacs kill-line.
    self.delete_range(self.cursor, self.cursor + 1)
  } else if self.cursor > 0 &&
    line_start_cursor(self.text, point.line) == self.cursor {
    // A trailing empty line has no forward content to kill; remove the line
    // itself by deleting the line break that precedes it.
    self.delete_range(self.cursor - 1, self.cursor)
  }
}

///|
/// Move the cursor one wrapped row up or down, keeping a preferred display
/// column. Unlike logical-line movement this steps between the soft-wrapped rows
/// of a single long line, matching how the composer is drawn.
pub fn Model::move_vertical(self : Model, delta : Int) -> Unit {
  let rows = visual_rows_for(self.text, self.content_width)
  let (index, offset) = resolve_cursor(
    rows,
    self.cursor_point(),
    self.at_wrap_end,
  )
  let current_column = @text.display_width(
    @text.grapheme_slice(rows[index].text, 0, offset),
  )
  let preferred = self.preferred_column.unwrap_or(current_column)
  let target_index = (index + delta).clamp(min=0, max=rows.length() - 1)
  let target = rows[target_index]
  let target_offset = place_display_column(target.text, preferred)
  let cursor = line_start_cursor(self.text, target.logical_line) +
    target.start_column +
    target_offset
  // Landing at the far edge of a non-final wrapped row sits on a boundary that
  // textually equals the next row's start; remember the affinity so it renders
  // at the end of this row instead of jumping down.
  let lands_on_wrap_boundary = target_index + 1 < rows.length() &&
    rows[target_index + 1].logical_line == target.logical_line &&
    target_offset == @text.grapheme_count(target.text)
  self.set_state(
    self.text,
    cursor,
    Some(preferred),
    self.view_start,
    mode=self.mode,
    at_wrap_end=lands_on_wrap_boundary,
  )
}
