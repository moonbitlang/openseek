///|
struct Ui {
  tty : @tty.Tty
  config : Config
  // The live viewport, or `None` before `enter` has placed it (and after
  // `leave`). Present exactly when the UI is entered.
  mut viewport : @viewport.Viewport?
  composer : @composer.Model
  history : @history.History
  transcript : Array[@doc.Doc]
  mut activity : @doc.Text?
  mut queued_inputs : Array[Input]
  mut status : @doc.Text
  mut notice : @doc.Text?
  commands : @task.Queue
  events : @aqueue.Queue[Result[Event, Error]]
}

///|
fn Ui::new(tty : @tty.Tty, config : Config) -> Ui {
  let composer = @composer.Model::new(
    "",
    max_text_rows=config.composer_max_rows,
  )
  {
    tty,
    config,
    viewport: None,
    composer,
    history: @history.History::new(),
    transcript: [],
    activity: None,
    queued_inputs: [],
    status: @doc.Text::plain(""),
    notice: None,
    commands: Queue(kind=Unbounded),
    events: Queue(kind=Unbounded),
  }
}

///|
/// Run `body` with the live UI entered: draw the first frame up front and always
/// restore the terminal afterwards, on both the success and error paths. Enter
/// and leave run on the command queue so they serialize with redraws.
async fn[T] Ui::with_entered(self : Self, body : async () -> T) -> T {
  self.commands.wait(() => self.enter())
  try body() catch {
    error => {
      self.commands.wait(() => self.leave())
      raise error
    }
  } noraise {
    value => {
      self.commands.wait(() => self.leave())
      value
    }
  }
}

///|
async fn[T] run_ui_session(ui : Ui, body : async (Ui) -> T) -> T {
  @async.with_task_group() <| g => {
    g.spawn_bg(no_wait=true) <| () => { ui.commands.run() }
    ui.with_entered(() => {
      // `enter` drew the first frame, querying cursor position through tty input.
      // Start the reader only now, so it cannot consume that response as a key.
      g.spawn_bg(no_wait=true) <| () => { ui.read_tty_events() }
      body(ui)
    })
  }
}

///|
async fn Ui::put_event_result(self : Ui, result : Result[Event, Error]) -> Unit {
  self.events.put(result) catch {
    @aqueue.QueueAlreadyClosed => ()
    error => raise error
  }
}

///|
async fn Ui::read_tty_events(self : Ui) -> Unit {
  for ;; {
    let tty_event = self.tty.read_event(
      esc_timeout_ms=self.config.esc_timeout_ms,
    ) catch {
      @async/io.ReaderClosed => {
        self.put_event_result(Ok(Quit))
        self.events.close()
        return
      }
      error if @async.is_being_cancelled() => raise error
      error => {
        self.put_event_result(Err(error))
        self.events.close()
        return
      }
    }
    let event = self.commands.wait(() => self.handle_tty_event(tty_event)) catch {
      error if @async.is_being_cancelled() => raise error
      error => {
        self.put_event_result(Err(error))
        self.events.close()
        return
      }
    }
    if event is Some(event) {
      self.put_event_result(Ok(event))
    }
  }
}

///|
/// Open a terminal session, run `body` with a live `Ui`, and always restore the
/// terminal afterwards. Opens the tty in raw mode, requests the kitty keyboard
/// "disambiguate" enhancement (gracefully ignored where unsupported), draws the
/// first frame, then spawns the command queue and tty reader for the duration of
/// `body`.
pub async fn[T] with_ui(
  config? : Config = Config::new(),
  body : async (Ui) -> T,
) -> T {
  let tty = @tty.Tty::open()
  defer tty.close()
  let ui = Ui::new(tty, config)
  // Request the kitty keyboard protocol's "disambiguate" level so modified keys
  // the legacy encoding cannot represent — Shift+Enter, Alt+F/Alt+B — are
  // reported as distinct CSI-u events. We deliberately avoid the higher levels
  // that also report key-release events, which would double-fire every key.
  // Terminals without kitty support ignore the request and degrade gracefully.
  let flags = @tty.KeyboardEnhancementFlags::disambiguate()
  tty.with_raw_mode() <| () => {
    tty.with_keyboard_enhancements(flags) <| () => { run_ui_session(ui, body) }
  }
}
