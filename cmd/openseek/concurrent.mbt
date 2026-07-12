///|
/// "Best-of-N" fleet mode (`--concurrency N`, any explicit N including 1): run
/// the same task in N sibling copies of `--dir` concurrently, each recording
/// its own durable session, then print a summary. The original `--dir` is
/// never written to.
///
/// Naming uses `<base>_run_<i>` (underscores, not a dotted suffix that reads as a
/// file extension) so the run directories are unambiguous and easy to recognize.
async fn run_fleet(matches : @argparse.Matches, concurrency~ : Int) -> Unit {
  // Fleet mode owns session creation and is a one-shot batch, so it conflicts
  // with the single-session and no-session modes of `openseek run`.
  guard !(matches is { flags: { "no-session": true, .. }, .. }) else {
    fail("--concurrency records each run; remove --no-session")
  }
  let task = task_text(matches)
  let (model, thinking, api_url) = agent_settings(matches)
  let api_key = @agentcli.api_key(matches, model)
  let max_steps = max_steps(matches)
  let (session, dir_input, session_root_input) = match matches {
    {
      values: {
        "session"? : Some([session, ..])
        | (Some([])
        | None) with session = "",
        "dir": [dir, ..],
        "session-root": [session_root, ..],
        ..
      },
      ..,
    } => (session.trim(), dir, session_root)
    _ => fail("missing parsed fleet defaults")
  }
  guard session.is_empty() else {
    fail("--concurrency runs independent sessions; remove --session")
  }
  let dir = trim_trailing_path_separators("\{dir_input.trim()}")
  let (run_dirs, source) = resolve_run_dirs(dir, concurrency)
  let session_root_value = "\{session_root_input.trim()}"
  // Skip the configured session store (not just the default) so a custom
  // --session-root does not copy stale source sessions into every trial.
  let sessions_rel = workspace_sessions_rel(session_root_value)
  // Materialize each workspace before running. A present --dir is copied; an
  // absent one yields empty workspaces (build-from-scratch best-of-N), mirroring
  // how a single run creates a missing --dir. Copies are sequential to avoid
  // thrashing the disk with N concurrent deep walks.
  for run_dir in run_dirs {
    match source {
      Some(src) => copy_tree(src, run_dir, sessions_rel~, root=src)
      None => @fs.mkdir(run_dir, recursive=true)
    }
  }
  @xlog.info() <?
    { "event": "fleet_started", "runs": concurrency, "task": task }
  let outcomes : Array[AttemptOutcome?] = Array::make(concurrency, None)
  @async.with_task_group(group => {
    for i in 0..<concurrency {
      let index = i
      let run_dir = run_dirs[i]
      // allow_failure so one crashed attempt never aborts its siblings; each
      // attempt also catches internally and records a failure outcome.
      group.spawn_bg(
        () => {
          outcomes[index] = Some(
            run_one_attempt(
              index,
              run_dir,
              matches,
              model,
              task,
              max_steps~,
              thinking~,
              api_key,
              api_url,
            ),
          )
        },
        allow_failure=true,
      )
    }
  })
  print_fleet_summary(task, outcomes, session_root_value)
  guard outcomes.any(outcome => outcome is Some(result) && result.ok) else {
    fail("all \{concurrency} run(s) failed")
  }
}

///|
/// Outcome of one fleet attempt, for the summary. `ok` is true only for a
/// `finished` terminal; everything else (aborted/interrupted/failed/no terminal,
/// or a thrown error) is a non-success.
priv struct AttemptOutcome {
  index : Int
  dir : String
  session : String
  status : String
  detail : String
  ok : Bool
}

///|
/// Resolve the N run-directory paths (siblings of `--dir`) and whether there is a
/// source directory to copy. Returns `source=Some(abs)` when `--dir` exists (copy
/// it), or `None` when it is absent but its parent exists (create empty
/// workspaces). Fails if `--dir` is a file, if its parent is missing, or if a run
/// directory already exists.
async fn resolve_run_dirs(dir : String, n : Int) -> (Array[String], String?) {
  if dir.is_empty() {
    fail("--dir or OPENSEEK_DIR must not be empty")
  }
  let (parent, base, source) = if @fs.exists(dir) {
    if @fs.kind(dir) != Directory {
      fail("--dir is not a directory: \{dir}")
    }
    let abs = @fs.realpath(dir)
    (
      @path.Path(abs).dirname().to_string(),
      @path.Path(abs).basename().to_owned(),
      Some(abs),
    )
  } else {
    let parent_raw = @path.Path(dir).dirname().to_string()
    let parent_raw = if parent_raw == "" { "." } else { parent_raw }
    if !@fs.exists(parent_raw) {
      fail("parent directory for --dir does not exist: \{parent_raw}")
    }
    if @fs.kind(parent_raw) != Directory {
      fail("parent path for --dir is not a directory: \{parent_raw}")
    }
    (@fs.realpath(parent_raw), @path.Path(dir).basename().to_owned(), None)
  }
  if base.is_empty() {
    fail("cannot derive a run-directory name from --dir: \{dir}")
  }
  let run_dirs : Array[String] = []
  for i in 0..<n {
    let run_dir = @workspace_path.resolve(parent, "\{base}_run_\{i + 1}")
    if @fs.exists(run_dir) {
      fail(
        "run directory already exists: \{run_dir} (remove it or use a fresh --dir)",
      )
    }
    run_dirs.push(run_dir)
  }
  (run_dirs, source)
}

