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
async test "delivery timeout or caller cancellation transfers one final receipt without resubmitting" {
  for caller_timeout in [false, true] {
    for delivery_fails in [false, true] {
      let service = @session_messages.Service()
      let (message, _) = service.request("sender", "target", "Hello", "slow")
      let started : @async.Queue[Unit] = Queue(kind=Blocking(1))
      let finish : @async.Queue[Unit] = Queue(kind=Blocking(1))
      let notices : @async.Queue[String] = Queue(kind=Blocking(1))
      let deliveries : Array[String] = []
      let errors : Array[String] = []
      @async.with_timeout(1000, () => {
        @async.with_task_group(group => {
          group.spawn_bg(no_wait=true, () => {
            service.run(
              (target, text, _) => {
                deliveries.push(target)
                if target == "target" {
                  started.put(())
                  finish.get()
                  if delivery_fails {
                    fail("target stopped accepting input")
                  }
                } else {
                  assert_eq(target, "sender")
                  notices.put(text)
                }
              },
              (_, error) => errors.push(error),
            )
          })
          assert_true(service.decide(message.id, true))
          started.get()
          if caller_timeout {
            // An outer tool deadline cancels only its waiter. The host task
            // is still blocked in the original delivery, not a replacement.
            assert_true(
              @async.with_timeout_opt(1, () => service.wait(message)) is None,
            )
          } else {
            assert_true(
              service.wait(message, delivery_wait_ms=1)
              is { "status": "delivering", "feedback": "pending", .. },
            )
          }
          assert_true(
            message.status()
            is { "status": "delivering", "feedback": "pending", .. },
          )
          let (duplicate, fresh) = service.request(
            "sender", "target", "Hello", "slow",
          )
          assert_false(fresh)
          assert_eq(duplicate.id, message.id)
          service.detach("sender")
          finish.put(())
          let notice = notices.get()
          if delivery_fails {
            assert_true(
              @message_context.parse(notice)
              is Some(DeliveryResult(status="failed", error=Some(_), ..)),
            )
          } else {
            assert_true(
              @message_context.parse(notice)
              is Some(DeliveryResult(status="sent", error=None, ..)),
            )
          }
          service.detach("sender")
          @async.pause()
          assert_true(message.status() is { "feedback": "notified", .. })
        })
      })
      assert_eq(deliveries, ["target", "sender"])
      assert_true(errors.is_empty())
    }
  }
}

///|
async test "completion near the delivery deadline has exactly one feedback owner" {
  for delay in [0, 1, 2] {
    let service = @session_messages.Service()
    let (message, _) = service.request("sender", "target", "Hello", "race")
    let deliveries : Array[String] = []
    let notices : @async.Queue[Unit] = Queue(kind=Blocking(1))
    let errors : Array[String] = []
    @async.with_timeout(1000, () => {
      @async.with_task_group(group => {
        group.spawn_bg(no_wait=true, () => {
          service.run(
            (target, _, _) => {
              deliveries.push(target)
              if target == "target" {
                @async.sleep(delay)
              } else {
                assert_eq(target, "sender")
                notices.put(())
              }
            },
            (_, error) => errors.push(error),
          )
        })
        assert_true(service.decide(message.id, true))
        let result = service.wait(message, delivery_wait_ms=1)
        if result is { "feedback": "tool_result", .. } {
          assert_true(result is { "status": "sent", .. })
          service.detach("sender")
          @async.pause()
          assert_eq(deliveries, ["target"])
        } else {
          assert_true(result is { "feedback": "pending", .. })
          notices.get()
          @async.pause()
          assert_true(message.status() is { "feedback": "notified", .. })
          assert_eq(deliveries, ["target", "sender"])
        }
      })
    })
    assert_true(errors.is_empty())
  }
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
      assert_eq(
        body,
        @message_context.Message(
          source_session="sender",
          message_id=message.id,
          text="Read-only work",
        ).encode(),
      )
      let (recipient, result, receipt) = deliveries.get()
      assert_eq(recipient, "sender")
      assert_eq(receipt, "\{message.id}-result")
      assert_true(
        @message_context.parse(result)
        is Some(DeliveryResult(status="sent", error=None, ..)),
      )
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
async test "delivery failure is reported once and duplicate requests retain the failure" {
  let service = @session_messages.Service()
  let (message, _) = service.request("sender", "target", "Hello", "fail")
  let notices : @async.Queue[String] = Queue(kind=Blocking(1))
  let deliveries : Array[String] = []
  let errors : Array[String] = []
  @async.with_timeout(1000, () => {
    @async.with_task_group(group => {
      group.spawn_bg(no_wait=true, () => {
        service.run(
          (target, text, _) => {
            deliveries.push(target)
            if target == "target" {
              fail("message was not delivered: the engine dropped the input")
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
      assert_true(
        @message_context.parse(notice)
        is Some(DeliveryResult(status="failed", error=Some(_), ..)),
      )
      assert_true(notice.contains("the engine dropped the input"))
      assert_true(message.status() is { "status": "failed", .. })
      let (duplicate, fresh) = service.request(
        "sender", "target", "Hello", "fail",
      )
      assert_false(fresh)
      assert_eq(duplicate.id, message.id)
      assert_true(service.wait(duplicate) is { "status": "failed", .. })
      assert_false(service.decide(message.id, true))
    })
  })
  assert_true(errors.is_empty())
  assert_eq(deliveries, ["target", "sender"])
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
    ignore(waiter.wait() catch { _ => null })
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
