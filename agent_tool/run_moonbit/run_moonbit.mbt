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
/// agent's memory before the timeout fires. Only this many bytes are read back
/// — the rest is dropped with a truncation marker.
const OutputCapBytes : Int = 48_000

///|
/// The `--warn-list` spec for `warning: "off"`. `-a` disables all warnings;
/// each `+name@name` pair then re-enables a selected correctness diagnostic
/// and promotes it back to an error. Keep this mnemonic list maintained by
/// hand; `unused_mut` intentionally remains suppressed for throwaway snippets.
const WarnOffList : String = "-a+partial_match@partial_match+multiline_string_escape@multiline_string_escape+invalid_inline_wasm@invalid_inline_wasm+unannotated_ffi@unannotated_ffi"

///|
/// Best-effort refusal of native FFI (`extern`, which can bind libc `system`
/// and sidesteps every guard above it). Spawning processes is no longer an
/// escape — it is what this tool is for — but FFI still is. A substring scan is
/// NOT a real boundary; HARD containment is deferred to the planned wasm
/// backend (safe by construction). Returns the reason to report, or None.
fn native_escape(source : String) -> String? {
  // Match the FFI syntax (`extern "c" fn …`), not the bare word. Scanning for
  // `extern` alone refused a snippet whose only offence was a commit message
  // mentioning it — the word appears in prose and string literals, the quote
  // that follows it does not.
  if source.contains("extern \"") {
    Some("uses native FFI (extern), which the wasm sandbox will contain later")
  } else {
    None
  }
}

///|
/// Tool definition for `run_moonbit`: compile and run a self-contained MoonBit
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
/// dependency-API probes against the workspace, not run_moonbit.
///
/// Compiler warnings are suppressed by default: snippets are throwaway
/// scripts, so unused-value style noise would only pollute the output.
/// Passing `warning: "on"` restores them, for when the warnings themselves
/// are the thing being probed. Selected correctness diagnostics such as
/// `partial_match` keep failing compilation with warnings off (see
/// `WarnOffList`).
///
/// Confinement comes from two layers that cover different things, because
/// neither covers both:
///
/// * moonrun's wasm policy (cross-platform) decides WHICH programs may start —
///   an allowlist holding the moon/git/gh toolchain and inert utilities, with
///   no shell, interpreter, or ad-hoc rewriter in it — and bounds the file
///   access of the snippet itself.
/// * `sandbox-exec` (macOS only) bounds what the process TREE may write: the
///   workspace, this run's build directory, the toolchain's caches, nothing
///   else. This is the only layer that reaches spawned children — the policy's
///   `fs` rules stop at the process boundary — so off macOS a spawned command
///   is bounded by the allowlist alone.
///
/// Note what is deliberately NOT denied: source writes as such. The commands
/// whose job is to rewrite source (`moon fmt`, `moon info`, `git checkout`) run
/// normally, and the reason the old rule existed — an arbitrary program editing
/// files behind the model's back — is covered by the allowlist admitting no
/// such program.
pub fn definition(
  workspace_root~ : String,
  bg_runtime? : @bgjobs.BgJobRuntime,
  job_dir? : String,
  scratch_dir? : String,
  worker_sandbox? : WorkerSandbox,
  run_timeout_ms? : Int = RunTimeoutMs,
) -> @agent_tool.AgentToolDefinition {
  // Background snippet directories are numbered inside the caller's scratch
  // dir rather than created as fresh system temp dirs: a detached job outlives
  // this call, so its snippet, build artifacts, and output log cannot be
  // removed here — the caller's scratch dir is what eventually reclaims them.
  let next_background = Ref(0)
  AgentToolDefinition(
    name="run_moonbit",
    description=description(background=bg_runtime is Some(_)),
    schema=JsonSchema(schema(background=bg_runtime is Some(_))),
    execute=Async(arguments => {
      execute(
        workspace_root,
        arguments,
        bg_runtime?,
        job_dir?,
        scratch_dir?,
        worker_sandbox?,
        run_timeout_ms~,
        next_background~,
      )
    }),
  )
}

