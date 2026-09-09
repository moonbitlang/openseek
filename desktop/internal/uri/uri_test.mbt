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
