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
/// The mbtx tool description and the default system prompt
/// (`prompt/default_prompt.mbt.md`, "Only these programs can be started")
/// both carry this list in prose. Admitting a command here without adding it
/// to both costs a turn steps: the model never learns it may use it.
let spawnable_commands : Array[(String, Array[String])] = [
  // The MoonBit toolchain, which is most of what a turn runs. Listed per
  // subcommand rather than as a bare `moon` so the set is reviewable, and so
  // adding a new one is a deliberate edit.
  ("moon", ["check"]),
  ("moon", ["test"]),
  ("moon", ["build"]),
  // Benchmarks compile and run workspace code natively, exactly like `test`:
  // admitting one while refusing the other would guard nothing, and
  // performance work is a recurring task shape.
  ("moon", ["bench"]),
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
  // Registry keyword search: read-only, and the natural first step before
  // `moon add` when the module name is not known yet.
  ("moon", ["search"]),
  ("moon", ["clean"]),
  ("moon", ["new"]),
  ("moon", ["ide"]),
  ("moon", ["doc"]),
  ("moon", ["explain"]),
  ("moon", ["coverage"]),
  ("moon", ["cram"]),
  ("moon", ["package"]),
  // Packaging may be checked against the registry contract, but publishing a
  // release remains outside the snippet's command surface. Keeping
  // `--dry-run` in the prefix makes that distinction enforceable.
  ("moon", ["publish", "--dry-run"]),
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
  // Proton CLI is SeekMoon's supported desktop application workflow, but it
  // is still listed per subcommand so the surface remains reviewable. Callers
  // set `Cmd.cwd` instead of passing the global `-C`/`--cwd` option, whose
  // position before the subcommand deliberately matches no rule below.
  ("proton_cli", ["--version"]),
  ("proton_cli", ["--help"]),
  ("proton_cli", ["new"]),
  ("proton_cli", ["dev"]),
  ("proton_cli", ["build"]),
  ("proton_cli", ["package"]),
  ("proton_cli", ["doctor"]),
  ("proton_cli", ["cef"]),
  ("proton_cli", ["updater"]),
  // Version control, listed per subcommand for two reasons. The obvious one is
  // that whole dangerous subcommands can be left out. The second falls out of
  // how prefixes match: git's reconfiguring GLOBAL options come BEFORE the
  // subcommand, so `git -c core.pager=CMD status` has args starting with `-c`
  // and matches no rule here — which recovers, for free, the guard the shell
  // tool spent a parser on (`global_option_reconfigures`).
  //
  // What a prefix CANNOT do is gate flags: admitting `rebase` admits
  // `rebase --exec CMD`, since the flag follows the subcommand. Such a
  // subcommand is all-or-nothing, and the ones below are decided on whether the
  // long tail is worth losing the verb — not on whether the flag exists, since
  // `moon run` already runs arbitrary programs from this same list.
  ("git", ["--version"]),
  ("git", ["--help"]),
  ("git", ["status"]),
  ("git", ["log"]),
  ("git", ["diff"]),
  ("git", ["show"]),
  ("git", ["blame"]),
  ("git", ["describe"]),
  ("git", ["rev-parse"]),
  // Read-only queries, each a subset of something already here. They were
  // missing only because this list is written a subcommand at a time.
  ("git", ["rev-list"]),
  ("git", ["show-ref"]),
  ("git", ["for-each-ref"]),
  ("git", ["cat-file"]),
  ("git", ["check-ignore"]),
  ("git", ["merge-base"]),
  ("git", ["range-diff"]),
  ("git", ["ls-files"]),
  // `ls-files` reads the index, so listing a tree at another commit had no
  // spelling short of `cat-file -p` on a hash the turn must first resolve.
  ("git", ["ls-tree"]),
  ("git", ["ls-remote"]),
  ("git", ["shortlog"]),
  ("git", ["grep"]),
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
  // Once limited to --continue/--abort/--skip, to keep `--exec` out. That
  // guards nothing next to `moon run`, already here and running arbitrary
  // programs, and it refused a plain `git rebase origin/main` in a live turn.
  ("git", ["rebase"]),
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
  // `prune` only garbage-collects the admin records of worktrees whose
  // DIRECTORY is already gone — it has no argument naming one to delete, so it
  // cannot reach a live tree the way `remove` can. That is what makes it the
  // safe half: delete your own worktree's directory, then prune the record.
  ("git", ["worktree", "prune"]),
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
  // `difftool`/`mergetool` are out for a different reason: both drive an
  // interactive external program, which a headless turn cannot answer.
  //
  // `config` writes what LATER git commands do — `core.pager`, `alias.*`,
  // `protocol.ext.allow` (which makes `ls-remote 'ext::sh -c ...'` a process
  // launcher) — so it undoes the `git -c` refusal one command later.
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
  // The Codex CLI, one verb only: `review` reads the current branch/diff and
  // reports findings — the review shape a shipping turn wants — while the
  // other verbs stay out: a bare `codex` opens an interactive agent, and
  // `exec`/`install` run or set one up. An admitted verb can still spawn
  // children of its own (the reviewer is an LLM agent, not a plain reader),
  // which is the already-accepted `moon run` shape; what the prefix buys is
  // that only the review FORM of this program exists in a turn's vocabulary.
  ("codex", ["review"]),
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
  // NOT listed: the general-purpose runners (`sh`, `bash`, `zsh`, `env`,
  // `xargs`, `python`, `node`, `perl`, `make`). Myshell exists so no shell sits
  // between the agent and a process; what the list buys is that going around
  // it takes intent.  
  // moonx inherits the sandbox policy from the agent, so it is not a security
  // perimeter.
  ("moonx", []),
]

