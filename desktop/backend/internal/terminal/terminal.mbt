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
  write_guard : @async.Mutex
  mut last_owner_key : Int64
  output : TerminalOutputWindow
  retained : @deque.Deque[(Int32, Bytes)]
  cond : @cond_var.Cond
  close_requested : @async.Queue[Unit]
  mut closing : Bool
  mut owner : TerminalClient?
  mut detached_at : Int64?
  mut exited : (Int32, Int64)?
}

///|
priv struct TerminalDelivery {
  session : TerminalSession
  mut sent : Int32
  mut exit_sent : Bool
}

///|
/// A transport's attachment to host-owned terminals. Its teardown detaches
/// shells; it never owns the tasks running those shells.
struct TerminalClient {
  key : Int64
  sessions : Map[String, TerminalDelivery]
  changed : @cond_var.Cond
  mut closed : Bool
  mut generation : Int32
}

///|
let next_client_key : Ref[Int64] = Ref(0)

///|
pub fn TerminalClient::TerminalClient() -> TerminalClient {
  next_client_key.val += 1
  {
    key: next_client_key.val,
    sessions: Map([]),
    changed: Cond(),
    closed: false,
    generation: 0,
  }
}

///|
priv struct OpenRequest {
  id : String
  client : TerminalClient
  generation : Int32
  argv : Array[String]
  cwd : String
  cols : Int32
  rows : Int32
  reply : @async.Queue[Result[Unit, String]]
}

///|
/// Host-lifetime owner. Terminal ids are unguessable capabilities, returned
/// only on an authenticated command channel; ordinary operations still require
/// an attachment on that channel. A new channel must explicitly attach.
struct TerminalState {
  requests : @async.Queue[OpenRequest]
  sessions : Map[String, TerminalSession]
  grace_ms : Int32
  mut closed : Bool
  mut opening : Int32
}

///|
pub fn new_terminal_state(grace_ms~ : Int32 = 300_000) -> TerminalState {
  {
    requests: Queue(kind=Blocking(16)),
    sessions: Map([]),
    grace_ms: grace_ms.max(1),
    closed: false,
    opening: 0,
  }
}

