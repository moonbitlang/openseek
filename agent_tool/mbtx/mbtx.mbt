///|
/// A snippet is bounded to this wall-clock so a runaway loop or a build that
/// never finishes cannot block the whole turn. On expiry the run is cancelled
/// (which tears down the moon subprocess) and reported as a timeout. Sized for
/// commands, not just compute: a snippet runs whole `moon test` cycles, and a
/// fresh workspace's first build downloads and compiles its dependencies.
const RunTimeoutMs : Int = 300_000

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
/// is what advertises the `escalated` argument at all — the same rule
/// `bg_runtime` follows for `run_in_background`: a build with nobody to ask
/// does not offer an argument whose every use would come back refused.
pub fn definition(
  workspace_root~ : String,
  read_only? : Bool = false,
  bg_runtime? : @bgjobs.BgJobRuntime,
  job_dir? : String,
  scratch_dir? : String,
  worker_sandbox? : WorkerSandbox,
  run_timeout_ms? : Int = RunTimeoutMs,
  approval? : @agent_runtime.ApprovalChannel,
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
    ),
    schema=JsonSchema(
      schema(background=bg_runtime is Some(_), escalation=approval is Some(_)),
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
        run_timeout_ms~,
        next_background~,
        approval?,
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
  // The wall-clock bound, injectable so a test can exercise the deadline
  // without waiting out the real one.
  run_timeout_ms~ : Int,
  next_background~ : Ref[Int],
  approval? : @agent_runtime.ApprovalChannel,
) -> @agent_tool.ToolAction {
  let input = @decode.decode(arguments) catch {
    error =>
      return @agent_tool.ToolAction::respond(
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
    return @agent_tool.ToolAction::respond(
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
      return @agent_tool.ToolAction::respond(
        "error: mbtx cwd does not exist: \{c}",
        is_error=true,
      )
    }
    guard @fs.kind(c) is Directory else {
      return @agent_tool.ToolAction::respond(
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
  if input.run_in_background && bg_runtime is None {
    return @agent_tool.ToolAction::respond(
      "error: run_in_background is not available in this context",
      is_error=true,
    )
  }
  // Escalation only means something on the backend the policy binds. The other
  // targets never had `--wasm-policy` passed to them in the first place — they
  // cannot spawn or touch files at all — so asking here would spend a person's
  // attention on a grant that changes nothing about the run.
  if input.escalated && input.target != "wasm" {
    return @agent_tool.ToolAction::respond(
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
      return @agent_tool.ToolAction::respond(
        escalation_refused(outcome),
        is_error=true,
        brief="mbtx (escalation \{escalation_brief(outcome)})",
      )
    }
    true
  } else {
    false
  }
  // A directory a job may take over must outlive this call, so it is numbered
  // inside the caller's job dir — reclaimed when the session's scope ends —
  // rather than a system temp dir that only this function ever revisits. That
  // covers BOTH ways a job takes over: an explicit `run_in_background`, and a
  // foreground run detached at its deadline, which is why this does not test
  // `run_in_background`.
  let background = input.run_in_background
  let dir = if job_dir is Some(scratch) {
    let dir = "\{scratch}/snippet-\{next_background.val}"
    next_background.val += 1
    @fs.mkdir(dir, recursive=true) catch {
      error if @async.is_being_cancelled() => raise error
      _ =>
        return @agent_tool.ToolAction::respond(
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
        return @agent_tool.ToolAction::respond(
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
        return @agent_tool.ToolAction::respond(
          "mbtx: could not create a temporary working directory.",
          is_error=true,
        )
    }
  }
  // Set once a background job takes over the directory (snippet, artifacts,
  // output log): either an explicit `run_in_background`, or a foreground run
  // detached at its deadline. `cleanup` runs on every exit path, so the flag —
  // not the request — decides whether reclaiming the directory is still ours.
  //
  // Handing it over is sound because a job only ever runs with a `job_dir`
  // wired, and that directory is reclaimed with the session's scope. The
  // `@fs.tmpdir` branch above has no such owner, but it is only taken when the
  // caller wired no job dir — which happens only if the session's own tmpdir
  // call failed, in which case the one above fails too and returns first.
  let job_owns_dir = Ref(false)
  async fn cleanup() -> Unit {
    if job_owns_dir.val {
      return
    }
    @async.protect_from_cancel(() => {
      @fs.rmdir(dir, recursive=true) catch {
        _ => ()
      }
    })
  }

  defer cleanup()
  @fs.write_file(
    "\{dir}/snippet.mbtx",
    input.source,
    create_mode=CreateOrTruncate,
  )
  let log = "\{dir}/output.log"
  // Pre-create the merged output file so both redirects open it; both append
  // so stdout and stderr interleave in write order.
  @fs.write_file(log, "", create_mode=CreateOrTruncate)
  // Give the snippet an EMPTY stdin (immediate EOF) rather than inheriting fd 0:
  // under `openseek serve`/TUI that fd is the JSONL control channel, and a
  // snippet reading `@stdio.stdin` would otherwise consume the engine's
  // prompt/steer/cancel commands (or block until the timeout). An empty temp
  // file is portable (no `/dev/null`/`NUL` special-casing).
  let empty_stdin = "\{dir}/stdin.empty"
  @fs.write_file(empty_stdin, "", create_mode=CreateOrTruncate)
  // moon's diagnostics point at the copied source under the build dir; the
  // canonical path anchors the diagnostic path rewrite below.
  let real = @fs.realpath(dir) catch { _ => dir }
  // The wasm backend is where moonrun's policy applies, so the policy file is
  // written for every run and passed alongside. `--wasm-policy` is silently
  // IGNORED on other backends, which is why `target` is not the model's choice
  // to make freely — see `decode`.
  let policy_path = "\{dir}/policy.json"
  // Scratch space for the snippet's own `@fs.tmpdir()`, kept beside the build
  // output rather than inside it so temp directories do not appear among moon's
  // artifacts. It goes away with `dir` when the run is cleaned up.
  let snippet_tmp = "\{dir}/tmp"
  @fs.mkdir(snippet_tmp) catch {
    error if @async.is_being_cancelled() => raise error
    _ => ()
  }
  // `cwd` is deliberately NOT a write root: naming where a program runs should
  // not also grant writing there, and reads are open, so a snippet can still
  // work in a directory it may not modify.
  let policy = wasm_policy_document(
    tmp_dir=snippet_tmp,
    extra_roots=[..scratch_dir.map(l => [l]).unwrap_or([])],
  )
  @fs.write_file(policy_path, policy.stringify(), create_mode=CreateOrTruncate)
  let moon_argv = [
    "run",
    "\{dir}/snippet.mbtx",
    "--target",
    input.target,
    "--target-dir",
    dir,
    // An approved escalation is exactly this: the policy file is still
    // written, and simply not passed. Widening the document instead was not
    // available — its `fs.write` roots are canonicalized existing paths with
    // no wildcard, and "any program" has no spelling in `process.allow` short
    // of enumerating one — so "no policy" is both the honest description of
    // what was approved and the only one the runtime can express.
    ..if input.target == "wasm" && !escalated {
      ["--wasm-policy", policy_path]
    },
    ..if !input.warning {
      ["--warn-list", WarnOffList]
    },
  ]
  // Wrap `moon run` in sandbox-exec for the roles that need a rule the wasm
  // policy cannot state: "may not write source". The policy's `fs` rules bind
  // the snippet and stop at the process boundary, so a spawned `moon fmt` is
  // beyond them, and a role defined by holding no editing tool needs that
  // covered in the kernel. The main agent is not such a role and takes no
  // profile — see below. Off macOS, or in a nested sandbox where a profile
  // cannot be applied, every role runs with the policy as its only bound.
  // The prepared command carries what it needs to classify its own denials, so
  // one showing up in the program's output can be recognized and explained.
  // The throwaway build dir is the writable subtree: if it falls INSIDE the
  // workspace root (e.g. `workspace_root=/tmp`, where `@fs.tmpdir` lands
  // under it) the shared deny would otherwise block moon's own generated
  // `snippet.mbt`.
  // The writable subtree has to contain the snippet's own build output. With a
  // lab wired the snippet builds inside it, so the lab covers both; otherwise
  // the build dir is the subtree. Choosing by where `dir` actually sits keeps
  // the two from disagreeing when a caller passes both a job dir and a lab.
  let writable_subtree = match scratch_dir {
    Some(lab) if dir.has_prefix(lab) => lab
    _ => dir
  }
  let sandboxed_command = match worker_sandbox {
    // Worker mode replaces the workspace source-write profile rather than
    // adding to it: a worker is supposed to write source, just only its own,
    // so the kernel denies its siblings' trees and the shared git dir instead
    // of denying source writes as such.
    Some(scope) =>
      @sandbox.SandboxedCommand::create_worker_if_available(
        Exec("moon", moon_argv),
        deny_roots=scope.deny_roots,
        worker_root=scope.worker_root,
        worker_admin_dir=scope.worker_admin_dir,
      )
    // The read-only roles (explore/review/audit) hold no editing tool, so "may
    // not write source" is the guarantee that defines them and it stays
    // kernel-enforced. The profile suits them for a second reason — it is
    // `(allow default)` minus source, so `moon check` can still write its
    // target dir inside the workspace, which a boundary profile denying the
    // workspace would take away.
    //
    // Read-only is its own parameter rather than being read off `scratch_dir`:
    // a caller that forgets the lab should lose the lab, not the sandbox.
    None if read_only =>
      @sandbox.SandboxedCommand::create_if_available(
        workspace_root,
        Exec("moon", moon_argv),
        writable_subtree~,
      )
    // The main agent runs with no kernel profile at all. Forbidding source
    // writes here would break the very commands it needs — `moon fmt`,
    // `moon info`, `git checkout` all rewrite source by definition — and the
    // other shape, denying writes globally and re-allowing an enumerated set,
    // was tried and withdrawn: every root it missed (`/dev` for git's
    // `/dev/null`, `/tmp` for `@fs.tmpdir`, the toolchain root, gh's cache)
    // surfaced as a bare EPERM in a live turn rather than in a test, and the
    // list only ever protected macOS.
    //
    // What is left bounding a child is the allowlist, which works everywhere:
    // it admits no shell, no interpreter and no ad-hoc rewriter, and it refuses
    // the git options that would point a command at another repository. That is
    // a bound on which commands exist, not on where they may write — the file
    // tools are not path-confined for this role either, so a profile here would
    // have been the only such rule in the tool set.
    None => None
  }
  let (prog, argv) = match sandboxed_command {
    Some(command) => (command.program(), command.args())
    None => ("moon", moon_argv)
  }
  if background && bg_runtime is Some(runtime) {
    // Compile in the FOREGROUND first. A detached run would otherwise report
    // a syntax or type error only through job_output, and with the throwaway
    // temp path instead of `source:LINE:COL` — the two things that make a
    // compile error readable. `--build-only` is the single-file equivalent of
    // a check: `moon check`/`moon build` do not accept a `.mbtx` script (the
    // first reports "no work to do", the second demands a Moon project).
    // TODO(upstream): teach `moon check` to accept a `.mbtx` script, and use
    // it here — building is more work than this preflight needs.
    let build_argv = [..argv]
    build_argv.push("--build-only")
    let build_log = "\{dir}/build.log"
    @fs.write_file(build_log, "", create_mode=CreateOrTruncate)
    // Bounded like every other run here: a first build downloads and compiles
    // dependencies, and a wedged fetch would otherwise hold the turn open —
    // exactly what asking for a background job was meant to avoid.
    let build_exit = @async.with_timeout_opt(run_timeout_ms, () => {
      @process.run(
        prog,
        build_argv,
        cwd=run_cwd.unwrap_or("."),
        inherit_env=true,
        stdin=@process.redirect_from_file(empty_stdin),
        stdout=@process.redirect_to_file(build_log, append=true),
        stderr=@process.redirect_to_file(build_log, append=true),
        no_console_window=true,
      )
    })
    guard build_exit is Some(build_exit) else {
      let text = rewrite_temp_paths(read_capped(build_log), [real, dir])
      return @agent_tool.ToolAction::respond(
        "mbtx: the build did not finish within \{run_timeout_ms / 1000}s, so no background job was started.\n\{text}",
        is_error=true,
        brief="mbtx (build timeout)",
      )
    }
    if build_exit != 0 {
      let text = rewrite_temp_paths(read_capped(build_log), [real, dir])
      return @agent_tool.ToolAction::respond(
        "[mbtx: the program did not compile, so no background job was started]\n\{text}",
        is_error=true,
        brief="mbtx (build failed)",
      )
    }
    let id = runtime.start(
      program=prog,
      args=argv,
      command="mbtx: \{@agent_tool.brief_line(input.source, limit=64)}",
      cwd?=run_cwd,
      sandboxed_command?,
      // Same EOF-on-stdin contract as a foreground run: a detached snippet
      // must not inherit the engine's fd 0, which under `serve` carries the
      // JSONL commands.
      stdin=@process.redirect_from_file(empty_stdin),
    )
    job_owns_dir.val = true
    return @agent_tool.ToolAction::respond(
      "started background job \{id} (the program compiled). Read its output with job_output (job_id=\"\{id}\") and stop it with job_stop (job_id=\"\{id}\").",
      brief="mbtx → bg \{id}",
    )
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
    let finished = @async.with_timeout_opt(run_timeout_ms, () => exec.wait())
    let saw_binary = exec.had_invalid_utf8()
    if finished is None {
      let _ = exec.background()
      let id = runtime.adopt(
        exec,
        command="mbtx: \{@agent_tool.brief_line(input.source, limit=64)}",
        cwd?=run_cwd,
        sandboxed_command?,
      )
      job_owns_dir.val = true
      return @agent_tool.ToolAction::respond(
        "mbtx: still running after \{run_timeout_ms / 1000}s, so it moved to the background as job \{id} (nothing was lost). Read its output with job_output (job_id=\"\{id}\") and stop it with job_stop (job_id=\"\{id}\").",
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
      escalated~,
    )
    exec.discard()
    let text = rewrite_temp_paths(raw, [real, dir])
    let body = if text.is_blank() {
      "mbtx: program exited \{exit_code} with no output"
    } else if exit_code != 0 {
      "[mbtx: exited \{exit_code}]\n\{text}"
    } else {
      text
    }
    let body = if output_limit_reached {
      "\{body}\n[mbtx: output passed \{OutputCapBytes} bytes, so the program was STOPPED and this is only what it printed first. Redirect bulky output with `stdout=ToFile(path)` and read the file instead.]"
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
    return @agent_tool.ToolAction::respond(
      body,
      is_error=exit_code != 0 ||
        sandbox_denied is Some(_) ||
        output_limit_reached,
      brief="mbtx (exit=\{exit_code})",
    )
  }
  let result = @async.with_timeout_opt(run_timeout_ms, () => {
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
    escalated~,
  )
  let action = match result {
    Some((exit_code, raw)) => {
      // Rewrite the throwaway temp path to `source` so the model reads
      // `source:LINE:COL` about its own input, not a random temp path.
      let text = rewrite_temp_paths(raw, [real, dir])
      // PREPEND the exit status so it survives the agent loop's outer 60k
      // result clamp (which cuts the tail); the output cap is below 60k so
      // both the status line and the body are retained.
      let body = if text.is_blank() {
        "mbtx: program exited \{exit_code} with no output"
      } else if exit_code != 0 {
        "[mbtx: exited \{exit_code}]\n\{text}"
      } else {
        text
      }
      let body = if sandbox_denied is Some(guidance) {
        "\{body}\n\n\{guidance}"
      } else {
        body
      }
      @agent_tool.ToolAction::respond(
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
      let partial = rewrite_temp_paths(read_capped(log), [real, dir])
      let head = "mbtx: timed out after \{run_timeout_ms / 1000}s and was cancelled — the program did not finish (an infinite loop, or a build that never completed)."
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
      @agent_tool.ToolAction::respond(
        body,
        is_error=true,
        brief="mbtx (timeout)",
      )
    }
  }
  action
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
  escalated~ : Bool,
) -> String? {
  async fn shows(reports : (String) -> Bool) -> Bool {
    match log_path {
      Some(path) => log_shows_denial(path, reports)
      None => reports(head)
    }
  }

  // An escalated run was given no policy, so nothing it prints can be this
  // tool's policy refusing something. The spawn marker is only the guest's own
  // `EPERM` text, which an unsandboxed child can produce for its own reasons —
  // scanning for it here would report a successful run as an error and tell
  // the model to ask for the escalation it was already granted.
  if !escalated && shows(@sandbox.output_reports_policy_refusal) {
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
fn rewrite_temp_paths(text : String, bases : Array[String]) -> String {
  let mut out = text
  for base in bases {
    for sep in ["/", "\\"] {
      // `.mbtx` first: replacing `snippet.mbt` before it would leave a stray
      // `x` (`sourcex`). `snippet.mbt` is the generated file at the top of the
      // target-dir; `_build/snippet.mbt` covers the older build layout.
      out = out
        .replace_all(old="\{base}\{sep}snippet.mbtx", new="source")
        .replace_all(old="\{base}\{sep}_build\{sep}snippet.mbt", new="source")
        .replace_all(old="\{base}\{sep}snippet.mbt", new="source")
    }
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
/// than twice `DenialScanBudgetBytes` is scanned at its head and tail only. An
/// uncaught denial crashes the snippet, so its OSError line is the log's tail;
/// a caught-and-printed denial lands where it happened, inside the head for
/// realistic probes. Only a denial buried in the MIDDLE of a >32MB flood is
/// missed — the price of a bounded scan. `budget_bytes` is parameterized for
/// tests only.
async fn log_shows_denial(
  path : String,
  reports_denial : (String) -> Bool,
  budget_bytes? : Int = DenialScanBudgetBytes,
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
/// The `mbtx` argument schema. `background` adds `run_in_background`,
/// which a definition without a job runtime must not advertise — the model
/// would only get an error from a call it cannot execute. `escalation` adds
/// `escalated` on the same rule: with no approval channel wired, every use of
/// it would come back refused, and the cheapest way to not waste a turn on
/// that is for the argument not to exist.
fn schema(background~ : Bool, escalation~ : Bool) -> Json {
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
          ..if background {
            [
              (
                "run_in_background",
                Json({
                  "type": "boolean",
                  "description": (
                    #|Run as a background job: returns a job id immediately and a completion
                    #|notice arrives when it exits. Use for long-running work (full test
                    #|suites, long builds, watchers) instead of blocking on the 300s
                    #|foreground bound, which moves the run to a job when it expires.
                  ),
                }),
              ),
            ]
          },
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
/// `background` is conditional because without a job runtime the tool must not
/// advertise `run_in_background`: the model would only get an error.
/// `escalation` is conditional for the same reason, and matters more: the
/// refused-command paragraph above tells the model to say so rather than work
/// around a refusal, and where escalation IS available that advice would be
/// wrong — there is a sanctioned way to ask. The paragraph that says so must
/// appear exactly where the way exists.
fn description(background~ : Bool, escalation~ : Bool) -> String {
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
    #|  install, tree, clean, new, ide, doc, explain, coverage, cram, package,
    #|  version, plus `publish --dry-run`. (Not plain `publish`, `login` or `register`.)
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
    #|- Bounded to 300s. For independent commands or probes, emit SEVERAL
    #|  `mbtx` calls in the SAME assistant turn — they run and come back
    #|  together, saving a model round-trip each.
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
  if !background {
    return base
  }
  // The blank `$|` line is the paragraph break: without it the section heading
  // runs onto the base text's last line and stops reading as a heading.
  (
    $|\{base}
    $|
    $|## Long-running work
    $|
    $|For full test suites, long builds and watchers, set run_in_background=true: the
    $|call returns a job id immediately and a notice arrives automatically when the job
    $|finishes — so never block on time (no sleep loops, no polling); keep working and
    $|act on the completion notice. Read a job's recent output with job_output and
    $|cancel it with job_stop. A foreground run is bounded to 300s; at that deadline it
    $|MOVES to a background job rather than dying, so nothing is lost either way —
    $|asking for a job up front just skips the wait.
  )
}