///|
/// Build the `moonrun --policy` document for one snippet run.
///
/// Deny-by-default: moonrun denies every surface a policy does not name. Writes
/// name only the two roots a snippet has business in — its own temp directory
/// and a read-only role's lab — while reads are open.
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
/// `inject` names variables written into the GUEST environment on top of the
/// host's, and `spawnable` an extra program the snippet may start. Both exist
/// for one caller: a snippet that runs a workflow needs the engine's own
/// absolute path plus the coordinates mbtx reserved for it, and neither can
/// come from the snippet — the whole point is that only values mbtx chose
/// resolve to anything the host is watching. `spawnable` is an ABSOLUTE path
/// for the same reason `explore` never resolves the engine through PATH:
/// parent and child must be the same binary or the report's derived JSON
/// codecs can drift. moonrun matches the entry exactly, so an absolute rule
/// admits only that exact binary and no same-named one earlier in PATH.
fn wasm_policy_document(
  tmp_dir~ : String,
  extra_roots~ : Array[String],
  inject~ : Map[String, String],
  spawnable~ : String?,
) -> Json {
  // A snippet writes NOTHING in the workspace. It does not need to: the file
  // tools make the edits, and the commands whose job is to rewrite source
  // (`moon fmt`, `moon info`, `git checkout`) are child processes, which no `fs`
  // rule here reaches. What granting the workspace did buy was a documented way
  // around `remove`'s provenance check — `remove_path`, `rename_path` and
  // `rmdir_path` are all gated on `fs.write`, so a snippet could delete a file
  // the guarded tool exists to refuse.
  //
  // That leaves the two places a snippet has real business writing: its own temp
  // directory (where `@fs.tmpdir()` lands, since `TMPDIR` points here) and a
  // read-only role's scratch lab, which is the one place those roles may build
  // an experiment — they hold no editing tool at all.
  //
  // Every entry must be an EXISTING path: moonrun canonicalizes each root when
  // it loads the policy and fails the whole file otherwise. Both of these are
  // created before this runs.
  let write_roots = [tmp_dir, ..extra_roots]
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
  // The engine itself, one verb only. `subrun` reads a JSON line and reports
  // a child agent's result; the other verbs stay out, since a bare `openseek`
  // starts an interactive agent. An admitted verb spawns children of its own
  // — the sub-run IS an agent — which is the already-accepted `moon run`
  // shape; what the prefix buys is that only the delegating FORM of this
  // program exists in a snippet's vocabulary.
  if spawnable is Some(exe) {
    allow.push({ "program": exe, "args_prefix": json_strings(["subrun"]) })
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
    "env": { "from_host": ["*"], "set": Json(env_set(tmp_dir, inject)) },
    // `"*"` is moonrun's every-host-path wildcard — see the header for why
    // reads are open where writes are not.
    "fs": { "read": ["*"], "write": json_strings(write_roots) },
    // Snippets may resolve names and connect out, but may listen only on the
    // exact IPv4 and IPv6 loopback addresses. moonrun requires IP literals in
    // bind rules, so `localhost` itself is not a valid spelling here.
    //
    // Like `fs`, these rules stop at the process boundary: an admitted child
    // retains the agent's ambient network access.
    "net": {
      "dns": ["*"],
      "connect": ["*:*"],
      "bind": ["127.0.0.1:*", "[::1]:*"],
    },
    "process": { "allow": Json(allow) },
  }
}

