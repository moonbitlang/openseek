///|
#skip("flaky: moonbitlang/async 0.22.x raises EAGAIN on a spurious process-read wake-up; unskip after bumping to a release with moonbitlang/async#634")
async test "current PR status verifies remote lifecycle even for saved branch associations" {
  let dir = @fs.tmpdir(prefix="openseek-pr-status-")
  let _ = {
    defer git_test_cleanup(dir)
    git_test_run(dir, ["init", "--quiet"])
    @fs.write_file("\{dir}/file.txt", "content", create_mode=CreateOrTruncate)
    git_test_run(dir, ["add", "."])
    git_test_commit(dir, "initial")
    let root = @pathx.Absolute::from_uri_path(dir).unwrap()
    let branch = github_checkout_branch(dir).unwrap()
    let base = git_revision_commit(dir, "HEAD").unwrap()
    let url = "https://github.example/owner/repo/pull/42"
    for saved in [false, true] {
      if saved {
        let metadata : Json = { "url": url, "base": base }
        git_test_run(dir, [
          "config",
          "branch.\{branch}.openseek-pr",
          metadata.stringify(),
        ])
      }
      for lifecycle in ["OPEN", "CLOSED", "MERGED"] {
        let status = github_checkout_status(root, args => {
          assert_eq(
            args,
            if saved {
              ["pr", "view", url, "--json", "url,state"]
            } else {
              ["pr", "status", "--json", "url,state"]
            },
          )
          // Draft is still an open PR; only lifecycle controls availability.
          let pr : Json = { "url": url, "state": lifecycle, "isDraft": true }
          if saved {
            pr
          } else {
            { "currentBranch": pr }
          }
        })
        assert_eq(status.branch, Some(branch))
        assert_eq(status.pull_request_url, Some(url))
        assert_eq(status.has_open_pull_request, lifecycle == "OPEN")
      }
      let invalid_replies : Array[Json] = [
        { "url": url },
        { "url": url, "state": "unknown" },
      ]
      for invalid in invalid_replies {
        let failed = try {
          let _ = github_checkout_status(root, _ => {
            if saved {
              invalid
            } else {
              { "currentBranch": invalid }
            }
          })
          false
        } catch {
          HostError(_) => true
          error => raise error
        }
        assert_true(failed)
      }
      let failed = try {
        let _ = github_checkout_status(root, _ => raise HostError("offline"))
        false
      } catch {
        HostError(message) => message == "offline"
        error => raise error
      }
      assert_true(failed)
      if !saved {
        let absent_replies : Array[Json] = [{}, { "currentBranch": null }]
        for absent in absent_replies {
          let status = github_checkout_status(root, _ => absent)
          assert_eq(status.pull_request_url, None)
          assert_false(status.has_open_pull_request)
        }
      }
    }
    git_test_run(dir, ["switch", "--detach", base])
    let status = github_checkout_status(root, _ => {
      fail("A detached checkout must not query a branch PR")
    })
    assert_eq(status.branch, None)
    assert_false(status.has_open_pull_request)
  }
}

///|
async test "checkout failures travel as data instead of redacted Proton errors" {
  let reply = github_checkout_op({
    cwd: "relative/path",
    repository_url: "https://github.com/owner/repo",
    number: 42,
    changes: Ask,
    update: false,
  })
  assert_true(
    reply is CheckoutFailure(message, _) &&
    message.contains("absolute checkout path"),
  )
}

