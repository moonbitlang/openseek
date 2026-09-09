///|
fn is_bundled_filename(filename : String) -> Bool {
  filename != "." &&
  filename != ".." &&
  !filename.contains("/") &&
  !filename.contains("\\")
}

///|
fn resolve_filename(
  workspace_root : String,
  filename : String,
  references : String?,
) -> String raise {
  if is_bundled_filename(filename) {
    guard references is Some(root) && !root.trim().is_empty() else {
      fail(
        "bundled filename \{filename} needs OPENSEEK_REFERENCES. For a workspace script, use ./\{filename}; bundled workflows are unavailable in this environment",
      )
    }
    @workspace_path.resolve(root, "workflow/\{filename}")
  } else {
    @workspace_path.resolve(workspace_root, filename)
  }
}

///|
test "bare filenames select bundled workflows without workspace fallback" {
  assert_eq(
    resolve_filename("/project", "check.mbtx", Some("/share")),
    "/share/workflow/check.mbtx",
  )
  assert_eq(
    resolve_filename("/project", "./check.mbtx", Some("/share")),
    "/project/check.mbtx",
  )
  assert_eq(
    resolve_filename("/project", "scripts/check.mbtx", None),
    "/project/scripts/check.mbtx",
  )
  assert_eq(
    resolve_filename("/project", "/other/check.mbtx", Some("/share")),
    "/other/check.mbtx",
  )
  assert_false(is_bundled_filename("."))
  assert_false(is_bundled_filename(".."))
  assert_false(is_bundled_filename(".\\check.mbtx"))
  assert_false(is_bundled_filename("C:\\scripts\\check.mbtx"))
  for references in [None, Some("  ")] {
    try resolve_filename("/project", "check.mbtx", references) catch {
      error => assert_true(error.to_string().contains("./check.mbtx"))
    } noraise {
      _ => fail("missing resources must not select a workspace file")
    }
  }
}
