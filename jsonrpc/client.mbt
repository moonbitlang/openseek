// A JSON-RPC 2.0 client over an arbitrary message Transport.
//
// The client runs two standing tasks, spawned once per connection by the
// caller: a reader (`run_message_pump`) that owns `transport.recv` and routes
// each inbound reply to the waiting request's inbox, and a writer (`run_writer`)
// that owns `transport.send`, draining an outbox queue. Every outgoing
// message — a `request`, a `notify`, or the pump's answer to a peer request —
// is enqueued on the outbox, so the reader never blocks on a write (which would
// otherwise deadlock all routing under a backpressured duplex transport) and the
// transport only ever sees one sender.
//
// A `request` allocates a numeric id, registers a one-shot inbox under it,
// enqueues the request, and blocks on that inbox until the reader delivers its
// reply (or the client closes). Because the reader is the only reader, requests
// are fully concurrent and order-independent with no read lock.
//
// Both tasks are REQUIRED: spawn `run_message_pump` and `run_writer` on tasks
// that outlive the requests (e.g. `group.spawn_bg(no_wait=true, ...)`). Closing
// the transport — end of stream, a failed send, or either task being
// cancelled — closes the client, ending both tasks and failing every
// outstanding and future request with `Closed`. This client advertises no
// capabilities; it answers a peer `ping` with an empty result and any other
// peer request with "method not found", and does not otherwise act on
// peer-initiated requests. `request` has no built-in deadline — a caller that
// needs one wraps the call in `@async.with_timeout`.

///|
/// The message transport a `Client` speaks over. It owns framing and delivery,
/// exchanging whole JSON-RPC messages. `recv` yields `None` at end of stream.
/// `send` is called only by the writer task (a single sender). `close` unblocks
/// any in-progress `recv`/`send` and is idempotent.
pub(open) trait Transport {
  /// Send one whole JSON-RPC message to the peer.
  async fn send(Self, Json) -> Unit
  /// Receive the next whole JSON-RPC message, or `None` once the stream ends.
  async fn recv(Self) -> Json?
  /// Close the transport, unblocking any in-progress `recv`/`send` so the
  /// client's reader and writer tasks return. Must be idempotent.
  fn close(Self) -> Unit
}

///|
/// Cap on the outbox so a peer flooding requests (each answered by the reader)
/// cannot grow it without bound while the writer is backpressured. Generous
/// enough that ordinary request/notify traffic never approaches it.
const OutboxCapacity : Int = 1024

///|
/// A JSON-RPC client. Build it with `Client::new`, spawn `run_message_pump` and
/// `run_writer`, then issue `request`/`notify`. Requests may be concurrent;
/// replies are matched by id.
struct Client {
  transport : &Transport
  // One-shot inbox per outstanding request, keyed by its id. The reader delivers
  // each reply's outcome here; the owning request wakes and takes it. Because
  // the reader is the sole reader and MoonBit's async is cooperative, the plain
  // map and counter mutation below never race.
  pending : Map[Int, @async.Queue[Result[Json, ResponseError]]]
  // Outgoing messages awaiting the writer, bounded (see OutboxCapacity) so a
  // flooding peer cannot grow it without bound. request/notify block when it is
  // full (natural backpressure); the reader's peer-request auto-replies are
  // dropped when full (see try_enqueue) so routing never blocks. The writer is
  // the only task that touches the wire.
  outbox : @async.Queue[Json]
  mut next_id : Int
  // Set once the client is closing (EOF, a failed send, or a cancelled task);
  // later requests fail fast with `Closed`, and both tasks return.
  mut closed : Bool
  // Called for each peer-initiated notification, on the reader task. The default
  // drops them; a caller that cares installs its own via
  // `set_notification_handler`. It must not block (it runs on the reader, so
  // blocking stalls routing) and must not abort (an abort is uncatchable and
  // takes down the process — the reader cannot contain it).
  mut on_notification : (String, Json) -> Unit
}

///|
/// Build a client over `transport`. Pure setup — no I/O and no background task.
/// The caller must spawn `run_message_pump` and `run_writer` before issuing
/// requests (see the module comment). Closing the transport makes in-flight and
/// later requests fail with `Closed`.
pub fn[T : Transport] Client::new(transport : T) -> Client {
  {
    transport: transport as &Transport,
    pending: Map([]),
    outbox: Queue(kind=Blocking(OutboxCapacity)),
    next_id: 1,
    closed: false,
    on_notification: (_, _) => (),
  }
}

///|
/// Install the handler run for each peer-initiated notification (`method`,
/// `params`). Replaces any previous handler; it runs on the reader task, so it
/// must not block on I/O.
pub fn Client::set_notification_handler(
  self : Client,
  handler : (String, Json) -> Unit,
) -> Unit {
  self.on_notification = handler
}

///|
/// Whether the client has closed. A closed client never answers again — every
/// later request fails fast with `Closed` — so a pool holding one should discard
/// it and connect afresh.
pub fn Client::is_closed(self : Client) -> Bool {
  self.closed
}

