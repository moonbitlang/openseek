///|
/// The commands a snippet may spawn, as `moonrun --policy` process rules.
///
/// This list is the agent's command vocabulary, not a security perimeter: the
/// programs on it can themselves run code (`moon run` compiles and runs a
/// program, `git` honours hooks), so what it buys is the LONG TAIL — an
/// arbitrary downloaded binary, `rm -rf /`, `curl | sh` — none of which a
/// legitimate turn needs.
///
/// Nothing confines where the admitted programs then write: moonrun's `fs`
/// section binds the snippet and stops at the process boundary. What this list
/// can still say is which FORM of a command exists, and the git rules use it:
/// the options that would point git at another repository (`-C`, `--git-dir`,
/// `--work-tree`) precede the subcommand, so they match no prefix rule below.
///
/// Entries are `(program, args_prefix)`. An empty prefix allows any arguments.
/// A prefix matches whole argument tokens from the front, so `moon` with
/// `["test"]` allows `moon test --filter x` but not `moon build`.
///
/// Which prose teaches this list is a separate decision — today it is each
/// role's system prompt. Admitting a command here without adding it there costs
/// a turn steps, since the model never learns it may use it.
let spawnable_commands : Array[(String, Array[String])] = [
  // The MoonBit toolchain, which is most of what a turn runs. Listed per
  // subcommand rather than as a bare `moon` so the set is reviewable, and so
  // adding a new one is a deliberate edit.
  ("moon", ["check"]),
  ("moon", ["test"]),
  ("moon", ["build"]),
  // `moon run` is how a turn exercises a binary it just built: a freshly
  // compiled executable can never be on this list — its name did not exist
  // when the list was written — so without `moon run` the whole shape of task
  // "write a CLI, then probe its behaviour" is unreachable.
  //
  // It was briefly withheld on the grounds that it recovers an unconstrained
  // native process. That was not a real distinction: `moon test` compiles and
  // runs workspace code natively too, and no `fs` rule of this policy reaches
  // any child. The `target: "native"` refusal in `decode` keeps the SNIPPET
  // under policy; it was never a boundary around what the snippet may start.
  ("moon", ["run"]),
  ("moon", ["fmt"]),
  ("moon", ["info"]),
  ("moon", ["add"]),
  ("moon", ["remove"]),
  ("moon", ["update"]),
  ("moon", ["install"]),
  ("moon", ["tree"]),
  ("moon", ["clean"]),
  ("moon", ["new"]),
  ("moon", ["ide"]),
  ("moon", ["doc"]),
  ("moon", ["explain"]),
  ("moon", ["coverage"]),
  ("moon", ["cram"]),
  ("moon", ["version"]),
  // Asking what is installed is the first thing a turn does when something
  // looks wrong with the toolchain, and it is spelled with the FLAG far more
  // often than with the subcommand. Listing only `version` left `moon
  // --version` matching no rule: a live run spent three attempts on it —
  // plain, then with a rebuilt `PATH`, then by absolute path — reading each
  // refusal as a broken toolchain rather than as this list. `git --version` was
  // already here; the asymmetry was an oversight, not a decision.
  ("moon", ["--version"]),
  ("moon", ["--help"]),
  // Version control, listed per subcommand for two reasons. The obvious one is
  // that whole dangerous subcommands can be left out. The second falls out of
  // how prefixes match: git's reconfiguring GLOBAL options come BEFORE the
  // subcommand, so `git -c core.pager=CMD status` has args starting with `-c`
  // and matches no rule here — which recovers, for free, the guard the shell
  // tool spent a parser on (`global_option_reconfigures`).
  //
  // What a prefix CANNOT do is gate flags: allowing `rebase` would allow
  // `rebase --exec CMD`, since the flag follows the subcommand. So a subcommand
  // carrying an "execute an arbitrary command" flag is all-or-nothing, and the
  // ones below are resolved by leaving the subcommand out and admitting only
  // the fixed control forms that have no such flag.
  ("git", ["--version"]),
  ("git", ["--help"]),
  ("git", ["status"]),
  ("git", ["log"]),
  ("git", ["diff"]),
  ("git", ["show"]),
  ("git", ["blame"]),
  ("git", ["describe"]),
  ("git", ["rev-parse"]),
  ("git", ["merge-base"]),
  ("git", ["range-diff"]),
  ("git", ["ls-files"]),
  ("git", ["ls-remote"]),
  ("git", ["shortlog"]),
  ("git", ["grep"]),
  ("git", ["config"]),
  ("git", ["branch"]),
  ("git", ["tag"]),
  ("git", ["remote"]),
  ("git", ["reflog"]),
  ("git", ["add"]),
  ("git", ["commit"]),
  ("git", ["checkout"]),
  ("git", ["switch"]),
  ("git", ["restore"]),
  ("git", ["reset"]),
  ("git", ["revert"]),
  ("git", ["rm"]),
  ("git", ["init"]),
  ("git", ["fetch"]),
  ("git", ["push"]),
  // `rebase` itself is withheld because `--exec` rides along with it; the
  // control forms that finish or abandon an in-progress rebase carry no such
  // flag and are what a turn actually needs.
  ("git", ["rebase", "--continue"]),
  ("git", ["rebase", "--abort"]),
  ("git", ["rebase", "--skip"]),
  // Same shape: `submodule foreach` runs an arbitrary command, `worktree
  // move`/`remove --force` relocate or destroy files, and the stash stack is
  // SHARED by every worktree of a repository — a `pop` here can take an entry
  // another session pushed. Where the hazard sits in a verb rather than a flag,
  // a two-token prefix separates the reads from it exactly; `git stash` with no
  // verb is a push, so it stays out along with `pop`, `drop` and `clear`.
  ("git", ["submodule", "update"]),
  ("git", ["submodule", "status"]),
  ("git", ["worktree", "list"]),
  ("git", ["worktree", "add"]),
  ("git", ["stash", "list"]),
  ("git", ["stash", "show"]),
  // Deliberately absent, matching the forms the shell tool pre-blocked:
  // `am`/`apply` (import arbitrary bytes), `clean` (permanently removes
  // untracked files), `bisect` (`run` executes a command), `merge`/`pull`/
  // `cherry-pick` (`-X`/strategy resolve an external merge driver), `mv`,
  // `clone`, and the plumbing (`fast-import`, `read-tree`, `update-index`,
  // `filter-branch`). In each of those the dangerous form is selected by a
  // FLAG, which follows the subcommand and so cannot be excluded by a prefix —
  // leaving the whole subcommand out is the only setting available.
  //
  // The forge CLI, likewise per subcommand: `gh extension` installs and then
  // runs third-party code, and `gh alias` turns any later invocation into
  // something else — both would make this list decorative.
  ("gh", ["pr"]),
  ("gh", ["issue"]),
  ("gh", ["run"]),
  ("gh", ["repo", "view"]),
  ("gh", ["api"]),
  ("gh", ["auth", "status"]),
  // The only two read-only utilities without a MoonBit equivalent worth using:
  // `rg` searches a whole tree faster than a snippet can walk it, and `diff`
  // produces a structured comparison. Their mutating counterparts (`rm`, `mv`,
  // `cp`, `chmod`) are absent because file changes belong to the file tools and
  // to `@fs`.
  //
  // `cat`, `ls`, `head`, `tail`, `wc`, `sort`, `uniq`, `grep`, `printf`,
  // `echo`, `pwd`, `date`, `which` and `uname` were dropped rather than listed.
  // Each is a line of MoonBit (`@fs`, string operations, `@env`) that works on
  // every platform, whereas the POSIX binaries do not exist on Windows — so
  // listing them offers the model a path that silently disappears there. It
  // would also cut against this tool's own advice, which is to capture
  // `out.stdout` and filter it in MoonBit instead of reaching for grep and awk.
  ("diff", []),
  ("rg", []),
  // NOT listed, on purpose: any program that runs another program on request
  // (`sh`, `bash`, `zsh`, `env`, `xargs`, `python`, `node`, `perl`, `make`).
  // Admitting one of those would make every other entry decorative, since a
  // snippet could reach anything through it — and myshell exists precisely so
  // that no shell sits between the agent and a process.
]

