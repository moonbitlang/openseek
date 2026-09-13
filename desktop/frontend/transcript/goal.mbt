///|
/// Display state projected from the shared durable goal-change type.
pub(all) enum GoalMarker {
  GoalSet(String)
  GoalCleared
  GoalBlocked(String)
  GoalUnblocked
} derive(Eq)

///|
pub fn goal_marker(change : @desktop_protocol.GoalChange) -> GoalMarker {
  match change {
    GoalSet(text, ..) => GoalSet(text)
    GoalCleared => GoalCleared
    GoalBlocked(reason) => GoalBlocked(reason)
    GoalUnblocked => GoalUnblocked
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
