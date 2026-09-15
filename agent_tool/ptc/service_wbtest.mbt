///|
async test "session listener reuses its port with isolated revocable capabilities" {
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let tool = @agent_tool.AgentToolDefinition(
        name="echo",
        description="echo",
        schema=JsonSchema({}),
        program_callable=true,
        concurrent_safe=true,
        execute=Sync(arguments => @agent_tool.respond("ok", data=arguments)),
      )
      let service = Service::start(group, Tools([tool]))
      let foreground : Array[Json] = []
      let background : Array[Json] = []
      let first = service.register(on_trace=data => foreground.push(data))
      let second = service.register()
      guard @json.parse(first.env()["OPENSEEK_PTC"])
        is { "url": String(url), "token": String(token), .. } else {
        fail("first capability")
      }
      guard @json.parse(second.env()["OPENSEEK_PTC"])
        is { "url": String(other_url), "token": String(other_token), .. } else {
        fail("second capability")
      }
      assert_eq(url, other_url)
      assert_true(token != other_token)
      ignore(request(first.env(), "echo", { "owner": "first" }))
      let foreground_count = foreground.length()
      first.handoff("job-test", data => background.push(data))
      ignore(request(first.env(), "echo", { "owner": "background" }))
      ignore(request(second.env(), "echo", { "owner": "second" }))
      assert_eq(foreground.length(), foreground_count)
      assert_eq(background.length(), 2)
      assert_true(
        first.trace()
        is {
          "ptc_calls": [_, { "arguments": { "owner": "background", .. }, .. }],
          ..
        },
      )
      assert_true(
        second.trace()
        is { "ptc_calls": [{ "arguments": { "owner": "second", .. }, .. }], .. },
      )
      first.close()
      let (response, body) = @http.post(url, ({} : Json), headers={
        "Authorization": "Bearer \{token}",
      })
      ignore(body.text())
      assert_eq(response.code, 403)
      assert_true(
        request(second.env(), "echo", {}) is { "is_error": false, .. },
      )
      second.close()
      assert_true(service.programs.is_empty())
    })
  })
}

///|
async test "closing queued and running RPC calls does not deadlock the shared file gate" {
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let state = @agent_tool.FileStateMap()
      let entered : @async.Queue[Unit] = Queue(kind=Unbounded)
      let release : @async.Queue[Unit] = Queue(kind=Unbounded)
      let journal : Array[String] = []
      let tool = state.serialize(
        AgentToolDefinition(
          name="edit",
          description="file gate probe",
          schema=JsonSchema({}),
          program_callable=true,
          execute=Async(arguments => {
            guard arguments is { "id": String(id), .. } else {
              fail("missing id")
            }
            journal.push(id)
            if id == "running" {
              entered.put(())
              release.get()
            }
            @agent_tool.respond("done")
          }),
        ),
      )
      let tools = @agent_tool.Tools([tool])
      let service = Service::start(group, tools)
      let running = service.register()
      let queued = service.register()
      let first = group.spawn(
        () => request(running.env(), "edit", { "id": "running" }),
        allow_failure=true,
      )
      entered.get()
      let second = group.spawn(
        () => request(queued.env(), "edit", { "id": "queued" }),
        allow_failure=true,
      )
      while queued.calls.is_empty() {
        @async.sleep(1)
      }
      queued.close()
      assert_true(queued.interrupted())
      let direct = group.spawn(() => {
        @agent_tool.execute_tool_call(
          @agent_tool.AgentToolCall::from_arguments("edit", { "id": "direct" }),
          tools,
        )
      })
      running.close()
      assert_true(running.interrupted())
      assert_true(direct.wait() is Respond({ is_error: false, .. }))
      ignore(first.wait()) catch {
        _ => ()
      }
      ignore(second.wait()) catch {
        _ => ()
      }
      assert_eq(journal, ["running", "direct"])
    })
  })
}