///|
pub async fn open_terminal(
  state : TerminalState,
  client : TerminalClient,
  cwd~ : String,
  cols~ : Int32,
  rows~ : Int32,
  command? : Array[String],
) -> String {
  guard !state.closed && !client.closed else {
    raise TerminalError("terminal service is closed")
  }
  let argv = session_argv(command?)
  let id = @uuid.mint()
  let reply : @async.Queue[Result[Unit, String]] = Queue(kind=Blocking(1))
  state.requests.put({
    id,
    client,
    generation: client.generation,
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
fn TerminalClient::session(
  self : TerminalClient,
  id : String,
) -> TerminalSession raise TerminalError {
  guard !self.closed &&
    self.sessions.get(id) is Some(delivery) &&
    delivery.session.owner is Some(owner) &&
    owner.key == self.key else {
    raise TerminalError("terminal is not attached to this connection")
  }
  delivery.session
}

///|
/// Reattach a surviving PTY, retaining the frontend's existing emulator.
/// `sequence` is the last chunk already accepted by that emulator. A missing
/// session (expiry or host restart) is distinct from an invalid cursor/owner.
pub fn attach_terminal(
  state : TerminalState,
  client : TerminalClient,
  id~ : String,
  sequence~ : Int32,
) -> Bool raise TerminalError {
  guard !state.closed && !client.closed else {
    raise TerminalError("terminal service is closed")
  }
  guard state.sessions.get(id) is Some(session) && !session.closing else {
    return false
  }
  if client.key < session.last_owner_key {
    raise TerminalError("a newer connection already owns this terminal")
  }
  let first = session.output.next_sequence - session.retained.length()
  guard sequence >= first - 1 && sequence < session.output.next_sequence else {
    raise TerminalError("terminal output cursor is outside the retained window")
  }
  if client.sessions.length() >= 32 && !client.sessions.contains(id) {
    raise TerminalError("too many attached terminals")
  }
  // A half-open socket may not have noticed network loss yet. A newer
  // authenticated connection holding the capability can take over; stale
  // requests from the old connection cannot move the session back.
  if session.owner is Some(owner) && owner.key != client.key {
    owner.sessions.remove(id)
    owner.changed.broadcast()
  }
  session.last_owner_key = client.key
  session.owner = Some(client)
  session.detached_at = None
  client.sessions[id] = { session, sent: sequence, exit_sent: false, }
  ack_terminal(client, id~, sequence~)
  client.changed.broadcast()
  true
}

///|
pub async fn write_terminal(
  client : TerminalClient,
  id~ : String,
  data : Bytes,
) -> Unit {
  let session = client.session(id)
  session.write_guard.acquire()
  defer session.write_guard.release()
  // Ownership can change while waiting for a write from the old connection.
  ignore(client.session(id))
  guard !session.closing && session.exited is None else {
    raise TerminalError("terminal has exited")
  }
  session.pty.write(data) catch {
    error => raise TerminalError(@debug.render(Repr(error)))
  }
}

///|
pub fn resize_terminal(
  client : TerminalClient,
  id~ : String,
  cols~ : Int32,
  rows~ : Int32,
) -> Unit raise {
  let session = client.session(id)
  session.pty.resize(cols~, rows~) catch {
    error => raise TerminalError("terminal resize failed: \{error}")
  }
}

///|
pub fn ack_terminal(
  client : TerminalClient,
  id~ : String,
  sequence~ : Int32,
) -> Unit {
  let session = client.session(id) catch { _ => return }
  if sequence >= session.output.next_sequence {
    return
  }
  ignore(session.output.acknowledge_through(sequence))
  while session.retained.front() is Some((seq, _)) && seq <= sequence {
    ignore(session.retained.pop_front())
  }
  session.cond.broadcast()
}

///|
fn TerminalSession::close(self : TerminalSession) -> Unit {
  if !self.closing {
    self.closing = true
    self.cond.broadcast()
    ignore(self.close_requested.try_put(()) catch { _ => false })
  }
}

///|
pub fn close_terminal(client : TerminalClient, id~ : String) -> Unit {
  let session = client.session(id) catch { _ => return }
  session.close()
  if session.exited is Some(_) {
    client.sessions.remove(id)
  }
}

///|
/// Explicit page replacement closes that page's terminals. Network loss uses
/// detach instead. Invalidate queued spawns as well as materialized sessions.
pub fn close_all_terminals(client : TerminalClient) -> Unit {
  client.generation += 1
  for delivery in client.sessions.values().to_array() {
    delivery.session.close()
  }
}

///|
pub fn TerminalClient::detach(self : TerminalClient) -> Unit {
  if self.closed {
    return
  }
  self.closed = true
  self.generation += 1
  for delivery in self.sessions.values() {
    let session = delivery.session
    if session.owner is Some(owner) && owner.key == self.key {
      session.owner = None
      session.detached_at = Some(@async.now())
    }
  }
  self.sessions.clear()
  self.changed.broadcast()
}

///|
/// Forward retained output in sequence order. Only this connection task may
/// suspend on the transport; a lost/slow socket cannot cancel a PTY reader.
pub async fn TerminalClient::run(
  self : TerminalClient,
  emit : async (TerminalPush) -> Unit,
) -> Unit {
  defer self.detach()
  while !self.closed {
    let mut progressed = false
    for (id, delivery) in self.sessions.to_array() {
      let session = delivery.session
      guard session.owner is Some(owner) && owner.key == self.key else {
        continue
      }
      if session.retained.iter().find_first(chunk => chunk.0 > delivery.sent)
        is Some((sequence, data)) {
        delivery.sent = sequence
        emit(Output(id~, sequence~, data~))
        // A transport emitter may only enqueue, without suspending. Let its
        // writer drain between replay records instead of overflowing a healthy
        // socket's bounded queue in one uninterrupted replay loop.
        @async.pause()
        progressed = true
      } else if !delivery.exit_sent && session.exited is Some((code, _)) {
        delivery.exit_sent = true
        emit(Exited(id~, code~))
        @async.pause()
        progressed = true
      }
    }
    if !progressed && !self.closed {
      self.changed.wait()
    }
  }
}

///|
pub fn TerminalState::shutdown(self : TerminalState) -> Unit {
  guard !self.closed else { return }
  self.closed = true
  for session in self.sessions.values() {
    session.close()
    if session.owner is Some(owner) {
      owner.detach()
    }
  }
  while (self.requests.try_get() catch { _ => None }) is Some(request) {
    request.reply.close(
      error=TerminalError("terminal service is closed"),
      clear=true,
    )
  }
  self.requests.close(error=TerminalPumpClosed, clear=true)
}