///|
#skip("flaky: moonbitlang/async 0.22.x raises EAGAIN on a spurious process-read wake-up; unskip after bumping to a release with moonbitlang/async#634")
async test "checkout choices preserve edits until chosen and stash retains index and untracked files" {
  let dir = @fs.tmpdir(prefix="openseek-checkout-choices-")
  let _ = {
    defer git_test_cleanup(dir)
    git_test_run(dir, ["init", "--quiet"])
    @fs.write_file(
      "\{dir}/tracked.txt",
      "original\n",
      create_mode=CreateOrTruncate,
    )
    git_test_run(dir, ["add", "tracked.txt"])
    git_test_commit(dir, "initial")
    @fs.write_file(
      "\{dir}/tracked.txt",
      "staged\n",
      create_mode=CreateOrTruncate,
    )
    git_test_run(dir, ["add", "tracked.txt"])
    @fs.write_file(
      "\{dir}/tracked.txt",
      "working\n",
      create_mode=CreateOrTruncate,
    )
    @fs.write_file(
      "\{dir}/untracked.txt",
      "keep\n",
      create_mode=CreateOrTruncate,
    )
    assert_false(github_prepare_checkout(dir, 42, Ask))
    assert_true(github_prepare_checkout(dir, 42, Carry))
    assert_eq(github_checkout_git(dir, ["show", ":tracked.txt"]), "staged\n")
    assert_eq(@fs.read_file("\{dir}/tracked.txt").text(), "working\n")
    assert_true(github_prepare_checkout(dir, 42, Stash))
    assert_eq(@fs.read_file("\{dir}/tracked.txt").text(), "original\n")
    assert_eq(
      github_checkout_git(dir, ["show", "stash@{0}:tracked.txt"]),
      "working\n",
    )
    assert_eq(
      github_checkout_git(dir, ["show", "stash@{0}^2:tracked.txt"]),
      "staged\n",
    )
    assert_eq(@fs.read_file("\{dir}/untracked.txt").text(), "keep\n")
    assert_true(github_prepare_checkout(dir, 42, Ask))
    git_test_run(dir, ["stash", "apply", "--index"])
    assert_true(github_prepare_checkout(dir, 42, Discard))
    assert_eq(@fs.read_file("\{dir}/tracked.txt").text(), "original\n")
    assert_eq(github_checkout_git(dir, ["show", ":tracked.txt"]), "original\n")
    assert_eq(@fs.read_file("\{dir}/untracked.txt").text(), "keep\n")
  }
}

///|
test "checkout errors explain recovery and retain Git diagnostics" {
  for
    (stderr, expected) in [
      (
        "error: Your local changes to the following files would be overwritten by checkout:\n\tfile.txt\nAborting",
        "Commit or stash",
      ),
      (
        "error: The following untracked working tree files would be overwritten by checkout:\n\tnew.txt\nAborting",
        "Move or commit",
      ),
      (
        "fatal: 'topic' is already used by worktree at '/tmp/other'", "another worktree",
      ),
    ] {
    assert_true(
      github_checkout_failure(stderr) is CheckoutFailure(message, Some(details)) &&
      message.contains(expected) &&
      details == stderr,
    )
  }
  assert_true(
    github_checkout_failure("authentication failed")
    is CheckoutFailure("authentication failed", None),
  )
  let fetch_then_error = "From github.com:owner/repo\n * [new branch] topic\nfatal: Not possible to fast-forward, aborting."
  assert_true(
    github_checkout_failure(fetch_then_error)
    is CheckoutFailure(
      "fatal: Not possible to fast-forward, aborting.",
      Some(details)
    ) &&
    details == fetch_then_error,
  )
}

///|
#skip("flaky: moonbitlang/async 0.22.x raises EAGAIN on a spurious process-read wake-up; unskip after bumping to a release with moonbitlang/async#634")
async test "PR review uses its merge base and association follows the checked out branch" {
  let dir = @fs.tmpdir(prefix="openseek-checkout-review-")
  let _ = {
    defer git_test_cleanup(dir)
    git_test_run(dir, ["init", "--quiet"])
    @fs.write_file(
      "\{dir}/upstream.txt",
      "before\n",
      create_mode=CreateOrTruncate,
    )
    git_test_run(dir, ["add", "."])
    git_test_commit(dir, "old default branch")
    @fs.write_file(
      "\{dir}/upstream.txt",
      "upstream work\n",
      create_mode=CreateOrTruncate,
    )
    git_test_run(dir, ["add", "."])
    git_test_commit(dir, "PR base")
    let base = git_revision_commit(dir, "HEAD").unwrap()
    git_test_run(dir, ["switch", "-c", "pr/feature"])
    @fs.write_file("\{dir}/pr.txt", "PR work\n", create_mode=CreateOrTruncate)
    git_test_run(dir, ["add", "."])
    git_test_commit(dir, "PR head")
    let url = "https://github.example/owner/repo/pull/42"
    let metadata : Json = { "url": url, "base": base }
    git_test_run(dir, [
      "config",
      "branch.pr/feature.openseek-pr",
      metadata.stringify(),
    ])
    let association = github_local_checkout_association(dir).unwrap()
    assert_eq(association.url, url)
    let (_, comparison, _, _, _, _, changes) = git_change_snapshot(
      dir,
      "",
      retries_left=2,
      pr_base=association.base,
    )
    assert_eq(comparison, Some(base))
    assert_eq(changes.map(change => change.path), ["pr.txt"])
    git_test_run(dir, ["switch", "--detach", base])
    assert_true(github_local_checkout_association(dir) is None)
    git_test_run(dir, ["switch", "-c", "other"])
    assert_true(github_local_checkout_association(dir) is None)
    git_test_run(dir, ["switch", "pr/feature"])
    assert_eq(github_local_checkout_association(dir).unwrap().url, url)
  }
}

