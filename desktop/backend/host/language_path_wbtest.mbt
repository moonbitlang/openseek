///|
/// Whether `LanguagePath::resolve` refuses this root/path pair at all: the
/// test only cares that the escape is rejected, not by which error.
async fn resolve_rejected(
  session : String,
  root : String,
  path : String,
) -> Bool {
  try {
    ignore(LanguagePath::resolve(session, root, path))
    false
  } catch {
    _ => true
  } noraise {
    rejected => rejected
  }
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
  let unauthorized_rejected = resolve_rejected(
    "unbound", root_resource, "src/main.mbt",
  )
  @work_dir.authorize_host_workspace("language-test", root)
  let resolved = LanguagePath::resolve(
    "language-test", root_resource, "src/main.mbt",
  )
  let traversal_rejected = resolve_rejected(
    "language-test", root_resource, "../outside.mbt",
  )
  let symlink_rejected = resolve_rejected(
    "language-test", root_resource, "src/link.mbt",
  )
  assert_eq(resolved.physical_relative, Relative("src/main.mbt"))
  assert_true(unauthorized_rejected)
  assert_true(traversal_rejected)
  assert_true(symlink_rejected)
}
