///|
test "account credential codecs reject device tokens and require stable identity" {
  let json : Json = {
    "token": "ts_fixture",
    "user": { "user_id": "123", "login": "octocat", "avatar_url": "" },
  }
  let session : @protocol.AccountSession = @json.from_json(json)
  assert_eq(session.user.user_id, "123")
  assert_eq(session.to_json(), json)
  let invalids : Array[Json] = [
    {
      "token": "odt_device",
      "user": { "user_id": "123", "login": "octocat", "avatar_url": "" },
    },
    { "token": "ts_fixture", "user": { "login": "octocat", "avatar_url": "" } },
    {
      "token": "ts_fixture",
      "user": { "user_id": "", "login": "octocat", "avatar_url": "" },
    },
  ]
  for invalid in invalids {
    let result : Result[@protocol.AccountSession, Error] = Ok(
      @json.from_json(invalid),
    ) catch {
      error => Err(error)
    }
    assert_true(result is Err(_))
  }
}

///|
test "snapshot save requires HTML and a session name, not a destination path" {
  let json : Json = {
    "session": "cloud-session",
    "html": "<html>snapshot</html>",
    "path": "/ignored",
  }
  let payload : @protocol.SnapshotSavePayload = @json.from_json(json)
  assert_eq(payload.to_json(), {
    "session": "cloud-session",
    "html": "<html>snapshot</html>",
  })
  let invalids : Array[Json] = [
    { "session": "cloud-session" },
    { "session": "cloud-session", "html": 7 },
    { "html": "snapshot" },
  ]
  for invalid in invalids {
    let result : Result[@protocol.SnapshotSavePayload, Error] = Ok(
      @json.from_json(invalid),
    ) catch {
      error => Err(error)
    }
    assert_true(result is Err(_))
  }
}
