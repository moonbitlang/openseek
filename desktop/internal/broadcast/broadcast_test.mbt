///|
test "every subscription reads the same published order" {
  let channel : @broadcast.Channel[Int] = Channel(capacity=8)
  let first = channel.subscribe()
  let second = channel.subscribe()
  channel.publish(1)
  channel.publish(2)
  assert_eq(first.try_next(), Some(1))
  assert_eq(second.try_next(), Some(1))
  assert_eq(second.try_next(), Some(2))
  assert_eq(second.try_next(), None)
  assert_eq(first.try_next(), Some(2))
  assert_eq(first.try_next(), None)
}

///|
test "a subscription starts at the head" {
  let channel : @broadcast.Channel[String] = Channel(capacity=8)
  channel.publish("before")
  let subscription = channel.subscribe()
  assert_eq(subscription.try_next(), None)
  channel.publish("after")
  assert_eq(subscription.try_next(), Some("after"))
}

///|
test "falling behind the window lags once and resumes at the oldest retained value" {
  let channel : @broadcast.Channel[Int] = Channel(capacity=2)
  let behind = channel.subscribe()
  let keeping_up = channel.subscribe()
  for value in 1..<=5 {
    channel.publish(value)
    assert_eq(keeping_up.try_next(), Some(value))
  }
  let lagged = try behind.try_next() catch {
    Lagged(missed~) => Some(missed)
  } noraise {
    _ => None
  }
  // Only the overwritten values count; the window still holds 4 and 5.
  assert_eq(lagged, Some(3))
  assert_eq(behind.try_next(), Some(4))
  assert_eq(behind.try_next(), Some(5))
  assert_eq(behind.try_next(), None)
  channel.publish(6)
  assert_eq(behind.try_next(), Some(6))
  assert_eq(keeping_up.try_next(), Some(6))
}

///|
test "skipping to the head gives up the retained window" {
  let channel : @broadcast.Channel[Int] = Channel(capacity=2)
  let subscription = channel.subscribe()
  for value in 1..<=5 {
    channel.publish(value)
  }
  let lagged = try subscription.try_next() catch {
    Lagged(_) => true
  } noraise {
    _ => false
  }
  assert_true(lagged)
  subscription.skip_to_head()
  assert_eq(subscription.try_next(), None)
  channel.publish(6)
  assert_eq(subscription.try_next(), Some(6))
}

///|
test "lag reads as a sentence" {
  let channel : @broadcast.Channel[Int] = Channel(capacity=1)
  let subscription = channel.subscribe()
  channel.publish(1)
  channel.publish(2)
  let message = try subscription.try_next() catch {
    error => "\{error}"
  } noraise {
    _ => "no error"
  }
  assert_eq(
    message, "subscription lagged: 1 values were overwritten before it read them",
  )
}

///|
async test "next waits for a publish and consumes nothing when cancelled" {
  let channel : @broadcast.Channel[Int] = Channel(capacity=2)
  let subscription = channel.subscribe()
  // Nothing published: the timeout cancels the wait.
  assert_true(@async.with_timeout_opt(20, () => subscription.next()) is None)
  @async.with_task_group(group => {
    let reader = group.spawn(() => subscription.next())
    // Let the reader park on the channel before publishing.
    @async.pause()
    channel.publish(7)
    assert_eq(reader.wait(), 7)
  })
  // The cancelled wait consumed nothing, and the value was consumed once.
  assert_eq(subscription.try_next(), None)
}
