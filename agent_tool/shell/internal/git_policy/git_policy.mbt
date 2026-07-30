// Pure git command-line policy for the shell source-write sandbox: parse a git
// invocation's subcommand and classify it. No filesystem, workspace, or
// shell-parse dependencies — just argv/word grammar — so the policy can be read
// and tested in isolation. The `shell` package supplies the workspace-path glue
// and the trusted-command-class wiring.

///|
/// A parsed git invocation: the subcommand and its index in `argv`.
pub struct Invocation {
  subcommand : String
  subcommand_index : Int
}

///|
/// Parse a git invocation starting at `arg_start` (the index just past `git`),
/// skipping global options, and return its subcommand and that subcommand's argv
/// index. Returns `None` for `--help`/`-h`, an explicit `--`, a missing argument
/// to a value option, or an unrecognized `-option` (fail closed). Aliases are not
/// resolved, so e.g. `git co` reports subcommand `co`.
pub fn parse(argv : Array[String], arg_start : Int) -> Invocation? {
  let mut index = arg_start
  while index < argv.length() {
    let arg = argv[index]
    if arg == "--" || arg == "--help" || arg == "-h" {
      return None
    }
    if arg == "-C" || arg == "--work-tree" || global_option_consumes_next(arg) {
      if index + 1 >= argv.length() {
        return None
      }
      index += 2
      continue
    }
    if attached_cwd_option(arg) is Some(_) ||
      attached_work_tree_option(arg) is Some(_) ||
      global_option_with_attached_value(arg) ||
      global_no_arg_option(arg) {
      index += 1
      continue
    }
    if arg.has_prefix("-") && arg != "-" {
      return None
    }
    return Some({ subcommand: arg, subcommand_index: index })
  }
  None
}

///|
/// True for a git global option that repoints config, the exec path, the git
/// dir, the namespace, or the cwd/worktree — a precursor that could make an
/// otherwise object-store subcommand write arbitrary bytes (via a smudge filter
/// or merge driver) or write the workspace from a different repository.
pub fn global_option_reconfigures(arg : String) -> Bool {
  global_option_consumes_next(arg) ||
  global_option_with_attached_value(arg) ||
  arg == "-C" ||
  arg == "--work-tree" ||
  attached_cwd_option(arg) is Some(_) ||
  attached_work_tree_option(arg) is Some(_)
}

///|
/// Git subcommands whose every worktree change either materializes content from
/// git's own object store (HEAD, the index, a commit/tree, or a stash) or removes
/// a tracked file recoverable from it — reviewable through git, never sourced from
/// an external file or stdin. Excluded: `mv` (moves arbitrary worktree bytes onto
/// the destination) and `clean` (deletes UNTRACKED files with no object-store
/// copy — permanent). `rm` stays: it only deletes tracked files.
pub fn subcommand_writes_from_object_store(subcommand : String) -> Bool {
  match subcommand {
    "checkout" | "switch" | "restore" | "reset" | "stash" | "rm" => true
    _ => false
  }
}

///|
/// Whether a `git worktree` invocation (args in `words[start..end)`, starting at
/// the verb) is a recoverable write. `add` qualifies with any flags: git
/// unconditionally refuses an existing non-empty (or file) target — `--force`
/// only relaxes the branch-checked-out-elsewhere and registered-but-missing-path
/// safeguards — so it only creates new paths whose content comes from the object
/// store, and a `-B` branch reset is reflog-recoverable like trusted `reset`.
/// `remove` qualifies only without force: git then refuses a worktree containing
/// modified or untracked files, so everything deleted is tracked and clean
/// (ignored files go silently — the same exposure as trusted `checkout`).
/// `prune` touches only `$GIT_DIR/worktrees` admin data. Everything else fails
/// closed: `list` is read-only and runs fine sandboxed, `move` relocates
/// arbitrary worktree bytes like the excluded `mv`.
pub fn worktree_args_are_recoverable(
  words : Array[String],
  start : Int,
  end : Int,
) -> Bool {
  guard start < end else { return false }
  match words[start] {
    "add" | "prune" => true
    "remove" => {
      for index in (start + 1)..<end {
        let arg = words[index]
        // `--force`, or `-f` possibly clustered (`-ff`). A path named `-f`
        // after `--` also matches — a conservative false positive that only
        // drops the command back into the sandbox.
        if arg == "--force" || short_cluster_has(arg, "f") {
          return false
        }
      }
      true
    }
    _ => false
  }
}

