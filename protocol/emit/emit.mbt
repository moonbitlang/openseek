///|
/// The stdout sink: the queue every emitted event waits in for the drain, or
/// `None` while no run is streaming, in which case `emit` drops the event.
///
/// Dropping is the default so that a process which never drains — a CLI
/// command whose stdout is a report, a test binary, anything that links the
/// agent without owning fd 1 — cannot accumulate events forever in a queue
/// nobody reads. `open` installs the queue, and only a caller that is about to
/// spawn a drain (or read `poll_line`) does that.
///
/// The queue exists because `emit` is synchronous (agent internals call it)
/// while `@stdio.stdout` writes are asynchronous: one drain task owns every
/// write to fd 1, so output reaches stdout whole and in order. It holds typed
/// events, not serialized lines, so the drain chooses the rendering:
/// `drain_stdout` writes the JSONL wire, while `drain` hands each event to a
/// caller that renders it for a person. It is unbounded, so `try_put` never
/// fails for lack of room.
priv struct PendingEvent {
  event : @protocol.Event?
  usage_record : Json?
}

///|
let sink : Ref[@async.Queue[PendingEvent]?] = Ref(None)

///|
/// Start accepting events: install a fresh queue for a drain (or `poll_line`)
/// to read. Synchronous, so a caller opens the sink *before*
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
/// Report `event`: hand it to the open sink, or drop it when no sink is open.
///
/// This is the protocol writer, not a logger. Nothing here filters by a
/// severity or an environment variable (`MOON_XLOG` cannot silence an event),
/// stamps a timestamp, labels a severity, or records a call site — the line is
/// the event fields plus optional model-usage metadata. Nothing that is a log
/// belongs on this stream, and the CLI links no logger.
///
/// The wire line is `Event::to_json` — the one encoder — so the engine and the
/// desktop host, which forwards a synthesized event of its own, cannot spell
/// the same event two ways. They did once.
pub fn emit(event : @protocol.Event) -> Unit {
  guard sink.val is Some(queue) else { return }
  // `try_put` raises only on a closed queue, and `close` uninstalls the queue
  // before closing it, so the sink never holds one; the catch satisfies the
  // signature.
  ignore(
    queue.try_put({ event: Some(event), usage_record: None, }) catch {
      _ => false
    },
  )
}

///|
/// Hand the open sink's events to `write`, in order, until the sink is closed
/// and drained.
///
/// The task captures the queue at entry, so the `close` that uninstalls it
/// does not end the drain early: `Queue::get` keeps returning buffered events
/// after `close` and only raises once the queue is closed *and* empty, so
/// closing never loses an event enqueued before it. A streaming CLI opens the
/// sink, spawns one drain per run, and closes the sink as its last act; the
/// drain owns fd 1 for that run. With no sink open there is nothing to drain
/// and the task returns at once.
pub async fn drain(write : async (@protocol.Event) -> Unit) -> Unit {
  drain_pending(pending => if pending.event is Some(event) { write(event) })
}

///|
async fn drain_pending(write : async (PendingEvent) -> Unit) -> Unit {
  guard sink.val is Some(queue) else { return }
  for ;; {
    let event = queue.get() catch {
      // The queue is closed and empty: every queued event has been written.
      // Cancellation bypasses catch; only the closed queue ends the drain.
      _ => return
    }
    write(event)
  }
}

///|
/// Write the open sink's events to stdout as the JSONL wire, one
/// `Event::to_json` line each. See `drain` for the lifecycle.
pub async fn drain_stdout() -> Unit {
  drain_json(event => @stdio.stdout.write("\{event.stringify()}\n"))
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
/// Return the next pending event's wire line without waiting; `None` when
/// nothing is queued or no sink is open.
///
/// This is the read side for an in-process consumer that does not own fd 1:
/// a test that runs the engine in-process and inspects what a turn emitted,
/// and this package's own tests, which pin the bytes `drain_stdout` writes.
/// The CLI drains instead. Reading here and draining are mutually exclusive
/// ways to consume the stream, so a process uses only one.
pub fn poll_line() -> String? {
  guard sink.val is Some(queue) else { return None }
  // `try_get` raises only on a closed, empty queue, which the sink never
  // holds; the catch satisfies the signature.
  let event = queue.try_get() catch { _ => return None }
  event.map(event => event.to_json().stringify())
}

///|
/// Read the complete wire stream, including attempt metadata. The legacy typed
/// drain retains its Event contract and ignores metadata-only notifications.
pub async fn drain_json(write : async (Json) -> Unit) -> Unit {
  drain_pending(pending => write(pending.to_json()))
}

///|
/// Enrich a legacy usage event with an optional attempt record, or publish a
/// metadata-only attempt when there is no ordinary successful response.
/// Numeric Usage and Event constructors remain unchanged for existing callers.
pub fn emit_usage(record : Json, usage? : @protocol.Usage) -> Unit {
  guard sink.val is Some(queue) else { return }
  let event = usage.map(usage => @protocol.Event::Usage(usage~))
  ignore(
    queue.try_put({ event, usage_record: Some(record), }) catch {
      _ => false
    },
  )
}

///|
fn PendingEvent::to_json(self : PendingEvent) -> Json {
  let json = match self.event {
    Some(event) => event.to_json()
    None => ({ "event": "model_usage" } : Json)
  }
  if self.usage_record is Some(record) && json is Object(fields) {
    fields["usage_record"] = record
  }
  json
}
