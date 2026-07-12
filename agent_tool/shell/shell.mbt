///|
/// Default foreground wait when the model omits `timeout_ms`. With a
/// background runtime wired the deadline DETACHES the command into a job
/// (nothing is lost, the turn stays alive — issue #419: two real multi-hour
/// silent stalls came from unbounded foreground waits), so the default can
/// be tight. Without one the deadline kills, so it is generous.
pub const DefaultForegroundTimeoutMs : Int = 120_000

///|
/// Default foreground wait when no background runtime is wired (Windows and
/// standalone registries): the deadline kills rather than detaches, so it is
/// generous. Longer legitimate work must pass an explicit `timeout_ms`.
pub const DefaultUnwiredForegroundTimeoutMs : Int = 600_000

///|
/// Ceiling for explicit `timeout_ms`. Longer work belongs in
/// `run_in_background`, so an explicit value above this is an error rather
/// than a silent clamp — a wait request is a semantic contract.
pub const HardMaxForegroundTimeoutMs : Int = 600_000

///|
/// Tool definition for `shell`: runs `arguments.cmd` through the platform
/// shell, optionally in `arguments.cwd`, and returns the exit code plus merged
/// stdout/stderr output.
///
/// ## Arguments
/// - `cmd` (string, required): shell command line passed to the platform shell.
/// - `cwd` (string, optional): working directory the command runs in.
///   An empty string is treated the same as a missing field.
/// - `max_output_chars` (number, optional): defaults to 12000 and is capped at
///   50000. Once the retained output prefix exceeds this limit, the child
///   process is cancelled and the result is reported as a tool error.
/// - `timeout_ms` (number, optional): positive timeout in milliseconds, capped
///   at `HardMaxForegroundTimeoutMs` (explicit values above it are an error).
///   When omitted, a default applies so no foreground wait is unbounded:
///   `DefaultForegroundTimeoutMs` with a background runtime wired (the
///   deadline detaches the command into a job), else
///   `DefaultUnwiredForegroundTimeoutMs` (the deadline cancels the command,
///   reported as a tool error).
///
/// ## Result
/// Metadata is a trailing `<system>...</system>` footer (the `read` tool
/// convention): output first, one footer line last. Output-less commands return
/// just the footer.
/// - `Respond(ToolOutput("<output>\n<system>exit=<code></system>", is_error=<code != 0>))`
///   when the platform shell runs. Non-zero exit codes are typed as tool errors
///   while preserving the full output for the model.
/// - `Respond(ToolOutput("<output-prefix>\n<system>exit=<code-or-cancelled> truncated=true output_limit_reached=true shown_chars=<n> max_output_chars=<n></system>", is_error=true))`
///   when output exceeds `max_output_chars`. The command may be cancelled before
///   its natural exit code is available.
/// - `Respond(ToolOutput("error running shell: ...", is_error=true))` when
///   launching the process raises.
/// - `Respond(ToolOutput("error: shell requires ...", is_error=true))` for
///   invalid arguments.
pub fn definition(
  workspace_root? : String = ".",
  read_only? : Bool = false,
  bg_runtime? : @bgjobs.BgJobRuntime,
  default_timeout_ms? : Int,
) -> @agent_tool.AgentToolDefinition {
  AgentToolDefinition(
    name="shell",
    // Only describe and advertise `run_in_background` when a background runtime
    // is wired (the agent's registry): a standalone/custom definition without
    // one cannot execute it, so exposing it would let a model make a call that
    // only errors — and the timeout semantics genuinely differ (wired: detach to
    // a background job; unwired: cancel and report a tool error), so a single
    // static description would misstate one of the two contexts.
    description=if bg_runtime is Some(_) {
      shell_description() + background_description()
    } else {
      shell_description()
    },
    schema=JsonSchema(
      if bg_runtime is Some(_) {
        {
          "type": "object",
          "properties": {
            "cmd": { "type": "string" },
            "cwd": { "type": "string" },
            "timeout_ms": {
              "type": "number",
              "description": "Max time to wait in the foreground (default 120000, max 600000); a command still running at the deadline is moved to the background as a job (not killed).",
            },
            "max_output_chars": { "type": "number" },
            "run_in_background": {
              "type": "boolean",
              "description": "Run as a background job: returns a job id immediately and a completion notice arrives when it exits. Use for long-running commands instead of blocking or sleeping.",
            },
          },
          "required": ["cmd"],
        }
      } else {
        {
          "type": "object",
          "properties": {
            "cmd": { "type": "string" },
            "cwd": { "type": "string" },
            "timeout_ms": {
              "type": "number",
              "description": "Max time to wait (default 600000, max 600000); a command still running at the deadline is cancelled and reported as a tool error.",
            },
            "max_output_chars": { "type": "number" },
          },
          "required": ["cmd"],
        }
      },
    ),
    execute=Async(arguments => {
      execute_with_workspace(
        workspace_root,
        arguments,
        read_only~,
        bg_runtime?,
        default_timeout_ms?,
      )
    }),
  )
}

