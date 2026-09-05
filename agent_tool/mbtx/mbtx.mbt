///|
/// How long a runtime-backed run stays inline before it is adopted as a job.
/// Five seconds keeps quick probes inline while moving builds, suites, and
/// watchers out of the turn without asking the model to predict their duration.
const AutoBackgroundAfterMs : Int = 5_000

///|
/// Runtime-less foreground work is bounded to this wall-clock so a runaway loop
/// or build cannot block the whole turn. On expiry it is cancelled and reported
/// as a timeout. Sized for commands, not just compute: a snippet runs whole
/// `moon test` cycles, and a fresh workspace's first build downloads and
/// compiles its dependencies.
const ForegroundTimeoutMs : Int = 300_000

///|
/// Ceiling on the build notes carried into a report, in characters. Warnings
/// are for reading, not archiving: the run's own body may already reach the
/// 48KB `OutputCapBytes`, which is sized to keep the whole result under the
/// agent loop's outer 60k clamp — a clamp that cuts the TAIL, exactly where
/// the stop/retry and sandbox guidance live. An uncapped prepend would spend
/// that margin; this cap preserves it.
const BuildNotesCapChars : Int = 8_000

///|
/// Wall-clock bound for the synchronous BUILD phase of a wasm run. The build
/// runs inline on purpose — its duration does not count against the program's
/// own foreground allowance — so it needs a bound of its own: a hung
/// dependency download must not hold the turn. Generous by an order of
/// magnitude: a trivial wasm build measures ~100ms and one pulling several
/// registry modules well under a second on a warm cache, and a timed-out
/// build's retry is faster still (moon caches downloaded modules).
const BuildTimeoutMs : Int = 10_000

///|
/// Output is streamed to a file on disk, not buffered in memory, so a snippet
/// that floods stdout (e.g. `while true { println(…) }`) cannot exhaust the
/// agent's memory before the timeout fires. A FOREGROUND run is STOPPED once it
/// passes this, rather than truncated — the runtime spawns it with
/// `kill_when_full`, so a clipped head means a killed program and the exit code
/// is not the program's own. Detaching clears that, so a background job is
/// bounded by the hard cap instead and runs to its own end.
const OutputCapBytes : Int = 48_000

///|
/// The `--warn-list` spec for `warning: "off"`. `-a` disables all warnings;
/// each `+name@name` pair then re-enables a selected correctness diagnostic
/// and promotes it back to an error. Keep this mnemonic list maintained by
/// hand; `unused_mut` intentionally remains suppressed for throwaway snippets.
const WarnOffList : String = "-a+partial_match@partial_match+multiline_string_escape@multiline_string_escape+invalid_inline_wasm@invalid_inline_wasm+unannotated_ffi@unannotated_ffi"

///|
/// Render an injected millisecond bound without losing sub-second precision in
/// model-facing text or tool results.
fn duration_label(milliseconds : Int) -> String {
  if milliseconds % 1000 == 0 {
    "\{milliseconds / 1000}s"
  } else {
    "\{milliseconds}ms"
  }
}

///|
/// Tool definition for `mbtx`: compile and run a self-contained MoonBit
/// program and return its merged stdout/stderr and exit status.
///
/// The program is a `.mbtx` single-file script — it may open with an inline
/// `import { "pkg", … }` block (comma-separated module paths) naming the
/// standard packages it uses, followed by the program including its own
/// `main`. It runs via `moon run` with your workspace as the working directory
/// by default — so relative `@fs` paths (e.g. `@fs.read_file("data.json")`)
/// resolve to workspace files, and any output the program writes lands in the
/// workspace. Pass `cwd` to run somewhere else. Build artifacts stay in a
/// throwaway temp directory (via `--target-dir`), so they never touch your
/// `_build` and the working tree is left clean.
///
/// Dependency resolution is still isolated: a local-package import resolves to
/// the published registry snapshot, not your uncommitted edits (so this is for
/// self-contained scripts; use a `*_test.mbt` + `moon test` for working-tree
/// code), and third-party imports resolve to their LATEST registry version,
/// which can differ from your workspace's pinned versions — verify
/// dependency-API probes against the workspace, not mbtx.
///
/// Compiler warnings are suppressed by default: snippets are throwaway
/// scripts, so unused-value style noise would only pollute the output.
/// Passing `warning: "on"` restores them, for when the warnings themselves
/// are the thing being probed. Selected correctness diagnostics such as
/// `partial_match` keep failing compilation with warnings off (see
/// `WarnOffList`).
///
/// Confinement is moonrun's wasm policy, which applies on every platform. It
/// decides WHICH programs may start — an allowlist holding the moon/git/gh
/// toolchain and inert utilities, with no shell, interpreter, or ad-hoc
/// rewriter in it — and bounds the file access of the snippet itself.
///
/// Its `fs` rules stop at the process boundary, so an admitted command writes
/// with the agent's own access. What is bounded is which commands exist at all,
/// and one of those bounds is per subcommand: the options that would point git
/// at another repository (`git -C`, `--git-dir`) precede the subcommand and so
/// match no allowlist prefix.
///
/// Note what is deliberately NOT denied: source writes as such. The commands
/// whose job is to rewrite source (`moon fmt`, `moon info`, `git checkout`) run
/// normally, and the reason the old rule existed — an arbitrary program editing
/// files behind the model's back — is covered by the allowlist admitting no
/// such program. A read-only subrun is the exception, and the one role that
/// still takes a `sandbox-exec` profile: holding no editing tool is what defines
/// it, so `read_only=true` puts "may not write source" in the kernel.
///
/// `approval` is where a request to run OUTSIDE the sandbox goes. Its presence
/// is what advertises the `escalated` argument at all: a build with nobody to
/// ask does not offer an argument whose every use would come back refused.
pub fn definition(
  workspace_root~ : String,
  read_only? : Bool = false,
  bg_runtime? : @bgjobs.BgJobRuntime,
  job_dir? : String,
  scratch_dir? : String,
  worker_sandbox? : WorkerSandbox,
  auto_background_after_ms? : Int = AutoBackgroundAfterMs,
  foreground_timeout_ms? : Int = ForegroundTimeoutMs,
  build_timeout_ms? : Int = BuildTimeoutMs,
  approval? : @agent_runtime.ApprovalChannel,
  subrun? : @host.SubrunInjection,
) -> @agent_tool.AgentToolDefinition {
  // Background snippet directories are numbered inside the caller's scratch
  // dir rather than created as fresh system temp dirs: a detached job outlives
  // this call, so its snippet, build artifacts, and output log cannot be
  // removed here — the caller's scratch dir is what eventually reclaims them.
  let next_background = Ref(0)
  AgentToolDefinition(
    name="mbtx",
    description=description(
      background=bg_runtime is Some(_),
      escalation=approval is Some(_),
      hosting=subrun is Some(_),
      auto_background_after_ms~,
      foreground_timeout_ms~,
      build_timeout_ms~,
    ),
    schema=JsonSchema(
      schema(escalation=approval is Some(_), hosting=subrun is Some(_)),
    ),
    execute=Async(arguments => {
      execute(
        workspace_root,
        arguments,
        read_only~,
        bg_runtime?,
        job_dir?,
        scratch_dir?,
        worker_sandbox?,
        auto_background_after_ms~,
        foreground_timeout_ms~,
        build_timeout_ms~,
        next_background~,
        approval?,
        subrun?,
      )
    }),
  )
}

