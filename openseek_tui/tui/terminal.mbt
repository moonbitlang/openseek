///|
fn Ui::composer_surface(
  self : Ui,
  cols~ : Int32,
  rows~ : Int32,
) -> @surface.Surface {
  let completion = match self.completion_menu() {
    Some(menu) if !self.completion.dismissed =>
      @completion.Model::open(
        items=menu.items,
        selected=self.completion.selected,
      )
    _ => @completion.Model::closed()
  }
  @render.composer_surface(
    self.composer,
    activity=self.activity,
    queued_inputs=self.queued_inputs,
    completion~,
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
  // Redraws only run while `run_ui_session` has the UI entered, so a missing
  // viewport is a lifecycle bug — surface it rather than silently skipping the
  // draw.
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
fn item_rows(doc : @doc.Doc, cols~ : Int32) -> Array[@surface.Line] {
  [Line([]), ..doc.layout(width=cols)]
}

///|
fn Ui::transcript_rows(self : Self, cols~ : Int32) -> Array[@surface.Line] {
  let rows : Array[@surface.Line] = []
  for doc in self.transcript {
    rows.append(item_rows(doc, cols~))
  }
  rows
}

///|
async fn Ui::redraw_after_resize(self : Self, size : @tty.WindowSize) -> Unit {
  guard self.viewport is Some(viewport) else {
    abort("resize without an entered UI")
  }
  viewport.refresh_size_after_resize(
    self.tty,
    rows=size.rows,
    cols=size.cols,
    timeout_ms=self.config.esc_timeout_ms,
  )
  viewport.replay_scrollback(
    self.tty,
    scrollback=self.transcript_rows(cols=viewport.cols()),
    surface=self.composer_surface(cols=viewport.cols(), rows=viewport.rows()),
  )
}

///|
/// Anchor and draw the first frame. `enter` queries the terminal cursor, so this
/// must run before the tty reader starts (see `run_ui_session`).
async fn Ui::enter(self : Self) -> Unit {
  let size = @viewport.read_terminal_size(self.tty)
  let viewport = @viewport.Viewport::enter(
    self.tty,
    size~,
    surface=(cols, rows) => self.composer_surface(cols~, rows~),
    timeout_ms=self.config.esc_timeout_ms,
  )
  self.viewport = Some(viewport)
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
pub fn Ui::columns(self : Self) -> Int32 {
  match self.viewport {
    Some(viewport) => viewport.cols()
    None => 80
  }
}

///|
/// Whether the user is not interacting with the input surface at all: no
/// draft text, plain input mode, and no submitted event still in flight
/// toward the app's queue. Shell mode counts as engaged even with an empty
/// buffer — a user sitting at a bare `! ` prompt is mid-composition — and so
/// does the reset-to-delivery window of a just-pressed Enter (the submit
/// helpers await a redraw between clearing the composer and returning the
/// event, so an empty composer alone can lie about pending input). Lets a
/// scheduler (e.g. `/loop`) avoid starting a turn under, or ahead of, the
/// user — the composer is private to the UI, so the update loop cannot see
/// any of this directly.
pub fn Ui::input_idle(self : Self) -> Bool {
  self.pending_submissions == 0 &&
  self.composer.text().is_empty() &&
  self.composer.mode().is_input()
}

///|
/// The app's event reader confirms one submitted event has reached its
/// message queue and is visible to queue drains. Called once per delivered
/// *submission* event (a prompt, queued input, or slash command) — rapid
/// submits can stack several in the UI's internal event queue while the app
/// loop is busy, so deliveries and submissions must pair one-to-one. The
/// floor guards a spurious call; it must never mask a real pending submit.
pub fn Ui::submission_delivered(self : Self) -> Unit {
  self.pending_submissions = (self.pending_submissions - 1).max(0)
}

///|
/// Replace the live view around the composer — the persistent status line
/// below it, the transient activity line above it (`None` hides it; it never
/// enters the transcript), and the queued-inputs preview (copied defensively)
/// — then redraw the frame once.
///
/// The whole view is set together because that is how an update loop works:
/// it derives every live element from its state each turn. Per-field setters
/// would queue one full-frame repaint each — three per loop turn — which
/// during a streaming burst is the difference between a calm frame and a
/// flickering one. Transient input notices may temporarily override the
/// status display until the next input event.
pub async fn Ui::set_live_view(
  self : Self,
  status~ : @doc.Text,
  activity~ : @doc.Text?,
  queued_inputs~ : Array[Input],
) -> Unit {
  self.commands.wait(() => {
    self.status = status
    self.activity = activity
    self.queued_inputs = queued_inputs.copy()
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
