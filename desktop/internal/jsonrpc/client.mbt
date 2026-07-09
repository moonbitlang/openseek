// A JSON-RPC 2.0 client over an arbitrary message Transport.
//
// It owns the generic plumbing — id allocation, correlating replies back to
// their requests (so replies may arrive out of order, as JSON-RPC allows),
// answering peer-initiated requests, and notifications — but knows nothing
// about framing or bytes: a `Transport` exchanges whole JSON messages.
//
// There is no background reader. Reading is pull-based and shared: a request
// registers a one-shot inbox keyed by its id, then takes turns (under a single
// read lock) reading one message at a time and *delivering it to the inbox of
// whichever id it belongs to* — its own or another's. A request returns as soon
// as its inbox has an outcome, so replies can come back in any order and many
// requests can be outstanding at once: a request still waiting just blocks on
// its inbox until some other reader delivers to it.

///|
/// The message transport a `Client` speaks over. It owns framing and delivery,
/// exchanging whole JSON-RPC messages. `recv` yields `None` at end of stream.
/// `send` must be safe under concurrent calls (a reader answering a peer request
/// can race application `request`/`notify` calls).
pub(open) trait Transport {
  async fn send(Self, Json) -> Unit
  async fn recv(Self) -> Json?
}

///|
/// A JSON-RPC client. Build it with `Client::new`, then issue `request`/
/// `notify`. Requests may be concurrent; replies are matched by id.
struct Client {
  transport : &Transport
  // One-shot inbox per outstanding request, keyed by its id. Whoever is reading
  // delivers each reply's outcome here; the owning request wakes and takes it.
  // Holding out-of-order replies for other requests is just delivery to their
  // inboxes.
  pending : Map[Int, @async.Queue[Result[Json, ResponseError]]]
  // Held by the one request currently reading the transport, so readers take
  // strict turns — one message per turn — and never race on `recv`.
  read_lock : @semaphore.Semaphore
  mut next_id : Int
  // Set once the transport ends; later requests fail fast with `Closed`.
  mut closed : Bool
  // Called for each peer-initiated notification, on whichever task reads it.
  // The default drops them (JSON-RPC lets a client ignore notifications); a
  // caller that cares — an LSP session watching `publishDiagnostics` — installs
  // its own via `set_notification_handler`.
  mut on_notification : (String, Json) -> Unit
}

///|
/// Build a client over `transport`. Pure setup — no I/O and no background task;
/// reading happens inside `request` calls. Closing the transport makes in-flight
/// and later requests fail with `Closed`.
pub fn[T : Transport] Client::new(transport : T) -> Client {
  {
    transport: transport as &Transport,
    pending: {},
    read_lock: Semaphore(1, initial_value=1),
    next_id: 1,
    closed: false,
    on_notification: (_, _) => (),
  }
}

///|
/// Install the handler run for each peer-initiated notification (`method`,
/// `params`). Replaces any previous handler; the handler runs on whichever task
/// reads the message (a `request` caller or the standing `run_message_pump`),
/// under the read lock, so it must not itself block on I/O.
pub fn Client::set_notification_handler(
  self : Client,
  handler : (String, Json) -> Unit,
) -> Unit {
  self.on_notification = handler
}

///|
/// Whether the transport has ended. A closed client never answers again —
/// every later request fails fast with `Closed` — so a pool holding one
/// should discard it and connect afresh.
pub fn Client::is_closed(self : Client) -> Bool {
  self.closed
}

///|
/// Issue a request and await its result. Concurrency-safe and order-independent:
/// many requests may be outstanding at once, and each reply is routed to its
/// request by id. Raises `ResponseError::Failed` on a JSON-RPC error reply, or
/// `ResponseError::Closed` if the transport ends before the reply arrives.
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
  send_message(self, build_request(id, method_, params))
  for ;; {
    match self.take_or_pump(inbox) {
      Some(Ok(json)) => return json
      Some(Err(error)) => raise error
      None => continue
    }
  }
}

///|
/// Send a notification (no reply expected).
pub async fn Client::notify(
  self : Client,
  method_~ : String,
  params~ : Json,
) -> Unit {
  guard !self.closed else { return }
  send_message(self, build_notification(method_, params))
}

///|
/// One step of waiting for a reply: return this caller's delivered outcome if
/// one is ready (or the stream has closed), otherwise take the read turn, read
/// and route a single message, and return `None` to keep waiting. Serialized
/// through `read_lock` so only one caller reads the transport at a time.
async fn Client::take_or_pump(
  self : Client,
  inbox : @async.Queue[Result[Json, ResponseError]],
) -> Result[Json, ResponseError]? {
  // Fast path: our reply may already be sitting in the inbox, delivered by the
  // standing pump or another request's read turn. Take it *without* contending
  // for the read lock — the pump can be parked in `recv` holding the lock with
  // no next message coming, so waiting for the lock here would block on an
  // answer we already have.
  if (inbox.try_get() catch { _ => None }) is Some(outcome) {
    return Some(outcome)
  }
  self.read_lock.acquire()
  defer self.read_lock.release()
  // Re-check: it may have been delivered while we waited for the read turn.
  if (inbox.try_get() catch { _ => None }) is Some(outcome) {
    return Some(outcome)
  }
  if self.route_next() {
    return Some(Err(Closed))
  }
  None
}

///|
/// A standing reader that routes inbound messages until the transport ends.
/// Spawned per server so peer notifications (LSP `publishDiagnostics`) are read
/// as they arrive, not only while some request happens to be in flight. It
/// shares the read lock and routing with `request`, so a reply is delivered to
/// its owning request's inbox whichever reader reads it first. Returns when the
/// stream closes; cancellation propagates.
pub async fn Client::run_message_pump(self : Client) -> Unit {
  for ;; {
    guard !self.closed else { return }
    self.read_lock.acquire()
    let closed = self.route_next() catch {
      error => {
        self.read_lock.release()
        raise error
      }
    }
    self.read_lock.release()
    if closed {
      return
    }
  }
}

///|
/// Read and route one inbound message; the caller must hold `read_lock`. Returns
/// `true` once the transport has ended (the client is now closed and every
/// outstanding request has been failed with `Closed`). Cancellation propagates.
async fn Client::route_next(self : Client) -> Bool {
  let message = self.transport.recv() catch {
    error if @async.is_being_cancelled() => raise error
    _ => {
      self.close() |> ignore
      return true
    }
  }
  guard message is Some(message) else {
    self.close() |> ignore
    return true
  }
  match classify_incoming(message) {
    // Deliver to whichever request owns this id — possibly us, possibly another
    // (an out-of-order reply); it'll pick it up on its next turn.
    Reply(reply_id, outcome) =>
      if self.pending.get(reply_id) is Some(target) {
        target.put(outcome)
      }
    PeerRequest(peer_id) => send_message(self, build_error_reply(peer_id))
    Notification(method_, params) => (self.on_notification)(method_, params)
    Unknown => ()
  }
  false
}

///|
/// Mark the client closed and fail every outstanding request with `Closed`.
/// Returns `Closed` for the caller that observed end of stream.
async fn Client::close(self : Client) -> Result[Json, ResponseError] {
  self.closed = true
  for _, inbox in self.pending {
    inbox.put(Err(Closed))
  }
  Err(Closed)
}

///|
/// Send one message, swallowing a non-cancellation failure (a dead transport
/// surfaces to callers as the next read failing their requests with `Closed`).
async fn send_message(client : Client, message : Json) -> Unit {
  client.transport.send(message) catch {
    error if @async.is_being_cancelled() => raise error
    _ => ()
  }
}
