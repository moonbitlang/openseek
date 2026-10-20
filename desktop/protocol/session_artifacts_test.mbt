///|
test "typed artifacts round trip and deduplicate by type and URL" {
  let artifacts : @protocol.SessionArtifacts = @json.from_json({
    "artifacts": [
      { "type": "pull_request", "url": " https://github.com/o/r/pull/1/ " },
      { "type": "branch", "url": "https://github.com/o/r/tree/feature/nested" },
      { "type": "pull_request", "url": "https://github.com/o/r/pull/1" },
    ],
  })
  assert_eq(artifacts.artifacts.map(item => item.url), [
    "https://github.com/o/r/pull/1", "https://github.com/o/r/tree/feature/nested",
  ])
  let decoded : @protocol.SessionArtifacts = @json.from_json(
    artifacts.to_json(),
  )
  assert_true(decoded == artifacts)
  assert_true(artifacts.without(artifacts.artifacts[0]).artifacts.length() == 1)
  let empty : @protocol.SessionArtifacts = @json.from_json({ "artifacts": [] })
  assert_true(empty == @protocol.SessionArtifacts::empty())
}

///|
test "missing malformed and unsafe artifacts cannot clear an existing list" {
  for
    invalid in [
      Json::null(),
      {},
      { "artifacts": null },
      { "artifacts": {} },
      { "artifacts": [null] },
      { "artifacts": [{}] },
      { "artifacts": [{ "url": null }] },
      { "artifacts": [{ "url": 1 }] },
      { "artifacts": [{ "branch": "main" }] },
      {
        "artifacts": [
          { "url": "https://github.com/o/r/pull/1", "branch": "main" },
        ],
      },
    ] {
    try (@json.from_json(invalid) : @protocol.SessionArtifacts) catch {
      JsonDecodeError(_) => ()
    } noraise {
      _ => fail("accepted invalid artifact snapshot")
    }
  }
  for
    url in [
      "", "javascript:alert(1)", "file:///tmp/work", "https:///o/r/pull/1", "https://u:p@github.com/o/r",
      "https://github.com/o/\nr", "https://github.com/o/ r", "https://github.com\\evil/o/r",
    ] {
    try
      (
        @json.from_json({ "type": "pull_request", "url": url }) :
        @protocol.SessionArtifact)
    catch {
      JsonDecodeError(_) => ()
    } noraise {
      _ => fail("accepted invalid URL: \{url}")
    }
  }
}

///|
test "artifact identity controls append and removal without mutating old snapshots" {
  let pr : @protocol.SessionArtifact = @json.from_json({
    "type": "pull_request",
    "url": "https://github.com/o/r/pull/1",
  })
  let branch : @protocol.SessionArtifact = @json.from_json({
    "type": "branch",
    "url": "https://github.com/o/r/pull/1",
  })
  let empty = @protocol.SessionArtifacts::empty()
  let first = empty.attach(pr)
  let both = first.attach(branch).attach(pr)
  assert_eq(empty.artifacts.length(), 0)
  assert_eq(first.artifacts, [pr])
  assert_eq(both.artifacts, [pr, branch])
  assert_eq(both.without(pr).artifacts, [branch])
  assert_eq(both.without(branch).artifacts, [pr])
  let decoded : @protocol.SessionArtifacts = @json.from_json(both.to_json())
  assert_eq(decoded, both)
  let removal : @protocol.SessionArtifactRemovePayload = {
    session: "s1",
    artifact: branch,
  }
  let decoded_removal : @protocol.SessionArtifactRemovePayload = @json.from_json(
    removal.to_json(),
  )
  assert_eq(decoded_removal, removal)
}

///|
test "artifacts require a supported explicit type" {
  let invalid_entries : Array[Json] = [
    { "url": "https://github.com/o/r/pull/1" },
    { "type": null, "url": "https://github.com/o/r/pull/1" },
    { "type": "file", "url": "https://github.com/o/r/pull/1" },
    {
      "type": "pull_request",
      "url": "https://github.com/o/r/pull/1",
      "extra": true,
    },
  ]
  for invalid in invalid_entries {
    try (@json.from_json(invalid) : @protocol.SessionArtifact) catch {
      JsonDecodeError(_) => ()
    } noraise {
      _ => fail("accepted invalid artifact type or fields")
    }
  }
}

///|
test "artifact changed notifications round trip across desktop transports" {
  let notification = @protocol.Notification::SessionArtifactsChanged({
    session: "s1",
  })
  assert_eq(notification.wire_name(), "session.artifacts_changed")
  assert_true(
    @protocol.Notification::from_wire(
      notification.wire_name(),
      notification.params(),
    ) ==
    Some(notification),
  )
}
