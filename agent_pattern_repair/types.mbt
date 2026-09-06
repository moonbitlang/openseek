///|
const MaxPatternChars : Int = 8000

///|
/// A bounded candidate returned by the Pattern Repair Agent.
struct PatternRepairReport {
  candidate_pattern : String
  message : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend PatternRepairReport with Debug::{to_repr}

///|
pub extend PatternRepairReport with Eq::{equal, not_equal}

///|
pub extend PatternRepairReport with ToJson::{to_json}

///|
pub extend PatternRepairReport with FromJson::{from_json}

///|
fn PatternRepairReport::validate(self : PatternRepairReport) -> Array[String] {
  let problems : Array[String] = []
  if self.candidate_pattern.trim().is_empty() {
    problems.push("candidate_pattern must not be empty")
  }
  if self.candidate_pattern.length() > MaxPatternChars {
    problems.push("candidate_pattern is too large")
  }
  if self.message.length() > MaxPatternChars {
    problems.push("message is too large")
  }
  problems
}

///|
/// Decode only. The contract check is `validate`, applied by the one caller
/// through `@agent_kind.validated`, exactly as the sibling report packages
/// do it.
fn PatternRepairReport::parse(
  json : Json,
) -> Result[PatternRepairReport, String] {
  let report : PatternRepairReport = @json.from_json(json) catch {
    error => return Err("invalid pattern repair report: \{error}")
  }
  Ok(report)
}