///|
async test "session teardown joins active calls and revokes all registrations" {
  let stopped = Ref(false)
  let retained : Ref[Program?] = Ref(None)
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let entered : @async.Queue[Unit] = Queue(kind=Unbounded)
      let tool = @agent_tool.AgentToolDefinition(
        name="block",
        description="block",
        schema=JsonSchema({}),
        program_callable=true,
        execute=Async(_ => {
          defer {
            stopped.val = true
          }
          entered.put(())
          @async.sleep(60000)
          @agent_tool.respond("unexpected")
        }),
      )
      let service = Service::start(group, Tools([tool]))
      let program = service.register()
      retained.val = Some(program)
      group.spawn_bg(
        () => ignore(request(program.env(), "block", {})),
        no_wait=true,
        allow_failure=true,
      )
      entered.get()
    })
  })
  assert_true(stopped.val)
  assert_true(
    retained.val is Some(program) && program.closed && program.interrupted(),
  )
}

///|
async test "retained trace stays within job record bounds without truncating client replies" {
  @async.with_task_group(group => {
    let text = "x".repeat(50000)
    let tool = @agent_tool.AgentToolDefinition(
      name="large",
      description="large",
      schema=JsonSchema({}),
      program_callable=true,
      execute=Sync(_ => @agent_tool.respond(text)),
    )
    let service = Service::start(group, Tools([tool]))
    let program = service.register()
    for _ in 0..<16 {
      assert_true(
        request(program.env(), "large", {})
        is { "content": String(content), .. } &&
        content == text,
      )
    }
    let trace = program.trace()
    assert_true(@utf8.encode(trace.stringify()).length() < 530000)
    guard trace is { "ptc_calls": Array(calls), .. } else {
      fail("missing calls")
    }
    assert_eq(calls.length(), 16)
    assert_true(
      calls.any(call => {
        call is { "result": { "trace_truncated": true, .. }, .. }
      }),
    )
    program.close()
  })
}

///|
async test "synchronous revocation prevents queued mutation before asynchronous close" {
  @async.with_timeout(3000, () => {
    @async.with_task_group(group => {
      let state = @agent_tool.FileStateMap()
      let held : @async.Queue[Unit] = Queue(kind=Unbounded)
      let release : @async.Queue[Unit] = Queue(kind=Unbounded)
      let mutations = Ref(0)
      let holder = group.spawn(() => {
        state.with_access(() => {
          held.put(())
          release.get()
        })
      })
      held.get()
      let service = Service::start(
        group,
        Tools([
          state.serialize(
            AgentToolDefinition(
              name="edit",
              description="queued mutation",
              schema=JsonSchema({}),
              program_callable=true,
              execute=Sync(_ => {
                mutations.val += 1
                @agent_tool.respond("applied")
              }),
            ),
          ),
        ]),
      )
      let program = service.register()
      let pending = group.spawn(
        () => request(program.env(), "edit", {}),
        allow_failure=true,
      )
      while program.calls.is_empty() {
        @async.sleep(1)
      }
      program.stop()
      assert_true(service.programs.is_empty())
      // Simulate publication/output draining before close is able to join.
      release.put(())
      holder.wait()
      ignore(pending.wait()) catch {
        _ => ()
      }
      assert_eq(mutations.val, 0)
      program.close()
      assert_true(program.interrupted())
    })
  })
}

///|
async test "incomplete HTTP headers cannot exhaust listener slots indefinitely" {
  @async.with_timeout(8000, () => {
    @async.with_task_group(group => {
      let service = Service::start(group, Tools([]))
      let program = service.register()
      let clients : Array[@socket.Tcp] = []
      defer (for client in clients {
        client.close()
      })
      for _ in 0..<16 {
        let client = @socket.Tcp::connect(service.server.addr)
        clients.push(client)
        client.write("POST /call HTTP/1.1\r\nAuthorization:")
      }
      @async.sleep(20)
      assert_true(
        request(program.env(), "unavailable", {}) is { "is_error": true, .. },
      )
    })
  })
}

