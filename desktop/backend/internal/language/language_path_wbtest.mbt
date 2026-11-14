///|
/// Whether `LanguagePath::resolve` refuses this root/path pair at all: the
/// test only cares that the escape is rejected, not by which error.
async fn resolve_rejected(
  session : String,
  root : String,
  path : String,
  stdlib_root? : @pathx.Absolute,
) -> Bool {
  try {
    ignore(LanguagePath::resolve(session, root, path, stdlib_root?))
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
  defer @async.protect_from_cancel(() => {
    @work_dir.revoke_host_workspace("language-test") catch {
      _ => ()
    }
  })
  @fs.mkdir("\{root}/src", recursive=true)
  @fs.write_text(
    "\{root}/src/main.mbt",
    "fn main {}",
    create_mode=CreateOrTruncate,
  )
  @fs.write_text(
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
  let core = outside + "/lib/core"
  @fs.mkdir(core, recursive=true)
  @fs.write_text(
    core + "/source.mbt",
    "fn source {}",
    create_mode=CreateOrTruncate,
  )
  @fs.symlink(target=outside + "/secret.mbt", core + "/escape.mbt")
  let stdlib = @pathx.Path(@fs.realpath(core)).resolve()
  let target = stdlib.join("source.mbt").resource_path()
  let external = LanguagePath::resolve(
    "language-test",
    root_resource,
    target,
    stdlib_root=stdlib,
  )
  assert_eq(external.root.physical, resolved.root.physical)
  assert_eq(external.cli_path(), stdlib.join("source.mbt").to_string())
  assert_true(resolve_rejected("language-test", root_resource, target))
  assert_true(
    resolve_rejected("unbound", root_resource, target, stdlib_root=stdlib),
  )
  assert_true(
    resolve_rejected(
      "language-test",
      root_resource,
      root_absolute.join("src/main.mbt").resource_path(),
      stdlib_root=stdlib,
    ),
  )
  assert_true(
    resolve_rejected(
      "language-test",
      root_resource,
      stdlib.join("escape.mbt").resource_path(),
      stdlib_root=stdlib,
    ),
  )
  assert_eq(resolved.file, resolved.root.physical.join("src/main.mbt"))
  assert_eq(resolved.cli_path(), "src/main.mbt")
  assert_true(unauthorized_rejected)
  assert_true(traversal_rejected)
  assert_true(symlink_rejected)
}
