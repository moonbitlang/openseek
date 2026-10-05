// Recalling the prompts a conversation has already sent. The root supplies
// them (`Input::history`); the entry remembers only how far back its draft
// was recalled, so history never becomes a second copy of the transcript.

///|
/// How far back the draft still is the prompt it was recalled from. A draft
/// changed by anything but stepping (a recovered draft, an appended quote, a
/// longer history) is no longer a recall, whatever `history_back` remembers.
fn Entry::recalled_back(self : Entry, input : Input) -> Int? {
  guard self.history_back is Some(back) &&
    back <= input.history.length() &&
    self.draft.task == input.history[input.history.length() - back] &&
    self.draft.mentions.is_empty() &&
    self.draft.images.is_empty() else {
    return None
  }
  Some(back)
}

///|
/// Whether Up may start or continue recalling: an untouched draft has nothing
/// to lose, and a recalled one is replaced as the user steps through. Anything
/// the user typed or attached is never overwritten, and a goal being edited
/// has no prompt history.
fn Entry::can_recall_history(self : Entry, input : Input) -> Bool {
  input.goal.draft is None &&
  !input.history.is_empty() &&
  (self.recalled_back(input) is Some(_) || self.draft.is_empty())
}

///|
/// The draft after one Up (`-1`, older) or Down (`+1`, newer) step. Down from
/// the latest prompt returns to the empty draft recall started from. `None`
/// when the key has nothing to do, so the caller leaves the entry untouched.
fn Entry::history_moved(self : Entry, input : Input, delta : Int) -> Entry? {
  guard self.can_recall_history(input) else { return None }
  let count = input.history.length()
  let back = match (self.recalled_back(input), delta) {
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
  guard self.recalled_back(input) is Some(back) else { return None }
  let count = input.history.length()
  Some("\{ui(locale, HistoryLabel)} \{count - back + 1}/\{count}")
}

///|
/// Whether the caret sits where the arrow key has no text left to move over:
/// on the first visual row for Up, the last for Down, counting soft-wrapped
/// rows. A selection is never an edge, so extending or collapsing one keeps its
/// ordinary meaning. Rows are measured on a hidden copy of the textarea holding
/// the text before the caret, so wrapping follows the real width and font.
extern "js" fn caret_at_edge(id : String, up~ : Bool) -> Bool =
  #| (id, up) => {
  #|   const input = document.getElementById(id)
  #|   if (!(input instanceof HTMLTextAreaElement)) return false
  #|   if (input.selectionStart !== input.selectionEnd) return false
  #|   const probe = input.cloneNode(false)
  #|   probe.removeAttribute("id")
  #|   const computed = getComputedStyle(input)
  #|   for (const name of computed) {
  #|     probe.style.setProperty(name, computed.getPropertyValue(name))
  #|   }
  #|   probe.style.position = "absolute"
  #|   probe.style.visibility = "hidden"
  #|   probe.style.pointerEvents = "none"
  #|   probe.style.height = "1px"
  #|   probe.style.minHeight = "0"
  #|   probe.style.maxHeight = "none"
  #|   probe.style.overflow = "hidden"
  #|   input.parentNode.appendChild(probe)
  #|   const height = text => {
  #|     probe.value = text
  #|     return probe.scrollHeight
  #|   }
  #|   try {
  #|     const before = height(input.value.slice(0, input.selectionStart))
  #|     return up ? before <= height("x") : before >= height(input.value)
  #|   } finally {
  #|     probe.remove()
  #|   }
  #| }