///|
async test "HTTP admission rejects oversized headers and ambiguous framing without execution" {
  @async.with_task_group(group => {
    let executed = Ref(0)
    let service = Service::start(
      group,
      Tools([
        AgentToolDefinition(
          name="probe",
          description="probe",
          schema=JsonSchema({}),
          program_callable=true,
          execute=Sync(_ => {
            executed.val += 1
            @agent_tool.respond("ok")
          }),
        ),
      ]),
    )
    let program = service.register()
    guard @json.parse(program.env()["OPENSEEK_PTC"])
      is { "token": String(token), .. } else {
      fail("missing token")
    }
    for
      headers in [
        "X-Long: \{"x".repeat(8192)}\r\n",
        "Content-Length: 0\r\nTransfer-Encoding: chunked\r\n",
        "Content-Length: 0\r\ncontent-length: 0\r\n",
        "Content-Length: 65537\r\n",
      ] {
      let client = @socket.Tcp::connect(service.server.addr)
      defer client.close()
      client.write(
        "POST /call HTTP/1.1\r\nAuthorization: Bearer \{token}\r\n\{headers}\r\n",
      )
      // Closing with unread oversized input may reset TCP instead of delivering
      // the error body. Neither outcome admits an executor.
      let response = @async.with_timeout(1000, () => {
        Some(client.read_all().text()) catch {
          _ => None
        }
      })
      if response is Some(text) {
        assert_true(text.contains("no tool executed"))
      }
    }
    assert_eq(executed.val, 0)
    assert_true(program.calls.is_empty())
    assert_true(
      request(program.env(), "probe", {}) is { "is_error": false, .. },
    )
    assert_eq(executed.val, 1)
  })
}

///|
async test "client disconnect leaves an accepted call owned by its live program" {
  @async.with_timeout(3000, () => {
    @async.with_task_group(group => {
      let entered : @async.Queue[Unit] = Queue(kind=Unbounded)
      let release : @async.Queue[Unit] = Queue(kind=Unbounded)
      let applied = Ref(false)
      let service = Service::start(
        group,
        Tools([
          AgentToolDefinition(
            name="edit",
            description="accepted mutation",
            schema=JsonSchema({}),
            program_callable=true,
            execute=Async(_ => {
              entered.put(())
              release.get()
              applied.val = true
              @agent_tool.respond("applied")
            }),
          ),
        ]),
      )
      let program = service.register()
      guard @json.parse(program.env()["OPENSEEK_PTC"])
        is { "token": String(token), .. } else {
        fail("missing token")
      }
      let client = @socket.Tcp::connect(service.server.addr)
      defer client.close()
      let body = ({ "version": 1, "name": "edit", "arguments": {} } : Json).stringify()
      client.write(
        "POST /call HTTP/1.1\r\nAuthorization: Bearer \{token}\r\nContent-Length: \{@utf8.encode(body).length()}\r\n\r\n\{body}",
      )
      entered.get()
      client.close()
      release.put(())
      while !(program.trace() is { "ptc_calls": [{ "status": "done", .. }], .. }) {
        @async.sleep(1)
      }
      assert_true(applied.val)
      program.close()
      assert_true(
        program.trace() is { "ptc_calls": [{ "status": "done", .. }], .. },
      )
    })
  })
}

