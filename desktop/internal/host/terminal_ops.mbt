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
  terminals : @terminal.TerminalState,
  payload : TerminalOpenPayload,
) -> TerminalOpenReply {
  guard @engine.resolve_in_workspace(
      payload.session,
      "",
      workspace?=payload.workspace,
    )
    is Some(root) else {
    raise HostError("terminal requires a conversation workspace")
  }
  // Scratch workspaces are created lazily by the first engine run. Opening a
  // terminal is also a valid first action, so create that directory here.
  @fsx.ensure_dir(root) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise HostError("could not open the workspace directory: \{error}")
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
