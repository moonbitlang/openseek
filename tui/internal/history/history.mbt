// Readline-style command history for the input composer.
//
// `History` stores submitted `Entry`s and a navigation cursor so Up/Ctrl-P and
// Down/Ctrl-N can recall previous submissions while preserving the in-progress
// draft. The cursor lives in the inclusive range `[0, entries.length()]`, where
// `entries.length()` means "editing the fresh draft" rather than a stored entry.

///|
/// One recallable submission: the composer text plus the mode it was entered in
/// (prompt vs. shell), so recall can restore both.
struct Entry {
  text : String
  mode : @composer.Mode
}

///|
/// Build a history entry from composer text and its mode.
pub fn Entry::new(text : String, mode : @composer.Mode) -> Entry {
  { text, mode }
}

///|
/// The recalled text.
pub fn Entry::text(self : Entry) -> String {
  self.text
}

///|
/// The mode the entry was submitted in.
pub fn Entry::mode(self : Entry) -> @composer.Mode {
  self.mode
}

///|
fn Entry::same_as(self : Entry, other : Entry) -> Bool {
  self.text == other.text && self.mode == other.mode
}

///|
/// Submitted entries plus the navigation cursor and the saved draft.
struct History {
  entries : Array[Entry]
  // Cursor is in the inclusive range [0, entries.length()].
  // entries.length() means the user is editing the fresh, not-yet-submitted
  // draft rather than a stored history entry.
  mut cursor : Int
  mut draft : Entry?
}

///|
/// An empty history positioned on the fresh draft.
pub fn History::new() -> History {
  { entries: [], cursor: 0, draft: None }
}

///|
/// Return the cursor to the fresh draft and forget any saved draft. Called when
/// the user edits, submits, or cancels, so the next recall starts from the end.
pub fn History::reset_navigation(self : History) -> Unit {
  self.cursor = self.entries.length()
  self.draft = None
}

///|
/// Append `entry` (unless empty or a duplicate of the most recent one) and reset
/// navigation to the fresh draft.
pub fn History::push(self : History, entry : Entry) -> Unit {
  if entry.text.length() > 0 {
    if self.entries.last() is Some(last) {
      if !last.same_as(entry) {
        self.entries.push(entry)
      }
    } else {
      self.entries.push(entry)
    }
  }
  self.reset_navigation()
}

///|
/// Recall the previous entry, saving `current` as the draft on the first step
/// back. Returns `None` when there is no history to recall.
pub fn History::previous(self : History, current : Entry) -> Entry? {
  if self.entries.length() == 0 {
    return None
  }
  if self.cursor == self.entries.length() {
    self.draft = Some(current)
  }
  if self.cursor > 0 {
    self.cursor -= 1
  }
  self.entries.get(self.cursor)
}

///|
/// Recall the next entry, returning to the saved draft past the last entry.
/// Returns `None` when already at the fresh draft.
pub fn History::next(self : History) -> Entry? {
  if self.cursor >= self.entries.length() {
    return None
  }
  self.cursor += 1
  if self.cursor == self.entries.length() {
    self.draft
  } else {
    self.entries.get(self.cursor)
  }
}
