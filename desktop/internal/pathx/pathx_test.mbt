///|
test "contains matches roots across path separators" {
  assert_true(@pathx.contains("/ws/proj", "/ws/proj/src/a.mbt"))
  assert_true(@pathx.contains("/ws/proj", "/ws/proj"))
  assert_true(@pathx.contains("C:\\ws\\proj", "C:\\ws\\proj\\src\\a.mbt"))
  assert_true(@pathx.contains("C:\\ws\\proj", "C:/ws/proj/src/a.mbt"))
  assert_false(@pathx.contains("/ws/proj", "/ws/project/a.mbt"))
  assert_false(@pathx.contains("C:\\ws\\proj", "C:\\ws\\other\\a.mbt"))
}

///|
test "relative_to strips the root prefix with normalized separators" {
  @debug.assert_eq(
    @pathx.relative_to("/ws/src/a.mbt", root="/ws"),
    Some("src/a.mbt"),
  )
  @debug.assert_eq(@pathx.relative_to("/ws", root="/ws"), Some(""))
  @debug.assert_eq(
    @pathx.relative_to("C:\\ws\\src\\a.mbt", root="C:\\ws"),
    Some("src/a.mbt"),
  )
  @debug.assert_eq(@pathx.relative_to("/other/a.mbt", root="/ws"), None)
  // A trailing slash on the root reads the same as none.
  @debug.assert_eq(@pathx.relative_to("/ws/a.mbt", root="/ws/"), Some("a.mbt"))
}

///|
test "normalize is lexical only" {
  assert_eq(@pathx.normalize("C:\\a\\b"), "C:/a/b")
  assert_eq(@pathx.normalize("/already/fine"), "/already/fine")
}
