///|
async test "Moon native host layout identifies checkout-local development paths" {
  let root : @path.Path = @fs.tmpdir(prefix="openseek-development-layout-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  let command_dir = root.join(
    "desktop/app/_build/native/debug/build/openseek_desktop/app",
  )
  @fs.mkdir(command_dir.to_string(), recursive=true)
  let executable = command_dir.join("app.exe").to_string()
  guard @development.Layout::detect(executable) is Some(layout) else {
    fail("expected the Moon native host layout to be detected")
  }
  assert_eq(
    layout.state_dir(),
    root.join("desktop/target/dev-state").to_string(),
  )
  assert_true(
    @development.Layout::detect(root.join("installed/app").to_string()) is None,
  )
}
