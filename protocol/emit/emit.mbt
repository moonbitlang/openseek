///|
/// The stdout sink: the queue every emitted line waits in for the drain, or
/// `None` while no run is streaming, in which case `emit` drops the event.
///
/// Dropping is the default so that a process which never drains — a CLI
/// command whose stdout is a report or human text, a test binary, anything
/// that links the agent without owning fd 1 — cannot accumulate lines forever
/// in a queue nobody reads. `open` installs the queue, and only a caller that
/// is about to spawn `drain_stdout` (or read `poll_line`) does that.
///
/// The queue exists because `emit` is synchronous (agent internals call it)
/// while `@stdio.stdout` writes are asynchronous: one drain task owns every
/// write to fd 1, so lines reach stdout whole and in order. It is unbounded,
/// so `try_put` never fails for lack of room.
let sink : Ref[@async.Queue[String]?] = Ref(None)

///|
/// Start accepting events: install a fresh queue for `drain_stdout` (or
/// `poll_line`) to read. Synchronous, so a caller opens the sink *before*
/// spawning the drain — `spawn_bg` leaves it undefined whether the child runs
/// before it returns, and an event reported in that window must not be lost.
/// A second `open` while the sink is open keeps the queue a running drain
/// holds; after `close`, `open` installs a new one.
pub fn open() -> Unit {
  if sink.val is None {
    sink.val = Some(Queue(kind=Unbounded))
  }
}

///|
/// Report `event`: serialize its line and hand it to the open sink, or drop it
/// when no sink is open.
///
/// This is the protocol writer, not a logger. Nothing here filters by a
/// severity or an environment variable (`MOON_XLOG` cannot silence an event),
/// stamps a timestamp, labels a severity, or records a call site — the line is
/// exactly the event's own fields. Nothing that is a log belongs on this
/// stream, and the CLI links no logger.
///
/// The line is `Event::to_json` — the one encoder — so the engine and the
/// desktop host, which forwards a synthesized event of its own, cannot spell
/// the same event two ways. They did once.
pub fn emit(event : @protocol.Event) -> Unit {
  guard sink.val is Some(queue) else { return }
  // `try_put` raises only on a closed queue, and `close` uninstalls the queue
  // before closing it, so the sink never holds one; the catch satisfies the
  // signature.
  ignore(queue.try_put(event.to_json().stringify()) catch { _ => false })
}

///|
/// Write the open sink's lines to stdout until it is closed and drained.
///
/// The task captures the queue at entry, so the `close` that uninstalls it
/// does not end the drain early: `Queue::get` keeps returning buffered lines
/// after `close` and only raises once the queue is closed *and* empty, so
/// closing never loses an event enqueued before it. A stdout-streaming CLI
/// opens the sink, spawns this task once per run, and closes the sink as its
/// last act; the task owns fd 1 for that run. With no sink open there is
/// nothing to drain and the task returns at once.
pub async fn drain_stdout() -> Unit {
  guard sink.val is Some(queue) else { return }
  for ;; {
    let line = queue.get() catch {
      error if @async.is_cancellation_error(error) => raise error
      // The queue is closed and empty: every queued line has been written.
      // This must not test `is_being_cancelled`: when the run body fails, the
      // `defer` close and the group's cancellation race, and re-raising the
      // close error here would replace the run's real failure with
      // `QueueAlreadyClosed` in the report the user sees.
      _ => return
    }
    @stdio.stdout.write("\{line}\n")
  }
}

///|
/// Stop accepting events: uninstall the queue, then close it so a running
/// drain writes what was enqueued and finishes. An `emit` after `close` is
/// dropped, which matches the process being on its way out. Closing a sink
/// that is not open does nothing.
pub fn close() -> Unit {
  guard sink.val is Some(queue) else { return }
  sink.val = None
  queue.close()
}

///|
/// Return the next pending line without waiting; `None` when nothing is queued
/// or no sink is open.
///
/// This is the read side for an in-process consumer that does not own fd 1:
/// a test that runs the engine in-process and inspects what a turn emitted,
/// and this package's own tests, which pin the bytes `emit` writes. The CLI
/// uses `drain_stdout` instead. Reading here and draining stdout are mutually
/// exclusive ways to consume the stream, so a process uses only one.
pub fn poll_line() -> String? {
  guard sink.val is Some(queue) else { return None }
  // `try_get` raises only on a closed, empty queue, which the sink never
  // holds; the catch satisfies the signature.
  queue.try_get() catch {
    _ => None
  }
}
