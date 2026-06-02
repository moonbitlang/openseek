///|
fn submitted_input(text : String, mode : @composer.Mode) -> Input {
  if mode.is_shell() {
    Command(text.trim().to_owned())
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
  self.notice = None
  self.redraw()
}

///|
async fn Ui::redraw_after_history_recall(self : Self) -> Unit {
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
    Enter => self.submit_current_input().map(input => Steer(input))
    Tab => self.submit_current_input().map(input => Queue(input))
    Escape => {
      self.history.reset_navigation()
      Some(Interrupt)
    }
    Char('k') if key.modifiers.ctrl() => {
      self.composer.kill_after()
      self.redraw_after_text_change()
      None
    }
    Char('n') if key.modifiers.ctrl() => {
      self.move_down_or_recall_history()
      None
    }
    Char('p') if key.modifiers.ctrl() => {
      self.move_up_or_recall_history()
      None
    }
    Char('u') if key.modifiers.ctrl() => {
      self.composer.kill_before()
      self.redraw_after_text_change()
      None
    }
    Up => {
      self.move_up_or_recall_history()
      None
    }
    Down => {
      self.move_down_or_recall_history()
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
    Input(Paste(text)) => {
      self.composer.insert_user_text(text)
      self.redraw_after_text_change()
      None
    }
    Input(FocusIn | FocusOut | Mouse(_)) => None
    Resize(_) => {
      self.redraw_after_resize()
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
