///|
test "PR bindings are URL-only complete lists with stable deduplication" {
  let bindings : @protocol.SessionPrBindings = @json.from_json({
    "bindings": [
      { "url": " https://github.com/o/r/pull/1/ " },
      { "url": "https://github.com/o/r/tree/feature/nested" },
      { "url": "https://github.com/o/r/pull/1" },
    ],
  })
  assert_eq(bindings.bindings.map(item => item.url), [
    "https://github.com/o/r/pull/1", "https://github.com/o/r/tree/feature/nested",
  ])
  let decoded : @protocol.SessionPrBindings = @json.from_json(
    bindings.to_json(),
  )
  assert_true(decoded == bindings)
  assert_true(
    bindings.without("https://github.com/o/r/pull/1").bindings.length() == 1,
  )
  let empty : @protocol.SessionPrBindings = @json.from_json({ "bindings": [] })
  assert_true(empty == @protocol.SessionPrBindings::empty())
}

///|
test "missing malformed and unsafe bindings cannot clear an existing list" {
  for
    invalid in [
      Json::null(),
      {},
      { "bindings": null },
      { "bindings": {} },
      { "bindings": [null] },
      { "bindings": [{}] },
      { "bindings": [{ "url": null }] },
      { "bindings": [{ "url": 1 }] },
      { "bindings": [{ "branch": "main" }] },
      {
        "bindings": [
          { "url": "https://github.com/o/r/pull/1", "branch": "main" },
        ],
      },
    ] {
    try (@json.from_json(invalid) : @protocol.SessionPrBindings) catch {
      JsonDecodeError(_) => ()
    } noraise {
      _ => fail("accepted invalid replacement")
    }
  }
  for
    url in [
      "", "javascript:alert(1)", "file:///tmp/work", "https:///o/r/pull/1", "https://u:p@github.com/o/r",
      "https://github.com/o/\nr", "https://github.com/o/ r", "https://github.com\\evil/o/r",
    ] {
    try (@json.from_json({ "url": url }) : @protocol.SessionPrBinding) catch {
      JsonDecodeError(_) => ()
    } noraise {
      _ => fail("accepted invalid URL: \{url}")
    }
  }
}

///|
test "PR changed notifications round trip across desktop transports" {
  let notification = @protocol.Notification::SessionPrChanged({ session: "s1", })
  assert_eq(notification.wire_name(), "session.pr_changed")
  assert_true(
    @protocol.Notification::from_wire(
      notification.wire_name(),
      notification.params(),
    ) ==
    Some(notification),
  )
}

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
  let detail : @protocol.SessionPrDetail = @json.from_json({
    "pull_request": pr,
    "head_url": null,
    "unknown": true,
  })
  assert_eq(detail.pull_request.number, 1)
  assert_true(detail.head_url is None)
  @debug.assert_eq(detail.to_json(), { "pull_request": pr })
  for empty in ([{}, { "detail": null }] : Array[Json]) {
    let absent : @protocol.SessionPrDetailReply = @json.from_json(empty)
    assert_true(absent.detail is None)
    @debug.assert_eq(absent.to_json(), {})
  }
  let invalid_details : Array[Json] = [
    {},
    { "pull_request": null },
    { "pull_request": "invalid" },
    { "error": "offline" },
    { "pull_request": pr, "head_url": 1 },
  ]
  for invalid in invalid_details {
    try
      (@json.from_json({ "detail": invalid }) : @protocol.SessionPrDetailReply)
    catch {
      JsonDecodeError(_) => ()
    } noraise {
      _ => fail("invalid metadata was treated as a successful lookup")
    }
  }
  let with_head : @protocol.SessionPrDetail = {
    ..detail,
    head_url: Some("https://github.com/fork/r/tree/topic"),
  }
  let round_trip : @protocol.SessionPrDetail = @json.from_json(
    with_head.to_json(),
  )
  assert_true(round_trip == with_head)
  let reply : @protocol.SessionPrDetailReply = { detail: Some(with_head), }
  @debug.assert_eq(reply.to_json(), { "detail": with_head.to_json() })
  let decoded : @protocol.SessionPrDetailReply = @json.from_json(
    reply.to_json(),
  )
  assert_true(decoded == reply)
}
