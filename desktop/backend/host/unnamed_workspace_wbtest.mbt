///|
test "unnamed workspace storage uses stable app data rather than development runtime state" {
  guard platform_app_data_dir() is Some(data) else {
    fail("expected platform app data")
  }
  assert_eq(
    unnamed_workspaces_dir(),
    data.join("SeekMoon").join("workspaces").resolve().normalize(),
  )
}

///|
async test "chat root metadata reports broken storage without raising into registry operations" {
  let dir = @fs.tmpdir(prefix="openseek-chat-root-error-")
  defer @fs.rmdir(dir, recursive=true)
  let parent = @pathx.Path(dir).resolve().join("file")
  @fs.write_text(parent.to_string(), "keep", create_mode=CreateOrTruncate)
  assert_true(chat_workspace_root_in(parent.join("workspaces")) is Failed(_))
  assert_true(chat_workspace_root_in(parent) is Failed(_))
  let missing = @pathx.Path(dir).resolve().join("not-created-yet")
  assert_eq(chat_workspace_root_in(missing), Ready(missing.resource_path()))
  let usable = @pathx.Path(dir).resolve().join("usable")
  @fs.mkdir(usable.to_string())
  assert_true(chat_workspace_root_in(usable) is Ready(_))
  assert_eq(@fs.read_text(parent.to_string()), "keep")
}
