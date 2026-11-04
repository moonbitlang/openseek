///|
test "forwarding drops this hop's headers and keeps relay redirects local" {
  for
    name in [
      "Host", "Cookie", "origin", "Referer", "Accept-Encoding", "Content-Length",
    ] {
    assert_true(dropped_request_header(name))
  }
  for name in ["Authorization", "Content-Type", "Accept"] {
    assert_false(dropped_request_header(name))
  }
  assert_true(dropped_response_header("Set-Cookie"))
  assert_false(dropped_response_header("Content-Type"))
  assert_eq(
    local_location(
      "https://relay.example/v2/x?y",
      relay="https://relay.example",
    ),
    "/v2/x?y",
  )
  assert_eq(
    local_location("https://github.com/login", relay="https://relay.example"),
    "https://github.com/login",
  )
  assert_eq(
    local_location(
      "https://relay.example.evil/x",
      relay="https://relay.example",
    ),
    "https://relay.example.evil/x",
  )
  assert_eq(socket_origin("https://relay.example"), "wss://relay.example")
  assert_eq(socket_origin("http://127.0.0.1:8080"), "ws://127.0.0.1:8080")
}

///|
test "close codes that cannot be sent become GoingAway" {
  assert_true(sendable_close(Normal) is Normal)
  assert_true(sendable_close(Abnormal) is GoingAway)
  assert_true(sendable_close(Other(4001)) is Other(4001))
  assert_true(sendable_close(Other(1015)) is GoingAway)
}
