///|
async test "Codex endpoints return original handler errors as replies" {
  let asynchronous = Endpoint::codex(@commands.codex_status, async fn(_) {
    @async.sleep(0)
    raise InvalidEndpointPayload(
      "Codex app-server request account/read failed: token unavailable",
    )
  })
  let asynchronous_reply = asynchronous.invoke_remote({})
  @debug.assert_eq(asynchronous_reply, {
    "error": "Codex app-server request account/read failed: token unavailable",
  })
  let synchronous = Endpoint::codex_sync(@commands.codex_status, _ => {
    raise InvalidEndpointPayload(
      "Codex app-server request config/read failed: invalid TOML",
    )
  })
  let synchronous_reply = synchronous.invoke_remote({})
  @debug.assert_eq(synchronous_reply, {
    "error": "Codex app-server request config/read failed: invalid TOML",
  })
}
