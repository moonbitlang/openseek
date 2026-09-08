///|
async test "user input wait retains messages and ignores notices and blanks" {
  @async.with_timeout(1000, () => {
    @async.with_task_group(group => {
      let runtime = @agent_runtime.AgentRuntime()
      let mut woke = false
      let task = group.spawn(() => {
        runtime.wait_for_user_input()
        woke = true
      })
      runtime.queue_steer(Notice("other job finished"))
      runtime.queue_steer(Prompt(" "))
      @async.pause()
      assert_false(woke)
      runtime.queue_steer(Command("user command result"))
      task.wait()
      assert_true(woke)
      let inputs = runtime.drain_steers()
      assert_eq(inputs.length(), 3)
      assert_true(inputs[2] is Command("user command result"))
      // Input queued before waiting is just as observable.
      runtime.queue_steer(Prompt("new direction"))
      runtime.wait_for_user_input()
      assert_true(runtime.drain_steers() is [Prompt("new direction")])
    })
  })
}

///|
async test "user-originated notices wake waiting and reset after drain" {
  @async.with_timeout(1000, () => {
    @async.with_task_group(group => {
      let runtime = @agent_runtime.AgentRuntime()
      runtime.queue_steer(Notice("goal changed"), wake=true)
      runtime.wait_for_user_input()
      assert_true(runtime.drain_steers() is [Notice("goal changed")])
      let mut woke = false
      let task = group.spawn(() => {
        runtime.wait_for_user_input()
        woke = true
      })
      runtime.queue_steer(Notice("ordinary completion"))
      runtime.queue_steer(Notice(" "), wake=true)
      @async.pause()
      assert_false(woke)
      runtime.queue_steer(Notice("goal cleared"), wake=true)
      task.wait()
      assert_true(woke)
      assert_eq(runtime.drain_steers().length(), 3)
    })
  })
}
