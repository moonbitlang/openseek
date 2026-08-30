///|
test "disposable is idempotent" {
  let count = Ref(0)
  let disposable = Disposable::from(() => count.val += 1)
  disposable.dispose()
  disposable.dispose()
  assert_eq(count.val, 1)
}

///|
test "emitter listener disposable removes only that listener" {
  let emitter : Emitter[String] = Emitter()
  let first = Ref("")
  let second = Ref("")
  let first_subscription = emitter.event(value => first.val += value)
  let second_subscription = emitter.event(value => second.val += value)
  emitter.fire("a")
  first_subscription.dispose()
  emitter.fire("b")
  second_subscription.dispose()
  emitter.fire("c")
  assert_eq(first.val, "a")
  assert_eq(second.val, "ab")
}

///|
test "microtask emitter merges queued events into one flush" {
  let scheduled : Array[() -> Unit] = []
  let emitter : MicrotaskEmitter[Array[Int]] = MicrotaskEmitter(
    merge=all => all.flatten(),
    schedule=run => scheduled.push(run),
  )
  let fired : Array[Array[Int]] = []
  emitter.event(values => fired.push(values)) |> ignore
  emitter.fire([1])
  emitter.fire([2, 3])
  // One scheduled flush for the whole tick, nothing delivered yet.
  assert_eq(scheduled.length(), 1)
  assert_eq(fired.length(), 0)
  scheduled[0]()
  debug_inspect(fired, content="[[1, 2, 3]]")
  // The flush resets the queue: the next fire schedules again.
  emitter.fire([4])
  assert_eq(scheduled.length(), 2)
  scheduled[1]()
  debug_inspect(fired, content="[[1, 2, 3], [4]]")
}

///|
test "microtask emitter without listeners queues nothing" {
  let scheduled : Array[() -> Unit] = []
  let emitter : MicrotaskEmitter[Int] = MicrotaskEmitter(schedule=run => {
    scheduled.push(run)
  })
  emitter.fire(1)
  assert_eq(scheduled.length(), 0)
}

///|
test "microtask emitter default schedule flushes inline" {
  let emitter : MicrotaskEmitter[Int] = MicrotaskEmitter()
  let fired : Array[Int] = []
  emitter.event(value => fired.push(value)) |> ignore
  emitter.fire(1)
  emitter.fire(2)
  debug_inspect(fired, content="[1, 2]")
}

///|
test "emitter dispose stops active and later listeners" {
  let emitter : Emitter[String] = Emitter()
  let seen = Ref("")
  emitter.event(value => seen.val += value).dispose()
  emitter.event(value => seen.val += value) |> ignore
  emitter.fire("a")
  emitter.dispose()
  emitter.event(value => seen.val += value) |> ignore
  emitter.fire("b")
  assert_eq(seen.val, "a")
}
