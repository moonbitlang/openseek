// The app-lifetime pump owns PTY tasks. Connection tasks only forward retained
// output; disconnecting them leaves shells running within a bounded grace
// period. The output window applies backpressure when no renderer drains it.

///|
/// Read PTY output in chunks this large; a typical child burst fits in one.
const ReadChunkBytes = 16384

///|
/// Run terminal sessions until the state shuts down or this task is cancelled,
/// retaining output until an attached client acknowledges it.
pub async fn run_terminal_pump(state : TerminalState) -> Unit {
  defer state.shutdown()
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => {
      while !state.closed {
        @async.sleep(state.grace_ms.min(1000))
        let now = @async.now()
        for (id, session) in state.sessions.to_array() {
          if (
              session.detached_at is Some(since) &&
              now - since >= state.grace_ms.to_int64()
            ) ||
            (
              session.exited is Some((_, since)) &&
              (session.closing || now - since >= state.grace_ms.to_int64())
            ) {
            session.close()
            state.sessions.remove(id)
            if session.owner is Some(owner) {
              owner.sessions.remove(id)
            }
          }
        }
      }
    })
    for ;; {
      let request = state.requests.get() catch {
        TerminalPumpClosed => return
        error => raise error
      }
      if state.sessions.length() + state.opening >= 128 {
        request.reply.put(Err("too many terminal sessions"))
        continue
      }
      state.opening += 1
      group.spawn_bg(allow_failure=true, () => run_session(state, request))
    }
  })
}

///|
/// Stop a session through the task group that owns its PTY. PTY 0.4 closes the
/// controlling handle when cancellation begins, gives the child five seconds
/// to exit, and then kills the process tree if it is still running.
async fn TerminalSession::close_when_requested(
  self : TerminalSession,
  group : @async.TaskGroup[Unit],
) -> Unit {
  self.close_requested.get()
  group.return_immediately(())
}