///|
/// What the model is told when an escalation did not become a run.
///
/// One text per outcome, and they are deliberately different sentences rather
/// than one "escalation denied": what the model should do next differs for
/// each, and a single text makes all three look like the same wall. A refusal
/// by a person is final for this task; a withdrawn request is not a decision
/// at all; an absent channel means the argument itself is unusable here and
/// the snippet should simply be retried without it.
///
/// `AllowedOnce` is not a refusal, so it has no text — it is unreachable here,
/// and answering it would be a fourth sentence nobody ever reads.
fn escalation_refused(outcome : @agent_runtime.ApprovalOutcome) -> String {
  match outcome {
    Rejected =>
      "mbtx: the user declined to run this snippet outside the sandbox. That is an answer, not an obstacle to route around: do not ask again for this task — solve it within the spawn allowlist and the write-root bound, or say plainly what that makes impossible."
    Cancelled =>
      "mbtx: the request to run outside the sandbox was withdrawn before anyone answered it, so NOTHING RAN. This is not a refusal — but do not ask a second time unless something has changed; retry the snippet without `escalated` instead."
    Unavailable =>
      "mbtx: this session has no approval channel, so running outside the sandbox cannot be granted here at all. Retry this exact snippet without `escalated`; the spawn allowlist and the write-root bound are what you have."
    // Unreachable: the caller only builds a refusal after the grant failed.
    AllowedOnce => "mbtx: escalation was granted."
  }
}

///|
/// The outcome word for the display-only brief.
fn escalation_brief(outcome : @agent_runtime.ApprovalOutcome) -> String {
  match outcome {
    AllowedOnce => "allowed"
    Rejected => "refused"
    Cancelled => "withdrawn"
    Unavailable => "unavailable"
  }
}

