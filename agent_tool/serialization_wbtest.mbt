///|
async test "a file gate grant followed by cancellation cannot enter the mutation" {
  @async.with_task_group(group => {
    let state = FileStateMap()
    let entered : @async.Queue[Unit] = Queue(kind=Unbounded)
    let mutations = Ref(0)
    state.lock.acquire()
    let task = group.spawn(
      () => {
        entered.put(())
        state.with_access(() => mutations.val += 1)
      },
      allow_failure=true,
    )
    entered.get()
    // Grant the queued waiter first, then cancel it before it can resume.
    state.lock.release()
    task.cancel()
    task.wait() catch {
      _ => ()
    }
    assert_eq(mutations.val, 0)
    state.with_access(() => ())
  })
}

///|
/// The cancelled waiter must unwind with the runtime's cancellation signal, not
/// an ordinary failure: a failure would cancel every sibling in its group.
async test "a cancelled file gate waiter leaves its siblings running" {
  @async.with_task_group(group => {
    let state = FileStateMap()
    let entered : @async.Queue[Unit] = Queue(kind=Unbounded)
    let sibling_done : @async.Queue[Unit] = Queue(kind=Unbounded)
    let mutations = Ref(0)
    let sibling_ran = Ref(false)
    state.lock.acquire()
    // Default spawn options: an ordinary error here would fail the group.
    let waiter = group.spawn(() => {
      entered.put(())
      state.with_access(() => mutations.val += 1)
    })
    let sibling = group.spawn(() => {
      sibling_done.get()
      sibling_ran.val = true
    })
    entered.get()
    state.lock.release()
    waiter.cancel()
    let error = try waiter.wait() catch {
      error => Some(error)
    } noraise {
      _ => None
    }
    assert_true(error is Some(error) && error is @async.TaskCancelled)
    assert_eq(mutations.val, 0)
    sibling_done.put(())
    sibling.wait()
    assert_true(sibling_ran.val)
  })
}
