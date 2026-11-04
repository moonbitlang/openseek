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
