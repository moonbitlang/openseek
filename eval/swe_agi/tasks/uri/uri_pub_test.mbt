///|
test "component/scheme/lowercase" {
  let uri = Uri::parse("http://example.com/")
  assert_eq(uri.scheme(), "http")
}

///|
test "component/scheme/uppercase-normalized" {
  let uri = Uri::parse("HTTP://example.com/")
  // Schemes are case-insensitive, may be normalized to lowercase
  assert_true(uri.scheme() == "http" || uri.scheme() == "HTTP")
}

///|
test "component/scheme/mixed-case" {
  let uri = Uri::parse("HtTp://example.com/")
  assert_true(uri.scheme() == "http" || uri.scheme() == "HtTp")
}

///|
test "component/scheme/with-numbers" {
  let uri = Uri::parse("h323://example.com/")
  assert_eq(uri.scheme(), "h323")
}

///|
test "component/scheme/with-plus" {
  let uri = Uri::parse("coap+tcp://example.com/")
  assert_eq(uri.scheme(), "coap+tcp")
}

///|
test "component/scheme/with-dash" {
  let uri = Uri::parse("coap-tcp://example.com/")
  assert_eq(uri.scheme(), "coap-tcp")
}

///|
test "component/scheme/with-dot" {
  let uri = Uri::parse("iris.beep://example.com/")
  assert_eq(uri.scheme(), "iris.beep")
}

///|
test "component/scheme/single-letter" {
  let uri = Uri::parse("x://example.com/")
  assert_eq(uri.scheme(), "x")
}

///|
test "component/userinfo/simple" {
  let uri = Uri::parse("http://user@example.com/")
  assert_eq(uri.userinfo(), Some("user"))
}

///|
test "component/userinfo/with-password" {
  let uri = Uri::parse("http://user:pass@example.com/")
  assert_eq(uri.userinfo(), Some("user:pass"))
}

///|
test "component/userinfo/empty" {
  let uri = Uri::parse("http://@example.com/")
  assert_eq(uri.userinfo(), Some(""))
}

///|
test "component/userinfo/percent-encoded" {
  let uri = Uri::parse("http://user%40name@example.com/")
  assert_eq(uri.userinfo(), Some("user%40name"))
}

///|
test "component/userinfo/complex" {
  let uri = Uri::parse("http://user:p%40ss:word@example.com/")
  assert_eq(uri.userinfo(), Some("user:p%40ss:word"))
}

///|
test "component/userinfo/none" {
  let uri = Uri::parse("http://example.com/")
  assert_eq(uri.userinfo(), None)
}