///|
/// The background-jobs paragraph appended to the shell description when a
/// background runtime is wired. Guides the model away from blocking waits:
/// long-running work goes to a background job and its completion is *pushed* as
/// a notice, so `sleep N && cmd` chains and shell_output polling loops are both
/// unnecessary and wasteful.
fn background_description() -> String {
  " For long-running work (builds, long test suites, servers, watchers) set run_in_background=true: the call returns a job id immediately and a notice arrives automatically when the job finishes — so never block the turn waiting on time (no `sleep N && cmd` chains, no repeated polling); keep working, or finish the turn, and act on the completion notice. Read a job's recent output with shell_output and cancel it with shell_stop. A foreground command that outlives timeout_ms (default 120000ms when omitted) is moved to the background as a job (not killed); pass a larger timeout_ms (up to 600000) only when you must block on the result."
}

///|
#cfg(platform="windows")
fn shell_description() -> String {
  "Run arguments.cmd through PowerShell (pwsh -NoProfile -Command), optionally in arguments.cwd, and return exit code plus output. Use PowerShell syntax and cmdlets in arguments.cmd. Source file edits for compiler feedback belong in line-anchored edit (or multi_edit for several fixes in one file); do not use shell rewrites."
}

///|
#cfg(not(platform="windows"))
fn shell_description() -> String {
  "Run arguments.cmd through the POSIX shell (sh -c), optionally in arguments.cwd, and return exit code plus output. Use POSIX shell syntax in arguments.cmd. Source file edits for compiler feedback belong in line-anchored edit (or multi_edit for several fixes in one file); do not use shell rewrites."
}

///|
async fn execute_with_workspace(
  workspace_root : String,
  arguments : Json,
  read_only~ : Bool,
  bg_runtime? : @bgjobs.BgJobRuntime,
  default_timeout_ms? : Int,
) -> @agent_tool.ToolAction {
  let input = @decode.decode(arguments) catch {
    error => {
      let message = @tool_error.failure_message("\{error}")
      return @agent_tool.ToolAction::respond(
        "error: shell requires \{message}",
        is_error=true,
      )
    }
  }
  let parsed_command = @shell_parse.parse_for_policy(input.cmd)
  // Read-only (review) mode: refuse the obvious bulk source-rewriters — a
  // source-mutating moon command (fmt / info / test --update) anywhere in the
  // parsed command, including `&&`/`;` chains, pipes, and env prefixes. This is
  // best-effort: opaque commands are allowed and `moon check`/`moon test` may
  // still pre-build, so it only stops a review from reformatting/regenerating
  // the tree wholesale, not every possible mutation.
  if read_only && review_read_only_blocks(parsed_command) {
    return @agent_tool.ToolAction::respond(
      "blocked in read-only review mode: `\{input.cmd}` runs a source-mutating moon command (fmt/info/test --update); a review reports rather than rewrites the tree. Use plain `moon check`/`moon test` (no --update), `git`, or `read`.",
      is_error=true,
    )
  }
  if @command_policy.moonbit_command_policy_error_for_parse(
      input.cmd,
      parsed_command,
    )
    is Some(message) {
    return @agent_tool.ToolAction::respond(message, is_error=true)
  }
  let cwd = @workspace_path.resolve_cwd(workspace_root, input.cwd)
  shell(
    input,
    parsed_command,
    cwd,
    workspace_root,
    bg_runtime?,
    default_timeout_ms?,
  ) catch {
    error =>
      @agent_tool.ToolAction::respond(
        "error running shell: \{error}",
        is_error=true,
      )
  }
}

