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

///|
/// Run `op` on `lane` the way a page effect does — detached, and unable to
/// propagate a failure — recording any error so a test asserts on it instead
/// of losing it.
fn lane_task(
  lane : Lane,
  failures : Array[String],
  op : async () -> Unit,
) -> Unit {
  @js.Promise::from_async(() => {
    lane.run(op) catch {
      error => failures.push("\{error}")
    }
  })
  |> ignore
}

///|
async fn drain_lane_tasks() -> Unit {
  // A timer runs after the complete chain of Promise hand-off microtasks.
  @base_browser.wait_callback(resolve => {
    @base_browser.schedule_timeout(() => resolve(()), 0) |> ignore
  })
}

///|
async test "an uncontended lane runs its caller and releases the lane" {
  let lane = Lane::Lane()
  let failures = []
  let ran = []
  lane_task(lane, failures, () => ran.push(true))
  drain_lane_tasks()
  assert_eq(ran, [true])
  assert_eq(failures, ([] : Array[String]))
  assert_false(lane.held)
}

///|
async test "a contended lane serves its callers in arrival order" {
  let lane = Lane::Lane()
  let failures = []
  let entered = []
  // Each caller parks here instead of returning, holding the lane across a
  // suspension point so the ones behind it genuinely queue.
  let parked : Array[(Unit) -> Unit] = []
  for index in 0..<3 {
    lane_task(lane, failures, () => {
      entered.push(index)
      @base_browser.wait_callback(wake => parked.push(wake))
    })
  }
  drain_lane_tasks()
  // Only the first caller has entered; the other callers are queued.
  assert_eq(entered, [0])
  parked[0](())
  drain_lane_tasks()
  assert_eq(entered, [0, 1])
  parked[1](())
  drain_lane_tasks()
  assert_eq(entered, [0, 1, 2])
  parked[2](())
  drain_lane_tasks()
  assert_eq(failures, ([] : Array[String]))
  assert_false(lane.held)
}

///|
async test "a failing caller still hands the lane on" {
  let lane = Lane::Lane()
  let failures = []
  let entered = []
  lane_task(lane, failures, () => raise BridgeError("host refused"))
  lane_task(lane, failures, () => entered.push(true))
  drain_lane_tasks()
  assert_eq(failures, ["host refused"])
  assert_eq(entered, [true])
  assert_false(lane.held)
}

///|
async test "a caller arriving mid-queue waits behind it" {
  let lane = Lane::Lane()
  let failures = []
  let entered = []
  let parked : Array[(Unit) -> Unit] = []
  for index in 0..<2 {
    lane_task(lane, failures, () => {
      entered.push(index)
      @base_browser.wait_callback(wake => parked.push(wake))
    })
  }
  drain_lane_tasks()
  parked[0](())
  drain_lane_tasks()
  // The second caller holds the lane now, so a late arrival still waits.
  assert_true(lane.held)
  let late = []
  lane_task(lane, failures, () => late.push(true))
  drain_lane_tasks()
  assert_eq(late, ([] : Array[Bool]))
  parked[1](())
  drain_lane_tasks()
  assert_eq(late, [true])
  assert_eq(failures, ([] : Array[String]))
  assert_false(lane.held)
}
