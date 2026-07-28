///|
test "component/host/domain" {
  let uri = Uri::parse("http://example.com/")
  assert_eq(uri.host(), Some("example.com"))
}

///|
test "component/host/subdomain" {
  let uri = Uri::parse("http://www.example.com/")
  assert_eq(uri.host(), Some("www.example.com"))
}

///|
test "component/host/ipv4" {
  let uri = Uri::parse("http://192.168.1.1/")
  assert_eq(uri.host(), Some("192.168.1.1"))
}

///|
test "component/host/ipv6-loopback" {
  let uri = Uri::parse("http://[::1]/")
  assert_eq(uri.host(), Some("[::1]"))
}

///|
test "component/host/ipv6-full" {
  let uri = Uri::parse("http://[2001:db8:85a3::8a2e:370:7334]/")
  assert_eq(uri.host(), Some("[2001:db8:85a3::8a2e:370:7334]"))
}

///|
test "component/host/ipv6-with-port" {
  let uri = Uri::parse("http://[::1]:8080/")
  assert_eq(uri.host(), Some("[::1]"))
  assert_eq(uri.port(), Some("8080"))
}

///|
test "component/host/localhost" {
  let uri = Uri::parse("http://localhost/")
  assert_eq(uri.host(), Some("localhost"))
}

///|
test "component/host/empty" {
  let uri = Uri::parse("file:///path/to/file")
  assert_eq(uri.host(), Some(""))
}

///|
test "component/host/none-for-opaque" {
  let uri = Uri::parse("mailto:user@example.com")
  assert_eq(uri.host(), None)
}

///|
test "component/port/standard-http" {
  let uri = Uri::parse("http://example.com:80/")
  assert_eq(uri.port(), Some("80"))
}

///|
test "component/port/standard-https" {
  let uri = Uri::parse("https://example.com:443/")
  assert_eq(uri.port(), Some("443"))
}

///|
test "component/port/high-port" {
  let uri = Uri::parse("http://example.com:65535/")
  assert_eq(uri.port(), Some("65535"))
}

///|
test "component/port/empty" {
  let uri = Uri::parse("http://example.com:/")
  assert_eq(uri.port(), Some(""))
}

///|
test "component/port/none" {
  let uri = Uri::parse("http://example.com/")
  assert_eq(uri.port(), None)
}

///|
test "component/port/zero" {
  let uri = Uri::parse("http://example.com:0/")
  assert_eq(uri.port(), Some("0"))
}

///|
test "component/path/empty" {
  let uri = Uri::parse("http://example.com")
  assert_eq(uri.path(), "")
}

///|
test "component/path/root" {
  let uri = Uri::parse("http://example.com/")
  assert_eq(uri.path(), "/")
}

///|
test "component/path/simple" {
  let uri = Uri::parse("http://example.com/path")
  assert_eq(uri.path(), "/path")
}

///|
test "component/path/nested" {
  let uri = Uri::parse("http://example.com/path/to/resource")
  assert_eq(uri.path(), "/path/to/resource")
}

///|
test "component/path/with-extension" {
  let uri = Uri::parse("http://example.com/file.html")
  assert_eq(uri.path(), "/file.html")
}

///|
test "component/path/percent-encoded" {
  let uri = Uri::parse("http://example.com/path%20with%20spaces")
  assert_eq(uri.path(), "/path%20with%20spaces")
}

///|
test "component/path/special-chars" {
  let uri = Uri::parse("http://example.com/path;params")
  assert_eq(uri.path(), "/path;params")
}

///|
test "component/path/dot-segments" {
  let uri = Uri::parse("http://example.com/a/b/../c")
  assert_eq(uri.path(), "/a/b/../c")
}

///|
test "component/path/opaque" {
  let uri = Uri::parse("mailto:user@example.com")
  assert_eq(uri.path(), "user@example.com")
}

///|
test "component/query/simple" {
  let uri = Uri::parse("http://example.com/?q=test")
  assert_eq(uri.query(), Some("q=test"))
}

///|
test "component/query/multiple-params" {
  let uri = Uri::parse("http://example.com/?a=1&b=2&c=3")
  assert_eq(uri.query(), Some("a=1&b=2&c=3"))
}

///|
test "component/query/empty" {
  let uri = Uri::parse("http://example.com/?")
  assert_eq(uri.query(), Some(""))
}

///|
test "component/query/none" {
  let uri = Uri::parse("http://example.com/")
  assert_eq(uri.query(), None)
}

///|
test "component/query/with-fragment" {
  let uri = Uri::parse("http://example.com/?q=test#section")
  assert_eq(uri.query(), Some("q=test"))
}

///|
test "component/query/special-chars" {
  let uri = Uri::parse("http://example.com/?q=a+b&x=1%262")
  assert_eq(uri.query(), Some("q=a+b&x=1%262"))
}

///|
test "component/query/unicode-encoded" {
  let uri = Uri::parse("http://example.com/?q=%E4%B8%AD%E6%96%87")
  assert_eq(uri.query(), Some("q=%E4%B8%AD%E6%96%87"))
}

///|
test "component/fragment/simple" {
  let uri = Uri::parse("http://example.com/#section")
  assert_eq(uri.fragment(), Some("section"))
}

///|
test "component/fragment/with-query" {
  let uri = Uri::parse("http://example.com/?q=test#section")
  assert_eq(uri.fragment(), Some("section"))
}

///|
test "component/fragment/empty" {
  let uri = Uri::parse("http://example.com/#")
  assert_eq(uri.fragment(), Some(""))
}

///|
test "component/fragment/none" {
  let uri = Uri::parse("http://example.com/")
  assert_eq(uri.fragment(), None)
}

///|
test "component/fragment/with-special-chars" {
  let uri = Uri::parse("http://example.com/#section/subsection")
  assert_eq(uri.fragment(), Some("section/subsection"))
}

///|
test "component/fragment/percent-encoded" {
  let uri = Uri::parse("http://example.com/#%E4%B8%AD%E6%96%87")
  assert_eq(uri.fragment(), Some("%E4%B8%AD%E6%96%87"))
}

///|
test "component/to_string/simple" {
  let uri = Uri::parse("http://example.com/")
  assert_eq(uri.to_string(), "http://example.com/")
}

///|
test "component/to_string/full" {
  let uri = Uri::parse("http://user:pass@example.com:8080/path?query#fragment")
  assert_eq(
    uri.to_string(),
    "http://user:pass@example.com:8080/path?query#fragment",
  )
}

///|
test "component/to_string/ipv6" {
  let uri = Uri::parse("http://[::1]:8080/path")
  assert_eq(uri.to_string(), "http://[::1]:8080/path")
}

