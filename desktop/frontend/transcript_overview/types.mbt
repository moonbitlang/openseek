// The overview rail's projection of the transcript: one entry per user turn,
// each identified by a key that survives re-renders and overlay churn. The
// rail, its preview popovers, and the scroll watcher's active-turn reports
// all speak in these keys.

///|
/// Identity of one user turn: the durable event sequence when the row has
/// one, else its position in the visible transcript (a client-local row, or
/// a fixture written without sequences). Sequences are per-session, so a key
/// must never outlive a conversation switch — the root resets the overview
/// state when the active conversation changes.
pub(all) enum TurnKey {
  Durable(Int)
  Local(Int)
} derive(Eq, Debug)

///|
pub fn TurnKey::of(item : @transcript.TranscriptItem, index~ : Int) -> TurnKey {
  match item.sequence {
    Some(sequence) => Durable(sequence)
    None => Local(index)
  }
}

///|
/// The DOM id this turn's bubble carries, shared between the bubble render,
/// the rail's jump command, and the scroll watcher's report.
pub fn TurnKey::anchor(self : TurnKey) -> String {
  match self {
    Durable(sequence) => "turn-s\{sequence}"
    Local(index) => "turn-i\{index}"
  }
}

///|
/// Recover the key from a bubble's DOM id — the scroll watcher only has the
/// element in hand. `None` for any id this package did not mint.
pub fn TurnKey::from_anchor(id : String) -> TurnKey? {
  if ordinal_after(id, "turn-s") is Some(sequence) {
    return Some(Durable(sequence))
  }
  if ordinal_after(id, "turn-i") is Some(index) {
    return Some(Local(index))
  }
  None
}

///|
fn ordinal_after(id : String, prefix : String) -> Int? {
  guard id.has_prefix(prefix) else { return None }
  let digits = id.clamped_view(start=prefix.length())
  let value = @string.parse_int(digits) catch { _ => return None }
  Some(value)
}

///|
/// One user turn on the rail: its key, the display form of the prompt, when
/// it was sent, and the answer it got.
pub(all) struct Entry {
  key : TurnKey
  // Display form of the prompt. The caller supplies the projection — it owns
  // the mention-envelope format this package should not know about.
  text : String
  ts : Double?
  // The turn's answer: the first assistant row before the next user turn,
  // `None` while the turn is still running (or when it never got one).
  reply : String?
  // Whether any tool in the turn came back an error. A long conversation is
  // read by scrolling, and the one thing a reader scrolls looking for is where
  // it went wrong; the rail is the only view of the whole conversation, so it
  // is the only place that question can be answered without scrolling.
  //
  // The turn's own failures, not the run's health: a turn that recovered still
  // marks, because "the agent hit an error here and worked around it" is the
  // same place a reader wants to land.
  failed : Bool
} derive(Eq, Debug)

///|
/// Project the visible transcript into rail entries, one per user turn.
pub fn entries(
  items : Array[@transcript.TranscriptItem],
  display~ : (String) -> String,
) -> Array[Entry] {
  let result : Array[Entry] = []
  for index, item in items {
    guard item.kind is User(prompt) else { continue }
    // The turn's answer is the first prose the agent said — a response that
    // only thought or only ran tools is not an answer yet. An abort/failure
    // bubble counts: it is what the turn got.
    //
    // Failures are collected over the whole turn rather than stopping at the
    // answer: a tool that failed after the first answer still failed in this
    // turn, and the reply search stops early by design.
    let mut reply : String? = None
    let mut failed = false
    for cursor in (index + 1)..<items.length() {
      let item = items[cursor]
      if item.kind is User(_) {
        break
      }
      match item.kind {
        Assistant(calls~, ..) =>
          if calls.iter().any(call => call.outcome is Done(is_error=true, ..)) {
            failed = true
          }
        Notice(is_error=true, ..) => failed = true
        _ => ()
      }
      if reply is None && item.kind is (Assistant(..) | Answer(_) | Failure(_)) {
        reply = item.text()
      }
    }
    result.push({
      key: TurnKey::of(item, index~),
      text: display(prompt),
      ts: item.ts,
      reply,
      failed,
    })
  }
  result
}

///|
pub extend Entry with Debug::{to_repr}

///|
pub extend Entry with Eq::{equal, not_equal}

///|
pub extend TurnKey with Debug::{to_repr}

///|
pub extend TurnKey with Eq::{equal, not_equal}
