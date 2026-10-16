///|
test "PR detail requires metadata and distinguishes no detail from lookup failure" {
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
  let detail : @protocol.GitPullRequest = @json.from_json(pr)
  assert_eq(detail.number, 1)
  assert_true(detail.head_url is None)
  @debug.assert_eq(detail.to_json(), pr)
  for empty in ([{}, { "pull_request": null }] : Array[Json]) {
    let absent : @protocol.GitPrDetailReply = @json.from_json(empty)
    assert_true(absent.pull_request is None)
    @debug.assert_eq(absent.to_json(), {})
  }
  for invalid in ([{}, "invalid", { "error": "offline" }] : Array[Json]) {
    try
      (@json.from_json({ "pull_request": invalid }) : @protocol.GitPrDetailReply)
    catch {
      JsonDecodeError(_) => ()
    } noraise {
      _ => fail("invalid metadata was treated as a successful lookup")
    }
  }
  guard pr is Object(fields) else { fail("expected object") }
  let invalid_head = fields.copy()
  invalid_head["head_url"] = 1
  try (@json.from_json(Json(invalid_head)) : @protocol.GitPullRequest) catch {
    JsonDecodeError(_) => ()
  } noraise {
    _ => fail("invalid head URL accepted")
  }
  let with_head : @protocol.GitPullRequest = {
    ..detail,
    head_url: Some("https://github.com/fork/r/tree/topic"),
  }
  let round_trip : @protocol.GitPullRequest = @json.from_json(
    with_head.to_json(),
  )
  assert_true(round_trip == with_head)
  let reply : @protocol.GitPrDetailReply = { pull_request: Some(with_head), }
  @debug.assert_eq(reply.to_json(), { "pull_request": with_head.to_json() })
  let decoded : @protocol.GitPrDetailReply = @json.from_json(reply.to_json())
  assert_true(decoded == reply)
}

///|
test "remote PR details accept a URL without session membership" {
  let payload : @protocol.GitPrDetailPayload = @json.from_json({
    "url": " https://github.com/o/r/pull/1/ ",
    "unknown": true,
  })
  @debug.assert_eq(payload.to_json(), { "url": "https://github.com/o/r/pull/1" })
  for
    invalid in (
      [{}, { "url": null }, { "url": 1 }, { "url": "relative" }] : Array[Json]) {
    try (@json.from_json(invalid) : @protocol.GitPrDetailPayload) catch {
      JsonDecodeError(_) => ()
    } noraise {
      _ => fail("invalid lookup URL accepted")
    }
  }
}
