///|
async test "development state stays inside the detected checkout" {
  let root : @pathx.Path = @fs.tmpdir(prefix="openseek-development-state-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  let command_dir = root.join(
    "_build/native/debug/build/openseek_desktop/backend",
  )
  @fs.mkdir(command_dir.to_string(), recursive=true)
  let executable = command_dir.join("backend.exe").to_string()
  let expected = root.join("desktop/target/dev-state").to_string()
  guard @host.prepared_runtime_dir(executable) is Some(actual) else {
    fail("detected development state directory was not created")
  }
  assert_eq(actual.to_string(), expected)
  assert_true(@fs.kind(expected) is Directory)
}
