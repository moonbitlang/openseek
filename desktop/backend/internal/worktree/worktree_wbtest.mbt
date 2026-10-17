// Tests. The lifecycle tests exercise the real git binary (like the CLI's
// subtask lifecycle tests); the environment-dependent ones serialize on
// `worktree_env_test_lock` because they redirect HOME.

///|
/// A fixture root in the tmpdir's physical spelling. The workspace registry
/// canonicalizes what it stores, so a fixture built from the symlinked
/// spelling (`/tmp` on macOS) would compare unequal to every path the
/// registry hands back.
async fn worktree_test_root(prefix : String) -> @pathx.Absolute {
  @pathx.Path(@fs.realpath(@fs.tmpdir(prefix~))).resolve()
}

///|
/// Tests that redirect HOME or USERPROFILE share the process environment,
/// so they run one at a time.
let worktree_env_test_lock : @async.Mutex = Mutex()

///|
#cfg(not(platform="windows"))
fn restore_home_env(previous : String?) -> Unit {
  if previous is Some(value) {
    @sys.set_env_var("HOME", value)
  } else {
    @sys.unset_env_var("HOME")
  }
}

///|
/// A host with no engine behind it: `live` names the conversations the pump
/// would report a slot for, and every drained session is appended to
/// `drained` instead of closing a process.
#cfg(not(platform="windows"))
fn test_host(
  live~ : Array[String] = [],
  drained~ : Array[String] = [],
) -> WorktreeHost {
  {
    lifecycle_lock: Mutex(),
    session_is_live: session => live.contains(session),
    session_is_moving: _ => false,
    drain_sessions: sessions => drained.append(sessions),
  }
}

///|
test "worktree names are one branch-safe path component" {
  assert_true(valid_worktree_name("fix-auth"))
  assert_true(valid_worktree_name("a.b_c-d"))
  assert_true(valid_worktree_name("A0"))
  assert_true(valid_worktree_name("x".repeat(64)))
  assert_false(valid_worktree_name(""))
  assert_false(valid_worktree_name("."))
  assert_false(valid_worktree_name(".."))
  assert_false(valid_worktree_name("-x"))
  assert_false(valid_worktree_name(".hidden"))
  assert_false(valid_worktree_name("a/b"))
  assert_false(valid_worktree_name("a\\b"))
  assert_false(valid_worktree_name("a b"))
  assert_false(valid_worktree_name("名字"))
  assert_false(valid_worktree_name("x".repeat(65)))
}