///|
/// Best-effort removal of a test repository. Cancellation stays observable;
/// any other rmdir failure is the test's own tmpdir and is ignored.
async fn git_test_cleanup(dir : String) -> Unit {
  @fs.rmdir(dir, recursive=true) catch {
    _ => ()
  }
}

///|
async fn git_test_commit(dir : String, message : String) -> Unit {
  git_test_run(dir, [
    "-c", "user.name=OpenSeek Test", "-c", "user.email=openseek@example.invalid",
    "-c", "commit.gpgSign=false", "commit", "--quiet", "-m", message,
  ])
}

///|
async fn git_test_run(dir : String, args : Array[String]) -> Unit {
  let (code, _, stderr) = git_collect(dir, args)
  guard code == 0 else {
    let detail = (stderr.text() catch { _ => "non-UTF-8 stderr" }).trim()
    fail("Git fixture command failed: \{detail}")
  }
}

///|
#skip("flaky: moonbitlang/async 0.22.x raises EAGAIN on a spurious process-read wake-up; unskip after bumping to a release with moonbitlang/async#634")
async test "Git history pages stay pinned and commit changes use first parent" {
  let dir = @fs.tmpdir(prefix="openseek-git-history-")
  let _ = {
    defer git_test_cleanup(dir)
    git_test_run(dir, ["init", "--quiet"])
    @fs.write_file("\{dir}/old.mbt", "first\n", create_mode=CreateOrTruncate)
    git_test_run(dir, ["add", "old.mbt"])
    git_test_commit(dir, "first")
    git_test_run(dir, ["branch", "-M", "feature/graph"])
    let first = git_revision_commit(dir, "HEAD").unwrap()
    git_test_run(dir, ["update-ref", "refs/remotes/origin/main", first])
    git_test_run(dir, [
      "symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main",
    ])
    git_test_run(dir, ["mv", "old.mbt", "new.mbt"])
    git_test_commit(dir, "rename")
    let second = git_revision_commit(dir, "HEAD").unwrap()
    git_test_run(dir, [
      "update-ref", "refs/remotes/origin/feature/graph", second,
    ])
    git_test_run(dir, ["config", "branch.feature/graph.remote", "origin"])
    git_test_run(dir, [
      "config", "remote.origin.fetch", "+refs/heads/*:refs/remotes/origin/*",
    ])
    git_test_run(dir, [
      "config", "branch.feature/graph.merge", "refs/heads/feature/graph",
    ])
    let snapshot = capture_git_history_snapshot(dir, Some(first))
    assert_eq(snapshot.head, Some(second))
    assert_eq(snapshot.branch, Some("feature/graph"))
    assert_true(snapshot.refs.any(ref_ => ref_.kind == "current"))
    assert_true(snapshot.refs.any(ref_ => ref_.kind == "upstream"))
    assert_true(snapshot.refs.any(ref_ => ref_.kind == "base"))
    let (first_page, has_more) = git_history_page(dir, snapshot, 0, 1)
    assert_true(has_more)
    assert_true(first_page is [{ id, subject: "rename", .. }] && id == second)
    @fs.write_file("\{dir}/third.mbt", "third\n", create_mode=CreateOrTruncate)
    git_test_run(dir, ["add", "third.mbt"])
    git_test_commit(dir, "third")
    let third = git_revision_commit(dir, "HEAD").unwrap()
    assert_true(third != second)
    // The next page still walks the captured second-commit tips.
    let (second_page, _) = git_history_page(dir, snapshot, 1, 1)
    assert_true(second_page is [{ id, subject: "first", .. }] && id == first)
    let renamed = git_commit_changes_at(dir, "", second)
    assert_eq(renamed.parent, Some(first))
    assert_true(
      renamed.changes
      is [
        {
          path: "new.mbt",
          original_path: Some("old.mbt"),
          status: "renamed",
          kind: "file",
        },
      ],
    )
    let root = git_commit_changes_at(dir, "", first)
    assert_eq(root.parent, None)
    assert_true(root.changes is [{ path: "old.mbt", status: "added", .. }])

    // A merge comparison follows Git's ordinary history-provider semantics:
    // only the first parent's delta appears below the merge row.
    git_test_run(dir, ["branch", "side", first])
    git_test_run(dir, ["checkout", "--quiet", "side"])
    @fs.write_file("\{dir}/side.mbt", "side\n", create_mode=CreateOrTruncate)
    git_test_run(dir, ["add", "side.mbt"])
    git_test_commit(dir, "side")
    git_test_run(dir, ["checkout", "--quiet", "feature/graph"])
    git_test_run(dir, [
      "-c", "user.name=OpenSeek Test", "-c", "user.email=openseek@example.invalid",
      "-c", "commit.gpgSign=false", "merge", "--quiet", "--no-ff", "-m", "merge side",
      "side",
    ])
    let merge = git_revision_commit(dir, "HEAD").unwrap()
    let merged = git_commit_changes_at(dir, "", merge)
    assert_eq(merged.parent, Some(third))
    assert_true(
      merged.changes
      is [{ path: "side.mbt", status: "added", kind: "file", .. }],
    )

    // Exhaustive copy discovery and tree modes are properties of historical
    // inspection, not the cheaper working-tree poll.
    @fs.write_file("\{dir}/copy.mbt", "first\n", create_mode=CreateOrTruncate)
    @fs.symlink(target="new.mbt", "\{dir}/link")
    git_test_run(dir, ["add", "copy.mbt", "link"])
    git_test_run(dir, [
      "update-index",
      "--add",
      "--cacheinfo",
      "160000,\{first},vendor/lib",
    ])
    git_test_commit(dir, "copy and modes")
    let modes_commit = git_revision_commit(dir, "HEAD").unwrap()
    let mode_changes = git_commit_changes_at(dir, "", modes_commit).changes
    assert_true(
      mode_changes.any(change => {
        change.path == "copy.mbt" &&
        change.original_path == Some("new.mbt") &&
        change.status == "copied" &&
        change.kind == "file"
      }),
    )
    assert_true(
      mode_changes.any(change => {
        change.path == "link" && change.kind == "symlink"
      }),
    )
    assert_true(
      mode_changes.any(change => {
        change.path == "vendor/lib" && change.kind == "submodule"
      }),
    )

    // A type change stays inert when either revision is a special Git object,
    // including the less obvious symlink-to-regular-file direction.
    @fs.remove("\{dir}/link")
    @fs.write_file("\{dir}/link", "regular\n", create_mode=CreateOrTruncate)
    git_test_run(dir, ["add", "link"])
    git_test_commit(dir, "replace symlink")
    let type_commit = git_revision_commit(dir, "HEAD").unwrap()
    assert_true(
      git_commit_changes_at(dir, "", type_commit).changes.any(change => {
        change.path == "link" &&
        change.status == "type-changed" &&
        change.kind == "symlink"
      }),
    )

    @fs.write_file(
      "\{dir}/binary.dat",
      "binary\u{0}payload",
      create_mode=CreateOrTruncate,
    )
    @fs.write_file(
      "\{dir}/oversized.txt",
      "x".repeat(@openpath.MaxEditorFileBytes + 1),
      create_mode=CreateOrTruncate,
    )
    git_test_run(dir, ["add", "binary.dat", "oversized.txt"])
    git_test_commit(dir, "binary content policies")
    let content_commit = git_revision_commit(dir, "HEAD").unwrap()
    assert_eq(
      git_original_file_at(dir, Relative("binary.dat"), content_commit),
      BinaryOriginal,
    )
    assert_eq(
      git_original_file_at(dir, Relative("oversized.txt"), content_commit),
      OversizedOriginal,
    )
  }
}

