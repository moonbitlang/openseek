///|
test "parse failure - missing scheme" {
  let url = @url.Url::parse("://no-scheme")
  assert_true(url is None)
}

///|
test "parse failure - empty input" {
  let url = @url.Url::parse("")
  assert_true(url is None)
}

///|
test "parse failure - unclosed IPv6" {
  let url = @url.Url::parse("http://[::1/")
  assert_true(url is None)
}

///|
test "parse failure - port out of range" {
  let url = @url.Url::parse("http://example.com:999999/")
  assert_true(url is None)
}

///|
test "parse failure - invalid IPv6" {
  let url = @url.Url::parse("http://[::::::]/")
  assert_true(url is None)
}

///|
test "parse failure - IPv4 too many parts" {
  let url = @url.Url::parse("http://1.2.3.4.5/")
  assert_true(url is None)
}

///|
test "parse basic http URL" {
  let url = @url.Url::parse("http://example.com/")
  guard url is Some(url) else { fail("parse failed") }
  assert_eq(url.to_string(), "http://example.com/")
}

///|
test "parse https URL" {
  let url = @url.Url::parse("https://example.com/")
  guard url is Some(url) else { fail("parse failed") }
  assert_eq(url.to_string(), "https://example.com/")
}

///|
test "parse URL with path" {
  let url = @url.Url::parse("http://example.com/a/b/c")
  guard url is Some(url) else { fail("parse failed") }
  assert_eq(url.pathname(), "/a/b/c")
}

///|
test "parse URL with query string" {
  let url = @url.Url::parse("http://example.com/?q=test")
  guard url is Some(url) else { fail("parse failed") }
  assert_eq(url.search(), "?q=test")
}

///|
test "parse URL with fragment" {
  let url = @url.Url::parse("http://example.com/#section")
  guard url is Some(url) else { fail("parse failed") }
  assert_eq(url.hash(), "#section")
}

///|
test "parse URL with all components" {
  let url = @url.Url::parse("http://example.com/path?query=value#fragment")
  guard url is Some(url) else { fail("parse failed") }
  assert_eq(url.protocol(), "http:")
  assert_eq(url.hostname(), "example.com")
  assert_eq(url.pathname(), "/path")
  assert_eq(url.search(), "?query=value")
  assert_eq(url.hash(), "#fragment")
}

///|
test "parse URL with port" {
  let url = @url.Url::parse("http://example.com:8080/")
  guard url is Some(url) else { fail("parse failed") }
  assert_eq(url.port(), "8080")
  assert_eq(url.host(), "example.com:8080")
}

///|
test "WPT #0" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("http://example\t.\norg", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://example.org/")
}

///|
test "WPT #1" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse(
    "http://user:pass@foo:21/bar;par?b#c",
    base=base_url,
  )
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://user:pass@foo:21/bar;par?b#c")
}

///|
test "WPT #2" {
  let result = @url.Url::parse("https://test:@test")
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "https://test@test/")
}

///|
test "WPT #3" {
  let result = @url.Url::parse("https://:@test")
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "https://test/")
}

///|
test "WPT #4" {
  let result = @url.Url::parse("non-special://test:@test/x")
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "non-special://test@test/x")
}

///|
test "WPT #5" {
  let result = @url.Url::parse("non-special://:@test/x")
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "non-special://test/x")
}

///|
test "WPT #6" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("http:foo.com", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://example.org/foo/foo.com")
}

///|
test "WPT #7" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("\t   :foo.com   \n", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://example.org/foo/:foo.com")
}

///|
test "WPT #8" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse(" foo.com  ", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://example.org/foo/foo.com")
}

///|
test "WPT #9" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("a:\t foo.com", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "a: foo.com")
}

///|
test "WPT #10" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("http://f:21/ b ? d # e ", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://f:21/%20b%20?%20d%20#%20e")
}

///|
test "WPT #11" {
  let result = @url.Url::parse("lolscheme:x x#x x")
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "lolscheme:x x#x%20x")
}

///|
test "WPT #12" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("http://f:/c", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://f/c")
}

///|
test "WPT #13" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("http://f:0/c", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://f:0/c")
}

