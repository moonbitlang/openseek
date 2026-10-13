///|
test "a workspace's session store is the engine's in-project default" {
  assert_eq(
    @workspaces.store_root(@pathx.Path("/home/u/proj").resolve()).to_string(),
    "/home/u/proj/.openseek",
  )
}

///|
test "workspace paths expand ~ against the home directory" {
  guard @home.dir() is Some(home) else {
    // No home in this environment; nothing to expand against.
    return
  }
  assert_eq(@workspaces.expanded_path("~").0, home.to_string())
  assert_eq(
    @workspaces.expanded_path("~/proj").0,
    home.join("proj").normalize().to_string(),
  )
  // Absolute paths pass through (normalized), and surrounding blanks drop.
  assert_eq(@workspaces.expanded_path("  /srv/code//app  ").0, "/srv/code/app")
}

///|
test "blank workspace paths are refused" {
  let _ = @workspaces.expanded_path("   ") catch {
    WorkspaceError(message) => {
      assert_true(message.contains("must not be empty"))
      return
    }
  }
  fail("a blank workspace path was accepted")
}

// Tests for the registry's one-time setup. They redirect HOME, which decides
// both where the default workspace and the registry file land, so they take
// one lock rather than racing each other's environment.

///|
/// Mark the platform-gated test alias as used: this binding is `_`-prefixed
/// (never warned about) and its body is never evaluated.
let _unused_test_imports : Unit = ignore(@sys.get_env_var)

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
  guard @workspaces.initialize() is Some(attached) else {
    fail("expected the default workspace to be attached")
  }
  assert_true(@fsx.is_dir(root.join("home/OpenSeek")))
  assert_eq(attached.to_path().basename(), "OpenSeek")
  assert_eq(@workspaces.registered(), [attached])
  // A second launch with the registry already initialized changes nothing,
  // even though the default workspace is still attached.
  assert_true(@workspaces.initialize() is None)
  assert_eq(@workspaces.registered(), [attached])
  // The user detaches it. `initialized` is rewritten untouched by the
  // removal, so setup still declines to bring it back.
  ignore(@workspaces.remove(attached.0, _ => ()))
  assert_eq(@workspaces.registered(), [])
  assert_true(@workspaces.initialize() is None)
  assert_eq(@workspaces.registered(), [])
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
  guard @workspaces.initialize() is Some(attached) else {
    fail("expected the default workspace to be attached")
  }
  // The already-attached project keeps its registration order; the default
  // workspace joins it rather than replacing it.
  let registered = @workspaces.registered()
  assert_eq(registered.length(), 2)
  assert_eq(registered[1], attached)
  assert_true(@workspaces.initialize() is None)
}

///|
/// The process-wide mutex orders one host's own requests; another host
/// process reaches the same file. A mutation must wait for that host's
/// change and read the registry only afterwards, or its write-back would
/// erase the entry the other host just committed. The file lock belongs to
/// the open file description, so holding it here stands in for that host.
#cfg(not(platform="windows"))
async test "an attach waits for another host's change and keeps its entry" {
  registry_env_test_lock.acquire()
  defer registry_env_test_lock.release()
  let dir = @fs.tmpdir(prefix="openseek-registry-two-hosts-")
  defer @fs.rmdir(dir, recursive=true)
  let root : @pathx.Path = Path(dir)
  let previous_home = @sys.get_env_var("HOME")
  @sys.set_env_var("HOME", root.join("home").to_string())
  defer restore_env("HOME", previous_home)
  let registry = root.join("home/.openseek/workspaces.json")
  let theirs = root.join("theirs")
  let ours = root.join("ours")
  @fsx.ensure_dir(theirs)
  @fsx.ensure_dir(ours)
  guard ours.to_absolute() is Some(ours) else { fail("tmpdir is not absolute") }
  let held = @fsx.FileLock::acquire(registry)
  @async.with_task_group(group => {
    group.spawn_bg(() => @workspaces.register_task_directory(ours))
    // Long enough for the attach to reach the lock and block on it.
    @async.sleep(100)
    @fsx.write_text_atomic(
      registry,
      ({ "workspaces": [theirs.to_string()], "initialized": true } : Json).stringify(),
    )
    held.release()
  })
  assert_eq(@workspaces.registered().map(path => path.to_path().basename()), [
    "theirs", "ours",
  ])
}
