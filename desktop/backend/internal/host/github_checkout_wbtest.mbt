///|
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
