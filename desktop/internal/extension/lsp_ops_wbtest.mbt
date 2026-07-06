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