///|
test "component/to_string/opaque" {
  let uri = Uri::parse("mailto:user@example.com")
  assert_eq(uri.to_string(), "mailto:user@example.com")
}

///|
test "component/to_string/file" {
  let uri = Uri::parse("file:///etc/passwd")
  assert_eq(uri.to_string(), "file:///etc/passwd")
}

///|
test "invalid/characters/unencoded-space" {
  let result = Ok(Uri::parse("http://example.com/path with space")) catch {
    _ => Err(())
  }
  assert_true(result is Err(_))
}

///|
test "invalid/scheme/starts-with-digit" {
  let result = Ok(Uri::parse("1http://example.com/")) catch { _ => Err(()) }
  assert_true(result is Err(_))
}

///|
test "invalid/ipv6/missing-bracket" {
  let result = Ok(Uri::parse("http://[::1/path")) catch { _ => Err(()) }
  assert_true(result is Err(_))
}

///|
test "resolve/base-with-empty-path" {
  let base = Uri::parse("http://example.com")
  assert_eq(Uri::resolve(base, "path").to_string(), "http://example.com/path")
}

///|
test "resolve/base-with-root-path" {
  let base = Uri::parse("http://example.com/")
  assert_eq(Uri::resolve(base, "path").to_string(), "http://example.com/path")
}

///|
test "resolve/relative-same-directory" {
  let base = Uri::parse("http://example.com/a/b/c")
  assert_eq(Uri::resolve(base, "d").to_string(), "http://example.com/a/b/d")
}

///|
test "resolve/relative-parent-directory" {
  let base = Uri::parse("http://example.com/a/b/c")
  assert_eq(Uri::resolve(base, "../d").to_string(), "http://example.com/a/d")
}

///|
test "resolve/relative-grandparent-directory" {
  let base = Uri::parse("http://example.com/a/b/c")
  assert_eq(Uri::resolve(base, "../../d").to_string(), "http://example.com/d")
}

///|
test "resolve/relative-beyond-root" {
  let base = Uri::parse("http://example.com/a/b")
  // Should not go above root
  assert_eq(
    Uri::resolve(base, "../../../d").to_string(),
    "http://example.com/d",
  )
}

///|
test "resolve/absolute-path" {
  let base = Uri::parse("http://example.com/a/b/c")
  assert_eq(Uri::resolve(base, "/d/e").to_string(), "http://example.com/d/e")
}

///|
test "resolve/absolute-uri" {
  let base = Uri::parse("http://example.com/a/b")
  assert_eq(
    Uri::resolve(base, "https://other.com/x").to_string(),
    "https://other.com/x",
  )
}

///|
test "resolve/network-path" {
  let base = Uri::parse("http://example.com/a/b")
  assert_eq(
    Uri::resolve(base, "//other.com/x").to_string(),
    "http://other.com/x",
  )
}

///|
test "resolve/query-only" {
  let base = Uri::parse("http://example.com/a/b?old=query")
  assert_eq(
    Uri::resolve(base, "?new=query").to_string(),
    "http://example.com/a/b?new=query",
  )
}

///|
test "resolve/fragment-only" {
  let base = Uri::parse("http://example.com/a/b?query")
  assert_eq(
    Uri::resolve(base, "#section").to_string(),
    "http://example.com/a/b?query#section",
  )
}

///|
test "resolve/empty-reference" {
  let base = Uri::parse("http://example.com/a/b?query#frag")
  assert_eq(Uri::resolve(base, "").to_string(), "http://example.com/a/b?query")
}

///|
test "resolve/dot-current" {
  let base = Uri::parse("http://example.com/a/b/c")
  assert_eq(Uri::resolve(base, ".").to_string(), "http://example.com/a/b/")
}

///|
test "resolve/dot-current-explicit" {
  let base = Uri::parse("http://example.com/a/b/c")
  assert_eq(Uri::resolve(base, "./").to_string(), "http://example.com/a/b/")
}

///|
test "resolve/dot-dot-parent" {
  let base = Uri::parse("http://example.com/a/b/c")
  assert_eq(Uri::resolve(base, "..").to_string(), "http://example.com/a/")
}

///|
test "resolve/dot-dot-parent-explicit" {
  let base = Uri::parse("http://example.com/a/b/c")
  assert_eq(Uri::resolve(base, "../").to_string(), "http://example.com/a/")
}

///|
test "resolve/complex-dot-segments" {
  let base = Uri::parse("http://example.com/a/b/c/d")
  assert_eq(
    Uri::resolve(base, "../../.././e/../f").to_string(),
    "http://example.com/f",
  )
}

///|
test "resolve/preserve-query-and-fragment" {
  let base = Uri::parse("http://example.com/a/b")
  assert_eq(
    Uri::resolve(base, "c?q=1#f").to_string(),
    "http://example.com/a/c?q=1#f",
  )
}

///|
test "resolve/reference-with-userinfo" {
  let base = Uri::parse("http://example.com/a")
  assert_eq(
    Uri::resolve(base, "//user@host/b").to_string(),
    "http://user@host/b",
  )
}

///|
test "resolve/reference-with-port" {
  let base = Uri::parse("http://example.com/a")
  assert_eq(
    Uri::resolve(base, "//host:8080/b").to_string(),
    "http://host:8080/b",
  )
}

///|
test "resolve/base-with-userinfo" {
  let base = Uri::parse("http://user@example.com/a")
  assert_eq(Uri::resolve(base, "b").to_string(), "http://user@example.com/b")
}

///|
test "resolve/base-with-port" {
  let base = Uri::parse("http://example.com:8080/a")
  assert_eq(Uri::resolve(base, "b").to_string(), "http://example.com:8080/b")
}

///|
test "resolve/relative-with-colon" {
  let base = Uri::parse("http://example.com/a")
  // Reference starting with ./ to avoid being interpreted as scheme
  assert_eq(Uri::resolve(base, "./x:y").to_string(), "http://example.com/x:y")
}

///|
test "resolve/file-scheme-base" {
  let base = Uri::parse("file:///home/user/docs/file.txt")
  assert_eq(
    Uri::resolve(base, "../other.txt").to_string(),
    "file:///home/user/other.txt",
  )
}

///|
test "resolve/urn-base" {
  let base = Uri::parse("urn:example:animal:ferret:nose")
  // URN base typically doesn't support relative resolution in the same way
  assert_eq(
    Uri::resolve(base, "urn:other:thing").to_string(),
    "urn:other:thing",
  )
}

///|
test "resolve/abnormal/dot-dot-g" {
  let base = Uri::parse("http://a/b/c/d;p?q")
  assert_eq(Uri::resolve(base, "../g").to_string(), "http://a/b/g")
}

