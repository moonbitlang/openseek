///|
test "one_line_brief collapses newlines and caps length" {
  assert_eq(one_line_brief("a\nb", 10), "a b")
  assert_eq(one_line_brief("  spaced  ", 10), "spaced")
  assert_eq(one_line_brief("hello world", 5), "hello…")
}

///|
test "copy_skip drops build/vendor/session data but keeps git, skills, sources" {
  let sr = ".openseek/sessions"
  assert_true(copy_skip("_build", sessions_rel=sr))
  assert_true(copy_skip("node_modules", sessions_rel=sr))
  assert_true(copy_skip("a/b/_build", sessions_rel=sr))
  // Default session store is skipped; the rest of .openseek (skills) is kept.
  assert_true(copy_skip(".openseek/sessions", sessions_rel=sr))
  assert_true(copy_skip("sub/.openseek/sessions", sessions_rel=sr))
  assert_false(copy_skip(".openseek", sessions_rel=sr))
  assert_false(copy_skip(".openseek/skills", sessions_rel=sr))
  assert_false(copy_skip(".git", sessions_rel=sr))
  assert_false(copy_skip("src", sessions_rel=sr))
}

///|
test "copy_skip follows the configured session root" {
  // A custom --session-root skips its own store, not the default path.
  assert_true(
    copy_skip("mysessions/sessions", sessions_rel="mysessions/sessions"),
  )
  assert_false(
    copy_skip(".openseek/sessions", sessions_rel="mysessions/sessions"),
  )
  // An absolute/external store (sessions_rel="") skips nothing extra.
  assert_false(copy_skip("sessions", sessions_rel=""))
  assert_false(copy_skip(".openseek/sessions", sessions_rel=""))
}

///|
test "workspace_sessions_rel derives the store path from --session-root" {
  assert_eq(workspace_sessions_rel(".openseek"), ".openseek/sessions")
  assert_eq(workspace_sessions_rel("mysessions"), "mysessions/sessions")
  assert_eq(workspace_sessions_rel("."), "sessions")
  assert_eq(workspace_sessions_rel("/abs/root"), "")
}

///|
test "has_shebang detects #! scripts" {
  assert_true(has_shebang(b"#!/bin/sh\n"))
  assert_false(has_shebang(b"echo hi\n"))
  assert_false(has_shebang(b"#"))
}

///|
test "inspect_hint adds --session-root only when non-default" {
  assert_eq(
    inspect_hint(".openseek"),
    "openseek sessions show <id> --dir <run-dir>",
  )
  assert_eq(
    inspect_hint("myroot"),
    "openseek sessions show <id> --dir <run-dir> --session-root myroot",
  )
}

///|
async test "copy_tree dereferences an in-workspace file symlink" {
  @vfs.with_tmpdir(prefix="openseek-fleet-symlink-", root => {
    let src = "\{root}/s"
    @fs.mkdir(src, recursive=true)
    @fs.write_file("\{src}/real.txt", "content", create_mode=CreateOrTruncate)
    // A relative, in-workspace symlink (like README.md -> README.mbt.md).
    @fs.symlink(target="real.txt", "\{src}/link.txt")
    let dst = "\{root}/d"
    copy_tree(
      src,
      dst,
      sessions_rel=".openseek/sessions",
      root=@fs.realpath(src),
    )
    assert_eq(@fs.read_file("\{dst}/real.txt").text(), "content")
    // The link is materialized as a regular file with the target's content.
    assert_eq(@fs.read_file("\{dst}/link.txt").text(), "content")
  })
}

///|
test "terminal_summary reads the last terminal" {
  let finished = @agent_session.Session(SessionId("t"), system_prompt="")
    .append(User(UserMessage("hi")))
    .append(Terminal(Finished("done")))
  let (status, detail) = terminal_summary(finished)
  assert_eq(status, "finished")
  assert_eq(detail, "done")
  let none = @agent_session.Session(SessionId("e"), system_prompt="")
  let (no_status, _) = terminal_summary(none)
  assert_eq(no_status, "(no terminal)")
}