///|
/// Read-only mode (used by `--review`) must refuse source-mutating moon commands
/// before they run, even though such commands are otherwise "trusted" and run
/// unsandboxed. The guard fires before execution, so no subprocess is spawned.
async test "read-only shell blocks source-mutating moon commands" {
  let blocked = execute_with_workspace(
    ".",
    { "cmd": "moon fmt" },
    read_only=true,
  )
  guard blocked is Respond(output) else { fail("expected Respond") }
  assert_true(output.is_error)
  assert_true(output.content.contains("read-only review mode"))
}

///|
async fn shell(
  input : @decode.ShellInput,
  parsed_command : @shell_parse.ParseResult,
  cwd : String?,
  workspace_root : String,
  bg_runtime? : @bgjobs.BgJobRuntime,
  default_timeout_ms? : Int,
) -> @agent_tool.ToolAction {
  // An explicit wait request above the ceiling is an error, not a silent
  // clamp — the caller asked for wait semantics this tool will not provide.
  if input.timeout_ms is Some(explicit) && explicit > HardMaxForegroundTimeoutMs {
    return @agent_tool.ToolAction::respond(
      "error: timeout_ms \{explicit} exceeds the maximum \{HardMaxForegroundTimeoutMs}ms; run longer work with run_in_background and poll it with shell_output",
      is_error=true,
    )
  }
  if cwd is Some(cwd) {
    let exists = @fs.exists(cwd)
    if !exists {
      return @agent_tool.ToolAction::respond(
        "error: cwd does not exist: \{cwd}",
        is_error=true,
      )
    }
    let kind = @fs.kind(cwd)
    if kind != Directory {
      return @agent_tool.ToolAction::respond(
        "error: cwd is not a directory: \{cwd}",
        is_error=true,
      )
    }
  }
  if direct_source_write_redirect_target(parsed_command, workspace_root, cwd)
    is Some(target) {
    return @agent_tool.ToolAction::respond(
      direct_source_blocked_content("source file write redirect", target),
      is_error=true,
      brief=shell_brief(input.cmd, None),
    )
  }
  // Background: detach the command as a job and return its id instead of blocking
  // for output. Runs the same source-tree guards and sandboxed launch as a
  // foreground command, so `run_in_background` cannot bypass any guardrail.
  if input.run_in_background {
    return start_background(
      input,
      parsed_command,
      cwd,
      workspace_root,
      bg_runtime?,
    )
  }
  // A background runtime means foreground commands run on the shared execution
  // model (session group), which is what lets a timed-out one be detached rather
  // than killed. Both the spawner and the detach hook come from it; without one
  // the shell falls back to the per-call collection path (no detach).
  //
  // No foreground wait is ever unbounded (issue #419: two real multi-hour
  // silent turn stalls came from calls without timeout_ms): an omitted
  // timeout gets a default — tight when a background runtime is wired, since
  // the deadline then DETACHES the command into a job (nothing is lost and
  // the turn stays alive); generous unwired, where the deadline kills.
  // `default_timeout_ms` is the test seam for both.
  let effective_timeout_ms = match input.timeout_ms {
    Some(explicit) => explicit
    None =>
      match default_timeout_ms {
        Some(injected) => injected
        None =>
          if bg_runtime is Some(_) {
            DefaultForegroundTimeoutMs
          } else {
            DefaultUnwiredForegroundTimeoutMs
          }
      }
  }
  // Every wired foreground command may now be detached at its deadline, so
  // spawn on the *retained* (file-backed, no output-limit kill) config: it
  // keeps a full record if detached — the foreground output-limit is still
  // enforced at display via `over_inline_cap` and the spill is discarded
  // when the command finishes in the foreground.
  let foreground_spawn : (async (String, Array[String], String?, Int) -> @shell_exec.ShellExecution)? = bg_runtime.map(runtime => {
      (program, args, cwd, max) => {
        runtime.spawn_foreground_retained(program, args, cwd, max)
      }
    },
  )
  // Detach-on-timeout: move a command that outlives its timeout to the background
  // instead of killing it — the model keeps watching it with shell_output /
  // shell_stop rather than losing it.
  let on_timeout_detach : ((@shell_exec.ShellExecution, AgentShellLaunch) -> String)? = bg_runtime.map(runtime => {
      (exec, launch) => {
        let _ = exec.background()
        runtime.adopt(
          exec,
          command=input.cmd,
          cwd?,
          source_write_sandboxed=launch.source_write_sandboxed,
          sandbox_denial_subjects=launch.sandbox_denial_subjects,
        )
      }
    },
  )
  // `run_agent_shell_with_tree_precheck` owns the timeout: with a spawner it
  // awaits a session-group execution and, on timeout, detaches it (or stops it)
  // so the process cannot leak; without one it wraps the per-call collection path.
  let result = run_agent_shell_with_tree_precheck(
    workspace_root,
    input.cmd,
    parsed_command,
    cwd?,
    max_output_chars=input.max_output_chars,
    timeout_ms=effective_timeout_ms,
    foreground_spawn?,
    on_timeout_detach?,
  )
  let agent_output = match result {
    ShellExecuted(output) => output
    ShellPreblockedSourceTree(target) =>
      return @agent_tool.ToolAction::respond(
        direct_source_blocked_content("source tree operation", target),
        is_error=true,
        brief=shell_brief(input.cmd, None),
      )
    ShellTimedOut => {
      let budget = if input.timeout_ms is Some(_) {
        ""
      } else {
        " (default foreground budget; pass timeout_ms up to \{HardMaxForegroundTimeoutMs}ms for longer waits)"
      }
      return @agent_tool.ToolAction::respond(
        "error: shell command timed out after \{effective_timeout_ms}ms\{budget}",
        is_error=true,
      )
    }
    ShellDetached(id) => {
      let budget = if input.timeout_ms is Some(_) {
        ""
      } else {
        " (default foreground budget)"
      }
      return @agent_tool.ToolAction::respond(
        "command still running after \{effective_timeout_ms}ms\{budget}; moved to the background as job \{id}. Read its output with shell_output (job_id=\"\{id}\") and stop it with shell_stop (job_id=\"\{id}\").",
        brief="\{@agent_tool.brief_line(input.cmd, limit=48)} → bg \{id}",
      )
    }
    ShellBinaryOutput =>
      return @agent_tool.ToolAction::respond(
        "error running shell: Malformed (binary / non-UTF-8) command output",
        is_error=true,
        brief=shell_brief(input.cmd, None),
      )
  }
  let output = agent_output.output
  let response = shell_response(output, input.max_output_chars)
  let sandbox_denied = agent_output_has_shell_sandbox_denial(agent_output)
  let content = append_shell_sandbox_feedback_if_needed(
    response.content,
    agent_output,
  )
  let content = append_moon_command_check_summary(
    parsed_command,
    cwd,
    content,
    output,
    input.timeout_ms,
    input.max_output_chars,
  )
  @agent_tool.ToolAction::respond(
    content,
    is_error=response.is_error || sandbox_denied,
    brief=shell_brief(input.cmd, output.exit_code),
  )
}

