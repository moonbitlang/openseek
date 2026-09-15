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
