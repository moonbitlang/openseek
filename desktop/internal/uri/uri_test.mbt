///|
test "path encoding keeps separators and escapes the rest" {
  assert_eq(@uri.encode_path("/a/b.mbt"), "/a/b.mbt")
  assert_eq(@uri.encode_path("/a b/c#d.mbt"), "/a%20b/c%23d.mbt")
  assert_eq(@uri.encode_path("/tmp/中文"), "/tmp/%E4%B8%AD%E6%96%87")
  assert_eq(@uri.encode_path("100%.mbt"), "100%25.mbt")
}

///|
test "component encoding escapes separators too" {
  assert_eq(@uri.encode_component("/ws/proj"), "%2Fws%2Fproj")
  assert_eq(@uri.encode_component("a=b&c"), "a%3Db%26c")
  assert_eq(@uri.encode_component("plain-id_1.2~x"), "plain-id_1.2~x")
}

///|
test "decode reverses both encoders" {
  for text in ["/a b/c#d.mbt", "/tmp/中文", "100%.mbt", "a=b&c?d"] {
    assert_eq(@uri.decode(@uri.encode_path(text)), text)
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
test "file uris encode reserved and non-ascii path bytes" {
  assert_eq(@uri.file_uri("/a/b.mbt"), "file:///a/b.mbt")
  assert_eq(@uri.file_uri("/a b/c#d.mbt"), "file:///a%20b/c%23d.mbt")
  assert_eq(@uri.file_uri("/tmp/中文"), "file:///tmp/%E4%B8%AD%E6%96%87")
}

///|
test "file uris give windows drive paths an authority slash" {
  assert_eq(
    @uri.file_uri("C:\\Users\\dev\\proj\\a.mbt"),
    "file:///C:/Users/dev/proj/a.mbt",
  )
}

///|
test "file uri paths round-trip through encode and decode" {
  for path in ["/a/b.mbt", "/a b/c#d.mbt", "/tmp/中文", "/x/100%.mbt"] {
    assert_eq(@uri.file_uri_path(@uri.file_uri(path)), path)
  }
  assert_eq(
    @uri.file_uri_path(@uri.file_uri("C:\\Users\\dev\\a.mbt")),
    "C:/Users/dev/a.mbt",
  )
}

///|
test "file uri path decode tolerates other schemes" {
  assert_eq(@uri.file_uri_path("untitled:one"), "untitled:one")
}
