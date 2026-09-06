///|
/// `WorkerReport` is the bounded status report a worker child submits when
/// its slice of work ends. The report is ADVISORY: the parent controller's
/// git-level scope validation is the ground truth about what changed — this
/// report tells the parent what the worker believes it did and how it
/// verified that, in the worker's own words.

///|
/// The schema version this build emits and accepts.
let current_schema_version : Int = 1

///|
/// Summary length ceiling, enforced by `validate`.
let max_summary_chars : Int = 2_000

///|
/// Verification length ceiling, enforced by `validate`.
let max_verification_chars : Int = 2_000

///|
/// The worker's own account of its run. `status` is one of `done` (the task
/// is complete and verified), `partial` (honest progress with work
/// remaining), or `failed` (nothing mergeable came of it). `verification`
/// names the commands the worker ran and their outcomes — a claim without
/// verification is a guess.
pub struct WorkerReport {
  priv schema_version : Int
  status : String
  summary : String
  verification : String
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Validate a report against the contract. Returns the list of problems; an
/// empty list means the report is valid.
fn WorkerReport::validate(self : WorkerReport) -> Array[String] {
  let problems : Array[String] = []
  if self.schema_version != current_schema_version {
    problems.push(
      "schema_version must be \{current_schema_version}, got \{self.schema_version}",
    )
  }
  if !(self.status is ("done" | "partial" | "failed")) {
    problems.push(
      "status must be done, partial, or failed — got \{self.status}",
    )
  }
  if self.summary.is_blank() {
    problems.push("summary must not be empty")
  }
  if self.summary.length() > max_summary_chars {
    problems.push(
      "summary exceeds \{max_summary_chars} chars (\{self.summary.length()}); tighten it",
    )
  }
  if self.verification.is_blank() {
    problems.push(
      "verification must not be empty — name the commands you ran and their outcomes",
    )
  }
  if self.verification.length() > max_verification_chars {
    problems.push(
      "verification exceeds \{max_verification_chars} chars (\{self.verification.length()}); tighten it",
    )
  }
  problems
}

///|
/// Parse a report from JSON, returning the report or a human-readable error.
fn WorkerReport::parse(json : Json) -> Result[WorkerReport, String] {
  let report : WorkerReport = @json.from_json(json) catch {
    e => return Err("invalid worker report JSON: \{e}")
  }
  Ok(report)
}

///|
fn sample_worker_report() -> WorkerReport {
  {
    schema_version: 1,
    status: "done",
    summary: "Replaced the deprecated to_repr calls in lib/ and cmd/.",
    verification: "moon check clean (0 warnings in scope); moon test lib: 12/12.",
  }
}

///|
test "worker report round-trips through json" {
  let report = sample_worker_report()
  guard WorkerReport::parse(ToJson::to_json(report)) is Ok(parsed) else {
    fail("parse failed")
  }
  assert_eq(parsed, report)
}

///|
test "validate accepts a good report and rejects contract violations" {
  assert_eq(sample_worker_report().validate().length(), 0)
  assert_true(
    { ..sample_worker_report(), status: "excellent", }.validate().length() > 0,
  )
  assert_true(
    { ..sample_worker_report(), schema_version: 2, }.validate().length() > 0,
  )
  assert_true(
    { ..sample_worker_report(), summary: "  ", }.validate().length() > 0,
  )
  assert_true(
    { ..sample_worker_report(), verification: "", }.validate().length() > 0,
  )
  let long = "a".repeat(max_summary_chars + 1)
  assert_true(
    { ..sample_worker_report(), summary: long, }.validate().length() > 0,
  )
}

///|
/// Parse AND validate in one step — the parent tool re-checks the contract
/// at the trust boundary exactly as the child's capture tool enforced it, so
/// both go through the same `parse_submission`; only the error shape differs.
pub fn WorkerReport::parse_validated(
  json : Json,
) -> Result[WorkerReport, String] {
  match parse_submission(json) {
    Err(problems) => Err(problems.join("; "))
    Ok(report) => Ok(report)
  }
}

///|
pub extend WorkerReport with Debug::{to_repr}

///|
pub extend WorkerReport with FromJson::{from_json}

///|
pub extend WorkerReport with Eq::{equal, not_equal}

///|
pub extend WorkerReport with ToJson::{to_json}
