///|
/// First line of the reminder notice the agent loop re-injects so a
/// long-running conversation keeps the standing goal near the context tail.
pub const GoalReminderPrefix : String = "[goal reminder]"

///|
/// First line of the notice the agent loop injects when the model tries to
/// end a turn while a standing goal is set.
pub const GoalCheckPrefix : String = "[goal check]"

///|
/// Exact text of the prompt the serve engine submits to open an
/// auto-continuation turn on a standing goal.
///
/// It is durably appended as a `User` message like any other prompt — the
/// model has to read it as one — with `AutoContinue` origin. This wording
/// is presentation only; consumers classify the explicit origin.
pub const GoalContinuePrompt : String =
  #|Continue working toward the standing goal. When it is fully met, record
  #|that by calling the goal tool with status "met".

///|
/// A standing goal derived from the durable event log.
struct StandingGoal {
  text : String
  baseline : GoalBaselineState
  answered_since_set : Bool
  set_sequence : Int
  blocked : Bool
} derive(Debug)

///|
/// The goal text as it was set (may span lines when set over the wire).
pub fn StandingGoal::text(self : StandingGoal) -> String {
  self.text
}

///|
/// Sequence of the set marker event that established this goal. Marker
/// identity for consumers that must distinguish "this exact set persisted"
/// from "an identical-text goal was already standing" — text alone cannot.
pub fn StandingGoal::set_sequence(self : StandingGoal) -> Int {
  self.set_sequence
}

///|
/// Whether any model response (assistant message or turn terminal) was
/// appended after the goal was set. When false the set marker itself is
/// still ahead of the model's next request, so injecting a turn-start
/// reminder would only duplicate it.
pub fn StandingGoal::answered_since_set(self : StandingGoal) -> Bool {
  self.answered_since_set
}

///|
/// Whether the model durably declared this goal blocked since it was set:
/// the goal still stands for the user, but auto-continuation must pause.
pub fn StandingGoal::blocked(self : StandingGoal) -> Bool {
  self.blocked
}

///|
/// Standing goal state reduced from typed changes: the last set or clear
/// establishes the goal, and newer block/unblock changes determine its state.
///
/// The scan reads raw events, not the compacted projection, so a goal whose
/// set marker is covered by a later compaction summary is still recovered
/// verbatim from the append-only log.
pub fn Session::current_goal(self : Session) -> StandingGoal? {
  let events = self.events()
  let mut answered = false
  let mut blocked = false
  // The newest of the block/unblock pair wins: scanning newest-first, the
  // first one encountered before the set marker decides `blocked`, and
  // `blocked_decided` freezes it so an older transition cannot override it.
  let mut blocked_decided = false
  let covered : Array[(Int, Int)] = []
  for index in (events.length() - 1)>=..0 {
    let event = events[index]
    match event.item() {
      Assistant(_) | Terminal(_) => answered = true
      // A summary whose range CONTAINS the set marker removes its verbatim
      // text from the projection: treat the goal as "answered" so the
      // cadence re-surfaces it — the next request must not see only the
      // lossy summary where the standing goal used to be. A summary of
      // later events leaves the marker verbatim and must not re-remind.
      Summary(summary) =>
        covered.push((summary.from_sequence(), summary.to_sequence()))
      Goal(change) =>
        match change {
          GoalCleared => return None
          // Newest-first: a blocked/unblocked marker precedes the set it
          // follows temporally; a NEWER set is found first and naturally
          // resets both. Between them, whichever is newer wins.
          GoalBlocked(_) =>
            if !blocked_decided {
              blocked = true
              blocked_decided = true
            }
          GoalUnblocked =>
            if !blocked_decided {
              blocked = false
              blocked_decided = true
            }
          GoalSet(text, baseline~) => {
            let sequence = event.sequence()
            let is_covered = covered.any(range => {
              let (from, to) = range
              from <= sequence && sequence <= to
            })
            return Some({
              text,
              baseline,
              answered_since_set: answered || is_covered,
              set_sequence: sequence,
              blocked,
            })
          }
        }
      _ => ()
    }
  }
  None
}

///|
/// The standing goal owns its baseline; unrelated events cannot change the pairing.
pub fn StandingGoal::baseline(self : StandingGoal) -> GoalBaselineState {
  self.baseline
}

///|
/// Available advisory anchor for the current standing goal.
pub fn Session::current_goal_baseline(self : Session) -> GoalBaseline? {
  match self.current_goal() {
    Some({ baseline: Captured(baseline), .. }) => Some(baseline)
    _ => None
  }
}

///|
#doc(hidden)
#deprecated
pub extend StandingGoal with Debug::{to_repr}