///|
async fn execute(
  workspace_root : String,
  arguments : Json,
  bg_runtime? : @bgjobs.BgJobRuntime,
  job_dir? : String,
  scratch_dir? : String,
  worker_sandbox? : WorkerSandbox,
  // The wall-clock bound, injectable so a test can exercise the deadline
  // without waiting out the real one.
  run_timeout_ms~ : Int,
  next_background~ : Ref[Int],
) -> @agent_tool.ToolAction {
  let input = @decode.decode(arguments) catch {
    error =>
      return @agent_tool.ToolAction::respond(
        "error: run_moonbit requires \{@tool_error.failure_message("\{error}")}",
        is_error=true,
      )
  }
  if native_escape(input.source) is Some(reason) {
    return @agent_tool.ToolAction::respond(
      "run_moonbit refuses this program: it \{reason}. run_moonbit is the compute/IO surface; deeper containment arrives with the wasm backend.",
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
        "error: run_moonbit cwd does not exist: \{c}",
        is_error=true,
      )
    }
    guard @fs.kind(c) is Directory else {
      return @agent_tool.ToolAction::respond(
        "error: run_moonbit cwd is not a directory: \{c}",
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
          "run_moonbit: could not create a working directory for the background job.",
          is_error=true,
        )
    }
    dir
  } else if scratch_dir is Some(lab) {
    // With a lab wired, the snippet builds INSIDE it: the profile re-allows
    // exactly one subtree, and pointing it at the lab then covers both the
    // lab writes the caller sanctioned and moon's own build output.
    let dir = "\{lab}/run-moonbit-\{next_background.val}"
    next_background.val += 1
    @fs.mkdir(dir, recursive=true) catch {
      error if @async.is_being_cancelled() => raise error
      _ =>
        return @agent_tool.ToolAction::respond(
          "run_moonbit: could not create a working directory in the scratch lab.",
          is_error=true,
        )
    }
    dir
  } else {
    @fs.tmpdir(prefix="openseek-run-moonbit-") catch {
      // Let a cancellation propagate to the loop's Interrupted terminal instead of
      // swallowing it into an ordinary tool error.
      error if @async.is_being_cancelled() => raise error
      _ =>
        return @agent_tool.ToolAction::respond(
          "run_moonbit: could not create a temporary working directory.",
          is_error=true,
        )
    }
  }
  // Set once a background job takes over the directory (snippet, artifacts,
  // output log): either an explicit `run_in_background`, or a foreground run
  // detached at its deadline. `cleanup` runs on every exit path, so the flag —
  // not the request — decides whether reclaiming the directory is still ours.
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
  let policy = wasm_policy_document(
    workspace_root~,
    dir~,
    tmp_dir=snippet_tmp,
    extra_roots=[
      ..run_cwd.map(c => [c]).unwrap_or([]),
      ..scratch_dir.map(l => [l]).unwrap_or([]),
    ],
  )
  @fs.write_file(policy_path, policy.stringify(), create_mode=CreateOrTruncate)
  let moon_argv = [
    "run",
    "\{dir}/snippet.mbtx",
    "--target",
    input.target,
    "--target-dir",
    dir,
    ..if input.target == "wasm" {
      ["--wasm-policy", policy_path]
    },
    ..if !input.warning {
      ["--warn-list", WarnOffList]
    },
  ]
  // Wrap `moon run` in sandbox-exec where it can actually enforce (macOS).
  // This is the layer the wasm policy cannot supply: the policy's `fs` rules
  // bind the snippet but stop at the process boundary, so without this a
  // spawned `git` or `moon` writes wherever it likes. Which profile depends on
  // the role below. Elsewhere (or in a nested sandbox where it cannot enforce)
  // run moon directly and let the policy's allowlist be the only bound.
  // The prepared command carries what it needs to classify its own denials, so
  // one showing up in the program's output can be recognized and explained
  // with the guidance for the rule that actually refused it. The
  // throwaway build dir is the writable subtree: if it falls INSIDE the
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
    // A lab means a read-only subrun (explore/review/audit): those hold no
    // editing tool, so "may not write source" is the guarantee that defines
    // them and it stays kernel-enforced. The profile suits them for a second
    // reason — it is `(allow default)` minus source, so `moon check` can still
    // write its target dir inside the workspace, which a boundary profile
    // denying the workspace would take away.
    None if scratch_dir is Some(_) =>
      @sandbox.SandboxedCommand::create_if_available(
        workspace_root,
        Exec("moon", moon_argv),
        writable_subtree~,
      )
    None =>
      // The main agent draws the line at the workspace instead. Forbidding
      // source writes here would break the very commands it needs — `moon fmt`,
      // `moon info`, `git checkout` all rewrite source by definition — and the
      // reason that rule existed is already covered: a snippet's programs come
      // from an allowlist with no shell, no interpreter, and no ad-hoc
      // rewriter in it. What is left worth denying is everything OUTSIDE.
      @sandbox.SandboxedCommand::create_workspace_boundary_if_available(
        workspace_root,
        Exec("moon", moon_argv),
        writable_roots=[writable_subtree, ..child_process_write_roots()],
      )
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
        "run_moonbit: the build did not finish within \{run_timeout_ms / 1000}s, so no background job was started.\n\{text}",
        is_error=true,
        brief="run_moonbit (build timeout)",
      )
    }
    if build_exit != 0 {
      let text = rewrite_temp_paths(read_capped(build_log), [real, dir])
      return @agent_tool.ToolAction::respond(
        "[run_moonbit: the program did not compile, so no background job was started]\n\{text}",
        is_error=true,
        brief="run_moonbit (build failed)",
      )
    }
    let id = runtime.start(
      program=prog,
      args=argv,
      command="run_moonbit: \{@agent_tool.brief_line(input.source, limit=64)}",
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
      brief="run_moonbit → bg \{id}",
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
    let finished = @async.with_timeout_opt(run_timeout_ms, () => {
      exec.wait_or_invalid()
    })
    // Binary output ends the await early with the child STILL RUNNING, so
    // reporting now would leave the process going while `defer cleanup()`
    // removes its build directory underneath it — and the exit code below
    // would be invented. Wait out the real exit first.
    let saw_binary = exec.had_invalid_utf8()
    if saw_binary {
      exec.wait()
    }
    if finished is None && !saw_binary {
      let _ = exec.background()
      let id = runtime.adopt(
        exec,
        command="run_moonbit: \{@agent_tool.brief_line(input.source, limit=64)}",
        cwd?=run_cwd,
        sandboxed_command?,
      )
      job_owns_dir.val = true
      return @agent_tool.ToolAction::respond(
        "run_moonbit: still running after \{run_timeout_ms / 1000}s, so it moved to the background as job \{id} (nothing was lost). Read its output with job_output (job_id=\"\{id}\") and stop it with job_stop (job_id=\"\{id}\").",
        brief="run_moonbit → bg \{id}",
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
    // `Some(guidance)` when denied: the flag and the explanation come from the
    // same command, so the text always matches the rule that refused.
    let sandbox_denied = if sandboxed_command is Some(command) &&
      (if denial_scan_source is Some(path) {
        log_shows_source_write_denial(path, output => {
          command.output_reports_denial(output)
        })
      } else {
        command.output_reports_denial(raw)
      }) {
      Some(command.denial_feedback())
    } else {
      None
    }
    exec.discard()
    let text = rewrite_temp_paths(raw, [real, dir])
    let body = if text.is_blank() {
      "run_moonbit: program exited \{exit_code} with no output"
    } else if exit_code != 0 {
      "[run_moonbit: exited \{exit_code}]\n\{text}"
    } else {
      text
    }
    let body = if output_limit_reached {
      "\{body}\n[run_moonbit: output passed \{OutputCapBytes} bytes, so the program was STOPPED and this is only what it printed first. Redirect bulky output with `stdout=ToFile(path)` and read the file instead.]"
    } else {
      body
    }
    let body = if saw_binary {
      "\{body}\n[run_moonbit: the program emitted non-UTF-8 bytes; the text above is a lossy rendering.]"
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
      brief="run_moonbit (exit=\{exit_code})",
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
  // A "not permitted" line naming a protected source path in a sandboxed run
  // is the source-write policy firing, not an environment fault: explain it
  // (the raw OS error is otherwise a dead end) and treat the run as failed
  // even if the snippet swallowed the error and exited 0 — a swallowed denial
  // still means the write it needed did not happen. Detection scans
  // the on-disk log far past the capped display prefix (bounded to a fixed
  // head+tail byte budget), and runs for the timeout arm too: a snippet can
  // flood past the cap before hitting the denial, or print a caught denial
  // and then hang.
  let sandbox_denied = if sandboxed_command is Some(command) &&
    log_shows_source_write_denial(log, output => {
      command.output_reports_denial(output)
    }) {
    Some(command.denial_feedback())
  } else {
    None
  }
  let action = match result {
    Some((exit_code, raw)) => {
      // Rewrite the throwaway temp path to `source` so the model reads
      // `source:LINE:COL` about its own input, not a random temp path.
      let text = rewrite_temp_paths(raw, [real, dir])
      // PREPEND the exit status so it survives the agent loop's outer 60k
      // result clamp (which cuts the tail); the output cap is below 60k so
      // both the status line and the body are retained.
      let body = if text.is_blank() {
        "run_moonbit: program exited \{exit_code} with no output"
      } else if exit_code != 0 {
        "[run_moonbit: exited \{exit_code}]\n\{text}"
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
        brief="run_moonbit (exit=\{exit_code})",
      )
    }
    None => {
      // The snippet may have printed useful output before it hung; the log is
      // still on disk (cleanup runs below), so surface the captured prefix
      // instead of discarding it behind a generic timeout message. The status
      // line stays first so it survives the outer result clamp.
      let partial = rewrite_temp_paths(read_capped(log), [real, dir])
      let head = "run_moonbit: timed out after \{run_timeout_ms / 1000}s and was cancelled — the program did not finish (an infinite loop, or a build that never completed)."
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
        brief="run_moonbit (timeout)",
      )
    }
  }
  action
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
/// Whether the on-disk output log shows a source-write denial. Detection must
/// not be bounded by the 48KB display cap (a snippet can flood past it before
/// the denied write), but it must stay bounded in bytes and time: a log larger
/// than twice `DenialScanBudgetBytes` is scanned at its head and tail only. An
/// uncaught denial crashes the snippet, so its OSError line is the log's tail;
/// a caught-and-printed denial lands where it happened, inside the head for
/// realistic probes. Only a denial buried in the MIDDLE of a >32MB flood is
/// missed — the price of a bounded scan. `budget_bytes` is parameterized for
/// tests only.
async fn log_shows_source_write_denial(
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
    "\{text}\n[run_moonbit: output truncated at \{OutputCapBytes} bytes]"
  } else {
    text
  }
}

///|
/// The `run_moonbit` argument schema. `background` adds `run_in_background`,
/// which a definition without a job runtime must not advertise — the model
/// would only get an error from a call it cannot execute.
fn schema(background~ : Bool) -> Json {
  let properties : Map[String, Json] = {
    "source": { "type": "string" },
    "target": {
      "type": "string",
      "enum": ["native", "wasm", "wasm-gc", "js", "llvm"],
      "description": "Backend to run on; defaults to wasm, which is the sandboxed one. The alternatives run pure computation only — they cannot spawn commands or touch files.",
    },
    "cwd": {
      "type": "string",
      "description": "Working directory the program runs in (relative paths resolve against the workspace root); defaults to the workspace root.",
    },
    "warning": {
      "type": "string",
      "enum": ["off", "on"],
      "description": (
        #|Whether compiler warnings appear in the output; defaults to off (a snippet
        #|is a throwaway script, so unused-variable style noise is suppressed). Set
        #|"on" only when the warnings themselves are what you are probing.
      ),
    },
  }
  if background {
    properties["run_in_background"] = {
      "type": "boolean",
      "description": (
        #|Run as a background job: returns a job id immediately and a completion
        #|notice arrives when it exits. Use for long-running work (full test
        #|suites, long builds, watchers) instead of blocking on the 300s
        #|foreground bound, which moves the run to a job when it expires.
      ),
    }
  }
  {
    "type": "object",
    "properties": Json::object(properties),
    "required": ["source"],
  }
}

///|
/// The `run_moonbit` tool description. `background` adds the background-jobs
/// paragraph, which a definition without a job runtime must not advertise —
/// the model would only get an error from a call it cannot execute.
fn description(background~ : Bool) -> String {
  let base =
    #|Compile and run a self-contained MoonBit program (a `.mbtx` single-file script)
    #|and return its merged stdout/stderr and exit status. This is BOTH your command
    #|runner and your scripting surface: there is no shell tool, so commands are spawned
    #|from MoonBit with the `bobzhang/myshell` EDSL. Command pattern:
    #|  import { "bobzhang/myshell", "moonbitlang/async" }
    #|  async fn main {
    #|    let out = @myshell.Cmd("moon", ["check", "--diagnostic-limit", "5"]).output()
    #|    println(out.stdout)
    #|    println(out.stderr)
    #|    println("exit=\{out.exit_code}")
    #|  }
    #|`Cmd(program, args)` takes the argument VECTOR literally — no shell parsing, no
    #|quoting, and `|`, `>`, `&&`, `$()`, `*` have no meaning. Optional labels:
    #|`cwd="dir"`, `env={..}`, `stdin=Text("...")` (also `Binary(bytes)`/`FromFile(path)`),
    #|`stdout=ToFile(path)`. Run several commands as ordinary sequential MoonBit
    #|statements and branch on `out.exit_code` / `out.success()`. Do NOT use
    #|`@myshell.Pipeline` — capture `out.stdout` and filter/transform it in MoonBit, which
    #|is what replaces grep/sed/awk. ALWAYS println each command's exit code, stdout, and
    #|stderr, or its result is invisible to you. For output larger than a few hundred KB
    #|redirect with `stdout=ToFile(...)` and read the file back. `source` may begin with an
    #|inline `import { "pkg", ... }` block (comma-separated module paths) followed by the
    #|program including its own `main`; use `async fn main` for commands and IO. It runs
    #|with your workspace as the working directory by default, so RELATIVE paths reach
    #|workspace files; pass `cwd` to run elsewhere. The SNIPPET's own build artifacts stay
    #|in a temp dir (your `_build` is untouched), and a snippet's imports resolve against
    #|the registry (NOT your uncommitted edits) — to exercise working-tree code, add a
    #|`*_test.mbt` to that package and run `moon test` through a `@myshell.Cmd`. Compiler
    #|warnings for the snippet are suppressed by default; pass `warning: "on"` when the
    #|warnings are what you want to see. Bounded to 300s. For independent commands or
    #|probes, emit SEVERAL run_moonbit calls in the SAME assistant turn — they run and
    #|come back together, saving a model round-trip each.
  if !background {
    return base
  }
  // The blank `$|` line is the paragraph break: without it the two texts run
  // together into one wall of text.
  (
    $|\{base}
    $|
    $|For long-running work (full test suites, long builds, watchers) set
    $|run_in_background=true: the call returns a job id immediately and a notice arrives
    $|automatically when the job finishes — so never block on time (no sleep loops, no
    $|polling); keep working and act on the completion notice. Read a job's recent output
    $|with job_output and cancel it with job_stop. A foreground run is bounded to 300s;
    $|at that deadline it MOVES to a background job rather than dying, so nothing is
    $|lost either way — asking for a job up front just skips the wait.
  )
}
