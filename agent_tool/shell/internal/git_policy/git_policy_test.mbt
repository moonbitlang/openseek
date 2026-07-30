///|
test "parse finds the subcommand past global options" {
  let argv = ["git", "-C", "pkg", "--no-pager", "checkout", "--", "main.mbt"]
  guard @git_policy.parse(argv, 1) is Some(inv) else { fail("expected Some") }
  assert_eq(inv.subcommand, "checkout")
  assert_eq(inv.subcommand_index, 4)
}

///|
test "parse fails closed" {
  assert_true(@git_policy.parse(["git", "--bogus", "checkout"], 1) is None)
  assert_true(@git_policy.parse(["git", "--help", "checkout"], 1) is None)
  assert_true(@git_policy.parse(["git", "--", "checkout"], 1) is None)
  assert_true(@git_policy.parse(["git", "-c"], 1) is None)
  assert_true(@git_policy.parse(["git"], 1) is None)
}

///|
test "object-store-write classification excludes mv and plumbing" {
  for sub in ["checkout", "switch", "restore", "reset", "stash", "rm"] {
    assert_true(@git_policy.subcommand_writes_from_object_store(sub))
  }
  for sub in ["mv", "clean", "apply", "am", "status", "checkout-index", "co"] {
    assert_false(@git_policy.subcommand_writes_from_object_store(sub))
  }
}

///|
test "should_preblock: feeders, mv, non-dry-run clean, reconfigured writers" {
  // Blocked: mutates source but is not a recoverable object-store write.
  for
    cmd in [
      ["git", "apply", "patch"],
      ["git", "am", "mbox"],
      ["git", "update-index", "--cacheinfo", "100644,abc,main.mbt"],
      ["git", "read-tree", "HEAD"],
      ["git", "fast-import"],
      ["git", "mv", "notes.md", "main.mbt"],
      ["git", "clean", "-fd"],
      // `-e -n` is an exclude pattern, not a dry run -> still destructive.
      ["git", "clean", "-e", "-n", "-fd"],
      // read-only apply flag forced back to applying.
      ["git", "apply", "--stat", "--apply", "patch"],
      ["git", "apply", "--cached", "patch"],
      // checkout/restore that can clobber an untracked file from another tree.
      ["git", "checkout", "-f", "other"],
      ["git", "restore", "--source=HEAD~1", "--", "foo.mbt"],
      ["git", "restore", "-s", "HEAD~1", "foo.mbt"],
      ["git", "checkout", "HEAD~1", "--", "foo.mbt"],
      ["git", "checkout", "-fB", "new", "other"],
      ["git", "checkout", "HEAD~1", "--pathspec-from-file=list"],
      ["git", "checkout", "--ours", "conflict.mbt"],
      ["git", "-c", "filter.f.smudge=cmd", "checkout", "--", "."],
      ["git", "-C", "/tmp/x", "checkout", "--", "."],
      ["git", "--work-tree=/tmp/x", "restore", "main.mbt"],
    ] {
    assert_true(@git_policy.should_preblock(cmd, 1))
  }
  // Not blocked: recoverable writers, dry-run clean, read-only apply validation,
  // read-only git, reconfigured read-only git, and help.
  for
    cmd in [
      ["git", "checkout", "--", "main.mbt"],
      ["git", "checkout", "feature/foo"],
      ["git", "restore", "main.mbt"],
      ["git", "reset", "--hard"],
      ["git", "stash"],
      ["git", "rm", "main.mbt"],
      ["git", "clean", "-fdn"],
      ["git", "clean", "--dry-run"],
      ["git", "apply", "--check", "patch"],
      ["git", "apply", "--stat", "patch"],
      ["git", "status"],
      ["git", "-c", "core.pager=less", "status"],
      ["git", "checkout", "--help"],
      ["git", "clean", "--help"],
    ] {
    assert_false(@git_policy.should_preblock(cmd, 1))
  }
}

///|
test "reconfiguring global options" {
  for
    opt in [
      "-c", "--config-env", "--git-dir", "--namespace", "--exec-path", "-C", "--work-tree",
      "-Cpkg", "--git-dir=/x", "--work-tree=/x",
    ] {
    assert_true(@git_policy.global_option_reconfigures(opt))
  }
  for opt in ["--no-pager", "-p", "--literal-pathspecs", "checkout"] {
    assert_false(@git_policy.global_option_reconfigures(opt))
  }
}

///|
test "text_should_preblock mirrors should_preblock on a flat word list" {
  let apply = ["git", "-C", "pkg", "apply", "patch"]
  assert_true(@git_policy.text_should_preblock(apply, 1, apply.length()))
  let mv = ["git", "mv", "a", "b"]
  assert_true(@git_policy.text_should_preblock(mv, 1, mv.length()))
  let recoverable = ["git", "checkout", "--", "f"]
  assert_false(
    @git_policy.text_should_preblock(recoverable, 1, recoverable.length()),
  )
  // A help flag on the subcommand disables the block.
  let help = ["git", "apply", "--help"]
  assert_false(@git_policy.text_should_preblock(help, 1, help.length()))
}

///|
test "worktree args: add and prune recoverable, remove only without force" {
  fn recoverable(args : Array[String]) -> Bool {
    @git_policy.worktree_args_are_recoverable(args, 0, args.length())
  }

  // `add` in any form: git itself refuses an existing non-empty target, force
  // included, so nothing existing can be clobbered.
  assert_true(recoverable(["add", "../wt"]))
  assert_true(recoverable(["add", "--force", "../wt"]))
  assert_true(recoverable(["add", "-b", "feat", "../wt", "HEAD"]))
  assert_true(recoverable(["add", "--detach", "../wt"]))
  // `remove` without force deletes only tracked, clean content.
  assert_true(recoverable(["remove", "../wt"]))
  assert_true(recoverable(["remove", "--", "../wt"]))
  assert_true(recoverable(["prune"]))
  assert_true(recoverable(["prune", "-n", "--expire", "1.day"]))
  // Force remove permanently deletes modified or untracked files. Any option
  // fails closed: git accepts unambiguous long-option abbreviations, so
  // `--fo`/`--for` force the removal too.
  assert_false(recoverable(["remove", "--force", "../wt"]))
  assert_false(recoverable(["remove", "-f", "../wt"]))
  assert_false(recoverable(["remove", "-ff", "../wt"]))
  assert_false(recoverable(["remove", "--fo", "../wt"]))
  assert_false(recoverable(["remove", "--quiet", "../wt"]))
  // After `--` every word is a path: a worktree named `-f` is a plain,
  // non-force removal.
  assert_true(recoverable(["remove", "--", "-f"]))
  // Everything else fails closed, including a missing verb.
  assert_false(recoverable(["list"]))
  assert_false(recoverable(["lock", "../wt"]))
  assert_false(recoverable(["move", "../wt", "../wt2"]))
  assert_false(recoverable(["repair"]))
  assert_false(recoverable([]))
}
