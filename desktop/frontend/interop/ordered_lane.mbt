// A first-come-first-serve lane, used by `bridge_request_in_order` to hold
// back a host call until the previous one on the same channel has answered.

///|
/// One serialized lane: `held` says whether someone is running on it, and
/// `waiters` holds the continuations of the callers queued behind them.
///
/// Each waiter uses a Promise continuation in the async runtime shared by
/// Rabbita effects. Direct hand-off keeps newly arriving callers behind the
/// existing queue while the next Promise continuation is waiting to resume.
priv struct Lane {
  mut held : Bool
  waiters : @deque.Deque[(Unit) -> Unit]
}

///|
fn Lane::Lane() -> Lane {
  { held: false, waiters: Deque([]), }
}

///|
/// Run `op` with the lane held, after everyone already queued for it.
///
/// The lane is a combinator rather than an `acquire`/`release` pair so that
/// no call site can take it without giving it back: the hand-off below is
/// reached on `op`'s error path too.
async fn[T] Lane::run(self : Lane, op : async () -> T) -> T {
  if self.held {
    @base_browser.wait_callback(wake => self.waiters.push_back(wake))
  } else {
    self.held = true
  }
  defer self.hand_off()
  op()
}

///|
/// Give the lane to the longest-waiting caller, or leave it free.
///
/// It is handed over directly rather than freed and re-taken: dropping `held`
/// first would let a caller arriving in the same turn take the lane ahead of
/// one already queued, which is the reordering the lane exists to prevent.
fn Lane::hand_off(self : Lane) -> Unit {
  match self.waiters.pop_front() {
    Some(wake) => wake(())
    None => self.held = false
  }
}
