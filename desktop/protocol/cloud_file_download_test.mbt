///|
test "Cloud download codecs retain exact cache bytes and optional absence" {
  let caches : Array[@protocol.CloudFileCache?] = [
    None,
    Some({ etag: "W/\"opaque\"", data_base64: "77u/YQ0K", }),
  ]
  for cached in caches {
    let payload : @protocol.CloudFileDownloadPayload = {
      account: "a",
      session: "s",
      path: "dir/file #.txt",
      cached,
    }
    let decoded : @protocol.CloudFileDownloadPayload = @json.from_json(
      payload.to_json(),
    )
    assert_eq(decoded, payload)
  }
  let absent : @protocol.CloudFileDownloadPayload = @json.from_json({
    "account": "a",
    "session": "s",
    "path": "x",
    "cached": null,
  })
  assert_true(absent.cached is None)
  for
    reply in [
      @protocol.Saved(path="/Downloads/file (1).txt", revealed=true),
      Saved(path="/Downloads/file.txt", revealed=false),
      Failed(message="HTTP 403"),
    ] {
    let decoded : @protocol.CloudFileDownloadReply = @json.from_json(
      reply.to_json(),
    )
    assert_eq(decoded, reply)
  }
  assert_true(
    refused(() => {
      let _ : @protocol.CloudFileDownloadPayload = @json.from_json({
        "account": "a",
        "session": "s",
        "path": "x",
        "cached": { "etag": "x" },
      })
    }),
  )
  assert_true(
    refused(() => {
      let _ : @protocol.CloudFileDownloadReply = @json.from_json({
        "kind": "saved",
        "path": "x",
      })
    }),
  )
}
