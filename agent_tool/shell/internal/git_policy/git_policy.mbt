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
  guard text_subcommand_index(argv, arg_start, argv.length()) is Some(index) else {
    return None
  }
  Some({ subcommand: argv[index], subcommand_index: index, })
}

///|
/// True for a git global option that repoints config, the exec path, the git
/// dir, the namespace, or the cwd/worktree — a precursor that could make an
/// otherwise recognized subcommand write arbitrary bytes (via a smudge filter
/// or merge driver) or target the workspace from a different repository.
pub fn global_option_reconfigures(arg : String) -> Bool {
  global_option_consumes_next(arg) ||
  global_option_with_attached_value(arg) ||
  arg == "-C" ||
  arg == "--work-tree" ||
  attached_cwd_option(arg) is Some(_) ||
  attached_work_tree_option(arg) is Some(_)
}

///|
/// Whether `subcommand` is a recognized first-party porcelain command. These
/// commands may compose with a trusted worktree-writing git command without
/// forcing the whole shell chain back into the source-write sandbox. Aliases,
/// plumbing, and external `git-foo` commands are deliberately absent: their
/// behavior cannot be inferred from the command name alone.
pub fn subcommand_is_recognized_porcelain(subcommand : String) -> Bool {
  match subcommand {
    "add"
    | "am"
    | "annotate"
    | "apply"
    | "bisect"
    | "blame"
    | "branch"
    | "checkout"
    | "cherry"
    | "cherry-pick"
    | "clean"
    | "clone"
    | "commit"
    | "describe"
    | "diff"
    | "fetch"
    | "fsck"
    | "gc"
    | "grep"
    | "init"
    | "log"
    | "maintenance"
    | "merge"
    | "merge-base"
    | "merge-tree"
    | "mv"
    | "notes"
    | "pull"
    | "push"
    | "range-diff"
    | "rebase"
    | "reflog"
    | "remote"
    | "reset"
    | "restore"
    | "revert"
    | "rm"
    | "shortlog"
    | "show"
    | "show-branch"
    | "sparse-checkout"
    | "stash"
    | "status"
    | "submodule"
    | "switch"
    | "tag"
    | "verify-commit"
    | "verify-tag"
    | "whatchanged"
    | "worktree" => true
    _ => false
  }
}

///|
/// Whether the porcelain command may update or remove files in a worktree.
/// This is intentionally command-level, not an assertion that every invocation
/// writes: for example `git apply --check` and `git clean -n` are harmless but
/// share a command name with writing forms. `should_preblock` handles the
/// dangerous argument forms before the trust classifier consults this list.
pub fn subcommand_may_write_worktree(subcommand : String) -> Bool {
  match subcommand {
    "am"
    | "apply"
    | "bisect"
    | "checkout"
    | "cherry-pick"
    | "clean"
    | "clone"
    | "merge"
    | "mv"
    | "pull"
    | "rebase"
    | "reset"
    | "restore"
    | "revert"
    | "rm"
    | "sparse-checkout"
    | "stash"
    | "submodule"
    | "switch"
    | "worktree" => true
    _ => false
  }
}