///|
#skip("flaky: moonbitlang/async 0.22.x raises EAGAIN on a spurious process-read wake-up; unskip after bumping to a release with moonbitlang/async#634")
async test "Git history paginates fifty commits and describes detached HEAD" {
  let dir = @fs.tmpdir(prefix="openseek-git-history-page-")
  let _ = {
    defer git_test_cleanup(dir)
    git_test_run(dir, ["init", "--quiet"])
    let unborn = capture_git_history_snapshot(dir, None)
    assert_eq(unborn.head, None)
    assert_true(unborn.refs.is_empty())
    assert_true(unborn.tips.is_empty())
    for index in 0..<52 {
      @fs.write_file(
        "\{dir}/history.txt",
        "\{index}\n",
        create_mode=CreateOrTruncate,
      )
      git_test_run(dir, ["add", "history.txt"])
      git_test_commit(dir, "history \{index}")
    }
    git_test_run(dir, ["checkout", "--quiet", "--detach"])
    let snapshot = capture_git_history_snapshot(dir, None)
    assert_true(snapshot.head is Some(_))
    assert_eq(snapshot.branch, None)
    assert_true(snapshot.refs is [{ name: "HEAD", kind: "head", .. }])
    let (first_page, has_more) = git_history_page(dir, snapshot, 0, 50)
    assert_eq(first_page.length(), 50)
    assert_true(has_more)
    let (last_page, last_has_more) = git_history_page(dir, snapshot, 50, 50)
    assert_eq(last_page.length(), 2)
    assert_false(last_has_more)
  }
}

