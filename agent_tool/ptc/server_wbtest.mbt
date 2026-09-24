///|
/// Test bracket. Production hosts register programs on their scoped service.
async fn run(
  tools : @agent_tool.Tools,
  program : async (Map[String, String]) -> @agent_tool.ToolAction,
  on_trace? : (Json) -> Unit = _ => (),
) -> @agent_tool.ToolAction {
  @async.with_task_group(group => {
    let service = Service::start(group, tools)
    let registration = service.register(on_trace~)
    defer registration.close()
    let action = program(registration.env()) catch {
      error =>
        @agent_tool.respond("PTC program failed: \{error}", is_error=true)
    }
    registration.close()
    registration.result(action)
  })
}

///|
/// A program-callable leaf tool; the description is never asserted on.
fn leaf(
  name~ : String,
  execute~ : @agent_tool.ToolExecutor,
  concurrent_safe? : Bool = false,
) -> @agent_tool.AgentToolDefinition {
  AgentToolDefinition(
    name~,
    description=name,
    schema=JsonSchema({}),
    program_callable=true,
    concurrent_safe~,
    execute~,
  )
}

///|
/// The SDK's discovery handoff, as a script would read it.
fn capability(env : Map[String, String]) -> (String, String) raise {
  guard @json.parse(env["OPENSEEK_PTC"])
    is { "url": String(url), "token": String(token), .. } else {
    fail("missing PTC handoff")
  }
  (url, token)
}

///|
/// Join a task whose outcome the test does not care about.
async fn[T] settle(task : @async.Task[T]) -> Unit {
  ignore(task.wait()) catch {
    _ => ()
  }
}

///|
/// Wait until the listener has admitted a program's first request.
async fn await_admission(program : Program) -> Unit {
  while program.calls.is_empty() {
    @async.sleep(1)
  }
}

///|
async fn request(
  env : Map[String, String],
  name : String,
  arguments : Json,
) -> Json {
  let (url, token) = capability(env)
  let (response, body) = @http.post(
    url,
    ({ "version": 1, "name": name, "arguments": arguments } : Json),
    headers={ "Authorization": "Bearer \{token}" },
  )
  assert_eq(response.code, 200)
  body.json()
}

///|
async test "PTC serializes stateful requests and overlaps concurrent-safe requests" {
  for concurrent_safe in [false, true] {
    let journal : Array[String] = []
    let tool = leaf(
      name="probe",
      concurrent_safe~,
      execute=Async(_ => {
        journal.push("start")
        @async.sleep(30)
        journal.push("end")
        @agent_tool.respond("ok", data={ "answer": 42 })
      }),
    )
    let action = @async.with_timeout(3000, () => {
      run(Tools([tool]), env => {
        @async.with_task_group(group => {
          for _ in 0..<2 {
            group.spawn_bg(() => {
              assert_true(
                request(env, "probe", {})
                is { "data": { "answer": 42, .. }, "is_error": false, .. },
              )
            })
          }
        })
        @agent_tool.respond("script done")
      })
    })
    assert_true(action is Respond({ is_error: false, .. }))
    assert_eq(
      journal,
      if concurrent_safe {
        ["start", "start", "end", "end"]
      } else {
        ["start", "end", "start", "end"]
      },
    )
  }
}

///|
async test "PTC rejects unauthenticated unregistered and loop-control calls before execution" {
  let executed = Ref(false)
  let control = @agent_tool.AgentToolDefinition(
    name="finish",
    description="control",
    schema=JsonSchema({}),
    control=true,
    program_callable=true,
    execute=Sync(_ => {
      executed.val = true
      @agent_tool.ToolAction::finish("done")
    }),
  )
  let hidden = @agent_tool.AgentToolDefinition(
    name="hidden",
    description="hidden",
    schema=JsonSchema({}),
    execute=Sync(_ => {
      executed.val = true
      @agent_tool.respond("hidden")
    }),
  )
  let action = run(Tools([control, hidden]), env => {
    for name in ["finish", "hidden", "mbtx", "goal", "job_wait"] {
      assert_true(request(env, name, {}) is { "is_error": true, .. })
    }
    let (url, _) = capability(env)
    let (response, _) = @http.post(url, ({} : Json))
    assert_eq(response.code, 403)
    @agent_tool.respond("ok")
  })
  assert_true(action is Respond({ is_error: false, .. }))
  assert_false(executed.val)
}

