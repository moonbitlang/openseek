///|
/// First line of the runtime notice that sets a standing goal. The full
/// marker content is `[goal]\n<text>`; `Session::current_goal` keys off the
/// exact prefix line, so it lives here with `RuntimeNotice` alongside
/// `PlanReminderPrefix` where producers (the serve engine, the agent loop)
/// and readers (the scan, viz, tests) share it. The bracket tags below are
/// reserved: only the goal command paths write notices with these first
/// lines.
pub const GoalPrefix : String = "[goal]"

///|
/// Exact content of the tombstone notice that clears a standing goal.
pub const GoalClearedNotice : String = "[goal cleared]"

///|
/// Marker prefix recording that the model declared the standing goal
/// BLOCKED: the goal keeps standing (the user decides what is next), but
/// auto-continuation must pause instead of relaunching declared-impossible
/// work.
pub const GoalBlockedPrefix : String = "[goal blocked]"

///|
/// Exact content of the marker that RESCINDS a prior `[goal blocked]`: the
/// model resumed work on the still-standing goal (via `goal(continuing)`), so
/// auto-continuation must resume too. A pure state transition, so it carries
/// no reason payload — exact content, like `[goal cleared]`.
pub const GoalUnblockedNotice : String = "[goal unblocked]"

///|
/// First line of the reminder notice the agent loop re-injects so a
/// long-running conversation keeps the standing goal near the context tail.
pub const GoalReminderPrefix : String = "[goal reminder]"

///|
/// First line of the notice the agent loop injects when the model tries to
/// end a turn while a standing goal is set.
pub const GoalCheckPrefix : String = "[goal check]"

///|
/// A standing goal derived from the durable event log.
pub struct StandingGoal {
  priv text : String
  priv answered_since_set : Bool
  priv set_sequence : Int
  priv blocked : Bool
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
/// A goal marker recognized in a runtime notice.
pub(all) enum GoalMarker {
  GoalSet(String)
  GoalCleared
  GoalBlocked(String)
  GoalUnblocked
} derive(Debug)

///|
/// Parse a runtime-notice content as a goal marker, if it is one. The set
/// marker requires the exact `[goal]` first line and the tombstone/unblock
/// markers require exact content, so other notices (plan reminders, goal
/// reminders, goal checks) never match. Unknown content is not a marker
/// (`None`), so a reader from an older build treats `[goal unblocked]` as a
/// plain notice and keeps the goal blocked — a safe degradation.
pub fn goal_marker(content : String) -> GoalMarker? {
  if content == GoalClearedNotice {
    Some(GoalCleared)
  } else if content == GoalUnblockedNotice {
    Some(GoalUnblocked)
  } else if content.strip_prefix("\{GoalBlockedPrefix}\n") is Some(content) {
    Some(GoalBlocked(content.to_owned()))
  } else if content.strip_prefix("\{GoalPrefix}\n") is Some(content) {
    Some(GoalSet(content.to_owned()))
  } else {
    None
  }
}

///|
/// Standing goal state: the last goal marker in the log wins — a
/// `[goal]\n<text>` notice yields that goal, a `[goal cleared]` tombstone
/// yields none.
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
      Runtime(notice) =>
        match goal_marker(notice.content()) {
          Some(GoalCleared) => return None
          // Newest-first: a blocked/unblocked marker precedes the set it
          // follows temporally; a NEWER set is found first and naturally
          // resets both. Between them, whichever is newer wins.
          Some(GoalBlocked(_)) =>
            if !blocked_decided {
              blocked = true
              blocked_decided = true
            }
          Some(GoalUnblocked) =>
            if !blocked_decided {
              blocked = false
              blocked_decided = true
            }
          Some(GoalSet(text)) => {
            let sequence = event.sequence()
            let is_covered = covered.any(range => {
              let (from, to) = range
              from <= sequence && sequence <= to
            })
            return Some({
              text,
              answered_since_set: answered || is_covered,
              set_sequence: sequence,
              blocked,
            })
          }
          None => ()
        }
      _ => ()
    }
  }
  None
}
