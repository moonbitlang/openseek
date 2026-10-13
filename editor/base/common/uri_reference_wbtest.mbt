// Conformance port of `vs/base/test/common/uri.test.ts` in the checked-in
// vscode source, suite "URI".
//
// White-box `isWindows`-gated suites run under `set_is_windows_for_testing`
// seam instead of being skipped; URIs are always created *after* setting the
// seam because `fs_path`/`to_string` cache their results (D5).
//
// Not transcribed: `URI.isUri` / `isUriComponents` (N-A, static types),
// `toJSON`/`revive` round-trips (D7, marshalling deferred), and the two
// `test.skip` suites Monaco itself skips.

///|
test "file#toString" {
  assert_eq(Uri::file("c:/win/path").to_string(), "file:///c%3A/win/path")
  assert_eq(Uri::file("C:/win/path").to_string(), "file:///c%3A/win/path")
  assert_eq(Uri::file("c:/win/path/").to_string(), "file:///c%3A/win/path/")
  assert_eq(Uri::file("/c:/win/path").to_string(), "file:///c%3A/win/path")
}

///|
test "http#toString" {
  assert_eq(
    Uri::from(scheme="http", authority="www.example.com", path="/my/path").to_string(),
    "http://www.example.com/my/path",
  )
  assert_eq(
    Uri::from(scheme="http", authority="www.EXAMPLE.com", path="/my/path").to_string(),
    "http://www.example.com/my/path",
  )
  assert_eq(
    Uri::from(scheme="http", authority="", path="my/path").to_string(),
    "http:/my/path",
  )
  assert_eq(
    Uri::from(scheme="http", authority="", path="/my/path").to_string(),
    "http:/my/path",
  )
  //http://example.com/#test=true
  assert_eq(
    Uri::from(
      scheme="http",
      authority="example.com",
      path="/",
      query="test=true",
    ).to_string(),
    "http://example.com/?test%3Dtrue",
  )
  assert_eq(
    Uri::from(
      scheme="http",
      authority="example.com",
      path="/",
      query="",
      fragment="test=true",
    ).to_string(),
    "http://example.com/#test%3Dtrue",
  )
}

///|
test "http#toString, encode=FALSE" {
  assert_eq(
    Uri::from(
      scheme="http",
      authority="example.com",
      path="/",
      query="test=true",
    ).to_string(skip_encoding=true),
    "http://example.com/?test=true",
  )
  assert_eq(
    Uri::from(
      scheme="http",
      authority="example.com",
      path="/",
      query="",
      fragment="test=true",
    ).to_string(skip_encoding=true),
    "http://example.com/#test=true",
  )
  assert_eq(
    Uri::from(scheme="http", path="/api/files/test.me", query="t=1234").to_string(
      skip_encoding=true,
    ),
    "http:/api/files/test.me?t=1234",
  )
  let value = Uri::parse("file://shares/pröjects/c%23/#l12")
  assert_eq(value.authority, "shares")
  assert_eq(value.path, "/pröjects/c#/")
  assert_eq(value.fragment, "l12")
  assert_eq(value.to_string(), "file://shares/pr%C3%B6jects/c%23/#l12")
  assert_eq(
    value.to_string(skip_encoding=true),
    "file://shares/pröjects/c%23/#l12",
  )
  let uri2 = Uri::parse(value.to_string(skip_encoding=true))
  let uri3 = Uri::parse(value.to_string())
  assert_eq(uri2.authority, uri3.authority)
  assert_eq(uri2.path, uri3.path)
  assert_eq(uri2.query, uri3.query)
  assert_eq(uri2.fragment, uri3.fragment)
}

///|
test "with, identity" {
  let uri = Uri::parse("foo:bar/path")
  let uri2 = uri.with_()
  assert_true(physical_equal(uri, uri2))
  let uri3 = uri.with_(scheme="foo", path="bar/path")
  assert_true(physical_equal(uri, uri3))
}

