///|
priv suberror AppServerFailed {
  AppServerFailed(String)
}

///|
impl Show for AppServerFailed with fn output(self, logger) {
  match self {
    AppServerFailed(message) => logger.write_string(message)
  }
}

///|
async test "Codex endpoints return original handler errors as replies" {
  let asynchronous = Endpoint::codex(@commands.codex_status, _ => {
    @async.sleep(0)
    raise AppServerFailed(
      "Codex app-server request account/read failed: token unavailable",
    )
  })
  let asynchronous_reply = asynchronous.invoke({})
  @debug.assert_eq(asynchronous_reply, {
    "error": "Codex app-server request account/read failed: token unavailable",
  })
  let synchronous = Endpoint::codex_sync(@commands.codex_status, _ => {
    raise AppServerFailed(
      "Codex app-server request config/read failed: invalid TOML",
    )
  })
  let synchronous_reply = synchronous.invoke({})
  @debug.assert_eq(synchronous_reply, {
    "error": "Codex app-server request config/read failed: invalid TOML",
  })
}

///|
async test "a payload that does not decode raises the decoder's error" {
  let endpoint = Endpoint::sync(@commands.fs_watch, _ => Acknowledged)
  try endpoint.invoke({ "root": 7 }) catch {
    @json.JsonDecodeError(_) => ()
    error => raise error
  } noraise {
    _ => fail("a malformed payload was accepted")
  }
}