///|
/// One session's lifetime: spawn the PTY child, answer the opener, then loop
/// reading output until the child exits (or `close_terminal` requests it),
/// pausing whenever the flow-control debt passes the high watermark.
async fn run_session(state : TerminalState, request : OpenRequest) -> Unit {
  let mut reserved = true
  defer (if reserved { state.opening -= 1 })
  defer request.reply.close(
    error=TerminalError("terminal open did not complete"),
    clear=false,
  )
  let mut opened_pty : @pty.Pty? = None
  @async.with_task_group(group => {
    if state.closed ||
      request.client.closed ||
      request.generation != request.client.generation {
      let message = if state.closed {
        "terminal service is closed"
      } else {
        "terminal open was cancelled by reconnect"
      }
      request.reply.put(Err(message))
      return
    }
    guard request.argv.get(0) is Some(file) else {
      request.reply.put(Err("terminal command must not be empty"))
      return
    }
    if request.client.sessions.length() >= 32 {
      request.reply.put(Err("too many terminal sessions"))
      return
    }
    let args = request.argv[1:].map(arg => arg.view())
    let pty = @pty.spawn(
      group,
      file.view(),
      args,
      // The PTY applies the working directory in the platform spawn call,
      // so neither POSIX nor Windows needs a shell command that performs cd.
      cwd=request.cwd,
      cols=request.cols,
      rows=request.rows,
    ) catch {
      error => {
        request.reply.put(Err(@debug.render(Repr(error))))
        return
      }
    }
    // Capture the id before publishing the session. The PTY handle mutates its
    // own copy during close, but this value remains the identity of the child
    // created for this session.
    let pid = pty.pid()
    if pid <= 0 {
      request.reply.put(
        Err("terminal spawn returned a non-positive process id"),
      )
      group.return_immediately(())
      return
    }
    // Spawning suspends, so a reconnect can invalidate the request while the
    // child is being created. Close it before publishing a stale session.
    if state.closed ||
      request.client.closed ||
      request.generation != request.client.generation {
      let message = if state.closed {
        "terminal service is closed"
      } else {
        "terminal open was cancelled by reconnect"
      }
      request.reply.put(Err(message))
      group.return_immediately(())
      return
    }
    if request.client.sessions.length() >= 32 {
      request.reply.put(Err("too many attached terminals"))
      group.return_immediately(())
      return
    }
    let session : TerminalSession = {
      pty,
      write_guard: Mutex(),
      last_owner_key: request.client.key,
      output: { unacked: 0, chunks: Deque([]), next_sequence: 1, },
      cond: Cond(),
      close_requested: Queue(kind=Blocking(1)),
      closing: false,
      retained: Deque([]),
      owner: Some(request.client),
      detached_at: None,
      exited: None,
    }
    state.opening -= 1
    reserved = false
    state.sessions[request.id] = session
    request.client.sessions[request.id] = {
      session,
      sent: 0,
      exit_sent: false,
    }
    opened_pty = Some(pty)
    request.reply.put(Ok(()))
    @xlog.debug() <?
      {
        "event": "terminal_spawn",
        "id": request.id,
        "pid": pid,
        "argv0": request.argv.get(0).unwrap_or(""),
        // The directory passed directly to the platform process spawn.
        "cwd": request.cwd,
      }
    let output_task = group.spawn(allow_failure=true, () => {
      let buf : FixedArray[Byte] = FixedArray::make(ReadChunkBytes, b'\x00')
      for ;; {
        // A closed master reports the child's exit as EIO on macOS rather
        // than a clean EOF; both end the session the same way.
        let n = pty.read(buf) catch {
          // Cancelling the Windows output task aborts its synchronous pipe
          // read. Treat that requested shutdown as EOF for this session.
          _ if session.closing => 0
          _ => 0
        }
        if n <= 0 {
          break
        }
        // Record the debt before emitting: the webview can acknowledge as soon
        // as it receives the event, including before this task resumes.
        let sequence = session.output.record(n)
        session.retained.push_back((sequence, Bytes::from_array(buf[:n])))
        if session.owner is Some(owner) {
          owner.changed.broadcast()
        }
        while (
                session.output.unacked >= HighWatermark ||
                session.retained.length() >= 4096
              ) &&
              !session.closing {
          session.cond.wait()
        }
      }
    })
    // The PTY owns the platform-specific process and handle shutdown. The
    // watcher only ends the task group that owns those resources.
    group.spawn_bg(no_wait=true, () => session.close_when_requested(group))
    output_task.wait() catch {
      _ if session.closing => ()
      error => raise error
    }
  })
  guard opened_pty is Some(pty) else { return }
  // The task group has finished, so the PTY's wait task already holds the
  // natural or cancellation-driven exit result even though its handles are
  // now closed.
  let code = pty.wait() catch { _ => -1 }
  @xlog.debug() <? { "event": "terminal_exit", "id": request.id, "code": code }
  if state.sessions.get(request.id) is Some(session) {
    session.exited = Some((code, @async.now()))
    if session.owner is Some(owner) {
      owner.changed.broadcast()
    }
  }
}

///|
/// Build the argv for a Windows session: the requested command when present,
/// or the system command interpreter from `%COMSPEC%`.
#cfg(platform="windows")
fn session_argv(command? : Array[String]) -> Array[String] raise TerminalError {
  if command is Some(argv) {
    guard !argv.is_empty() else {
      raise TerminalError("terminal command must not be empty")
    }
    return argv
  }
  [@env.get("COMSPEC").unwrap_or("cmd.exe")]
}

///|
/// Build the argv for a POSIX session: the requested command when present,
/// or the user's login shell with the terminal emulator capabilities set.
/// `/usr/bin/env` execs the shell directly without a quoting or `cd` script.
#cfg(not(platform="windows"))
fn session_argv(command? : Array[String]) -> Array[String] raise TerminalError {
  if command is Some(argv) {
    guard !argv.is_empty() else {
      raise TerminalError("terminal command must not be empty")
    }
    return argv
  }
  let shell = @env.get("SHELL").unwrap_or("/bin/sh")
  ["/usr/bin/env", "TERM=xterm-256color", "COLORTERM=truecolor", shell, "-l"]
}
