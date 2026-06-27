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
/// - `timeout_ms` (number, optional): positive timeout in milliseconds. If the
///   command is still running after the timeout, the process is cancelled and
///   reported as a tool error.
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
) -> @agent_tool.AgentToolDefinition {
  AgentToolDefinition(
    name="shell",
    description=shell_description(),
    schema=JsonSchema({
      "type": "object",
      "properties": {
        "cmd": { "type": "string" },
        "cwd": { "type": "string" },
        "timeout_ms": { "type": "number" },
        "max_output_chars": { "type": "number" },
      },
      "required": ["cmd"],
    }),
    execute=Async(arguments => execute_with_workspace(workspace_root, arguments)),
  )
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
  match
    @command_policy.moonbit_command_policy_error_for_parse(
      input.cmd,
      parsed_command,
    ) {
    Some(message) =>
      return @agent_tool.ToolAction::respond(message, is_error=true)
    None => ()
  }
  let cwd = @workspace_path.resolve_cwd(workspace_root, input.cwd)
  shell(input, parsed_command, cwd, workspace_root) catch {
    error =>
      @agent_tool.ToolAction::respond(
        "error running shell: \{error}",
        is_error=true,
      )
  }
}

///|
async fn shell(
  input : @decode.ShellInput,
  parsed_command : @shell_parse.ParseResult,
  cwd : String?,
  workspace_root : String,
) -> @agent_tool.ToolAction {
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
  match
    direct_source_write_redirect_target(parsed_command, workspace_root, cwd) {
    Some(target) =>
      return @agent_tool.ToolAction::respond(
        direct_source_write_redirect_blocked_content(target),
        is_error=true,
        brief=shell_brief(input.cmd, None),
      )
    None => ()
  }
  let result = match input.timeout_ms {
    Some(timeout_ms) =>
      @async.with_timeout_opt(timeout_ms, () => {
        run_agent_shell_with_tree_precheck(
          workspace_root,
          input.cmd,
          parsed_command,
          cwd?,
          max_output_chars=input.max_output_chars,
        )
      })
    None =>
      Some(
        run_agent_shell_with_tree_precheck(
          workspace_root,
          input.cmd,
          parsed_command,
          cwd?,
          max_output_chars=input.max_output_chars,
        ),
      )
  }
  let agent_output = match result {
    Some(ShellExecuted(output)) => output
    Some(ShellPreblockedSourceTree(target)) =>
      return @agent_tool.ToolAction::respond(
        direct_source_tree_operation_blocked_content(target),
        is_error=true,
        brief=shell_brief(input.cmd, None),
      )
    None => {
      let timeout_ms = match input.timeout_ms {
        Some(timeout_ms) => timeout_ms
        None => 0
      }
      return @agent_tool.ToolAction::respond(
        "error: shell command timed out after \{timeout_ms}ms",
        is_error=true,
      )
    }
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
}

///|
async fn run_agent_shell_with_tree_precheck(
  workspace_root : String,
  cmd : String,
  parsed_command : @shell_parse.ParseResult,
  cwd? : String,
  max_output_chars~ : Int,
) -> ShellRunResult {
  match
    direct_source_tree_operation_target(parsed_command, workspace_root, cwd) {
    Some(target) => ShellPreblockedSourceTree(target)
    None => {
      match
        dynamic_source_tree_operation_target(
          parsed_command, cmd, workspace_root, cwd,
        ) {
        Some(target) => return ShellPreblockedSourceTree(target)
        None => ()
      }
      ShellExecuted(
        collect_agent_shell_output(
          workspace_root,
          cmd,
          parsed_command,
          cwd?,
          max_output_chars~,
        ),
      )
    }
  }
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
    let code = match output.exit_code {
      Some(code) => code
      None => 0
    }
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