///|
async test "PTC cancellation joins handlers releases shared state and retains interruption" {
  let state = @agent_tool.FileStateMap()
  let started : @async.Queue[Unit] = Queue(kind=Unbounded)
  let stopped = Ref(false)
  let trace : Ref[Json?] = Ref(None)
  let tool = state.serialize(
    leaf(
      name="block",
      execute=Async(_ => {
        defer {
          stopped.val = true
        }
        started.put(())
        @async.sleep(60000)
        @agent_tool.respond("should not finish")
      }),
    ),
  )
  @async.with_task_group(group => {
    let operation = group.spawn(() => {
      run(
        Tools([tool]),
        env => {
          request(env, "block", {}) |> ignore
          @agent_tool.respond("script done")
        },
        on_trace=data => trace.val = Some(data),
      )
    })
    @async.with_timeout(3000, () => started.get())
    operation.cancel()
    try operation.wait() |> ignore catch {
      _ => ()
    }
    assert_true(stopped.val)
    @async.with_timeout(1000, () => state.with_access(() => ()))
  })
  assert_true(
    trace.val is Some({ "ptc_calls": [{ "status": "interrupted", .. }], .. }),
  )
}

///|
async test "PTC answers a call revoked by program close with an error result" {
  let started : @async.Queue[Unit] = Queue(kind=Unbounded)
  let tool = leaf(
    name="block",
    execute=Async(_ => {
      started.put(())
      @async.sleep(60000)
      @agent_tool.respond("should not finish")
    }),
  )
  @async.with_timeout(3000, () => {
    @async.with_task_group(group => {
      let service = Service::start(group, Tools([tool]))
      let program = service.register()
      // The handler's `Task::wait` on the revoked executor raises the ordinary
      // `WaitedTaskAlreadyCancelled` error; the client still gets a reply.
      let pending = group.spawn(
        () => request(program.env(), "block", {}),
        allow_failure=true,
      )
      started.get()
      program.close()
      assert_true(
        pending.wait() is { "is_error": true, "content": String(message), .. } &&
        message.contains("PTC call failed"),
      )
    })
  })
}

///|
async test "PTC tool failures are results and do not end the program" {
  let failed = leaf(name="fail", execute=Async(_ => fail("expected failure")))
  let action = run(Tools([failed]), env => {
    assert_true(
      request(env, "fail", {})
      is { "is_error": true, "content": String(message), .. } &&
      message.contains("expected failure"),
    )
    @agent_tool.respond("recovered")
  })
  assert_true(action is Respond({ content: "recovered", is_error: false, .. }))
}

///|
async test "PTC rejects malformed requests and enforces execution and result budgets" {
  let executions = Ref(0)
  let tool = leaf(
    name="probe",
    execute=Sync(_ => {
      executions.val += 1
      @agent_tool.respond(String::make(65537, 'x'))
    }),
  )
  let action = run(Tools([tool]), env => {
    let (url, token) = capability(env)
    for
      invalid in [
        "{",
        String::make(65537, 'x'),
        "{\"version\":2,\"name\":\"probe\",\"arguments\":{}}",
      ] {
      let (_, body) = @http.post(url, invalid, headers={
        "Authorization": "Bearer \{token}",
      })
      assert_true(body.json() is { "is_error": true, .. })
    }
    assert_eq(executions.val, 0)
    for _ in 0..<1024 {
      assert_true(
        request(env, "probe", {})
        is { "is_error": true, "content": String(message), .. } &&
        message.contains("Tool executed"),
      )
    }
    assert_true(
      request(env, "probe", {})
      is { "is_error": true, "content": String(message), .. } &&
      message.contains("1024-call or four-active-call budget"),
    )
    @agent_tool.respond("done")
  })
  assert_true(action is Respond({ is_error: false, .. }))
  assert_eq(executions.val, 1024)
  guard action is Respond({ data: Some({ "ptc_calls": Array(calls), .. }), .. }) else {
    fail("missing trace")
  }
  assert_eq(calls.length(), 1024)
}

