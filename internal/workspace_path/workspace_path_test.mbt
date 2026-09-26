///|
test "workspace path keeps default and absolute paths unchanged" {
  assert_eq(@workspace_path.resolve(".", "src/main.mbt"), "src/main.mbt")
  assert_eq(
    @workspace_path.resolve("/tmp/work", "/var/log/file"),
    "/var/log/file",
  )
  assert_true(@workspace_path.resolve_cwd(".", None) is None)
}

///|
test "workspace path resolves relative paths under a non-default root" {
  assert_eq(
    @workspace_path.resolve("/tmp/work", "src/../README.md"),
    "/tmp/work/README.md",
  )
  assert_true(
    @workspace_path.resolve_cwd("/tmp/work", None) is Some("/tmp/work"),
  )
  assert_true(
    @workspace_path.resolve_cwd("/tmp/work", Some("subdir"))
    is Some("/tmp/work/subdir"),
  )
}

///|
test "lexical path helpers preserve roots and normalize separators" {
  assert_eq(@workspace_path.strip_trailing_slash("/work///"), "/work")
  assert_eq(@workspace_path.strip_trailing_slash("/"), "/")
  assert_true(@workspace_path.parent_dir("/") is None)
  // A leading slash is the whole parent: the part before it is empty, and the
  // answer is the root rather than "".
  assert_true(@workspace_path.parent_dir("/work") is Some("/"))
  assert_true(@workspace_path.parent_dir("/work/lib") is Some("/work"))
  assert_true(@workspace_path.parent_dir("relative/lib") is Some("relative"))
  assert_true(@workspace_path.parent_dir("bare") is Some("."))
  assert_true(@workspace_path.parent_dir("C:") is None)
  assert_true(@workspace_path.parent_dir("C:/") is None)
  assert_true(@workspace_path.parent_dir("C:/work") is Some("C:"))
  assert_true(@workspace_path.parent_dir("C:\\work\\lib\\") is Some("C:/work"))
  assert_eq(@workspace_path.join_child(".", "moon.mod"), "moon.mod")
  assert_eq(@workspace_path.join_child("/work/", "moon.mod"), "/work/moon.mod")
  assert_eq(@workspace_path.path_basename("/work/pkg/"), "pkg")
  assert_eq(@workspace_path.path_basename("C:\\work\\main.mbt"), "main.mbt")
  assert_eq(@workspace_path.path_basename("bare"), "bare")
  assert_eq(@workspace_path.path_basename("/main.mbt"), "main.mbt")
  assert_true(@workspace_path.is_under_workspace_root("/work", "/work"))
  assert_true(
    @workspace_path.is_under_workspace_root("/work/", "/work/pkg/main.mbt"),
  )
  assert_false(
    @workspace_path.is_under_workspace_root("/work", "/workspace/main.mbt"),
  )
  assert_true(
    @workspace_path.is_under_workspace_root("C:\\work", "C:\\work\\main.mbt"),
  )
}

///|
test "filesystem path helpers preserve separator spelling" {
  assert_true(
    @workspace_path.parent_dir_preserving_separators("/work/lib")
    is Some("/work"),
  )
  assert_true(
    @workspace_path.parent_dir_preserving_separators("/work") is Some("/"),
  )
  assert_true(
    @workspace_path.parent_dir_preserving_separators("bare") is Some("."),
  )
  assert_true(
    @workspace_path.parent_dir_preserving_separators("C:\\work\\lib\\")
    is Some("C:\\work"),
  )
  assert_true(
    @workspace_path.parent_dir_preserving_separators("C:\\work\\main.mbt")
    is Some("C:\\work"),
  )
  assert_true(@workspace_path.parent_dir_preserving_separators("C:\\") is None)
  assert_eq(
    @workspace_path.join_child_preserving_separator("/work/pkg", "main.mbt"),
    "/work/pkg/main.mbt",
  )
  assert_eq(
    @workspace_path.join_child_preserving_separator("C:\\work\\pkg", "main.mbt"),
    "C:\\work\\pkg\\main.mbt",
  )
}
