// The integrated terminal's request ops: open a session in the conversation
// workspace with the selected toolchain first on PATH, and decode input.

///|
fn @protocol.TerminalInputPayload::bytes(
  self : @protocol.TerminalInputPayload,
) -> Bytes raise TerminalError {
  match (self.data, self.data_base64) {
    (Some(data), None) => @utf8.encode(data)
    (None, Some(data)) =>
      @base64.decode(data) catch {
        _ => raise TerminalError("terminal input contains invalid base64")
      }
    _ =>
      raise TerminalError("terminal input must contain exactly one data field")
  }
}

///|
pub async fn TerminalState::open(
  self : TerminalState,
  payload : @protocol.TerminalOpenPayload,
  engine~ : String,
  runtime_dir? : @pathx.Path,
  source~ : @moonbit.ToolchainSource,
  bin_dir? : String,
) -> @protocol.TerminalOpenReply {
  guard @work_dir.resolve_in_workspace(
      payload.session,
      "",
      workspace?=payload.workspace,
    )
    is Some(root) else {
    raise TerminalError("terminal requires a conversation workspace")
  }
  // Match the engine and language services: packaged command-line tools and a
  // packaged MoonBit seed win when present. Queue one combined path update
  // after shell startup so rc/profile files cannot overwrite the selection.
  // Its entries leave the final order as moon-bin, packaged-bin, then the
  // shell's PATH. Unknown shells stay usable without receiving a command in
  // another shell's syntax. MOON_HOME remains the user's registry and caches.
  let toolchain = @moonbit.resolve_toolchain(engine, runtime_dir?, source~)
  let windows = @async.platform is Windows
  let shell_command = if windows {
    @sys.get_env_var("COMSPEC").unwrap_or("cmd.exe")
  } else {
    @sys.get_env_var("SHELL").unwrap_or("/bin/sh")
  }
  let path_entries = [toolchain.bin_dir.to_string()]
  if bin_dir is Some(bin_dir) {
    path_entries.push(bin_dir)
  }
  // A `!` command is the session's only process: no login shell starts, so
  // there is no prompt to activate and the path rides the command's own argv.
  if payload.command is Some(command) {
    guard !command.is_blank() else {
      raise TerminalError("terminal command must not be empty")
    }
    let id = self.spawn(
      cwd=root.to_string(),
      cols=payload.cols,
      rows=payload.rows,
      command=command_argv(command, path_entries, shell=shell_command, windows~),
    )
    return { id, }
  }
  let activation_command = @shellenv.path_prepend_command(
    shell_command,
    path_entries,
    windows~,
  )
  let id = self.spawn(
    cwd=root.to_string(),
    cols=payload.cols,
    rows=payload.rows,
  )
  if activation_command is Some(command) {
    self.write(id~, @utf8.encode(command)) catch {
      TerminalError(message) => {
        self.close(id~)
        raise TerminalError(
          "could not activate terminal command-line tools: \{message}",
        )
      }
      error => {
        self.close(id~)
        raise error
      }
    }
  }
  { id, }
}

///|
/// The argv that runs one `!` command line as a terminal session's only
/// process, with `path_entries` ahead of the shell's search path. POSIX hands
/// the text to the user's shell non-interactively (`$SHELL -c`), under
/// `/usr/bin/env` so the terminal capabilities are set without a quoting
/// script. Windows runs it through `powershell.exe`, like the agent's own
/// commands, with UTF-8 output so non-ASCII text survives the code page.
///
/// The path prefix is the first line of the script itself, in the shell's own
/// syntax, exactly as the interactive terminal types it after startup: set in
/// the environment instead, a `.zshenv` that prepends to PATH would put the
/// user's own tools back in front. A shell whose syntax is unknown runs the
/// command with its path as it is. Pagers are turned off on both platforms:
/// the tab may not be on screen, and a `git log` parked in `less` would wait
/// for a keypress nobody knows to give.
fn command_argv(
  command : String,
  path_entries : Array[String],
  shell~ : String,
  windows~ : Bool,
) -> Array[String] {
  // `path_prepend_command` ends its line the way a typed line ends; inside a
  // script the line ends with a separator instead.
  let activation = (interpreter : String, separator : String) => {
    @shellenv.path_prepend_command(interpreter, path_entries, windows~)
    .map(line => line.trim_end(chars="\r").to_owned() + separator)
    .unwrap_or("")
  }
  if windows {
    let activation = activation("powershell.exe", ";")
    return [
      "powershell.exe",
      "-NoProfile",
      "-Command",
      // `powershell -Command` reports any failing native command as 1. When
      // the command line's last statement failed, hand back the native
      // status it left, or 1 for a cmdlet, which sets none. `$?` decides:
      // `$LASTEXITCODE` alone would still hold an earlier failure the line
      // went on to recover from.
      "\{activation}$env:PAGER='cat';$env:GIT_PAGER='cat';$OutputEncoding=[Console]::OutputEncoding=[Text.Encoding]::UTF8;chcp 65001 > $null;\{command}\nif(-not $?){if($LASTEXITCODE){exit $LASTEXITCODE};exit 1}",
    ]
  }
  [
    "/usr/bin/env",
    "TERM=xterm-256color",
    "COLORTERM=truecolor",
    "PAGER=cat",
    "GIT_PAGER=cat",
    shell,
    "-c",
    activation(shell, "\n") + command,
  ]
}

///|
test "a ! command runs under the user's shell with the toolchain first on PATH" {
  assert_eq(
    command_argv(
      "moon test | tail -3",
      ["/app/moon/bin", "/app/bin"],
      shell="/bin/zsh",
      windows=false,
    ),
    [
      "/usr/bin/env", "TERM=xterm-256color", "COLORTERM=truecolor", "PAGER=cat",
      "GIT_PAGER=cat", "/bin/zsh", "-c", "export PATH='/app/moon/bin':'/app/bin':\"$PATH\"\nmoon test | tail -3",
    ],
  )
  // A shell whose syntax is unknown gets the command alone.
  assert_true(
    command_argv("ls", ["/app/bin"], shell="/opt/bin/xonsh", windows=false)
    is [.., "/opt/bin/xonsh", "-c", "ls"],
  )
  guard command_argv("dir", ["C:\\app\\bin"], shell="cmd.exe", windows=true)
    is ["powershell.exe", "-NoProfile", "-Command", script] else {
    fail("expected a powershell invocation")
  }
  assert_true(script.has_prefix("$env:Path = 'C:\\app\\bin;' + $env:Path;"))
  assert_true(script.contains("$env:GIT_PAGER='cat';"))
  assert_true(
    script.has_suffix(
      ";dir\nif(-not $?){if($LASTEXITCODE){exit $LASTEXITCODE};exit 1}",
    ),
  )
}

///|
pub async fn TerminalState::input(
  self : TerminalState,
  payload : @protocol.TerminalInputPayload,
) -> Unit {
  self.write(id=payload.id, payload.bytes())
}
