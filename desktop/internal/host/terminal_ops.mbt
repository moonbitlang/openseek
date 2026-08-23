// The integrated terminal's transport-independent host ops. PTY output stays
// byte-transparent across JSON by using base64; each emitted chunk also has a
// per-session sequence so a client can retry an acknowledgement safely.

///|
type TerminalOpenPayload = @protocol.TerminalOpenPayload

///|
type TerminalOpenReply = @protocol.TerminalOpenReply

///|
type TerminalInputPayload = @protocol.TerminalInputPayload

///|
fn TerminalInputPayload::bytes(
  self : TerminalInputPayload,
) -> Bytes raise HostError {
  match (self.data, self.data_base64) {
    (Some(data), None) => @utf8.encode(data)
    (None, Some(data)) =>
      @base64.decode(data) catch {
        _ => raise HostError("terminal input contains invalid base64")
      }
    _ => raise HostError("terminal input must contain exactly one data field")
  }
}

///|
type TerminalResizePayload = @protocol.TerminalResizePayload

///|
type TerminalAckPayload = @protocol.TerminalAckPayload

///|
type TerminalClosePayload = @protocol.TerminalClosePayload

///|
priv struct TerminalOutputPayload {
  id : Int
  sequence : Int
  data : String
}

///|
priv struct TerminalExitPayload {
  id : Int
  code : Int
}

///|
async fn terminal_open_op(
  state : HostState,
  terminals : @terminal.TerminalState,
  payload : TerminalOpenPayload,
) -> TerminalOpenReply {
  guard @work_dir.resolve_in_workspace(
      payload.session,
      "",
      workspace?=payload.workspace,
    )
    is Some(root) else {
    raise HostError("terminal requires a conversation workspace")
  }
  // Match the engine and language services: packaged command-line tools and a
  // packaged MoonBit seed win when present. Queue both path updates after shell
  // startup so rc/profile files cannot overwrite the selection. The toolchain
  // command runs second, leaving the final order as moon-bin, packaged-bin,
  // then the shell's PATH. Unknown shells stay usable without receiving a
  // command in another shell's syntax. MOON_HOME remains the user's registry
  // and caches.
  let toolchain = @moonbit.resolve_toolchain(
    state.engine,
    runtime_dir?=state.runtime_dir,
  ) catch {
    error if @async.is_being_cancelled() => raise error
    @moonbit.ToolchainUnavailable as unavailable =>
      raise HostError("\{unavailable}")
    error => raise HostError("could not resolve a MoonBit toolchain: \{error}")
  }
  let windows = @sysplatform.win32 || @sysplatform.win64
  let shell_command = if windows {
    @sys.get_env_var("COMSPEC").unwrap_or("cmd.exe")
  } else {
    @sys.get_env_var("SHELL").unwrap_or("/bin/sh")
  }
  let activation_commands : Array[String] = []
  if state.executable is Some(executable) &&
    PackagedTools::resolve(executable) is Some(tools) &&
    tools.terminal_path_command(shell_command, windows~) is Some(command) {
    activation_commands.push(command)
  }
  if @shellenv.path_prepend_command(
      shell_command,
      toolchain.bin_dir.to_string(),
      windows~,
    )
    is Some(command) {
    activation_commands.push(command)
  }
  let id = @terminal.open_terminal(
    terminals,
    cwd=root.to_string(),
    cols=payload.cols,
    rows=payload.rows,
  ) catch {
    @terminal.TerminalError(message) => raise HostError(message)
    error => raise error
  }
  if !activation_commands.is_empty() {
    @terminal.write_terminal(
      terminals,
      id~,
      @utf8.encode(activation_commands.join("")),
    ) catch {
      @terminal.TerminalError(message) => {
        @terminal.close_terminal(terminals, id~)
        raise HostError(
          "could not activate terminal command-line tools: \{message}",
        )
      }
      error => {
        @terminal.close_terminal(terminals, id~)
        raise error
      }
    }
  }
  { id, }
}

///|
async fn terminal_input_op(
  terminals : @terminal.TerminalState,
  payload : TerminalInputPayload,
) -> Unit {
  @terminal.write_terminal(terminals, id=payload.id, payload.bytes()) catch {
    @terminal.TerminalError(message) => raise HostError(message)
    error => raise error
  }
}

///|
fn terminal_resize_op(
  terminals : @terminal.TerminalState,
  payload : TerminalResizePayload,
) -> Unit raise {
  @terminal.resize_terminal(
    terminals,
    id=payload.id,
    cols=payload.cols,
    rows=payload.rows,
  ) catch {
    @terminal.TerminalError(message) => raise HostError(message)
    error => raise error
  }
}

///|
fn terminal_ack_op(
  terminals : @terminal.TerminalState,
  payload : TerminalAckPayload,
) -> Unit {
  @terminal.ack_terminal(terminals, id=payload.id, sequence=payload.sequence)
}

///|
fn terminal_close_op(
  terminals : @terminal.TerminalState,
  payload : TerminalClosePayload,
) -> Unit {
  @terminal.close_terminal(terminals, id=payload.id)
}