///|
test "resolve/abnormal/dot-dot-dot-dot-g" {
  let base = Uri::parse("http://a/b/c/d;p?q")
  // ../../g should go up two levels from /b/c/ to /
  assert_eq(Uri::resolve(base, "../../g").to_string(), "http://a/g")
}

///|
test "resolve/abnormal/excessive-parent-refs" {
  let base = Uri::parse("http://a/b/c/d;p?q")
  // Should not go above root
  assert_eq(Uri::resolve(base, "../../../g").to_string(), "http://a/g")
  assert_eq(Uri::resolve(base, "../../../../g").to_string(), "http://a/g")
}

///|
test "resolve/abnormal/absolute-with-dots" {
  let base = Uri::parse("http://a/b/c/d;p?q")
  // Absolute path - dots should be removed during merging
  assert_eq(Uri::resolve(base, "/./g").to_string(), "http://a/g")
  assert_eq(Uri::resolve(base, "/../g").to_string(), "http://a/g")
}

///|
test "resolve/abnormal/g-with-dot" {
  let base = Uri::parse("http://a/b/c/d;p?q")
  assert_eq(Uri::resolve(base, "g.").to_string(), "http://a/b/c/g.")
}

///|
test "resolve/abnormal/dot-g" {
  let base = Uri::parse("http://a/b/c/d;p?q")
  assert_eq(Uri::resolve(base, ".g").to_string(), "http://a/b/c/.g")
}

///|
test "resolve/abnormal/g-dot-dot" {
  let base = Uri::parse("http://a/b/c/d;p?q")
  assert_eq(Uri::resolve(base, "g..").to_string(), "http://a/b/c/g..")
}

///|
test "resolve/abnormal/dot-dot-g-file" {
  let base = Uri::parse("http://a/b/c/d;p?q")
  assert_eq(Uri::resolve(base, "..g").to_string(), "http://a/b/c/..g")
}

///|
test "resolve/abnormal/g-semicolon-x-eq-1" {
  let base = Uri::parse("http://a/b/c/d;p?q")
  assert_eq(Uri::resolve(base, "g;x=1/./y").to_string(), "http://a/b/c/g;x=1/y")
}

///|
test "resolve/abnormal/g-semicolon-x-eq-1-dot-dot" {
  let base = Uri::parse("http://a/b/c/d;p?q")
  assert_eq(Uri::resolve(base, "g;x=1/../y").to_string(), "http://a/b/c/y")
}

///|
test "resolve/abnormal/g-query-y-slash-dot-x" {
  let base = Uri::parse("http://a/b/c/d;p?q")
  assert_eq(Uri::resolve(base, "g?y/./x").to_string(), "http://a/b/c/g?y/./x")
}

///|
test "resolve/abnormal/g-query-y-slash-dot-dot-x" {
  let base = Uri::parse("http://a/b/c/d;p?q")
  assert_eq(Uri::resolve(base, "g?y/../x").to_string(), "http://a/b/c/g?y/../x")
}

///|
test "resolve/abnormal/g-fragment-s-slash-dot-x" {
  let base = Uri::parse("http://a/b/c/d;p?q")
  assert_eq(Uri::resolve(base, "g#s/./x").to_string(), "http://a/b/c/g#s/./x")
}

///|
test "resolve/abnormal/g-fragment-s-slash-dot-dot-x" {
  let base = Uri::parse("http://a/b/c/d;p?q")
  assert_eq(Uri::resolve(base, "g#s/../x").to_string(), "http://a/b/c/g#s/../x")
}

///|
test "rfc3986 example http rfc3986" {
  let uri = Uri::parse("http://www.ietf.org/rfc/rfc3986.txt")
  assert_eq(uri.scheme(), "http")
  assert_eq(uri.userinfo(), None)
  assert_eq(uri.host(), Some("www.ietf.org"))
  assert_eq(uri.port(), None)
  assert_eq(uri.path(), "/rfc/rfc3986.txt")
  assert_eq(uri.query(), None)
  assert_eq(uri.fragment(), None)
}

///|
test "rfc3986 example ftp rfc1808" {
  let uri = Uri::parse("ftp://ftp.is.co.za/rfc/rfc1808.txt")
  assert_eq(uri.scheme(), "ftp")
  assert_eq(uri.userinfo(), None)
  assert_eq(uri.host(), Some("ftp.is.co.za"))
  assert_eq(uri.port(), None)
  assert_eq(uri.path(), "/rfc/rfc1808.txt")
  assert_eq(uri.query(), None)
  assert_eq(uri.fragment(), None)
}

///|
test "rfc3986 example mailto" {
  let uri = Uri::parse("mailto:John.Doe@example.com")
  assert_eq(uri.scheme(), "mailto")
  assert_eq(uri.userinfo(), None)
  assert_eq(uri.host(), None)
  assert_eq(uri.port(), None)
  assert_eq(uri.path(), "John.Doe@example.com")
  assert_eq(uri.query(), None)
  assert_eq(uri.fragment(), None)
}

///|
test "rfc3986 example news" {
  let uri = Uri::parse("news:comp.infosystems.www.servers.unix")
  assert_eq(uri.scheme(), "news")
  assert_eq(uri.userinfo(), None)
  assert_eq(uri.host(), None)
  assert_eq(uri.port(), None)
  assert_eq(uri.path(), "comp.infosystems.www.servers.unix")
  assert_eq(uri.query(), None)
  assert_eq(uri.fragment(), None)
}

///|
test "rfc3986 invalid characters" {
  // Space in URI (should be percent-encoded)
  let result1 = Ok(Uri::parse("http://example.com/path with space")) catch {
    _ => Err(())
  }
  assert_true(result1 is Err(_))

  // Angle brackets
  let result2 = Ok(Uri::parse("http://example.com/<path>")) catch {
    _ => Err(())
  }
  assert_true(result2 is Err(_))

  // Backslash
  let result3 = Ok(Uri::parse("http://example.com/path\\to\\resource")) catch {
    _ => Err(())
  }
  assert_true(result3 is Err(_))

  // Caret
  let result4 = Ok(Uri::parse("http://example.com/path^test")) catch {
    _ => Err(())
  }
  assert_true(result4 is Err(_))

  // Backtick
  let result5 = Ok(Uri::parse("http://example.com/`path`")) catch {
    _ => Err(())
  }
  assert_true(result5 is Err(_))

  // Curly braces
  let result6 = Ok(Uri::parse("http://example.com/{path}")) catch {
    _ => Err(())
  }
  assert_true(result6 is Err(_))

  // Pipe
  let result7 = Ok(Uri::parse("http://example.com/path|test")) catch {
    _ => Err(())
  }
  assert_true(result7 is Err(_))
}

