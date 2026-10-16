///|
fn payload() -> @protocol.AskUserPayload {
  {
    questions: [
      { id: "plan", title: "Which plan?", options: Some(["A", "B"]), },
    ],
  }
}

///|
async test "timely answers return through the tool exactly once" {
  let errors : Array[String] = []
  let service = @user_questions.Service()
  let request = service.request("chat", payload())
  let id = service.snapshot().requests[0].id
  let deliveries : Array[String] = []
  @async.with_timeout(1000, () => {
    @async.with_task_group(group => {
      group.spawn_bg(no_wait=true, () => {
        service.run((_, text, _) => deliveries.push(text), (_, error) => {
          errors.push(error)
        })
      })
      let waiter = group.spawn(() => service.wait(request))
      @async.sleep(1)
      let answers : Map[String, String] = { "plan": "My own plan" }
      service.answer({ id, session: "chat", answers: Some(answers), })
      // The service owns its accepted answer, not the transport's mutable map.
      answers["plan"] = "changed externally"
      assert_true(
        waiter.wait()
        is {
          "status": "answered",
          "answers": { "plan": "My own plan", .. },
          ..
        },
      )
      service.detach("chat")
      @async.sleep(1)
      assert_true(deliveries.is_empty())
      assert_true(service.snapshot().requests.is_empty())
      assert_true(errors.is_empty())
    })
  })
}

///|
async test "timeout preserves the card and delivers a later answer or skip once" {
  for skip in [false, true] {
    let errors : Array[String] = []
    let service = @user_questions.Service()
    let request = service.request("chat", payload())
    let before = service.snapshot()
    let id = before.requests[0].id
    assert_true(
      service.wait(request, wait_ms=1)
      is { "status": "pending", "answers": Null, .. },
    )
    assert_eq(service.snapshot(), before)
    let answer : @protocol.UserQuestionAnswer = {
      id,
      session: "chat",
      answers: if skip {
        None
      } else {
        Some({ "plan": "B" })
      },
    }
    let deliveries : Array[String] = []
    let delivered : @async.Queue[Unit] = Queue(kind=Blocking(2))
    @async.with_timeout(1000, () => {
      @async.with_task_group(group => {
        group.spawn_bg(no_wait=true, () => {
          service.run(
            (session, text, delivery_id) => {
              assert_eq(session, "chat")
              assert_eq(delivery_id, id + "-result")
              assert_true(text.contains("Which plan?"))
              assert_true(
                text.contains(if skip { "skipped" } else { "answered" }),
              )
              deliveries.push(text)
              delivered.put(())
            },
            (_, error) => errors.push(error),
          )
        })
        service.answer(answer)
        delivered.get()
        service.answer(answer)
        service.detach("chat")
        @async.sleep(1)
        assert_eq(deliveries.length(), 1)
        assert_true(service.snapshot().requests.is_empty())
        assert_true(errors.is_empty())
      })
    })
  }
}

///|
async test "cancelled tool or finished turn leaves questions answerable" {
  for cancelled in [false, true] {
    let errors : Array[String] = []
    let service = @user_questions.Service()
    let request = service.request("chat", payload())
    let id = service.snapshot().requests[0].id
    if cancelled {
      assert_true(
        @async.with_timeout_opt(1, () => service.wait(request)) is None,
      )
    } else {
      service.detach("chat")
      service.answer({ id, session: "chat", answers: Some({ "plan": "A" }), })
      // A detached waiter cannot also return the answer owned by background delivery.
      assert_true(service.wait(request) is { "status": "pending", .. })
    }
    let delivered : @async.Queue[Unit] = Queue(kind=Blocking(1))
    @async.with_timeout(1000, () => {
      @async.with_task_group(group => {
        group.spawn_bg(no_wait=true, () => {
          service.run((_, _, _) => delivered.put(()), (_, error) => {
            errors.push(error)
          })
        })
        service.answer({ id, session: "chat", answers: Some({ "plan": "A" }), })
        delivered.get()
        assert_true(errors.is_empty())
      })
    })
  }
}

///|
test "answers are scoped, complete, and first-writer wins across clients" {
  let service = @user_questions.Service()
  ignore(
    service.request("chat", {
      questions: [
        { id: "one", title: "First?", options: None, },
        { id: "two", title: "Second?", options: None, },
      ],
    }),
  )
  let pending = service.snapshot()
  let id = pending.requests[0].id
  let invalid : Array[@protocol.UserQuestionAnswer] = [
    { id, session: "other", answers: None, },
    { id: "missing", session: "chat", answers: None, },
    { id, session: "chat", answers: Some({ "one": "A" }), },
    { id, session: "chat", answers: Some({ "one": "A", "two": "  " }), },
    { id, session: "chat", answers: Some({ "one": "A", "wrong": "B" }), },
  ]
  for answer in invalid {
    let rejected = try {
      service.answer(answer)
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
    assert_eq(service.snapshot(), pending)
  }
  let answer : @protocol.UserQuestionAnswer = {
    id,
    session: "chat",
    answers: Some({ "one": "A", "two": "B" }),
  }
  service.answer(answer)
  let resolved = service.snapshot()
  service.answer(answer)
  assert_eq(service.snapshot(), resolved)
  let rejected = try {
    service.answer({ ..answer, answers: None, })
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  assert_eq(service.snapshot(), resolved)
}

///|
async test "failed delayed delivery is reported without resending" {
  let errors : Array[String] = []
  let service = @user_questions.Service()
  let request = service.request("chat", payload())
  let id = service.snapshot().requests[0].id
  ignore(service.wait(request, wait_ms=1))
  let calls : Array[String] = []
  @async.with_timeout(1000, () => {
    @async.with_task_group(group => {
      group.spawn_bg(no_wait=true, () => {
        service.run(
          (_, _, id) => {
            calls.push(id)
            fail("session unavailable")
          },
          (_, error) => errors.push(error),
        )
      })
      service.answer({ id, session: "chat", answers: None, })
      while errors.is_empty() {
        @async.sleep(1)
      }
      assert_true(errors[0].contains("session unavailable"))
      service.detach("chat")
      @async.sleep(1)
      assert_eq(calls.length(), 1)
    })
  })
}
