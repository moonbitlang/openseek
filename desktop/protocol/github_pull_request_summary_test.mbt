///|
test "a PR summary reply tells no pull request apart from a malformed one" {
  let pr : Json = {
    "number": 1,
    "title": "Example PR",
    "state": "open",
    "draft": false,
    "url": "https://github.com/o/r/pull/1",
    "base": "main",
    "additions": 1,
    "deletions": 0,
    "changed_files": 1,
  }
  let reply : @protocol.GithubPullRequestSummaryReply = @json.from_json({
    "pull_request": pr,
  })
  guard reply.pull_request is Some(summary) else { fail("expected a PR") }
  assert_eq(summary.number, 1)
  @debug.assert_eq(reply.to_json(), { "pull_request": pr })
  for empty in ([{}, { "pull_request": null }] : Array[Json]) {
    let absent : @protocol.GithubPullRequestSummaryReply = @json.from_json(
      empty,
    )
    assert_true(absent.pull_request is None)
    @debug.assert_eq(absent.to_json(), {})
  }
  for invalid in ([{}, "invalid", { "error": "offline" }] : Array[Json]) {
    try
      (
        @json.from_json({ "pull_request": invalid }) :
        @protocol.GithubPullRequestSummaryReply)
    catch {
      JsonDecodeError(_) => ()
    } noraise {
      _ => fail("a malformed pull request was read as a lookup answer")
    }
  }
}

///|
test "a PR summary payload takes only a normalized HTTPS address" {
  let payload : @protocol.GithubPullRequestSummaryPayload = @json.from_json({
    "url": " https://github.com/o/r/pull/1/ ",
    "unknown": true,
  })
  @debug.assert_eq(payload.to_json(), { "url": "https://github.com/o/r/pull/1" })
  for
    invalid in (
      [{}, { "url": null }, { "url": 1 }, { "url": "relative" }] : Array[Json]) {
    try
      (@json.from_json(invalid) : @protocol.GithubPullRequestSummaryPayload)
    catch {
      JsonDecodeError(_) => ()
    } noraise {
      _ => fail("an invalid lookup address was accepted")
    }
  }
}
