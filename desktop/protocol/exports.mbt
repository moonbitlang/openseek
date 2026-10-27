// Deliberate exports with no in-repo production consumer (see
// shrink_package.md). Each entry documents its reason.
//
// `goal_set`, `goal_clear`: test seam — the `desktop/backend` engine tests
// drive the command queue, the write-failure path and the discard path with
// these two goal commands (`desktop/backend/engine/engine.mbt`,
// `desktop/backend/engine/ops.mbt`). They are the goal half of the command
// family whose other members (`prompt`, `steer`, `compact`, `cancel`,
// `approval`) have production callers.

///|
/// Set (or replace) the session's standing goal. `auto` arms the engine's
/// autonomous continuation: after a cleanly finished turn it starts the next
/// one itself, until the goal is met, the agent reports it blocked, or the
/// engine's turn budget runs out. Manual is the default the UI offers.
///
/// Arming lives in the serve process, not in the durable record — the
/// `[goal]` marker stores the text alone — so it does not survive an engine
/// restart, and any later goal command supersedes it.
pub fn goal_set(text : String, auto~ : Bool) -> @wire.Command {
  GoalSet(text~, auto~)
}

///|
/// Clear the session's standing goal.
pub fn goal_clear() -> @wire.Command {
  GoalClear
}