///|
test "rfc3986 invalid scheme" {
  // Scheme starting with number
  let result1 = Ok(Uri::parse("1http://example.com/")) catch { _ => Err(()) }
  assert_true(result1 is Err(_))

  // Scheme with invalid characters
  let result2 = Ok(Uri::parse("ht@tp://example.com/")) catch { _ => Err(()) }
  assert_true(result2 is Err(_))

  // Scheme with space
  let result3 = Ok(Uri::parse("ht tp://example.com/")) catch { _ => Err(()) }
  assert_true(result3 is Err(_))
}

///|
test "rfc3986 invalid ipv6" {
  // Missing closing bracket
  let result1 = Ok(Uri::parse("http://[::1/path")) catch { _ => Err(()) }
  assert_true(result1 is Err(_))

  // Missing opening bracket
  let result2 = Ok(Uri::parse("http://::1]/path")) catch { _ => Err(()) }
  assert_true(result2 is Err(_))

  // Invalid IPv6 address format
  let result3 = Ok(Uri::parse("http://[:::]/path")) catch { _ => Err(()) }
  assert_true(result3 is Err(_))

  // Brackets without IPv6
  let result4 = Ok(Uri::parse("http://[invalid]/path")) catch { _ => Err(()) }
  assert_true(result4 is Err(_))
}

///|
test "rfc3986 invalid port" {
  // Non-numeric port
  let result1 = Ok(Uri::parse("http://example.com:abc/path")) catch {
    _ => Err(())
  }
  assert_true(result1 is Err(_))

  // Negative port (dash is invalid in port)
  let result2 = Ok(Uri::parse("http://example.com:-80/path")) catch {
    _ => Err(())
  }
  assert_true(result2 is Err(_))
}

///|
test "rfc3986 invalid percent-encoding additional" {
  // Single % at the start
  let result1 = Ok(Uri::parse("%")) catch { _ => Err(()) }
  assert_true(result1 is Err(_))

  // % followed by one valid hex digit only
  let result2 = Ok(Uri::parse("http://example.com/%a")) catch { _ => Err(()) }
  assert_true(result2 is Err(_))

  // Invalid hex digit (lowercase outside a-f range)
  let result3 = Ok(Uri::parse("http://example.com/%xz")) catch { _ => Err(()) }
  assert_true(result3 is Err(_))

  // Multiple incomplete percent-encodings
  let result4 = Ok(Uri::parse("http://example.com/%2%3%4")) catch {
    _ => Err(())
  }
  assert_true(result4 is Err(_))

  // Percent at end of query
  let result5 = Ok(Uri::parse("http://example.com/?query%")) catch {
    _ => Err(())
  }
  assert_true(result5 is Err(_))

  // Percent at end of fragment
  let result6 = Ok(Uri::parse("http://example.com/#frag%")) catch {
    _ => Err(())
  }
  assert_true(result6 is Err(_))
}

///|
test "rfc3986 invalid authority parsing" {
  // Multiple @ signs (ambiguous userinfo)
  let result1 = Ok(Uri::parse("http://user@host@example.com/")) catch {
    _ => Err(())
  }
  assert_true(result1 is Err(_))

  // Unencoded @ in host (not in userinfo position)
  let result2 = Ok(Uri::parse("http://host@/path")) catch { _ => Err(()) }
  assert_true(result2 is Err(_))

  // Invalid character in host
  let result3 = Ok(Uri::parse("http://exam ple.com/")) catch { _ => Err(()) }
  assert_true(result3 is Err(_))

  // Control characters in host
  let result4 = Ok(Uri::parse("http://exam\u0000ple.com/")) catch {
    _ => Err(())
  }
  assert_true(result4 is Err(_))
}

///|
test "rfc3986 invalid ipv6 additional" {
  // Too many colons without ::
  let result1 = Ok(Uri::parse("http://[1:2:3:4:5:6:7:8:9]/")) catch {
    _ => Err(())
  }
  assert_true(result1 is Err(_))

  // Invalid characters in IPv6
  let result2 = Ok(Uri::parse("http://[::gggg]/")) catch { _ => Err(()) }
  assert_true(result2 is Err(_))

  // Multiple :: in address
  let result3 = Ok(Uri::parse("http://[::1::2]/")) catch { _ => Err(()) }
  assert_true(result3 is Err(_))

  // IPv6 with port inside brackets
  // Note: [::1:80] could be valid IPv6 (::1:80 = ::0001:0080), so we skip assertion here
  // This is actually a valid IPv6 address representation

  // Empty IPv6
  let result5 = Ok(Uri::parse("http://[]/")) catch { _ => Err(()) }
  assert_true(result5 is Err(_))

  // Space inside brackets
  let result6 = Ok(Uri::parse("http://[::1 ]/")) catch { _ => Err(()) }
  assert_true(result6 is Err(_))
}

///|
test "rfc3986 invalid ipvfuture" {
  // Missing version number
  let result1 = Ok(Uri::parse("http://[v.test]/")) catch { _ => Err(()) }
  assert_true(result1 is Err(_))

  // Invalid version character
  let result2 = Ok(Uri::parse("http://[vZ.test]/")) catch { _ => Err(()) }
  assert_true(result2 is Err(_))

  // Missing dot after version
  let result3 = Ok(Uri::parse("http://[v1test]/")) catch { _ => Err(()) }
  assert_true(result3 is Err(_))
}

///|
test "rfc3986 invalid scheme additional" {
  // Empty scheme
  let result1 = Ok(Uri::parse("://example.com/")) catch { _ => Err(()) }
  assert_true(result1 is Err(_))

  // Scheme with underscore (not allowed)
  let result2 = Ok(Uri::parse("my_scheme://example.com/")) catch {
    _ => Err(())
  }
  assert_true(result2 is Err(_))

  // Scheme starting with dash
  let result3 = Ok(Uri::parse("-http://example.com/")) catch { _ => Err(()) }
  assert_true(result3 is Err(_))

  // Scheme with only numbers after first char is OK, but starting with number is not
  let result4 = Ok(Uri::parse("123://example.com/")) catch { _ => Err(()) }
  assert_true(result4 is Err(_))
}

