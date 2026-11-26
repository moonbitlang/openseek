///|
#cfg(not(platform="windows"))
async test "cancel runs the hook before termination and cancels it on child exit" {
  @async.with_timeout(3000, () => {
    @async.with_task_group(group => {
      let (input, writer) = @process.write_to_process()
      defer input.close()
      defer writer.close()
      let mut calls = 0
      let mut finished_hook = false
      let child = @process_lifecycle.spawn(
        group,
        "sh",
        ["-c", "echo ready; cat >/dev/null; echo flushed"],
        stdin=Shared(input),
        stdout=Collect,
        on_cancel=_ => {
          calls += 1
          writer.close()
          @async.sleep(10000)
          finished_hook = true
        },
      )
      defer child.stdout.close()
      assert_eq(child.stdout.text.read_line(), Some("ready"))
      child.cancel()
      child.cancel()
      assert_eq(child.wait(), 0)
      assert_eq(child.stdout.text.read_all(), "flushed\n")
      assert_eq(calls, 1)
      assert_false(finished_hook)
      assert_eq(child.try_wait(), Some(0))
    })
  })
}

///|
#cfg(not(platform="windows"))
async test "group teardown runs the hook and waits for the child" {
  @async.with_timeout(3000, () => {
    let (input, writer) = @process.write_to_process()
    defer input.close()
    defer writer.close()
    let mut child : @process_lifecycle.Process? = None
    let mut calls = 0
    @async.with_task_group(group => {
      let process = @process_lifecycle.spawn(
        group,
        "sh",
        ["-c", "echo ready; cat >/dev/null; echo flushed"],
        stdin=Shared(input),
        stdout=Collect,
        no_wait=true,
        on_cancel=_ => {
          calls += 1
          writer.close()
          @async.sleep(10000)
        },
      )
      child = Some(process)
      assert_eq(process.stdout.text.read_line(), Some("ready"))
    })
    let child = child.unwrap()
    defer child.stdout.close()
    assert_eq(calls, 1)
    assert_eq(child.try_wait(), Some(0))
    assert_eq(child.stdout.text.read_all(), "flushed\n")
  })
}

///|
async test "a caught spawn failure does not fail the caller's task group" {
  @async.with_timeout(3000, () => {
    @async.with_task_group(group => {
      try
        @process_lifecycle.spawn(group, "openseek-missing-process-734a1", [])
      catch {
        _ => ()
      } noraise {
        _ => fail("missing executable unexpectedly started")
      }
    })
  })
}
