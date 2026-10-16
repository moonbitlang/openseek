// Synchronous fan-out into subscriber-owned inboxes. A slow destination is
// paused instead of blocking the publisher or silently continuing after a gap.

///|
struct Channel[T] {
  receivers : Map[Int32, Receiver[T]]
  mut next_id : Int32
}

///|
priv enum Delivery {
  Accepted
  Full
  Closed
}

///|
priv struct Receiver[T] {
  offer : (T) -> Delivery
  on_lag : (Subscription[T]) -> Unit
  mut paused : Bool
}

///|
pub fn[T] Channel::Channel() -> Channel[T] {
  { receivers: Map([]), next_id: 0, }
}

///|
/// Register an inbox for future publications. `map` may omit notifications
/// that this transport does not send. Delivery never suspends.
///
/// A full inbox pauses this subscription and invokes `on_lag` once. Its owner
/// must either close it or resume it at a resync boundary. Publications while
/// paused are omitted; there is no replay. Closing the inbox retires the
/// subscription on its next delivery attempt. Always close the subscription
/// when its owner exits, including on cancellation.
pub fn[T, U] Channel::subscribe(
  self : Channel[T],
  inbox : @async.Queue[U],
  map~ : (T) -> U?,
  on_lag~ : (Subscription[T]) -> Unit,
) -> Subscription[T] {
  self.subscribe_with(
    offer=value => {
      guard map(value) is Some(message) else { return true }
      inbox.try_put(message)
    },
    on_lag~,
  )
}

///|
/// Register a synchronous transport sink; false means full, errors mean closed.
pub fn[T] Channel::subscribe_with(
  self : Channel[T],
  offer~ : (T) -> Bool raise,
  on_lag~ : (Subscription[T]) -> Unit,
) -> Subscription[T] {
  let id = self.next_id
  self.next_id += 1
  self.receivers[id] = {
    offer: value => {
      let accepted = offer(value) catch { _ => return Closed }
      if accepted {
        Accepted
      } else {
        Full
      }
    },
    on_lag,
    paused: false,
  }
  { channel: self, id, }
}

///|
/// Offer the event to each active inbox without waiting. Snapshot identities
/// so an overflow handler can close subscriptions without invalidating this
/// iteration; subscriptions opened by that handler start with the next event.
pub fn[T] Channel::publish(self : Channel[T], value : T) -> Unit {
  for id in self.receivers.keys().to_array() {
    if self.receivers.get(id) is Some(receiver) && !receiver.paused {
      match (receiver.offer)(value) {
        Accepted => ()
        Full => {
          receiver.paused = true
          (receiver.on_lag)({ channel: self, id, })
        }
        Closed => self.receivers.remove(id)
      }
    }
  }
}

///|
/// Ownership of a registered destination. Closing is idempotent; resuming a
/// closed subscription cannot register it again.
struct Subscription[T] {
  channel : Channel[T]
  id : Int32
}

///|
pub fn[T] Subscription::close(self : Subscription[T]) -> Unit {
  self.channel.receivers.remove(self.id)
}

///|
/// Resume future publications. The owner must establish its resync boundary
/// before accepting more events; call this when consuming that boundary,
/// before requesting the replacement snapshot.
pub fn[T] Subscription::resume_delivery(self : Subscription[T]) -> Unit {
  if self.channel.receivers.get(self.id) is Some(receiver) {
    receiver.paused = false
  }
}
