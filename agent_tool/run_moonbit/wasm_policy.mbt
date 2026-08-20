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
/// Deny-by-default: moonrun denies every surface a policy does not name, so
/// each root here is one the run genuinely needs. `workspace_root` is where the
/// snippet reads and writes the user's files, `dir` is its throwaway build
/// tree, and the toolchain roots are what `moon` itself reads.
///
/// What this binds is the SNIPPET, on every platform. It does not reach the
/// child processes its `process` rules let the snippet start: those run with the
/// agent's own ambient access, and what bounds them is the allowlist itself —
/// which admits no shell, no interpreter, and no ad-hoc rewriter, and which
/// refuses git's reconfiguring global options because they precede the
/// subcommand.
async fn wasm_policy_document(
  workspace_root~ : String,
  dir~ : String,
  tmp_dir~ : String,
  extra_roots~ : Array[String],
) -> Json {
  let read_roots = [workspace_root, dir, ..extra_roots, ..toolchain_roots()]
  // The toolchain's own directories are deliberately NOT writable here. This
  // section binds the SNIPPET, and a snippet never writes the registry or the
  // compiler assets — `moon` does, as a child process, which no `fs` rule of
  // this policy reaches. Listing them would confine nothing and only suggest
  // the snippet has business there.
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
    "fs": {
      "read": json_strings(read_roots),
      "write": json_strings(write_roots),
    },
    // Network stays denied: nothing a snippet does needs it except registry
    // fetches, which run inside `moon` — a child, and so outside this policy
    // either way.
    "process": { "allow": Json::array(allow) },
  }
}

///|
/// Where the toolchain lives, resolved exactly the way `moon` itself resolves it
/// (moonutil `resolve_moon_home`): `MOON_HOME` when set, otherwise `$HOME/.moon`.
/// There is no third location — a path like `$HOME/Library/MoonBit` is where an
/// installer may put the toolchain, but then it exports `MOON_HOME` to match, so
/// listing it as a fallback would only widen the sandbox for hosts that do not
/// use it. What `toolchain_roots` adds on top of this answer is the DEFAULT
/// location as well, which is a different question — see there.
fn moon_home() -> String? {
  if @env.get_env_var("MOON_HOME") is Some(home) && home != "" {
    return Some(home)
  }
  if @env.get_env_var("HOME") is Some(home) && home != "" {
    return Some("\{home}/.moon")
  }
  None
}

///|
/// Where the compiler and `lib/core` live, which is NOT the same place as
/// `moon_home()` and is resolved by a different rule. Following moonutil's
/// `resolve_toolchain_root`: `MOON_TOOLCHAIN_ROOT` when set, otherwise the
/// parent of the directory holding the `moon` on `PATH` — moon locates its own
/// assets relative to its executable.
///
/// The two diverge exactly where it matters. The desktop app never sets
/// `MOON_HOME` and finds moon purely by prepending a bin directory to `PATH`,
/// so there the registry is `~/.moon` while `lib/core` is wherever moon was
/// installed — and a snippet reading an `.mbti` to look up an API needs the
/// second one, which `MOON_HOME` alone does not name.
/// The answer cannot change while the agent runs — `PATH` and
/// `MOON_TOOLCHAIN_ROOT` are fixed at startup — while finding it stats every
/// `PATH` entry in turn. `Lazy` resolves it on first use and caches it,
/// including for concurrent runs: several snippets may be in flight at once,
/// and they share the one lookup instead of racing to repeat it.
let toolchain_root : @async.Lazy[String?] = Lazy(() => resolve_toolchain_root())

///|
/// The `PATH` walk is written for the POSIX spelling (`:`-separated, no `.exe`).
/// On Windows it finds nothing and the toolchain root goes ungranted, which
/// costs a snippet the ability to READ `lib/core` there — an API lookup, not a
/// build, since `moon` is a child process and reads it on its own account.
async fn resolve_toolchain_root() -> String? {
  if @env.get_env_var("MOON_TOOLCHAIN_ROOT") is Some(root) && root != "" {
    return Some(root)
  }
  guard @env.get_env_var("PATH") is Some(path) else { return None }
  for entry in path.split(":") {
    guard !entry.is_empty() else { continue }
    let bin_dir = @path.Path(entry.to_owned())
    if @fs.exists(bin_dir.join(Path("moon")).to_string()) {
      return Some(bin_dir.dirname().to_string())
    }
  }
  None
}

///|
/// What a SNIPPET reads outside its own workspace: the toolchain, whose
/// `lib/core/*.mbti` files are how a run looks up an API, and the registry
/// cache next to it.
///
/// System directories are deliberately not listed. A snippet reads its
/// workspace and the toolchain; the programs that read `/usr` and `/etc` are
/// `moon` and `git`, and they are child processes this policy's `fs` rules do
/// not reach. Hardcoding POSIX paths would also have been meaningless on
/// Windows — every root here comes from the environment instead.
async fn toolchain_roots() -> Array[String] {
  let roots = []
  if moon_home() is Some(home) {
    roots.push(home)
  }
  // `$HOME/.moon` even when `MOON_HOME` points elsewhere. It is the DEFAULT
  // registry location and the one a snippet reaches for by name — the API
  // lookup a turn is taught is `${MOON_HOME:-$HOME/.moon}`, and a machine that
  // relocated `MOON_HOME` usually still has a registry here. A run spent a step
  // on this: it read `~/.moon` to find a package's `.mbti`, got a policy
  // refusal rather than a plain "no such file", and had to work out which of
  // the two it was looking at. Reads only, and this list is already the
  // toolchain's.
  if @env.get_env_var("HOME") is Some(home) && home != "" {
    let default_home = "\{home}/.moon"
    if !roots.contains(default_home) {
      roots.push(default_home)
    }
  }
  if toolchain_root.wait() is Some(root) {
    roots.push(root)
  }
  roots
}

///|
/// A JSON array of strings, for the path lists the policy is mostly made of.
fn json_strings(values : Array[String]) -> Json {
  Json::array([ for value in values => Json::string(value) ])
}