///|
async test "Git recognizes only origin HEAD's branch as the default" {
  let dir = @fs.tmpdir(prefix="openseek-git-default-branch-")
  defer git_test_cleanup(dir)
  git_test_run(dir, ["init", "--quiet"])
  @fs.write_file("\{dir}/tracked.txt", "first\n", create_mode=CreateOrTruncate)
  git_test_run(dir, ["add", "tracked.txt"])
  git_test_run(dir, [
    "-c", "user.name=OpenSeek Test", "-c", "user.email=openseek@example.invalid",
    "-c", "commit.gpgSign=false", "commit", "--quiet", "-m", "first",
  ])
  // A branch spelling alone proves nothing until the remote declares its
  // default. Once it does, only that exact name is suppressed from PR lookup.
  assert_false(git_is_default_branch(dir, branch="main"))
  git_test_run(dir, ["update-ref", "refs/remotes/origin/main", "HEAD"])
  git_test_run(dir, [
    "symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main",
  ])
  assert_true(git_is_default_branch(dir, branch="main"))
  assert_false(git_is_default_branch(dir, branch="feature/from-main"))
}

///|
#skip("flaky: moonbitlang/async 0.22.x raises EAGAIN on a spurious process-read wake-up; unskip after bumping to a release with moonbitlang/async#634")
async test "Git snapshots pair status with HEAD and supplied revisions stay pinned" {
  let dir = @fs.tmpdir(prefix="openseek-git-review-")
  defer git_test_cleanup(dir)
  git_test_run(dir, ["init", "--quiet"])
  assert_eq(git_revision_commit(dir, "HEAD"), None)
  @fs.mkdir("\{dir}/desktop", recursive=true)
  @fs.write_file("\{dir}/review.txt", "first\n", create_mode=CreateOrTruncate)
  @fs.write_file(
    "\{dir}/desktop/keep.txt",
    "keep\n",
    create_mode=CreateOrTruncate,
  )
  git_test_run(dir, ["add", "review.txt", "desktop/keep.txt"])
  git_test_run(dir, [
    "-c", "user.name=OpenSeek Test", "-c", "user.email=openseek@example.invalid",
    "commit", "--quiet", "-m", "first",
  ])
  let first = git_revision_commit(dir, "HEAD").unwrap()
  // A task deletion must use the comparison tree's mode, not a staged type
  // change that no longer exists in the working tree.
  @fs.remove("\{dir}/desktop/keep.txt")
  @fs.symlink(target="../review.txt", "\{dir}/desktop/keep.txt")
  git_test_run(dir, ["add", "desktop/keep.txt"])
  @fs.remove("\{dir}/desktop/keep.txt")
  let (_, _, _, current_symlinks, _, deleted_symlinks, type_changes) = git_change_snapshot(
    dir,
    "",
    retries_left=2,
    worktree_base=first,
  )
  assert_true(current_symlinks.contains("desktop/keep.txt"))
  assert_false(deleted_symlinks.contains("desktop/keep.txt"))
  guard type_changes is [deleted] else {
    fail("expected the staged type-change deletion")
  }
  assert_eq(
    git_change_with_path_kind(
      deleted,
      Unknown,
      false,
      deleted_symlinks.contains(deleted.path),
    ).kind,
    "deleted",
  )
  git_test_run(dir, ["restore", "--staged", "desktop/keep.txt"])
  git_test_run(dir, ["restore", "desktop/keep.txt"])
  @fs.write_file("\{dir}/review.txt", "working\n", create_mode=CreateOrTruncate)
  let (snapshot_head, snapshot_base, _, _, _, _, changes) = git_change_snapshot(
    dir,
    "",
    retries_left=2,
  )
  assert_eq(snapshot_head, Some(first))
  assert_eq(snapshot_base, None)
  assert_true(changes is [{ path: "review.txt", kind: "modified", .. }])
  let (_, task_base, _, _, _, _, task_before_commit) = git_change_snapshot(
    dir,
    "",
    retries_left=2,
    worktree_base=first,
  )
  assert_eq(task_base, Some(first))
  git_test_run(dir, ["add", "review.txt"])
  git_test_run(dir, [
    "-c", "user.name=OpenSeek Test", "-c", "user.email=openseek@example.invalid",
    "commit", "--quiet", "-m", "second",
  ])
  let second = git_revision_commit(dir, "HEAD").unwrap()
  assert_true(second != first)
  let (_, head_base, _, _, _, _, head_changes) = git_change_snapshot(
    dir,
    "",
    retries_left=2,
  )
  assert_eq(head_base, None)
  assert_true(head_changes.is_empty())
  let (_, _, _, _, _, _, task_changes) = git_change_snapshot(
    dir,
    "",
    retries_left=2,
    worktree_base=first,
  )
  assert_eq(task_changes, task_before_commit)
  assert_eq(git_revision_commit(dir, first), Some(first))
  assert_eq(git_revision_commit(dir, "missing-review-revision"), None)
  assert_eq(
    git_original_file_at(dir, Relative("review.txt"), first),
    OriginalContent("first\n"),
  )
  assert_eq(
    git_original_file_at(dir, Relative("review.txt"), second),
    OriginalContent("working\n"),
  )
  // Populate a gitlink directly so the test stays offline, add a symlink,
  // then stage both deletions from a workspace rooted below the repository.
  // Targeted HEAD discovery must retain the repository-root path spelling
  // emitted by --full-name and both non-text entry modes.
  git_test_run(dir, [
    "update-index",
    "--add",
    "--cacheinfo",
    "160000,\{second},desktop/vendor/lib",
  ])
  @fs.symlink(target="keep.txt", "\{dir}/desktop/link")
  git_test_run(dir, ["add", "desktop/link"])
  git_test_run(dir, [
    "-c", "user.name=OpenSeek Test", "-c", "user.email=openseek@example.invalid",
    "commit", "--quiet", "-m", "gitlink",
  ])
  let gitlink_head = git_revision_commit(dir, "HEAD").unwrap()
  @fs.remove("\{dir}/desktop/link")
  git_test_run(dir, [
    "update-index", "--force-remove", "desktop/link", "desktop/vendor/lib",
  ])
  let (nested_head, _, _, _, deleted_gitlinks, deleted_symlinks, nested_changes) = git_change_snapshot(
    "\{dir}/desktop",
    "desktop/",
    retries_left=2,
  )
  assert_eq(nested_head, Some(gitlink_head))
  assert_eq(deleted_gitlinks.length(), 1)
  assert_true(deleted_gitlinks.contains("vendor/lib"))
  assert_eq(deleted_symlinks.length(), 1)
  assert_true(deleted_symlinks.contains("link"))
  assert_true(
    nested_changes
    is [
      { path: "link", index_status: "D", kind: "deleted", .. },
      { path: "vendor/lib", index_status: "D", kind: "deleted", .. },
    ],
  )
  let classified = nested_changes.map(change => {
    git_change_with_path_kind(
      change,
      Unknown,
      deleted_gitlinks.contains(change.path),
      deleted_symlinks.contains(change.path),
    )
  })
  assert_true(
    classified
    is [
      { path: "link", kind: "symlink", .. },
      { path: "vendor/lib", kind: "submodule", .. },
    ],
  )
}

