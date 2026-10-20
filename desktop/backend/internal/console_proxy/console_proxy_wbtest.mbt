///|
test "sign-in returns only to a path on this origin" {
  assert_eq(
    return_path(Some("/device/d_1/chat?workspace=%2Fws")),
    "/device/d_1/chat?workspace=%2Fws",
  )
  for
    target in [
      "https://evil.example/", "//evil.example/", "/\\evil.example", "cloud", "/a\nb",
    ] {
    assert_eq(return_path(Some(target)), "/cloud")
  }
  assert_eq(return_path(None), "/cloud")
}

///|
test "the PKCE challenge matches RFC 7636's example" {
  assert_eq(
    pkce_challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
    "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
  )
  assert_eq(
    start_url(
      "https://relay.example",
      oauth_state="s",
      challenge="c",
      port=27190,
    ),
    "https://relay.example/v2/auth/account/start?state=s&code_challenge=c&code_challenge_method=S256&port=27190",
  )
}

///|
test "the sign-in page cannot be broken out of by its values" {
  let page = sign_in_markup(
    "{\"token\":\"</script><script>alert(1)</script>\"}",
    return_to="/cloud?q=\"x\"",
  )
  assert_false(page.contains("</script><script>"))
  assert_true(page.contains("localStorage.setItem(\"seekmoon.account.v1\""))
  assert_true(page.contains("location.replace(\"/cloud?q=\\\"x\\\"\")"))
}

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
