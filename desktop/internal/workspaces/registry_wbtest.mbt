// Tests for the registry's one-time setup. They redirect HOME, which decides
// both where the default workspace and the registry file land, so they take
// one lock rather than racing each other's environment.

///|
#cfg(not(platform="windows"))
let registry_env_test_lock : @async.Mutex = Mutex()

///|
#cfg(not(platform="windows"))
fn restore_env(name : String, previous : String?) -> Unit {
  if previous is Some(value) {
    @sys.set_env_var(name, value)
  } else {
    @sys.unset_env_var(name)
  }
}

///|
/// The whole point of recording `initialized` in the registry: attaching the
/// default workspace is a one-time courtesy, not a policy the app re-applies.
/// A user who detaches it has decided, and the next launch must respect that.
#cfg(not(platform="windows"))
async test "the default workspace is attached once and never re-attached" {
  registry_env_test_lock.acquire()
  defer registry_env_test_lock.release()
  let dir = @fs.tmpdir(prefix="openseek-default-workspace-")
  defer @fs.rmdir(dir, recursive=true)
  let root : @pathx.Path = Path(dir)
  let previous_home = @sys.get_env_var("HOME")
  @sys.set_env_var("HOME", root.join("home").to_string())
  defer restore_env("HOME", previous_home)
  // A fresh install: no registry at all. Setup creates the directory and
  // attaches it, so the first client already has somewhere to work.
  guard initialize() is Some(attached) else {
    fail("expected the default workspace to be attached")
  }
  assert_true(@fsx.is_dir(root.join("home/OpenSeek")))
  assert_eq(attached.to_path().basename(), "OpenSeek")
  assert_eq(registered(), [attached])
  // A second launch with the registry already initialized changes nothing,
  // even though the default workspace is still attached.
  assert_true(initialize() is None)
  assert_eq(registered(), [attached])
  // The user detaches it. `initialized` is rewritten untouched by the
  // removal, so setup still declines to bring it back.
  ignore(remove(attached.0, fn(_) {  }))
  assert_eq(registered(), [])
  assert_true(initialize() is None)
  assert_eq(registered(), [])
}

///|
/// A registry written before this marker existed carries no `initialized`
/// field. Reading it as uninitialized is what lets an existing install
/// receive the default workspace on its next launch, alongside whatever the
/// user had already attached.
#cfg(not(platform="windows"))
async test "a registry without the marker still receives the default workspace" {
  registry_env_test_lock.acquire()
  defer registry_env_test_lock.release()
  let dir = @fs.tmpdir(prefix="openseek-legacy-registry-")
  defer @fs.rmdir(dir, recursive=true)
  let root : @pathx.Path = Path(dir)
  let previous_home = @sys.get_env_var("HOME")
  @sys.set_env_var("HOME", root.join("home").to_string())
  defer restore_env("HOME", previous_home)
  let global_root = root.join("home/.openseek")
  let existing = root.join("project")
  @fsx.ensure_dir(existing)
  @fsx.ensure_dir(global_root)
  @fs.write_file(
    global_root.join("workspaces.json").to_string(),
    ({ "workspaces": [existing.to_string()] } : Json).stringify(),
    create_mode=CreateOrTruncate,
  )
  guard initialize() is Some(attached) else {
    fail("expected the default workspace to be attached")
  }
  // The already-attached project keeps its registration order; the default
  // workspace joins it rather than replacing it.
  let registered = registered()
  assert_eq(registered.length(), 2)
  assert_eq(registered[1], attached)
  assert_true(initialize() is None)
}

///|
/// Mark the platform-gated wbtest alias as used: this binding is `_`-prefixed
/// (never warned about) and its body is never evaluated.
let _unused_wbtest_imports : Unit = ignore(@sys.get_env_var)