///|
#skip("flaky: moonbitlang/async 0.22.x raises EAGAIN on a spurious process-read wake-up; unskip after bumping to a release with moonbitlang/async#634")
async test "checkout reviews retain committed changes and follow rebases" {
  let dir = @fs.tmpdir(prefix="openseek-git-root-review-")
  defer git_test_cleanup(dir)
  git_test_run(dir, ["init", "--quiet"])
  @fs.write_file("\{dir}/review.txt", "first\n", create_mode=CreateOrTruncate)
  git_test_run(dir, ["add", "review.txt"])
  git_test_run(dir, [
    "-c", "user.name=OpenSeek Test", "-c", "user.email=openseek@example.invalid",
    "-c", "commit.gpgSign=false", "commit", "--quiet", "-m", "first",
  ])
  let first = git_revision_commit(dir, "HEAD").unwrap()
  git_test_run(dir, ["update-ref", "refs/remotes/origin/main", first])
  git_test_run(dir, [
    "symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main",
  ])
  @fs.write_file("\{dir}/review.txt", "working\n", create_mode=CreateOrTruncate)
  let (before_head, before_base, _, _, _, _, before_changes) = git_change_snapshot(
    dir,
    "",
    retries_left=2,
  )
  assert_eq(before_head, Some(first))
  // At the fork point, preserve porcelain's staged/worktree distinction.
  assert_eq(before_base, None)
  assert_true(
    before_changes
    is [{ path: "review.txt", index_status: " ", worktree_status: "M", .. }],
  )
  git_test_run(dir, ["add", "review.txt"])
  git_test_run(dir, [
    "-c", "user.name=OpenSeek Test", "-c", "user.email=openseek@example.invalid",
    "-c", "commit.gpgSign=false", "commit", "--quiet", "-m", "second",
  ])
  let second = git_revision_commit(dir, "HEAD").unwrap()
  let (after_head, after_base, _, _, _, _, after_changes) = git_change_snapshot(
    dir,
    "",
    retries_left=2,
  )
  assert_eq(after_head, Some(second))
  assert_eq(after_base, Some(first))
  // Committing must not make an ordinary checkout's Review turn empty.
  assert_eq(after_changes, before_changes)
  // Rebase onto new upstream work while retaining the task's creation base.
  git_test_run(dir, ["switch", "--detach", first])
  @fs.write_file(
    "\{dir}/upstream.txt",
    "upstream\n",
    create_mode=CreateOrTruncate,
  )
  git_test_run(dir, ["add", "upstream.txt"])
  git_test_commit(dir, "upstream")
  let upstream = git_revision_commit(dir, "HEAD").unwrap()
  git_test_run(dir, ["update-ref", "refs/remotes/origin/main", upstream])
  // At the default tip, the valid HEAD boundary must beat an old task base.
  let (_, tip_base, _, _, _, _, tip_changes) = git_change_snapshot(
    dir,
    "",
    retries_left=2,
    worktree_base=first,
  )
  assert_eq(tip_base, Some(upstream))
  assert_true(tip_changes.is_empty())
  @fs.write_file("\{dir}/review.txt", "pending\n", create_mode=CreateOrTruncate)
  let (_, pending_base, _, _, _, _, pending_changes) = git_change_snapshot(
    dir,
    "",
    retries_left=2,
    worktree_base=first,
  )
  assert_eq(pending_base, Some(upstream))
  assert_eq(pending_changes.map(change => change.path), ["review.txt"])
  git_test_run(dir, ["restore", "review.txt"])
  git_test_run(dir, ["switch", "--detach", second])
  git_test_run(dir, [
    "-c", "user.name=OpenSeek Test", "-c", "user.email=openseek@example.invalid",
    "-c", "commit.gpgSign=false", "rebase", "origin/main",
  ])
  @fs.write_file(
    "\{dir}/review.txt",
    "uncommitted\n",
    create_mode=CreateOrTruncate,
  )
  let (_, rebased_base, _, _, _, _, rebased_changes) = git_change_snapshot(
    dir,
    "",
    retries_left=2,
    worktree_base=first,
  )
  assert_eq(rebased_base, Some(upstream))
  assert_eq(rebased_changes.map(change => change.path), ["review.txt"])
  // Explicit PR baselines retain their priority over the default branch.
  let (_, pinned_base, _, _, _, _, _) = git_change_snapshot(
    dir,
    "",
    retries_left=2,
    pr_base=first,
    worktree_base=upstream,
  )
  assert_eq(pinned_base, Some(first))
  // Without a declared default branch, retain the creation base fallback.
  git_test_run(dir, ["symbolic-ref", "--delete", "refs/remotes/origin/HEAD"])
  let (_, fallback_base, _, _, _, _, fallback_changes) = git_change_snapshot(
    dir,
    "",
    retries_left=2,
    worktree_base=first,
  )
  assert_eq(fallback_base, Some(first))
  assert_eq(fallback_changes.map(change => change.path), [
    "review.txt", "upstream.txt",
  ])
}
