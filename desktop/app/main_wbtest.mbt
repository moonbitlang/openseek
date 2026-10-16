///|
test "shared server URL does not consume the account API origin override" {
  let matches = command.parse(argv=[], env={
    "OPENSEEK_SERVER_URL": "https://account.example",
  })
  assert_eq(matches.values.get("server-url"), None)
  let matches = command.parse(argv=[], env={
    "SEEKMOON_SHARED_SERVER_URL": "http://localhost:1234/",
  })
  assert_eq(matches.values.get("server-url"), Some(["http://localhost:1234/"]))
  let matches = command.parse(argv=["--server-url", "http://localhost:5678/"], env={
    "SEEKMOON_SHARED_SERVER_URL": "http://localhost:1234/",
  })
  assert_eq(matches.values.get("server-url"), Some(["http://localhost:5678/"]))
}
