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
