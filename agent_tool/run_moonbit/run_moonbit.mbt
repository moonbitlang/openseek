///|
/// A snippet is bounded to this wall-clock so a runaway loop or a build that
/// never finishes cannot block the whole turn. On expiry the run is cancelled
/// (which tears down the moon subprocess) and reported as a timeout.
const RunTimeoutMs : Int = 60_000

///|
/// Output is streamed to a file on disk, not buffered in memory, so a snippet
/// that floods stdout (e.g. `while true { println(…) }`) cannot exhaust the
/// agent's memory before the timeout fires. Only this many bytes are read back
/// — the rest is dropped with a truncation marker.
const OutputCapBytes : Int = 48_000

///|
/// Guidance appended when a sandboxed run's output shows a source-write denial
/// ("Operation not permitted" on a protected source path). Without it the model
/// reads a bare OS error and debugs the filesystem — or worse, tries to escape
/// the sandbox — instead of using `edit`.
const SandboxSourceWriteFeedback : String =
  #|run_moonbit sandbox: the "Operation not permitted" failure above is this tool's
  #|sandbox denying a write to a protected MoonBit source file (`*.mbt`, `*.mbti`,
  #|`*.mbt.md`, `moon.mod`/`moon.pkg`/`moon.work`) — not a filesystem or permissions
  #|problem to debug. Snippets run source-write-readonly by design; writing non-source
  #|files (data, logs, reports) stays allowed. Do NOT try to work around the block from
  #|inside a snippet (renames, copies, temp-then-move, or other sandbox escapes) — make
  #|source changes with the line-anchored `edit` tool instead, and keep run_moonbit for
  #|compute, probing, and non-source IO.

///|
/// The `--warn-list` spec for `warning: "off"`. `-a` disables all warnings;
/// each `+name@name` pair then re-enables a selected correctness diagnostic
/// and promotes it back to an error. Keep this mnemonic list maintained by
/// hand; `unused_mut` intentionally remains suppressed for throwaway snippets.
const WarnOffList : String = "-a+partial_match@partial_match+multiline_string_escape@multiline_string_escape+invalid_inline_wasm@invalid_inline_wasm+unannotated_ffi@unannotated_ffi"

