///|
test "file uris encode reserved and non-ascii path bytes" {
  assert_eq(file_uri("/a/b.mbt"), "file:///a/b.mbt")
  assert_eq(file_uri("/a b/c#d.mbt"), "file:///a%20b/c%23d.mbt")
  assert_eq(file_uri("/tmp/中文"), "file:///tmp/%E4%B8%AD%E6%96%87")
  assert_eq(file_uri("/x/100%.mbt"), "file:///x/100%25.mbt")
}

///|
test "file uris give windows drive paths an authority slash" {
  assert_eq(
    file_uri("C:\\Users\\dev\\proj\\a.mbt"),
    "file:///C:/Users/dev/proj/a.mbt",
  )
}

///|
test "file uri paths round-trip through encode and decode" {
  for path in ["/a/b.mbt", "/a b/c#d.mbt", "/tmp/中文", "/x/100%.mbt"] {
    assert_eq(file_uri_path(file_uri(path)), path)
  }
  assert_eq(
    file_uri_path(file_uri("C:\\Users\\dev\\a.mbt")),
    "C:/Users/dev/a.mbt",
  )
}

///|
test "file uri path decode tolerates malformed escapes and other schemes" {
  assert_eq(file_uri_path("file:///a%2"), "/a%2")
  assert_eq(file_uri_path("file:///a%zz"), "/a%zz")
  assert_eq(file_uri_path("untitled:one"), "untitled:one")
}

///|
test "workspace relative strips the workspace prefix on both separators" {
  assert_eq(workspace_relative("file:///ws/src/a.mbt", "/ws"), "src/a.mbt")
  assert_eq(workspace_relative("file:///ws/a%20b.mbt", "/ws"), "a b.mbt")
  assert_eq(
    workspace_relative("file:///C:/ws/src/a.mbt", "C:\\ws"),
    "src/a.mbt",
  )
  assert_eq(workspace_relative("file:///ws", "/ws"), "")
  assert_eq(workspace_relative("file:///other/a.mbt", "/ws"), "/other/a.mbt")
}