///|
priv enum ShellRunResult {
  ShellPreblockedSourceTree(String)
  ShellExecuted(AgentShellOutput)
  // Still running after `timeout_ms` and stopped.
  ShellTimedOut
  // Still running after `timeout_ms` and detached to the background instead of
  // stopped; carries the new job id.
  ShellDetached(String)
  // The command produced invalid (non-UTF-8 / binary) output; the per-call path
  // raises on strict decode, and the execution path reports it here.
  ShellBinaryOutput
}

///|
/// The protected target of a source-tree operation in `cmd`, or `None` when the
/// command is allowed: the direct (parse-based) detection first, then the
/// dynamic (text-based) one for too-complex commands.
async fn source_tree_operation_target(
  parsed_command : @shell_parse.ParseResult,
  cmd : String,
  workspace_root : String,
  cwd : String?,
) -> String? {
  match
    direct_source_tree_operation_target(parsed_command, workspace_root, cwd) {
    Some(target) => Some(target)
    None =>
      dynamic_source_tree_operation_target(
        parsed_command, cmd, workspace_root, cwd,
      )
  }
}

///|
async fn run_agent_shell_with_tree_precheck(
  workspace_root : String,
  cmd : String,
  parsed_command : @shell_parse.ParseResult,
  cwd? : String,
  max_output_chars~ : Int,
  timeout_ms~ : Int,
  foreground_spawn? : async (String, Array[String], String?, Int) -> @shell_exec.ShellExecution,
  on_timeout_detach? : (@shell_exec.ShellExecution, AgentShellLaunch) -> String,
) -> ShellRunResult {
  if source_tree_operation_target(parsed_command, cmd, workspace_root, cwd)
    is Some(target) {
    return ShellPreblockedSourceTree(target)
  }
  let launch = agent_shell_launch(workspace_root, cmd, parsed_command, cwd?)
  match foreground_spawn {
    // Foreground on the shared execution model: spawn on the session group and
    // await it (up to `timeout_ms`). The session-group process outlives this
    // await, so a timeout must stop it here — not leak it — and a turn
    // cancellation must too (the catch stops it before re-raising).
    Some(spawn) => {
      let exec = spawn(launch.program, launch.args, cwd, max_output_chars)
      let finished = @async.with_timeout_opt(timeout_ms, () => {
        exec.wait_or_invalid()
      }) catch {
        error => {
          exec.request_stop()
          raise error
        }
      }
      match finished {
        None =>
          match on_timeout_detach {
            Some(detach) => ShellDetached(detach(exec, launch))
            None => {
              let _ = exec.stop()
              ShellTimedOut
            }
          }
        // Preserve the per-call path's strict-decode behavior: invalid
        // (binary/non-UTF-8) output is a tool error, not replacement characters
        // presented as success.
        Some(_) =>
          // `wait_or_invalid` may return with the child still running (binary
          // output seen); stop it so binary output is an immediate error. Either
          // way this execution finished in the foreground (not adopted), so free
          // its spill file if the retained config opened one.
          if exec.had_invalid_utf8() {
            let _ = exec.stop()
            exec.discard()
            ShellBinaryOutput
          } else {
            let output = agent_shell_output_from_exec(exec, launch)
            exec.discard()
            ShellExecuted(output)
          }
      }
    }
    // No session scope (e.g. `collect_shell_output`, the TUI `!` command): keep
    // the per-call collection path, with the same timeout wrapping as before.
    None => {
      let collected = @async.with_timeout_opt(timeout_ms, () => {
        collect_process_output(
          launch.program,
          launch.args,
          cwd?,
          max_output_chars~,
        )
      })
      match collected {
        None => ShellTimedOut
        Some(output) =>
          ShellExecuted({
            output,
            source_write_sandboxed: launch.source_write_sandboxed,
            sandbox_denial_subjects: launch.sandbox_denial_subjects,
          })
      }
    }
  }
}

