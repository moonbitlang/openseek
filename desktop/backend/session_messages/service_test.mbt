///|
async test "timely approval waits for delivery beyond the approval timeout" {
  let service = @session_messages.Service()
  let (message, fresh) = service.request(
    "sender", "target", "Pause builds", "one",
  )
  assert_true(fresh)
  assert_true(
    message.status()
    is {
      "status": "pending_approval",
      "error": Null,
      "feedback_error": Null,
      ..
    },
  )
  let started : @async.Queue[String] = Queue(kind=Blocking(2))
  let finish : @async.Queue[Unit] = Queue(kind=Blocking(1))
  let errors : Array[String] = []
  @async.with_timeout(1000, () => {
    @async.with_task_group(group => {
      group.spawn_bg(no_wait=true, () => {
        service.run(
          (target, text, id) => {
            assert_eq(target, "target")
            assert_eq(id, message.id)
            assert_true(text.contains("Pause builds"))
            started.put(target)
            finish.get()
          },
          (_, error) => errors.push(error),
        )
      })
      assert_true(service.decide(message.id, true))
      let waiter = group.spawn(() => service.wait(message, wait_ms=1))
      assert_eq(started.get(), "target")
      @async.sleep(5)
      assert_true(waiter.try_wait() is None)
      assert_true(message.status() is { "status": "delivering", .. })
      finish.put(())
      assert_true(
        waiter.wait() is { "status": "sent", "feedback": "tool_result", .. },
      )
      service.detach("sender")
      assert_true(message.status() is { "feedback": "tool_result", .. })
      assert_false(service.decide(message.id, true))
    })
  })
  assert_true(errors.is_empty())
}

///|
async test "timeout retains approval and actively delivers the final result to the sender" {
  let service = @session_messages.Service()
  let (message, _) = service.request(
    "sender", "target", "Read-only work", "two",
  )
  let deliveries : @async.Queue[(String, String, String)] = Queue(
    kind=Blocking(2),
  )
  let errors : Array[String] = []
  @async.with_timeout(1000, () => {
    @async.with_task_group(group => {
      group.spawn_bg(no_wait=true, () => {
        service.run((target, text, id) => deliveries.put((target, text, id)), (
          _,
          error,
        ) => errors.push(error))
      })
      assert_true(
        service.wait(message, wait_ms=1)
        is { "status": "pending_approval", "feedback": "pending", .. },
      )
      // Approval is still possible after the tool and originating turn finish.
      service.detach("sender")
      assert_true(service.decide(message.id, true))
      assert_false(service.decide(message.id, false))
      let (target, body, id) = deliveries.get()
      assert_eq(target, "target")
      assert_eq(id, message.id)
      assert_true(body.contains("Read-only work"))
      let (recipient, result, receipt) = deliveries.get()
      assert_eq(recipient, "sender")
      assert_eq(receipt, "\{message.id}-result")
      assert_true(result.contains("\"status\":\"sent\""))
    })
  })
  assert_true(errors.is_empty())
}

///|
async test "rejection and withdrawal never deliver the proposed message" {
  for approve in [false, true] {
    let service = @session_messages.Service()
    let (message, _) = service.request("sender", "target", "Do work", "denied")
    if approve {
      service.cancel("sender", message.id)
    } else {
      assert_true(service.decide(message.id, false))
    }
    let result = service.wait(message, wait_ms=1)
    if approve {
      assert_true(result is { "status": "cancelled", .. })
    } else {
      assert_true(result is { "status": "rejected", .. })
    }
    assert_false(service.decide(message.id, true))
  }
}

///|
async test "delivery failure is actively reported as failure rather than success" {
  let service = @session_messages.Service()
  let (message, _) = service.request("sender", "target", "Hello", "fail")
  let notices : @async.Queue[String] = Queue(kind=Blocking(1))
  let errors : Array[String] = []
  @async.with_timeout(1000, () => {
    @async.with_task_group(group => {
      group.spawn_bg(no_wait=true, () => {
        service.run(
          (target, text, _) => {
            if target == "target" {
              fail("target was archived")
            }
            assert_eq(target, "sender")
            notices.put(text)
          },
          (_, error) => errors.push(error),
        )
      })
      ignore(service.wait(message, wait_ms=1))
      assert_true(service.decide(message.id, true))
      let notice = notices.get()
      assert_true(notice.contains("\"status\":\"failed\""))
      assert_true(notice.contains("target was archived"))
      assert_true(message.status() is { "status": "failed", .. })
    })
  })
  assert_true(errors.is_empty())
}

///|
test "identical retries recover one request and cannot change its approval subject" {
  let service = @session_messages.Service()
  let (first, _) = service.request("sender", "target", "Exact text", "key")
  let (retry, fresh) = service.request("sender", "target", "Exact text", "key")
  assert_false(fresh)
  assert_eq(retry.id, first.id)
  for (target, text) in [("other", "Exact text"), ("target", "Changed text")] {
    try service.request("sender", target, text, "key") catch {
      _ => ()
    } noraise {
      _ => fail("a retry changed the approved subject")
    }
  }
  try service.get("other-sender", first.id) catch {
    _ => ()
  } noraise {
    _ => fail("another conversation inspected this request")
  }
  try service.cancel("other-sender", first.id) catch {
    _ => ()
  } noraise {
    _ => fail("another conversation withdrew this request")
  }
  assert_true(service.decide(first.id, true))
  try service.cancel("sender", first.id) catch {
    _ => ()
  } noraise {
    _ => fail("withdrew a message that was already approved")
  }
}

///|
async test "a cancelled tool waiter leaves approval and later feedback alive" {
  let service = @session_messages.Service()
  let (message, _) = service.request("sender", "target", "Hello", "cancel-wait")
  @async.with_task_group(group => {
    let waiter = group.spawn(no_wait=true, () => service.wait(message))
    @async.sleep(1)
    waiter.cancel()
    ignore(waiter.wait() catch { _ => Json::null() })
  })
  assert_true(
    message.status()
    is { "status": "pending_approval", "feedback": "pending", .. },
  )
  assert_true(service.decide(message.id, true))
}

///|
test "mutual synchronous sends fail the closing edge instead of deadlocking" {
  let service = @session_messages.Service()
  let (first, _) = service.request("a", "b", "Hello B", "a-to-b")
  let (second, _) = service.request("b", "a", "Hello A", "b-to-a")
  assert_true(service.decide(first.id, true))
  assert_true(service.decide(second.id, true))
  assert_true(first.status() is { "status": "delivering", .. })
  assert_true(
    second.status() is { "status": "failed", "error": String(_), .. },
    msg=second.status().stringify(),
  )
}
