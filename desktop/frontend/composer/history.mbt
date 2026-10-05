// Recalling the prompts a conversation has already sent. The root supplies
// them (`Input::history`); the entry remembers only how far back its draft
// was recalled, so history never becomes a second copy of the transcript.

///|
/// Whether Up may start or continue recalling: an untouched draft has nothing
/// to lose, and a recalled one is replaced as the user steps through. Anything
/// the user typed or attached is never overwritten.
fn Entry::can_recall_history(self : Entry, input : Input) -> Bool {
  !input.history.is_empty() &&
  (self.history_back is Some(_) || self.draft.is_empty())
}

///|
/// The draft after one Up (`-1`, older) or Down (`+1`, newer) step. Down from
/// the latest prompt returns to the empty draft recall started from. `None`
/// when the key has nothing to do, so the caller leaves the entry untouched.
fn Entry::history_moved(self : Entry, input : Input, delta : Int) -> Entry? {
  guard self.can_recall_history(input) else { return None }
  let count = input.history.length()
  let back = match (self.history_back, delta) {
    (Some(back), -1) => back + 1
    (None, -1) => 1
    (Some(back), 1) => back - 1
    _ => return None
  }
  if back > count {
    return None
  }
  if back < 1 {
    return Some({
      ..self,
      draft: { task: "", mentions: [], images: [], },
      completion: None,
      pending_submission: None,
      history_back: None,
    })
  }
  Some({
    ..self,
    draft: { task: input.history[count - back], mentions: [], images: [], },
    completion: None,
    pending_submission: None,
    history_back: Some(back),
  })
}

///|
/// The "History 3/9" caption for a recalled draft; `None` otherwise.
fn Entry::history_label(
  self : Entry,
  locale : @i18n.Locale,
  input : Input,
) -> String? {
  guard self.history_back is Some(back) && back <= input.history.length() else {
    return None
  }
  let count = input.history.length()
  Some("\{ui(locale, HistoryLabel)} \{count - back + 1}/\{count}")
}

///|
/// Whether the caret sits where the arrow key has no text left to move over:
/// on the first line for Up, the last for Down. A selection is never an edge,
/// so extending or collapsing one keeps its ordinary meaning.
extern "js" fn caret_at_edge(id : String, up~ : Bool) -> Bool =
  #| (id, up) => {
  #|   const input = document.getElementById(id)
  #|   if (!(input instanceof HTMLTextAreaElement)) return false
  #|   if (input.selectionStart !== input.selectionEnd) return false
  #|   return up
  #|     ? !input.value.slice(0, input.selectionStart).includes("\n")
  #|     : !input.value.slice(input.selectionEnd).includes("\n")
  #| }