///|
async test "worktree registry decode drops malformed entries" {
  let root = worktree_test_root("openseek-worktree-decode-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  @fsx.ensure_dir(@workspaces.store_root(root).to_path())
  @fsx.write_text(worktrees_file(root).to_path(), "{ not json")
  assert_eq(read_worktrees_unlocked(root).length(), 0)
  let registry : Json = {
    "worktrees": [
      { "name": "ok", "branch": "openseek/ok", "base": "abc", "session": "s1" },
      {
        "name": "codex",
        "branch": "openseek/codex",
        "base": "def",
        "codex_thread": "thread-1",
      },
      {
        "name": "ambiguous",
        "branch": "openseek/ambiguous",
        "base": "ghi",
        "session": "s2",
        "codex_thread": "thread-2",
      },
      {
        "name": "blank",
        "branch": "openseek/blank",
        "base": "y",
        "session": "",
      },
      { "name": "bad/slash", "branch": "x", "base": "y" },
      { "name": "nobranch", "base": "y" },
      { "name": "ok", "branch": "dup", "base": "y" },
      "not-an-object",
      {
        "name": "detached",
        "base": "def",
        "recovery_ref": "\{WorktreeRecoveryPrefix}detached-\{"a".repeat(32)}",
      },
      {
        "name": "both",
        "base": "def",
        "branch": "openseek/both",
        "recovery_ref": "\{WorktreeRecoveryPrefix}both-\{"b".repeat(32)}",
      },
      { "name": "wrong", "base": "def", "recovery_ref": "refs/heads/main" },
      { "name": "null", "base": "def", "recovery_ref": null },
      { "name": "empty", "base": "def", "recovery_ref": "" },
    ],
  }
  @fsx.write_text(worktrees_file(root).to_path(), registry.stringify())
  let entries = read_worktrees_unlocked(root)
  assert_eq(entries.length(), 4)
  assert_eq(entries[0].name, "ok")
  assert_true(entries[0].checkout is Branch("openseek/ok"))
  assert_eq(entries[0].base, "abc")
  assert_eq(entries[0].sessions, ["s1"])
  assert_eq(entries[0].codex_thread, None)
  assert_eq(entries[1].name, "codex")
  assert_eq(entries[1].sessions, [])
  assert_eq(entries[1].codex_thread, Some("thread-1"))
  // A blank session self-heals to unbound rather than a phantom id.
  assert_eq(entries[2].name, "blank")
  assert_eq(entries[2].sessions, [])
  assert_true(entries[2].codex_thread is None)
  assert_true(
    entries[3].checkout is Detached(recovery_ref) &&
    recovery_ref == "\{WorktreeRecoveryPrefix}detached-\{"a".repeat(32)}",
  )
  assert_eq(entries[3].checkout.branch(), None)
}

///|
#cfg(not(platform="windows"))
async test "failed worktree registry staging preserves every live row" {
  let root = worktree_test_root("openseek-worktree-atomic-write-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  let retained : WorktreeEntry = {
    name: "retained",
    checkout: Branch("openseek/retained"),
    base: "abc",
    sessions: ["other-session"],
    codex_thread: None,
  }
  write_worktrees(root, [retained])
  // A store that refuses new files makes the staging write fail before
  // publication, modeling an interrupted or rejected one. A leftover at a
  // fixed temporary name no longer does: the save names its file randomly,
  // so that one crash cannot block every later save.
  let store = @workspaces.store_root(root).to_string()
  @fs.chmod(store, 0o555)
  let failed = try {
    write_worktrees(root, [])
    false
  } catch {
    _ => true
  }
  @fs.chmod(store, 0o755)
  assert_true(failed)
  guard read_worktrees_unlocked(root) is [after] else {
    fail("the previous worktree registry must remain readable")
  }
  assert_eq(after.name, retained.name)
  assert_true(after.checkout is Branch("openseek/retained"))
  assert_eq(after.base, retained.base)
  assert_eq(after.sessions, retained.sessions)
}

///|
#cfg(not(platform="windows"))
async fn prepare_git_repo(dir : @pathx.Absolute) -> Unit {
  @fsx.ensure_dir(dir.to_path())
  ignore(@gitx.run(dir, ["init", "-q"]))
  ignore(
    @gitx.run(dir, [
      "-c", "user.email=test@example.com", "-c", "user.name=test", "-c", "commit.gpgsign=false",
      "commit", "--allow-empty", "-q", "-m", "init",
    ]),
  )
}

///|
#cfg(not(platform="windows"))
async test "attach refuses a linked worktree, keeps main and non-git attachable" {
  worktree_env_test_lock.acquire()
  defer worktree_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  let root = worktree_test_root("openseek-worktree-attach-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  @sys.set_env_var("HOME", root.join("global").to_string())
  defer restore_home_env(previous)
  let repo = root.join("repo")
  prepare_git_repo(repo)
  ignore(
    @gitx.run(repo, ["worktree", "add", "-q", root.join("linked").to_string()]),
  )
  let detail = try {
    ignore(@workspaces.add(root.join("linked").to_string(), _ => ()))
    "no error"
  } catch {
    WorktreeError(detail) => detail
    error => "\{error}"
  }
  assert_true(detail.contains("linked git worktree"))
  // The main checkout, one of its subdirectories, and a plain directory all
  // stay attachable — in particular the guard must not misfire on paths whose
  // `.git` is elsewhere for other reasons.
  assert_true(@workspaces.add(repo.to_string(), _ => ()).contains(repo))
  let sub = repo.join("sub")
  @fsx.ensure_dir(sub.to_path())
  assert_true(@workspaces.add(sub.to_string(), _ => ()).contains(sub))
  let plain = root.join("plain")
  @fsx.ensure_dir(plain.to_path())
  assert_true(@workspaces.add(plain.to_string(), _ => ()).contains(plain))
}

///|
#cfg(not(platform="windows"))
async test "worktree create provisions detached checkout, recovery ref, registry, exclusion" {
  worktree_env_test_lock.acquire()
  defer worktree_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  let root = worktree_test_root("openseek-worktree-create-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  @sys.set_env_var("HOME", root.join("global").to_string())
  defer restore_home_env(previous)
  let repo = root.join("repo")
  prepare_git_repo(repo)
  ignore(@workspaces.add(repo.to_string(), _ => ()))
  let host = test_host()
  let committed : Ref[Int32] = Ref(-1)
  let reply = create(
    host,
    repo.to_string(),
    WorktreeOwner::openseek("s-fix-auth"),
    infos => committed.val = infos.length(),
    name="fix-auth",
  )
  assert_eq(committed.val, 1)
  assert_eq(reply.name, "fix-auth")
  guard reply.worktrees is [info] else { fail("expected one worktree") }
  assert_eq(info.name, "fix-auth")
  assert_eq(info.branch, None)
  guard read_worktrees_unlocked(repo) is [entry] else {
    fail("missing registry row")
  }
  guard entry.checkout is Detached(recovery_ref) else {
    fail("expected detached checkout")
  }
  assert_true(valid_recovery_ref(info.name, recovery_ref))
  assert_eq(
    @gitx.run(repo, [
      "for-each-ref", "--format=%(refname)", "refs/heads/openseek/",
    ]),
    "",
  )
  assert_eq(info.base, @gitx.run(repo, ["rev-parse", "HEAD"]))
  // Creation IS the binding: the entry carries its conversation from birth.
  assert_eq(info.sessions, ["s-fix-auth"])
  assert_eq(tree_base(repo, "s-fix-auth"), Some(info.base))
  assert_eq(tree_base(repo, "workspace-root"), None)
  assert_eq(info.path, repo.join(".worktrees/fix-auth").to_string())
  assert_true(info.present)
  assert_true(@fsx.is_dir(repo.join(".worktrees/fix-auth").to_path()))
  assert_true(
    @gitx.probe(repo, ["show-ref", "--verify", "--quiet", recovery_ref])
    is Some(_),
  )
  // The new checkout sits detached at the recorded base.
  assert_eq(
    @gitx.run(repo.join(".worktrees/fix-auth"), [
      "rev-parse", "--abbrev-ref", "HEAD",
    ]),
    "HEAD",
  )
  let exclude = @fsx.read_text(repo.join(".git/info/exclude").to_path())
  assert_true(exclude.contains(".worktrees/"))
  assert_true(exclude.contains(".openseek/"))
  guard list(repo.to_string()).worktrees is [listed] else {
    fail("expected one listed worktree")
  }
  assert_eq(listed.name, "fix-auth")
  assert_true(listed.present)
}

///|
#cfg(not(platform="windows"))
async test "explicit registry removal can prune a vanished worktree" {
  worktree_env_test_lock.acquire()
  defer worktree_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  let root = worktree_test_root("openseek-worktree-release-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  @sys.set_env_var("HOME", root.join("global").to_string())
  defer restore_home_env(previous)
  let repo = root.join("repo")
  prepare_git_repo(repo)
  ignore(@workspaces.add(repo.to_string(), _ => ()))
  let host = test_host()
  ignore(
    create(
      host,
      repo.to_string(),
      WorktreeOwner::openseek("s-release"),
      _ => (),
      name="wt",
    ),
  )
  @fs.rmdir(repo.join(".worktrees/wt").to_string(), recursive=true)
  // The low-level protocol operation remains available for orphan cleanup.
  // The bundled UI does not expose it for a conversation; Archive retains the
  // row so a later Unarchive still requires explicit Repair.
  let reply = remove(host, repo.to_string(), "wt", false, _ => ())
  assert_eq(reply.worktrees.length(), 0)
  // Unbound, the conversation runs in the workspace again — no refusal.
  assert_eq(run_dir(repo, "s-release").to_string(), repo.to_string())
}

///|
#cfg(not(platform="windows"))
async test "worktree names are host-generated and skip surviving references" {
  worktree_env_test_lock.acquire()
  defer worktree_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  let root = worktree_test_root("openseek-worktree-autoname-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  @sys.set_env_var("HOME", root.join("global").to_string())
  defer restore_home_env(previous)
  let repo = root.join("repo")
  prepare_git_repo(repo)
  ignore(@workspaces.add(repo.to_string(), _ => ()))
  let host = test_host()
  let first = create(host, repo.to_string(), WorktreeOwner::openseek("s-1"), _ => {
    ()
  })
  assert_eq(first.name, "wt-1")
  // The session is the idempotency key: a replay (a retry after a lost
  // reply) gets the existing binding back, never a second checkout.
  let replay = create(host, repo.to_string(), WorktreeOwner::openseek("s-1"), _ => {
    ()
  })
  assert_eq(replay.name, "wt-1")
  assert_eq(replay.worktrees.length(), 1)
  let second = create(host, repo.to_string(), WorktreeOwner::openseek("s-2"), _ => {
    ()
  })
  assert_eq(second.name, "wt-2")
  // Removal keeps the recovery ref, so a fresh name never resurrects wt-1.
  ignore(remove(host, repo.to_string(), "wt-1", false, _ => ()))
  let third = create(host, repo.to_string(), WorktreeOwner::openseek("s-3"), _ => {
    ()
  })
  assert_eq(third.name, "wt-3")
  guard list(repo.to_string()).worktrees is [a, b] else {
    fail("expected two registered worktrees")
  }
  assert_eq(a.name, "wt-2")
  assert_eq(b.name, "wt-3")
  // A bare `openseek/wt-4` left behind by a build that minted unsalted
  // branches is history too: the counter moves past it instead of pairing
  // the directory with a lookalike salted branch.
  ignore(@gitx.run(repo, ["branch", "openseek/wt-4"]))
  // Codex uses the same registry, name allocator, and idempotency contract,
  // but its owner remains in a distinct field from OpenSeek sessions.
  let codex = create(host, repo.to_string(), WorktreeOwner::codex("thread-1"), _ => {
    ()
  })
  assert_eq(codex.name, "wt-5")
  let codex_replay = create(
    host,
    repo.to_string(),
    WorktreeOwner::codex("thread-1"),
    _ => (),
  )
  assert_eq(codex_replay.name, "wt-5")
  guard codex_replay.worktrees.iter().find_first(info => info.name == "wt-5")
    is Some(codex_info) else {
    fail("expected Codex-owned worktree row")
  }
  assert_eq(codex_info.sessions, [])
  assert_eq(codex_info.codex_thread, Some("thread-1"))
}

///|
#cfg(not(platform="windows"))
async test "worktree remove prunes an externally deleted checkout" {
  worktree_env_test_lock.acquire()
  defer worktree_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  let root = worktree_test_root("openseek-worktree-prune-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  @sys.set_env_var("HOME", root.join("global").to_string())
  defer restore_home_env(previous)
  let repo = root.join("repo")
  prepare_git_repo(repo)
  ignore(@workspaces.add(repo.to_string(), _ => ()))
  let host = test_host()
  ignore(
    create(
      host,
      repo.to_string(),
      WorktreeOwner::openseek("s-gone"),
      _ => (),
      name="gone",
    ),
  )
  @fs.rmdir(repo.join(".worktrees/gone").to_string(), recursive=true)
  guard list(repo.to_string()).worktrees is [listed] else {
    fail("expected the deleted worktree to stay listed")
  }
  assert_false(listed.present)
  ignore(remove(host, repo.to_string(), "gone", false, _ => ()))
  assert_eq(list(repo.to_string()).worktrees.length(), 0)
  assert_false(
    @gitx.run(repo, ["worktree", "list", "--porcelain"]).contains(
      ".worktrees/gone",
    ),
  )
}
