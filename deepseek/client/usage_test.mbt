///|
async test "attempt observer preserves reported usage before malformed response decoding" {
  @async.with_task_group() <| group => {
    guard bind_test_server("local TCP bind unavailable; skipping usage test")
      is Some(server) else {
      return
    }
    let hits = Ref(0)
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (_request, body, conn) => {
          ignore(body.read_all())
          hits.val += 1
          conn.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
          })
          conn.write(
            "{\"id\":\"bad-message\",\"usage\":{\"total_tokens\":17},\"choices\":[]}",
          )
        },
        max_connections=1,
      )
    }
    let attempts : Array[@client.ChatAttempt] = []
    let failed = try {
      ignore(
        retry_client(
          "http://127.0.0.1:\{server.addr.port()}/chat/completions",
          attempts=3,
        ).chat([ChatMessage(User, content=[Text("go")])], on_attempt=attempt => {
          attempts.push(attempt)
        }),
      )
      false
    } catch {
      _ => true
    }
    assert_true(failed)
    assert_eq(hits.val, 1)
    assert_eq(attempts.length(), 1)
    assert_eq(attempts[0].response_id, Some("bad-message"))
    assert_eq(attempts[0].report.total_tokens, Some(17))
    assert_eq(attempts[0].outcome, Failed)
  }
}

///|
async test "attempt observer separates stream retry usage and keeps unknown attempts unknown" {
  @async.with_task_group() <| group => {
    guard bind_test_server("local TCP bind unavailable; skipping usage test")
      is Some(server) else {
      return
    }
    let hits = Ref(0)
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (_request, body, conn) => {
          ignore(body.read_all())
          hits.val += 1
          conn.send_response(200, "OK", extra_headers={
            "Content-Type": "text/event-stream",
          })
          if hits.val == 1 {
            conn.write(
              "data: {\"id\":\"first\",\"usage\":{\"total_tokens\":11}}\n\n",
            )
          } else {
            conn.write(
              "data: {\"choices\":[{\"delta\":{\"content\":\"ok\"}}]}\n\ndata: [DONE]\n\n",
            )
          }
        },
        max_connections=1,
      )
    }
    let attempts : Array[@client.ChatAttempt] = []
    let response = retry_client(
      "http://127.0.0.1:\{server.addr.port()}/chat/completions",
      attempts=2,
    ).chat(
      [ChatMessage(User, content=[Text("go")])],
      stream=StreamHandler(on_content_delta=_ => (), on_retry=(_, _, _) => ()),
      on_attempt=attempt => attempts.push(attempt),
    )
    assert_eq(response.content, "ok")
    assert_eq(attempts.length(), 2)
    assert_eq(attempts[0].attempt, 1)
    assert_eq(attempts[0].outcome, Failed)
    assert_eq(attempts[0].report.total_tokens, Some(11))
    assert_eq(attempts[1].attempt, 2)
    assert_eq(attempts[1].outcome, Completed)
    assert_eq(attempts[1].report.reported, false)
  }
}

///|
async test "usage survives a delta callback failure without retrying" {
  @async.with_task_group() <| group => {
    guard bind_test_server("local TCP bind unavailable; skipping usage test")
      is Some(server) else {
      return
    }
    let hits = Ref(0)
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (_request, body, conn) => {
          ignore(body.read_all())
          hits.val += 1
          conn.send_response(200, "OK", extra_headers={
            "Content-Type": "text/event-stream",
          })
          conn.write(
            "data: {\"usage\":{\"total_tokens\":21},\"choices\":[{\"delta\":{\"content\":\"text\"}}]}\n\n",
          )
        },
        max_connections=1,
      )
    }
    let attempts : Array[@client.ChatAttempt] = []
    let failed = try {
      ignore(
        retry_client(
          "http://127.0.0.1:\{server.addr.port()}/chat/completions",
          attempts=2,
        ).chat(
          [ChatMessage(User, content=[Text("go")])],
          stream=StreamHandler(on_content_delta=_ => fail("consumer failed"), on_retry=(
            _,
            _,
            _,
          ) => ()),
          on_attempt=attempt => attempts.push(attempt),
        ),
      )
      false
    } catch {
      _ => true
    }
    assert_true(failed)
    assert_eq(hits.val, 1)
    assert_eq(attempts[0].outcome, Failed)
    assert_eq(attempts[0].report.total_tokens, Some(21))
  }
}

///|
async test "cancellation reports unknown or observed usage without restarting" {
  for reported in [false, true] {
    @async.with_task_group() <| group => {
      guard bind_test_server("local TCP bind unavailable; skipping usage test")
        is Some(server) else {
        return
      }
      let ready : @async.Queue[Unit] = Queue(kind=Unbounded)
      group.spawn_bg(no_wait=true) <| () => {
        server.run_forever(
          (_request, body, conn) => {
            ignore(body.read_all())
            conn.send_response(200, "OK", extra_headers={
              "Content-Type": "text/event-stream",
            })
            if reported {
              conn.write(
                "data: {\"usage\":{\"total_tokens\":31},\"choices\":[{\"delta\":{\"content\":\"ready\"}}]}\n\n",
              )
            } else {
              conn.write(
                "data: {\"choices\":[{\"delta\":{\"content\":\"ready\"}}]}\n\n",
              )
            }
            conn.flush()
            @async.sleep(60_000)
          },
          max_connections=1,
        )
      }
      let attempts : Array[@client.ChatAttempt] = []
      let task = group.spawn(() => {
        ignore(
          retry_client(
            "http://127.0.0.1:\{server.addr.port()}/chat/completions",
            attempts=2,
          ).chat(
            [ChatMessage(User, content=[Text("go")])],
            stream=StreamHandler(on_content_delta=_ => ready.put(())),
            on_attempt=attempt => attempts.push(attempt),
          ),
        )
      })
      ready.get()
      task.cancel()
      task.wait() catch {
        _ => ()
      }
      assert_eq(attempts.length(), 1)
      assert_eq(attempts[0].outcome, Interrupted)
      assert_eq(
        attempts[0].report.total_tokens,
        if reported {
          Some(31)
        } else {
          None
        },
      )
    }
  }
}
