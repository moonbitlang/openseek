///|
/// Shared structured evidence. Only reach verdicts recommend a retry threshold;
/// count-based rollback itself does not depend on diagnostic identity.
pub fn Comparability::feedback(
  self : Comparability,
  delta~ : Int,
) -> Map[String, Json] {
  let verdict = self.verdict()
  let data : Map[String, Json] = {
    "verdict": verdict.name().to_json(),
    "new_in_edited": self.new_in_edited.to_json(),
    "new_breaking": self.new_breaking.to_json(),
    "new_in_dependents": self.new_in_dependents.to_json(),
    "new_independent": self.new_independent.to_json(),
  }
  if verdict is Inconclusive(reason) {
    data["verdict_reason"] = reason.to_json()
  }
  if self.before_count is Some(count) {
    data["baseline_error_count"] = count.to_json()
  }
  if verdict is (CertifiedReach | PlausibleReach) {
    data["reissue_with"] = (delta + 1).to_json()
  }
  data
}
