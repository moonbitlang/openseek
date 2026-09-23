///|
/// One `gh pr list` element, spelled the way gh spells it, for the tests to
/// vary field by field.
fn pull_request_json(
  number~ : Int,
  state~ : String,
  draft~ : Bool,
  checks? : Json = Json::null(),
  cross? : Bool = false,
) -> Json {
  {
    "number": Json(number.to_double()),
    "title": "Add a changed-files explorer",
    "state": "\{state}",
    "url": "https://github.test/acme/app/pull/\{number}",
    "isDraft": Json(draft),
    "baseRefName": "main",
    "additions": 2972,
    "deletions": 287,
    "changedFiles": 18,
    "statusCheckRollup": checks,
    "isCrossRepository": Json(cross),
  }
}

///|
test "A fork's pull request does not answer for this checkout's branch" {
  // `--head` matches the branch name in every repository that forked this one,
  // so an open pull request from someone else's fork can arrive first.
  let outsider = pull_request_json(
    number=900,
    state="OPEN",
    draft=false,
    cross=true,
  )
  let mine = pull_request_json(number=712, state="MERGED", draft=false)
  guard pick_pull_request([outsider, mine]) is Some(picked) else {
    fail("expected a pull request")
  }
  // Merged and second in the list, but the only one whose head is here.
  assert_eq(picked.number, 712)
  // A fork checkout has nothing but cross-repository pull requests; dropping
  // them all would leave the chip blank, so there the filter stands down.
  guard pick_pull_request([outsider]) is Some(only) else {
    fail("a fork checkout still has its own pull request")
  }
  assert_eq(only.number, 900)
}

///|
test "A pull request record missing a rendered field is not shown at all" {
  assert_eq(pick_pull_request([]), None)
  // An unknown state is a gh whose output this does not understand.
  assert_eq(
    pick_pull_request([pull_request_json(number=1, state="LOCKED", draft=false)]),
    None,
  )
  let json = pull_request_json(number=1, state="OPEN", draft=false)
  guard json is Object(fields) else { fail("expected an object") }
  for absent in ["title", "url", "number", "additions", "changedFiles"] {
    let entries : Map[String, Json] = Map([])
    for key, value in fields {
      if key != absent {
        entries[key] = value
      }
    }
    assert_eq(parse_pull_request(Json(entries)), None)
  }
}

///|
test "An open pull request outranks the branch's older merged one" {
  let candidates = [
    pull_request_json(number=712, state="OPEN", draft=true),
    pull_request_json(number=700, state="MERGED", draft=false),
  ]
  guard pick_pull_request(candidates) is Some(picked) else {
    fail("expected a pull request")
  }
  assert_eq(picked.number, 712)
  assert_eq(picked.state, "open")
  // A draft stays open — it is a pull request that refuses to merge, not a
  // fourth state — and GitHub's own totals come through unrounded.
  assert_true(picked.draft)
  assert_eq(
    (picked.additions, picked.deletions, picked.changed_files),
    (2972, 287, 18),
  )
  // Order still decides once no candidate is open.
  guard pick_pull_request(candidates[1:].to_owned()) is Some(merged) else {
    fail("expected the merged pull request")
  }
  assert_eq(merged.state, "merged")
}
