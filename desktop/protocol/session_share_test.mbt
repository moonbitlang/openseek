///|
test "share reply requires tagged and typed outcomes" {
  let values : Array[@protocol.SessionShareReply] = [
    Shared(
      url="http://shares.test/v1/shares/a",
      expires_at="2026-09-22T00:00:00Z",
    ),
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
      { "status": "shared", "url": null, "expires_at": "date" },
      { "status": "failed", "message": 1 },
      { "status": "uploading" },
    ] {
    let decoded : Result[@protocol.SessionShareReply, Error] = Ok(
      @json.from_json(invalid),
    ) catch {
      e => Err(e)
    }
    assert_true(decoded is Err(_))
  }
}
