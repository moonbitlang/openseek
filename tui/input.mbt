///|
fn submitted_input(text : String, mode : @composer.Mode) -> Input {
  if mode.is_shell() {
    Command("\{text.trim()}")
  } else {
    Prompt(text)
  }
}

///|
fn Ui::current_history_entry(self : Self) -> @history.Entry {
  @history.Entry::new(self.composer.text(), self.composer.mode())
}

///|
async fn Ui::submit_current_input(self : Self) -> Input? {
  if self.composer.text().length() == 0 && self.composer.mode().is_input() {
    self.notice = Some(@doc.dim_text("empty input"))
    self.redraw()
    None
  } else {
    let text = self.composer.text()
    let mode = self.composer.mode()
    self.history.push(@history.Entry::new(text, mode))
    self.composer.reset()
    self.notice = None
    self.completion.reset()
    self.redraw()
    Some(submitted_input(text, mode))
  }
}

///|
/// Readline redraws directly after each branch. Agentui keeps small local
/// helpers because most input changes also clear transient status text.
async fn Ui::redraw_after_cursor_move(self : Self) -> Unit {
  self.notice = None
  self.redraw()
}

///|
async fn Ui::redraw_after_text_change(self : Self) -> Unit {
  self.history.reset_navigation()
  self.completion.dismissed = false
  self.sync_completion_menu()
  self.notice = None
  self.redraw()
}

///|
async fn Ui::redraw_after_history_recall(self : Self) -> Unit {
  self.completion.dismissed = false
  self.sync_completion_menu()
  self.notice = None
  self.redraw()
}

///|
async fn Ui::recall_previous_history(self : Self) -> Unit {
  if self.history.previous(self.current_history_entry()) is Some(entry) {
    self.composer.replace(entry.text(), mode=entry.mode())
    self.redraw_after_history_recall()
  }
}

///|
async fn Ui::recall_next_history(self : Self) -> Unit {
  if self.history.next() is Some(entry) {
    self.composer.replace(entry.text(), mode=entry.mode())
    self.redraw_after_history_recall()
  }
}

///|
async fn Ui::move_up_or_recall_history(self : Self) -> Unit {
  if self.composer.cursor_at_first_visual_row() {
    self.recall_previous_history()
  } else {
    self.composer.move_vertical(-1)
    self.redraw_after_cursor_move()
  }
}

///|
async fn Ui::move_down_or_recall_history(self : Self) -> Unit {
  if self.composer.cursor_at_last_visual_row() {
    self.recall_next_history()
  } else {
    self.composer.move_vertical(1)
    self.redraw_after_cursor_move()
  }
}