///|
async fn execute(
  workspace_root : String,
  arguments : Json,
  read_only~ : Bool,
  bg_runtime? : @bgjobs.BgJobRuntime,
  job_dir? : String,
  scratch_dir? : String,
  worker_sandbox? : WorkerSandbox,
  // Independent injectable bounds: a runtime-backed run hands off at the
  // first; a runtime-less run is cancelled at the second; a wasm target's
  // synchronous build phase is cancelled at the third.
  auto_background_after_ms~ : Int,
  foreground_timeout_ms~ : Int,
  build_timeout_ms~ : Int,
  next_background~ : Ref[Int],
  approval? : @agent_runtime.ApprovalChannel,
  subrun? : @host.SubrunInjection,
) -> @agent_tool.ToolAction {
  let input = @decode.decode(arguments) catch {
    error =>
      return @agent_tool.respond(
        "error: mbtx requires \{@tool_error.failure_message("\{error}")}",
        is_error=true,
      )
  }
  // Refuse FFI (`extern`), the one construct no mbtx target runs sandboxed.
  // The wasm family needs no scan — the compiler refuses `extern "c"` and
  // `extern "js"` on those backends outright — but the js target's host is
  // bare node, where `extern "js"` reaches host globals, and llvm is
  // unsandboxed native codegen. Match the FFI syntax (`extern "c"`/`extern
  // "js"`), not the bare word: `extern` alone appears in prose and string
  // literals (a snippet quoting a commit message was refused once), the quote
  // that follows it does not. A substring scan is NOT a real boundary; it is
  // what keeps the non-wasm targets' "compute-only" promise true.
  if input.source.contains("extern \"") {
    return @agent_tool.respond(
      "mbtx refuses this program: it uses native FFI (extern), which no mbtx target can run sandboxed — the wasm family refuses to compile it, and the js/llvm targets have no policy to contain it.",
      is_error=true,
    )
  }
  // The program's working directory (default: the workspace root, so relative
  // `@fs` paths reach workspace files). An explicit relative `cwd` resolves
  // against the workspace, as every workspace-relative tool path does.
  let run_cwd = @workspace_path.resolve_cwd(workspace_root, input.cwd)
  if run_cwd is Some(c) {
    guard @fs.exists(c) else {
      return @agent_tool.respond(
        "error: mbtx cwd does not exist: \{c}",
        is_error=true,
      )
    }
    guard @fs.kind(c) is Directory else {
      return @agent_tool.respond(
        "error: mbtx cwd is not a directory: \{c}",
        is_error=true,
      )
    }
  }
  // The snippet and all build artifacts live in a throwaway temp dir (passed as
  // `--target-dir`), while the program itself runs with `run_cwd` as its working
  // directory — so relative `@fs` paths reach workspace files yet nothing lands
  // in the working tree. The temp dir is managed by hand (not `@vfs.with_tmpdir`)
  // so its cleanup can be shielded from cancellation — that helper re-raises on
  // cancel WITHOUT removing the dir, which would leak the snippet, artifacts, and
  // a possibly-large output log when a turn is cancelled mid-run. The timeout
  // wraps only the process body; output is redirected to a file (not buffered in
  // memory) and read back capped, so a flood cannot exhaust memory.
  // Escalation only means something on the backend the policy binds. The other
  // targets never had `--wasm-policy` passed to them in the first place — they
  // cannot spawn or touch files at all — so asking here would spend a person's
  // attention on a grant that changes nothing about the run.
  // Delegation lives in the sandbox policy — the handoff is a policy `env.set`,
  // the engine a policy `process.allow` entry, the run directory a policy write
  // root — so it exists only where the policy applies: the wasm target, with
  // the policy in force. Refuse anything else BEFORE a block is reserved or a
  // run announced; the alternative is a snippet that finds no handoff while
  // the desktop shows a workflow that never existed.
  if input.subrun && input.target != "wasm" {
    return @agent_tool.respond(
      "mbtx: `subrun` applies to the wasm target, which is the one the sandbox policy binds — the handoff, the engine's spawn rule and the run's write root all live in that policy; `\{input.target}` runs none. Drop `target` to use wasm, or drop `subrun`.",
      is_error=true,
      brief="mbtx (subrun needs wasm)",
    )
  }
  if input.subrun && input.escalated {
    return @agent_tool.respond(
      "mbtx: `subrun` and `escalated` exclude each other — escalation runs the snippet with NO sandbox policy, and the delegation handoff is delivered through that policy. Use `subrun` alone to delegate; the allowed programs already include the engine.",
      is_error=true,
      brief="mbtx (subrun with escalated)",
    )
  }
  if input.escalated && input.target != "wasm" {
    return @agent_tool.respond(
      "mbtx: `escalated` applies to the wasm target, which is the one the sandbox policy binds; `\{input.target}` runs no policy to lift and cannot spawn or touch files anyway. Drop `escalated`, or drop `target` to use wasm.",
      is_error=true,
    )
  }
  // Resolve the escalation request before anything is created or spawned, and
  // after every cheap check above: a snippet with a typo'd `cwd` must fail on
  // the typo rather than spend a person's attention on a prompt for a call
  // that was never going to run.
  //
  // A granted escalation is consumed by THIS call and nothing else. There is
  // no session-scoped grant and no rule to remember, so the next escalating
  // call asks again.
  let escalated = if input.escalated {
    let outcome = match approval {
      Some(channel) =>
        // The program goes with the question. It is what the user is actually
        // deciding about, and `detail` — which is a constant — describes only
        // the permission. Passed as the exact string this call was made with,
        // so what is approved and what runs cannot differ.
        channel.ask({
          tool_name: "mbtx",
          detail: "run this snippet with no sandbox policy: no spawn allowlist, and writes anywhere",
          body: Some(input.source),
        })
      // The argument was not advertised in this build's schema, so reaching
      // here means the model asked for a field it was never offered.
      None => Unavailable
    }
    guard outcome is AllowedOnce else {
      return @agent_tool.respond(
        escalation_refused(outcome),
        is_error=true,
        brief="mbtx (escalation \{escalation_brief(outcome)})",
      )
    }
    true
  } else {
    false
  }
  // One source of truth for whether moonrun's policy actually governs this
  // execution. The launch argv, adopted-job metadata, and foreground refusal
  // classifier must not drift: ordinary output from a non-wasm or escalated run
  // is never evidence of a policy that was not active.
  let policy_active = input.target == "wasm" && !escalated
  let handoff_dir_has_owner = job_dir is Some(_) || scratch_dir is Some(_)
  // A directory that an automatic handoff may give to a job must outlive this
  // call, so it is numbered inside a caller-owned job dir or scratch lab when
  // one exists. Its `tmp` subtree is the snippet's writable result area and may
  // contain paths named in completion output, so only the separate build subtree
  // is reclaimed when a handed-off job becomes terminal.
  let dir = if job_dir is Some(scratch) {
    let dir = "\{scratch}/snippet-\{next_background.val}"
    next_background.val += 1
    @fs.mkdir(dir, recursive=true) catch {
      error if @async.is_being_cancelled() => raise error
      _ =>
        return @agent_tool.respond(
          "mbtx: could not create a working directory for the background job.",
          is_error=true,
        )
    }
    dir
  } else if scratch_dir is Some(lab) {
    // With a lab wired, the snippet builds INSIDE it: the profile re-allows
    // exactly one subtree, and pointing it at the lab then covers both the
    // lab writes the caller sanctioned and moon's own build output.
    let dir = "\{lab}/mbtx-\{next_background.val}"
    next_background.val += 1
    @fs.mkdir(dir, recursive=true) catch {
      error if @async.is_being_cancelled() => raise error
      _ =>
        return @agent_tool.respond(
          "mbtx: could not create a working directory in the scratch lab.",
          is_error=true,
        )
    }
    dir
  } else {
    @fs.tmpdir(prefix="openseek-mbtx-") catch {
      // Let a cancellation propagate to the loop's Interrupted terminal instead of
      // swallowing it into an ordinary tool error.
      error if @async.is_being_cancelled() => raise error
      _ =>
        return @agent_tool.respond(
          "mbtx: could not create a temporary working directory.",
          is_error=true,
        )
    }
  }
  // Set once an automatically handed-off job takes over resource cleanup.
  // `cleanup` runs on every exit path, so the flag prevents it from racing the
  // process after handoff.
  //
  // Handing it over is sound when either caller-owned root is wired: the
  // standard registry's `job_dir` has a task-group teardown, and a scratch lab
  // has its own lifecycle. A non-standard caller that wires neither root has no
  // owner, so its fallback directory is reclaimed by the job at terminal status.
  let mut job_owns_cleanup = false
  async fn cleanup() -> Unit {
    if job_owns_cleanup {
      return
    }
    @async.protect_from_cancel(() => {
      @fs.rmdir(dir, recursive=true) catch {
        _ => ()
      }
    })
  }

  defer cleanup()
  // Keep disposable compiler inputs and artifacts apart from `tmp`, whose
  // result files may need to remain readable after a background job exits.
  let build_dir = "\{dir}/build"
  @fs.mkdir(build_dir) catch {
    error if @async.is_being_cancelled() => raise error
    _ =>
      return @agent_tool.respond(
        "mbtx: could not create a build directory for the snippet.",
        is_error=true,
      )
  }
  @fs.write_file(
    "\{build_dir}/snippet.mbtx",
    input.source,
    create_mode=CreateOrTruncate,
  )
  let log = "\{build_dir}/output.log"
  // Pre-create the merged output file so both redirects open it; both append
  // so stdout and stderr interleave in write order.
  @fs.write_file(log, "", create_mode=CreateOrTruncate)
  // Give the snippet an EMPTY stdin (immediate EOF) rather than inheriting fd 0:
  // under `openseek serve`/TUI that fd is the JSONL control channel, and a
  // snippet reading `@stdio.stdin` would otherwise consume the engine's
  // prompt/steer/cancel commands (or block until the timeout). An empty temp
  // file is portable (no `/dev/null`/`NUL` special-casing).
  let empty_stdin = "\{build_dir}/stdin.empty"
  @fs.write_file(empty_stdin, "", create_mode=CreateOrTruncate)
  // moon's diagnostics point at the copied source under the build dir; the
  // canonical path anchors the diagnostic path rewrite below.
  let real = @fs.realpath(build_dir) catch { _ => build_dir }
  // The wasm backend is where moonrun's policy applies, so the policy file is
  // written for every run and passed alongside. `--wasm-policy` is silently
  // IGNORED on other backends, which is why `target` is not the model's choice
  // to make freely — see `decode`.
  let policy_path = "\{build_dir}/policy.json"
  // Scratch space for the snippet's own `@fs.tmpdir()`, kept beside the build
  // output rather than inside it so temp directories do not appear among moon's
  // artifacts. After handoff its caller-owned container preserves these results;
  // all foreground and standalone paths still remove the whole container.
  let snippet_tmp = "\{dir}/tmp"
  @fs.mkdir(snippet_tmp) catch {
    error if @async.is_being_cancelled() => raise error
    _ => ()
  }
  // `cwd` is deliberately NOT a write root: naming where a program runs should
  // not also grant writing there, and reads are open, so a snippet can still
  // work in a directory it may not modify.
  // Reserve this snippet's child ordinals and journal BEFORE it runs. The
  // coordinates reach it as guest environment variables, never as argv it
  // wrote: only values mbtx chose resolve to anything the host watches, so a
  // snippet cannot name a session that was not reserved for it.
  let reservation = if input.subrun {
    match subrun {
      Some(injection) => Some(injection.reserve())
      // Asked, and cannot be served: say so. A snippet that believed it had a
      // handoff would spawn children with no transcript, and the model would
      // learn nothing until its subagents failed to appear anywhere.
      None =>
        return @agent_tool.respond(
          "mbtx: `subrun` was requested, but this conversation has no durable session, so a workflow's children would have nowhere to leave a transcript. Retry without `subrun` and do the work in this snippet directly.",
          is_error=true,
          brief="mbtx (subrun unavailable)",
        )
    }
  } else {
    None
  }
  // The run's own directory, and the ONE place in the session store the
  // snippet may write. It must exist before the policy names it — moonrun
  // canonicalizes every root when it loads the document and refuses the whole
  // file otherwise. Granting the store itself would let a snippet append to
  // another session's transcript; the ledger gets a directory instead.
  if reservation is Some(r) {
    @fs.mkdir(r.dir()) catch {
      error if @async.is_being_cancelled() => raise error
      _ => ()
    }
  }
  let policy = wasm_policy_document(
    tmp_dir=snippet_tmp,
    extra_roots=[
      ..scratch_dir.map(l => [l]).unwrap_or([]),
      ..reservation.map(r => [r.dir()]).unwrap_or([]),
    ],
    inject=reservation.map(r => r.env()).unwrap_or(Map([])),
    spawnable=match (reservation, subrun) {
      (Some(_), Some(injection)) => Some(injection.exe())
      _ => None
    },
  )
  @fs.write_file(policy_path, policy.stringify(), create_mode=CreateOrTruncate)
  // Wrap each phase's command in sandbox-exec for the roles that need a rule
  // the wasm policy cannot state: "may not write source". The policy's `fs`
  // rules bind the snippet and stop at the process boundary, so a spawned
  // `moon fmt` is beyond them, and a role defined by holding no editing tool
  // needs that covered in the kernel. The main agent is not such a role and
  // takes no profile — see below. Off macOS, or in a nested sandbox where a
  // profile cannot be applied, every role runs with the policy as its only
  // bound. The prepared command carries what it needs to classify its own
  // denials, so one showing up in the program's output can be recognized and
  // explained.
  // The throwaway snippet container is the writable subtree: if it falls INSIDE
  // the workspace root (e.g. `workspace_root=/tmp`, where `@fs.tmpdir` lands
  // under it) the shared deny would otherwise block moon's own generated
  // `snippet.mbt`.
  // The writable subtree has to contain the snippet's own build output. With a
  // lab wired the snippet builds inside it, so the lab covers both; otherwise
  // the snippet container covers `build` and `tmp`. Choosing by where `dir`
  // actually sits keeps the two from disagreeing when a caller passes both a
  // job dir and a lab.
  let writable_subtree = match scratch_dir {
    Some(lab) if dir.has_prefix(lab) => lab
    _ => dir
  }
  async fn confine(
    program : String,
    command_argv : Array[String],
  ) -> @sandbox.SandboxedCommand? {
    match worker_sandbox {
      // Worker mode replaces the workspace source-write profile rather than
      // adding to it: a worker is supposed to write source, just only its own,
      // so the kernel denies its siblings' trees and the shared git dir instead
      // of denying source writes as such.
      Some(scope) =>
        @sandbox.SandboxedCommand::create_worker_if_available(
          Exec(program, command_argv),
          deny_roots=scope.deny_roots,
          worker_root=scope.worker_root,
          worker_admin_dir=scope.worker_admin_dir,
        )
      // The read-only roles (explore/review/audit) hold no editing tool, so
      // "may not write source" is the guarantee that defines them and it stays
      // kernel-enforced. The profile suits them for a second reason — it is
      // `(allow default)` minus source, so `moon check` can still write its
      // target dir inside the workspace, which a boundary profile denying the
      // workspace would take away.
      //
      // Read-only is its own parameter rather than being read off
      // `scratch_dir`: a caller that forgets the lab should lose the lab, not
      // the sandbox.
      None if read_only =>
        @sandbox.SandboxedCommand::create_if_available(
          workspace_root,
          Exec(program, command_argv),
          writable_subtree~,
        )
      // The main agent runs with no kernel profile at all. Forbidding source
      // writes here would break the very commands it needs — `moon fmt`,
      // `moon info`, `git checkout` all rewrite source by definition — and the
      // other shape, denying writes globally and re-allowing an enumerated
      // set, was tried and withdrawn: every root it missed (`/dev` for git's
      // `/dev/null`, `/tmp` for `@fs.tmpdir`, the toolchain root, gh's cache)
      // surfaced as a bare EPERM in a live turn rather than in a test, and the
      // list only ever protected macOS.
      //
      // What is left bounding a child is the allowlist, which works
      // everywhere: it admits no shell, no interpreter and no ad-hoc rewriter,
      // and it refuses the git options that would point a command at another
      // repository. That is a bound on which commands exist, not on where they
      // may write — the file tools are not path-confined for this role either,
      // so a profile here would have been the only such rule in the tool set.
      None => None
    }
  }

  // The wasm target runs in TWO phases. The BUILD runs first, synchronously,
  // on its own bound: build time deliberately does not count against the
  // program's foreground allowance, a failed build returns immediately and is
  // a build failure BY CONSTRUCTION (the run phase never starts — no exit
  // code or output archaeology can confuse the two stages), and what the
  // background runtime may later adopt is exactly the running program. The
  // RUN phase then execs `moonrun` directly on the artifact the build
  // reported — the same process `moon run` would exec, with `--policy` being
  // moonrun's spelling of `--wasm-policy` (confirmed against moon's own
  // `--dry-run` plan).
  //
  // The other targets keep the single-shot `moon run`: they are compute-only
  // (no policy to stage around), their runners are not moonrun, and they are
  // rare enough that a second execution shape is not worth carrying.
  let staged_run = if input.target == "wasm" {
    match
      build_snippet(
        build_dir~,
        run_cwd~,
        warning=input.warning,
        build_timeout_ms~,
        empty_stdin~,
        rewrite_bases=[real, build_dir],
        confine~,
      ) {
      NotBuilt(action) => return action
      Built(artifact~, notes~) => {
        // An approved escalation is exactly this: the policy file is still
        // written, and simply not passed. Widening the document instead was
        // not available — its `fs.write` roots are canonicalized existing
        // paths with no wildcard, and "any program" has no spelling in
        // `process.allow` short of enumerating one — so "no policy" is both
        // the honest description of what was approved and the only one the
        // runtime can express.
        let run_argv : Array[String] = [
          ..if policy_active {
            ["--policy", policy_path]
          },
          artifact,
          "--",
        ]
        Some(("moonrun", run_argv, notes))
      }
    }
  } else {
    None
  }
  let (spawn_program, spawn_argv, build_notes) = staged_run.unwrap_or(
    (
      "moon",
      [
        "run",
        "-q",
        "\{build_dir}/snippet.mbtx",
        "--target",
        input.target,
        "--target-dir",
        build_dir,
        ..if !input.warning {
          ["--warn-list", WarnOffList]
        },
      ],
      "",
    ),
  )
  let staged = staged_run is Some(_)
  let sandboxed_command = confine(spawn_program, spawn_argv)
  let (prog, argv) = match sandboxed_command {
    Some(command) => (command.program(), command.args())
    None => (spawn_program, spawn_argv)
  }
  // With a job runtime wired the foreground run happens ON it, so the
  // deadline can DETACH the still-running program as a background job rather
  // than killing it: a long `moon test` that outlives the bound is then still
  // there to read, which is what the shell tool did with its own deadline.
  // Without a runtime (a standalone definition) there is nothing to hand the
  // process to, so the deadline cancels as before.
  if bg_runtime is Some(runtime) {
    let exec = runtime.spawn_foreground_retained(
      prog,
      argv,
      run_cwd,
      OutputCapBytes,
      // Same EOF-on-stdin contract as every other path here: never hand the
      // snippet the engine's fd 0.
      stdin=@process.redirect_from_file(empty_stdin),
    )
    // A cancelled turn must not leak the child: stop it before unwinding.
    errdefer exec.request_stop()
    // `wait`, not `wait_or_invalid`. That one returns early on the first non-UTF-8
    // byte, for a caller that fails fast on binary output — and this is not one:
    // reporting with the child still running would leave it going while
    // `defer cleanup()` removes its build directory underneath it, and the exit
    // code below would be invented. The exit is what this waits for either way,
    // so asking for the early wake only put the rest of the wait outside the
    // deadline. Expiry needs nothing special: it detaches like any other long run.
    let finished = @async.with_timeout_opt(auto_background_after_ms, () => {
      exec.wait()
    })
    let saw_binary = exec.had_invalid_utf8()
    if finished is None {
      let _ = exec.background()
      // A session- or lab-owned outer directory keeps only durable `tmp`
      // results. A standalone runtime has no later owner, so it reclaims the
      // whole fallback directory once the process is terminal.
      let terminal_cleanup_path = if handoff_dir_has_owner {
        build_dir
      } else {
        dir
      }
      let terminal_cleanup : async () -> Unit = () => {
        @async.protect_from_cancel(() => {
          @fs.rmdir(terminal_cleanup_path, recursive=true) catch {
            _ => ()
          }
        })
      }
      // A staged job's label carries the phase marker: the notice and the job
      // listing then say on their face that the build already succeeded, so a
      // later nonzero exit reads as the program's — job_output shows pure
      // program output and its `exit=N` is the program's own by construction.
      let id = runtime.adopt(
        exec,
        command=if staged {
          "mbtx run (build ok): \{@agent_tool.brief_line(input.source, limit=64)}"
        } else {
          "mbtx: \{@agent_tool.brief_line(input.source, limit=64)}"
        },
        sandboxed_command?,
        output_rewrites=temp_path_rewrites([real, build_dir]),
        moonrun_policy_active=policy_active,
        on_terminal=terminal_cleanup,
      )
      job_owns_cleanup = true
      let handoff = if staged {
        "mbtx: the build succeeded and the RUNNING PROGRAM was still going after \{duration_label(auto_background_after_ms)}, so it moved to the background as job \{id} (nothing was lost; any later nonzero exit is the program's own). Read its output with job_output (job_id=\"\{id}\") and stop it with job_stop (job_id=\"\{id}\")."
      } else {
        "mbtx: still running after \{duration_label(auto_background_after_ms)}, so it moved to the background as job \{id} (nothing was lost). Read its output with job_output (job_id=\"\{id}\") and stop it with job_stop (job_id=\"\{id}\")."
      }
      // Explicitly requested compiler warnings must not vanish because the
      // program outlived the grace: they exist only in the build phase's
      // capture, so this response is their one ride to the model.
      return @agent_tool.respond(
        with_build_notes(build_notes, handoff),
        brief="mbtx → bg \{id}",
      )
    }
    let raw = exec.head()
    let exit_code = exec.exit_code().unwrap_or(-1)
    // The retained execution is KILLED once output passes the inline cap, so a
    // clipped head means a stopped program, not a quiet one — say which.
    let output_limit_reached = exec.over_inline_cap() || exec.output_truncated()
    // A denial can land past the rendered head — a snippet floods, THEN hits
    // it — so scan the retained output on disk with the same bounded,
    // chunked walk the redirected path uses. A memory-only execution (no
    // session temp dir) has no such file, and there the head is all there is.
    let denial_scan_source = exec.spill_path()
    let sandbox_denied = refusal_guidance(
      sandboxed_command,
      denial_scan_source,
      raw,
      escalation=approval is Some(_),
      policy_active~,
    )
    exec.discard()
    let text = rewrite_temp_paths(raw, [real, build_dir])
    let body = with_build_notes(
      build_notes,
      finished_body(text, exit_code, staged~),
    )
    let body = if output_limit_reached {
      "\{body}\n[mbtx: output passed the fixed \{OutputCapBytes}-byte inline limit, so the program was STOPPED and this is only what it printed first. Retrying the same call will hit the same limit. Redirect bulky child output with `stdout=ToFile(path)` where `path` is under `@fs.tmpdir()`, then have that same snippet read the file and print only the needed excerpt before it exits.]"
    } else {
      body
    }
    let body = if saw_binary {
      "\{body}\n[mbtx: the program emitted non-UTF-8 bytes; the text above is a lossy rendering.]"
    } else {
      body
    }
    let body = if sandbox_denied is Some(guidance) {
      "\{body}\n\n\{guidance}"
    } else {
      body
    }
    return @agent_tool.respond(
      body,
      is_error=exit_code != 0 ||
        sandbox_denied is Some(_) ||
        output_limit_reached,
      brief="mbtx (exit=\{exit_code})",
    )
  }
  let result = @async.with_timeout_opt(foreground_timeout_ms, () => {
    let exit_code = @process.run(
      prog,
      argv,
      cwd=run_cwd.unwrap_or("."),
      inherit_env=true,
      stdin=@process.redirect_from_file(empty_stdin),
      stdout=@process.redirect_to_file(log, append=true),
      stderr=@process.redirect_to_file(log, append=true),
      no_console_window=true,
    )
    (exit_code, read_capped(log))
  })
  // A refusal is this tool's confinement firing, not an environment fault:
  // explain it (the raw OS error is otherwise a dead end) and treat the run as
  // failed even if the snippet swallowed the error and exited 0 — a swallowed
  // denial still means the access it needed did not happen. It runs for the
  // timeout arm too: a snippet can print a caught denial and then hang.
  let sandbox_denied = refusal_guidance(
    sandboxed_command,
    Some(log),
    "",
    escalation=approval is Some(_),
    policy_active~,
  )
  let action = match result {
    Some((exit_code, raw)) => {
      // Rewrite the throwaway temp path to `source` so the model reads
      // `source:LINE:COL` about its own input, not a random temp path.
      let text = rewrite_temp_paths(raw, [real, build_dir])
      // PREPEND the exit status so it survives the agent loop's outer 60k
      // result clamp (which cuts the tail); the output cap is below 60k so
      // both the status line and the body are retained.
      let body = with_build_notes(
        build_notes,
        finished_body(text, exit_code, staged~),
      )
      let body = if sandbox_denied is Some(guidance) {
        "\{body}\n\n\{guidance}"
      } else {
        body
      }
      @agent_tool.respond(
        body,
        is_error=exit_code != 0 || sandbox_denied is Some(_),
        brief="mbtx (exit=\{exit_code})",
      )
    }
    None => {
      // The snippet may have printed useful output before it hung; the log is
      // still on disk (cleanup runs below), so surface the captured prefix
      // instead of discarding it behind a generic timeout message. The status
      // line stays first so it survives the outer result clamp.
      let partial = rewrite_temp_paths(read_capped(log), [real, build_dir])
      let head = timeout_head(foreground_timeout_ms, staged~)
      let body = if partial.is_blank() {
        head
      } else {
        "\{head}\n[partial output before the timeout]\n\{partial}"
      }
      let body = if sandbox_denied is Some(guidance) {
        "\{body}\n\n\{guidance}"
      } else {
        body
      }
      // Requested compiler warnings live only in the build phase's capture, so
      // a run that never finished must still carry them out.
      @agent_tool.respond(
        with_build_notes(build_notes, body),
        is_error=true,
        brief="mbtx (timeout)",
      )
    }
  }
  action
}

