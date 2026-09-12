///|
async test "unnamed workspace allocation preserves files and handles concurrent names" {
  let dir = @fs.tmpdir(prefix="openseek-unnamed-workspace-")
  defer @fs.rmdir(dir, recursive=true)
  let root = @pathx.Path(dir).resolve().join("workspaces")
  guard create_unnamed_workspace_in(root) is Listing(path=first, ..) else {
    fail("expected a created workspace")
  }
  assert_eq(first, root.join("Unnamed workspace").resource_path())
  let file = root.join("Unnamed workspace").join("keep.txt")
  @fs.write_file(file.to_string(), "user work", create_mode=CreateOrTruncate)
  let paths : Array[String] = []
  @async.with_task_group(group => {
    for _ in 0..<4 {
      group.spawn_bg(() => {
        guard create_unnamed_workspace_in(root) is Listing(path~, ..) else {
          fail("expected a created workspace")
        }
        assert_true(!paths.contains(path))
        paths.push(path)
      })
    }
  })
  assert_eq(paths.length(), 4)
  for index in 2..<6 {
    assert_true(
      paths.contains(
        root
        .join(("Unnamed workspace \{index}" : @pathx.Relative))
        .resource_path(),
      ),
    )
  }
  assert_eq(@fs.read_file(file.to_string()).text(), "user work")
}

///|
async test "unnamed workspace storage errors fail instead of selecting an existing folder" {
  let dir = @fs.tmpdir(prefix="openseek-unnamed-workspace-error-")
  defer @fs.rmdir(dir, recursive=true)
  let root = @pathx.Path(dir).resolve().join("not-a-directory")
  @fs.write_file(root.to_string(), "keep", create_mode=CreateOrTruncate)
  try create_unnamed_workspace_in(root) catch {
    HostError(message) =>
      assert_true(message.contains("workspace storage directory"))
    error => raise error
  } noraise {
    _ => fail("expected the storage failure to propagate")
  }
  assert_eq(@fs.read_file(root.to_string()).text(), "keep")
}

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
