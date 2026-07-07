///|
test "lsp roots contain files across path separators" {
  assert_true(root_contains_file("/ws/proj", "/ws/proj/src/a.mbt"))
  assert_true(root_contains_file("/ws/proj", "/ws/proj"))
  assert_true(root_contains_file("C:\\ws\\proj", "C:\\ws\\proj\\src\\a.mbt"))
  assert_true(root_contains_file("C:\\ws\\proj", "C:/ws/proj/src/a.mbt"))
  assert_false(root_contains_file("/ws/proj", "/ws/project/a.mbt"))
  assert_false(root_contains_file("C:\\ws\\proj", "C:\\ws\\other\\a.mbt"))
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