///|
/// Run one attempt in its own workspace and session, capturing the terminal as
/// an `AttemptOutcome`. Any thrown error becomes a failure outcome so one bad
/// attempt is reported, not propagated.
async fn run_one_attempt(
  index : Int,
  run_dir : String,
  matches : @argparse.Matches,
  model : @deepseek.Model,
  task : String,
  max_steps~ : Int?,
  thinking~ : @deepseek.ThinkingMode,
  api_key : String,
  api_url : String?,
) -> AttemptOutcome {
  // Generated before the try so a failed attempt can still name its (partial)
  // session in the summary for inspection.
  let id = @agent_session.SessionId::generated(
    prefix="cli",
    now_ms=@env.now().reinterpret_as_int64(),
    salt=random_salt(),
  )
  try {
    let root = session_root(matches, workspace_root=run_dir)
    let store = @store.SessionStore(root)
    let session = load_or_new_session(
      store,
      id,
      matches,
      model,
      workspace_root=run_dir,
    )
    let completed = @agent.run_turn_with_append(
      api_key~,
      model~,
      session~,
      task~,
      append_item=(session, item) => store.append(session, item),
      max_steps?,
      thinking~,
      api_url?,
      workspace_root=run_dir,
    )
    let (status, detail) = terminal_summary(completed)
    {
      index,
      dir: run_dir,
      session: id.value(),
      status,
      detail,
      // A context-ceiling yield is durably Finished (replay/chaining) but is
      // not task success for a one-shot fleet run.
      ok: status == "finished" &&
      !detail.has_prefix(@agent_session.ContextYieldAnswerPrefix),
    }
  } catch {
    error =>
      {
        index,
        dir: run_dir,
        session: id.value(),
        status: "error",
        detail: failure_message("\{error}"),
        ok: false,
      }
  }
}

///|
/// The terminal status and message of a finished run, read from its last
/// `Terminal` event. `("(no terminal)", "")` when the run recorded none.
fn terminal_summary(session : @agent_session.Session) -> (String, String) {
  let mut out = ("(no terminal)", "")
  for event in session.events() {
    if event.item() is Terminal(terminal) {
      out = match terminal {
        Finished(answer) => ("finished", answer)
        Aborted(reason) => ("aborted", reason)
        Interrupted(reason) => ("interrupted", reason)
        Failed(message) => ("failed", message)
      }
    }
  }
  out
}

///|
/// Recursively copy `src` into `dst`. A normal `.git` directory is copied (so the
/// copy is a self-contained repo); a worktree/submodule `.git` *file* is dropped
/// because it points back at the original repo and copying it would let git in
/// the copy mutate the original — the trade-off is that a copied linked worktree
/// is not itself a git checkout. Files are copied byte-for-byte, preserving the
/// executable bit for shebang scripts (the fs API exposes no source mode). A
/// symlink to a regular file inside the workspace is dereferenced (there is no
/// readlink to recreate the link); other symlinks and special files are skipped.
/// `root` is the absolute source root (for the in-workspace check) and `rel` the
/// path within it (for path-aware skipping). `dst` and parents are made.
async fn copy_tree(
  src : String,
  dst : String,
  sessions_rel~ : String,
  root~ : String,
  rel? : String = "",
) -> Unit {
  @fs.mkdir(dst, recursive=true)
  for name in @fs.readdir(src, include_hidden=true, sort=true) {
    let child_rel = if rel == "" { name } else { "\{rel}/\{name}" }
    if copy_skip(child_rel, sessions_rel~) {
      continue
    }
    let s = @workspace_path.resolve(src, name)
    let d = @workspace_path.resolve(dst, name)
    match @fs.kind(s, follow_symlink=false) {
      Directory => copy_tree(s, d, sessions_rel~, root~, rel=child_rel)
      // A `.git` file is a worktree/submodule pointer at the original repo; skip
      // it so git in the copy can never write the original.
      Regular => if name != ".git" { copy_regular(s, d) }
      SymLink => copy_symlink(s, d, root)
      _ => () // sockets, pipes, devices skipped
    }
  }
}