///|
test "WPT #14" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("http://f:00000000000000/c", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://f:0/c")
}

///|
test "WPT #15" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse(
    "http://f:00000000000000000000080/c",
    base=base_url,
  )
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://f/c")
}

///|
test "WPT #16" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("http://f:b/c", base=base_url)
  guard result is None else {
    fail("Expected failure but got: \{result.unwrap().to_string().escape()}")
  }
}

///|
test "WPT #17" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("http://f: /c", base=base_url)
  guard result is None else {
    fail("Expected failure but got: \{result.unwrap().to_string().escape()}")
  }
}

///|
test "WPT #18" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("http://f:\n/c", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://f/c")
}

///|
test "WPT #19" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("http://f:fifty-two/c", base=base_url)
  guard result is None else {
    fail("Expected failure but got: \{result.unwrap().to_string().escape()}")
  }
}

///|
test "WPT #20" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("http://f:999999/c", base=base_url)
  guard result is None else {
    fail("Expected failure but got: \{result.unwrap().to_string().escape()}")
  }
}

///|
test "WPT #21" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("non-special://f:999999/c", base=base_url)
  guard result is None else {
    fail("Expected failure but got: \{result.unwrap().to_string().escape()}")
  }
}

///|
test "WPT #22" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("http://f: 21 / b ? d # e ", base=base_url)
  guard result is None else {
    fail("Expected failure but got: \{result.unwrap().to_string().escape()}")
  }
}

///|
test "WPT #23" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://example.org/foo/bar")
}

///|
test "WPT #24" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("  \t", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://example.org/foo/bar")
}

///|
test "WPT #25" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse(":foo.com/", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://example.org/foo/:foo.com/")
}

///|
test "WPT #26" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse(":foo.com\\", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://example.org/foo/:foo.com/")
}

///|
test "WPT #27" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse(":", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://example.org/foo/:")
}

///|
test "WPT #28" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse(":a", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://example.org/foo/:a")
}

///|
test "WPT #29" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse(":/", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://example.org/foo/:/")
}

///|
test "WPT #30" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse(":\\", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://example.org/foo/:/")
}

///|
test "WPT #31" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse(":#", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://example.org/foo/:#")
}

///|
test "WPT #32" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("#", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://example.org/foo/bar#")
}

///|
test "WPT #33" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("#/", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://example.org/foo/bar#/")
}

///|
test "WPT #34" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("#\\", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://example.org/foo/bar#\\")
}

///|
test "WPT #35" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("#;?", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://example.org/foo/bar#;?")
}

///|
test "WPT #36" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("?", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://example.org/foo/bar?")
}

///|
test "WPT #37" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("/", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://example.org/")
}

///|
test "WPT #38" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse(":23", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://example.org/foo/:23")
}

///|
test "WPT #39" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("/:23", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://example.org/:23")
}

///|
test "WPT #40" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("\\x", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://example.org/x")
}

///|
test "WPT #41" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("\\\\x\\hello", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://x/hello")
}

///|
test "WPT #42" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("::", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://example.org/foo/::")
}

///|
test "WPT #43" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("::23", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://example.org/foo/::23")
}

///|
test "WPT #44" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("foo://", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "foo://")
}

///|
test "WPT #45" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("http://a:b@c:29/d", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://a:b@c:29/d")
}

///|
test "WPT #46" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("http::@c:29", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://example.org/foo/:@c:29")
}

///|
test "WPT #47" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("http://&a:foo(b]c@d:2/", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://&a:foo(b%5Dc@d:2/")
}

///|
test "WPT #48" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("http://::@c@d:2", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://:%3A%40c@d:2/")
}

///|
test "WPT #49" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("http://foo.com:b@d/", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://foo.com:b@d/")
}

///|
test "WPT #50" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("http://foo.com/\\@", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://foo.com//@")
}

///|
test "WPT #51" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("http:\\\\foo.com\\", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://foo.com/")
}

///|
test "WPT #52" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("http:\\\\a\\b:c\\d@foo.com\\", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://a/b:c/d@foo.com/")
}

///|
test "WPT #53" {
  let result = @url.Url::parse("http://a:b@c\\")
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://a:b@c/")
}

