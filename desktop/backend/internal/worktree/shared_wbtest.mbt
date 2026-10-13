// A worktree several conversations are bound to. Private access is needed to
// write a multi-member registry row directly: these rules hold for any row
// the registry can carry, however its members came to be bound.

///|
/// Rebind the row `name` to exactly `sessions`.
#cfg(not(platform="windows"))
async fn bind_shared_fixture(
  repo : @pathx.Absolute,
  name : String,
  sessions : Array[String],
) -> Unit {
  let entries = read_worktrees_unlocked(repo).map(entry => {
    if entry.name == name {
      { ..entry, sessions, }
    } else {
      entry
    }
  })
  write_worktrees(repo, entries)
}

///|
/// The live durable record a started conversation leaves in the project's
/// store, which is what the registry reads as "still working here".
#cfg(not(platform="windows"))
fn shared_fixture_record(
  repo : @pathx.Absolute,
  session : String,
) -> @pathx.Absolute {
  @workspaces.store_root(repo).join("sessions").join(session)
}

///|
#cfg(not(platform="windows"))
async test "a shared checkout goes only with the last conversation holding it" {
  with_recovery_fixture((repo, host) => {
    let first = WorktreeOwner::openseek("first")
    let second = WorktreeOwner::openseek("second")
    let created = create(host, resource_path(repo), first, _ => ())
    let checkout = worktree_dir(repo, created.name)
    bind_shared_fixture(repo, created.name, ["first", "second"])
    @fsx.ensure_dir(shared_fixture_record(repo, "first").to_path())
    @fsx.ensure_dir(shared_fixture_record(repo, "second").to_path())
    @fsx.write_text(checkout.join("draft.txt").to_path(), "uncommitted")
    // The other conversation still works here, so nothing is at risk: no
    // dirty refusal, no deletion, and no broadcast of an unchanged registry.
    let published : Array[WorktreeInfo] = []
    assert_eq(
      first.archive_checkout(host, false, on_committed=(_, infos) => {
        published.append(infos)
      }),
      None,
    )
    assert_true(@fsx.is_dir(checkout.to_path()))
    assert_eq(published.length(), 0)
    assert_eq(
      tree_dir(repo, "first").map(dir => dir.to_string()),
      Some(checkout.to_string()),
    )
    // The archived conversation's record has left the live store, which
    // makes the remaining one the last holder: its archive is the one that
    // must confirm discarding the uncommitted work.
    @fs.rmdir(shared_fixture_record(repo, "first").to_string(), recursive=true)
    guard second.archive_checkout(host, false) is Some(refusal) else {
      fail("the last holder must confirm discarding uncommitted changes")
    }
    assert_eq(refusal.worktree, created.name)
    assert_true(@fsx.is_dir(checkout.to_path()))
    assert_eq(second.archive_checkout(host, true), None)
    assert_false(@fsx.exists(checkout.to_path()))
    // Both placements survive, so either conversation can rebuild it later.
    guard read_worktrees_unlocked(repo) is [row] else {
      fail("the shared placement must survive archive")
    }
    assert_eq(row.sessions, ["first", "second"])
  })
}

///|
#cfg(not(platform="windows"))
async test "a bound conversation holds a checkout only once it starts" {
  with_recovery_fixture((repo, host) => {
    let first = WorktreeOwner::openseek("first")
    let created = create(host, resource_path(repo), first, _ => ())
    let checkout = worktree_dir(repo, created.name)
    bind_shared_fixture(repo, created.name, ["first", "unstarted"])
    @fsx.ensure_dir(shared_fixture_record(repo, "first").to_path())
    // A slot in the running pump is a start in flight: its record is about
    // to exist, and its engine's cwd is this directory.
    let starting = test_host(live=["unstarted"])
    assert_eq(first.archive_checkout(starting, false), None)
    assert_true(@fsx.is_dir(checkout.to_path()))
    // Bound but neither started nor starting, it pins nothing.
    assert_eq(first.archive_checkout(host, false), None)
    assert_false(@fsx.exists(checkout.to_path()))
  })
}

///|
#cfg(not(platform="windows"))
async test "deleting one member's placement keeps the row for the others" {
  with_recovery_fixture((repo, host) => {
    let shared = create(
      host,
      resource_path(repo),
      WorktreeOwner::openseek("first"),
      _ => (),
    )
    let codex = create(
      host,
      resource_path(repo),
      WorktreeOwner::codex("thread"),
      _ => (),
    )
    bind_shared_fixture(repo, shared.name, ["first", "second"])
    guard drop_placements(repo, ["first"]) is Some([kept, other]) else {
      fail("a row with a remaining member must stay")
    }
    assert_eq(kept.name, shared.name)
    assert_eq(kept.sessions, ["second"])
    assert_eq(other.name, codex.name)
    // Nothing left to drop is reported as no registry change at all.
    assert_true(drop_placements(repo, ["first"]) is None)
    // The row goes with its last member; unrelated rows are untouched.
    guard drop_placements(repo, ["second"]) is Some([remaining]) else {
      fail("the row must go with its last member")
    }
    assert_eq(remaining.name, codex.name)
    assert_eq(remaining.codex_thread, Some("thread"))
  })
}

