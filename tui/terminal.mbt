///|
fn Ui::composer_surface(
  self : Ui,
  cols~ : Int,
  rows~ : Int,
) -> @surface.Surface {
  @render.composer_surface(
    self.composer,
    activity=self.activity,
    queued_inputs=self.queued_inputs,
    status=self.status,
    notice=self.notice,
    cols~,
    max_rows=rows,
  )
}

///|
async fn Ui::redraw_frame(self : Ui, viewport : @viewport.Viewport) -> Unit {
  viewport.redraw(
    self.tty,
    self.composer_surface(cols=viewport.cols(), rows=viewport.rows()),
  )
}

///|
async fn Ui::redraw(self : Self) -> Unit {
  // Redraws only run inside `with_entered`'s body, so a missing viewport is a
  // lifecycle bug — surface it rather than silently skipping the draw.
  guard self.viewport is Some(viewport) else {
    abort("redraw without an entered UI")
  }
  viewport.refresh_size(self.tty)
  self.redraw_frame(viewport)
}

///|
/// Lay out one transcript item, prefixed with a blank separator row so items
/// are visually spaced apart (matching the Codex TUI). The separator is plain,
/// outside any item background block.
fn item_rows(doc : @doc.Doc, cols~ : Int) -> Array[@surface.Line] {
  let rows : Array[@surface.Line] = [@surface.Line::new([])]
  for row in doc.layout(width=cols) {
    rows.push(row)
  }
  rows
}

///|
fn Ui::transcript_rows(self : Self, cols~ : Int) -> Array[@surface.Line] {
  let rows : Array[@surface.Line] = []
  for doc in self.transcript {
    for row in item_rows(doc, cols~) {
      rows.push(row)
    }
  }
  rows
}

///|
async fn Ui::redraw_after_resize(self : Self) -> Unit {
  guard self.viewport is Some(viewport) else {
    abort("resize without an entered UI")
  }
  viewport.refresh_size(self.tty)
  viewport.replay_scrollback(
    self.tty,
    scrollback=self.transcript_rows(cols=viewport.cols()),
    surface=self.composer_surface(cols=viewport.cols(), rows=viewport.rows()),
  )
}

///|
/// Anchor and draw the first frame. `enter` queries the terminal cursor, so this
/// must run before the tty reader starts (see `with_entered`).
async fn Ui::enter(self : Self) -> Unit {
  let size = @viewport.read_terminal_size(self.tty)
  self.viewport = Some(
    @viewport.Viewport::enter(
      self.tty,
      size~,
      surface=self.composer_surface(cols=size.cols(), rows=size.rows()),
      timeout_ms=self.config.esc_timeout_ms,
    ),
  )
}

///|
/// Append a styled `Doc` to the permanent transcript: insert its rows into the
/// terminal scrollback above the live area, then redraw the live frame. Runs on
/// the command queue so it serializes with other redraws.
async fn Ui::append_transcript(self : Self, doc : @doc.Doc) -> Unit {
  self.commands.wait(() => {
    self.transcript.push(doc)
    guard self.viewport is Some(viewport) else {
      abort("append without an entered UI")
    }
    viewport.refresh_size(self.tty)
    viewport.insert_before(self.tty, item_rows(doc, cols=viewport.cols()))
    self.redraw_frame(viewport)
  })
}

///|
/// Project a semantic `TranscriptItem` to a `Doc` and append it to the
/// transcript via `append_transcript`.
pub async fn Ui::append_item(self : Self, item : TranscriptItem) -> Unit {
  self.append_transcript(@doc.ToDoc::to_doc(item))
}

///|
/// The terminal width in columns as of the last redraw, or a conservative 80
/// before the UI has entered the live screen. Lets callers fit transient
/// content (e.g. a streaming tail preview) to the row the renderer will clip
/// it to.
pub fn Ui::columns(self : Self) -> Int {
  match self.viewport {
    Some(viewport) => viewport.cols()
    None => 80
  }
}

///|
/// Set or clear the transient activity label shown above the composer. `Some`
/// shows a busy/progress line that never enters the transcript; `None` hides it.
/// Redraws the live frame.
pub async fn Ui::set_activity(self : Self, activity : @doc.Text?) -> Unit {
  self.commands.wait(() => {
    self.activity = activity
    self.redraw()
  })
}

///|
/// Replace the list of queued inputs shown in the live area (copied defensively)
/// and redraw the frame.
pub async fn Ui::set_queued_inputs(self : Self, inputs : Array[Input]) -> Unit {
  self.commands.wait(() => {
    self.queued_inputs = inputs.copy()
    self.redraw()
  })
}

///|
/// Set the persistent status line below the composer and redraw. Transient input
/// notices may temporarily override its display until the next input event.
pub async fn Ui::set_status(self : Self, status : @doc.Text) -> Unit {
  self.commands.wait(() => {
    self.status = status
    self.redraw()
  })
}

///|
async fn Ui::leave(self : Self) -> Unit {
  guard self.viewport is Some(viewport) else { return }
  self.viewport = None
  viewport.refresh_size(self.tty)
  viewport.leave(self.tty)
}
