///|
const MinTextRows : Int = 1

///|
/// Default cap on how many editable rows the composer grows to before it
/// scrolls instead of growing further.
pub const DefaultMaxTextRows : Int = 4

///|
/// Display width of the prompt prefix (`> `, `! `, or the `  ` continuation),
/// which is always two columns. Every wrapped composer row reserves this much.
const PromptWidth : Int = 2

///|
/// Editable content width for a composer rendered at `cols` terminal columns,
/// i.e. the room left once the two-column prompt prefix is reserved.
fn compute_content_width(cols~ : Int) -> Int {
  let width = cols - PromptWidth
  width.max(1)
}

///|
/// Content width assumed before the composer has been laid out against a real
/// terminal. The renderer calls `Model::resize` on every frame, so this only
/// governs editing that happens before the first draw.
const DefaultContentWidth : Int = 78

///|
/// Number of editable rows to render for `total` wrapped rows, clamped between
/// one and `max_text_rows`.
fn compute_visible_count(total~ : Int, max_text_rows~ : Int) -> Int {
  let max_text_rows = max_text_rows.max(MinTextRows)
  total.clamp(min=MinTextRows, max=max_text_rows)
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
let exclaimation_prefix : @displaytext.DisplayText = DisplayText("! ")

///|
fn Mode::prompt_prefix(self : Mode) -> @displaytext.DisplayText {
  match self {
    Input => @core.prompt_prefix
    Shell => exclaimation_prefix
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
/// Mutable state model for the multiline composer.
///
/// `Model` owns the user-editable text, cursor position, semantic mode, the
/// editable content width, the maximum rows the composer may grow to, and the
/// first visible wrapped row. Because it knows its own width it soft-wraps long
/// logical lines and navigates by on-screen row like a text editor. It does not
/// emit terminal sequences; terminal anchoring and rendering belong to `Ui`.
struct Model {
  mut text : String
  // Cached layout state. Edits replace the arrays as a unit; wrapping then
  // refreshes each logical line's row_start/row_end metadata for cursor lookup.
  mut logical_lines : Array[LogicLine]
  mut visual_rows : Array[VisualRow]
  mut cursor : TextCursor
  mut preferred_column : Int?
  mut view_start : Int
  // Affinity for a cursor that lands on a soft-wrap boundary: when true the
  // cursor belongs to the end of the earlier wrapped row, not the start of the
  // next one. Set by vertical movement, reset by every other edit.
  mut at_wrap_end : Bool
  mut content_width : Int
  max_text_rows : Int
  // The live cap on visible rows, narrowed by `resize` to the terminal's budget
  // so the composer fits alongside its chrome on a short terminal. Always
  // `<= max_text_rows`.
  mut visible_cap : Int
  mut mode : Mode
}

///|
/// Create an `Input` mode composer initialized with `text` whose editable area
/// grows to at most `max_text_rows` wrapped rows.
pub fn Model::new(
  text : String,
  max_text_rows? : Int = DefaultMaxTextRows,
) -> Model {
  let max_text_rows = max_text_rows.max(MinTextRows)
  let content_width = DefaultContentWidth
  let logical_lines = split_logical_lines(text)
  let visual_rows = wrap_visual_rows(logical_lines, content_width~)
  let cursor = TextCursor::text_end(logical_lines)
  let model = {
    text,
    logical_lines,
    visual_rows,
    cursor,
    preferred_column: None,
    view_start: 0,
    at_wrap_end: false,
    content_width,
    max_text_rows,
    visible_cap: max_text_rows,
    mode: Input,
  }
  // The scroll offset depends on how the text wraps, so resolve it once now and
  // keep it current after every edit and resize.
  model.reclamp_view()
  model
}

///|
/// Clear the composer back to empty `Input` mode, resetting the cursor and
/// scroll window.
pub fn Model::reset(self : Model) -> Unit {
  self.replace("", mode=Input)
}

///|
/// Replace the entire buffer with `text` in `mode`, placing the cursor at the
/// end and scrolling the view back to the top. Used to load history entries.
pub fn Model::replace(self : Model, text : String, mode~ : Mode) -> Unit {
  let logical_lines = split_logical_lines(text)
  self.set_logical_lines(
    logical_lines~,
    cursor=TextCursor::text_end(logical_lines),
    view_start=0,
    mode~,
  )
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
  compute_visible_count(
    total=self.visual_rows.length(),
    max_text_rows=self.visible_cap,
  )
}

///|
/// Return the wrapped input segment displayed at a composer row.
///
/// `row` is relative to the visible composer text area, not the terminal.
pub fn Model::visible_line(
  self : Model,
  row : Int,
) -> @displaytext.DisplayText? {
  let index = self.view_start + row
  if index < 0 || index >= self.visual_rows.length() {
    None
  } else {
    Some(self.visual_rows[index].display)
  }
}

///|
/// Return the prompt prefix for a visible composer row at `cols` columns.
///
/// Only the very first wrapped row of the first logical input line gets `❯ ` or
/// `! `. Every other row — later logical lines and soft-wrapped continuations
/// alike — uses two spaces so wrapped content lines up with the editable text.
pub fn Model::input_prefix(self : Model, row : Int) -> @displaytext.DisplayText {
  let index = self.view_start + row
  if index >= 0 &&
    index < self.visual_rows.length() &&
    index >= self.logical_lines[0].row_start &&
    index < self.logical_lines[0].row_end &&
    self.visual_rows[index].logic_start == self.logical_lines[0].display.start() {
    self.mode.prompt_prefix()
  } else {
    DisplayText("  ")
  }
}

///|
/// Resolve the current cursor to its wrapped-row index for the live layout.
fn Model::resolve_cursor_index(self : Model) -> Int {
  resolve_cursor(
    self.logical_lines,
    rows=self.visual_rows,
    cursor=self.cursor,
    at_wrap_end=self.at_wrap_end,
  )
}

///|
/// Cursor row within the visible composer text area.
///
/// The row is measured in wrapped rows and clamped to the current visible row
/// count, so terminal renderers can move relative to the current composer
/// surface even when the underlying cursor is temporarily outside the window.
pub fn Model::cursor_row(self : Model) -> Int {
  let visible = compute_visible_count(
    total=self.visual_rows.length(),
    max_text_rows=self.visible_cap,
  )
  let index = self.resolve_cursor_index()
  let row = index - self.view_start
  row.clamp(min=0, max=visible - 1)
}

///|
/// Whether the cursor is on the first wrapped row of the composer.
///
/// Vertical-up at this row hands off to history recall rather than moving within
/// the buffer, so wrapped continuation rows count as interior rows here.
pub fn Model::cursor_at_first_visual_row(self : Model) -> Bool {
  self.resolve_cursor_index() == 0
}

///|
/// Whether the cursor is on the last wrapped row of the composer.
pub fn Model::cursor_at_last_visual_row(self : Model) -> Bool {
  self.resolve_cursor_index() == self.visual_rows.length() - 1
}

///|
/// Cursor column offset within the terminal row that contains the cursor.
///
/// The result is a display-cell offset from column 1, including the prompt
/// prefix width, and is measured within the cursor's wrapped segment so it stays
/// correct when a long line soft-wraps. It is based on `DisplayText` column
/// measurement, not byte length.
pub fn Model::cursor_offset(self : Model) -> Int {
  let index = self.resolve_cursor_index()
  let row = self.visual_rows[index]
  let line = self.logical_lines[self.cursor.line]
  PromptWidth +
  line.display_column(position=self.cursor.position) -
  line.display_column(position=row.logic_start)
}

///|
fn Model::set_logical_lines(
  self : Model,
  logical_lines~ : Array[LogicLine],
  cursor~ : TextCursor,
  view_start~ : Int,
  preferred_column? : Int,
  mode~ : Mode,
  at_wrap_end? : Bool = false,
) -> Unit {
  let logical_lines = if logical_lines is [] {
    split_logical_lines("")
  } else {
    logical_lines
  }
  let visual_rows = wrap_visual_rows(
    logical_lines,
    content_width=self.content_width,
  )
  let cursor = TextCursor::new(
    logical_lines,
    line=cursor.line,
    position=cursor.position,
  )
  self.text = join_logical_lines(logical_lines)
  self.logical_lines = logical_lines
  self.visual_rows = visual_rows
  self.cursor = cursor
  self.preferred_column = preferred_column
  self.view_start = view_start.max(0)
  self.mode = mode
  self.at_wrap_end = at_wrap_end
  // The text or cursor may have moved; pull the scroll window back over the
  // cursor for the current width.
  self.reclamp_view()
}

///|
fn Model::set_cursor(
  self : Model,
  cursor~ : TextCursor,
  preferred_column? : Int,
  at_wrap_end? : Bool = false,
) -> Unit {
  self.cursor = TextCursor::new(
    self.logical_lines,
    line=cursor.line,
    position=cursor.position,
  )
  self.preferred_column = preferred_column
  self.at_wrap_end = at_wrap_end
  self.reclamp_view()
}

///|
/// Re-clamp `view_start` so the cursor's wrapped row stays visible at the
/// current content width. Called after every edit, move, and resize.
fn Model::reclamp_view(self : Model) -> Unit {
  let total = self.visual_rows.length()
  let visible = compute_visible_count(total~, max_text_rows=self.visible_cap)
  let max_start = (total - visible).max(0)
  let cursor_row_index = self.resolve_cursor_index()
  let mut start = self.view_start.clamp(min=0, max=max_start)
  if cursor_row_index < start {
    start = cursor_row_index
  } else if cursor_row_index >= start + visible {
    start = cursor_row_index - visible + 1
  }
  self.view_start = start.clamp(min=0, max=max_start)
}

///|
/// Lay the composer out for a terminal `cols` columns wide. The renderer calls
/// this each frame so soft-wrapping and vertical movement track the live width.
///
/// `max_rows` is the live row budget available to the composer. The cap narrows
/// the configured ceiling so the composer fits its surrounding chrome on a
/// short terminal. Omitting it restores the configured ceiling.
pub fn Model::resize(self : Model, cols~ : Int, max_rows? : Int) -> Unit {
  self.visible_cap = match max_rows {
    Some(max_rows) => max_rows.clamp(min=MinTextRows, max=self.max_text_rows)
    None => self.max_text_rows
  }
  self.content_width = compute_content_width(cols~)
  self.visual_rows = wrap_visual_rows(
    self.logical_lines,
    content_width=self.content_width,
  )
  self.reclamp_view()
}

///|
fn Model::replace_line_range(
  self : Model,
  line_index~ : Int,
  start~ : @displaytext.TextualPosition,
  end~ : @displaytext.TextualPosition,
  replacement~ : String,
) -> Unit {
  let line = self.logical_lines[line_index]
  let prefix = line.display.view(line.display.start(), start)
  let suffix = line.display.view(end, line.display.end())
  let cursor_text = "\{prefix}\{replacement}"
  let new_line = LogicLine::new(DisplayText("\{cursor_text}\{suffix}"))
  let replacement_lines = [new_line]
  let logical_lines = splice_logical_lines(
    self.logical_lines,
    start=line_index,
    delete_count=1,
    inserted=replacement_lines,
  )
  self.set_logical_lines(
    logical_lines~,
    cursor=TextCursor::new(
      logical_lines,
      line=line_index,
      position=new_line.display.textual_position_at_char(
        offset=cursor_text.length(),
      ),
    ),
    view_start=self.view_start,
    mode=self.mode,
  )
}

///|
fn Model::join_with_next_line(self : Model, line_index~ : Int) -> Unit {
  if line_index < 0 || line_index + 1 >= self.logical_lines.length() {
    self.set_cursor(cursor=self.cursor)
  } else {
    let left = self.logical_lines[line_index].text()
    let right = self.logical_lines[line_index + 1].text()
    let joined = LogicLine::new(DisplayText("\{left}\{right}"))
    let replacement_lines = [joined]
    let logical_lines = splice_logical_lines(
      self.logical_lines,
      start=line_index,
      delete_count=2,
      inserted=replacement_lines,
    )
    self.set_logical_lines(
      logical_lines~,
      cursor=TextCursor::new(
        logical_lines,
        line=line_index,
        position=joined.display.textual_position_at_char(offset=left.length()),
      ),
      view_start=self.view_start,
      mode=self.mode,
    )
  }
}

///|
fn Model::remove_current_empty_line(self : Model) -> Unit {
  if self.cursor.line <= 0 || !self.logical_lines[self.cursor.line].is_empty() {
    self.set_cursor(cursor=self.cursor)
  } else {
    let logical_lines = splice_logical_lines(
      self.logical_lines,
      start=self.cursor.line,
      delete_count=1,
      inserted=[],
    )
    self.set_logical_lines(
      logical_lines~,
      cursor=TextCursor::line_end(logical_lines, line=self.cursor.line - 1),
      view_start=self.view_start,
      mode=self.mode,
    )
  }
}

///|
/// Insert `text` at the cursor and advance the cursor to the nearest legal
/// display boundary after the inserted text.
pub fn Model::insert(self : Model, text : String) -> Unit {
  // Splice only the current logical line. The cursor splits that line into:
  //
  //   before cursor | after cursor
  //        ab       |      cd
  //
  // Inserting "x\ny" turns it into replacement logical lines:
  //
  //   abx
  //   ycd
  //
  // Single-line inserts are the same splice with one replacement line.
  let line = self.logical_lines[self.cursor.line]
  let prefix = line.display.view(line.display.start(), self.cursor.position)
  let suffix = line.display.view(self.cursor.position, line.display.end())
  let inserted = @displaytext.split_lines(text)
  let last = inserted.length() - 1
  let replacement_lines : Array[LogicLine] = []
  for index, inserted_line in inserted {
    let inserted_text = inserted_line.view(
      inserted_line.start(),
      inserted_line.end(),
    )
    let replacement_line = if inserted.length() == 1 {
      LogicLine::new(DisplayText("\{prefix}\{inserted_text}\{suffix}"))
    } else if index == 0 {
      LogicLine::new(DisplayText("\{prefix}\{inserted_text}"))
    } else if index == last {
      LogicLine::new(DisplayText("\{inserted_text}\{suffix}"))
    } else {
      LogicLine::new(inserted_line)
    }
    replacement_lines.push(replacement_line)
  }
  let cursor_line = self.cursor.line + last
  // Char (code-unit) count of the portion before the cursor in the last
  // replacement line. Using char count rather than display columns avoids the
  // non-additivity trap: if the tail of the inserted text combines with the
  // first char of the suffix (e.g. Arabic lam-alef), a column-based lookup
  // would overshoot into the suffix. `textual_position_at_char` snaps back to
  // the start of any display unit that spans the insertion boundary.
  let cursor_chars = if inserted.length() == 1 {
    prefix.length() + inserted[0].text().length()
  } else {
    inserted[last].text().length()
  }
  let logical_lines = splice_logical_lines(
    self.logical_lines,
    start=self.cursor.line,
    delete_count=1,
    inserted=replacement_lines,
  )
  self.set_logical_lines(
    logical_lines~,
    cursor=TextCursor::new(
      logical_lines,
      line=cursor_line,
      position=replacement_lines[last].display.textual_position_at_char(
        offset=cursor_chars,
      ),
    ),
    view_start=self.view_start,
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
  // Drop terminal-control bytes (pasted ANSI escapes, stray `\r`, tabs) before
  // they reach the model, so the live echo can never mutate the terminal and
  // the cursor math stays consistent with what is drawn.
  let text = @text.sanitize(text)
  if self.mode.is_input() &&
    self.text.length() == 0 &&
    self.cursor.line == 0 &&
    self.cursor.is_line_start(self.logical_lines) &&
    text is ['!', .. rest] {
    let logical_lines = split_logical_lines(rest)
    self.set_logical_lines(
      logical_lines~,
      cursor=TextCursor::text_end(logical_lines),
      view_start=self.view_start,
      mode=Shell,
    )
  } else {
    self.insert(text)
  }
}

///|
/// Delete the display unit before the cursor (Backspace). At the start of the
/// buffer this is a no-op that also normalizes the mode back to `Input`.
pub fn Model::delete_before(self : Model) -> Unit {
  if self.cursor.line == 0 && self.cursor.is_line_start(self.logical_lines) {
    self.mode = Input
    self.set_cursor(cursor=TextCursor::line_start(self.logical_lines, line=0))
  } else if self.cursor.is_line_start(self.logical_lines) {
    self.join_with_next_line(line_index=self.cursor.line - 1)
  } else {
    let previous = move_cursor_left(self.logical_lines, self.cursor)
    self.replace_line_range(
      line_index=self.cursor.line,
      start=previous.position,
      end=self.cursor.position,
      replacement="",
    )
  }
}

///|
/// Delete the display unit at the cursor (Delete / Ctrl-D). At the end of the
/// buffer this is a no-op.
pub fn Model::delete_after(self : Model) -> Unit {
  if self.cursor.is_line_end(self.logical_lines) {
    if self.cursor.line + 1 < self.logical_lines.length() {
      self.join_with_next_line(line_index=self.cursor.line)
    } else {
      self.set_cursor(cursor=self.cursor)
    }
  } else {
    let next = move_cursor_right(self.logical_lines, self.cursor)
    self.replace_line_range(
      line_index=self.cursor.line,
      start=self.cursor.position,
      end=next.position,
      replacement="",
    )
  }
}

///|
/// Move the cursor one display unit left, crossing line breaks. Clamped at the
/// start of the buffer.
pub fn Model::move_left(self : Model) -> Unit {
  self.set_cursor(cursor=move_cursor_left(self.logical_lines, self.cursor))
}

///|
/// Move the cursor one display unit right, crossing line breaks. Clamped at the
/// end of the buffer.
pub fn Model::move_right(self : Model) -> Unit {
  self.set_cursor(cursor=move_cursor_right(self.logical_lines, self.cursor))
}

///|
/// Move the cursor to the end of the next word: skip any leading delimiters,
/// then the run of word units. Matches readline's `forward-word` (Alt-F).
pub fn Model::move_word_right(self : Model) -> Unit {
  self.set_cursor(
    cursor=move_cursor_word_right(self.logical_lines, self.cursor),
  )
}

///|
/// Move the cursor to the start of the previous word: skip any trailing
/// delimiters, then the run of word units. Matches readline's `backward-word`
/// (Alt-B).
pub fn Model::move_word_left(self : Model) -> Unit {
  self.set_cursor(cursor=move_cursor_word_left(self.logical_lines, self.cursor))
}

///|
/// Move the cursor to the start of its current logical line (Home / Ctrl-A),
/// not the start of the wrapped row.
pub fn Model::move_home(self : Model) -> Unit {
  self.set_cursor(
    cursor=TextCursor::line_start(self.logical_lines, line=self.cursor.line),
  )
}

///|
/// Move the cursor to the end of its current logical line (End / Ctrl-E), past
/// any soft-wrapped rows of that line.
pub fn Model::move_end(self : Model) -> Unit {
  self.set_cursor(
    cursor=TextCursor::line_end(self.logical_lines, line=self.cursor.line),
  )
}

///|
/// Delete from the start of the current logical line up to the cursor (Ctrl-U).
pub fn Model::kill_before(self : Model) -> Unit {
  if self.cursor.is_line_start(self.logical_lines) {
    self.set_cursor(cursor=self.cursor)
  } else {
    self.replace_line_range(
      line_index=self.cursor.line,
      start=self.logical_lines[self.cursor.line].display.start(),
      end=self.cursor.position,
      replacement="",
    )
  }
}

///|
/// Delete from the cursor to the end of the current logical line (Ctrl-K).
///
/// When the cursor is already at the line's end, kill the following line break
/// so the next line joins up; on a trailing empty line with nothing ahead,
/// remove the line itself by deleting the preceding break. On a fully empty
/// buffer this is a no-op.
pub fn Model::kill_after(self : Model) -> Unit {
  if !self.cursor.is_line_end(self.logical_lines) {
    // Kill to the end of the current line's content.
    self.replace_line_range(
      line_index=self.cursor.line,
      start=self.cursor.position,
      end=self.logical_lines[self.cursor.line].display.end(),
      replacement="",
    )
  } else if self.cursor.line + 1 < self.logical_lines.length() {
    // Already at the end of the line (an empty line is its own end): kill the
    // line break so the next line joins up, matching readline/emacs kill-line.
    self.join_with_next_line(line_index=self.cursor.line)
  } else if self.cursor.line > 0 &&
    self.logical_lines[self.cursor.line].is_empty() {
    // A trailing empty line has no forward content to kill; remove the line
    // itself by deleting the line break that precedes it.
    self.remove_current_empty_line()
  }
}

///|
/// Move the cursor one wrapped row up or down, keeping a preferred display
/// column. Unlike logical-line movement this steps between the soft-wrapped rows
/// of a single long line, matching how the composer is drawn.
pub fn Model::move_vertical(self : Model, delta : Int) -> Unit {
  // Visual rows are slices of logical lines:
  //
  //   logical:  abcdefghij
  //             0    5    10 display columns
  //   rows:     abcde | fghij
  //
  // Moving vertically keeps the column within the wrapped slice, then converts
  // that display column back to a textual position on the target logical line.
  // If the position is exactly the right edge of a non-final slice, remember
  // `at_wrap_end` so the cursor renders on the upper row instead of the next
  // row's left edge; both are the same textual boundary.
  let index = self.resolve_cursor_index()
  let row = self.visual_rows[index]
  let line = self.logical_lines[self.cursor.line]
  let current_column = line.display_column(position=self.cursor.position) -
    line.display_column(position=row.logic_start)
  let preferred = self.preferred_column.unwrap_or(current_column)
  let target_index = (index + delta).clamp(
    min=0,
    max=self.visual_rows.length() - 1,
  )
  let target = self.visual_rows[target_index]
  let target_line_index = logic_line_at_row(
    self.logical_lines,
    row_index=target_index,
  )
  let target_line = self.logical_lines[target_line_index]
  let target_display_column = (target_line.display_column(
    position=target.logic_start,
  ) +
  preferred).clamp(
    min=target_line.display_column(position=target.logic_start),
    max=target_line.display_column(position=target.logic_end),
  )
  let target_position = target_line.position_at_display_column(
    column=target_display_column,
  )
  let target_cursor = TextCursor::new(
    self.logical_lines,
    line=target_line_index,
    position=target_position,
  )
  // Landing at the far edge of a non-final wrapped row sits on a boundary that
  // textually equals the next row's start; remember the affinity so it renders
  // at the end of this row instead of jumping down.
  let lands_on_wrap_boundary = target_index + 1 < target_line.row_end &&
    target_position == target.logic_end
  self.set_cursor(
    cursor=target_cursor,
    preferred_column=preferred,
    at_wrap_end=lands_on_wrap_boundary,
  )
}

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
fn visible_row_text(model : Model, row : Int) -> String {
  if model.visible_line(row) is Some(line) {
    line.text()
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

///|
pub extend Mode with Eq::{equal, not_equal}
