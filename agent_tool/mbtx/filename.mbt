///|
fn is_bundled_filename(filename : String) -> Bool {
  filename.has_prefix("@builtin/")
}

///|
fn resolve_filename(
  workspace_root : String,
  filename : String,
  references : String?,
) -> String raise {
  if filename.has_prefix("@") {
    guard is_bundled_filename(filename) else {
      fail(
        "unknown script namespace in \{filename}. Only @builtin/ is supported. Use ./\{filename} for a literal workspace path",
      )
    }
    let name = filename[9:].to_owned()
    guard !name.is_empty() &&
      !name.contains("\\") &&
      name
      .split("/")
      .all(part => !part.is_empty() && part != "." && part != "..") else {
      fail(
        "invalid bundled script path \{filename}; use @builtin/check.mbtx or a relative path within that namespace, without . or .. components",
      )
    }
    guard references is Some(root) && !root.trim().is_empty() else {
      fail(
        "bundled filename \{filename} needs OPENSEEK_REFERENCES; bundled workflows are unavailable in this environment. Use a workspace filename or inline source instead",
      )
    }
    @workspace_path.resolve(root, "workflow/\{name}")
  } else {
    @workspace_path.resolve(workspace_root, filename)
  }
}

///|
test "only the builtin namespace selects bundled workflows" {
  assert_eq(
    resolve_filename("/project", "@builtin/check.mbtx", Some("/share")),
    "/share/workflow/check.mbtx",
  )
  assert_eq(
    resolve_filename("/project", "check.mbtx", Some("/share")),
    "/project/check.mbtx",
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
    try resolve_filename("/project", "@builtin/check.mbtx", references) catch {
      error => assert_true(error.to_string().contains("OPENSEEK_REFERENCES"))
    } noraise {
      _ => fail("missing resources must not select a workspace file")
    }
  }
  for
    name in [
      "@skill/check.mbtx", "@builtin/", "@builtin/../check.mbtx", "@builtin//check.mbtx",
      "@builtin/a\\check.mbtx",
    ] {
    try resolve_filename("/project", name, Some("/share")) catch {
      _ => ()
    } noraise {
      _ => fail("invalid namespace path accepted: \{name}")
    }
  }
  assert_eq(
    resolve_filename("/project", "./@builtin/check.mbtx", None),
    "/project/@builtin/check.mbtx",
  )
}
