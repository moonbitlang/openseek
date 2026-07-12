///|
/// `ReviewReport` is the stable, versioned contract returned by every review
/// front-end (the headless `--review` CLI today; TUI / MCP later) and consumed
/// by external agents that dispatch a review to OpenSeek. The JSON shape is the
/// integration boundary, so it is kept deliberately flat and string-typed.

///|
/// The schema version this build emits and accepts.
pub let current_schema_version : Int = 1

///|
/// Allowed severity values, ordered most to least severe.
pub fn severities() -> Array[String] {
  ["blocker", "high", "medium", "low", "nit"]
}

///|
/// A single review finding at an optional source location.
pub(all) struct Finding {
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
pub(all) struct ReviewScope {
  base : String
  head : String
  files : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Deterministic preflight signals that ground the review in the compiler/tests
/// rather than model opinion.
pub(all) struct ReviewStats {
  files_reviewed : Int
  findings : Int
  build : String
  tests : String
} derive(Debug, Eq, ToJson, FromJson)

///|
/// The full review report.
pub(all) struct ReviewReport {
  schema_version : Int
  scope : ReviewScope
  findings : Array[Finding]
  summary : String
  stats : ReviewStats
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Validate a report against the contract. Returns the list of problems; an
/// empty list means the report is valid. The `submit_review` tool uses this to
/// reject malformed model output and ask for a retry.
pub fn ReviewReport::validate(self : ReviewReport) -> Array[String] {
  let problems : Array[String] = []
  if self.schema_version != current_schema_version {
    problems.push(
      "schema_version must be \{current_schema_version}, got \{self.schema_version}",
    )
  }
  if self.summary.trim() == "" {
    problems.push("summary must not be empty")
  }
  let allowed = severities()
  for finding in self.findings {
    if !allowed.contains(finding.severity) {
      problems.push(
        "finding '\{finding.title}': invalid severity '\{finding.severity}'",
      )
    }
    if finding.file == "" {
      problems.push("a finding has an empty file path")
    }
    if finding.title == "" {
      problems.push("a finding has an empty title")
    }
    if finding.category == "" {
      problems.push("finding '\{finding.title}': empty category")
    }
    if finding.detail == "" {
      problems.push("finding '\{finding.title}': empty detail")
    }
  }
  problems
}

///|
/// Parse a report from JSON, returning the report or a human-readable error.
pub fn ReviewReport::parse(json : Json) -> Result[ReviewReport, String] {
  let report : ReviewReport = @json.from_json(json) catch {
    e => return Err("invalid review report JSON: \{e}")
  }
  Ok(report)
}

///|
/// Encode the report as a single-line JSON string (the CLI stdout contract).
pub fn ReviewReport::to_json_string(self : ReviewReport) -> String {
  self.to_json().stringify()
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
  let json = report.to_json()
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
