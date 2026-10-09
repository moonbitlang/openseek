///|
test "component encoding escapes separators too" {
  assert_eq(@uri.encode_component("/ws/proj"), "%2Fws%2Fproj")
  assert_eq(@uri.encode_component("a=b&c"), "a%3Db%26c")
  assert_eq(@uri.encode_component("plain-id_1.2~x"), "plain-id_1.2~x")
}

///|
test "decode reverses component encoding" {
  for text in ["/a b/c#d.mbt", "/tmp/中文", "100%.mbt", "a=b&c?d"] {
    assert_eq(@uri.decode(@uri.encode_component(text)), text)
  }
}

///|
test "decode leaves malformed escapes literal" {
  assert_eq(@uri.decode("a%2"), "a%2")
  assert_eq(@uri.decode("a%zz"), "a%zz")
  assert_eq(@uri.decode("a%"), "a%")
}

///|
test "component decoding preserves URI component semantics" {
  for
    (encoded, decoded) in [
      ("Application%20Support", "Application Support"),
      ("%e4%b8%ad%E6%96%87%F0%9F%8C%99", "中文🌙"),
      ("中文%20🌙", "中文 🌙"),
      ("a+b%2Bc", "a+b+c"),
      ("%2520", "%20"),
      ("%2F%3F%23%26%3D%3A", "/?#&=:"),
      ("%EF%BB%BFx%EF%BB%BF", "\u{FEFF}x\u{FEFF}"),
      ("%00", "\u{0}"),
      ("", ""),
    ] {
    assert_eq(@uri.decode_component(encoded), decoded)
  }
}

///|
test "component decoding keeps all input on malformed escapes or UTF8" {
  for
    malformed in [
      "%", "%2", "%zz", "%0g", "%g0", "%80", "%BF", "%C0%AF", "%C1%BF", "%C2", "%C2x%A0",
      "%E0%80%AF", "%ED%A0%80", "%ED%BF%BF", "%E2%82", "%F0%80%80%AF", "%F4%90%80%80",
      "%F5%80%80%80", "%FF",
    ] {
    // Earlier valid escapes must not be decoded when a later escape fails.
    let input = "prefix%20\{malformed}%20suffix"
    assert_eq(@uri.decode_component(input), input)
  }
}

///|
test "pure component encoding and decoding round trip Unicode and ASCII" {
  for
    text in [
      "", "Application Support", "中文🌙", "a+b/c?d#e&f=g", "100%", "\u{0}\u{7F}\u{80}\u{7FF}\u{800}\u{D7FF}\u{E000}\u{FFFF}\u{10000}\u{10FFFF}",
      "\u{FEFF}BOM",
    ] {
    assert_eq(@uri.decode_component(@uri.encode_component(text)), text)
  }
  assert_eq(
    @uri.encode_component("中文🌙"),
    "%E4%B8%AD%E6%96%87%F0%9F%8C%99",
  )
  // Desktop's encoder uses the RFC 3986 unreserved set, which is stricter
  // than JavaScript's encoder; retain the established authentication URLs.
  assert_eq(@uri.encode_component("!'()*+"), "%21%27%28%29%2A%2B")
  for code in 0..<128 {
    let text = code.unsafe_to_char().to_string()
    assert_eq(@uri.decode_component(@uri.encode_component(text)), text)
  }
}

///|
test "local file URLs preserve path separators and escape filename syntax" {
  assert_eq(
    @uri.file_url("/tmp/中文 #?%.pdf"),
    "file:///tmp/%E4%B8%AD%E6%96%87%20%23%3F%25.pdf",
  )
  assert_eq(
    @uri.file_url("/C:/Users/Test/document.pdf"),
    "file:///C:/Users/Test/document.pdf",
  )
}

///|
test "file URL recognition is independent of file type" {
  assert_true(@uri.is_file_url("file:///tmp/index.html"))
  assert_true(@uri.is_file_url("FILE:///tmp/report.pdf"))
  assert_true(@uri.is_file_url("file://server/share/image.png"))
  assert_false(@uri.is_file_url("file://"))
  assert_false(@uri.is_file_url("file:relative.html"))
  assert_false(@uri.is_file_url("https://example.com/file://index.html"))
}

///|
test "local file URL paths decode once after removing query and fragment" {
  for
    path in [
      "/tmp/中文 #?100%.pdf", "/tmp/a+b.pdf", "/tmp/%20.pdf", "/C:/Users/Test/report.pdf",
    ] {
    let url = @uri.file_url(path)
    assert_eq(@uri.local_file_path(url), Some(path))
    assert_eq(@uri.local_file_path(url + "?query#page=2"), Some(path))
    assert_eq(@uri.local_file_path(url + "#page=2?query"), Some(path))
    assert_eq(
      @uri.local_file_path("FILE://LOCALHOST" + url[7:].to_owned()),
      Some(path),
    )
  }
  assert_eq(@uri.local_file_path("file:///tmp/a+b.pdf"), Some("/tmp/a+b.pdf"))
}

///|
test "local file URL paths reject remote authorities and malformed paths" {
  for
    url in [
      "https://example.com/report.pdf", "file://server/share/report.pdf", "file://localhost.example/report.pdf",
      "file://user@localhost/report.pdf", "file://localhost:80/report.pdf", "file:relative.pdf",
      "file://", "file://localhost", "file:////server/share/report.pdf", "file:///%2Fserver/report.pdf",
      "file:///tmp/%zz.pdf", "file:///tmp/%FF.pdf", "file:///tmp/%00.pdf",
    ] {
    assert_eq(@uri.local_file_path(url), None)
  }
}
