///|
test "Cloud cached content retains only the server's opaque HTTP validator" {
  let etag = "W/\"content-v1-opaque\""
  let reply = validated_reply(
    {
      "kind": "content",
      "content": "hello",
      "absolute": "/hello.txt",
      "sig": "wire-signature",
    },
    Some(etag),
  )
  assert_eq(
    reply,
    @protocol.Content(content="hello", absolute="/hello.txt", sig=etag),
  )
  assert_true(validated_reply({ "kind": "oversized" }, None) is Oversized)
  assert_true(validated_reply({ "kind": "binary" }, None) is Binary)
  let binary = validated_reply(
    {
      "kind": "binary_content",
      "data_base64": "AA==",
      "media_type": "image/png",
      "sig": "wire",
    },
    Some(etag),
  )
  assert_eq(
    binary,
    @protocol.BinaryContent(
      data_base64="AA==",
      media_type="image/png",
      sig=etag,
    ),
  )
  for etag in [None, Some("")] {
    let malformed = try {
      ignore(
        validated_reply(
          {
            "kind": "content",
            "content": "hello",
            "absolute": "/hello.txt",
            "sig": "wire",
          },
          etag,
        ),
      )
      false
    } catch {
      RequestError(Malformed) => true
      _ => false
    }
    assert_true(malformed)
  }
}