///|
/// Result of the synchronous wasm BUILD phase: the runnable artifact plus any
/// build output worth carrying into the final report (compiler warnings under
/// `warning: "on"`), or a ready-to-return report for a build that failed,
/// timed out, or produced no artifact.
priv enum BuildOutcome {
  Built(artifact~ : String, notes~ : String)
  NotBuilt(@agent_tool.ToolAction)
}

///|
/// PHASE 1 of a wasm run: build the snippet with `moon run --build-only`,
/// synchronously, on its own wall-clock bound. A nonzero exit here is a BUILD
/// failure by construction — the run phase never starts — which is what makes
/// the stage labels trustworthy without probing artifacts or parsing output:
/// `moon run` alone exits 1 for a rejected build and a trapped program alike,
/// and diagnostics in a merged stream prove nothing (a snippet legitimately
/// runs `moon check` as a child process).
///
/// On success moon prints `{"artifacts_path":[…]}` naming the runnable; that
/// line is consumed here — moon's own statement of the layout, so the tool
/// assumes none — with the single-file layout as a fallback for a moon
/// without the report line.
async fn build_snippet(
  build_dir~ : String,
  run_cwd~ : String?,
  warning~ : Bool,
  build_timeout_ms~ : Int,
  empty_stdin~ : String,
  rewrite_bases~ : Array[String],
  confine~ : async (String, Array[String]) -> @sandbox.SandboxedCommand?,
) -> BuildOutcome {
  let build_argv = [
    "run",
    "-q",
    "\{build_dir}/snippet.mbtx",
    "--build-only",
    "--target",
    "wasm",
    "--target-dir",
    build_dir,
    ..if !warning {
      ["--warn-list", WarnOffList]
    },
  ]
  let (prog, argv) = match confine("moon", build_argv) {
    Some(command) => (command.program(), command.args())
    None => ("moon", build_argv)
  }
  // Its own log file, so build diagnostics and program output never share a
  // stream: warnings stay attributable to the build, and the run phase's
  // policy-refusal scan never reads build chatter.
  let build_log = "\{build_dir}/build.log"
  @fs.write_file(build_log, "", create_mode=CreateOrTruncate)
  let result = @async.with_timeout_opt(build_timeout_ms, () => {
    let exit_code = @process.run(
      prog,
      argv,
      cwd=run_cwd.unwrap_or("."),
      inherit_env=true,
      stdin=@process.redirect_from_file(empty_stdin),
      stdout=@process.redirect_to_file(build_log, append=true),
      stderr=@process.redirect_to_file(build_log, append=true),
      no_console_window=true,
    )
    (exit_code, read_capped(build_log))
  })
  guard result is Some((exit_code, raw)) else {
    return NotBuilt(
      @agent_tool.respond(
        "mbtx: the BUILD did not finish within \{duration_label(build_timeout_ms)} and was cancelled — the program never ran. Compilation or a dependency download stalled; retrying is faster than it looks (downloaded modules are cached).",
        is_error=true,
        brief="mbtx (build timeout)",
      ),
    )
  }
  let text = rewrite_temp_paths(raw, rewrite_bases)
  if exit_code != 0 {
    // The exit code is moon's and it is kept: build-stage faults are not all
    // exit 1 (a dependency-resolution fault exits 255), and distinct codes
    // are diagnostic. The output below says whether the compiler rejected
    // `source` or the toolchain faulted.
    return NotBuilt(
      @agent_tool.respond(
        if text.is_blank() {
          "mbtx: the BUILD failed (exit \{exit_code}) with no output — the program never ran"
        } else {
          "[mbtx: BUILD failed (exit \{exit_code}) — the program never ran; the output below is the build's]\n\{text}"
        },
        is_error=true,
        brief="mbtx (build failed, exit=\{exit_code})",
      ),
    )
  }
  let artifact = parse_artifacts_path(raw).unwrap_or(
    "\{build_dir}/wasm/debug/build/single/single.wasm",
  )
  let artifact_present = @fs.exists(artifact) catch {
    error if @async.is_being_cancelled() => raise error
    // A stat FAULT is not absence (AGENTS.md: never fold unrelated errors
    // into the missing case): name the filesystem failure instead of
    // reporting a missing artifact. Either way the run cannot proceed, so
    // both are build-stage faults — they just say different true things.
    error =>
      return NotBuilt(
        @agent_tool.respond(
          "mbtx: the build succeeded but its artifact could not be verified (\{error}) — a filesystem fault, not a problem in `source`.",
          is_error=true,
          brief="mbtx (build fault)",
        ),
      )
  }
  guard artifact_present else {
    return NotBuilt(
      @agent_tool.respond(
        "mbtx: the build reported success but its artifact is missing (\{artifact}) — a toolchain fault, not a problem in `source`; retry, and report it if it persists.",
        is_error=true,
        brief="mbtx (build fault)",
      ),
    )
  }
  Built(artifact~, notes=cap_build_notes(strip_artifact_report(text)))
}