///|
async test "resolve_run_dirs names siblings and reports a copy source" {
  @vfs.with_tmpdir(prefix="openseek-fleet-resolve-", root => {
    @fs.mkdir("\{root}/proj", recursive=true)
    // Existing dir → a source to copy, with sibling _run_N names.
    let (dirs, source) = resolve_run_dirs("\{root}/proj", 2)
    assert_eq(dirs.length(), 2)
    assert_true(dirs[0].has_suffix("proj_run_1"))
    assert_true(dirs[1].has_suffix("proj_run_2"))
    guard source is Some(_) else {
      fail("expected a copy source for an existing dir")
    }
    // Absent dir (parent exists) → no source (build-from-scratch).
    let (ghost_dirs, ghost_source) = resolve_run_dirs("\{root}/ghost", 1)
    assert_true(ghost_dirs[0].has_suffix("ghost_run_1"))
    guard ghost_source is None else {
      fail("expected no source for an absent dir")
    }
  })
}

///|
async test "resolve_run_dirs rejects an existing run directory" {
  @vfs.with_tmpdir(prefix="openseek-fleet-collide-", root => {
    @fs.mkdir("\{root}/proj", recursive=true)
    @fs.mkdir("\{root}/proj_run_1", recursive=true)
    let mut raised = false
    let _ = resolve_run_dirs("\{root}/proj", 2) catch {
      _ => {
        raised = true
        ([], None)
      }
    }
    assert_true(raised)
  })
}

///|
async test "copy_tree keeps files, .git dir, skills; skips build and sessions" {
  @vfs.with_tmpdir(prefix="openseek-fleet-copy-", root => {
    let src = "\{root}/s"
    @fs.mkdir("\{src}/sub", recursive=true)
    @fs.mkdir("\{src}/_build", recursive=true)
    @fs.mkdir("\{src}/.git", recursive=true)
    @fs.mkdir("\{src}/.openseek/skills", recursive=true)
    @fs.mkdir("\{src}/.openseek/sessions/old", recursive=true)
    @fs.write_file("\{src}/a.txt", "hi", create_mode=CreateOrTruncate)
    @fs.write_file("\{src}/sub/b.txt", "yo", create_mode=CreateOrTruncate)
    @fs.write_file("\{src}/_build/junk", "x", create_mode=CreateOrTruncate)
    @fs.write_file("\{src}/.git/config", "g", create_mode=CreateOrTruncate)
    @fs.write_file(
      "\{src}/.openseek/skills/s.md",
      "skill",
      create_mode=CreateOrTruncate,
    )
    @fs.write_file(
      "\{src}/.openseek/sessions/old/openseek_session-old.jsonl",
      "{}",
      create_mode=CreateOrTruncate,
    )
    let dst = "\{root}/d"
    copy_tree(
      src,
      dst,
      sessions_rel=".openseek/sessions",
      root=@fs.realpath(src),
    )
    assert_eq(@fs.read_file("\{dst}/a.txt").text(), "hi")
    assert_true(@fs.exists("\{dst}/sub/b.txt"))
    assert_true(@fs.exists("\{dst}/.git/config")) // normal .git dir kept
    assert_true(@fs.exists("\{dst}/.openseek/skills/s.md")) // skills kept
    assert_false(@fs.exists("\{dst}/_build")) // build skipped
    assert_false(@fs.exists("\{dst}/.openseek/sessions")) // session logs skipped
  })
}

///|
async test "copy_tree skips a worktree .git file (never points at the original)" {
  @vfs.with_tmpdir(prefix="openseek-fleet-worktree-", root => {
    let src = "\{root}/wt"
    @fs.mkdir(src, recursive=true)
    // A linked worktree/submodule stores .git as a *file* pointing elsewhere.
    @fs.write_file(
      "\{src}/.git",
      "gitdir: \{root}/main/.git/worktrees/wt",
      create_mode=CreateOrTruncate,
    )
    @fs.write_file("\{src}/code.mbt", "x", create_mode=CreateOrTruncate)
    let dst = "\{root}/d"
    copy_tree(
      src,
      dst,
      sessions_rel=".openseek/sessions",
      root=@fs.realpath(src),
    )
    assert_true(@fs.exists("\{dst}/code.mbt"))
    assert_false(@fs.exists("\{dst}/.git")) // worktree pointer not copied
  })
}
