// The host side of the integrated terminal: a session table plus the ops the
// IPC layer calls into. PTY processes themselves are owned by the pump
// (`run_terminal_pump`), which runs inside the host services' task group —
// see pump.mbt.

///|
/// A host-side failure with a user-facing message; the IPC boundary
/// translates it into the error the webview displays.
pub suberror TerminalError {
  TerminalError(String)
}

///|
/// The request queue uses this private error only to wake and stop its pump.
/// Callers instead receive `TerminalError` from their individual reply queue.
priv suberror TerminalPumpClosed {
  TerminalPumpClosed
}

///|
/// One push from a terminal session to the webview. `Output` carries raw PTY
/// bytes (chunk boundaries may split UTF-8 sequences, so the wire encoding
/// must stay byte-transparent); `Exited` reports the child's exit code after
/// the session drained.
pub(all) enum TerminalPush {
  /// `sequence` identifies this output chunk within one session. The webview
  /// echoes it in `terminal_ack`, making retries safe when a bridge response
  /// is lost after the host already applied the acknowledgement.
  Output(id~ : String, sequence~ : Int, data~ : Bytes)
  Exited(id~ : String, code~ : Int)
}

///|
/// Stop reading the PTY once this many emitted bytes are unacknowledged; the
/// kernel PTY buffer then fills and the child blocks, so a `cat` of a huge
/// file cannot flood the webview.
const HighWatermark = 262144

///|
/// Resume reading once acknowledgements bring the debt below this.
const LowWatermark = 65536

///|
priv struct TerminalSession {
  pty : @pty.Pty
  /// Bytes emitted to the webview but not yet acknowledged.
  mut unacked : Int
  /// Each sequence remains here until its acknowledgement is applied. Removing
  /// it exactly once makes a retried acknowledgement idempotent.
  unacked_chunks : Map[Int, Int]
  mut next_output_sequence : Int
  /// Wakes the session's read loop when acknowledgements drain the debt or
  /// the session starts closing.
  cond : @cond_var.Cond
  /// Carries the one shutdown request to the session task. Process
  /// cancellation is async, so the synchronous host op only signals here.
  close_requested : @async.Queue[Unit]
  mut closing : Bool
}

///|
priv struct OpenRequest {
  id : String
  /// The page connection that submitted this request. A later connect
  /// handshake invalidates it even if the pump has already dequeued it.
  connection_generation : Int
  argv : Array[String]
  /// The directory passed directly to the PTY process spawn.
  cwd : String
  cols : Int
  rows : Int
  /// Spawn outcome for the waiting `open_terminal` call.
  reply : @async.Queue[Result[Unit, String]]
}

///|
/// The terminal subsystem's shared state: the pump's mailbox of pending
/// spawns, the table of live sessions, and the current page connection.
struct TerminalState {
  requests : @async.Queue[OpenRequest]
  sessions : Map[String, TerminalSession]
  /// Once closed, this state cannot serve another connection. Page reconnects
  /// use `close_all_terminals` instead and leave the pump available.
  mut closed : Bool
  /// Incremented by the connect handshake so opens from an older page cannot
  /// publish a session after that page has gone away.
  mut connection_generation : Int
}

///|
pub fn new_terminal_state() -> TerminalState {
  {
    requests: Queue(kind=Unbounded),
    sessions: Map([]),
    closed: false,
    connection_generation: 0,
  }
}

///|
/// Open a terminal session in `cwd` and return its id once the child is
/// running. Without `command`, POSIX launches `$SHELL -l` and Windows launches
/// `%COMSPEC%`; with it, that argv runs directly in the session's PTY instead.
/// Requires `run_terminal_pump` to be running (the host services' task
/// group), otherwise the call waits until it is. A permanently shut down state
/// rejects the request instead of leaving its caller parked.
pub async fn open_terminal(
  state : TerminalState,
  cwd~ : String,
  cols~ : Int,
  rows~ : Int,
  command? : Array[String],
) -> String {
  guard !state.closed else { raise TerminalError("terminal service is closed") }
  let argv = session_argv(command?)
  guard @uuid.mint() is Some(id) else {
    raise TerminalError("could not create a terminal id")
  }
  let reply : @async.Queue[Result[Unit, String]] = Queue(kind=Blocking(1))
  state.requests.put({
    id,
    connection_generation: state.connection_generation,
    argv,
    cwd,
    cols,
    rows,
    reply,
  }) catch {
    TerminalPumpClosed => raise TerminalError("terminal service is closed")
    error => raise error
  }
  match reply.get() {
    Ok(_) => id
    Err(message) => raise TerminalError(message)
  }
}