///|
fn cap_build_notes(notes : String) -> String {
  if notes.length() <= BuildNotesCapChars {
    notes
  } else {
    "\{notes.clamped_view(end=BuildNotesCapChars)}\n[mbtx: build warnings truncated at \{BuildNotesCapChars} characters]"
  }
}

///|
/// The artifact path `moon run --build-only` reports on success, read from
/// the last `{"artifacts_path":[…]}` line of its output. `None` for a moon
/// that does not print one.
///
/// A malformed or truncated report line is deliberately treated like an
/// absent one, not surfaced as a fault: both degrade to the single-file
/// layout fallback, and the existence check that follows validates WHICHEVER
/// path was chosen — a wrong guess surfaces as a named build fault, never as
/// a silent misrun. That holds even if the layout fallback is itself stale:
/// the guard then reports a missing artifact, still a correctly-classified
/// build-stage fault — only the diagnostic detail differs, and naming the
/// parse failure instead would matter only on a moon that broke its report
/// line AND its layout at once. Failing the call on a report the fallback
/// would have covered would only make the tool more brittle.
fn parse_artifacts_path(output : String) -> String? {
  let mut found : String? = None
  for line in output.split("\n") {
    let line = line.trim()
    guard line.has_prefix("{\"artifacts_path\"") else { continue }
    let parsed = @json.parse(line.to_owned()) catch { _ => continue }
    if parsed is { "artifacts_path": [String(path), ..], .. } {
      found = Some(path)
    }
  }
  found
}