///|
async test "stateful dispatch rechecks cancellation when a lock handoff wins" {
  @async.with_timeout(3000, () => {
    @async.with_task_group(group => {
      let entered : @async.Queue[Unit] = Queue(kind=Unbounded)
      let release : @async.Queue[Unit] = Queue(kind=Unbounded)
      let mutations = Ref(0)
      let service = Service::start(
        group,
        Tools([
          AgentToolDefinition(
            name="edit",
            description="standalone stateful tool",
            schema=JsonSchema({}),
            program_callable=true,
            execute=Async(arguments => {
              if arguments == "hold" {
                entered.put(())
                release.get()
              } else {
                mutations.val += 1
              }
              @agent_tool.respond("done")
            }),
          ),
        ]),
      )
      let holder = service.register()
      let queued = service.register()
      let first = group.spawn(() => request(holder.env(), "edit", "hold"))
      entered.get()
      let second = group.spawn(
        () => request(queued.env(), "edit", "mutate"),
        allow_failure=true,
      )
      while queued.calls.is_empty() {
        @async.sleep(1)
      }
      // Cancellation without revoking the program also occurs on an executor
      // deadline or handler cancellation. A later call can still use the program.
      for task in queued.active.values() {
        task.cancel()
      }
      release.put(())
      ignore(first.wait())
      ignore(second.wait()) catch {
        _ => ()
      }
      assert_eq(mutations.val, 0)
      assert_true(
        queued.interrupted() ||
        queued.trace()
        is {
          "ptc_calls": [
            { "status": "done", "result": { "is_error": true, .. }, .. },
          ],
          ..
        },
      )
      assert_true(
        request(queued.env(), "edit", "mutate") is { "is_error": false, .. },
      )
      assert_eq(mutations.val, 1)
    })
  })
}

///|
async test "request deadline includes blocked pre-dispatch publication" {
  @async.with_timeout(1000, () => {
    @async.with_task_group(group => {
      let release : @async.Queue[Unit] = Queue(kind=Unbounded)
      let mutations = Ref(0)
      let service = Service::start(
        group,
        Tools([
          AgentToolDefinition(
            name="edit",
            description="mutation",
            schema=JsonSchema({}),
            program_callable=true,
            execute=Sync(_ => {
              mutations.val += 1
              @agent_tool.respond("applied")
            }),
          ),
        ]),
        call_timeout_ms=10,
        trace_timeout_ms=30,
      )
      let program = service.register()
      program.handoff("job", _ => release.get())
      assert_true(
        request(program.env(), "edit", {}) is { "is_error": true, .. },
      )
      assert_eq(mutations.val, 0)
      program.close()
      assert_true(program.trace_error() is Some(_))
      release.put(())
      assert_eq(mutations.val, 0)
      assert_true(
        program.result(@agent_tool.respond("done"))
        is Respond({ is_error: true, .. }),
      )
    })
  })
}

///|
async test "stop joins calls without repeating blocked cancellation-time publication" {
  @async.with_timeout(1000, () => {
    @async.with_task_group(group => {
      let entered : @async.Queue[Unit] = Queue(kind=Unbounded)
      let release : @async.Queue[Unit] = Queue(kind=Unbounded)
      let service = Service::start(group, Tools([]), trace_timeout_ms=30)
      let program = service.register()
      let publications = Ref(0)
      program.handoff("job", _ => {
        publications.val += 1
        entered.put(())
        release.get()
      })
      let pending = group.spawn(
        () => request(program.env(), "unavailable", {}),
        allow_failure=true,
      )
      entered.get()
      program.close()
      ignore(pending.wait()) catch {
        _ => ()
      }
      assert_true(program.interrupted())
      assert_eq(publications.val, 2) // Initial attempt and one final snapshot.
      assert_true(
        program.trace()
        is {
          "ptc_trace_error": String(_),
          "ptc_calls": [{ "status": "interrupted", .. }],
          ..
        },
      )
    })
  })
}

///|
async test "an RPC gate grant followed by cancellation cannot enter a standalone mutation" {
  @async.with_timeout(1000, () => {
    @async.with_task_group(group => {
      let mutations = Ref(0)
      let service = Service::start(
        group,
        Tools([
          AgentToolDefinition(
            name="edit",
            description="mutation",
            schema=JsonSchema({}),
            program_callable=true,
            execute=Sync(_ => {
              mutations.val += 1
              @agent_tool.respond("done")
            }),
          ),
        ]),
      )
      service.serial.acquire()
      let program = service.register()
      let pending = group.spawn(
        () => request(program.env(), "edit", {}),
        allow_failure=true,
      )
      while program.calls.is_empty() {
        @async.sleep(1)
      }
      @async.sleep(20)
      service.serial.release()
      for task in program.active.values() {
        task.cancel()
      }
      ignore(pending.wait()) catch {
        _ => ()
      }
      assert_eq(mutations.val, 0)
      assert_true(
        program.interrupted() ||
        program.trace()
        is {
          "ptc_calls": [
            { "status": "done", "result": { "is_error": true, .. }, .. },
          ],
          ..
        },
      )
    })
  })
}

