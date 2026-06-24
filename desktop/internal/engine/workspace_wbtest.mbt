// Tests for the pure workspace-path helper. The full
// `session_workspace_dir` / `workspace_root` chain depends on the
// environment (HOME, an existing Documents folder), so the tests cover the
// pure piece: which ids are allowed under the workspace root.

///|
test "session ids are accepted as workspace folder names" {
  assert_true(safe_workspace_id("desktop-20260611-093045-123"))
  assert_true(safe_workspace_id("my-cli-session"))
  assert_true(safe_workspace_id("a.b"))
}

///|
test "ids that could escape the workspace root are rejected" {
  assert_false(safe_workspace_id(""))
  assert_false(safe_workspace_id("."))
  assert_false(safe_workspace_id(".."))
  assert_false(safe_workspace_id("a/b"))
  assert_false(safe_workspace_id("a\\b"))
  assert_false(safe_workspace_id("../escape"))
}

///|
test "absolute paths open as themselves" {
  assert_eq(open_target("/home/u/repo", "/etc/hosts"), "/etc/hosts")
  // Normalized, but never re-rooted into the working directory.
  assert_eq(open_target("/home/u/repo", "/a/b/../c.mbt"), "/a/c.mbt")
}

///|
test "relative paths are taken against the working directory" {
  assert_eq(
    open_target("/home/u/repo", "core/builtin/array.mbt"),
    "/home/u/repo/core/builtin/array.mbt",
  )
  assert_eq(open_target("/home/u/repo", "./main.mbt"), "/home/u/repo/main.mbt")
}

///|
test "a relative path with no working directory is left untouched" {
  assert_eq(open_target("", "core/builtin/array.mbt"), "core/builtin/array.mbt")
  assert_eq(open_target("", ""), "")
}

///|
/// The containment rule the FS bridge ops rely on: in-tree relatives resolve
/// against the root, while anything climbing out — `..` segments or an
/// absolute path — is rejected. This is the security boundary for browsing a
/// conversation's workspace from the webview, so pin it directly.
test "contained_path keeps in-tree relatives and rejects escapes" {
  let root = @path.Path("/home/u/OpenSeek/sess")
  assert_eq(
    contained_path(root, "").unwrap().to_string(),
    "/home/u/OpenSeek/sess",
  )
  assert_eq(
    contained_path(root, "src/main.mbt").unwrap().to_string(),
    "/home/u/OpenSeek/sess/src/main.mbt",
  )
  assert_eq(
    contained_path(root, "./a/../b").unwrap().to_string(),
    "/home/u/OpenSeek/sess/b",
  )
  assert_true(contained_path(root, "..") is None)
  assert_true(contained_path(root, "../sibling") is None)
  assert_true(contained_path(root, "../../etc/passwd") is None)
  assert_true(contained_path(root, "/etc/passwd") is None)
  assert_true(contained_path(root, "src/../../escape") is None)
}
