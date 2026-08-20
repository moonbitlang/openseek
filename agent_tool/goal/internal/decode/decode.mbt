///|
/// A decoded verdict about the standing session goal.
pub enum GoalStatus {
  /// The goal is fully achieved and verified.
  Met
  /// Work remains and can continue autonomously.
  Continuing(String)
  /// Progress requires user action or an external-state change.
  Blocked(String)
} derive(Debug)

///|
/// Decode and validate `goal` tool-call arguments.
///
/// `met` needs no companion field. `continuing` requires a non-blank
/// `remaining`, and `blocked` requires a non-blank `reason`. The original text
/// is preserved after its trimmed form is checked, so the durable record has
/// exactly the wording supplied by the model. Malformed arguments raise a
/// `Failure` whose message identifies the field to repair.
pub fn decode(arguments : Json) -> GoalStatus raise {
  match arguments {
    { "status": "met", .. } => Met
    { "status": "continuing", "remaining": String(remaining), .. } =>
      if remaining.is_blank() {
        fail(
          "goal requires a non-blank \"remaining\" when status is \"continuing\"",
        )
      } else {
        Continuing(remaining)
      }
    { "status": "continuing", .. } =>
      fail("goal requires a string \"remaining\" when status is \"continuing\"")
    { "status": "blocked", "reason": String(reason), .. } =>
      if reason.is_blank() {
        fail("goal requires a non-blank \"reason\" when status is \"blocked\"")
      } else {
        Blocked(reason)
      }
    { "status": "blocked", .. } =>
      fail("goal requires a string \"reason\" when status is \"blocked\"")
    { "status": String(other), .. } =>
      fail(
        "goal status must be \"met\", \"continuing\", or \"blocked\", got \"\{other}\"",
      )
    _ => fail("goal requires a string \"status\" field")
  }
}

///|
#deprecated
pub extend GoalStatus with Debug::{to_repr}