///|
async test "HTTP accepts fragmented headers and UTF-8 across single-byte chunks" {
  @async.with_timeout(3000, () => {
    @async.with_task_group(group => {
      let arguments : Ref[Json?] = Ref(None)
      let service = Service::start(
        group,
        Tools([
          AgentToolDefinition(
            name="probe",
            description="probe",
            schema=JsonSchema({}),
            program_callable=true,
            execute=Sync(value => {
              arguments.val = Some(value)
              @agent_tool.respond("ok")
            }),
          ),
        ]),
      )
      let program = service.register()
      guard @json.parse(program.env()["OPENSEEK_PTC"])
        is { "token": String(token), .. } else {
        fail("missing token")
      }
      let client = @socket.Tcp::connect(service.server.addr)
      defer client.close()
      client.write("POST /ca")
      client.write("ll HTTP/1.1\r")
      client.write("\nAuthorization: Bea")
      client.write("rer \{token}\r\nTransfer-Encoding: chunked\r\n\r\n")
      let body = (
        { "version": 1, "name": "probe", "arguments": { "text": "你好" } } :
        Json).stringify()
      for byte in @utf8.encode(body).to_array() {
        client.write("1\r\n")
        client.write(Bytes::from_array([byte]))
        client.write("\r\n")
      }
      client.write("0\r\n\r\n")
      assert_true(client.read_all().text().contains("200 OK"))
      assert_eq(arguments.val, Some({ "text": "你好" }))
    })
  })
}

///|
async test "HTTP rejects malformed chunks and excessive framing before reservation" {
  @async.with_timeout(3000, () => {
    @async.with_task_group(group => {
      let executions = Ref(0)
      let service = Service::start(
        group,
        Tools([
          AgentToolDefinition(
            name="probe",
            description="probe",
            schema=JsonSchema({}),
            program_callable=true,
            execute=Sync(_ => {
              executions.val += 1
              @agent_tool.respond("ok")
            }),
          ),
        ]),
      )
      let program = service.register()
      guard @json.parse(program.env()["OPENSEEK_PTC"])
        is { "token": String(token), .. } else {
        fail("missing token")
      }
      let body = (
        { "version": 1, "name": "probe", "arguments": "x".repeat(23000) } : Json).stringify()
      let framed = body.iter().map(c => "1\r\n\{c}\r\n").to_array().join("") +
        "0\r\n\r\n"
      for
        chunks in [
          "-1\r\n", "10001\r\n", "1;extension\r\n", "1\r\nx!\n", "0\r\nTrailer: x\r\n\r\n",
          framed,
        ] {
        let client = @socket.Tcp::connect(service.server.addr)
        defer client.close()
        try {
          client.write(
            "POST /call HTTP/1.1\r\nAuthorization: Bearer \{token}\r\nTransfer-Encoding: chunked\r\n\r\n\{chunks}",
          )
          ignore(client.read_all())
        } catch {
          _ => ()
        }
      }
      assert_eq(executions.val, 0)
      assert_true(program.calls.is_empty())
    })
  })
}