///|
/// Write user input (already encoded as terminal input bytes) to a session.
pub async fn write_terminal(
  state : TerminalState,
  id~ : String,
  data : Bytes,
) -> Unit {
  guard state.sessions.get(id) is Some(session) else {
    raise TerminalError("terminal \{id} is not open")
  }
  session.pty.write(data) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise TerminalError(@debug.render(Repr(error)))
  }
}

///|
/// Propagate a webview-side viewport change to the PTY.
pub fn resize_terminal(
  state : TerminalState,
  id~ : String,
  cols~ : Int,
  rows~ : Int,
) -> Unit raise {
  guard state.sessions.get(id) is Some(session) else {
    raise TerminalError("terminal \{id} is not open")
  }
  session.pty.resize(cols~, rows~) catch {
    error => raise TerminalError("terminal resize failed: \{error}")
  }
}

///|
/// Acknowledge one output chunk the webview has finished rendering. A sequence
/// is removed at most once, so retrying after a lost bridge response cannot
/// double-release the flow-control window.
pub fn ack_terminal(
  state : TerminalState,
  id~ : String,
  sequence~ : Int,
) -> Unit {
  guard state.sessions.get(id) is Some(session) else { return }
  guard session.unacked_chunks.get(sequence) is Some(bytes) else { return }
  session.unacked_chunks.remove(sequence)
  session.unacked -= bytes
  if session.unacked < 0 {
    session.unacked = 0
  }
  if session.unacked < LowWatermark {
    session.cond.signal()
  }
}

///|
/// Request a session's shutdown. Its owning task group cancels the PTY wait and
/// output tasks together; the PTY then closes its controlling handle, allows a
/// bounded graceful exit, and releases its native resources before `Exited`.
/// Unknown ids are a no-op (already exited).
pub fn close_terminal(state : TerminalState, id~ : String) -> Unit {
  guard state.sessions.get(id) is Some(session) else { return }
  guard !session.closing else { return }
  session.closing = true
  session.cond.broadcast()
  // A full or closed queue means the only shutdown request is already being
  // handled, so repeated close operations remain harmless.
  ignore(session.close_requested.try_put(()) catch { _ => false })
}

///|
/// Retire every live session and invalidate every open requested by an older
/// page. A freshly (re)loaded page cannot reclaim the old page's terminal
/// tabs, including requests the pump has not published as sessions yet.
pub fn close_all_terminals(state : TerminalState) -> Unit {
  // Incrementing before the live-session sweep also covers requests that the
  // pump dequeued but whose PTY spawn has not completed.
  state.connection_generation += 1
  // Materialized: teardown mutates the table as sessions unwind.
  for id in state.sessions.keys().to_array() {
    close_terminal(state, id~)
  }
}

///|
/// Permanently stop this connection's terminal subsystem. Pending open calls
/// are rejected before the request queue closes, so neither they nor an idle
/// pump remain parked. Repeated shutdown calls are harmless.
pub fn TerminalState::shutdown(self : TerminalState) -> Unit {
  guard !self.closed else { return }
  self.closed = true
  close_all_terminals(self)
  // A request still in this queue has an opener blocked on its private reply.
  // Close that reply explicitly before removing the pump's only route to it.
  while (self.requests.try_get() catch { _ => None }) is Some(request) {
    request.reply.close(
      error=TerminalError("terminal service is closed"),
      clear=true,
    )
  }
  self.requests.close(error=TerminalPumpClosed, clear=true)
}
