///|
/// The window owns local PTYs running ssh, independent of Route::run's
/// app-server reconnections. Output still uses the terminal's bounded ACK
/// window and the existing byte-transparent frontend protocol.
pub async fn Route::run_terminals(
  self : Route,
  emit : async (@protocol.Notification) -> Unit,
) -> Unit {
  defer self.terminals.shutdown()
  @terminal.run_terminal_pump(self.terminals, push => {
    match push {
      Output(id~, sequence~, data~) =>
        emit(TerminalOutput({ id, sequence, data: @base64.encode(data), }))
      Exited(id~, code~) => emit(TerminalExit({ id, code, }))
    }
  })
}

///|
pub fn Route::close_terminals(self : Route) -> Unit {
  @terminal.close_all_terminals(self.terminals)
}

///|
/// These endpoints are bound to the local window only. No terminal operation
/// enters the remote app-server or resolves a remote path on the local host.
pub fn Route::terminal_endpoints(self : Route) -> Array[@endpoint.Endpoint] {
  [
    Endpoint(@commands.terminal_open, payload => {
      guard payload.workspace is Some(path) && path.has_prefix("/") else {
        raise SshError("SSH terminal requires a resolved remote checkout")
      }
      // Protocol workspace values are decoded URI path components, not
      // percent-encoded URLs. Preserve literal percent signs and Unicode.
      let cwd = path
      let args = @host_client.terminal_args(
        destination=self.profile.destination,
        cwd~,
        command?=payload.command,
      )
      let id = @terminal.open_terminal(
        self.terminals,
        cwd="/",
        cols=payload.cols,
        rows=payload.rows,
        command=[
            "/usr/bin/env",
            "TERM=xterm-256color",
            "COLORTERM=truecolor",
            self.connection.host.config.ssh,
          ] +
          args,
      )
      { id, }
    }),
    Endpoint(@commands.terminal_input, payload => {
      let data = match (payload.data, payload.data_base64) {
        (Some(data), None) => @utf8.encode(data)
        (None, Some(data)) => @base64.decode(data)
        _ => raise SshError("terminal input requires exactly one data field")
      }
      @terminal.write_terminal(self.terminals, id=payload.id, data)
      Acknowledged
    }),
    @endpoint.Endpoint::sync(@commands.terminal_resize, payload => {
      @terminal.resize_terminal(
        self.terminals,
        id=payload.id,
        cols=payload.cols,
        rows=payload.rows,
      )
      Acknowledged
    }),
    @endpoint.Endpoint::sync(@commands.terminal_ack, payload => {
      @terminal.ack_terminal(
        self.terminals,
        id=payload.id,
        sequence=payload.sequence,
      )
      Acknowledged
    }),
    @endpoint.Endpoint::sync(@commands.terminal_close, payload => {
      @terminal.close_terminal(self.terminals, id=payload.id)
      Acknowledged
    }),
  ]
}
