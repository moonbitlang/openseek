// The host side of the integrated terminal: a session table plus the ops the
// IPC layer calls into. PTY processes themselves are owned by the pump
// (`run_pump`), which runs inside the host services' task group —
// see pump.mbt.

///|
/// A host-side failure with a user-facing message; the IPC boundary
/// translates it into the error the webview displays.
pub suberror TerminalError {
  InvalidBase64Input
  AmbiguousInput
  NoWorkspace
  EmptyCommand
  ServiceClosed
  CancelledByReconnect
  SpawnFailed(String)
  NotOpen(String)
  WriteFailed(String)
  ResizeFailed(String)
}

///|
pub impl Show for TerminalError with fn output(self, logger) {
  let message = match self {
    InvalidBase64Input => "terminal input contains invalid base64"
    AmbiguousInput => "terminal input must contain exactly one data field"
    NoWorkspace => "terminal requires a conversation workspace"
    EmptyCommand => "terminal command must not be empty"
    ServiceClosed => "terminal service is closed"
    CancelledByReconnect => "terminal open was cancelled by reconnect"
    SpawnFailed(detail) => "terminal spawn failed: \{detail}"
    NotOpen(id) => "terminal \{id} is not open"
    WriteFailed(detail) => "terminal write failed: \{detail}"
    ResizeFailed(detail) => "terminal resize failed: \{detail}"
  }
  logger.write_string(message)
}

///|
pub extend TerminalError with Show::{output, to_string}

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
  /// echoes the latest rendered value in `terminal_ack`; acknowledging a
  /// sequence also acknowledges every earlier outstanding chunk.
  Output(id~ : String, sequence~ : Int32, data~ : Bytes)
  Exited(id~ : String, code~ : Int32)
}

///|
/// Stop reading the PTY once this many emitted bytes are unacknowledged; the
/// kernel PTY buffer then fills and the child blocks, so a `cat` of a huge
/// file cannot flood the webview.
const HighWatermark = 262144

///|
/// Outstanding output for one terminal. Acknowledgements are cumulative so a
/// later successful request covers earlier requests that did not reach the
/// host. An unknown future sequence remains a no-op instead of releasing data
/// the client has not demonstrated it received.
priv struct TerminalOutputWindow {
  mut unacked : Int32
  // Byte counts in sequence order. The first outstanding sequence is
  // `next_sequence - chunks.length()`, so no sequence-to-size map is needed.
  chunks : @deque.Deque[Int32]
  mut next_sequence : Int32
}

///|
/// Record one emitted chunk before it becomes visible to the client and
/// return its monotonically increasing sequence.
fn TerminalOutputWindow::record(
  self : TerminalOutputWindow,
  bytes : Int32,
) -> Int32 {
  let sequence = self.next_sequence
  self.next_sequence += 1
  self.chunks.push_back(bytes)
  self.unacked += bytes
  sequence
}

///|
/// Release `sequence` and every earlier outstanding chunk. The result tells
/// the blocked reader whether the bounded window has capacity again.
fn TerminalOutputWindow::acknowledge_through(
  self : TerminalOutputWindow,
  sequence : Int32,
) -> Bool {
  let first_sequence = self.next_sequence - self.chunks.length()
  let acknowledged_chunks = sequence - first_sequence + 1
  guard acknowledged_chunks > 0 && acknowledged_chunks <= self.chunks.length() else {
    return false
  }
  for bytes in self.chunks.drain(start=0, len=acknowledged_chunks) {
    self.unacked -= bytes
  }
  self.unacked < HighWatermark
}

///|
test "a later terminal acknowledgement advances the output window" {
  let window : TerminalOutputWindow = {
    unacked: 0,
    chunks: Deque([]),
    next_sequence: 1,
  }
  for sequence in 1..<=16 {
    assert_eq(window.record(16384), sequence)
  }
  assert_eq(window.unacked, HighWatermark)
  // A successful acknowledgement before four missing tail requests frees
  // capacity immediately; the reader can emit another chunk whose later
  // cumulative acknowledgement retires the whole missing suffix.
  assert_true(window.acknowledge_through(12))
  assert_eq(window.unacked, 65536)
  assert_eq(window.chunks.length(), 4)
  assert_eq(window.record(16384), 17)
  assert_true(window.acknowledge_through(17))
  assert_eq(window.unacked, 0)
  assert_true(window.chunks.is_empty())
  // Duplicate and invented future acknowledgements cannot release anything.
  assert_false(window.acknowledge_through(17))
  assert_eq(window.record(16384), 18)
  assert_false(window.acknowledge_through(19))
  assert_eq(window.unacked, 16384)
}