///|
/// Best-effort refusal of the two obvious native escapes: process spawning
/// (`moonbitlang/async/process` — the `shell` tool owns commands) and native
/// FFI (`extern`, which can bind libc `system`). A substring scan is NOT a
/// real boundary — a determined native snippet can still escape — so HARD
/// containment is deferred to the planned wasm backend (safe by construction).
/// Until then this closes the trivial escapes and keeps descendant processes
/// from outliving the timeout. Returns the reason to report, or None.
fn native_escape(source : String) -> String? {
  if source.contains("moonbitlang/async/process") {
    Some(
      "spawns processes (moonbitlang/async/process) — use the shell tool for commands",
    )
  } else if source.contains("extern") {
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
/// Note: on macOS the run is wrapped in `sandbox-exec` with the shell tool's
/// source-write-readonly profile, so a snippet is blocked from directly writing
/// protected source files (`*.mbt`, `*.mbti`, `*.mbt.md`, `moon.mod/pkg/work`)
/// while non-source output stays permitted. This is best-effort, not a hard
/// boundary — an arbitrary snippet can still smuggle sources via directory
/// renames (which `shell` catches by preflighting its command text, impossible
/// for arbitrary code). Full capability containment is deferred to the planned
/// wasm backend, where the runtime is safe by construction.
pub fn definition(workspace_root~ : String) -> @agent_tool.AgentToolDefinition {
  AgentToolDefinition(
    name="run_moonbit",
    description=(
      #|Compile and run a self-contained MoonBit program (a `.mbtx` single-file script)
      #|and return its merged stdout/stderr and exit status. Use this for scripting
      #|automation (read/transform files, parse JSON, compute) and for probing MoonBit
      #|language behavior — PREFER it over shell python/node so the automation is MoonBit.
      #|`source` may begin with an inline `import { "pkg", ... }` block (comma-separated
      #|module paths such as `"moonbitlang/async", "moonbitlang/async/fs",
      #|"moonbitlang/core/json"`) followed by the program including its own `main`; use
      #|`async fn main` for IO (add `"moonbitlang/async"` to the import block for it). It
      #|runs with your workspace as the working directory by default, so RELATIVE paths
      #|like `@fs.read_file("data.json")` reach workspace files and files the program
      #|writes land in the workspace; pass `cwd` to run elsewhere. Build artifacts stay in
      #|a temp dir (your `_build` is untouched), and imports resolve against the registry
      #|(NOT your uncommitted edits) — to exercise working-tree code, add a `*_test.mbt`
      #|to that package and run `moon test` via shell instead. Compiler warnings are
      #|suppressed by default (throwaway scripts trip unused-value noise constantly); pass
      #|`warning: "on"` when the warnings are what you want to see. Bounded to 60s. When
      #|probing language or API behavior, don't probe serially one turn at a time: emit
      #|SEVERAL independent run_moonbit calls in the SAME assistant turn — one small
      #|program per hypothesis — and read all the results together; batching saves a full
      #|model round-trip per hypothesis and keeps each probe minimal instead of one
      #|growing mega-program.
    ),
    schema=JsonSchema({
      "type": "object",
      "properties": {
        "source": { "type": "string" },
        "target": {
          "type": "string",
          "enum": ["native", "wasm", "wasm-gc", "js", "llvm"],
          "description": "Backend to run on; defaults to native (required for the async @fs/@stdio/@process IO batteries).",
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
      },
      "required": ["source"],
    }),
    execute=Async(arguments => execute(workspace_root, arguments)),
  )
}

///|
async fn execute(
  workspace_root : String,
  arguments : Json,
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
  // against the workspace, like the shell tool.
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
  let dir = @fs.tmpdir(prefix="openseek-run-moonbit-") catch {
    // Let a cancellation propagate to the loop's Interrupted terminal instead of
    // swallowing it into an ordinary tool error.
    error if @async.is_being_cancelled() => raise error
    _ =>
      return @agent_tool.ToolAction::respond(
        "run_moonbit: could not create a temporary working directory.",
        is_error=true,
      )
  }
  async fn cleanup() -> Unit {
    // rmdir is async, so it cannot run in a `defer`; shield it from cancellation
    // so an interrupted run still removes its temp dir.
    @async.protect_from_cancel(() => {
      @fs.rmdir(dir, recursive=true) catch {
        _ => ()
      }
    })
  }

  try {
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
    let moon_argv = [
      "run",
      "\{dir}/snippet.mbtx",
      "--target",
      input.target,
      "--target-dir",
      dir,
      ..if !input.warning {
        ["--warn-list", WarnOffList]
      },
    ]
    // Wrap `moon run` in sandbox-exec where it can actually enforce (macOS) so a
    // snippet cannot directly overwrite protected source files — reusing the
    // shell tool's source-write-readonly profile keyed on the workspace root.
    // This is best-effort, not a hard boundary: unlike `shell` (which statically
    // preflights the command) an arbitrary snippet can still smuggle sources via
    // directory renames; full containment is the wasm backend's job. Elsewhere
    // (or in a nested sandbox where it cannot enforce) run moon directly.
    // The prepared command carries its denial subjects, so a denial showing up
    // in the program's output can be recognized and explained below. The
    // throwaway build dir is the writable subtree: if it falls INSIDE the
    // workspace root (e.g. `workspace_root=/tmp`, where `@fs.tmpdir` lands
    // under it) the shared deny would otherwise block moon's own generated
    // `snippet.mbt`.
    let sandboxed_command = @sandbox.SandboxedCommand::create_if_available(
      workspace_root,
      Exec("moon", moon_argv),
      writable_subtree=dir,
    )
    let (prog, argv) = match sandboxed_command {
      Some(command) => (command.program(), command.args())
      None => ("moon", moon_argv)
    }
    let result = @async.with_timeout_opt(RunTimeoutMs, () => {
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
    // even if the snippet swallowed the error and exited 0 — the same
    // semantics the shell tool applies to its command output. Detection scans
    // the on-disk log far past the capped display prefix (bounded to a fixed
    // head+tail byte budget), and runs for the timeout arm too: a snippet can
    // flood past the cap before hitting the denial, or print a caught denial
    // and then hang.
    let sandbox_denied = sandboxed_command is Some(command) &&
      log_shows_source_write_denial(log, output => {
        command.output_reports_denial(output)
      })
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
        let body = if sandbox_denied {
          "\{body}\n\n\{SandboxSourceWriteFeedback}"
        } else {
          body
        }
        @agent_tool.ToolAction::respond(
          body,
          is_error=exit_code != 0 || sandbox_denied,
          brief="run_moonbit (exit=\{exit_code})",
        )
      }
      None => {
        // The snippet may have printed useful output before it hung; the log is
        // still on disk (cleanup runs below), so surface the captured prefix
        // instead of discarding it behind a generic timeout message. The status
        // line stays first so it survives the outer result clamp.
        let partial = rewrite_temp_paths(read_capped(log), [real, dir])
        let head = "run_moonbit: timed out after \{RunTimeoutMs / 1000}s and was cancelled — the program did not finish (an infinite loop, or a build that never completed)."
        let body = if partial.is_blank() {
          head
        } else {
          "\{head}\n[partial output before the timeout]\n\{partial}"
        }
        let body = if sandbox_denied {
          "\{body}\n\n\{SandboxSourceWriteFeedback}"
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
    cleanup()
    action
  } catch {
    error => {
      cleanup()
      raise error
    }
  }
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
