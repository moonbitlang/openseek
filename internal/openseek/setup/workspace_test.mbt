///|
async test "--dir creates a missing final component when its parent exists" {
  @vfs.with_tmpdir(prefix="openseek-dir-parent-", parent => {
    let child = "\{parent}/child"
    let parsed = @testkit.run_matches(
      argv=["--dir", child, "write", "MoonBit"],
      env={ "DEEPSEEK": "test-key" },
    )
    let root = @setup.prepare_workspace_root(parsed)
    assert_true(@fs.exists(child))
    assert_eq(root, @fs.realpath(child))
  })
}

///|
async test "--dir creates a missing final component with trailing separator" {
  @vfs.with_tmpdir(prefix="openseek-dir-trailing-", parent => {
    let child = "\{parent}/child"
    let parsed = @testkit.run_matches(
      argv=["--dir", "\{child}/", "write", "MoonBit"],
      env={ "DEEPSEEK": "test-key" },
    )
    let root = @setup.prepare_workspace_root(parsed)
    assert_true(@fs.exists(child))
    assert_eq(root, @fs.realpath(child))
  })
}

///|
test "--dir trailing separator trim preserves roots" {
  assert_eq(@setup.trim_trailing_path_separators("/"), "/")
  assert_eq(@setup.trim_trailing_path_separators("//"), "//")
  assert_eq(@setup.trim_trailing_path_separators("C:\\"), "C:\\")
  assert_eq(@setup.trim_trailing_path_separators("C:/"), "C:/")
  assert_eq(
    @setup.trim_trailing_path_separators("C:\\workspace\\"),
    "C:\\workspace",
  )
  assert_eq(
    @setup.trim_trailing_path_separators("C:/workspace/"),
    "C:/workspace",
  )
}

///|
async test "--dir rejects missing parents instead of creating recursively" {
  @vfs.with_tmpdir(prefix="openseek-dir-missing-parent-", root => {
    let child = "\{root}/missing/child"
    let parsed = @testkit.run_matches(
      argv=["--dir", child, "write", "MoonBit"],
      env={ "DEEPSEEK": "test-key" },
    )
    let _ = @setup.prepare_workspace_root(parsed) catch {
      error => {
        assert_true(
          "\{error}".contains(
            "parent directory for --dir does not exist: \{root}/missing",
          ),
        )
        return
      }
    }
    fail("missing parent accepted")
  })
}

///|
async test "--dir rejects existing non-directories" {
  @vfs.with_tmpdir(prefix="openseek-dir-file-", root => {
    let path = "\{root}/file"
    @fs.write_file(path, "not a directory", create_mode=CreateOrTruncate)
    let parsed = @testkit.run_matches(
      argv=["--dir", path, "write", "MoonBit"],
      env={ "DEEPSEEK": "test-key" },
    )
    let _ = @setup.prepare_workspace_root(parsed) catch {
      error => {
        assert_true("\{error}".contains("--dir is not a directory: \{path}"))
        return
      }
    }
    fail("file path accepted as --dir")
  })
}

///|
test "session root resolves relative to workspace root" {
  let parsed = @testkit.run_matches(argv=["write", "MoonBit"], env={
    "DEEPSEEK": "test-key",
  })
  assert_eq(
    @setup.session_root(parsed, workspace_root="/tmp/openseek-workspace"),
    "/tmp/openseek-workspace/.openseek",
  )
  let custom = @testkit.run_matches(
    argv=["--session-root", "sessions", "write", "MoonBit"],
    env={ "DEEPSEEK": "test-key" },
  )
  assert_eq(
    @setup.session_root(custom, workspace_root="/tmp/openseek-workspace"),
    "/tmp/openseek-workspace/sessions",
  )
}