///|
test "with, changes" {
  assert_eq(
    Uri::parse("before:some/file/path").with_(scheme="after").to_string(),
    "after:some/file/path",
  )
  assert_eq(
    Uri::from(scheme="s")
    .with_(scheme="http", path="/api/files/test.me", query="t=1234")
    .to_string(),
    "http:/api/files/test.me?t%3D1234",
  )
  assert_eq(
    Uri::from(scheme="s")
    .with_(
      scheme="http",
      authority="",
      path="/api/files/test.me",
      query="t=1234",
      fragment="",
    )
    .to_string(),
    "http:/api/files/test.me?t%3D1234",
  )
  assert_eq(
    Uri::from(scheme="s")
    .with_(
      scheme="https",
      authority="",
      path="/api/files/test.me",
      query="t=1234",
      fragment="",
    )
    .to_string(),
    "https:/api/files/test.me?t%3D1234",
  )
  assert_eq(
    Uri::from(scheme="s")
    .with_(
      scheme="HTTP",
      authority="",
      path="/api/files/test.me",
      query="t=1234",
      fragment="",
    )
    .to_string(),
    "HTTP:/api/files/test.me?t%3D1234",
  )
  assert_eq(
    Uri::from(scheme="s")
    .with_(
      scheme="HTTPS",
      authority="",
      path="/api/files/test.me",
      query="t=1234",
      fragment="",
    )
    .to_string(),
    "HTTPS:/api/files/test.me?t%3D1234",
  )
  assert_eq(
    Uri::from(scheme="s")
    .with_(
      scheme="boo",
      authority="",
      path="/api/files/test.me",
      query="t=1234",
      fragment="",
    )
    .to_string(),
    "boo:/api/files/test.me?t%3D1234",
  )
}

///|
test "with, remove components #8465" {
  assert_eq(
    Uri::parse("scheme://authority/path").with_(authority="").to_string(),
    "scheme:/path",
  )
  assert_eq(
    Uri::parse("scheme:/path")
    .with_(authority="authority")
    .with_(authority="")
    .to_string(),
    "scheme:/path",
  )
  assert_eq(
    Uri::parse("scheme:/path")
    .with_(authority="authority")
    .with_(path="")
    .to_string(),
    "scheme://authority",
  )
  assert_eq(
    Uri::parse("scheme:/path").with_(authority="").to_string(),
    "scheme:/path",
  )
}

///|
test "with, validation" {
  let uri = Uri::parse("foo:bar/path")
  for
    change in [
      () => uri.with_(scheme="fai:l") |> ignore,
      () => uri.with_(scheme="fäil") |> ignore,
      () => uri.with_(authority="fail") |> ignore,
      () => uri.with_(path="//fail") |> ignore,
    ] {
    try change() catch {
      UriError(_) => ()
    } noraise {
      _ => fail("expected with_ to raise UriError")
    }
  }
}

///|
test "parse, disallow //path when no authority" {
  try Uri::parse("file:////shares/files/p.cs") |> ignore catch {
    UriError(_) => ()
  } noraise {
    _ => fail("expected parse to raise UriError")
  }
}

///|
test "URI#file, always slash" {
  let value = Uri::file("a.file")
  assert_eq(value.scheme, "file")
  assert_eq(value.authority, "")
  assert_eq(value.path, "/a.file")
  assert_eq(value.to_string(), "file:///a.file")
  let value = Uri::parse(value.to_string())
  assert_eq(value.scheme, "file")
  assert_eq(value.authority, "")
  assert_eq(value.path, "/a.file")
  assert_eq(value.to_string(), "file:///a.file")
}

///|
test "URI.toString, only scheme and query" {
  assert_eq(Uri::parse("stuff:?qüery").to_string(), "stuff:?q%C3%BCery")
}

///|
test "URI#toString, upper-case percent espaces" {
  assert_eq(
    Uri::parse("file://sh%c3%a4res/path").to_string(),
    "file://sh%C3%A4res/path",
  )
}

///|
test "URI#toString, lower-case windows drive letter" {
  assert_eq(
    Uri::parse("untitled:c:/Users/jrieken/Code/abc.txt").to_string(),
    "untitled:c%3A/Users/jrieken/Code/abc.txt",
  )
  assert_eq(
    Uri::parse("untitled:C:/Users/jrieken/Code/abc.txt").to_string(),
    "untitled:c%3A/Users/jrieken/Code/abc.txt",
  )
}

///|
test "URI#toString, escape all the bits" {
  let value = Uri::file(
    "/Users/jrieken/Code/_samples/18500/Mödel + Other Thîngß/model.js",
  )
  assert_eq(
    value.to_string(),
    "file:///Users/jrieken/Code/_samples/18500/M%C3%B6del%20%2B%20Other%20Th%C3%AEng%C3%9F/model.js",
  )
}

///|
test "URI#toString, don't encode port" {
  let value = Uri::parse("http://localhost:8080/far")
  assert_eq(value.to_string(), "http://localhost:8080/far")
  let value = Uri::from(scheme="http", authority="löcalhost:8080", path="/far")
  assert_eq(value.to_string(), "http://l%C3%B6calhost:8080/far")
}