///|
/// A successful build's output with moon's machine-facing artifact report
/// removed: what remains — compiler warnings under `warning: "on"`, usually
/// nothing — is for the model to read.
fn strip_artifact_report(text : String) -> String {
  [..text.split("\n")]
  .filter(line => !line.trim().has_prefix("{\"artifacts_path\""))
  .join("\n")
  .trim()
  .to_owned()
}

///|
/// The status framing for a finished run. `staged` is the wasm two-phase
/// path, where the build already succeeded synchronously before this process
/// started — so a failure here is from the RUN by construction, and saying so
/// is what keeps the model from re-reading a runtime trap as a compile error.
/// The single-shot targets keep the plain framing: their one exit code covers
/// both stages and claims neither.
fn finished_body(text : String, exit_code : Int, staged~ : Bool) -> String {
  if exit_code == 0 {
    return if text.is_blank() {
      "mbtx: program exited 0 with no output"
    } else {
      text
    }
  }
  if staged {
    if text.is_blank() {
      "mbtx: the build succeeded, then the run exited \{exit_code} with no output"
    } else {
      "[mbtx: exited \{exit_code} at RUNTIME — the build succeeded; this failure is from the run, not the build]\n\{text}"
    }
  } else if text.is_blank() {
    "mbtx: program exited \{exit_code} with no output"
  } else {
    "[mbtx: exited \{exit_code}]\n\{text}"
  }
}

///|
/// The first line of a foreground timeout report. On the staged wasm path the
/// build had already succeeded, so only the program can be what never
/// finished; a single-shot target keeps the two-sided hedge.
fn timeout_head(foreground_timeout_ms : Int, staged~ : Bool) -> String {
  let bound = duration_label(foreground_timeout_ms)
  if staged {
    "mbtx: timed out after \{bound} and was cancelled — the build had already succeeded, so it is the PROGRAM that did not finish (an infinite loop, or waiting on something that never arrived)."
  } else {
    "mbtx: timed out after \{bound} and was cancelled — the program did not finish (an infinite loop, or a build that never completed)."
  }
}

///|
/// Prepend the build phase's surviving output (warnings) to the run's report,
/// so `warning: "on"` still shows the compiler's voice ahead of the program's.
fn with_build_notes(notes : String, body : String) -> String {
  if notes.is_blank() {
    body
  } else {
    "\{notes}\n\{body}"
  }
}

///|
/// The guidance for a refusal this run's confinement produced, or `None` when
/// the output shows none.
///
/// Both layers are read, in the order they can fire. The moonrun policy binds
/// the snippet itself and refuses first — a write outside its roots never
/// reaches the kernel — and it applies on every platform, so it is checked
/// whether or not a profile was prepared. A `sandbox-exec` profile refuses only
/// what got past that, and only for the roles that carry one; its text comes
/// from the prepared command, so it always describes the profile that actually
/// ran.
///
/// `log_path` is the retained output on disk, scanned past the display cap; a
/// memory-only execution has none and `head` is then all there is.
async fn refusal_guidance(
  sandboxed_command : @sandbox.SandboxedCommand?,
  log_path : String?,
  head : String,
  escalation~ : Bool,
  policy_active~ : Bool,
) -> String? {
  async fn shows(reports : (String) -> Bool) -> Bool {
    match log_path {
      Some(path) =>
        log_shows_denial(path, reports, budget_bytes=DenialScanBudgetBytes)
      None => reports(head)
    }
  }

  // A non-wasm or escalated run was given no moonrun policy, so nothing it
  // prints can be that policy refusing something. The marker is ordinary guest
  // text in that case; classifying it would turn a successful run into an error.
  if policy_active && shows(@sandbox.output_reports_policy_refusal) {
    // The escalating variant only where a channel exists AND this is a
    // foreground report: its wording assumes nothing ran, which is true here
    // and false of `job_output`, whose job worked before it was refused.
    return Some(
      if escalation {
        @sandbox.policy_refusal_with_escalation
      } else {
        @sandbox.policy_refusal_feedback
      },
    )
  }
  guard sandboxed_command is Some(command) else { return None }
  if shows(output => command.output_reports_denial(output)) {
    return Some(command.denial_feedback())
  }
  None
}

///|
/// Rewrite moon's throwaway temp paths back to `source` in its diagnostics, for
/// both `/` and `\` separators — moon reports the canonical native path (with
/// backslashes on Windows), so `source:LINE:COL` shows on every host rather than
/// a random `_build` path leaking through.
fn temp_path_rewrites(bases : Array[String]) -> Array[(String, String)] {
  let rewrites : Array[(String, String)] = []
  for base in bases {
    for sep in ["/", "\\"] {
      // `.mbtx` first: replacing `snippet.mbt` before it would leave a stray
      // `x` (`sourcex`). `snippet.mbt` is the generated file at the top of the
      // target-dir; `_build/snippet.mbt` covers the older build layout.
      rewrites.push(("\{base}\{sep}snippet.mbtx", "source"))
      rewrites.push(("\{base}\{sep}_build\{sep}snippet.mbt", "source"))
      rewrites.push(("\{base}\{sep}snippet.mbt", "source"))
    }
  }
  rewrites
}

///|
fn rewrite_temp_paths(text : String, bases : Array[String]) -> String {
  let mut out = text
  for rewrite in temp_path_rewrites(bases) {
    let (old, replacement) = rewrite
    out = out.replace_all(old~, new=replacement)
  }
  out
}

///|
/// Chunk size for the log denial scan, and the carry kept when a single line
/// outgrows a chunk — the tail is far larger than any denial pattern, so only
/// a pattern split exactly at a trim point of a >64KB line is missed.
const DenialScanChunkBytes : Int = 65_536

///|
const DenialScanCarryTailChars : Int = 4_096

///|
/// Byte budget for the denial scan at EACH end of the log. The scan runs after
/// the run's 60s deadline has already expired, so its work must not scale with
/// how hard a snippet flooded stdout — a fixed budget keeps the tool call's
/// wall-clock bounded whatever the log's size.
const DenialScanBudgetBytes : Int = 16_777_216