///|
priv struct TerminalSession {
  pty : @pty.Pty
  output : TerminalOutputWindow
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
  connection_generation : Int32
  argv : Array[String]
  /// The directory passed directly to the PTY process spawn.
  cwd : String
  cols : Int32
  rows : Int32
  /// Spawn outcome for the waiting `spawn` call.
  reply : @async.Queue[Result[Unit, TerminalError]]
}

///|
/// The terminal subsystem's shared state: the pump's mailbox of pending
/// spawns, the table of live sessions, and the current page connection.
struct TerminalState {
  requests : @async.Queue[OpenRequest]
  sessions : Map[String, TerminalSession]
  /// Once closed, this state cannot serve another connection. Page reconnects
  /// use `close_all` instead and leave the pump available.
  mut closed : Bool
  /// Incremented by the connect handshake so opens from an older page cannot
  /// publish a session after that page has gone away.
  mut connection_generation : Int32
}

///|
pub fn TerminalState::TerminalState() -> TerminalState {
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
/// Requires `run_pump` to be running (the host services' task
/// group), otherwise the call waits until it is. A permanently shut down state
/// rejects the request instead of leaving its caller parked.
async fn TerminalState::spawn(
  self : TerminalState,
  cwd~ : String,
  cols~ : Int32,
  rows~ : Int32,
  command? : Array[String],
) -> String {
  guard !self.closed else { raise ServiceClosed }
  let argv = session_argv(command?)
  let id = @uuid.mint()
  let reply : @async.Queue[Result[Unit, TerminalError]] = Queue(
    kind=Blocking(1),
  )
  self.requests.put({
    id,
    connection_generation: self.connection_generation,
    argv,
    cwd,
    cols,
    rows,
    reply,
  }) catch {
    TerminalPumpClosed => raise ServiceClosed
    error => raise error
  }
  match reply.get() {
    Ok(_) => id
    Err(error) => raise error
  }
}

///|
/// Write user input (already encoded as terminal input bytes) to a session.
async fn TerminalState::write(
  self : TerminalState,
  id~ : String,
  data : Bytes,
) -> Unit {
  guard self.sessions.get(id) is Some(session) else { raise NotOpen(id) }
  session.pty.write(data) catch {
    error => raise WriteFailed(@debug.render(Repr(error)))
  }
}

///|
/// Propagate a webview-side viewport change to the PTY.
pub fn TerminalState::resize(
  self : TerminalState,
  id~ : String,
  cols~ : Int32,
  rows~ : Int32,
) -> Unit raise {
  guard self.sessions.get(id) is Some(session) else { raise NotOpen(id) }
  session.pty.resize(cols~, rows~) catch {
    error => raise ResizeFailed("\{error}")
  }
}

///|
/// Acknowledge every output chunk through the latest sequence the webview has
/// rendered. A later acknowledgement covers an earlier request that failed to
/// reach the host; duplicates and out-of-order older requests remain no-ops.
pub fn TerminalState::ack(
  self : TerminalState,
  id~ : String,
  sequence~ : Int32,
) -> Unit {
  guard self.sessions.get(id) is Some(session) else { return }
  if session.output.acknowledge_through(sequence) {
    session.cond.signal()
  }
}

///|
/// Request a session's shutdown. Its owning task group cancels the PTY wait and
/// output tasks together; the PTY then closes its controlling handle, allows a
/// bounded graceful exit, and releases its native resources before `Exited`.
/// Unknown ids are a no-op (already exited).
pub fn TerminalState::close(self : TerminalState, id~ : String) -> Unit {
  guard self.sessions.get(id) is Some(session) else { return }
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
pub fn TerminalState::close_all(self : TerminalState) -> Unit {
  // Incrementing before the live-session sweep also covers requests that the
  // pump dequeued but whose PTY spawn has not completed.
  self.connection_generation += 1
  // Materialized: teardown mutates the table as sessions unwind.
  for id in self.sessions.keys().to_array() {
    self.close(id~)
  }
}

///|
/// Permanently stop this connection's terminal subsystem. Pending open calls
/// are rejected before the request queue closes, so neither they nor an idle
/// pump remain parked. Repeated shutdown calls are harmless.
pub fn TerminalState::shutdown(self : TerminalState) -> Unit {
  guard !self.closed else { return }
  self.closed = true
  self.close_all()
  // A request still in this queue has an opener blocked on its private reply.
  // Close that reply explicitly before removing the pump's only route to it.
  while (self.requests.try_get() catch { _ => None }) is Some(request) {
    request.reply.close(error=ServiceClosed, clear=true)
  }
  self.requests.close(error=TerminalPumpClosed, clear=true)
}