///|
/// The guest's `env.set` block: whatever the caller injects, then the two
/// names whose values are POLICY DECISIONS rather than messages, written last
/// so no injected variable can override them.
///
/// `TMPDIR` points the snippet's scratch space into the directory this run
/// owns. `WORKFLOW_HOST` is always set — to the handoff when this run has one,
/// and to NOTHING otherwise. The guest copies the host's environment
/// (`from_host: ["*"]`), and this process may itself be a child of a hosted
/// snippet, whose handoff it inherited: left alone, that handoff would reach
/// this snippet, which would then mint child ids from a block that belongs to
/// its grandparent and collide with the grandparent's own children. An empty
/// value fails the library's reader closed, so the snippet sees no handoff
/// rather than someone else's.
fn env_set(tmp_dir : String, inject : Map[String, String]) -> Map[String, Json] {
  let set : Map[String, Json] = Map([])
  for name, value in inject {
    set[name] = value.to_json()
  }
  if !set.contains(HostHandoffVar) {
    set[HostHandoffVar] = "".to_json()
  }
  set["TMPDIR"] = tmp_dir.to_json()
  set
}

///|
/// The variable `moonbitlang/workflow/hosted` reads its handoff from.
const HostHandoffVar = "WORKFLOW_HOST"

///|
/// A JSON array of strings, for the path lists the policy is mostly made of.
fn json_strings(values : Array[String]) -> Json {
  Json([ for value in values => Json(value) ])
}

///|
fn test_injection(issued : Ref[Int]) -> @host.SubrunInjection {
  SubrunInjection(
    exe="/opt/openseek",
    session_root="/store",
    parent="run7",
    workspace_root="/ws",
    reserve_ordinals=count => {
      let base = issued.val + 1
      issued.val += count
      base
    },
  )
}

///|
test "the reservation reaches the guest, and only its own directory is writable" {
  let injection = test_injection(Ref(0))
  let reservation = injection.reserve()
  // A snippet that tried to redirect its own scratch space cannot: the policy
  // writes TMPDIR last, so the one name here whose value is a policy decision
  // rather than a message always wins.
  let inject = reservation.env()
  inject["TMPDIR"] = "/somewhere/else"
  let policy = wasm_policy_document(
    tmp_dir="/run/tmp",
    extra_roots=[reservation.dir()],
    inject~,
    spawnable=Some(injection.exe()),
  )
  guard policy
    is {
      "env": { "set": Object(set), .. },
      "fs": { "write": Array(write), .. },
      "process": { "allow": Array(allow), .. },
      ..
    } else {
    fail("policy lost its env, fs or process section")
  }
  assert_eq(set.get("TMPDIR"), Some(Json::string("/run/tmp")))
  assert_true(set.get("WORKFLOW_HOST") is Some(String(_)))
  // The run's directory is writable; the session store as a whole is not. A
  // snippet can append its own ledger and nothing else's transcript.
  assert_true(write.contains("/store/run7-wf-1"))
  assert_false(write.contains("/store"))
  // The engine is admitted by ABSOLUTE path and for one verb. moonrun matches
  // the entry exactly, so this admits that binary and not a same-named one
  // earlier in PATH — the same guarantee `explore` gets from never resolving
  // the engine through PATH.
  assert_true(
    allow.contains({ "program": "/opt/openseek", "args_prefix": ["subrun"] }),
  )
}

///|
test "no injection clears any inherited handoff and admits no engine" {
  let policy = wasm_policy_document(
    tmp_dir="/run/tmp",
    extra_roots=[],
    inject=Map([]),
    spawnable=None,
  )
  guard policy
    is {
      "env": { "set": Object(set), .. },
      "process": { "allow": Array(allow), .. },
      ..
    } else {
    fail("policy lost its env or process section")
  }
  // A conversation with no durable session gets no coordinates and no engine
  // in its command vocabulary: there is nowhere to put a child transcript, so
  // admitting the spawn would only produce invisible children.
  //
  // `WORKFLOW_HOST` is still SET — to nothing. The guest copies the host's
  // environment, and this process may itself be a child of a hosted snippet,
  // whose handoff it inherited. Left alone, that handoff would reach this
  // snippet, which would mint child ids from a block that belongs to its
  // grandparent. An empty value fails the library's reader closed.
  assert_eq(set.length(), 2)
  assert_true(set.get("TMPDIR") is Some(_))
  assert_eq(set.get("WORKFLOW_HOST"), Some(Json::string("")))
  for rule in allow {
    guard rule is { "program": String(program), .. } else { continue }
    assert_false(program.contains("openseek"))
  }
}