///|
async fn Ui::handle_key(self : Self, key : @tty/input.KeyEvent) -> Event? {
  self.sync_completion_menu()
  // A modal picker (e.g. `/skills`) intercepts keys before the composer,
  // history, and completion menu see them.
  if self.picker_open() {
    return self.handle_picker_key(key)
  }
  match key.code {
    Char('a') if key.modifiers.ctrl() => {
      self.composer.move_home()
      self.redraw_after_cursor_move()
      None
    }
    Char('b') if key.modifiers.ctrl() => {
      self.composer.move_left()
      self.redraw_after_cursor_move()
      None
    }
    Char('c') if key.modifiers.ctrl() => {
      self.history.reset_navigation()
      Some(Interrupt)
    }
    Char('d') if key.modifiers.ctrl() =>
      if self.composer.text().length() == 0 {
        Some(Quit)
      } else {
        self.composer.delete_after()
        self.redraw_after_text_change()
        None
      }
    Char('e') if key.modifiers.ctrl() => {
      self.composer.move_end()
      self.redraw_after_cursor_move()
      None
    }
    Char('f') if key.modifiers.ctrl() => {
      self.composer.move_right()
      self.redraw_after_cursor_move()
      None
    }
    Char('f') if key.modifiers.alt() => {
      self.composer.move_word_right()
      self.redraw_after_cursor_move()
      None
    }
    Char('b') if key.modifiers.alt() => {
      self.composer.move_word_left()
      self.redraw_after_cursor_move()
      None
    }
    Char('h') if key.modifiers.ctrl() => {
      self.composer.delete_before()
      self.redraw_after_text_change()
      None
    }
    Enter if key.modifiers.shift() => {
      self.composer.insert("\n")
      self.redraw_after_text_change()
      None
    }
    Enter =>
      match
        ui_enter_decision(
          self.config.slash_commands,
          self.composer,
          self.completion,
          menu_visible=self.completion_menu_visible(),
        ) {
        RunSlashCommand(name~, arguments~) =>
          self.submit_slash_command(name~, arguments~)
        SubmitInput => self.submit_current_input().map(input => Steer(input))
        NoCompletionMatch => {
          self.notice = Some(@doc.dim_text("no matching completion"))
          self.redraw()
          None
        }
      }
    Tab =>
      // In a completion menu, Tab accepts the highlighted item (completes the
      // text) rather than submitting. A slash-command line is never queued as a
      // prompt — even a bare `/` — so it falls through to a no-op when there is
      // nothing to complete. Only ordinary input is queued.
      if self.completion_menu_open() {
        self.accept_completion()
      } else if composer_is_slash_entry(
          self.config.slash_commands,
          self.composer,
        ) {
        None
      } else {
        self.submit_current_input().map(input => Queue(input))
      }
    Escape => {
      // Esc only resets history navigation; it deliberately does NOT interrupt.
      // Under the kitty keyboard protocol every key is an ESC-prefixed sequence,
      // and a sequence split across reads (the decoder's esc-timeout firing
      // before the rest arrives) surfaces as a phantom bare Esc. Routing that to
      // Interrupt would spuriously cancel a running task or, when idle, quit.
      // Ctrl+C is the deliberate interrupt/quit key.
      self.history.reset_navigation()
      if self.completion_menu_open() {
        self.completion.dismissed = true
        self.redraw()
      }
      None
    }
    Char('k') if key.modifiers.ctrl() => {
      self.composer.kill_after()
      self.redraw_after_text_change()
      None
    }
    Char('n') if key.modifiers.ctrl() => {
      if self.completion_menu_open() {
        self.move_completion_selection(1)
      } else {
        self.move_down_or_recall_history()
      }
      None
    }
    Char('p') if key.modifiers.ctrl() => {
      if self.completion_menu_open() {
        self.move_completion_selection(-1)
      } else {
        self.move_up_or_recall_history()
      }
      None
    }
    Char('u') if key.modifiers.ctrl() => {
      self.composer.kill_before()
      self.redraw_after_text_change()
      None
    }
    Up => {
      if self.completion_menu_open() {
        self.move_completion_selection(-1)
      } else {
        self.move_up_or_recall_history()
      }
      None
    }
    Down => {
      if self.completion_menu_open() {
        self.move_completion_selection(1)
      } else {
        self.move_down_or_recall_history()
      }
      None
    }
    Left => {
      self.composer.move_left()
      self.redraw_after_cursor_move()
      None
    }
    Right => {
      self.composer.move_right()
      self.redraw_after_cursor_move()
      None
    }
    Home => {
      self.composer.move_home()
      self.redraw_after_cursor_move()
      None
    }
    End => {
      self.composer.move_end()
      self.redraw_after_cursor_move()
      None
    }
    Char('j') if key.modifiers.ctrl() => {
      self.composer.insert("\n")
      self.redraw_after_text_change()
      None
    }
    Backspace => {
      self.composer.delete_before()
      self.redraw_after_text_change()
      None
    }
    Delete => {
      self.composer.delete_after()
      self.redraw_after_text_change()
      None
    }
    _ =>
      if key.text is Some(text) {
        self.composer.insert_user_text(text)
        self.redraw_after_text_change()
        None
      } else {
        self.notice = Some(@doc.dim_text("ignored key"))
        self.redraw()
        None
      }
  }
}

///|
async fn Ui::handle_tty_event(self : Self, event : @tty.Event) -> Event? {
  match event {
    Input(Key(key)) => self.handle_key(key)
    Input(Unknown(bytes)) => {
      self.notice = Some(
        @doc.dim_text("unknown input: \{bytes.length()} bytes"),
      )
      self.redraw()
      None
    }
    // A bracketed paste reaches the composer outside `handle_key`, so the modal
    // picker must swallow it here too — otherwise a paste edits the draft
    // underneath the open list.
    Input(Paste(text)) =>
      if self.picker_open() {
        None
      } else {
        self.composer.insert_user_text(text)
        self.redraw_after_text_change()
        None
      }
    Input(FocusIn | FocusOut | Mouse(_)) => None
    Resize(size) => {
      self.redraw_after_resize(size)
      None
    }
  }
}

///|
/// Block until the next semantic `Event` from the input loop. Reraises any error
/// the tty reader encountered; yields `Quit` once the reader is closed.
pub async fn Ui::read_event(self : Self) -> Event {
  self.events.get().unwrap_or_error()
}
