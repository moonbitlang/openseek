///|
test "publish delivers directly to every inbox in order" {
  let channel : @broadcast.Channel[Int32] = Channel()
  let first : @async.Queue[Int32] = Queue(kind=Blocking(4))
  let second : @async.Queue[String] = Queue(kind=Blocking(4))
  let a = channel.subscribe(first, map=value => Some(value), on_lag=sub => {
    sub.close()
  })
  defer a.close()
  let b = channel.subscribe(second, map=value => Some("event:\{value}"), on_lag=sub => {
    sub.close()
  })
  defer b.close()
  channel.publish(1)
  channel.publish(2)
  // No task has run between publishing and receiving.
  assert_eq(first.try_get(), Some(1))
  assert_eq(first.try_get(), Some(2))
  assert_eq(second.try_get(), Some("event:1"))
  assert_eq(second.try_get(), Some("event:2"))
  assert_eq(first.try_get(), None)
  assert_eq(second.try_get(), None)
}

///|
test "new subscriptions receive future events and may filter their profile" {
  let channel : @broadcast.Channel[Int32] = Channel()
  let inbox : @async.Queue[Int32] = Queue(kind=Blocking(1))
  channel.publish(1)
  let mut lagged = false
  let subscription = channel.subscribe(
    inbox,
    map=value => if value % 2 == 0 { Some(value) } else { None },
    on_lag=_ => lagged = true,
  )
  defer subscription.close()
  assert_eq(inbox.try_get(), None)
  channel.publish(2)
  // A filtered event cannot overflow an otherwise full destination.
  channel.publish(3)
  assert_false(lagged)
  assert_eq(inbox.try_get(), Some(2))
  assert_eq(inbox.try_get(), None)
}

///|
test "a full inbox pauses once without blocking healthy subscribers" {
  let channel : @broadcast.Channel[Int32] = Channel()
  let slow : @async.Queue[Int32] = Queue(kind=Blocking(1))
  let fast : @async.Queue[Int32] = Queue(kind=Blocking(1))
  let mut overflows = 0
  let a = channel.subscribe(slow, map=value => Some(value), on_lag=_ => {
    overflows += 1
  })
  defer a.close()
  let b = channel.subscribe(fast, map=value => Some(value), on_lag=sub => {
    sub.close()
  })
  defer b.close()
  for value in 1..<=5 {
    channel.publish(value)
    assert_eq(fast.try_get(), Some(value))
  }
  assert_eq(overflows, 1)
  assert_eq(slow.try_get(), Some(1))
  // Free space alone does not allow notifications to cross the stream gap.
  channel.publish(6)
  assert_eq(slow.try_get(), None)
  assert_eq(fast.try_get(), Some(6))
  a.resume_delivery()
  channel.publish(7)
  assert_eq(slow.try_get(), Some(7))
  assert_eq(fast.try_get(), Some(7))
}

///|
test "closed subscriptions and inboxes stop receiving publications" {
  let channel : @broadcast.Channel[Int32] = Channel()
  let inbox : @async.Queue[Int32] = Queue(kind=Blocking(1))
  let mut offers = 0
  let subscription = channel.subscribe(
    inbox,
    map=value => {
      offers += 1
      Some(value)
    },
    on_lag=sub => sub.close(),
  )
  subscription.close()
  subscription.close()
  subscription.resume_delivery()
  channel.publish(1)
  assert_eq(offers, 0)
  assert_eq(inbox.try_get(), None)
  let closed = channel.subscribe(
    inbox,
    map=value => {
      offers += 1
      Some(value)
    },
    on_lag=sub => sub.close(),
  )
  defer closed.close()
  inbox.close()
  channel.publish(2)
  channel.publish(3)
  assert_eq(offers, 1)
}

///|
test "an overflow handler can unregister without skipping another inbox" {
  let channel : @broadcast.Channel[Int32] = Channel()
  let slow : @async.Queue[Int32] = Queue(kind=Blocking(0))
  let fast : @async.Queue[Int32] = Queue(kind=Blocking(2))
  let a = channel.subscribe(slow, map=value => Some(value), on_lag=sub => {
    sub.close()
  })
  defer a.close()
  let b = channel.subscribe(fast, map=value => Some(value), on_lag=sub => {
    sub.close()
  })
  defer b.close()
  channel.publish(1)
  channel.publish(2)
  assert_eq(fast.try_get(), Some(1))
  assert_eq(fast.try_get(), Some(2))
}

///|
async test "a shared inbox retains simultaneous local and hub events" {
  let channel : @broadcast.Channel[String] = Channel()
  let inbox : @async.Queue[String] = Queue(kind=Blocking(8))
  let subscription = channel.subscribe(inbox, map=value => Some(value), on_lag=sub => {
    sub.close()
  })
  defer subscription.close()
  @async.with_timeout(1000, () => {
    // Both ready before the consumer runs.
    channel.publish("agent.finished:1")
    inbox.put("browser.event:1")
    assert_eq(inbox.get(), "agent.finished:1")
    assert_eq(inbox.get(), "browser.event:1")
    // Both published while the consumer is waiting.
    @async.with_task_group(group => {
      let reader = group.spawn(() => [inbox.get(), inbox.get()])
      @async.pause()
      channel.publish("agent.finished:2")
      inbox.put("browser.event:2")
      assert_eq(reader.wait(), ["agent.finished:2", "browser.event:2"])
    })
  })
}

///|
async test "a full inbox retains its prefix and one recovery boundary" {
  let channel : @broadcast.Channel[String] = Channel()
  let inbox : @async.Queue[String] = Queue(kind=Blocking(1))
  @async.with_timeout(1000, () => {
    @async.with_task_group(group => {
      let subscription = channel.subscribe(inbox, map=value => Some(value), on_lag=_ => {
        group.spawn_bg(() => inbox.put("resync"))
      })
      defer subscription.close()
      inbox.put("local.control")
      channel.publish("missed:1")
      channel.publish("missed:2")
      assert_eq(inbox.get(), "local.control")
      assert_eq(inbox.get(), "resync")
      subscription.resume_delivery()
      channel.publish("after-resync")
      assert_eq(inbox.get(), "after-resync")
      assert_eq(inbox.try_get(), None)
    })
  })
}

///|
async test "cancelling an owner unregisters its inbox" {
  let channel : @broadcast.Channel[Int32] = Channel()
  let inbox : @async.Queue[Int32] = Queue(kind=Blocking(1))
  let ready : @async.Queue[Unit] = Queue(kind=Blocking(1))
  let blocked : @async.Queue[Unit] = Queue(kind=Blocking(1))
  @async.with_timeout(1000, () => {
    @async.with_task_group(group => {
      let owner = group.spawn(() => {
        let subscription = channel.subscribe(inbox, map=value => Some(value), on_lag=sub => {
          sub.close()
        })
        defer subscription.close()
        ready.put(())
        blocked.get()
      })
      ready.get()
      owner.cancel()
      owner.wait() catch {
        @async.WaitedTaskAlreadyCancelled => ()
        error => raise error
      }
      channel.publish(1)
      assert_eq(inbox.try_get(), None)
    })
  })
}