///|
/// Adapt a finished foreground execution into an `AgentShellOutput` for the
/// shared renderer: exit code, the in-memory head as the rendered output (a
/// retained execution may also hold a spill file, but a foreground result only
/// ever renders the head), and truncation, plus the launch's sandbox metadata.
fn agent_shell_output_from_exec(
  exec : @shell_exec.ShellExecution,
  launch : AgentShellLaunch,
) -> AgentShellOutput {
  {
    output: {
      exit_code: exec.exit_code(),
      text: exec.head(),
      // Foreground output-limit is the inline cap (max_output_chars): either the
      // detachable execution grew past it (over_inline_cap, large hard cap) or the
      // memory-only one was killed at it (truncated, hard cap == inline cap).
      output_limit_reached: exec.over_inline_cap() || exec.output_truncated(),
    },
    source_write_sandboxed: launch.source_write_sandboxed,
    sandbox_denial_subjects: launch.sandbox_denial_subjects,
  }
}

///|
/// Detach `input.cmd` as a background job through the platform shell and report
/// its id, or a tool error when the tool was built without a job runtime.
async fn start_background(
  input : @decode.ShellInput,
  parsed_command : @shell_parse.ParseResult,
  cwd : String?,
  workspace_root : String,
  bg_runtime? : @bgjobs.BgJobRuntime,
) -> @agent_tool.ToolAction {
  guard bg_runtime is Some(runtime) else {
    return @agent_tool.ToolAction::respond(
      "error: run_in_background is not available in this context",
      is_error=true,
    )
  }
  if input.timeout_ms is Some(_) {
    return @agent_tool.ToolAction::respond(
      "error: timeout_ms is not supported with run_in_background; a background job runs until it finishes or is stopped with shell_stop",
      is_error=true,
    )
  }
  if source_tree_operation_target(
      parsed_command,
      input.cmd,
      workspace_root,
      cwd,
    )
    is Some(target) {
    return @agent_tool.ToolAction::respond(
      direct_source_blocked_content("source tree operation", target),
      is_error=true,
      brief=shell_brief(input.cmd, None),
    )
  }
  let launch = agent_shell_launch(
    workspace_root,
    input.cmd,
    parsed_command,
    cwd?,
  )
  let id = runtime.start(
    program=launch.program,
    args=launch.args,
    command=input.cmd,
    cwd?,
    max_output_chars=input.max_output_chars,
    source_write_sandboxed=launch.source_write_sandboxed,
    sandbox_denial_subjects=launch.sandbox_denial_subjects,
  )
  @agent_tool.ToolAction::respond(
    "started background job \{id}: `\{input.cmd}`. Read its output with shell_output (job_id=\"\{id}\") and stop it with shell_stop (job_id=\"\{id}\").",
    brief="\{@agent_tool.brief_line(input.cmd, limit=48)} → bg \{id}",
  )
}