///|
/// Build the `moonrun --policy` document for one snippet run.
///
/// Deny-by-default: moonrun denies every surface a policy does not name. Writes
/// name the roots a run genuinely needs — `workspace_root` for the user's files
/// and `dir` for its throwaway build tree — while reads are open.
///
/// Reads are open because bounding them stops nothing this agent cannot already
/// do more easily, and costs steps to enforce. The `read` tool takes any
/// absolute path with no scope of its own, so any file on the machine is one
/// tool call away; `env.from_host` below hands the snippet every environment
/// variable the agent holds, API keys included. Against that, a read root list
/// buys no confidentiality — it only turns a wrong guess at where the toolchain
/// lives into a refusal that reads like a broken environment. Live runs spent
/// steps on exactly that, guessing `~/.moon`, `~/.mooncakes` and an opam-
/// installed `moon`, none of which the list happened to name.
///
/// Writes keep their bound for the reason reads do not: a snippet writing
/// outside the tree is INVISIBLE in the transcript, where a `write` tool call
/// naming the same path is right there to read. The asymmetry is legibility,
/// not access.
///
/// What this binds is the SNIPPET, on every platform. It does not reach the
/// child processes its `process` rules let the snippet start: those run with the
/// agent's own ambient access, and what bounds them is the allowlist itself —
/// which admits no shell, no interpreter, and no ad-hoc rewriter, and which
/// refuses git's reconfiguring global options because they precede the
/// subcommand.
fn wasm_policy_document(
  workspace_root~ : String,
  dir~ : String,
  tmp_dir~ : String,
  extra_roots~ : Array[String],
) -> Json {
  // The toolchain's own directories are deliberately NOT writable. This section
  // binds the SNIPPET, and a snippet never writes the registry or the compiler
  // assets — `moon` does, as a child process, which no `fs` rule of this policy
  // reaches. Listing them would confine nothing and only suggest the snippet
  // has business there.
  let write_roots = [workspace_root, dir, ..extra_roots]
  let allow : Array[Json] = []
  for entry in spawnable_commands {
    let (program, args_prefix) = entry
    let rule : Json = if args_prefix.is_empty() {
      { "program": program }
    } else {
      { "program": program, "args_prefix": json_strings(args_prefix) }
    }
    allow.push(rule)
  }
  {
    // A policy run BUILDS the guest environment rather than inheriting one, so
    // an empty list means an empty environment — `moon` could not even be
    // resolved by name. `"*"` copies the host's, which is what the shell tool
    // did and the only defensible choice here: a curated list would have to
    // know the variables the user's own project reads (`OPENAI_API_KEY`,
    // `DATABASE_URL`, whatever the tests need), and getting that wrong is
    // silent — the snippet, and the `moon test` it spawns, simply see nothing.
    // Confinement on this surface would be a functionality gate, not a boundary:
    // the agent process already holds these values.
    //
    // `TMPDIR` is then overridden, because under a policy moonrun resolves
    // `@fs.tmpdir()` from the POLICY's environment (`async_api/fs.rs::tmp_path`)
    // rather than the host's. Pointing it at a directory this run already owns
    // gives the snippet working scratch space without granting the host temp
    // directory, which would widen the read and write roots to hold every other
    // run's files. A native child ignores it either way — moonbitlang/async's
    // `stub.c` hardcodes `/tmp` off Windows — but a child is outside this
    // policy, so its temp directory is not this policy's business.
    "env": { "from_host": ["*"], "set": { "TMPDIR": tmp_dir } },
    // `"*"` is moonrun's every-host-path wildcard — see the header for why
    // reads are open where writes are not.
    "fs": { "read": ["*"], "write": json_strings(write_roots) },
    // Network stays denied: nothing a snippet does needs it except registry
    // fetches, which run inside `moon` — a child, and so outside this policy
    // either way.
    "process": { "allow": Json::array(allow) },
  }
}

///|
/// A JSON array of strings, for the path lists the policy is mostly made of.
fn json_strings(values : Array[String]) -> Json {
  Json::array([ for value in values => Json::string(value) ])
}
