///|
async test "current PR status skips GitHub for a local checkout without remotes" {
  let dir = @fs.tmpdir(prefix="openseek-local-pr-status-")
  let repo = git_test_repo(dir)
  let _ = {
    defer git_test_cleanup(dir)
    git_test_run(dir, ["init", "--quiet"])
    let branch = @git.current_branch(repo).unwrap()
    let status = github_checkout_status(repo, _ => {
      fail("A local checkout without remotes must not query GitHub")
    })
    assert_eq(status.branch, Some(branch))
    assert_eq(status.pull_request_url, None)
    assert_false(status.has_open_pull_request)
  }
}

///|
#skip("flaky: moonbitlang/async 0.22.x raises EAGAIN on a spurious process-read wake-up; unskip after bumping to a release with moonbitlang/async#634")
async test "current PR status verifies remote lifecycle even for saved branch associations" {
  let dir = @fs.tmpdir(prefix="openseek-pr-status-")
  let repo = git_test_repo(dir)
  let _ = {
    defer git_test_cleanup(dir)
    git_test_run(dir, ["init", "--quiet"])
    @fs.write_file("\{dir}/file.txt", "content", create_mode=CreateOrTruncate)
    git_test_run(dir, ["add", "."])
    git_test_commit(dir, "initial")
    let branch = @git.current_branch(repo).unwrap()
    let base = @git.revision_commit(repo, "HEAD").unwrap()
    let url = "https://github.example/owner/repo/pull/42"
    git_test_run(dir, [
      "remote", "add", "origin", "https://github.example/owner/repo.git",
    ])
    for saved in [false, true] {
      if saved {
        git_test_run(dir, ["remote", "remove", "origin"])
        let metadata : Json = { "url": url, "base": base }
        git_test_run(dir, [
          "config",
          "branch.\{branch}.openseek-pr",
          metadata.stringify(),
        ])
      }
      for lifecycle in ["OPEN", "CLOSED", "MERGED"] {
        let status = github_checkout_status(repo, args => {
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
          let _ = github_checkout_status(repo, _ => {
            if saved {
              invalid
            } else {
              { "currentBranch": invalid }
            }
          })
          false
        } catch {
          InvalidResponse(_) => true
          error => raise error
        }
        assert_true(failed)
      }
      let failed = try {
        let _ = github_checkout_status(repo, _ => raise Unavailable("offline"))
        false
      } catch {
        Unavailable(message) => message == "offline"
        error => raise error
      }
      assert_true(failed)
      if !saved {
        let absent_replies : Array[Json] = [{}, { "currentBranch": null }]
        for absent in absent_replies {
          let status = github_checkout_status(repo, _ => absent)
          assert_eq(status.pull_request_url, None)
          assert_false(status.has_open_pull_request)
        }
      }
    }
    git_test_run(dir, ["switch", "--detach", base])
    let status = github_checkout_status(repo, _ => {
      fail("A detached checkout must not query a branch PR")
    })
    assert_eq(status.branch, None)
    assert_false(status.has_open_pull_request)
  }
}

///|
async test "checkout failures travel as data instead of redacted Proton errors" {
  let reply = checkout({
    cwd: "relative/path",
    repository_url: "https://github.com/owner/repo",
    number: 42,
    changes: Ask,
    update: false,
  })
  assert_true(
    reply is CheckoutFailure(message, _) &&
    message.contains("path is not absolute"),
  )
}

///|
#skip("flaky: moonbitlang/async 0.22.x raises EAGAIN on a spurious process-read wake-up; unskip after bumping to a release with moonbitlang/async#634")
async test "checkout choices preserve edits until chosen and stash retains index and untracked files" {
  let dir = @fs.tmpdir(prefix="openseek-checkout-choices-")
  let repo = git_test_repo(dir)
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
    assert_false(github_prepare_checkout(repo, 42, Ask))
    assert_true(github_prepare_checkout(repo, 42, Carry))
    assert_eq(@gitx.output(repo, ["show", ":tracked.txt"]), "staged\n")
    assert_eq(@fs.read_file("\{dir}/tracked.txt").text(), "working\n")
    assert_true(github_prepare_checkout(repo, 42, Stash))
    assert_eq(@fs.read_file("\{dir}/tracked.txt").text(), "original\n")
    assert_eq(
      @gitx.output(repo, ["show", "stash@{0}:tracked.txt"]),
      "working\n",
    )
    assert_eq(
      @gitx.output(repo, ["show", "stash@{0}^2:tracked.txt"]),
      "staged\n",
    )
    assert_eq(@fs.read_file("\{dir}/untracked.txt").text(), "keep\n")
    assert_true(github_prepare_checkout(repo, 42, Ask))
    git_test_run(dir, ["stash", "apply", "--index"])
    assert_true(github_prepare_checkout(repo, 42, Discard))
    assert_eq(@fs.read_file("\{dir}/tracked.txt").text(), "original\n")
    assert_eq(@gitx.output(repo, ["show", ":tracked.txt"]), "original\n")
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
/// Best-effort removal of a test repository; it runs to completion under
/// cancellation, and an rmdir failure is the test's own tmpdir and is ignored.
async fn git_test_cleanup(dir : String) -> Unit nocancel {
  @async.protect_from_cancel(() => {
    @fs.rmdir(dir, recursive=true) catch {
      _ => ()
    }
  })
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
  let _ = @gitx.output(git_test_repo(dir), args) catch {
    error => fail("Git fixture command failed: \{error}")
  }
}

///|
fn git_test_repo(dir : String) -> @pathx.Absolute raise {
  @pathx.Absolute::parse_resource_path(dir)
}