///|
/// Whether a git invocation must be pre-blocked before execution — the
/// cross-platform guard that does not depend on the runtime sandbox. Conservative
/// by design: block the git that mutates source but is NOT a recoverable
/// object-store write — store feeders (`apply`/`am`/`update-index`/`read-tree`/
/// `fast-import`), `mv` (moves arbitrary worktree bytes), non-dry-run `clean`
/// (permanently deletes untracked files), and any object-store writer that is
/// reconfigured (`git -c filter=… checkout`, `-C`, `--work-tree`). The recoverable
/// writers (`checkout`/`switch`/`restore`/`reset`/`stash`/`rm`) and read-only git
/// are not pre-blocked; they run (trusted, or sandboxed where they cannot harm).
pub fn should_preblock(argv : Array[String], arg_start : Int) -> Bool {
  guard parse(argv, arg_start) is Some(invocation) else { return false }
  preblock_for_subcommand(
    argv,
    arg_start,
    invocation.subcommand_index,
    argv.length(),
  )
}

///|
/// The TooComplex text-path counterpart of `should_preblock`, scanning a flat
/// `words` list over `[start, end)`. Returns false when the subcommand requests
/// help.
pub fn text_should_preblock(
  words : Array[String],
  start : Int,
  end : Int,
) -> Bool {
  guard text_subcommand_index(words, start, end) is Some(subcommand_index) else {
    return false
  }
  preblock_for_subcommand(words, start, subcommand_index, end)
}

///|
/// Whether the git subcommand found in `words[start..end)` is a recoverable
/// object-store writer (checkout/switch/restore/reset/stash/rm). The text path
/// uses this to decide whether a custom environment before `git` (which it cannot
/// see in `words[start..]`) makes the writer unsafe and must be pre-blocked.
pub fn text_invocation_writes_from_object_store(
  words : Array[String],
  start : Int,
  end : Int,
) -> Bool {
  match text_subcommand_index(words, start, end) {
    Some(subcommand_index) =>
      subcommand_writes_from_object_store(words[subcommand_index])
    None => false
  }
}

///|
fn preblock_for_subcommand(
  words : Array[String],
  global_start : Int,
  subcommand_index : Int,
  end : Int,
) -> Bool {
  let args_start = subcommand_index + 1
  if args_start < end &&
    (words[args_start] == "--help" || words[args_start] == "-h") {
    return false
  }
  match words[subcommand_index] {
    // `apply` writes unless it is a read-only validation/info mode (`--check`,
    // `--stat`, `--numstat`, `--summary`) with no forced application.
    "apply" => apply_writes(words, args_start, end)
    "am" | "update-index" | "read-tree" | "fast-import" | "mv" => true
    // `clean` permanently deletes untracked files unless it is a dry run.
    "clean" => !clean_args_request_dry_run(words, args_start, end)
    // checkout/switch/restore can overwrite an UNTRACKED file at a path when
    // forced or sourced from another tree (`-f`/`--force`/`--source`/`--overlay`/
    // `--ours`/`--theirs`), permanently losing it (git's own untracked guard is
    // bypassed). Plain index restore (`git checkout -- f`) is fine.
    "checkout" | "switch" | "restore" =>
      region_reconfigures(words, global_start, subcommand_index) ||
      overwrites_untracked_from_tree(words, args_start, end)
    // The other recoverable writers are only unsafe when reconfigured.
    subcommand =>
      subcommand_writes_from_object_store(subcommand) &&
      region_reconfigures(words, global_start, subcommand_index)
  }
}

///|
/// True when a `checkout`/`switch`/`restore` form can overwrite an untracked file
/// from another tree: a force/overlay/side flag, an explicit source tree-ish
/// (`--source`/`--source=`/`-s`/`-s<tree>`), or a positional tree-ish before
/// `--` (`git checkout <tree-ish> -- <path>`). Plain index restore
/// (`git checkout -- f`, `git restore f`) and bare branch switch are excluded.
fn overwrites_untracked_from_tree(
  words : Array[String],
  start : Int,
  end : Int,
) -> Bool {
  let mut positional_before_paths = false
  for index in start..<end {
    let arg = words[index]
    // Force / overlay / side-pick overwrite regardless of untracked state. `-f`
    // may be clustered (`-fB`, `-fq`), so match it inside a short cluster too.
    if arg == "--force" ||
      arg == "--overlay" ||
      arg == "--ours" ||
      arg == "--theirs" ||
      short_cluster_has(arg, "f") {
      return true
    }
    // Explicit source tree-ish: `--source`, `--source=<t>`, `-s`, `-s<t>`.
    if arg == "--source" ||
      arg.has_prefix("--source=") ||
      arg == "-s" ||
      (arg.has_prefix("-s") && !arg.has_prefix("--")) {
      return true
    }
    // `--`, or `--pathspec-from-file`, ends the tree-ish/pathspec boundary; a
    // positional tree-ish before it (`git checkout HEAD~1 -- f`, or
    // `git checkout HEAD~1 --pathspec-from-file=list`) sources the paths from it.
    if arg == "--" ||
      arg == "--pathspec-from-file" ||
      arg.has_prefix("--pathspec-from-file=") {
      return positional_before_paths
    }
    if !arg.has_prefix("-") {
      positional_before_paths = true
    }
  }
  false
}

