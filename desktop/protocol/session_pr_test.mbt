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