///|
/// Whether a git invocation must be pre-blocked before execution — the
/// cross-platform guard that does not depend on the runtime sandbox. Conservative
/// by design: block the git forms that import arbitrary bytes, permanently lose
/// untracked data, or explicitly run external commands. Recognized first-party
/// porcelain not matched here is allowed to compose; aliases, plumbing, and
/// external `git-foo` commands still fail closed in the trust classifier.
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
/// Whether the git subcommand found in `words[start..end)` may write a
/// worktree. The text path uses this to decide whether a custom environment
/// before `git` (which it cannot see in `words[start..]`) makes the invocation
/// unsafe and must be pre-blocked.
pub fn text_invocation_may_write_worktree(
  words : Array[String],
  start : Int,
  end : Int,
) -> Bool {
  match text_subcommand_index(words, start, end) {
    Some(subcommand_index) =>
      subcommand_may_write_worktree(words[subcommand_index])
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
    // rebase replays object-store commits (recoverable via ORIG_HEAD/reflog),
    // but its command-running forms execute arbitrary commands and must never
    // run; a reconfigured rebase is unsafe like the other writers.
    "rebase" =>
      region_reconfigures(words, global_start, subcommand_index) ||
      rebase_args_run_external_commands(words, args_start, end)
    // A merge strategy is resolved as `git-merge-<strategy>` and can run an
    // external executable. `pull` forwards the same options to merge and also
    // exposes an interactive rebase mode.
    "merge" =>
      region_reconfigures(words, global_start, subcommand_index) ||
      merge_strategy_args_run_external_command(words, args_start, end, true)
    "pull" =>
      region_reconfigures(words, global_start, subcommand_index) ||
      merge_strategy_args_run_external_command(words, args_start, end, true) ||
      pull_args_request_interactive_rebase(words, args_start, end)
    // Cherry-pick/revert use `-s` for signoff, so only `-X` and the long
    // strategy spellings select a merge strategy here.
    "cherry-pick" | "revert" =>
      region_reconfigures(words, global_start, subcommand_index) ||
      merge_strategy_args_run_external_command(words, args_start, end, false)
    // `bisect run` executes the remaining argv as an arbitrary command.
    "bisect" =>
      region_reconfigures(words, global_start, subcommand_index) ||
      bisect_args_run_external_command(words, args_start, end)
    // `submodule update` checks out commits from the object store (like
    // checkout), but its command-running and data-losing forms are pre-blocked:
    // `foreach` executes arbitrary shell commands in each submodule, and forced
    // `update`/`deinit` permanently lose dirty or untracked content. An
    // unrecognized leading option fails closed too.
    "submodule" =>
      region_reconfigures(words, global_start, subcommand_index) ||
      submodule_verb_is_unsafe(words, args_start, end)
    // `worktree move` relocates arbitrary bytes and forced `remove` destroys
    // modified/untracked files. The other verbs may write but remain allowed.
    "worktree" =>
      region_reconfigures(words, global_start, subcommand_index) ||
      worktree_verb_is_unsafe(words, args_start, end)
    // Every other recognized worktree writer is unsafe when reconfigured.
    subcommand =>
      subcommand_may_write_worktree(subcommand) &&
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
/// True when some argument in `words[start..end)` before a `--` terminator
/// satisfies `matches`. Every option scan here stops at `--`: past it every
/// word is an operand, and an operand cannot be an option.
fn any_arg_before_ddash(
  words : Array[String],
  start : Int,
  end : Int,
  matches : (String) -> Bool,
) -> Bool {
  for index in start..<end {
    let arg = words[index]
    if arg == "--" {
      return false
    }
    if matches(arg) {
      return true
    }
  }
  false
}

///|
/// Whether a `git rebase` invocation's arguments (in `words[start..end)`)
/// request running external commands: `-i`/`--interactive` (sequence-editor
/// driven, `exec` todo lines), `--edit-todo` (opens the todo in an editor),
/// `-x`/`--exec` (a shell command per commit), or a merge strategy
/// (`-s`/`--strategy` resolves a `git-merge-<s>` executable from the exec
/// path; `-X`/`--strategy-option` is grouped with it conservatively). These
/// are pre-blocked cross-platform: on a platform without `sandbox-exec` they
/// would otherwise run arbitrary commands. Long options match by prefix
/// because git accepts unambiguous abbreviations (`--exe=cmd` runs the
/// command; an ambiguous prefix such as `--e` just errors in git, so
/// over-matching is harmless in a pre-block); short options match inside
/// clusters and attached-value forms (`-iv`, `-xcmd`). The scan stops at `--`:
/// past it every word is a revision, and a revision cannot begin with a dash.
fn rebase_args_run_external_commands(
  words : Array[String],
  start : Int,
  end : Int,
) -> Bool {
  any_arg_before_ddash(words, start, end, rebase_arg_runs_external_commands)
}

///|
fn rebase_arg_runs_external_commands(arg : String) -> Bool {
  if arg.has_prefix("--") {
    return long_option_selects(arg, "--interactive") ||
      long_option_selects(arg, "--exec") ||
      long_option_selects(arg, "--edit-todo") ||
      long_option_selects(arg, "--strategy") ||
      long_option_selects(arg, "--strategy-option")
  }
  short_cluster_has(arg, "i") ||
  short_cluster_has(arg, "x") ||
  short_cluster_has(arg, "s") ||
  short_cluster_has(arg, "X")
}

///|
/// Whether merge-family arguments explicitly select a merge strategy or
/// strategy option. Git may resolve the strategy through its exec path, so
/// these forms can launch an external executable. For merge/pull `-s` means
/// strategy; for cherry-pick/revert it means signoff and stays allowed.
fn merge_strategy_args_run_external_command(
  words : Array[String],
  start : Int,
  end : Int,
  short_s_is_strategy : Bool,
) -> Bool {
  any_arg_before_ddash(words, start, end, arg => {
    (
      arg.has_prefix("--") &&
      (
        long_option_selects(arg, "--strategy") ||
        long_option_selects(arg, "--strategy-option")
      )
    ) ||
    short_cluster_has(arg, "X") ||
    (short_s_is_strategy && short_cluster_has(arg, "s"))
  })
}

///|
/// `git pull --rebase=interactive` enters the sequence-editor path just like an
/// interactive rebase. Git accepts the short `i` value; prefix matching also
/// fails closed for future/abbreviated spellings beginning with `i`.
fn pull_args_request_interactive_rebase(
  words : Array[String],
  start : Int,
  end : Int,
) -> Bool {
  any_arg_before_ddash(words, start, end, arg => arg.has_prefix("--rebase=i"))
}

///|
/// `git bisect run <command>...` executes an arbitrary program repeatedly.
fn bisect_args_run_external_command(
  words : Array[String],
  start : Int,
  end : Int,
) -> Bool {
  start < end && words[start] == "run"
}

///|
/// Worktree operations with unrecoverable effects: `move` relocates arbitrary
/// bytes, while forced `remove` deletes modified and untracked files. Long
/// force abbreviations such as `--fo` count because git accepts them.
fn worktree_verb_is_unsafe(
  words : Array[String],
  start : Int,
  end : Int,
) -> Bool {
  guard start < end else { return false }
  if words[start] == "move" {
    return true
  }
  if words[start] != "remove" {
    return false
  }
  any_arg_before_ddash(words, start + 1, end, arg => {
    long_option_selects(arg, "--force") || short_cluster_has(arg, "f")
  })
}

///|
/// Whether `arg` selects the long option `full`, accepting git's
/// unambiguous-abbreviation forms and an attached value: for
/// `full == "--exec"`, the args `--exec`, `--exe`, and `--exe=cmd` all match.
/// The name must extend past the bare `--` terminator, which never matches.
fn long_option_selects(arg : String, full : String) -> Bool {
  let name = match [..arg.split("=")] {
    [name, _, ..] => name.to_owned()
    _ => arg
  }
  name.length() > 2 && full.has_prefix(name)
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
/// Find the git subcommand's index in a flat `words` list, scanning
/// `[start, end)` and skipping global options. The scanner behind both the
/// TooComplex text path and `parse`. An explicit `--` is rejected by the
/// trailing unrecognized-option arm, and a value option with no argument runs
/// `index` past `end` and so falls out as `None`.
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
  arg is ("-c" | "--config-env" | "--exec-path" | "--git-dir" | "--namespace")
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

///|
/// Find the `git submodule` verb in `words[start..end)`, skipping the
/// recognized leading submodule options (`--quiet`/`-q` — the only global
/// submodule options per `git submodule -h`). Returns the verb's index, or
/// `None` for a missing verb or an unrecognized leading option (fail closed).
/// A `--help`/`-h` request also returns `None`; callers decide separately
/// whether the invocation is a help request.
fn submodule_verb_index(words : Array[String], start : Int, end : Int) -> Int? {
  let mut index = start
  while index < end {
    let arg = words[index]
    if arg == "--quiet" || arg == "-q" {
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
/// True when a `git submodule update`/`deinit` invocation carries
/// `-f`/`--force` (also inside a short cluster). A forced update replaces
/// untracked files in a dirty submodule with the target commit's contents, and
/// a forced deinit removes a submodule worktree even with local changes — both
/// permanently lose data that has no object-store copy. The scan stops at `--`,
/// past which every word is a path.
fn submodule_forced(words : Array[String], start : Int, end : Int) -> Bool {
  any_arg_before_ddash(words, start, end, arg => {
    arg == "--force" || short_cluster_has(arg, "f")
  })
}

///|
/// Whether a `git submodule` invocation must be pre-blocked: `foreach` (runs an
/// arbitrary shell command in each submodule — the only exception is a bare
/// `--help` immediately after the verb, not trailing a command argument), and
/// `update`/`deinit` with `-f`/`--force` (permanently lose dirty or untracked
/// content). An absent verb (bare `git submodule`) is the implicit `status`
/// form — not preblocked. Unrecognized leading options still fail closed.
fn submodule_verb_is_unsafe(
  words : Array[String],
  start : Int,
  end : Int,
) -> Bool {
  match submodule_verb_index(words, start, end) {
    None => false
    Some(verb_index) =>
      match words[verb_index] {
        "foreach" =>
          !submodule_foreach_is_help_request(words, verb_index + 1, end)
        "update" | "deinit" => submodule_forced(words, verb_index + 1, end)
        _ => false
      }
  }
}

///|
/// True when a `git submodule foreach` invocation is a bare help request:
/// `foreach --help` or `foreach --recursive --help`. Once a positional command
/// argument appears, `--help` at the end is part of the shell command being
/// executed, not a git help flag — so it does NOT bypass the preblock.
fn submodule_foreach_is_help_request(
  words : Array[String],
  start : Int,
  end : Int,
) -> Bool {
  let mut index = start
  while index < end {
    let arg = words[index]
    if arg == "--help" || arg == "-h" {
      return true
    }
    if arg == "--recursive" {
      index += 1
      continue
    }
    // Anything else (including other flags) starts the positional command.
    return false
  }
  false
}