///|
test "WPT #54" {
  let result = @url.Url::parse("ws://a@b\\c")
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "ws://a@b/c")
}

///|
test "WPT #55" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("foo:/", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "foo:/")
}

///|
test "WPT #56" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("foo:/bar.com/", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "foo:/bar.com/")
}

///|
test "WPT #57" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("foo://///////", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "foo://///////")
}

///|
test "WPT #58" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("foo://///////bar.com/", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "foo://///////bar.com/")
}

///|
test "WPT #59" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("foo:////://///", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "foo:////://///")
}

///|
test "WPT #60" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("c:/foo", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "c:/foo")
}

///|
test "WPT #61" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("//foo/bar", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://foo/bar")
}

///|
test "WPT #62" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("http://foo/path;a??e#f#g", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://foo/path;a??e#f#g")
}

///|
test "WPT #63" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("http://foo/abcd?efgh?ijkl", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://foo/abcd?efgh?ijkl")
}

///|
test "WPT #64" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("http://foo/abcd#foo?bar", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://foo/abcd#foo?bar")
}

///|
test "WPT #65" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("[61:24:74]:98", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://example.org/foo/[61:24:74]:98")
}

///|
test "WPT #66" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("http:[61:27]/:foo", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://example.org/foo/[61:27]/:foo")
}

///|
test "WPT #67" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("http://[1::2]:3:4", base=base_url)
  guard result is None else {
    fail("Expected failure but got: \{result.unwrap().to_string().escape()}")
  }
}

///|
test "WPT #68" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("http://2001::1", base=base_url)
  guard result is None else {
    fail("Expected failure but got: \{result.unwrap().to_string().escape()}")
  }
}

///|
test "WPT #69" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("http://2001::1]", base=base_url)
  guard result is None else {
    fail("Expected failure but got: \{result.unwrap().to_string().escape()}")
  }
}

///|
test "WPT #70" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("http://2001::1]:80", base=base_url)
  guard result is None else {
    fail("Expected failure but got: \{result.unwrap().to_string().escape()}")
  }
}

///|
test "WPT #71" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("http://[2001::1]", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://[2001::1]/")
}

///|
test "WPT #72" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("http://[::127.0.0.1]", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://[::7f00:1]/")
}

///|
test "WPT #73" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("http://[::127.0.0.1.]", base=base_url)
  guard result is None else {
    fail("Expected failure but got: \{result.unwrap().to_string().escape()}")
  }
}

///|
test "WPT #74" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("http://[0:0:0:0:0:0:13.1.68.3]", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://[::d01:4403]/")
}

///|
test "WPT #75" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("http://[2001::1]:80", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://[2001::1]/")
}

///|
test "WPT #76" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("http:/example.com/", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "http://example.org/example.com/")
}

///|
test "WPT #77" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("ftp:/example.com/", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "ftp://example.com/")
}

///|
test "WPT #78" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("https:/example.com/", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "https://example.com/")
}

///|
test "WPT #79" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("madeupscheme:/example.com/", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "madeupscheme:/example.com/")
}

///|
test "WPT #80" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("file:/example.com/", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "file:///example.com/")
}

///|
test "WPT #81" {
  let result = @url.Url::parse("file://example:1/")
  guard result is None else {
    fail("Expected failure but got: \{result.unwrap().to_string().escape()}")
  }
}

///|
test "WPT #82" {
  let result = @url.Url::parse("file://example:test/")
  guard result is None else {
    fail("Expected failure but got: \{result.unwrap().to_string().escape()}")
  }
}

///|
test "WPT #83" {
  let result = @url.Url::parse("file://example%/")
  guard result is None else {
    fail("Expected failure but got: \{result.unwrap().to_string().escape()}")
  }
}

///|
test "WPT #84" {
  let result = @url.Url::parse("file://[example]/")
  guard result is None else {
    fail("Expected failure but got: \{result.unwrap().to_string().escape()}")
  }
}

///|
test "WPT #85" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("ftps:/example.com/", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "ftps:/example.com/")
}

