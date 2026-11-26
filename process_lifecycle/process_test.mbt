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

///|
#cfg(not(platform="windows"))
async test "a returning hook does not implicitly terminate the child" {
  @async.with_timeout(3000, () => {
    @async.with_task_group(group => {
      let invoked : @async.Queue[Unit] = Queue(kind=Blocking(1))
      let child = @process_lifecycle.spawn(
        group,
        "sh",
        ["-c", "echo ready; read line; echo $line; exit 7"],
        stdin=FeedFromParent,
        stdout=Collect,
        on_cancel=_ => invoked.put(()),
      )
      defer child.stdin.close()
      defer child.stdout.close()
      assert_eq(child.stdout.text.read_line(), Some("ready"))
      child.cancel()
      invoked.get()
      assert_eq(child.try_wait(), None)
      child.stdin.write(b"finish\n")
      assert_eq(child.wait(), 7)
      assert_eq(child.stdout.text.read_all(), "finish\n")
    })
  })
}

///|
#cfg(not(platform="windows"))
async test "the hook decides when to invoke the termination policy" {
  @async.with_timeout(3000, () => {
    @async.with_task_group(group => {
      let invoked : @async.Queue[Unit] = Queue(kind=Blocking(1))
      let terminate : @async.Queue[Unit] = Queue(kind=Blocking(1))
      let child = @process_lifecycle.spawn(
        group,
        "sh",
        ["-c", "echo ready; read line"],
        stdin=FeedFromParent,
        stdout=Collect,
        on_cancel=process => {
          invoked.put(())
          terminate.get()
          process.cancel()
        },
      )
      defer child.stdin.close()
      defer child.stdout.close()
      assert_eq(child.stdout.text.read_line(), Some("ready"))
      child.cancel()
      invoked.get()
      assert_eq(child.try_wait(), None)
      terminate.put(())
      assert_eq(child.wait(), -9)
    })
  })
}

///|
#cfg(not(platform="windows"))
async test "a failed hook terminates and joins the child before reporting error" {
  @async.with_timeout(3000, () => {
    let mut owned : @process.Process? = None
    let error = try {
      @async.with_task_group(group => {
        let child = @process_lifecycle.spawn(
          group,
          "sh",
          ["-c", "echo ready; read line"],
          stdin=FeedFromParent,
          stdout=Collect,
          on_cancel=process => {
            owned = Some(process)
            fail("shutdown hook failed")
          },
        )
        defer child.stdin.close()
        defer child.stdout.close()
        assert_eq(child.stdout.text.read_line(), Some("ready"))
        child.cancel()
        ignore(child.wait())
      })
      None
    } catch {
      error => Some("\{error}")
    }
    assert_true(
      error is Some(message) && message.contains("shutdown hook failed"),
    )
    assert_eq(owned.unwrap().try_wait(), Some(-9))
  })
}