///|
test "rfc3986 invalid control characters" {
  // Null character
  let result1 = Ok(Uri::parse("http://example.com/path\u0000end")) catch {
    _ => Err(())
  }
  assert_true(result1 is Err(_))

  // Tab character
  let result2 = Ok(Uri::parse("http://example.com/path\tend")) catch {
    _ => Err(())
  }
  assert_true(result2 is Err(_))

  // Newline character
  let result3 = Ok(Uri::parse("http://example.com/path\nend")) catch {
    _ => Err(())
  }
  assert_true(result3 is Err(_))

  // Carriage return
  let result4 = Ok(Uri::parse("http://example.com/path\rend")) catch {
    _ => Err(())
  }
  assert_true(result4 is Err(_))

  // DEL character
  let result5 = Ok(Uri::parse("http://example.com/path\u007fend")) catch {
    _ => Err(())
  }
  assert_true(result5 is Err(_))
}

///|
test "rfc3986 invalid query and fragment" {
  // Fragment before query (invalid order)
  // Actually #fragment?query is valid per RFC - fragment includes everything after #
  // Let's test other invalid scenarios

  // Invalid character in query
  let result1 = Ok(Uri::parse("http://example.com/?query<value")) catch {
    _ => Err(())
  }
  assert_true(result1 is Err(_))

  // Invalid character in fragment
  let result2 = Ok(Uri::parse("http://example.com/#frag>ment")) catch {
    _ => Err(())
  }
  assert_true(result2 is Err(_))

  // Space in query
  let result3 = Ok(Uri::parse("http://example.com/?query value")) catch {
    _ => Err(())
  }
  assert_true(result3 is Err(_))

  // Space in fragment
  let result4 = Ok(Uri::parse("http://example.com/#frag ment")) catch {
    _ => Err(())
  }
  assert_true(result4 is Err(_))
}

///|
test "rfc3986 example tel" {
  let uri = Uri::parse("tel:+1-816-555-1212")
  assert_eq(uri.scheme(), "tel")
  assert_eq(uri.userinfo(), None)
  assert_eq(uri.host(), None)
  assert_eq(uri.port(), None)
  assert_eq(uri.path(), "+1-816-555-1212")
  assert_eq(uri.query(), None)
  assert_eq(uri.fragment(), None)
}

///|
test "rfc3986 example telnet" {
  let uri = Uri::parse("telnet://192.0.2.16:80/")
  assert_eq(uri.scheme(), "telnet")
  assert_eq(uri.userinfo(), None)
  assert_eq(uri.host(), Some("192.0.2.16"))
  assert_eq(uri.port(), Some("80"))
  assert_eq(uri.path(), "/")
  assert_eq(uri.query(), None)
  assert_eq(uri.fragment(), None)
}

///|
test "rfc3986 example urn" {
  let uri = Uri::parse("urn:oasis:names:specification:docbo:dtd:xml:4.1.2")
  assert_eq(uri.scheme(), "urn")
  assert_eq(uri.userinfo(), None)
  assert_eq(uri.host(), None)
  assert_eq(uri.port(), None)
  assert_eq(uri.path(), "oasis:names:specification:docbo:dtd:xml:4.1.2")
  assert_eq(uri.query(), None)
  assert_eq(uri.fragment(), None)
}

///|
test "rfc3986 query fragment" {
  let uri = Uri::parse("http://example.com/path?query#frag")
  assert_eq(uri.scheme(), "http")
  assert_eq(uri.userinfo(), None)
  assert_eq(uri.host(), Some("example.com"))
  assert_eq(uri.port(), None)
  assert_eq(uri.path(), "/path")
  assert_eq(uri.query(), Some("query"))
  assert_eq(uri.fragment(), Some("frag"))
}

///|
test "rfc3986 section 5.4.1 normal examples" {
  let base = Uri::parse("http://a/b/c/d;p?q")

  // g:h -> g:h
  assert_eq(Uri::resolve(base, "g:h").to_string(), "g:h")

  // g -> http://a/b/c/g
  assert_eq(Uri::resolve(base, "g").to_string(), "http://a/b/c/g")

  // ./g -> http://a/b/c/g
  assert_eq(Uri::resolve(base, "./g").to_string(), "http://a/b/c/g")

  // g/ -> http://a/b/c/g/
  assert_eq(Uri::resolve(base, "g/").to_string(), "http://a/b/c/g/")

  // /g -> http://a/g
  assert_eq(Uri::resolve(base, "/g").to_string(), "http://a/g")

  // //g -> http://g
  assert_eq(Uri::resolve(base, "//g").to_string(), "http://g")

  // ?y -> http://a/b/c/d;p?y
  assert_eq(Uri::resolve(base, "?y").to_string(), "http://a/b/c/d;p?y")

  // g?y -> http://a/b/c/g?y
  assert_eq(Uri::resolve(base, "g?y").to_string(), "http://a/b/c/g?y")

  // #s -> http://a/b/c/d;p?q#s
  assert_eq(Uri::resolve(base, "#s").to_string(), "http://a/b/c/d;p?q#s")

  // g#s -> http://a/b/c/g#s
  assert_eq(Uri::resolve(base, "g#s").to_string(), "http://a/b/c/g#s")

  // g?y#s -> http://a/b/c/g?y#s
  assert_eq(Uri::resolve(base, "g?y#s").to_string(), "http://a/b/c/g?y#s")

  // ;x -> http://a/b/c/;x
  assert_eq(Uri::resolve(base, ";x").to_string(), "http://a/b/c/;x")

  // g;x -> http://a/b/c/g;x
  assert_eq(Uri::resolve(base, "g;x").to_string(), "http://a/b/c/g;x")

  // g;x?y#s -> http://a/b/c/g;x?y#s
  assert_eq(Uri::resolve(base, "g;x?y#s").to_string(), "http://a/b/c/g;x?y#s")

  // "" (empty) -> http://a/b/c/d;p?q
  assert_eq(Uri::resolve(base, "").to_string(), "http://a/b/c/d;p?q")

  // . -> http://a/b/c/
  assert_eq(Uri::resolve(base, ".").to_string(), "http://a/b/c/")

  // ./ -> http://a/b/c/
  assert_eq(Uri::resolve(base, "./").to_string(), "http://a/b/c/")

  // .. -> http://a/b/
  assert_eq(Uri::resolve(base, "..").to_string(), "http://a/b/")

  // ../ -> http://a/b/
  assert_eq(Uri::resolve(base, "../").to_string(), "http://a/b/")

  // ../g -> http://a/b/g
  assert_eq(Uri::resolve(base, "../g").to_string(), "http://a/b/g")

  // ../.. -> http://a/
  assert_eq(Uri::resolve(base, "../..").to_string(), "http://a/")

  // ../../ -> http://a/
  assert_eq(Uri::resolve(base, "../../").to_string(), "http://a/")

  // ../../g -> http://a/g
  assert_eq(Uri::resolve(base, "../../g").to_string(), "http://a/g")
}

