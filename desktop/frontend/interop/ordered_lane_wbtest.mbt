///|
async fn drain_lane_tasks() -> Unit {
  // A timer runs after the complete chain of Promise hand-off microtasks.
  @base_browser.wait_callback(resolve => {
    @base_browser.schedule_timeout(() => resolve(()), 0) |> ignore
  })
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
async test "an ordered request failure releases its channel lane" {
  // No bridge is injected under test, so both calls fail at the same point.
  // The second one only reaches it if the first released the lane on its way
  // out; before, a lane still held would have parked it forever.
  let failures = []
  for _ in 0..<2 {
    @js.Promise::from_async(() => {
      ignore(
        bridge_request_in_order(
          Local,
          @commands.fs_unwatch,
          @protocol.EmptyPayload::NoPayload,
        ),
      ) catch {
        _ => {
          failures.push(true)
          return
        }
      }
      failures.push(false)
    })
    |> ignore
  }
  drain_lane_tasks()
  assert_eq(failures, [true, true])
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
