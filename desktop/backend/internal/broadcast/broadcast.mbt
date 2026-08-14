// One bounded log shared by every reader, instead of one queue per reader.
// A publisher appends once and wakes whoever is waiting; a subscription is
// only a cursor into the log, so opening one registers nothing with the
// channel and dropping it is the whole of unsubscribing. Every reader sees
// the same sequence. A reader that falls further behind than the window
// retains has lost the overwritten values for good: its next read raises
// `Lagged` with their count and its cursor moves up to the oldest value still
// retained, as tokio's broadcast channel does. Whether the retained remainder
// is worth reading is the reader's call; `skip_to_head` says it is not.

///|
/// A bounded broadcast log of `T`. `capacity` is how many published values
/// stay readable behind the head; a subscription further behind than that
/// has lagged.
struct Channel[T] {
  capacity : Int
  // The retained window, oldest first: `log[i]` carries sequence `base + i`.
  log : @deque.Deque[T]
  mut base : Int
  // Broadcast on every publish. Readers wait on it only once caught up, and
  // re-check the log after waking, so a wake with nothing new is harmless.
  cond : @cond_var.Cond
}

///|
pub fn[T] Channel::Channel(capacity~ : Int) -> Channel[T] {
  { capacity, log: Deque([], capacity~), base: 0, cond: Cond(), }
}

///|
/// The sequence the next published value will carry.
fn[T] Channel::head(self : Channel[T]) -> Int {
  self.base + self.log.length()
}

///|
/// Append `value` for every subscription and wake the readers waiting for
/// it. Never suspends, so publish order is the order every reader sees. When
/// the window is full the oldest value falls out; a subscription still
/// pointing at it has lagged, and learns so on its next read.
pub fn[T] Channel::publish(self : Channel[T], value : T) -> Unit {
  self.log.push_back(value)
  if self.log.length() > self.capacity {
    ignore(self.log.pop_front())
    self.base += 1
  }
  self.cond.broadcast()
}

///|
/// A subscription positioned at the head: it sees what is published from
/// now on, nothing retained from before. Dropping it is all it takes to
/// unsubscribe.
pub fn[T] Channel::subscribe(self : Channel[T]) -> Subscription[T] {
  { channel: self, cursor: self.head(), }
}

///|
/// One reader's position in a channel's log.
struct Subscription[T] {
  channel : Channel[T]
  mut cursor : Int
}

///|
/// The subscription fell further behind than the channel retains: `missed`
/// values were overwritten before it read them. Reading resumes at the
/// oldest value still retained.
pub suberror Lagged {
  Lagged(missed~ : Int)
} derive(Debug)

///|
pub impl Show for Lagged with fn output(self, logger) {
  match self {
    Lagged(missed~) =>
      logger.write_string(
        "subscription lagged: \{missed} values were overwritten before it read them",
      )
  }
}

///|
/// The next value without waiting: `None` when the subscription is caught up
/// with the head.
pub fn[T] Subscription::try_next(self : Subscription[T]) -> T? raise Lagged {
  let channel = self.channel
  if self.cursor < channel.base {
    let missed = channel.base - self.cursor
    self.cursor = channel.base
    raise Lagged(missed~)
  }
  guard channel.log.get(self.cursor - channel.base) is Some(value) else {
    return None
  }
  self.cursor += 1
  Some(value)
}

///|
/// The next value, waiting for a publish while caught up. Raises `Lagged`
/// when the window rolled past the cursor. Cancellation leaves the cursor
/// where it was: nothing is consumed until a value is returned.
pub async fn[T] Subscription::next(self : Subscription[T]) -> T {
  for ;; {
    if self.try_next() is Some(value) {
      return value
    }
    self.channel.cond.wait()
  }
}

///|
/// Give up whatever the log still retains and continue from the head. For a
/// reader to whom a stream with a hole in it is worth nothing after `Lagged`:
/// it resyncs by other means and wants only what is published from now on.
pub fn[T] Subscription::skip_to_head(self : Subscription[T]) -> Unit {
  self.cursor = self.channel.head()
}

///|
pub extend Lagged with Debug::{to_repr}

///|
pub extend Lagged with Show::{to_string, output}