///|
#cfg(not(platform="windows"))
async test "removing a shared worktree drains every bound conversation" {
  with_recovery_fixture((repo, host) => {
    let created = create(
      host,
      resource_path(repo),
      WorktreeOwner::openseek("first"),
      _ => (),
    )
    bind_shared_fixture(repo, created.name, ["first", "second"])
    let drained : Array[String] = []
    ignore(
      remove(test_host(drained~), resource_path(repo), created.name, false, _ => {
        ()
      }),
    )
    assert_eq(drained, ["first", "second"])
    assert_false(@fsx.exists(worktree_dir(repo, created.name).to_path()))
    assert_eq(read_worktrees_unlocked(repo).length(), 0)
  })
}

///|
#cfg(not(platform="windows"))
async test "a fork is bound to its original's worktree around its record's creation" {
  with_recovery_fixture((repo, host) => {
    let created = create(
      host,
      resource_path(repo),
      WorktreeOwner::openseek("first"),
      _ => (),
    )
    let published : Array[Array[WorktreeInfo]] = []
    // The binding is already committed when the record is created, so an
    // archive of the original never sees a fork that is bound nowhere.
    let bound_at_creation : Array[String] = []
    add_session_to_worktree(
      repo,
      session="fork",
      worktree_of="first",
      () => {
        guard read_worktrees_unlocked(repo) is [row] else {
          fail("the worktree row must still be registered")
        }
        bound_at_creation.append(row.sessions)
      },
      record_exists=() => true,
      rows => published.push(rows),
    )
    assert_eq(bound_at_creation, ["first", "fork"])
    guard published is [[row]] else {
      fail("the new binding must be reported once")
    }
    assert_eq(row.name, created.name)
    assert_eq(row.sessions, ["first", "fork"])
    // A conversation in the workspace root has no worktree to join.
    let mut created_in_root = false
    add_session_to_worktree(
      repo,
      session="root-fork",
      worktree_of="root",
      () => created_in_root = true,
      record_exists=() => true,
      rows => published.push(rows),
    )
    assert_true(created_in_root)
    assert_eq(published.length(), 1)
    assert_eq(
      tree_dir(repo, "root-fork").map(dir => dir.to_string()),
      Some(repo.to_string()),
    )
    // A record that could not be created takes its binding back out.
    let failed = try {
      add_session_to_worktree(
        repo,
        session="broken",
        worktree_of="first",
        () => raise WorktreeError("record failed"),
        record_exists=() => false,
        rows => published.push(rows),
      )
      false
    } catch {
      _ => true
    }
    assert_true(failed)
    assert_eq(published.length(), 1)
    guard read_worktrees_unlocked(repo) is [after] else {
      fail("the worktree row must survive a failed fork")
    }
    assert_eq(after.sessions, ["first", "fork"])
    // A record that was written keeps its binding whatever became of the
    // call that wrote it, and the row is still reported.
    let failed_late = try {
      add_session_to_worktree(
        repo,
        session="late",
        worktree_of="first",
        () => raise WorktreeError("the writer failed after the record"),
        record_exists=() => true,
        rows => published.push(rows),
      )
      false
    } catch {
      _ => true
    }
    assert_true(failed_late)
    guard published is [_, [late]] else {
      fail("a fork that exists must be reported with its binding")
    }
    assert_eq(late.sessions, ["first", "fork", "late"])
    assert_eq(
      tree_dir(repo, "late").map(dir => dir.to_string()),
      tree_dir(repo, "first").map(dir => dir.to_string()),
    )
  })
}

///|
async test "single-member registry rows read as member lists and are rewritten as one" {
  let root = worktree_test_root("openseek-worktree-members-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  @fsx.ensure_dir(@workspaces.store_root(root).to_path())
  let registry : Json = {
    "worktrees": [
      {
        "name": "single",
        "branch": "openseek/single",
        "base": "abc",
        "session": "s1",
      },
      {
        "name": "shared",
        "branch": "openseek/shared",
        "base": "def",
        "sessions": ["s2", "", "s3", "s2", 7],
      },
      {
        "name": "ambiguous",
        "branch": "openseek/ambiguous",
        "base": "ghi",
        "sessions": ["s4"],
        "codex_thread": "thread-1",
      },
    ],
  }
  @fsx.write_text(worktrees_file(root).to_path(), registry.stringify())
  guard read_worktrees_unlocked(root) is [single, shared] else {
    fail("expected the two unambiguous rows")
  }
  assert_eq(single.sessions, ["s1"])
  // Blank, repeated, and non-string members name no further conversation.
  assert_eq(shared.sessions, ["s2", "s3"])
  write_worktrees(root, [single, shared])
  guard @fsx.try_read_text(worktrees_file(root).to_path()) is Some(text) else {
    fail("the registry must be readable after a commit")
  }
  let expected : Json = {
    "worktrees": [
      {
        "name": "single",
        "base": "abc",
        "branch": "openseek/single",
        "sessions": ["s1"],
      },
      {
        "name": "shared",
        "base": "def",
        "branch": "openseek/shared",
        "sessions": ["s2", "s3"],
      },
    ],
  }
  assert_eq(@json.parse(text), expected)
}