///|
/// Issue a request and await its result. Concurrency-safe and order-independent:
/// many requests may be outstanding at once, and each reply is routed to its
/// request by id by the reader. Requires running `run_message_pump` and
/// `run_writer`. Raises `ResponseError::Failed` on a JSON-RPC error reply, or
/// `ResponseError::Closed` if the client closes before the reply arrives.
pub async fn Client::request(
  self : Client,
  method_~ : String,
  params~ : Json,
) -> Json {
  guard !self.closed else { raise Closed }
  let id = self.next_id
  self.next_id = self.next_id + 1
  let inbox : @async.Queue[Result[Json, ResponseError]] = Queue(kind=Unbounded)
  self.pending.set(id, inbox)
  defer self.pending.remove(id)
  // Register the inbox before enqueuing so a concurrent close still delivers
  // `Closed` here rather than leaving us to block forever.
  self.enqueue(build_request(id, method_, params))
  match inbox.get() {
    Ok(json) => json
    Err(error) => raise error
  }
}

///|
/// Send a notification (no reply expected). Like `request`, it enqueues on the
/// outbox and so may block if the outbox is full (the writer is backpressured).
pub async fn Client::notify(
  self : Client,
  method_~ : String,
  params~ : Json,
) -> Unit {
  guard !self.closed else { return }
  self.enqueue(build_notification(method_, params))
}

///|
/// Enqueue one outgoing request/notification for the writer. Blocks only if the
/// outbox is full (the writer is backpressured); a closed outbox (the client is
/// shutting down) drops the message, since the owning request already fails via
/// its inbox.
async fn Client::enqueue(self : Client, message : Json) -> Unit {
  self.outbox.put(message) catch {
    error if @async.is_being_cancelled() => raise error
    _ => ()
  }
}

///|
/// Enqueue a reader-generated reply (a peer-request answer) without ever
/// blocking the reader: if the outbox is full (a flooding peer) or closed, drop
/// it. This keeps routing live and the outbox bounded.
fn Client::try_enqueue(self : Client, message : Json) -> Unit {
  (self.outbox.try_put(message) catch { _ => false }) |> ignore
}

///|
/// The writer task: the sole caller of `transport.send`, draining the outbox
/// until the client closes. A failed send closes the client (so a request never
/// waits on a reply to a message that could not be sent). Spawn exactly one.
pub async fn Client::run_writer(self : Client) -> Unit {
  while !self.closed {
    let message = self.outbox.get() catch {
      error if @async.is_being_cancelled() => {
        self.close()
        raise error
      }
      // Outbox closed: the client is shutting down.
      _ => break
    }
    self.transport.send(message) catch {
      error if @async.is_being_cancelled() => {
        self.close()
        raise error
      }
      _ => break
    }
  }
  self.close()
}

///|
/// The reader task: owns `transport.recv` and routes each inbound message until
/// the stream ends or the client closes. Spawn exactly one, on a task that
/// outlives the requests. Closes the client on every exit — end of stream, a
/// transport error, or cancellation — so `is_closed` is always truthful and no
/// request is left hanging.
pub async fn Client::run_message_pump(self : Client) -> Unit {
  for ;; {
    if self.closed {
      break
    }
    let ended = self.route_next() catch {
      error => {
        self.close()
        raise error
      }
    }
    if ended {
      break
    }
  }
  self.close()
}

///|
/// Read and route one inbound message (or, for a batch, each element). Returns
/// `true` once the transport has ended. Cancellation propagates.
async fn Client::route_next(self : Client) -> Bool {
  let message = self.transport.recv() catch {
    error if @async.is_being_cancelled() => raise error
    _ => return true
  }
  guard message is Some(message) else { return true }
  // A non-conformant peer may batch replies in a top-level array; route each so
  // the correlated requests are not left hanging.
  match message {
    Array(items) =>
      for item in items {
        self.dispatch(item)
      }
    _ => self.dispatch(message)
  }
  false
}

///|
/// Act on one classified message: deliver a reply to its request, answer a peer
/// request (via the outbox, never inline on the read path), or run the
/// notification handler.
async fn Client::dispatch(self : Client, message : Json) -> Unit {
  match classify_incoming(message) {
    // Deliver to whichever request owns this id, if any (a stale or unknown id
    // is dropped).
    Reply(reply_id, outcome) =>
      if self.pending.get(reply_id) is Some(target) {
        target.put(outcome)
      }
    PeerRequest(peer_id, method_) => {
      let reply = if method_ == "ping" {
        build_success_reply(peer_id, Json::empty_object())
      } else {
        build_error_reply(peer_id)
      }
      // Non-blocking: never let answering a peer stall the read loop or grow the
      // outbox without bound.
      self.try_enqueue(reply)
    }
    Notification(method_, params) => (self.on_notification)(method_, params)
    Unknown => ()
  }
}

///|
/// Mark the client closed, close the transport (unblocking a parked reader/
/// writer) and the outbox, and fail every outstanding request with `Closed`.
/// Idempotent, and never suspends (unbounded `put`, synchronous transport
/// `close`), so it is safe to run during cancellation unwind.
async fn Client::close(self : Client) -> Unit {
  if self.closed {
    return
  }
  self.closed = true
  self.transport.close()
  self.outbox.close()
  for _, inbox in self.pending {
    inbox.put(Err(Closed))
  }
}
