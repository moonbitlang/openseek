///|
/// `ReviewReport` is the stable, versioned contract returned by every review
/// front-end (the headless `--review` CLI today; TUI / MCP later) and consumed
/// by external agents that dispatch a review to OpenSeek. The JSON shape is the
/// integration boundary, so it is kept deliberately flat and string-typed.

///|
/// A single review finding at an optional source location.
pub struct Finding {
  file : String
  line : Int?
  severity : String
  category : String
  title : String
  detail : String
  suggestion : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
/// The change set the review covered.
pub struct ReviewScope {
  base : String
  head : String
  files : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Deterministic preflight signals that ground the review in the compiler/tests
/// rather than model opinion.
pub struct ReviewStats {
  files_reviewed : Int
  findings : Int
  build : String
  tests : String
} derive(Debug, Eq, ToJson, FromJson)

///|
/// The full review report.
pub struct ReviewReport {
  schema_version : Int
  scope : ReviewScope
  findings : Array[Finding]
  summary : String
  stats : ReviewStats
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Encode the report as a single-line JSON string (the CLI stdout contract).
pub fn ReviewReport::to_json_string(self : ReviewReport) -> String {
  ToJson::to_json(self).stringify()
}

///|
fn sample_report() -> ReviewReport {
  {
    schema_version: 1,
    scope: { base: "origin/main", head: "HEAD", files: ["a.mbt", "b.mbt"] },
    findings: [
      {
        file: "a.mbt",
        line: Some(42),
        severity: "high",
        category: "correctness",
        title: "off-by-one in loop bound",
        detail: "uses < where <= is intended",
        suggestion: Some("change < to <="),
      },
      {
        file: "b.mbt",
        line: None,
        severity: "nit",
        category: "style",
        title: "unclear name",
        detail: "rename x to count",
        suggestion: None,
      },
    ],
    summary: "two findings",
    stats: { files_reviewed: 2, findings: 2, build: "pass", tests: "skipped" },
  }
}

///|
test "review report round-trips through json" {
  let report = sample_report()
  let json = ToJson::to_json(report)
  guard ReviewReport::parse(json) is Ok(parsed) else { fail("parse failed") }
  assert_eq(parsed.to_json_string(), report.to_json_string())
}

///|
test "json string carries the flat string-typed contract" {
  let s = sample_report().to_json_string()
  assert_true(s.contains("\"schema_version\""))
  assert_true(s.contains("\"findings\""))
  // severity renders as a plain string, not a tagged enum
  assert_true(s.contains("\"high\""))
  assert_true(s.contains("\"nit\""))
}

///|
test "validate accepts a good report" {
  assert_eq(sample_report().validate().length(), 0)
}

///|
test "validate rejects a bad severity" {
  let report = {
    ..sample_report(),
    findings: [
      {
        file: "a.mbt",
        line: None,
        severity: "urgent",
        category: "correctness",
        title: "t",
        detail: "d",
        suggestion: None,
      },
    ],
  }
  assert_true(report.validate().length() > 0)
}

///|
test "validate rejects a wrong schema version" {
  let report = { ..sample_report(), schema_version: 2 }
  assert_true(report.validate().length() > 0)
}

///|
test "validate rejects an empty summary" {
  assert_true({ ..sample_report(), summary: "" }.validate().length() > 0)
  assert_true({ ..sample_report(), summary: "   " }.validate().length() > 0)
}

///|
test "parse reports an error on malformed json" {
  guard ReviewReport::parse(Json::null()) is Err(_) else {
    fail("expected parse error")
  }
}

///|
#deprecated
pub extend Finding with Debug::{to_repr}

///|
pub extend Finding with FromJson::{from_json}

///|
pub extend Finding with Eq::{equal, not_equal}

///|
pub extend Finding with ToJson::{to_json}

///|
#deprecated
pub extend ReviewReport with Debug::{to_repr}

///|
pub extend ReviewReport with FromJson::{from_json}

///|
pub extend ReviewReport with Eq::{equal, not_equal}

///|
pub extend ReviewReport with ToJson::{to_json}

///|
#deprecated
pub extend ReviewScope with Debug::{to_repr}

///|
pub extend ReviewScope with FromJson::{from_json}

///|
pub extend ReviewScope with Eq::{equal, not_equal}

///|
pub extend ReviewScope with ToJson::{to_json}

///|
#deprecated
pub extend ReviewStats with Debug::{to_repr}

///|
pub extend ReviewStats with FromJson::{from_json}

///|
pub extend ReviewStats with Eq::{equal, not_equal}

///|
pub extend ReviewStats with ToJson::{to_json}
