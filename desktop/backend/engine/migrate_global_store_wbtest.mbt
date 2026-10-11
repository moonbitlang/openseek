// Tests for the one-time relocation out of the global store. HOME decides
// where both the default workspace and the global store land, so they take
// `ambient_env_test_lock` alongside every other environment-mutating test in
// this package.

///|
#cfg(not(platform="windows"))
async fn seed_record(record : @pathx.Absolute, content : String) -> Unit {
  @fsx.ensure_dir(record.join("events").to_path())
  @fsx.write_text(record.join("events/1.jsonl").to_path(), content)
}

///|
/// The three kinds of entry a global store can hold, and what becomes of each.
/// Archived records are the ones this got wrong first: they live one level
/// below the archived root, so relocating that root wholesale would treat
/// `sessions` itself as a conversation and skip every archive the destination
/// already had.
#cfg(not(platform="windows"))
async test "the migration relocates live and archived records one by one" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let dir = @fs.tmpdir(prefix="openseek-migrate-global-")
  defer @fs.rmdir(dir, recursive=true)
  let root : @pathx.Path = Path(dir)
  let previous_home = @sys.get_env_var("HOME")
  @sys.set_env_var("HOME", root.join("home").to_string())
  defer restore_home_env(previous_home)
  guard @workspaces.initialize() is Some(workspace) else {
    fail("expected the default workspace to be attached")
  }
  guard @workspaces.global_store_root() is Some(global) else {
    fail("expected a global store root")
  }
  let destination = @workspaces.store_root(workspace)
  seed_record(global.join("sessions/live-1"), "live\n")
  seed_record(
    @session_store.archived_root(global).join("sessions/gone-1"),
    "gone\n",
  )
  // A conversation the destination already knows. Its transcript is the one
  // the sidebar shows; the global copy must not overwrite it.
  seed_record(global.join("sessions/shared"), "global\n")
  seed_record(destination.join("sessions/shared"), "workspace\n")
  // An archive the destination already holds: the reason the archived twin
  // has to be walked record by record.
  seed_record(
    @session_store.archived_root(destination).join("sessions/kept"),
    "kept\n",
  )
  // Permanent deletion's condemned staging area is not a conversation.
  @fsx.ensure_dir(
    @session_store.deleting_root(global).join("condemned").to_path(),
  )
  assert_eq(migrate_global_store(), 2)
  assert_eq(
    @fsx.read_text(destination.join("sessions/live-1/events/1.jsonl").to_path()),
    "live\n",
  )
  assert_eq(
    @fsx.read_text(
      @session_store.archived_root(destination)
      .join("sessions/gone-1/events/1.jsonl")
      .to_path(),
    ),
    "gone\n",
  )
  assert_eq(
    @fsx.read_text(
      @session_store.archived_root(destination)
      .join("sessions/kept/events/1.jsonl")
      .to_path(),
    ),
    "kept\n",
  )
  assert_eq(
    @fsx.read_text(destination.join("sessions/shared/events/1.jsonl").to_path()),
    "workspace\n",
  )
  assert_true(@fsx.is_dir(global.join("sessions/shared").to_path()))
  assert_false(@fsx.exists(global.join("sessions/live-1").to_path()))
  assert_true(
    @fsx.is_dir(
      @session_store.deleting_root(global).join("condemned").to_path(),
    ),
  )
  // Nothing is left of a migration in the destination store.
  assert_false(@fsx.exists(destination.join(StagingDirName).to_path()))
  // A second launch finds nothing to do rather than repeating itself.
  assert_eq(migrate_global_store(), 0)
}

///|
/// The fallback a store on another filesystem takes. It cannot be provoked
/// from a single temporary directory — `rename` succeeds there — so exercise
/// the copy directly: the whole record arrives, the source is gone, and the
/// staging directory it passed through is empty again.
#cfg(not(platform="windows"))
async test "copying a record across filesystems leaves the destination whole" {
  let dir = @fs.tmpdir(prefix="openseek-migrate-copy-")
  defer @fs.rmdir(dir, recursive=true)
  let root : @pathx.Path = Path(dir)
  guard root.to_absolute() is Some(root) else { fail("expected \{root}") }
  let record = root.join("global/sessions/chat")
  seed_record(record, "one\n")
  @fsx.write_text(record.join("meta.json").to_path(), "{}")
  let destination = root.join("workspace/.openseek/sessions/chat")
  let staging = root.join("workspace/.openseek/.migrating/chat")
  @fsx.ensure_dir(destination.join("..").normalize().to_path())
  assert_true(copy_record(record, destination, staging))
  assert_eq(
    @fsx.read_text(destination.join("events/1.jsonl").to_path()),
    "one\n",
  )
  assert_eq(@fsx.read_text(destination.join("meta.json").to_path()), "{}")
  assert_false(@fsx.exists(record.to_path()))
  assert_false(@fsx.exists(staging.to_path()))
}

///|
/// Mark the platform-gated wbtest imports as used: this binding is `_`-prefixed
/// (never warned about) and its body is never evaluated.
let _unused_wbtest_imports : Unit = {
  ignore(@gitx.run)
  ignore(@work_dir.open_target)
}
