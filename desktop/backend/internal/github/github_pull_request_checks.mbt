///|
pub enum PullRequestChecks {
  ChecksWaiting(retrying~ : Bool)
  ChecksFailed
  // Store the sorted rollup so newly registered checks restart the green wait.
  ChecksPassed(Array[String])
}

///|
/// Tabs, fragments and query parameters do not create separate watches.
pub fn canonical_pull_request_url(url : String) -> String? {
  guard github_pull_request_summary_identity(url) is Some(identity) else {
    return None
  }
  Some(
    "https://\{identity.host.to_lower()}/\{identity.owner.to_lower()}/\{identity.repo.to_lower()}/pull/\{identity.number}",
  )
}

///|
/// gh's PR finder follows every check page for an individual pull request.
async fn pull_request_checks_paginated(
  identity : GithubReviewIdentity,
) -> PullRequestCheckSnapshot {
  let raw = read_pull_request_fields(
    identity, "state,headRefOid,statusCheckRollup",
  )
  match raw {
    { "state": String("CLOSED" | "MERGED"), .. } => ChecksClosed
    {
      "state": String("OPEN"),
      "headRefOid": String(head),
      "statusCheckRollup": rollup,
      ..
    } if valid_check_head(head) =>
      match rollup {
        Array(rows) =>
          ChecksOpen(head~, checks=classify_pull_request_checks(rows))
        Null => ChecksOpen(head~, checks=ChecksWaiting(retrying=false))
        _ => raise InvalidResponse("GitHub returned an invalid check rollup.")
      }
    _ => raise InvalidResponse("GitHub returned an invalid PR CI snapshot.")
  }
}

///|
fn valid_check_head(head : String) -> Bool {
  (head.length() == 40 || head.length() == 64) &&
  head.all(c => (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))
}

///|
fn classify_pull_request_checks(checks : Array[Json]) -> PullRequestChecks {
  let mut passed = false
  let mut waiting = false
  let mut retrying = false
  for check in checks {
    let state = match check {
      {
        "__typename": String("CheckRun"),
        "status": String("COMPLETED"),
        "conclusion": String(conclusion),
        ..
      } => conclusion
      { "__typename": String("CheckRun"), "status": String(status), .. } =>
        status
      { "__typename": String("StatusContext"), "state": String(state), .. } =>
        state
      _ => ""
    }
    match state {
      "SUCCESS" => passed = true
      "NEUTRAL" | "SKIPPED" => ()
      "FAILURE"
      | "ERROR"
      | "TIMED_OUT"
      | "CANCELLED"
      | "ACTION_REQUIRED"
      | "STARTUP_FAILURE"
      | "STALE" => return ChecksFailed
      "QUEUED"
      | "IN_PROGRESS"
      | "PENDING"
      | "EXPECTED"
      | "WAITING"
      | "REQUESTED" => {
        waiting = true
        retrying = true
      }
      _ => waiting = true
    }
  }
  if passed && !waiting {
    let fingerprint = checks.map(check => check.stringify())
    fingerprint.sort()
    ChecksPassed(fingerprint)
  } else {
    ChecksWaiting(retrying~)
  }
}