///|
async test "an acknowledged call deadline remains a tool error the script can handle" {
  @async.with_timeout(1000, () => {
    @async.with_task_group(group => {
      let service = Service::start(
        group,
        Tools([
          AgentToolDefinition(
            name="slow",
            description="slow",
            schema=JsonSchema({}),
            program_callable=true,
            execute=Async(_ => {
              @async.sleep(60000)
              @agent_tool.respond("unexpected")
            }),
          ),
        ]),
        call_timeout_ms=10,
      )
      let program = service.register()
      assert_true(
        request(program.env(), "slow", {}) is { "is_error": true, .. },
      )
      program.close()
      assert_false(program.interrupted())
      assert_true(
        program.trace()
        is {
          "ptc_calls": [
            { "status": "done", "result": { "is_error": true, .. }, .. },
          ],
          ..
        },
      )
      assert_true(
        program.result(@agent_tool.respond("handled"))
        is Respond({ is_error: false, .. }),
      )
    })
  })
}

///|
/// A process that exits while adoption is suspended revokes the registration
/// before mbtx hands it to the job. The final publish from terminal cleanup
/// must still leave the foreground slot alone: after handoff nothing may
/// route through the observer the mbtx result already drained.
async test "handoff after revocation detaches the foreground observer" {
  @async.with_timeout(3000, () => {
    @async.with_task_group(group => {
      let foreground : Array[Json] = []
      let job : Array[Json] = []
      let service = Service::start(
        group,
        Tools([
          AgentToolDefinition(
            name="edit",
            description="leaf",
            schema=JsonSchema({}),
            program_callable=true,
            concurrent_safe=true,
            execute=Sync(_ => @agent_tool.respond("applied")),
          ),
        ]),
      )
      let program = service.register(on_trace=data => foreground.push(data))
      ignore(request(program.env(), "edit", {}))
      let published_before_exit = foreground.length()
      // Observed process exit during adopt(): the ending hook stops first.
      program.stop()
      program.handoff("job-1", data => job.push(data))
      // Terminal cleanup on the job side publishes the final trace.
      program.close()
      assert_eq(foreground.length(), published_before_exit)
      // The closed registration acquires no job observer either: the job
      // reads its final data through the record supplier instead.
      assert_true(job.is_empty())
      assert_true(program.adopted())
      assert_true(program.trace() is { "ptc_job_id": "job-1", .. })
    })
  })
}

///|
/// A timed-out handler publishes after its executor is gone. If that observer
/// is slow, close must not race past it: the final snapshot has to be the
/// last one delivered, or a job would retain a trace that still shows a later
/// call as running.
async test "a slow publication cannot deliver a stale snapshot after close" {
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let delivered : Array[Json] = []
      let gate : @async.Queue[Unit] = Queue(kind=Unbounded)
      let blocked : @async.Queue[Unit] = Queue(kind=Unbounded)
      let held = Ref(false)
      let service = Service::start(
        group,
        Tools([
          AgentToolDefinition(
            name="slow",
            description="outlives its deadline",
            schema=JsonSchema({}),
            program_callable=true,
            concurrent_safe=true,
            execute=Async(_ => {
              @async.sleep(400)
              @agent_tool.respond("late")
            }),
          ),
        ]),
        call_timeout_ms=30,
      )
      let program = service.register()
      program.handoff("job-1", data => {
        // The first snapshot showing a finished call is the timed-out
        // handler's publication: hold it until close has been asked for.
        if !held.val &&
          data is { "ptc_calls": [{ "status": "done", .. }, ..], .. } {
          held.val = true
          blocked.put(())
          gate.get()
        }
        delivered.push(data)
      })
      let first = group.spawn(
        () => request(program.env(), "slow", {}),
        allow_failure=true,
      )
      blocked.get()
      let second = group.spawn(
        () => request(program.env(), "slow", {}),
        allow_failure=true,
      )
      while program.calls.length() < 2 {
        @async.sleep(1)
      }
      let closing = group.spawn(() => program.close())
      @async.sleep(20)
      gate.put(())
      closing.wait()
      ignore(first.wait()) catch {
        _ => ()
      }
      ignore(second.wait()) catch {
        _ => ()
      }
      assert_true(
        delivered.last()
        is Some({ "ptc_calls": [_, { "status": "interrupted", .. }], .. }),
      )
    })
  })
}