///|
test "WPT #86" {
  let base_url = @url.Url::parse("http://example.org/foo/bar")
  guard base_url is Some(base_url) else { fail("base URL must parse") }
  let result = @url.Url::parse("gopher:/example.com/", base=base_url)
  guard result is Some(url) else { fail("Expected success but parsing failed") }
  assert_eq(url.to_string(), "gopher:/example.com/")
}

///|
test "WPT setters href #0" {
  let url = @url.Url::parse("file:///var/log/system.log")
  guard url is Some(url) else { fail("parse failed") }
  url.set_href("http://0300.168.0xF0")
  assert_eq(url.href(), "http://192.168.0.240/")
  assert_eq(url.protocol(), "http:")
}

///|
test "WPT setters protocol #0" {
  let url = @url.Url::parse("a://example.net")
  guard url is Some(url) else { fail("parse failed") }
  url.set_protocol("")
  assert_eq(url.href(), "a://example.net")
  assert_eq(url.protocol(), "a:")
}

///|
test "WPT setters protocol #1" {
  let url = @url.Url::parse("a://example.net")
  guard url is Some(url) else { fail("parse failed") }
  url.set_protocol("b")
  assert_eq(url.href(), "b://example.net")
  assert_eq(url.protocol(), "b:")
}

///|
test "WPT setters protocol #2" {
  let url = @url.Url::parse("javascript:alert(1)")
  guard url is Some(url) else { fail("parse failed") }
  url.set_protocol("defuse")
  assert_eq(url.href(), "defuse:alert(1)")
  assert_eq(url.protocol(), "defuse:")
}

///|
test "WPT setters protocol #3" {
  let url = @url.Url::parse("a://example.net")
  guard url is Some(url) else { fail("parse failed") }
  url.set_protocol("B")
  assert_eq(url.href(), "b://example.net")
  assert_eq(url.protocol(), "b:")
}

///|
test "WPT setters protocol #4" {
  let url = @url.Url::parse("a://example.net")
  guard url is Some(url) else { fail("parse failed") }
  url.set_protocol("\u{E9}")
  assert_eq(url.href(), "a://example.net")
  assert_eq(url.protocol(), "a:")
}

///|
test "WPT setters protocol #5" {
  let url = @url.Url::parse("a://example.net")
  guard url is Some(url) else { fail("parse failed") }
  url.set_protocol("0b")
  assert_eq(url.href(), "a://example.net")
  assert_eq(url.protocol(), "a:")
}

///|
test "WPT setters protocol #6" {
  let url = @url.Url::parse("a://example.net")
  guard url is Some(url) else { fail("parse failed") }
  url.set_protocol("+b")
  assert_eq(url.href(), "a://example.net")
  assert_eq(url.protocol(), "a:")
}

///|
test "WPT setters protocol #7" {
  let url = @url.Url::parse("a://example.net")
  guard url is Some(url) else { fail("parse failed") }
  url.set_protocol("bC0+-.")
  assert_eq(url.href(), "bc0+-.://example.net")
  assert_eq(url.protocol(), "bc0+-.:")
}

///|
test "WPT setters protocol #8" {
  let url = @url.Url::parse("a://example.net")
  guard url is Some(url) else { fail("parse failed") }
  url.set_protocol("b,c")
  assert_eq(url.href(), "a://example.net")
  assert_eq(url.protocol(), "a:")
}

///|
test "WPT setters protocol #9" {
  let url = @url.Url::parse("a://example.net")
  guard url is Some(url) else { fail("parse failed") }
  url.set_protocol("b\u{E9}")
  assert_eq(url.href(), "a://example.net")
  assert_eq(url.protocol(), "a:")
}

///|
test "WPT setters protocol #10" {
  let url = @url.Url::parse("http://test@example.net")
  guard url is Some(url) else { fail("parse failed") }
  url.set_protocol("file")
  assert_eq(url.href(), "http://test@example.net/")
  assert_eq(url.protocol(), "http:")
}

///|
test "WPT setters protocol #11" {
  let url = @url.Url::parse("https://example.net:1234")
  guard url is Some(url) else { fail("parse failed") }
  url.set_protocol("file")
  assert_eq(url.href(), "https://example.net:1234/")
  assert_eq(url.protocol(), "https:")
}

