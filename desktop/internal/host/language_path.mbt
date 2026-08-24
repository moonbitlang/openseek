// One file location for Desktop language operations. The frontend supplies
// the exact editor root and a path relative to it; the host keeps both the
// lexical spelling used by Viewer resources and the physical spelling used
// to contain symlinks before invoking MoonBit tooling.

///|
priv struct LanguagePath {
  lexical_root : @pathx.Absolute
  physical_root : @pathx.Absolute
  physical_relative : @pathx.Relative
}

///|
/// Confirm that an explicit editor root is the checkout currently owned by
/// `session`. Keep `root` in its frontend resource form for the authorization
/// lookup: on Windows, converting `/C:/work` to `C:\work` first would make the
/// registered-workspace lookup reject the fresh conversation's first request.
async fn LanguagePath::authorized_root(
  session : String,
  root : String,
) -> @pathx.Absolute {
  guard @pathx.Absolute::from_uri_path(root) is Some(lexical_root) else {
    raise PayloadError("root must be absolute")
  }
  let lexical_root = lexical_root.normalize()
  let authorized = match
    @work_dir.resolve_in_workspace(session, "", workspace=root) {
    Some(root) => Some(root)
    None => @work_dir.resolve_in_workspace(session, "")
  }
  guard authorized is Some(authorized) && authorized.normalize() == lexical_root else {
    raise HostError("root is not authorized for this conversation")
  }
  lexical_root
}

///|
/// Resolve one host-authorized editor root and relative file path. The
/// physical containment check also rejects a symlink target leaving it.
async fn LanguagePath::resolve(
  session : String,
  root : String,
  path : String,
) -> LanguagePath {
  let lexical_root = LanguagePath::authorized_root(session, root)
  guard @pathx.Path(path).to_absolute() is None else {
    raise PayloadError("path must be relative to root")
  }
  let relative = @pathx.Relative(path).normalize()
  guard !relative.is_root() else {
    raise PayloadError("path must name a file below root")
  }
  let lexical_file = lexical_root.join(relative).normalize()
  guard lexical_root.contains(lexical_file) else {
    raise HostError("path is outside root")
  }
  let physical_root_text = @fs.realpath(lexical_root.to_string()) catch {
    error if @async.is_being_cancelled() => raise error
    _ => raise HostError("root is unavailable")
  }
  let physical_file_text = @fs.realpath(lexical_file.to_string()) catch {
    error if @async.is_being_cancelled() => raise error
    _ => raise HostError("path is unavailable")
  }
  guard @pathx.Path(physical_root_text).to_absolute() is Some(physical_root) &&
    @pathx.Path(physical_file_text).to_absolute() is Some(physical_file) else {
    raise HostError("root or path is not a host absolute path")
  }
  guard physical_file.relative_to(root=physical_root) is Some(physical_relative) &&
    !physical_relative.is_root() else {
    raise HostError("path is outside root")
  }
  { lexical_root, physical_root, physical_relative }
}

///|
async test "language paths accept frontend resource roots and reject escapes" {
  let root = @fs.tmpdir(prefix="openseek-language-root-")
  let outside = @fs.tmpdir(prefix="openseek-language-outside-")
  defer (@fs.rmdir(outside, recursive=true) catch { _ => () })
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  defer (@work_dir.revoke_host_workspace("language-test") catch { _ => () })
  @fs.mkdir("\{root}/src", recursive=true)
  @fs.write_file(
    "\{root}/src/main.mbt",
    "fn main {}",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    "\{outside}/secret.mbt",
    "fn secret {}",
    create_mode=CreateOrTruncate,
  )
  @fs.symlink(target="\{outside}/secret.mbt", "\{root}/src/link.mbt")
  guard @pathx.Path(root).to_absolute() is Some(root_absolute) &&
    root_absolute.to_uri_path() is Some(root_resource) else {
    fail("test root could not be represented as a frontend resource")
  }
  let unauthorized_rejected = try {
    ignore(LanguagePath::resolve("unbound", root_resource, "src/main.mbt"))
    false
  } catch {
    _ => true
  } noraise {
    rejected => rejected
  }
  @work_dir.authorize_host_workspace("language-test", root)
  let resolved = LanguagePath::resolve(
    "language-test", root_resource, "src/main.mbt",
  )
  let traversal_rejected = try {
    ignore(
      LanguagePath::resolve("language-test", root_resource, "../outside.mbt"),
    )
    false
  } catch {
    _ => true
  } noraise {
    rejected => rejected
  }
  let symlink_rejected = try {
    ignore(
      LanguagePath::resolve("language-test", root_resource, "src/link.mbt"),
    )
    false
  } catch {
    _ => true
  } noraise {
    rejected => rejected
  }
  assert_eq(resolved.physical_relative, Relative("src/main.mbt"))
  assert_true(unauthorized_rejected)
  assert_true(traversal_rejected)
  assert_true(symlink_rejected)
}
