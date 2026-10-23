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
      null,
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
test "share phases round trip with request identity" {
  json_inspect(@protocol.Uploading(attempt=1).to_json(), content=[
    "Uploading",
    { "attempt": 1 },
  ])
  for
    progress in [
      @protocol.Preparing,
      Connecting(attempt=1),
      Uploading(attempt=1),
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
      null,
      {},
      { "generation": 7 },
      { "generation": null, "progress": "Preparing" },
      { "generation": "7", "progress": "Preparing" },
      { "generation": 7, "progress": null },
      { "generation": 7, "progress": "Unknown" },
      { "generation": 7, "progress": ["Uploading", {}] },
      { "generation": 7, "progress": ["Uploading", { "attempt": null }] },
      { "generation": 7, "progress": ["Connecting", { "attempt": "1" }] },
    ] {
    try (@json.from_json(invalid) : @protocol.SessionShareProgress) catch {
      JsonDecodeError(_) => ()
    } noraise {
      _ => fail("invalid progress must not decode")
    }
  }
  let progress : @protocol.SessionShareProgress = @json.from_json({
    "generation": 7,
    "progress": ["Uploading", { "attempt": 1, "future": true }],
    "future": true,
  })
  assert_true(progress.progress is Uploading(attempt=1))
}

///|
test "share request requires explicit authority and rejects account tokens as upload grants" {
  for
    authorization in [
      @protocol.LocalAccount(user_id="user-1"),
      UploadGrant(upload_token="sug_fixture"),
    ] {
    let request : @protocol.SessionSharePayload = {
      generation: 3,
      idempotency_key: "a".repeat(64),
      authorization,
      source: {
        session: "session",
        workspace: "/workspace",
        title: "Title",
        archived: false,
      },
    }
    let decoded : @protocol.SessionSharePayload = @json.from_json(
      request.to_json(),
    )
    assert_true(decoded == request)
  }
  for token in ["ts_account", "odt_device", ""] {
    let result : Result[@protocol.ShareAuthorization, Error] = try
      @json.from_json({ "kind": "upload_grant", "upload_token": token })
    catch {
      error => Err(error)
    } noraise {
      authorization => Ok(authorization)
    }
    assert_true(result is Err(_))
  }
}

///|
test "file share requests preserve owner-side paths and explicit upload authority" {
  let request : @protocol.FileSharePayload = {
    source: { root: Some("/workspace"), path: "docs/报告.bin", },
    idempotency_key: "a".repeat(64),
    authorization: UploadGrant(upload_token="sug_fixture"),
  }
  let decoded : @protocol.FileSharePayload = @json.from_json(request.to_json())
  assert_true(decoded == request)
  for key in ["source", "idempotency_key", "authorization"] {
    let invalid : Map[String, Json] = {
      "source": request.source.to_json(),
      "idempotency_key": Json(request.idempotency_key),
      "authorization": request.authorization.to_json(),
    }
    invalid.remove(key)
    try (@json.from_json(Json(invalid)) : @protocol.FileSharePayload) catch {
      JsonDecodeError(_) => ()
    } noraise {
      _ => fail("missing share request field must be rejected")
    }
  }
}