///|
/// Whether the on-disk output log shows a denial, as `reports_denial` reads
/// one. Detection must not be bounded by the 48KB display cap (a snippet can
/// flood past it before the denied access), but it must stay bounded in bytes
/// and time: a log larger
/// than twice `budget_bytes` is scanned at its head and tail only. An
/// uncaught denial crashes the snippet, so its OSError line is the log's tail;
/// a caught-and-printed denial lands where it happened, inside the head for
/// realistic probes. Only a denial buried in the MIDDLE of a >32MB flood is
/// missed — the price of a bounded scan. Production passes
/// `DenialScanBudgetBytes` as `budget_bytes`; tests pass a small budget to
/// exercise the head/tail split.
async fn log_shows_denial(
  path : String,
  reports_denial : (String) -> Bool,
  budget_bytes~ : Int,
) -> Bool {
  let file = @fs.open(path, mode=ReadOnly) catch { _ => return false }
  defer file.close()
  let size = file.size() catch {
    error if @async.is_being_cancelled() => raise error
    _ => return false
  }
  let budget = budget_bytes.to_int64()
  if size <= budget * 2 {
    denial_scan_region(file, 0, size, reports_denial)
  } else {
    denial_scan_region(file, 0, budget, reports_denial) ||
    denial_scan_region(file, size - budget, budget, reports_denial)
  }
}

///|
/// Scan `len` bytes of `file` starting at `start` for a source-write denial,
/// chunked with a trailing-partial-line carry so a denial line split across
/// chunk boundaries is reassembled before the line-level detector sees it. (A
/// region that starts mid-line can only truncate a pattern, never fabricate
/// one, so the tail region needs no line alignment.)
async fn denial_scan_region(
  file : @fs.File,
  start : Int64,
  len : Int64,
  reports_denial : (String) -> Bool,
) -> Bool {
  let buf = FixedArray::make(DenialScanChunkBytes, b'\x00')
  let mut carry = ""
  let mut position = start
  let end = start + len
  while position < end {
    let remaining = end - position
    let want = if remaining < DenialScanChunkBytes.to_int64() {
      remaining.to_int()
    } else {
      DenialScanChunkBytes
    }
    let n = file.read_at(buf, position~, len=want) catch {
      error if @async.is_being_cancelled() => raise error
      _ => break
    }
    if n <= 0 {
      break
    }
    position += n.to_int64()
    let text = carry + @utf8.decode_lossy(Bytes::from_array(buf[:n]))
    // Split at the last newline: everything before it is whole lines the
    // detector can judge now, everything after is the partial line to carry.
    match text.rev_split_once("\n") {
      Some((whole_lines, partial_line)) => {
        if reports_denial(whole_lines.to_owned()) {
          return true
        }
        carry = partial_line.to_owned()
      }
      None => carry = text
    }
    // A single line larger than a chunk must not grow the carry unboundedly:
    // scan what accumulated, keep only a pattern-sized tail.
    if carry.length() > DenialScanChunkBytes {
      if reports_denial(carry) {
        return true
      }
      carry = carry
        .clamped_view(start=carry.length() - DenialScanCarryTailChars)
        .to_owned()
    }
  }
  reports_denial(carry)
}

///|
/// Read at most `OutputCapBytes` from the process output file, decoding lossily
/// and appending a marker when there was more. The file — not memory — absorbs
/// a flood; only this bounded prefix is ever materialized.
async fn read_capped(path : String) -> String {
  let file = @fs.open(path, mode=ReadOnly) catch { _ => return "" }
  defer file.close()
  let buf = FixedArray::make(OutputCapBytes, b'\x00')
  let mut filled = 0
  while filled < OutputCapBytes {
    let n = file.read(buf, offset=filled, max_len=OutputCapBytes - filled)
    if n <= 0 {
      break
    }
    filled += n
  }
  let text = @utf8.decode_lossy(Bytes::from_array(buf[:filled]))
  // If we filled the cap there may be more; note the truncation.
  if filled == OutputCapBytes {
    "\{text}\n[mbtx: output truncated at \{OutputCapBytes} bytes]"
  } else {
    text
  }
}

///|
/// The `mbtx` argument schema. `escalation` adds `escalated` only when an
/// approval channel is wired; otherwise every use would come back refused, and
/// the cheapest way not to waste a turn is for the argument not to exist.
fn schema(escalation~ : Bool, hosting~ : Bool) -> Json {
  {
    "type": "object",
    "properties": Json(
      Map(
        [
          ("source", Json({ "type": "string" })),
          (
            "target",
            {
              "type": "string",
              "enum": ["wasm", "wasm-gc", "js", "llvm"],
              "description": "Backend to run on; defaults to wasm, which is the sandboxed one. The alternatives run pure computation only — they cannot spawn commands or touch files.",
            },
          ),
          (
            "cwd",
            {
              "type": "string",
              "description": "Working directory the program runs in (relative paths resolve against the workspace root); defaults to the workspace root.",
            },
          ),
          (
            "warning",
            {
              "type": "string",
              "enum": ["off", "on"],
              "description": (
                #|Whether compiler warnings appear in the output; defaults to off (a snippet
                #|is a throwaway script, so unused-variable style noise is suppressed). Set
                #|"on" only when the warnings themselves are what you are probing.
              ),
            },
          ),
          ..if escalation {
            [
              (
                "escalated",
                Json({
                  "type": "boolean",
                  "description": (
                    #|Ask the user to run this snippet with NO sandbox policy — any program may
                    #|be spawned and the snippet may write anywhere. The call blocks on a
                    #|person's answer, and a refusal or an unanswered request means nothing ran.
                    #|Use it only when the allowed programs genuinely cannot do the job, and say
                    #|in the snippet's own code what it needs the extra reach for: the user is
                    #|shown this program, and decides on it.
                  ),
                }),
              ),
            ]
          },
          ..if hosting {
            [
              (
                "subrun",
                Json({
                  "type": "boolean",
                  "description": (
                    #|Set true when this snippet DELEGATES: runs a `moonbitlang/workflow`
                    #|workflow whose children are subagents (`import "moonbitlang/workflow/hosted"`,
                    #|then `@hosted.context()` and `ctx.run(wf => ...)`). Only then are child
                    #|sessions reserved and handed to the snippet, so its subagents get their own
                    #|transcripts and appear in the desktop. Leave it unset for every other
                    #|snippet: reserving children a script never starts wastes ids and announces
                    #|a workflow that does not exist. A snippet may start at most 32 children.
                  ),
                }),
              ),
            ]
          },
        ],
      ),
    ),
    "required": ["source"],
  }
}

