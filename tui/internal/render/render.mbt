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
    @surface.Span::new(
      String::make(cols, '─'),
      style=@doc.Style::dim().to_surface(),
    ),
  ])
}

///|
fn input_style() -> @surface.Style {
  @doc.Style::default().to_surface()
}

///|
fn prompt_style() -> @surface.Style {
  @doc.Style::prompt().to_surface()
}

///|
fn prompt_line(prefix~ : String, line~ : String, cols~ : Int) -> @surface.Line {
  let prefix_width = @text.display_width(prefix)
  let content = @text.truncate_line(line, cols - prefix_width)
  let used = prefix_width + @text.display_width(content)
  let fill_cols = if used < cols { cols - used } else { 0 }
  @surface.Line::new([
    @surface.Span::new(prefix, style=prompt_style()),
    @surface.Span::new(content, style=input_style()),
    @surface.Span::new(String::make(fill_cols, ' '), style=input_style()),
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
/// Lay the composer area out for `cols` columns.
///
/// `queued_inputs` are any queued follow-up inputs, previewed above the
/// composer. `activity` is an optional in-progress block drawn between them and
/// the composer border. `status`/`notice` form the bottom status line, with
/// `notice` taking precedence when present.
pub fn composer_surface(
  composer : @composer.Model,
  activity~ : @doc.Text?,
  queued_inputs~ : Array[@core.Input],
  status~ : @doc.Text,
  notice~ : @doc.Text?,
  cols~ : Int,
) -> @surface.Surface {
  let rows : Array[@surface.Line] = []
  for row in queued_input_rows(queued_inputs, cols~) {
    rows.push(row)
  }
  if activity is Some(activity) {
    rows.push(@surface.Line::new([]))
    rows.push(activity.first_line(width=cols))
    rows.push(@surface.Line::new([]))
  }
  // Lay the composer out for the current width so soft-wrapping, scrolling, and
  // cursor placement below all agree with what we draw.
  composer.resize(cols~)
  let composer_top = rows.length()
  rows.push(separator_line(cols~))
  for row in 0..<composer.visible_text_rows() {
    rows.push(
      prompt_line(
        prefix=composer.input_prefix(row),
        line=composer.visible_line(row),
        cols~,
      ),
    )
  }
  rows.push(separator_line(cols~))
  rows.push(status_line(status, notice, cols~))
  @surface.Surface::new(
    width=cols,
    rows~,
    cursor=@surface.Cursor::new(
      row=composer_top + 1 + composer.cursor_row(),
      col=composer.cursor_offset(),
    ),
  )
}
