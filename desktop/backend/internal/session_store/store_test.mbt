///|
test "session ids are accepted as store record names" {
  assert_true(@session_store.safe_session_id("desktop-20260611-093045-123"))
  assert_true(@session_store.safe_session_id("my-cli-session"))
  assert_true(@session_store.safe_session_id("a.b"))
}

///|
test "session ids that could escape their root are refused" {
  assert_false(@session_store.safe_session_id(""))
  assert_false(@session_store.safe_session_id("."))
  assert_false(@session_store.safe_session_id(".."))
  assert_false(@session_store.safe_session_id("a/b"))
  assert_false(@session_store.safe_session_id("a\\b"))
  assert_false(@session_store.safe_session_id("../escape"))
}

// Tests for the lookups that search the registered stores. They redirect
// HOME, which decides where the workspace registry lives, so they take one
// lock rather than racing each other's environment.

///|
#cfg(not(platform="windows"))
let store_env_test_lock : @async.Mutex = Mutex()

///|
/// Mark the platform-gated test alias as used: this binding is `_`-prefixed
/// (never warned about) and its body is never evaluated.
let _unused_test_imports : Unit = ignore(@sys.get_env_var)

///|
/// Whether a lookup refused with the store's own error instead of answering.
#cfg(not(platform="windows"))
async fn lookup_refused(lookup : async () -> Unit) -> Bool {
  lookup() catch {
    @session_store.StoreError(message) =>
      return message.has_prefix("could not inspect the session record at ")
    error => raise error
  }
  false
}

///|
/// Which workspace owns a session is read off the disk, and "none of them"
/// is an answer callers act on — a run is refused, a worktree is skipped, an
/// id is treated as free. Only a record that is not there may give it. A
/// store that is a regular file is as absent as a missing one (ENOTDIR); a
/// record name longer than a filesystem allows (ENAMETOOLONG) and a record
/// that is a symlink to itself (ELOOP) could not be inspected at all, and
/// neither needs permission bits to reproduce.
#cfg(not(platform="windows"))
async test "a session lookup raises when a store cannot be inspected" {
  store_env_test_lock.acquire()
  defer store_env_test_lock.release()
  let dir = @fs.tmpdir(prefix="openseek-session-lookup-")
  defer @fs.rmdir(dir, recursive=true)
  let root : @pathx.Path = Path(dir)
  let previous_home = @sys.get_env_var("HOME")
  @sys.set_env_var("HOME", root.join("home").to_string())
  defer (if previous_home is Some(value) {
    @sys.set_env_var("HOME", value)
  } else {
    @sys.unset_env_var("HOME")
  })
  // The first store is a file where a directory belongs; the second holds
  // the record. The lookup has to pass the first to find it.
  let hollow = root.join("hollow")
  @fsx.ensure_dir(hollow)
  @fsx.write_text(hollow.join(".openseek"), "")
  let project = root.join("project")
  let sessions = project.join(".openseek/sessions")
  @fsx.ensure_dir(sessions.join("chat"))
  @fsx.ensure_dir(project.join(".openseek/archived/sessions/shelved"))
  ignore(@workspaces.add(hollow.to_string(), _ => ()))
  guard @workspaces.add(project.to_string(), _ => ()) is [_, owner] else {
    fail("expected both workspaces to be registered")
  }
  let store = @workspaces.store_root(owner)
  assert_eq(@session_store.workspace_of("chat"), Some(owner))
  assert_eq(@session_store.live_root_of("chat"), Some(store))
  assert_eq(@session_store.archived_root_of("shelved"), Some(store))
  assert_eq(@session_store.workspace_of("absent"), None)
  assert_eq(@session_store.live_root_of("absent"), None)
  assert_eq(@session_store.archived_root_of("absent"), None)
  let overlong = "n".repeat(300)
  assert_true(
    lookup_refused(() => ignore(@session_store.workspace_of(overlong))),
  )
  assert_true(lookup_refused(() => ignore(@session_store.root_of(overlong))))
  assert_true(
    lookup_refused(() => ignore(@session_store.live_root_of(overlong))),
  )
  assert_true(
    lookup_refused(() => ignore(@session_store.archived_root_of(overlong))),
  )
  let cycle = sessions.join("cycle")
  @fs.symlink(cycle.to_string(), target=cycle.to_string())
  assert_true(
    lookup_refused(() => ignore(@session_store.workspace_of("cycle"))),
  )
  assert_true(
    lookup_refused(() => ignore(@session_store.live_root_of("cycle"))),
  )
}