///|
/// One-line brief for a shell call: the command, plus the exit code when the
/// command failed.
fn shell_brief(cmd : String, exit_code : Int?) -> String {
  let head = @agent_tool.brief_line(cmd, limit=64)
  match exit_code {
    Some(code) if code != 0 => "\{head} → exit \{code}"
    _ => head
  }
}

///|
/// The result of running a shell command line: the `exit_code` (`None` if the
/// command was cancelled or killed before it exited), the merged stdout+stderr
/// `text` (truncated to the character budget), and whether that truncation
/// happened.
pub struct ShellOutput {
  exit_code : Int?
  text : String
  output_limit_reached : Bool
}

///|
priv struct ShellResponse {
  content : String
  is_error : Bool
}

///|
/// Run `cmd` through the platform shell (`sh -c`, or `pwsh -NoProfile -Command`
/// on Windows), capturing merged stdout+stderr. This is the execution core
/// behind the `shell` tool, but it applies NO command policy or safety
/// filtering — so frontends that run explicit user commands (e.g. the TUI's `!`
/// command) can reuse it directly. Callers that want the agent guardrails go
/// through `definition()`/`execute` instead.
pub async fn collect_shell_output(
  cmd : String,
  cwd? : String,
  max_output_chars? : Int = @decode.default_max_output_chars,
) -> ShellOutput {
  collect_process_output(
    PlatformShellProgram,
    platform_shell_args(cmd),
    cwd?,
    max_output_chars~,
  )
}

///|
async fn collect_process_output(
  program : String,
  args : Array[String],
  cwd? : String,
  max_output_chars~ : Int,
) -> ShellOutput {
  let (reader, writer) = @process.read_from_process()
  @async.with_task_group() <| group => {
    defer reader.close()
    let process = @process.spawn(
      group,
      program,
      args,
      stdout=writer,
      stderr=writer,
      cwd?=cwd.map(cwd => cwd.view()),
      cancel_handler=@process.hard_cancel(),
      no_wait=true,
    )
    let prefix = read_output_prefix(reader, max_output_chars)
    let exit_code = if prefix.output_limit_reached {
      None
    } else {
      Some(process.wait())
    }
    {
      exit_code,
      text: prefix.text,
      output_limit_reached: prefix.output_limit_reached,
    }
  }
}