///|
test "WPT setters protocol #12" {
  let url = @url.Url::parse("wss://x:x@example.net:1234")
  guard url is Some(url) else { fail("parse failed") }
  url.set_protocol("file")
  assert_eq(url.href(), "wss://x:x@example.net:1234/")
  assert_eq(url.protocol(), "wss:")
}

///|
test "WPT setters protocol #13" {
  let url = @url.Url::parse("file://localhost/")
  guard url is Some(url) else { fail("parse failed") }
  url.set_protocol("http")
  assert_eq(url.href(), "file:///")
  assert_eq(url.protocol(), "file:")
}

///|
test "WPT setters protocol #14" {
  let url = @url.Url::parse("file:///test")
  guard url is Some(url) else { fail("parse failed") }
  url.set_protocol("https")
  assert_eq(url.href(), "file:///test")
  assert_eq(url.protocol(), "file:")
}

///|
test "WPT setters protocol #15" {
  let url = @url.Url::parse("file:")
  guard url is Some(url) else { fail("parse failed") }
  url.set_protocol("wss")
  assert_eq(url.href(), "file:///")
  assert_eq(url.protocol(), "file:")
}

///|
test "WPT setters protocol #16" {
  let url = @url.Url::parse("http://example.net")
  guard url is Some(url) else { fail("parse failed") }
  url.set_protocol("b")
  assert_eq(url.href(), "http://example.net/")
  assert_eq(url.protocol(), "http:")
}

///|
test "WPT setters protocol #17" {
  let url = @url.Url::parse("file://hi/path")
  guard url is Some(url) else { fail("parse failed") }
  url.set_protocol("s")
  assert_eq(url.href(), "file://hi/path")
  assert_eq(url.protocol(), "file:")
}

///|
test "WPT setters protocol #18" {
  let url = @url.Url::parse("https://example.net")
  guard url is Some(url) else { fail("parse failed") }
  url.set_protocol("s")
  assert_eq(url.href(), "https://example.net/")
  assert_eq(url.protocol(), "https:")
}

///|
test "WPT setters protocol #19" {
  let url = @url.Url::parse("ftp://example.net")
  guard url is Some(url) else { fail("parse failed") }
  url.set_protocol("test")
  assert_eq(url.href(), "ftp://example.net/")
  assert_eq(url.protocol(), "ftp:")
}

///|
test "WPT setters protocol #20" {
  let url = @url.Url::parse("mailto:me@example.net")
  guard url is Some(url) else { fail("parse failed") }
  url.set_protocol("http")
  assert_eq(url.href(), "mailto:me@example.net")
  assert_eq(url.protocol(), "mailto:")
}

///|
test "WPT setters protocol #21" {
  let url = @url.Url::parse("ssh://me@example.net")
  guard url is Some(url) else { fail("parse failed") }
  url.set_protocol("http")
  assert_eq(url.href(), "ssh://me@example.net")
  assert_eq(url.protocol(), "ssh:")
}

///|
test "WPT setters protocol #22" {
  let url = @url.Url::parse("ssh://me@example.net")
  guard url is Some(url) else { fail("parse failed") }
  url.set_protocol("https")
  assert_eq(url.href(), "ssh://me@example.net")
  assert_eq(url.protocol(), "ssh:")
}

///|
test "WPT setters protocol #23" {
  let url = @url.Url::parse("ssh://me@example.net")
  guard url is Some(url) else { fail("parse failed") }
  url.set_protocol("file")
  assert_eq(url.href(), "ssh://me@example.net")
  assert_eq(url.protocol(), "ssh:")
}

///|
test "WPT setters protocol #24" {
  let url = @url.Url::parse("ssh://example.net")
  guard url is Some(url) else { fail("parse failed") }
  url.set_protocol("file")
  assert_eq(url.href(), "ssh://example.net")
  assert_eq(url.protocol(), "ssh:")
}

///|
test "WPT setters protocol #25" {
  let url = @url.Url::parse("nonsense:///test")
  guard url is Some(url) else { fail("parse failed") }
  url.set_protocol("https")
  assert_eq(url.href(), "nonsense:///test")
  assert_eq(url.protocol(), "nonsense:")
}
