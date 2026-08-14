// One initialized Codex app-server process and its JSON-RPC connection.

///|
/// App-server must answer initialize promptly. This bounds accidental launches
/// of an incompatible `codex` executable and a wedged child process.
const HandshakeTimeoutMs : Int = 30000

///|
/// The initialized JSON-RPC connection. Its tasks and child process belong to
/// the task group passed to `connect`; `shutdown` is an eager, idempotent close.
struct Connection {
  rpc : @jsonrpc.Client
}

///|
pub async fn Connection::request(
  self : Connection,
  method_~ : String,
  params~ : Json,
) -> Json {
  self.rpc.request(method_~, params~)
}

///|
pub async fn Connection::respond(
  self : Connection,
  request : @jsonrpc.PeerRequest,
  result : Json,
) -> Unit {
  self.rpc.respond(request, result)
}

///|
pub async fn Connection::respond_error(
  self : Connection,
  request : @jsonrpc.PeerRequest,
  code~ : Int,
  message~ : String,
) -> Unit {
  self.rpc.respond_error(request, code~, message~)
}

///|
pub fn Connection::is_closed(self : Connection) -> Bool {
  self.rpc.is_closed()
}

///|
pub fn Connection::shutdown(self : Connection) -> Unit {
  self.rpc.close()
}

///|
/// Spawn `codex app-server`, install the two inbound event receivers before
/// the handshake, then send the required initialize/initialized pair. Raises
/// the failure after tearing down any spawn, protocol, or timeout failure.
pub async fn[X] connect(
  group : @async.TaskGroup[X],
  command~ : String,
  notification_handler~ : (String, Json) -> Unit,
  request_handler~ : (@jsonrpc.PeerRequest) -> Bool raise,
  on_closed~ : () -> Unit,
  version~ : String,
  home~ : @pathx.Path?,
  handshake_timeout_ms? : Int = HandshakeTimeoutMs,
) -> Connection {
  // The Desktop's isolated CODEX_HOME must win over anything the login-shell
  // environment inherited. Every process the app-server later spawns inherits
  // it too, so nested codex calls, sandbox approvals, and tool runs agree
  // with the app-server on auth and config.
  let env : Map[String, String] = match home {
    Some(home) => Map([("CODEX_HOME", home.to_string())])
    None => Map([])
  }
  let (executable, args) = app_server_launch(
    command,
    windows=@platform.win32 || @platform.win64,
  )
  let (stdin_writer, stdout_reader, stderr_reader, process) = try {
    let (child_stdin, stdin_writer) = @process.write_to_process()
    errdefer stdin_writer.close()
    let (stdout_reader, child_stdout) = @process.read_from_process()
    errdefer stdout_reader.close()
    let (stderr_reader, child_stderr) = @process.read_from_process()
    errdefer stderr_reader.close()
    let process = @process.spawn(
      group,
      executable,
      args,
      inherit_env=true,
      extra_env=env,
      stdin=child_stdin,
      stdout=child_stdout,
      stderr=child_stderr,
      no_console_window=true,
      cancel_handler=@process.graceful_cancel(timeout=1000),
      no_wait=true,
    )
    (stdin_writer, stdout_reader, stderr_reader, process)
  } catch {
    error if @async.is_being_cancelled() => raise error
    error =>
      raise CodexError::Unavailable(
        "Could not start \{command} app-server via \{executable}: \{error}",
      )
  }
  // As in MCP stdio, each task owns its pipe. Cancel pending IO before the
  // owner closes the handle, so Windows can still deliver its completion.
  let mut torn_down = false
  let mut reader_task : @async.Task[Unit]? = None
  let mut writer_task : @async.Task[Unit]? = None
  let mut stderr_task : @async.Task[Unit]? = None
  let teardown = () => {
    if !torn_down {
      torn_down = true
      if reader_task is Some(task) {
        task.cancel()
      }
      if writer_task is Some(task) {
        task.cancel()
      }
      if stderr_task is Some(task) {
        task.cancel()
      }
      // Closing the writer supplies stdin EOF; process cancellation is the
      // backstop for a server that does not exit on EOF, matching MCP stdio.
      process.cancel()
      on_closed()
    }
  }
  let transport = StdioTransport(stdout_reader, stdin_writer, teardown~)
  let rpc = @jsonrpc.Client(transport)
  rpc.set_notification_handler(notification_handler)
  rpc.set_request_handler(request_handler)
  reader_task = Some(
    group.spawn(
      () => {
        defer stdout_reader.close()
        rpc.run_message_pump()
      },
      no_wait=true,
      allow_failure=true,
    ),
  )
  writer_task = Some(
    group.spawn(
      () => {
        defer stdin_writer.close()
        rpc.run_writer()
      },
      no_wait=true,
      allow_failure=true,
    ),
  )
  // Drain stderr independently for the process lifetime. App-server can emit
  // model-refresh, network, and crash diagnostics there; retain each complete
  // line in the Desktop JSONL log while keeping the pipe from backpressuring
  // protocol progress on stdout.
  stderr_task = Some(
    group.spawn(
      () => {
        defer stderr_reader.close()
        for ;; {
          let line = stderr_reader.read_until("\n") catch {
            error if @async.is_being_cancelled() => raise error
            error => {
              @xlog.warn(category="codex") <?
                {
                  "event": "codex_app_server_stderr_read_failed",
                  "error": "\{error}",
                }
              None
            }
          }
          guard line is Some(line) else { break }
          @xlog.debug(category="codex") <?
            { "event": "codex_app_server_stderr", "line": line }
        }
      },
      no_wait=true,
      allow_failure=true,
    ),
  )
  errdefer rpc.close()
  let _ = @async.with_timeout(handshake_timeout_ms, () => {
    rpc.request(method_="initialize", params={
      "clientInfo": {
        "name": "openseek_desktop",
        "title": "OpenSeek Desktop",
        "version": version,
      },
      // Paginated Codex histories are read through `thread/turns/list`. That
      // method remains experimental in app-server 0.146, so advertise exactly
      // the capability needed by the Desktop's read-only history fallback.
      "capabilities": { "experimentalApi": true },
    })
  }) catch {
    error if @async.is_being_cancelled() => raise error
    error => {
      let error : CodexError = match error {
        @jsonrpc.Failed(code~, message~, data~) =>
          JsonRpc(method_="initialize", code~, message~, data~)
        @jsonrpc.Closed => TransportClosed(method_="initialize")
        @async.TimeoutError =>
          RequestFailed(
            method_="initialize",
            detail="timed out after \{handshake_timeout_ms} ms",
          )
        error => RequestFailed(method_="initialize", detail="\{error}")
      }
      error.log()
      raise error
    }
  }
  rpc.notify(method_="initialized", params=Json::empty_object())
  { rpc, }
}