///|
test "URI#toString, user information in authority" {
  let value = Uri::parse("http://foo:bar@localhost/far")
  assert_eq(value.to_string(), "http://foo:bar@localhost/far")
  let value = Uri::parse("http://foo@localhost/far")
  assert_eq(value.to_string(), "http://foo@localhost/far")
  let value = Uri::parse("http://foo:bAr@localhost:8080/far")
  assert_eq(value.to_string(), "http://foo:bAr@localhost:8080/far")
  let value = Uri::parse("http://foo@localhost:8080/far")
  assert_eq(value.to_string(), "http://foo@localhost:8080/far")
  let value = Uri::from(
    scheme="http",
    authority="föö:bör@löcalhost:8080",
    path="/far",
  )
  assert_eq(
    value.to_string(),
    "http://f%C3%B6%C3%B6:b%C3%B6r@l%C3%B6calhost:8080/far",
  )
}

///|
test "URI - http, query & toString" {
  let uri = Uri::parse("https://go.microsoft.com/fwlink/?LinkId=518008")
  assert_eq(uri.query, "LinkId=518008")
  assert_eq(
    uri.to_string(skip_encoding=true),
    "https://go.microsoft.com/fwlink/?LinkId=518008",
  )
  assert_eq(uri.to_string(), "https://go.microsoft.com/fwlink/?LinkId%3D518008")
  let uri2 = Uri::parse(uri.to_string())
  assert_eq(uri2.query, "LinkId=518008")
  assert_eq(uri2.query, uri.query)
  let uri = Uri::parse(
    "https://go.microsoft.com/fwlink/?LinkId=518008&foö&ké¥=üü",
  )
  assert_eq(uri.query, "LinkId=518008&foö&ké¥=üü")
  assert_eq(
    uri.to_string(skip_encoding=true),
    "https://go.microsoft.com/fwlink/?LinkId=518008&foö&ké¥=üü",
  )
  assert_eq(
    uri.to_string(),
    "https://go.microsoft.com/fwlink/?LinkId%3D518008%26fo%C3%B6%26k%C3%A9%C2%A5%3D%C3%BC%C3%BC",
  )
  let uri2 = Uri::parse(uri.to_string())
  assert_eq(uri2.query, "LinkId=518008&foö&ké¥=üü")
  assert_eq(uri2.query, uri.query)

  // #24849
  let uri = Uri::parse("https://twitter.com/search?src=typd&q=%23tag")
  assert_eq(
    uri.to_string(skip_encoding=true),
    "https://twitter.com/search?src=typd&q=%23tag",
  )
}

///|
test "class URI cannot represent relative file paths #34449" {
  assert_eq(Uri::file("/foo/bar").path, "/foo/bar")
  assert_eq(Uri::file("foo/bar").path, "/foo/bar")
  assert_eq(Uri::file("./foo/bar").path, "/./foo/bar") // missing normalization
  let file_uri1 = Uri::parse("file:foo/bar")
  assert_eq(file_uri1.path, "/foo/bar")
  assert_eq(file_uri1.authority, "")
  let uri = file_uri1.to_string()
  assert_eq(uri, "file:///foo/bar")
  let file_uri2 = Uri::parse(uri)
  assert_eq(file_uri2.path, "/foo/bar")
  assert_eq(file_uri2.authority, "")
}

///|
test "Ctrl click to follow hash query param url gets urlencoded #49628" {
  let input = "http://localhost:3000/#/foo?bar=baz"
  let uri = Uri::parse(input)
  assert_eq(uri.to_string(skip_encoding=true), input)
  let input = "http://localhost:3000/foo?bar=baz"
  let uri = Uri::parse(input)
  assert_eq(uri.to_string(skip_encoding=true), input)
}

///|
test "Unable to open '%A0.txt': URI malformed #76506" {
  let uri = Uri::file("/foo/%A0.txt")
  let uri2 = Uri::parse(uri.to_string())
  assert_eq(uri.scheme, uri2.scheme)
  assert_eq(uri.path, uri2.path)
  let uri = Uri::file("/foo/%2e.txt")
  let uri2 = Uri::parse(uri.to_string())
  assert_eq(uri.scheme, uri2.scheme)
  assert_eq(uri.path, uri2.path)
}

///|
test "from, from(strict)" {
  try Uri::from(scheme="", strict=true) |> ignore catch {
    UriError(_) => ()
  } noraise {
    _ => fail("expected from(strict) to raise UriError")
  }
  assert_eq(Uri::from(scheme="").scheme, "file")
  // `URI.revive({scheme: ''}).scheme === ''` — revive deferred (D7).
}

///|
test "Unable to open '%A0.txt': URI malformed #76506, part 2" {
  assert_eq(Uri::parse("file://some/%.txt").to_string(), "file://some/%25.txt")
  assert_eq(
    Uri::parse("file://some/%A0.txt").to_string(),
    "file://some/%25A0.txt",
  )
}

