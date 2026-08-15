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
  teardown : () -> Unit
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
  (self.teardown)()
}

///|
/// Spawn `codex app-server`, install the two inbound event receivers before
/// the handshake, then send the required initialize/initialized pair. Returns
/// `None` after fully tearing down any spawn, protocol, or timeout failure.
pub async fn[X] connect(
  group : @async.TaskGroup[X],
  command~ : String,
  notification_handler~ : (String, Json) -> Unit,
  request_handler~ : (@jsonrpc.PeerRequest) -> Bool raise,
  on_closed~ : () -> Unit,
  version~ : String,
  handshake_timeout_ms? : Int = HandshakeTimeoutMs,
) -> Connection? {
  let (child_stdin, stdin_writer) = @process.write_to_process() catch {
    error if @async.is_being_cancelled() => raise error
    _ => return None
  }
  let (stdout_reader, child_stdout) = @process.read_from_process() catch {
    error if @async.is_being_cancelled() => {
      stdin_writer.close()
      raise error
    }
    _ => {
      stdin_writer.close()
      return None
    }
  }
  let (stderr_reader, child_stderr) = @process.read_from_process() catch {
    error if @async.is_being_cancelled() => {
      stdout_reader.close()
      stdin_writer.close()
      raise error
    }
    _ => {
      stdout_reader.close()
      stdin_writer.close()
      return None
    }
  }
  let process = @process.spawn(
    group,
    command,
    ["app-server"],
    inherit_env=true,
    stdin=child_stdin,
    stdout=child_stdout,
    stderr=child_stderr,
    no_console_window=true,
    cancel_handler=@process.graceful_cancel(timeout=1000),
    no_wait=true,
  ) catch {
    error if @async.is_being_cancelled() => {
      stderr_reader.close()
      stdout_reader.close()
      stdin_writer.close()
      raise error
    }
    _ => {
      stderr_reader.close()
      stdout_reader.close()
      stdin_writer.close()
      return None
    }
  }
  let closed : Ref[Bool] = { val: false }
  let teardown_action : Ref[() -> Unit] = {
    val: () => {
      stderr_reader.close()
      stdout_reader.close()
      stdin_writer.close()
      process.cancel()
    },
  }
  let teardown = () => {
    if !closed.val {
      closed.val = true
      (teardown_action.val)()
      on_closed()
    }
  }
  let transport = StdioTransport(stdout_reader, stdin_writer, teardown~)
  let rpc = @jsonrpc.Client::new(transport)
  rpc.set_notification_handler(notification_handler)
  rpc.set_request_handler(request_handler)
  group.spawn_bg(() => rpc.run_message_pump(), no_wait=true, allow_failure=true)
  group.spawn_bg(() => rpc.run_writer(), no_wait=true, allow_failure=true)
  // Drain stderr independently for the process lifetime. App-server can emit
  // model-refresh, network, and crash diagnostics there; retain each complete
  // line in the Desktop JSONL log while keeping the pipe from backpressuring
  // protocol progress on stdout.
  group.spawn_bg(
    () => {
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
  )
  teardown_action.val = () => {
    // Closing the three pipes wakes the background tasks. They remain owned
    // by `group`, so the task group waits for their unwind before reconnecting.
    stderr_reader.close()
    stdout_reader.close()
    stdin_writer.close()
    process.cancel()
  }
  let initialized = @async.with_timeout_opt(handshake_timeout_ms, () => {
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
    error if @async.is_being_cancelled() => {
      teardown()
      raise error
    }
    @jsonrpc.Failed(code~, message~, data~) => {
      JsonRpc(method_="initialize", code~, message~, data~).log()
      teardown()
      return None
    }
    @jsonrpc.Closed => {
      TransportClosed(method_="initialize").log()
      teardown()
      return None
    }
    error => {
      RequestFailed(method_="initialize", detail="\{error}").log()
      teardown()
      return None
    }
  }
  guard initialized is Some(_) else {
    RequestFailed(
      method_="initialize",
      detail="timed out after \{handshake_timeout_ms} ms",
    ).log()
    teardown()
    return None
  }
  rpc.notify(method_="initialized", params=Json::empty_object())
  Some({ rpc, teardown })
}
