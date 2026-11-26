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

///|
test "batch PR summary payload normalizes and deduplicates URLs" {
  let payload : @protocol.GithubPullRequestSummariesPayload = @json.from_json({
    "urls": [
      " https://github.com/o/r/pull/1/ ", "https://github.com/o/r/pull/1", "https://github.com/o/r/pull/2",
    ],
  })
  assert_eq(payload.urls, [
    "https://github.com/o/r/pull/1", "https://github.com/o/r/pull/2",
  ])
  @debug.assert_eq(payload.to_json(), {
    "urls": ["https://github.com/o/r/pull/1", "https://github.com/o/r/pull/2"],
  })
  for
    invalid in ([{}, { "urls": null }, { "urls": ["not-a-url"] }] : Array[Json]) {
    try
      (@json.from_json(invalid) : @protocol.GithubPullRequestSummariesPayload)
    catch {
      JsonDecodeError(_) => ()
    } noraise {
      _ => fail("invalid batch PR summary payload was accepted")
    }
  }
}

///|
test "batch PR summary reply roundtrips pull request map" {
  let pr : Json = {
    "number": 42,
    "title": "Sidebar PR status",
    "state": "merged",
    "draft": false,
    "url": "https://github.com/o/r/pull/42",
    "base": "main",
    "additions": 10,
    "deletions": 2,
    "changed_files": 3,
  }
  let reply : @protocol.GithubPullRequestSummariesReply = @json.from_json({
    "pull_requests": { "https://github.com/o/r/pull/42": pr },
  })
  guard reply.pull_requests.get("https://github.com/o/r/pull/42")
    is Some(summary) else {
    fail("expected PR summary in batch reply")
  }
  assert_eq(summary.number, 42)
  assert_eq(summary.state, "merged")
  @debug.assert_eq(reply.to_json(), {
    "pull_requests": { "https://github.com/o/r/pull/42": pr },
  })
}