///|
/// The `mbtx` tool description.
///
/// Holds the tool-local contract every role must see: the admitted child
/// processes, refusal and escalation behavior, isolation, limits, and the
/// arguments this build actually supports. What a shell's utilities are in
/// MoonBit is the system prompt's to teach — it is how a snippet does its
/// work, not advice handed out after a refusal — so the refusal text below
/// names no table. The default system prompt owns the
/// `moonbitlang/async/shell` tutorial and worked examples; those teach one
/// role's workflow rather than describing what the tool enforces.
///
/// The spawn list is prose about `spawnable_commands`, kept by hand so the
/// groupings survive; adding an entry there means editing this text too.
///
/// `background` selects the execution-time contract the caller actually wired:
/// automatic handoff with a job runtime, or a longer cancelling timeout without
/// one. `escalation` is conditional too, and matters more: the
/// refused-command paragraph above tells the model to say so rather than work
/// around a refusal, and where escalation IS available that advice would be
/// wrong — there is a sanctioned way to ask. The paragraph that says so must
/// appear exactly where the way exists.
fn description(
  background~ : Bool,
  escalation~ : Bool,
  hosting~ : Bool,
  auto_background_after_ms~ : Int,
  foreground_timeout_ms~ : Int,
  build_timeout_ms~ : Int,
) -> String {
  // The one sentence here that depends on what this build can actually do.
  //
  // Without an approval channel a refusal really is the end of the road, and
  // "say so" is the whole of the advice. With one there is a sanctioned door,
  // and a description that does not name it leaves the model to do what it did
  // in practice: quietly reconstruct the refused command out of allowed parts
  // and never mention that asking was an option. Reading the justfile and
  // running the three `moon` commands it expands to is a fine outcome — being
  // unable to weigh it against asking is not.
  //
  // Both spellings keep the same stance. Routing AROUND a refusal is still the
  // thing not to do; what changes is whether there is a third answer beside
  // "find the replacement" and "give up".
  let refusal_advice = if escalation {
    (
      #|Anything else is REFUSED, including the obvious ones. When a refused command
      #|is genuinely what the task needs, two answers are legitimate: reach for the
      #|MoonBit replacement, or — when no replacement is faithful and the
      #|refused program IS the task — retry that one snippet with escalated=true and
      #|let the user decide. Reconstructing the refused command out of allowed parts
      #|without saying so is the answer that is not.
    )
  } else {
    (
      #|Anything else is REFUSED, including the obvious ones; if a refused command is
      #|genuinely what the task needs, say so rather than working around it.
    )
  }
  let base_head =
    #|Compile and run a self-contained MoonBit program and return its merged
    #|stdout/stderr and exit status. This is BOTH your command runner and your
    #|scripting surface: there is no shell tool, so commands, IO, and computation
    #|happen inside the submitted MoonBit program.
    #|
    #|`source` is the whole program. Diagnostics are rewritten to `source:LINE:COL`
    #|about your input; `target` defaults to wasm, the sandboxed backend.
    #|
    #|## Which programs a snippet may start
    #|
    #|These, and nothing else:
    #|
    #|- `moon` — check, test, build, bench, run, fmt, info, add, remove, update,
    #|  install, tree, search, clean, new, ide, doc, explain, coverage, cram,
    #|  package, version, plus `publish --dry-run`. (Not plain `publish`, `login` or `register`.)
    #|- `proton_cli` — `--version`, `--help`, new, dev, build, package, doctor,
    #|  cef, and updater. Set `Cmd.cwd` for the project directory; the global
    #|  `-C`/`--cwd` options before the subcommand are refused.
    #|- `git` — status, log, diff, show, blame, describe, rev-parse, rev-list,
    #|  show-ref, for-each-ref, cat-file, check-ignore, merge-base, range-diff,
    #|  ls-files, ls-tree, ls-remote, shortlog, grep, branch, tag, remote, reflog,
    #|  add, commit, checkout, switch, restore, reset, revert, rm, init, fetch,
    #|  push, rebase; plus `submodule update|status`, `worktree list|add|prune`,
    #|  `stash list|show`. Not `config`. A global option BEFORE the subcommand
    #|  (`-c`, `-C`, `--git-dir`, `--work-tree`) is refused.
    #|- `gh` — pr, issue, run, `repo view`, api, `auth status`.
    #|- `codex` — review (read-only review of the current branch/diff; not
    #|  `exec`, `install`, or a bare `codex`).
    #|- `rg` and `diff`.
  let base_tail =
    #|## Isolation and limits
    #|
    #|- A snippet runs with the workspace as its working directory, so RELATIVE paths
    #|  reach workspace files; pass `cwd` to run elsewhere. Its own build artifacts
    #|  stay in a temp dir — your `_build` is untouched.
    #|- A snippet's imports resolve against the REGISTRY, not your uncommitted edits.
    #|  To exercise working-tree code, add a `*_test.mbt` to that package and run
    #|  `moon test` as an admitted child process.
    #|- A snippet READS anywhere and WRITES only its own `@fs.tmpdir()`. Changing a
    #|  workspace file is the file tools' job, or a command's — `moon fmt`, `git
    #|  checkout` and friends are child processes and run normally. A write refusal
    #|  is that rule firing, not a filesystem fault to debug or route around.
    #|- DNS and outbound connections are allowed. A snippet may bind/listen only on
    #|  IPv4 or IPv6 localhost; wildcard and external-interface binds are refused.
    #|  These network rules do not constrain an allowed child process.
    #|- Compiler warnings for the snippet are suppressed; pass `warning: "on"` to
    #|  see them.
    #|- For independent commands or probes, emit SEVERAL `mbtx` calls in the SAME
    #|  assistant turn — they run and come back together, saving a model round-trip
    #|  each.
  // Three raw pieces joined at the seam, rather than one interpolating block:
  // the tail carries `\{@fs.tmpdir()}` inside a code sample, which a `$|` block
  // would try to evaluate.
  let base =
    $|\{base_head}
    $|
    $|\{refusal_advice}
    $|
    $|\{base_tail}
  // The escalation paragraph goes BEFORE the background one so it sits next to
  // the refusal rules it qualifies.
  let base = if !escalation {
    base
  } else {
    (
      $|\{base}
      $|
      $|## When the allowlist genuinely is not enough
      $|
      $|Set escalated=true to ask the user to run one snippet with NO policy: any
      $|program, and writes anywhere. The call then BLOCKS until a person answers, so
      $|it costs their attention — spend it only when the allowed programs cannot do
      $|the job, never as a first attempt or to skip reading a refusal. A refusal is
      $|final for the task; a withdrawn request decided nothing and ran nothing. Either way
      $|the snippet did not run, and the reply says which happened. The user sees this
      $|program and decides on it, so write it to be read: no extra reach beyond what
      $|the task needs, and the reason evident in the code itself.
    )
  }
  let foreground_bound = duration_label(foreground_timeout_ms)
  let handoff_bound = duration_label(auto_background_after_ms)
  let build_bound = duration_label(build_timeout_ms)
  // The staged-execution paragraph is shared by both execution-time variants:
  // the build/run split and its failure labels hold with or without a job
  // runtime; only what happens to a long RUN differs.
  let staging =
    $|On the default wasm target the snippet is BUILT first, synchronously (up to
    $|\{build_bound}): a failed build returns immediately, labeled `BUILD failed`, and the
    $|program never starts — so a failure labeled `at RUNTIME` really is from the
    $|run. Build time does not count against the run's own allowance below.
  if !background {
    return (
      $|\{base}
      $|
      $|## Execution time
      $|
      $|\{staging}
      $|
      $|This context has no background-job runtime. A run may stay in the foreground
      $|for up to \{foreground_bound}; at that deadline it is cancelled and reported as a timeout.
    )
  }
  // Delegation is described only where it can be granted. A session with no
  // durable store has no argument to advertise, and telling the model about
  // one it cannot use costs it a refused call to find that out.
  let delegation = if hosting {
    (
      #|
      #|## Delegating to subagents
      #|
      #|Set `subrun: true` when this snippet runs a `moonbitlang/workflow` workflow whose
      #|children are subagents — and only then. Import "moonbitlang/workflow" and
      #|"moonbitlang/workflow/hosted", then `guard @hosted.context() is Some(ctx)` and
      #|`ctx.run(wf => ...)`; inside, `wf.agent(prompt=..., kind="explore")` runs one
      #|scout, and `@workflow.parallel([...])` with `@workflow.attempt` fans several out
      #|concurrently. The children get their own transcripts and appear in the desktop.
      #|A snippet may start at most 32 children. Without the flag no child sessions are
      #|reserved and the engine is not on the spawn allowlist: a workflow written
      #|without it runs with no handoff and its subagents are refused.
    )
  } else {
    ""
  }
  // The blank `$|` line is the paragraph break: without it the section heading
  // runs onto the base text's last line and stops reading as a heading.
  (
    $|\{base}
    $|
    $|## Long-running work
    $|
    $|\{staging}
    $|
    $|Every call's RUN stays inline for up to \{handoff_bound}. If it is still running, it AUTOMATICALLY
    $|moves to a background job and returns the job id; no background flag or duration
    $|guess is needed. A wasm job is always the RUNNING PROGRAM — its build already
    $|succeeded, so the job's output and exit code are the program's own. A completion
    $|notice arrives when it finishes, so never wait with sleep loops or repeated
    $|polling: keep working and act on the notice. Read recent output with job_output
    $|(use one bounded wait_ms call only when the result is needed now), and cancel it
    $|with job_stop.
    $|\{delegation}
  )
}
