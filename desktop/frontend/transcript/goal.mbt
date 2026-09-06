// The durable goal markers, re-spelled from `agent_session`'s goal
// vocabulary: this js-only package cannot depend on that native package, so
// the marker shapes are duplicated here — `agent_session/goal.mbt` is the
// authority if they ever drift.

///|
/// A goal marker recognized in a durable `runtime_notice`. The set marker
/// requires the exact `[goal]` first line and the tombstone/unblock markers
/// require exact content, so the other goal-family notices (reminders,
/// checks, the baseline pairing record) never match.
pub(all) enum GoalMarker {
  GoalSet(String)
  GoalCleared
  GoalBlocked(String)
  GoalUnblocked
} derive(Eq)

///|
pub fn goal_marker(content : String) -> GoalMarker? {
  if content == "[goal cleared]" {
    Some(GoalCleared)
  } else if content == "[goal unblocked]" {
    Some(GoalUnblocked)
  } else if content.strip_prefix("[goal blocked]\n") is Some(reason) {
    Some(GoalBlocked(reason.to_owned()))
  } else if content.strip_prefix("[goal]\n") is Some(text) {
    Some(GoalSet(text.to_owned()))
  } else {
    None
  }
}

///|
/// The standing goal a durable record's markers reduce to: the newest set
/// marker's text, and the blocked reason when the newest block/unblock
/// transition since that set left it blocked.
pub(all) struct GoalStanding {
  text : String
  blocked : String?
} derive(Eq)

///|
/// One reducer step: the last marker wins. Block/unblock transitions apply
/// only to a standing goal — on a goalless record they are transport noise
/// from an older fault, not state to resurrect.
pub fn apply_goal_marker(
  goal : GoalStanding?,
  marker : GoalMarker,
) -> GoalStanding? {
  match marker {
    GoalSet(text) => Some({ text, blocked: None, })
    GoalCleared => None
    GoalBlocked(reason) => goal.map(goal => { ..goal, blocked: Some(reason), })
    GoalUnblocked => goal.map(goal => { ..goal, blocked: None, })
  }
}

///|
test "goal markers parse exactly and other goal-family notices never match" {
  assert_true(
    goal_marker("[goal]\nship the feature") is Some(GoalSet("ship the feature")),
  )
  assert_true(
    goal_marker("[goal]\nline one\nline two")
    is Some(GoalSet("line one\nline two")),
  )
  assert_true(goal_marker("[goal cleared]") is Some(GoalCleared))
  assert_true(
    goal_marker("[goal blocked]\nneeds a decision")
    is Some(GoalBlocked("needs a decision")),
  )
  assert_true(goal_marker("[goal unblocked]") is Some(GoalUnblocked))
  // Reminders, checks and the baseline record are transport/model-directed.
  assert_true(goal_marker("[goal reminder]\nThe standing goal…") is None)
  assert_true(goal_marker("[goal check]\nThe standing goal…") is None)
  assert_true(goal_marker("[goal baseline] sha=abc dirty=false") is None)
  // A bare `[goal]` with no text line is not a set.
  assert_true(goal_marker("[goal]") is None)
  assert_true(goal_marker("plain notice") is None)
}

///|
test "the goal reducer follows last-marker-wins with guarded transitions" {
  let set = apply_goal_marker(None, GoalSet("ship it"))
  assert_true(set is Some({ text: "ship it", blocked: None, }))
  let blocked = apply_goal_marker(set, GoalBlocked("needs access"))
  assert_true(
    blocked is Some({ text: "ship it", blocked: Some("needs access"), }),
  )
  let resumed = apply_goal_marker(blocked, GoalUnblocked)
  assert_true(resumed is Some({ text: "ship it", blocked: None, }))
  // A newer set resets a standing block.
  let replaced = apply_goal_marker(blocked, GoalSet("polish it"))
  assert_true(replaced is Some({ text: "polish it", blocked: None, }))
  assert_true(apply_goal_marker(blocked, GoalCleared) is None)
  // Stray transitions on a goalless record stay goalless.
  assert_true(apply_goal_marker(None, GoalBlocked("orphan")) is None)
  assert_true(apply_goal_marker(None, GoalUnblocked) is None)
}

///|
pub extend GoalMarker with Eq::{equal, not_equal}

///|
pub extend GoalStanding with Eq::{equal, not_equal}