///|
async test "PTC preserves completed calls when the program fails" {
  let probe = leaf(
    name="probe",
    execute=Sync(_ => @agent_tool.respond("applied")),
  )
  let action = run(Tools([probe]), env => {
    request(env, "probe", {}) |> ignore
    fail("program failed after its mutation")
  })
  assert_true(
    action
    is Respond(
      {
        is_error: true,
        data: Some(
          {
            "ptc_calls": [
              { "status": "done", "result": { "content": "applied", .. }, .. },
            ],
            ..
          }
        ),
        ..
      }
    ),
  )
}

///|
async test "PTC and direct file calls share one execution gate" {
  let state = @agent_tool.FileStateMap()
  let started : @async.Queue[Unit] = Queue(kind=Unbounded)
  let release : @async.Queue[Unit] = Queue(kind=Unbounded)
  let journal : Array[String] = []
  let definition = state.serialize(
    leaf(
      name="edit",
      execute=Async(arguments => {
        if arguments == "ptc" {
          journal.push("ptc start")
          started.put(())
          release.get()
          journal.push("ptc end")
        } else {
          journal.push("direct")
        }
        @agent_tool.respond("ok")
      }),
    ),
  )
  let tools = @agent_tool.Tools([definition])
  @async.with_timeout(3000, () => {
    @async.with_task_group(group => {
      group.spawn_bg(() => {
        run(tools, env => {
          request(env, "edit", "ptc") |> ignore
          @agent_tool.respond("done")
        })
        |> ignore
      })
      started.get()
      group.spawn_bg(() => {
        @agent_tool.execute_tool_call(
          @agent_tool.AgentToolCall::from_arguments("edit", "direct"),
          tools,
        )
        |> ignore
      })
      @async.sleep(20)
      assert_eq(journal, ["ptc start"])
      release.put(())
    })
  })
  assert_eq(journal, ["ptc start", "ptc end", "direct"])
}

///|
async test "PTC program exit joins an unawaited request and revokes its endpoint" {
  let started : @async.Queue[Unit] = Queue(kind=Unbounded)
  let stopped = Ref(false)
  let handoff : Ref[Map[String, String]?] = Ref(None)
  let tool = leaf(
    name="block",
    execute=Async(_ => {
      defer {
        stopped.val = true
      }
      started.put(())
      @async.sleep(60000)
      @agent_tool.respond("unexpected")
    }),
  )
  @async.with_timeout(3000, () => {
    @async.with_task_group(group => {
      let action = run(Tools([tool]), env => {
        handoff.val = Some(env)
        group.spawn_bg(() => {
          (request(env, "block", {}) |> ignore) catch {
            _ => ()
          }
        })
        started.get()
        @agent_tool.respond("program exited without awaiting its call")
      })
      assert_true(stopped.val)
      assert_true(action is Respond({ is_error: true, .. }))
      assert_true(
        action
        is Respond(
          {
            data: Some({ "ptc_calls": [{ "status": "interrupted", .. }], .. }),
            ..
          }
        ),
      )
      guard handoff.val is Some(env) else { fail("no handoff") }
      let closed = try {
        request(env, "block", {}) |> ignore
        false
      } catch {
        _ => true
      }
      assert_true(closed)
    })
  })
}