///|
/// Copy a regular file byte-for-byte, preserving the executable bit for shebang
/// scripts (the fs API exposes no source mode to copy).
async fn copy_regular(s : String, d : String) -> Unit {
  let data = @fs.read_file(s).binary()
  @fs.write_file(d, data, create_mode=CreateOrTruncate)
  if has_shebang(data) {
    @fs.chmod(d, 0o755) catch {
      _ => ()
    }
  }
}

///|
/// There is no readlink to recreate a symlink, so dereference one that resolves
/// to a regular file inside the workspace (e.g. `README.md -> README.mbt.md`),
/// copying its content. Broken, directory, and out-of-workspace targets are
/// skipped to avoid loops or escaping `--dir`.
async fn copy_symlink(s : String, d : String, root : String) -> Unit {
  let resolved = @fs.realpath(s) catch { _ => return }
  guard within_root(resolved, root) else { return }
  let target_kind = @fs.kind(s, follow_symlink=true) catch { _ => return }
  match target_kind {
    Regular => copy_regular(s, d)
    _ => () // directory/other targets skipped (loop-safe)
  }
}

///|
/// Whether absolute `path` is `root` or nested under it.
fn within_root(path : String, root : String) -> Bool {
  path == root || path.has_prefix("\{root}/")
}

///|
/// Paths (relative to the source) never copied into a trial workspace: build
/// output and vendored deps anywhere, and the durable session store
/// (`sessions_rel`, derived from `--session-root` — `.openseek/sessions` by
/// default), since each trial records its own. Workspace skills under
/// `.openseek/skills` are deliberately kept so a trial behaves like a normal run.
/// `sessions_rel` is `""` when the session store lives outside the workspace.
fn copy_skip(rel : String, sessions_rel~ : String) -> Bool {
  let base = match rel.rev_split_once("/") {
    Some((_, base)) => base
    None => rel
  }
  if base == "_build" || base == "node_modules" {
    return true
  }
  sessions_rel != "" &&
  (rel == sessions_rel || rel.has_suffix("/\{sessions_rel}"))
}

///|
/// The workspace-relative session-store path to skip when copying, derived from
/// the configured `--session-root`. `""` when the store is configured outside the
/// workspace (an absolute root), so nothing inside the copy needs skipping.
fn workspace_sessions_rel(session_root_value : String) -> String {
  let root = trim_trailing_path_separators("\{session_root_value.trim()}")
  if root == "" || @path.Path(root).is_absolute() {
    ""
  } else if root == "." {
    "sessions"
  } else {
    "\{root}/sessions"
  }
}

///|
/// Whether `data` starts with a `#!` shebang, marking an executable script whose
/// executable bit should survive the copy.
fn has_shebang(data : Bytes) -> Bool {
  data.length() >= 2 && data[0].to_int() == 0x23 && data[1].to_int() == 0x21
}

///|
/// The summary's "inspect a run" command. Includes `--session-root` only when it
/// is non-default, since each run records its session under that root inside its
/// run directory, and `sessions show` resolves the root relative to `--dir`.
fn inspect_hint(session_root_value : String) -> String {
  let root = session_root_value.trim()
  let extra = if root == "" || root == ".openseek" {
    ""
  } else {
    " --session-root \{root}"
  }
  "openseek sessions show <id> --dir <run-dir>\{extra}"
}

///|
/// Print the fleet summary to stderr (stdout stays the JSONL event stream): a
/// header line plus one row per attempt, and where to view the results.
async fn print_fleet_summary(
  task : String,
  outcomes : Array[AttemptOutcome?],
  session_root_value : String,
) -> Unit {
  let total = outcomes.length()
  let finished = outcomes
    .iter()
    .count_if(outcome => outcome is Some(result) && result.ok)
  let lines : Array[String] = [
    "",
    "openseek: \{total} run(s) of \"\{one_line_brief(task, 60)}\" — \{finished} finished, \{total - finished} not",
  ]
  for outcome in outcomes {
    match outcome {
      Some(result) =>
        lines.push(
          "  #\{result.index + 1}  \{result.status}  \{result.session}  \{result.dir}  \{one_line_brief(result.detail, 60)}",
        )
      None => lines.push("  (run did not report)")
    }
  }
  lines.push("")
  lines.push("inspect a run:  \{inspect_hint(session_root_value)}")
  lines.push("")
  @stdio.stderr.write(lines.join("\n")) catch {
    _ => ()
  }
}

///|
/// Collapse to a single trimmed line capped at `max` characters (ellipsis when
/// cut), iterating by character so a cap never splits a surrogate pair.
fn one_line_brief(text : String, max : Int) -> String {
  let one = text.replace_all(old="\n", new=" ").trim()
  if one.length() <= max {
    "\{one}"
  } else {
    let kept = StringBuilder()
    for ch in one.iter().take(max) {
      kept.write_char(ch)
    }
    kept.write_char('…')
    kept.to_string()
  }
}

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
