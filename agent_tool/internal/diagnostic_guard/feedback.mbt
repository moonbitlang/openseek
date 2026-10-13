///|
/// Shared structured evidence. Only reach verdicts recommend a retry threshold;
/// count-based rollback itself does not depend on diagnostic identity.
pub fn Comparability::feedback(
  self : Comparability,
  delta~ : Int32,
) -> Map[String, Json] {
  let verdict = self.verdict()
  let data : Map[String, Json] = {
    "verdict": Json(verdict.name()),
    "new_in_edited": Json(self.new_in_edited),
    "new_breaking": Json(self.new_breaking),
    "new_in_dependents": Json(self.new_in_dependents),
    "new_independent": Json(self.new_independent),
  }
  if verdict is Inconclusive(reason) {
    data["verdict_reason"] = Json(reason)
  }
  if self.before_count is Some(count) {
    data["baseline_error_count"] = Json(count)
  }
  if verdict is (CertifiedReach | PlausibleReach) {
    data["reissue_with"] = Json(delta + 1)
  }
  data
}
