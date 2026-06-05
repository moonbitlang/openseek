// Lay the live composer area out into a render-data `@surface.Surface`.
//
// Given the editing `@composer.Model` plus styled status/activity text and any
// pre-rendered queued-input rows, `composer_surface` stacks the queued rows, an
// optional activity block, the bordered composer body, and the status line into
// one surface, and places the cursor on the active input row. It is the view
// layer for the composer: pure, terminal-agnostic, and performs no IO.
//
// Queued follow-up inputs are rendered into their preview block here (see
// queued.mbt); the editing model and the doc vocabulary cover the rest.

///|
fn separator_line(cols~ : Int) -> @surface.Line {
  @surface.Line::new([
    Span(DisplayText(String::make(cols, '─')), style=@style.dim),
  ])
}

///|
fn prompt_line(
  prefix~ : @displaytext.DisplayText,
  line~ : @displaytext.DisplayText,
  cols~ : Int,
) -> @surface.Line {
  let prefix_width = prefix.width()
  let content = @displaytext.DisplayText(line.truncate(cols - prefix_width))
  let used = prefix_width + content.width()
  let fill_cols = if used < cols { cols - used } else { 0 }
  let fill_cols = @displaytext.DisplayText(String::make(fill_cols, ' '))
  @surface.Line::new([
    Span(prefix, style=@style.dim),
    Span(content, style=@style.default),
    Span(fill_cols, style=@style.default),
  ])
}

///|
fn status_line(
  status : @doc.Text,
  notice : @doc.Text?,
  cols~ : Int,
) -> @surface.Line {
  notice.unwrap_or(status).first_line(width=cols)
}

///|
/// Prepend `indent` blank columns to a line so it lines up with the composer's
/// editable text (which starts after the prompt prefix), not the left edge.
fn indent_line(line : @surface.Line, indent~ : Int) -> @surface.Line {
  if indent <= 0 {
    return line
  }
  let indent = @displaytext.DisplayText(String::make(indent, ' '))
  let spans : Array[@surface.Span] = [Span(indent, style=@style.default)]
  for span in line.spans() {
    spans.push(span)
  }
  @surface.Line::new(spans)
}

///|
/// The shortest terminal the live area fits in without clipping: a spacer, two
/// separators, one composer row, and the status line.
const MinLiveRows : Int = 5

///|
/// A one-line notice shown in place of the composer when the terminal is too
/// short to render it without clipping the prompt or status.
fn too_small_surface(cols~ : Int) -> @surface.Surface {
  @surface.Surface::new(
    width=cols,
    rows=[
      @surface.Line::new([
        Span(
          DisplayText(
            @displaytext.DisplayText(
              "Terminal too small — resize to at least \{MinLiveRows} rows",
            ).truncate(cols),
          ),
          style=@style.error,
        ),
      ]),
    ],
    cursor=@surface.Cursor::new(row=0, col=0),
  )
}

///|
/// Lay the composer area out for `cols` columns.
///
/// `activity` is an optional in-progress block ("Working …") for the current
/// task; `queued_inputs` are the follow-ups that run after it. They render as one
/// group above the composer — activity first (present), then the queue (next) —
/// in temporal order. `status`/`notice` form the bottom status line, with
/// `notice` taking precedence when present.
///
/// `max_rows` is the live area's row budget (the terminal height). The queued
/// preview is bounded to whatever rows remain after the composer and its chrome,
/// so a long queue on a short terminal never clips the prompt the user is typing
/// into; the overflow collapses into a `… N more` line.
pub fn composer_surface(
  composer : @composer.Model,
  activity~ : @doc.Text?,
  queued_inputs~ : Array[@core.Input],
  status~ : @doc.Text,
  notice~ : @doc.Text?,
  cols~ : Int,
  max_rows~ : Int,
) -> @surface.Surface {
  // Below the minimum the prompt or status would be clipped, so show a notice
  // instead of a broken frame. This runs on every redraw, so it also covers a
  // live resize down to (and back up from) a too-short terminal.
  if max_rows < MinLiveRows {
    return too_small_surface(cols~)
  }
  // Status and activity rows have no prompt prefix, so indent them to the
  // composer's text column (after `❯ `) instead of the screen's left edge.
  let indent = composer.input_prefix(0).width()
  // Lay the composer out first, capped to the rows left after its mandatory
  // chrome (spacer + two separators + status), so a tall multiline draft scrolls
  // to the cursor instead of overflowing the budget. Its height then bounds the
  // queued preview below.
  composer.resize(cols~, max_rows=max_rows - (MinLiveRows - 1))
  let composer_rows = composer.visible_text_rows()
  // Rows that must always stay visible — the composer and its chrome: a spacer,
  // two separators, the composer itself, and the status line. The composer wins
  // the row budget; the activity line and queue get whatever is left over.
  let fixed = 1 + composer_rows + 2 + 1
  // Show the activity line only if it plus its trailing blank still fit, so a
  // very short terminal drops "Working …" rather than clipping the prompt.
  let show_activity = activity is Some(_) && max_rows >= fixed + 2
  // Reserve the activity line + its bracketing blanks (between + trailing) when
  // shown, otherwise just the queue's trailing blank.
  let chrome = if show_activity { 3 } else { 1 }
  let queued = queued_input_rows(
    queued_inputs,
    cols~,
    indent~,
    max_rows=max_rows - fixed - chrome,
  )
  let has_queue = queued.length() > 0
  let rows : Array[@surface.Line] = []
  // A blank spacer above the live area so the committed transcript does not butt
  // directly against the composer's top border — matching the blank that
  // precedes each transcript item.
  rows.push(@surface.Line::new([]))
  if show_activity && activity is Some(activity) {
    rows.push(indent_line(activity.first_line(width=cols - indent), indent~))
  }
  // Blank between the activity line and the queue, when both are present.
  if show_activity && has_queue {
    rows.push(@surface.Line::new([]))
  }
  for row in queued {
    rows.push(row)
  }
  // Set the live-status group off from the composer border with a blank.
  if show_activity || has_queue {
    rows.push(@surface.Line::new([]))
  }
  let composer_top = rows.length()
  rows.push(separator_line(cols~))
  for row in 0..<composer.visible_text_rows() {
    if composer.visible_line(row) is Some(line) {
      rows.push(prompt_line(prefix=composer.input_prefix(row), line~, cols~))
    }
  }
  rows.push(separator_line(cols~))
  rows.push(
    indent_line(status_line(status, notice, cols=cols - indent), indent~),
  )
  @surface.Surface::new(
    width=cols,
    rows~,
    cursor=@surface.Cursor::new(
      row=composer_top + 1 + composer.cursor_row(),
      col=composer.cursor_offset(),
    ),
  )
}