///|
fn assert_joined(
  base : String,
  fragment : String,
  expected : String,
) -> Unit raise {
  let base_uri = Uri::parse(base)
  let new_uri = Uri::join_path(base_uri, [fragment])
  let actual = new_uri.to_string(skip_encoding=true)
  assert_eq(actual, expected)
}

///|
test "URI#joinPath" {
  assert_joined("file:///foo/", "../../bazz", "file:///bazz")
  assert_joined("file:///foo", "../../bazz", "file:///bazz")
  assert_joined("file:///foo/bar/", "./bazz", "file:///foo/bar/bazz")
  assert_joined("file:///foo/bar", "./bazz", "file:///foo/bar/bazz")
  assert_joined("file:///foo/bar", "bazz", "file:///foo/bar/bazz")

  // "auto-path" scheme
  assert_joined("file:", "bazz", "file:///bazz")
  assert_joined("http://domain", "bazz", "http://domain/bazz")
  assert_joined("https://domain", "bazz", "https://domain/bazz")
  assert_joined("http:", "bazz", "http:/bazz")
  assert_joined("https:", "bazz", "https:/bazz")

  // no "auto-path" scheme with and w/o paths
  assert_joined("foo:/", "bazz", "foo:/bazz")
  assert_joined("foo://bar/", "bazz", "foo://bar/bazz")
}

///|
test "panic URI#joinPath, no auto-path + no path (foo:)" {
  // no "auto-path" + no path -> error
  ignore(Uri::join_path(Uri::parse("foo:"), ["bazz"]))
}

///|
test "panic URI#joinPath, no auto-path + no path (foo://bar)" {
  ignore(Uri::join_path(Uri::parse("foo://bar"), ["bazz"]))
}

///|
test "vscode-uri: URI.toString() wrongly encode IPv6 literals #154048" {
  assert_eq(
    Uri::parse("http://[FEDC:BA98:7654:3210:FEDC:BA98:7654:3210]:80/index.html").to_string(),
    "http://[fedc:ba98:7654:3210:fedc:ba98:7654:3210]:80/index.html",
  )
  assert_eq(
    Uri::parse(
      "http://user@[FEDC:BA98:7654:3210:FEDC:BA98:7654:3210]:80/index.html",
    ).to_string(),
    "http://user@[fedc:ba98:7654:3210:fedc:ba98:7654:3210]:80/index.html",
  )
  assert_eq(
    Uri::parse(
      "http://us[er@[FEDC:BA98:7654:3210:FEDC:BA98:7654:3210]:80/index.html",
    ).to_string(),
    "http://us%5Ber@[fedc:ba98:7654:3210:fedc:ba98:7654:3210]:80/index.html",
  )
}

///|
test "strict-mode and scheme validation errors (each _validateUri branch)" {
  // missing scheme, strict
  try Uri::parse("/relative/path", strict=true) |> ignore catch {
    UriError(_) => ()
  } noraise {
    _ => fail("expected missing-scheme error")
  }
  // illegal scheme chars (space captured by the scheme scanner)
  try Uri::parse("ht tp://example.com") |> ignore catch {
    UriError(message) => assert_true(message.contains("illegal characters"))
  } noraise {
    _ => fail("expected illegal-scheme error")
  }
  // authority + path without leading slash
  try Uri::from(scheme="s", authority="auth", path="relative") |> ignore catch {
    UriError(_) => ()
  } noraise {
    _ => fail("expected authority/path slash-rule error")
  }
  // no authority + `//` path via percent-decoded parse input
  try Uri::parse("foo:%2F%2Fbar") |> ignore catch {
    UriError(_) => ()
  } noraise {
    _ => fail("expected //-path error")
  }
}

///|
test "non-ASCII and astral path round-trips (D4)" {
  // astral char U+1D49C (𝒜) → 4-byte UTF-8 percent encoding
  let value = Uri::from(scheme="s", authority="a", path="/𝒜/file.txt")
  assert_eq(value.to_string(), "s://a/%F0%9D%92%9C/file.txt")
  let round = Uri::parse(value.to_string())
  assert_eq(round.path, "/𝒜/file.txt")
  assert_true(round == value)
  // invalid %ZZ run decodes gracefully (raw text kept)
  assert_eq(Uri::parse("s://a/%ZZ.txt").path, "/%ZZ.txt")
  // double-encoded input round-trips through one decode
  assert_eq(Uri::parse("s://a/%2520").path, "/%20")
}

///|
test "panic toString with lone surrogate raises like URIError (D4)" {
  let lone = Int32::unsafe_to_char(0xD800).to_string()
  let value = Uri::from(scheme="s", authority="a", path="/\{lone}")
  ignore(value.to_string())
}