///|
/// True when `arg` is a short option cluster (`-…`, not `--…`) containing `flag`.
fn short_cluster_has(arg : String, flag : String) -> Bool {
  arg.has_prefix("-") &&
  !arg.has_prefix("--") &&
  arg != "-" &&
  arg.contains(flag)
}

///|
/// `git apply` writes the worktree/index unless it runs in a read-only
/// validation/info mode (`--check`/`--stat`/`--numstat`/`--summary`) and is not
/// forced to apply (`--apply`/`--cached`/`--index`/`--3way`). Conservative: a
/// read-only flag alongside any forcing flag is treated as writing.
fn apply_writes(words : Array[String], start : Int, end : Int) -> Bool {
  let mut read_only = false
  let mut forced = false
  for index in start..<end {
    match words[index] {
      "--check" | "--stat" | "--numstat" | "--summary" => read_only = true
      "--apply" | "--cached" | "--index" | "--3way" | "-3" => forced = true
      _ => ()
    }
  }
  forced || !read_only
}

///|
fn region_reconfigures(words : Array[String], start : Int, end : Int) -> Bool {
  for index in start..<end {
    if global_option_reconfigures(words[index]) {
      return true
    }
  }
  false
}

///|
/// True when `git clean`'s arguments request a dry run (`-n`, `--dry-run`, or a
/// short cluster such as `-fdn`; in git clean `n` always means dry run). An
/// exclude option (`-e`/`--exclude`/a cluster with `e`) takes a pattern operand
/// that could itself look like `-n` (`git clean -e -n -fd` is destructive), so
/// rather than parse git's getopt clustering this conservatively treats any clean
/// carrying an exclude as NOT a dry run — it stays blocked.
fn clean_args_request_dry_run(
  words : Array[String],
  start : Int,
  end : Int,
) -> Bool {
  let mut dry_run = false
  for index in start..<end {
    let arg = words[index]
    if clean_arg_is_exclude(arg) {
      return false
    }
    if arg == "-n" ||
      arg == "--dry-run" ||
      (arg.has_prefix("-") && !arg.has_prefix("--") && arg.contains("n")) {
      dry_run = true
    }
  }
  dry_run
}

///|
fn clean_arg_is_exclude(arg : String) -> Bool {
  arg == "-e" ||
  arg == "--exclude" ||
  arg.has_prefix("--exclude=") ||
  (arg.has_prefix("-") && !arg.has_prefix("--") && arg.contains("e"))
}

///|
/// Find the git subcommand's index in a flat `words` list (the TooComplex text
/// path), scanning `[start, end)` and skipping global options. Mirrors `parse`.
fn text_subcommand_index(words : Array[String], start : Int, end : Int) -> Int? {
  let mut index = start
  while index < end {
    let arg = words[index]
    if arg == "--help" || arg == "-h" {
      return None
    }
    if arg == "-C" || arg == "--work-tree" || global_option_consumes_next(arg) {
      index += 2
      continue
    }
    if attached_cwd_option(arg) is Some(_) ||
      attached_work_tree_option(arg) is Some(_) ||
      global_option_with_attached_value(arg) ||
      global_no_arg_option(arg) {
      index += 1
      continue
    }
    if arg.has_prefix("-") && arg != "-" {
      return None
    }
    return Some(index)
  }
  None
}

///|
fn global_option_consumes_next(arg : String) -> Bool {
  arg == "-c" ||
  arg == "--config-env" ||
  arg == "--exec-path" ||
  arg == "--git-dir" ||
  arg == "--namespace"
}

///|
fn global_option_with_attached_value(arg : String) -> Bool {
  (arg.has_prefix("-c") && arg != "-c") ||
  arg.has_prefix("--config-env=") ||
  arg.has_prefix("--exec-path=") ||
  arg.has_prefix("--git-dir=") ||
  arg.has_prefix("--namespace=")
}

///|
fn global_no_arg_option(arg : String) -> Bool {
  match arg {
    "--version"
    | "--help"
    | "-p"
    | "--paginate"
    | "-P"
    | "--no-pager"
    | "--no-replace-objects"
    | "--no-optional-locks"
    | "--no-lazy-fetch"
    | "--literal-pathspecs"
    | "--glob-pathspecs"
    | "--noglob-pathspecs"
    | "--icase-pathspecs"
    | "--bare" => true
    _ => false
  }
}

///|
/// Returns a view into `arg` (not an owned copy): every caller only tests
/// `is Some(_)`, so materializing the value would allocate for nothing.
fn attached_cwd_option(arg : String) -> StringView? {
  if arg.strip_prefix("-C") is Some(value) && !value.is_empty() {
    Some(value)
  } else {
    None
  }
}

///|
fn attached_work_tree_option(arg : String) -> StringView? {
  if arg.strip_prefix("--work-tree=") is Some(value) {
    Some(value)
  } else {
    None
  }
}
