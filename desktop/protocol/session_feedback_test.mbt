///|
test "feedback receipts require an id and ignore link metadata" {
  for
    body in (
      [{ "id": "fb_test" }, { "id": "fb_test", "url": false }] : Array[Json]) {
    let receipt : @protocol.FeedbackReceipt = @json.from_json(body)
    assert_eq(receipt.id, "fb_test")
  }
  for body in ([{}, { "id": null }, { "id": "  " }] : Array[Json]) {
    try (@json.from_json(body) : @protocol.FeedbackReceipt) catch {
      JsonDecodeError(_) => ()
    } noraise {
      _ => fail("accepted an invalid feedback id")
    }
  }
}

///|
test "local feedback command preserves the submitted id and failure reason" {
  let replies : Array[@protocol.SessionFeedbackReply] = [
    Submitted(id="fb_test"),
    SignInRequired,
    Failed(message="Storage unavailable"),
  ]
  for reply in replies {
    let decoded : @protocol.SessionFeedbackReply = @json.from_json(
      ToJson::to_json(reply),
    )
    assert_true(decoded == reply)
  }
}
