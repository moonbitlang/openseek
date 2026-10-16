///|
test "share reply requires tagged and typed outcomes" {
  let values : Array[@protocol.SessionShareReply] = [
    Shared(url="http://shares.test/v1/shares/a"),
    SignInRequired,
    Failed(message="Sharing unavailable"),
  ]
  for value in values {
    let decoded : @protocol.SessionShareReply = @json.from_json(value.to_json())
    assert_true(decoded == value)
  }
  for
    invalid in [
      Json::null(),
      {},
      { "status": "shared" },
      { "status": "shared", "url": null },
      { "status": "failed", "message": 1 },
      { "status": "uploading" },
    ] {
    try (@json.from_json(invalid) : @protocol.SessionShareReply) catch {
      JsonDecodeError(_) => ()
    } noraise {
      _ => fail("\{invalid.stringify()} must not decode")
    }
  }
}

///|
test "share progress and request round trip with request identity" {
  let request : @protocol.SessionSharePayload = {
    generation: 7,
    source: { session: "a", workspace: "/w", title: "A", archived: false, },
  }
  let decoded : @protocol.SessionSharePayload = @json.from_json(
    request.to_json(),
  )
  assert_true(decoded == request)
  json_inspect(@protocol.Uploading(attempt=1, percent=42).to_json(), content=[
    "Uploading",
    { "attempt": 1, "percent": 42 },
  ])
  for
    progress in [
      @protocol.Preparing,
      Connecting(attempt=1),
      Uploading(attempt=1, percent=42),
      Waiting(attempt=2),
    ] {
    let payload : @protocol.SessionShareProgress = { generation: 7, progress, }
    let decoded : @protocol.SessionShareProgress = @json.from_json(
      payload.to_json(),
    )
    assert_true(decoded == payload)
  }
}

///|
test "share progress codecs reject missing null and malformed fields" {
  for
    invalid in [
      Json::null(),
      {},
      { "generation": 7 },
      { "generation": null, "progress": "Preparing" },
      { "generation": "7", "progress": "Preparing" },
      { "generation": 7, "progress": null },
      { "generation": 7, "progress": "Unknown" },
      { "generation": 7, "progress": ["Uploading", { "attempt": 1 }] },
      {
        "generation": 7,
        "progress": ["Uploading", { "attempt": 1, "percent": null }],
      },
      { "generation": 7, "progress": ["Connecting", { "attempt": "1" }] },
    ] {
    try (@json.from_json(invalid) : @protocol.SessionShareProgress) catch {
      JsonDecodeError(_) => ()
    } noraise {
      _ => fail("invalid progress must not decode")
    }
  }
  for
    invalid in [
      Json::null(),
      {},
      { "generation": 1, "source": null },
      { "generation": null, "source": {} },
      { "generation": 1, "source": {} },
    ] {
    try (@json.from_json(invalid) : @protocol.SessionSharePayload) catch {
      JsonDecodeError(_) => ()
    } noraise {
      _ => fail("invalid request must not decode")
    }
  }
  let progress : @protocol.SessionShareProgress = @json.from_json({
    "generation": 7,
    "progress": ["Uploading", { "attempt": 1, "percent": 42, "future": true }],
    "future": true,
  })
  assert_true(progress.progress is Uploading(attempt=1, percent=42))
}
