///|
/// An open modal picker: a fixed list the user navigates and selects from.
/// Unlike the autocomplete menu, the items are not derived from composer text;
/// accepting one inserts its `insert_text` at the cursor. A `None` picker on
/// `Ui` means closed. Only one menu (picker or completion) is ever live.
priv struct PickerState {
  items : Array[@completion.CompletionItem]
  selected : Int
}

///|
/// Open a modal picker over `items`. Closes the autocomplete menu so only one
/// menu is live, clears any notice, and redraws. A no-op for an empty list.
pub async fn Ui::open_picker(
  self : Self,
  items : Array[@completion.CompletionItem],
) -> Unit {
  if items.is_empty() {
    return
  }
  // Serialize with key/resize/status redraws on the command queue: this is
  // dispatched from the message loop, not the tty worker, so a bare redraw here
  // could interleave with one already in flight and leave the frame inconsistent.
  self.commands.wait(() => {
    self.picker = Some({ items, selected: 0 })
    self.completion.reset()
    self.notice = None
    self.redraw()
  })
}

///|
/// Whether a picker is open AND there is room to render it. Like the completion
/// menu, a picker that cannot be drawn must not capture keys (an invisible modal
/// would silently swallow Enter/arrows).
fn Ui::picker_open(self : Self) -> Bool {
  self.picker is Some(_) && self.completion_menu_visible()
}

///|
/// Handle a key while the picker is open. The picker is modal: navigation,
/// accept (insert + close), and dismiss are handled; Ctrl-C stays a global
/// interrupt; every other key is swallowed so typing cannot mutate the composer
/// underneath the open list.
async fn Ui::handle_picker_key(
  self : Self,
  key : @tty/input.KeyEvent,
) -> Event? {
  match key.code {
    Up => {
      self.picker_move(-1)
      None
    }
    Down => {
      self.picker_move(1)
      None
    }
    Char('p') if key.modifiers.ctrl() => {
      self.picker_move(-1)
      None
    }
    Char('n') if key.modifiers.ctrl() => {
      self.picker_move(1)
      None
    }
    Enter | Tab => {
      self.picker_accept()
      None
    }
    Escape => {
      self.close_picker()
      None
    }
    Char('c') if key.modifiers.ctrl() => {
      self.history.reset_navigation()
      Some(Interrupt)
    }
    _ => None
  }
}

///|
/// Move the picker selection by `delta`, wrapping around the ends, then redraw.
async fn Ui::picker_move(self : Self, delta : Int) -> Unit {
  guard self.picker is Some(picker) else { return }
  let len = picker.items.length()
  if len == 0 {
    return
  }
  let selected = if delta < 0 {
    if picker.selected <= 0 {
      len - 1
    } else {
      picker.selected - 1
    }
  } else if picker.selected + 1 >= len {
    0
  } else {
    picker.selected + 1
  }
  self.picker = Some({ items: picker.items, selected })
  self.redraw()
}

///|
/// Insert the selected item's text at the cursor and close the picker.
async fn Ui::picker_accept(self : Self) -> Unit {
  guard self.picker is Some(picker) else { return }
  let selected = picker.selected.clamp(min=0, max=picker.items.length() - 1)
  self.picker = None
  // Skill labels come from frontmatter/filenames, so strip terminal control
  // sequences (e.g. ESC) before echoing the inserted text into the composer —
  // `insert` (unlike `insert_user_text`) does not sanitize.
  self.composer.insert(@text.sanitize(picker.items[selected].insert_text()))
  self.redraw()
}

///|
/// Close the picker without selecting.
async fn Ui::close_picker(self : Self) -> Unit {
  self.picker = None
  self.redraw()
}
