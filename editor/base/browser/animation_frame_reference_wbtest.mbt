// Reference coverage for `AnimationFrameQueueItem`,
// `scheduleAtNextAnimationFrame`, and
// `runAtThisOrScheduleAtNextAnimationFrame` in
// `vscode/src/vs/base/browser/dom.ts:396-498`, pinned at
// b18492a288de038fbc7643aae6de8247029d11bd.

///|
priv struct TestAnimationFrameDriver {
  callbacks : Array[() -> Unit]
  mut request_count : Int
  mut frame : Int
}

///|
fn TestAnimationFrameDriver::TestAnimationFrameDriver() -> TestAnimationFrameDriver {
  { callbacks: [], request_count: 0, frame: 0, }
}

///|
fn TestAnimationFrameDriver::coordinator(
  self : TestAnimationFrameDriver,
) -> AnimationFrameCoordinator {
  AnimationFrameCoordinator(callback => {
    self.request_count += 1
    self.callbacks.push(callback)
  })
}

///|
fn TestAnimationFrameDriver::run_next(self : TestAnimationFrameDriver) -> Unit {
  guard !self.callbacks.is_empty() else {
    abort("expected one pending native animation frame")
  }
  let callback = self.callbacks.remove(0)
  self.frame += 1
  callback()
}

///|
test "strict-next coalesces native requests and preserves equal-priority FIFO" {
  let driver = TestAnimationFrameDriver()
  let coordinator = driver.coordinator()
  let events : Array[(Int, String)] = []
  coordinator.schedule_at_next_animation_frame(
    () => events.push((driver.frame, "first")),
    0,
  )
  |> ignore
  coordinator.schedule_at_next_animation_frame(
    () => events.push((driver.frame, "second")),
    0,
  )
  |> ignore
  assert_eq(driver.request_count, 1)
  assert_eq(driver.callbacks.length(), 1)
  driver.run_next()
  assert_true(events == [(1, "first"), (1, "second")])
  assert_eq(driver.callbacks.length(), 0)
}

///|
test "initial and reentrant current queues select descending priority" {
  let driver = TestAnimationFrameDriver()
  let coordinator = driver.coordinator()
  let events : Array[String] = []
  coordinator.schedule_at_next_animation_frame(
    () => {
      events.push("initial-10")
      coordinator.run_at_this_or_schedule_at_next_animation_frame(
        () => events.push("reentrant-100"),
        100,
      )
      |> ignore
      coordinator.run_at_this_or_schedule_at_next_animation_frame(
        () => events.push("reentrant-5"),
        5,
      )
      |> ignore
    },
    10,
  )
  |> ignore
  coordinator.schedule_at_next_animation_frame(
    () => events.push("initial-0"),
    0,
  )
  |> ignore
  driver.run_next()
  assert_true(
    events == ["initial-10", "reentrant-100", "reentrant-5", "initial-0"],
  )
}

///|
test "current-or-next outside a drain waits for the next native frame" {
  let driver = TestAnimationFrameDriver()
  let coordinator = driver.coordinator()
  let mut observed_frame = 0
  coordinator.run_at_this_or_schedule_at_next_animation_frame(
    () => observed_frame = driver.frame,
    0,
  )
  |> ignore
  assert_eq(observed_frame, 0)
  assert_eq(driver.request_count, 1)
  driver.run_next()
  assert_eq(observed_frame, 1)
}

///|
test "strict-next registered during a drain crosses a native-frame boundary" {
  let driver = TestAnimationFrameDriver()
  let coordinator = driver.coordinator()
  let events : Array[(Int, String)] = []
  coordinator.schedule_at_next_animation_frame(
    () => {
      events.push((driver.frame, "current"))
      coordinator.schedule_at_next_animation_frame(
        () => events.push((driver.frame, "strict-next")),
        100,
      )
      |> ignore
      coordinator.run_at_this_or_schedule_at_next_animation_frame(
        () => events.push((driver.frame, "current-append")),
        0,
      )
      |> ignore
    },
    0,
  )
  |> ignore
  driver.run_next()
  assert_true(events == [(1, "current"), (1, "current-append")])
  assert_eq(driver.request_count, 2)
  assert_eq(driver.callbacks.length(), 1)
  driver.run_next()
  assert_true(
    events == [(1, "current"), (1, "current-append"), (2, "strict-next")],
  )
}

///|
test "cancellation before and during a drain is deterministic and idempotent" {
  let driver = TestAnimationFrameDriver()
  let coordinator = driver.coordinator()
  let events : Array[String] = []
  let canceled_before = coordinator.schedule_at_next_animation_frame(
    () => events.push("canceled-before"),
    100,
  )
  let canceled_during = coordinator.schedule_at_next_animation_frame(
    () => events.push("canceled-during"),
    0,
  )
  coordinator.schedule_at_next_animation_frame(
    () => {
      events.push("canceler")
      canceled_during.dispose()
      canceled_during.dispose()
    },
    50,
  )
  |> ignore
  canceled_before.dispose()
  canceled_before.dispose()
  driver.run_next()
  assert_true(events == ["canceler"])

  let all_canceled = coordinator.schedule_at_next_animation_frame(
    () => events.push("all-canceled"),
    0,
  )
  all_canceled.dispose()
  // Monaco retains the one already-requested native frame. New canceled work
  // joins it without requesting a duplicate.
  assert_eq(driver.request_count, 2)
  driver.run_next()
  assert_true(events == ["canceler"])
  assert_eq(driver.callbacks.length(), 0)
}

///|
test "nested current and next consumers lose no callback and restart after idle" {
  let driver = TestAnimationFrameDriver()
  let coordinator = driver.coordinator()
  let events : Array[(Int, String)] = []
  coordinator.schedule_at_next_animation_frame(
    () => {
      events.push((driver.frame, "consumer-a"))
      coordinator.run_at_this_or_schedule_at_next_animation_frame(
        () => {
          events.push((driver.frame, "consumer-a-current"))
          coordinator.schedule_at_next_animation_frame(
            () => events.push((driver.frame, "consumer-a-next")),
            0,
          )
          |> ignore
        },
        0,
      )
      |> ignore
    },
    0,
  )
  |> ignore
  coordinator.schedule_at_next_animation_frame(
    () => events.push((driver.frame, "consumer-b")),
    0,
  )
  |> ignore
  assert_eq(driver.request_count, 1)
  driver.run_next()
  assert_true(
    events == [(1, "consumer-a"), (1, "consumer-b"), (1, "consumer-a-current")],
  )
  driver.run_next()
  assert_true(events.last() == Some((2, "consumer-a-next")))
  assert_eq(driver.callbacks.length(), 0)

  coordinator.schedule_at_next_animation_frame(
    () => events.push((driver.frame, "after-idle")),
    0,
  )
  |> ignore
  assert_eq(driver.request_count, 3)
  driver.run_next()
  assert_true(events.last() == Some((3, "after-idle")))
}