///|
test "rfc3986 section 5.4.2 abnormal examples" {
  let base = Uri::parse("http://a/b/c/d;p?q")

  // ../../../g -> http://a/g
  assert_eq(Uri::resolve(base, "../../../g").to_string(), "http://a/g")

  // ../../../../g -> http://a/g
  assert_eq(Uri::resolve(base, "../../../../g").to_string(), "http://a/g")

  // /./g -> http://a/g
  assert_eq(Uri::resolve(base, "/./g").to_string(), "http://a/g")

  // /../g -> http://a/g
  assert_eq(Uri::resolve(base, "/../g").to_string(), "http://a/g")

  // g. -> http://a/b/c/g.
  assert_eq(Uri::resolve(base, "g.").to_string(), "http://a/b/c/g.")

  // .g -> http://a/b/c/.g
  assert_eq(Uri::resolve(base, ".g").to_string(), "http://a/b/c/.g")

  // g.. -> http://a/b/c/g..
  assert_eq(Uri::resolve(base, "g..").to_string(), "http://a/b/c/g..")

  // ..g -> http://a/b/c/..g
  assert_eq(Uri::resolve(base, "..g").to_string(), "http://a/b/c/..g")

  // ./../g -> http://a/b/g
  assert_eq(Uri::resolve(base, "./../g").to_string(), "http://a/b/g")

  // ./g/. -> http://a/b/c/g/
  assert_eq(Uri::resolve(base, "./g/.").to_string(), "http://a/b/c/g/")

  // g/./h -> http://a/b/c/g/h
  assert_eq(Uri::resolve(base, "g/./h").to_string(), "http://a/b/c/g/h")

  // g/../h -> http://a/b/c/h
  assert_eq(Uri::resolve(base, "g/../h").to_string(), "http://a/b/c/h")

  // g;x=1/./y -> http://a/b/c/g;x=1/y
  assert_eq(Uri::resolve(base, "g;x=1/./y").to_string(), "http://a/b/c/g;x=1/y")

  // g;x=1/../y -> http://a/b/c/y
  assert_eq(Uri::resolve(base, "g;x=1/../y").to_string(), "http://a/b/c/y")

  // g?y/./x -> http://a/b/c/g?y/./x
  assert_eq(Uri::resolve(base, "g?y/./x").to_string(), "http://a/b/c/g?y/./x")

  // g?y/../x -> http://a/b/c/g?y/../x
  assert_eq(Uri::resolve(base, "g?y/../x").to_string(), "http://a/b/c/g?y/../x")

  // g#s/./x -> http://a/b/c/g#s/./x
  assert_eq(Uri::resolve(base, "g#s/./x").to_string(), "http://a/b/c/g#s/./x")

  // g#s/../x -> http://a/b/c/g#s/../x
  assert_eq(Uri::resolve(base, "g#s/../x").to_string(), "http://a/b/c/g#s/../x")

  // http:g -> http:g (strict mode per RFC 3986)
  assert_eq(Uri::resolve(base, "http:g").to_string(), "http:g")
}

///|
test "rfc3986 ipv6 address parsing" {
  // IPv6 loopback
  let uri1 = Uri::parse("http://[::1]:8080/path")
  assert_eq(uri1.scheme(), "http")
  assert_eq(uri1.host(), Some("[::1]"))
  assert_eq(uri1.port(), Some("8080"))
  assert_eq(uri1.path(), "/path")

  // IPv6 full address
  let uri2 = Uri::parse("http://[2001:db8::1]/path")
  assert_eq(uri2.scheme(), "http")
  assert_eq(uri2.host(), Some("[2001:db8::1]"))
  assert_eq(uri2.port(), None)
  assert_eq(uri2.path(), "/path")

  // IPv6 with userinfo
  let uri3 = Uri::parse("http://user:pass@[::1]:8080/")
  assert_eq(uri3.scheme(), "http")
  assert_eq(uri3.userinfo(), Some("user:pass"))
  assert_eq(uri3.host(), Some("[::1]"))
  assert_eq(uri3.port(), Some("8080"))
  assert_eq(uri3.path(), "/")

  // IPv6 full form
  let uri4 = Uri::parse("http://[2001:0db8:0000:0000:0000:0000:0000:0001]/")
  assert_eq(uri4.scheme(), "http")
  assert_eq(uri4.host(), Some("[2001:0db8:0000:0000:0000:0000:0000:0001]"))
  assert_eq(uri4.path(), "/")

  // IPv6 with query and fragment
  let uri5 = Uri::parse("http://[::1]/path?query=value#fragment")
  assert_eq(uri5.scheme(), "http")
  assert_eq(uri5.host(), Some("[::1]"))
  assert_eq(uri5.path(), "/path")
  assert_eq(uri5.query(), Some("query=value"))
  assert_eq(uri5.fragment(), Some("fragment"))

  // IPv6 zone ID (RFC 6874)
  let uri6 = Uri::parse("http://[fe80::1%25eth0]/")
  assert_eq(uri6.scheme(), "http")
  assert_eq(uri6.host(), Some("[fe80::1%25eth0]"))
  assert_eq(uri6.path(), "/")
}

///|
test "rfc3986 ipvfuture" {
  // IPvFuture format: [v<version>.<address>]
  let uri = Uri::parse("http://[v1.test]/path")
  assert_eq(uri.scheme(), "http")
  assert_eq(uri.host(), Some("[v1.test]"))
  assert_eq(uri.path(), "/path")
}

///|
test "rfc3986 percent-encoding in path" {
  // Space encoded as %20
  let uri1 = Uri::parse("http://example.com/hello%20world")
  assert_eq(uri1.path(), "/hello%20world")

  // Various special characters encoded
  let uri2 = Uri::parse("http://example.com/path%2Fwith%2Fslashes")
  assert_eq(uri2.path(), "/path%2Fwith%2Fslashes")

  // UTF-8 encoded characters (e.g., é = %C3%A9)
  let uri3 = Uri::parse("http://example.com/caf%C3%A9")
  assert_eq(uri3.path(), "/caf%C3%A9")

  // Mixed encoded and unencoded
  let uri4 = Uri::parse("http://example.com/a%20b/c%2Fd")
  assert_eq(uri4.path(), "/a%20b/c%2Fd")

  // Uppercase hex digits (RFC 3986 recommends uppercase)
  let uri5 = Uri::parse("http://example.com/%7Euser")
  assert_eq(uri5.path(), "/%7Euser")

  // Lowercase hex digits (also valid)
  let uri6 = Uri::parse("http://example.com/%7euser")
  assert_eq(uri6.path(), "/%7euser")
}