///|
#cfg(platform="windows")
const PlatformShellProgram : String = "pwsh"

///|
#cfg(not(platform="windows"))
const PlatformShellProgram : String = "sh"

///|
#cfg(platform="windows")
fn platform_shell_args(cmd : String) -> Array[String] {
  ["-NoProfile", "-Command", cmd]
}

///|
#cfg(not(platform="windows"))
fn platform_shell_args(cmd : String) -> Array[String] {
  ["-c", cmd]
}

///|
priv struct OutputPrefix {
  text : String
  output_limit_reached : Bool
}

///|
async fn read_output_prefix(
  reader : @process.ReadFromProcess,
  max_output_chars : Int,
) -> OutputPrefix {
  let buffer = Buffer()
  let byte_budget = max_output_chars * 4 + 4
  for ;; {
    let remaining_budget = byte_budget - buffer.length()
    let chunk_limit = if remaining_budget <= 0 {
      1
    } else if remaining_budget < 1024 {
      remaining_budget
    } else {
      1024
    }
    match reader.read_some(max_len=chunk_limit) {
      None =>
        return {
          text: @utf8.decode(buffer.to_bytes()),
          output_limit_reached: false,
        }
      Some(chunk) => {
        buffer.write_bytes(chunk)
        let text = decode_valid_utf8_prefix(buffer.to_bytes())
        if text.char_length() > max_output_chars {
          return {
            text: text_prefix_by_chars(text, max_output_chars),
            output_limit_reached: true,
          }
        } else {
          continue
        }
      }
    }
  }
}

///|
fn text_prefix_by_chars(text : String, max_chars : Int) -> String {
  match text.offset_of_nth_char(max_chars) {
    Some(end) => "\{text[:end]}"
    None => text
  }
}

///|
fn decode_valid_utf8_prefix(bytes : Bytes) -> String raise {
  for dropped in 0..<=3 {
    let end = bytes.length() - dropped
    if end >= 0 {
      try {
        return @utf8.decode(bytes[:end])
      } catch {
        _ => ()
      }
    }
  }
  @utf8.decode(bytes)
}

///|
fn shell_response(
  output : ShellOutput,
  max_output_chars : Int,
) -> ShellResponse {
  if output.output_limit_reached {
    let footer = "<system>\{exit_header(output.exit_code)} truncated=true output_limit_reached=true shown_chars=\{output.text.char_length()} max_output_chars=\{max_output_chars}</system>"
    { content: with_system_footer(output.text, footer), is_error: true }
  } else {
    let code = output.exit_code.unwrap_or(0)
    {
      content: with_system_footer(output.text, "<system>exit=\{code}</system>"),
      is_error: code != 0,
    }
  }
}

///|
fn exit_header(exit_code : Int?) -> String {
  match exit_code {
    Some(code) => "exit=\{code}"
    None => "exit=cancelled"
  }
}

///|
/// Append a trailing `<system>...</system>` metadata footer to command output,
/// matching the `read` tool convention (output first, one footer line last).
/// Output-less commands return just the footer, and a single newline separates
/// output from the footer even when the output already ends in one.
fn with_system_footer(text : String, footer : String) -> String {
  if text == "" {
    footer
  } else if text.has_suffix("\n") {
    "\{text}\{footer}"
  } else {
    "\{text}\n\{footer}"
  }
}

///|
test "shell parses and caps output limit" {
  let input = @decode.decode({
    "cmd": "echo hello",
    "cwd": "/tmp",
    "timeout_ms": 250,
    "max_output_chars": 999999,
  })
  assert_eq(input.cmd, "echo hello")
  assert_true(input.cwd is Some("/tmp"))
  assert_true(input.timeout_ms is Some(250))
  assert_eq(input.max_output_chars, @decode.hard_max_output_chars)
}

///|
test "shell formats output limit metadata" {
  assert_eq(
    shell_response(
      { exit_code: Some(0), text: "abc", output_limit_reached: true },
      3,
    ).content,
    "abc\n<system>exit=0 truncated=true output_limit_reached=true shown_chars=3 max_output_chars=3</system>",
  )
}
