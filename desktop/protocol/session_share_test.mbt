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