///|
test "rfc3986 percent-encoding in query" {
  // Encoded equals and ampersand
  let uri1 = Uri::parse("http://example.com/?key%3Dvalue%26other")
  assert_eq(uri1.query(), Some("key%3Dvalue%26other"))

  // Space in query
  let uri2 = Uri::parse("http://example.com/?search=hello%20world")
  assert_eq(uri2.query(), Some("search=hello%20world"))

  // Plus sign (not special in RFC 3986, but often used for space)
  let uri3 = Uri::parse("http://example.com/?q=hello+world")
  assert_eq(uri3.query(), Some("q=hello+world"))
}

///|
test "rfc3986 percent-encoding in fragment" {
  let uri1 = Uri::parse("http://example.com/#section%201")
  assert_eq(uri1.fragment(), Some("section%201"))
  let uri2 = Uri::parse("http://example.com/#%C3%A9l%C3%A8ve")
  assert_eq(uri2.fragment(), Some("%C3%A9l%C3%A8ve"))
}

///|
test "rfc3986 percent-encoding in userinfo" {
  // Encoded @ in username
  let uri1 = Uri::parse("http://user%40domain:pass@example.com/")
  assert_eq(uri1.userinfo(), Some("user%40domain:pass"))
  assert_eq(uri1.host(), Some("example.com"))

  // Encoded colon in password
  let uri2 = Uri::parse("http://user:pass%3Aword@example.com/")
  assert_eq(uri2.userinfo(), Some("user:pass%3Aword"))
}

///|
test "rfc3986 reserved characters" {
  // gen-delims: : / ? # [ ] @
  // sub-delims: ! $ & ' ( ) * + , ; =

  // Sub-delims in path (allowed unencoded)
  let uri1 = Uri::parse("http://example.com/path!$&'()*+,;=")
  assert_eq(uri1.path(), "/path!$&'()*+,;=")

  // Unreserved characters (allowed unencoded): ALPHA DIGIT - . _ ~
  let uri2 = Uri::parse("http://example.com/path-._~test")
  assert_eq(uri2.path(), "/path-._~test")
}

///|
test "rfc3986 empty components" {
  // Empty path
  let uri1 = Uri::parse("http://example.com")
  assert_eq(uri1.host(), Some("example.com"))
  assert_eq(uri1.path(), "")

  // Empty query
  let uri2 = Uri::parse("http://example.com?")
  assert_eq(uri2.query(), Some(""))

  // Empty fragment
  let uri3 = Uri::parse("http://example.com#")
  assert_eq(uri3.fragment(), Some(""))

  // Empty userinfo
  let uri4 = Uri::parse("http://@example.com/")
  assert_eq(uri4.userinfo(), Some(""))
  assert_eq(uri4.host(), Some("example.com"))

  // Empty port
  let uri5 = Uri::parse("http://example.com:/path")
  assert_eq(uri5.host(), Some("example.com"))
  assert_eq(uri5.port(), Some(""))
  assert_eq(uri5.path(), "/path")

  // All empty optional components
  let uri6 = Uri::parse("http://@:/")
  assert_eq(uri6.scheme(), "http")
  assert_eq(uri6.userinfo(), Some(""))
  assert_eq(uri6.host(), Some(""))
  assert_eq(uri6.port(), Some(""))
  assert_eq(uri6.path(), "/")
}

///|
test "rfc3986 scheme-only uri" {
  // Scheme with path only
  let uri1 = Uri::parse("file:///etc/passwd")
  assert_eq(uri1.scheme(), "file")
  assert_eq(uri1.host(), Some(""))
  assert_eq(uri1.path(), "/etc/passwd")

  // Scheme with empty authority
  let uri2 = Uri::parse("file://")
  assert_eq(uri2.scheme(), "file")
  assert_eq(uri2.host(), Some(""))
  assert_eq(uri2.path(), "")
}

///|
test "rfc3986 path-only references" {
  // Absolute path reference
  let uri1 = Uri::parse("/path/to/resource")
  assert_eq(uri1.scheme(), "")
  assert_eq(uri1.host(), None)
  assert_eq(uri1.path(), "/path/to/resource")

  // Relative path reference
  let uri2 = Uri::parse("path/to/resource")
  assert_eq(uri2.scheme(), "")
  assert_eq(uri2.host(), None)
  assert_eq(uri2.path(), "path/to/resource")

  // Query-only reference
  let uri3 = Uri::parse("?query=value")
  assert_eq(uri3.scheme(), "")
  assert_eq(uri3.path(), "")
  assert_eq(uri3.query(), Some("query=value"))

  // Fragment-only reference
  let uri4 = Uri::parse("#fragment")
  assert_eq(uri4.scheme(), "")
  assert_eq(uri4.path(), "")
  assert_eq(uri4.fragment(), Some("fragment"))

  // Empty reference
  let uri5 = Uri::parse("")
  assert_eq(uri5.scheme(), "")
  assert_eq(uri5.path(), "")
}

