///|
test "absolute paths open as themselves" {
  guard @pathx.Path("/home/u/repo").to_absolute() is Some(cwd) else {
    fail("expected an absolute working-directory fixture")
  }
  assert_true(
    @work_dir.open_target(Some(cwd), Path("/etc/hosts")) == Path("/etc/hosts"),
  )
  // Normalized, but never re-rooted into the working directory.
  assert_true(
    @work_dir.open_target(Some(cwd), Path("/a/b/../c.mbt")) == Path("/a/c.mbt"),
  )
}

///|
test "relative paths are taken against the working directory" {
  guard @pathx.Path("/home/u/repo").to_absolute() is Some(cwd) else {
    fail("expected an absolute working-directory fixture")
  }
  assert_true(
    @work_dir.open_target(Some(cwd), Path("core/builtin/array.mbt")) ==
    Path("/home/u/repo/core/builtin/array.mbt"),
  )
  assert_true(
    @work_dir.open_target(Some(cwd), Path("./main.mbt")) ==
    Path("/home/u/repo/main.mbt"),
  )
}

///|
test "a relative path with no working directory is left untouched" {
  assert_true(
    @work_dir.open_target(None, Path("core/builtin/array.mbt")) ==
    Path("core/builtin/array.mbt"),
  )
  assert_true(@work_dir.open_target(None, Path("")) == Path(""))
}

///|
async test "host-authorized workspaces are exact and session-scoped" {
  let root = @fs.tmpdir(prefix="openseek-authorized-workspace-")
  let session = "codex-authorized-workspace-test"
  @work_dir.revoke_host_workspace(session)
  @work_dir.authorize_host_workspace(session, root)
  guard @pathx.Path(root).to_absolute().bind(path => path.to_uri_path())
    is Some(resource) else {
    fail("expected a resource path")
  }
  let resource = match resource {
    ['/', drive, ':', '/', .. rest] =>
      "/" + drive.to_ascii_lowercase().to_string() + ":/" + rest.to_owned()
    _ => resource
  }
  let exact = @work_dir.resolve_host_workspace_authorization(session, resource)
  let authorized = @work_dir.resolve_in_workspace(
    session,
    "src/main.mbt",
    workspace=resource,
  )
  let other_session = @work_dir.resolve_in_workspace(
    "codex-other-workspace-test",
    "src/main.mbt",
    workspace=resource,
  )
  let escape = @work_dir.resolve_in_workspace(
    session,
    "../outside",
    workspace=resource,
  )
  @work_dir.revoke_host_workspace(session)
  let revoked = @work_dir.resolve_in_workspace(session, "", workspace=resource)
  let exact_revoked = @work_dir.resolve_host_workspace_authorization(
    session, resource,
  )
  @fs.rmdir(root, recursive=true) catch {
    _ => ()
  }
  assert_eq(
    authorized,
    @pathx.Path(root)
    .join(Relative("src/main.mbt"))
    .to_absolute()
    .map(path => path.normalize()),
  )
  assert_true(other_session is None)
  assert_true(exact is Some(_))
  assert_true(escape is None)
  assert_true(revoked is None)
  assert_true(exact_revoked is None)
}