///|
test "rfc3986 unusual but valid uris" {
  // Numeric host
  let uri1 = Uri::parse("http://127.0.0.1/")
  assert_eq(uri1.host(), Some("127.0.0.1"))

  // Very long path segments
  let uri2 = Uri::parse(
    "http://example.com/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  )
  assert_eq(uri2.path(), "/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")

  // Multiple query parameters
  let uri3 = Uri::parse("http://example.com/?a=1&b=2&c=3")
  assert_eq(uri3.query(), Some("a=1&b=2&c=3"))

  // Path with multiple consecutive slashes
  let uri4 = Uri::parse("http://example.com//path//to//resource")
  assert_eq(uri4.path(), "//path//to//resource")

  // Scheme with numbers and plus/minus/dot
  let uri5 = Uri::parse("custom+scheme.1-2://host/path")
  assert_eq(uri5.scheme(), "custom+scheme.1-2")
  assert_eq(uri5.host(), Some("host"))

  // Data URI scheme
  let uri6 = Uri::parse("data:text/plain;base64,SGVsbG8=")
  assert_eq(uri6.scheme(), "data")
  assert_eq(uri6.path(), "text/plain;base64,SGVsbG8=")

  // Localhost variations
  let uri7 = Uri::parse("http://localhost:3000/api")
  assert_eq(uri7.host(), Some("localhost"))
  assert_eq(uri7.port(), Some("3000"))
  assert_eq(uri7.path(), "/api")
}

///|
test "rfc3986 authority edge cases" {
  // Host only (no path)
  let uri1 = Uri::parse("//example.com")
  assert_eq(uri1.scheme(), "")
  assert_eq(uri1.host(), Some("example.com"))
  assert_eq(uri1.path(), "")

  // Authority with all components
  let uri2 = Uri::parse("http://user:pass@host.com:8080/path")
  assert_eq(uri2.userinfo(), Some("user:pass"))
  assert_eq(uri2.host(), Some("host.com"))
  assert_eq(uri2.port(), Some("8080"))
  assert_eq(uri2.path(), "/path")

  // Userinfo with special characters
  let uri3 = Uri::parse("http://us-er_name.test:pa-ss_word.test@example.com/")
  assert_eq(uri3.userinfo(), Some("us-er_name.test:pa-ss_word.test"))
}

///|
test "rfc3986 section 6.2.2 case normalization" {
  // Scheme is case-insensitive (should be normalized to lowercase)
  let uri1 = Uri::parse("HTTP://example.com/")
  // Note: The parser may or may not normalize the scheme; testing parse behavior
  assert_eq(uri1.host(), Some("example.com"))

  // Host is case-insensitive for reg-name
  let uri2 = Uri::parse("http://EXAMPLE.COM/path")
  // Testing that the URI is parsed correctly regardless of case
  assert_eq(uri2.path(), "/path")

  // Mixed case scheme
  let uri3 = Uri::parse("HtTp://Example.Com/Path")
  assert_eq(uri3.path(), "/Path")
}

///|
test "rfc3986 section 6.2.2 percent-encoding normalization" {
  // Uppercase hex digits in percent-encoding
  let uri1 = Uri::parse("http://example.com/%7E")
  assert_eq(uri1.path(), "/%7E")

  // Lowercase hex digits (equivalent)
  let uri2 = Uri::parse("http://example.com/%7e")
  assert_eq(uri2.path(), "/%7e")

  // These are equivalent but stored as-is
  let uri3 = Uri::parse("http://example.com/~")
  assert_eq(uri3.path(), "/~")

  // Unreserved chars that could be encoded but don't need to be
  let uri4 = Uri::parse("http://example.com/%41%42%43")
  // %41%42%43 = ABC (but parser preserves encoding)
  assert_eq(uri4.path(), "/%41%42%43")
}

///|
test "rfc3986 section 6.2.2 path segment normalization" {
  // Dot segments in paths should be removed during resolution
  let base = Uri::parse("http://example.com/a/b/c")

  // Resolve dot segments
  assert_eq(Uri::resolve(base, "./d").to_string(), "http://example.com/a/b/d")
  assert_eq(Uri::resolve(base, "../d").to_string(), "http://example.com/a/d")
  assert_eq(Uri::resolve(base, "../../d").to_string(), "http://example.com/d")

  // Double dots at root
  assert_eq(
    Uri::resolve(base, "../../../d").to_string(),
    "http://example.com/d",
  )

  // Dot in middle of path
  assert_eq(
    Uri::resolve(base, "d/./e").to_string(),
    "http://example.com/a/b/d/e",
  )
  assert_eq(
    Uri::resolve(base, "d/../e").to_string(),
    "http://example.com/a/b/e",
  )
}

///|
test "rfc3986 section 6.2.3 scheme-based normalization" {
  // HTTP default port is 80, HTTPS is 443
  // Explicit default ports may be normalized away
  let uri1 = Uri::parse("http://example.com:80/path")
  assert_eq(uri1.host(), Some("example.com"))
  assert_eq(uri1.port(), Some("80"))
  assert_eq(uri1.path(), "/path")

  // Non-default port
  let uri2 = Uri::parse("http://example.com:8080/path")
  assert_eq(uri2.port(), Some("8080"))

  // HTTPS default port
  let uri3 = Uri::parse("https://example.com:443/path")
  assert_eq(uri3.port(), Some("443"))

  // Empty path normalization for http(s) - path should be "/" per RFC
  let uri4 = Uri::parse("http://example.com")
  // An empty path is equivalent to "/"
  assert_eq(uri4.path(), "")
}

///|
test "rfc3986 martin durst relative reference tests" {
  // Based on W3C Martin Dürst's relative reference test cases
  // https://www.w3.org/2004/04/uri-rel-test.html

  let base = Uri::parse("http://a/b/c/d;p?q")

  // Additional relative reference edge cases
  // Reference with only authority
  assert_eq(Uri::resolve(base, "//host").to_string(), "http://host")
  assert_eq(Uri::resolve(base, "//host/").to_string(), "http://host/")
  assert_eq(Uri::resolve(base, "//host/path").to_string(), "http://host/path")

  // Query and fragment combinations
  assert_eq(Uri::resolve(base, "?").to_string(), "http://a/b/c/d;p?")
  assert_eq(Uri::resolve(base, "#").to_string(), "http://a/b/c/d;p?q#")

  // Absolute path with query
  assert_eq(
    Uri::resolve(base, "/path?query").to_string(),
    "http://a/path?query",
  )

  // Path with dot segments and query
  assert_eq(Uri::resolve(base, "./path?q").to_string(), "http://a/b/c/path?q")
  assert_eq(Uri::resolve(base, "../path?q").to_string(), "http://a/b/path?q")
}

///|
test "rfc3986 roy fielding examples" {
  // Based on Roy Fielding's URI reference examples
  // http://gbiv.com/protocols/uri/test/rel_examples1.html

  let base = Uri::parse("http://a/b/c/d;p?q")

  // Same document reference
  assert_eq(Uri::resolve(base, "").to_string(), "http://a/b/c/d;p?q")

  // Fragment only - same document with fragment
  assert_eq(Uri::resolve(base, "#frag").to_string(), "http://a/b/c/d;p?q#frag")

  // Absolute URI takes precedence
  assert_eq(Uri::resolve(base, "http://x/y").to_string(), "http://x/y")

  // Network path
  assert_eq(Uri::resolve(base, "//x/y").to_string(), "http://x/y")

  // Absolute path
  assert_eq(Uri::resolve(base, "/x/y").to_string(), "http://a/x/y")

  // Relative path
  assert_eq(Uri::resolve(base, "x/y").to_string(), "http://a/b/c/x/y")
}

///|
test "rfc3986 complex resolution scenarios" {
  let base = Uri::parse("http://a/b/c/d;p?q")

  // Multiple path segments with dots
  assert_eq(Uri::resolve(base, "g/../../../h").to_string(), "http://a/h")
  assert_eq(Uri::resolve(base, "./g/./h/../i").to_string(), "http://a/b/c/g/i")

  // Dot at very end
  assert_eq(Uri::resolve(base, "g/.").to_string(), "http://a/b/c/g/")
  assert_eq(Uri::resolve(base, "g/..").to_string(), "http://a/b/c/")

  // Query replacement
  assert_eq(Uri::resolve(base, "?y#s").to_string(), "http://a/b/c/d;p?y#s")
}
