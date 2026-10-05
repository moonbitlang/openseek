///|
/// A service whose owner-bound tools are built by `build`, with two shared
/// tools every program reaches alike.
async fn[X] owned_service(
  group : @async.TaskGroup[X],
  build : (Owner) -> Array[@agent_tool.AgentToolDefinition],
) -> Service {
  Service::start(
    group,
    Tools([
      leaf(name="shared", execute=Sync(_ => @agent_tool.respond("shared"))),
      leaf(name="gate", execute=Sync(_ => @agent_tool.respond("shared gate"))),
    ]),
    owner_tools=build,
  )
}

///|
/// The text a call answered with.
fn content(reply : Json) -> String raise {
  guard reply is { "content": String(text), .. } else {
    fail("a reply carries its content: \{reply.stringify()}")
  }
  text
}

///|
/// Each program gets its own instances, closed over its own owner; a tool
/// learns who is calling from the host and never from the arguments.
async test "each program reaches tools built for it alone" {
  @async.with_task_group(group => {
    let built : Array[String] = []
    let service = owned_service(group, owner => {
      built.push(owner.id())
      [
        leaf(
          name="whoami",
          concurrent_safe=true,
          // The arguments claim to be someone else; the answer is the owner.
          execute=Sync(_ => @agent_tool.respond(owner.id())),
        ),
        // Not program-callable: built, and unreachable like any such tool.
        AgentToolDefinition(
          name="hidden",
          description="hidden",
          schema=JsonSchema({}),
          execute=Sync(_ => @agent_tool.respond("reached")),
        ),
      ]
    })
    let first = service.register()
    let second = service.register()
    defer first.close()
    defer second.close()
    // Built once per program, at registration, before any call.
    assert_eq(built, ["program-1", "program-2"])
    let claim : Json = { "owner": "program-2" }
    assert_eq(content(request(first.env(), "whoami", claim)), "program-1")
    assert_eq(content(request(second.env(), "whoami", {})), "program-2")
    // Shared tools are still shared, and resolved after a program's own.
    assert_eq(content(request(first.env(), "shared", {})), "shared")
    guard request(first.env(), "hidden", {}) is { "is_error": true, .. } else {
      fail("a tool that is not program-callable must stay unreachable")
    }
    guard request(first.env(), "nope", {}) is { "is_error": true, .. } else {
      fail("an unknown name is still unavailable")
    }
  })
}

///|
/// A name is in one registry or the other — both would make which tool a
/// script reaches depend on lookup order — and a set of owner-bound tools may
/// not name one tool twice. Either way registration fails AFTER the factory
/// ran: the owner it was handed must still be stopped and cleaned up, since
/// no program will ever exist to do it.
async test "a registration that fails still stops and cleans up its owner" {
  let shadowing : Array[@agent_tool.AgentToolDefinition] = [
    leaf(name="gate", execute=Sync(_ => @agent_tool.respond("mine"))),
  ]
  let repeated : Array[@agent_tool.AgentToolDefinition] = [
    leaf(name="twice", execute=Sync(_ => @agent_tool.respond("a"))),
    leaf(name="twice", execute=Sync(_ => @agent_tool.respond("b"))),
  ]
  for case in [("`gate` is both", shadowing), ("twice", repeated)] {
    let (expected, tools) = case
    let owners : Array[Owner] = []
    let mut stopped = 0
    let mut cleaned = 0
    @async.with_task_group(group => {
      let service = owned_service(group, owner => {
        owners.push(owner)
        owner.on_stop(() => stopped += 1)
        owner.on_close(() => cleaned += 1)
        tools
      })
      try service.register() catch {
        error => assert_true("\{error}".contains(expected))
      } noraise {
        _ => fail("registration must be refused: \{expected}")
      }
      assert_true(service.programs.is_empty())
      // Stopped at once, synchronously, with the failure.
      assert_true(owners is [owner] && owner.is_closed())
      assert_eq(stopped, 1)
      // The next program is unaffected, and does not get the failed one's id.
      // (It fails the same way here; the id is what is being checked.)
      try service.register() catch {
        _ => ()
      } noraise {
        _ => fail("the factory still returns a bad set")
      }
      assert_eq(owners.map(owner => owner.id()), ["program-1", "program-2"])
    })
    // Closing the service joined the cleanup of both abandoned owners.
    assert_eq(stopped, 2)
    assert_eq(cleaned, 2)
  }
}

///|
/// The cleanup of an abandoned owner runs on the session group, which
/// cancels its tasks when it ends. A hook that is waiting at that moment
/// must still finish what it was releasing.
async test "an abandoned owner's cleanup survives the session's shutdown" {
  let mut releasing = false
  let mut released = false
  @async.with_task_group(group => {
    let service = owned_service(group, owner => {
      owner.on_close(() => {
        releasing = true
        // Still waiting when the group ends and cancels its tasks.
        @async.sleep(60)
        released = true
      })
      [leaf(name="gate", execute=Sync(_ => @agent_tool.respond("mine")))]
    })
    try service.register() catch {
      _ => ()
    } noraise {
      _ => fail("a shadowing tool must be refused")
    }
    // Let the cleanup start, and leave while it is mid-wait.
    for _ in 0..<200 {
      if releasing {
        break
      }
      @async.sleep(1)
    }
    assert_true(releasing)
    assert_false(released)
    assert_eq(service.abandoned.length(), 1)
  })
  assert_true(released)
}

///|
/// A stop hook may register a program itself. If that fails too, there are
/// two abandoned owners, the inner one created and stopped while the outer
/// registration is still unwinding. Each cleanup is tracked under its own
/// owner's number, so an explicit close of the service waits for both.
async test "nested failed registrations are each joined by an explicit close" {
  @async.with_task_group(group => {
    let service : Ref[Service?] = Ref(None)
    let mut nested = false
    let mut cleaned = 0
    let ids : Array[String] = []
    service.val = Some(
      owned_service(group, owner => {
        ids.push(owner.id())
        owner.on_stop(() => {
          guard !nested else { return }
          nested = true
          // Fails the same way, from inside the outer registration's stop.
          try service.val.unwrap().register() catch {
            _ => ()
          } noraise {
            _ => ()
          }
        })
        owner.on_close(() => {
          @async.sleep(40)
          cleaned += 1
        })
        [leaf(name="gate", execute=Sync(_ => @agent_tool.respond("mine")))]
      }),
    )
    let service = service.val.unwrap()
    try service.register() catch {
      _ => ()
    } noraise {
      _ => fail("a shadowing tool must be refused")
    }
    assert_eq(ids, ["program-1", "program-2"])
    // Both cleanups are pending, each under its own key.
    assert_eq(service.abandoned.length(), 2)
    assert_eq(cleaned, 0)
    service.close()
    // The close returned only after both had finished.
    assert_eq(cleaned, 2)
    assert_true(service.abandoned.is_empty())
  })
}

///|
/// The program limit is checked before the factory runs, and the factory
/// may register a program itself. If that takes the last place, the outer
/// registration is refused when it comes to be admitted — and its owner,
/// already handed to the factory, is stopped and cleaned up.
async test "a factory that takes the last place leaves none for its own program" {
  @async.with_task_group(group => {
    let service : Ref[Service?] = Ref(None)
    let mut nest = false
    let stopped : Array[String] = []
    let cleaned : Array[String] = []
    service.val = Some(
      owned_service(group, owner => {
        owner.on_stop(() => stopped.push(owner.id()))
        owner.on_close(() => cleaned.push(owner.id()))
        if nest {
          nest = false
          // Succeeds: one place was left, and this takes it.
          ignore(service.val.unwrap().register()) catch {
            _ => ()
          }
        }
        []
      }),
    )
    let service = service.val.unwrap()
    for _ in 0..<(MaxPrograms - 1) {
      ignore(service.register())
    }
    assert_eq(service.programs.length(), MaxPrograms - 1)
    nest = true
    try service.register() catch {
      error => assert_true("\{error}".contains("active programs"))
    } noraise {
      _ => fail("the limit must hold however the last place was taken")
    }
    // The nested program got the last place; the outer one got none.
    assert_eq(service.programs.length(), MaxPrograms)
    // Owner numbers: 1..63 registered first, 64 is the refused outer one,
    // 65 the nested one it let in.
    assert_eq(stopped, ["program-\{MaxPrograms}"])
    service.close()
    assert_true(cleaned.contains("program-\{MaxPrograms}"))
    assert_eq(cleaned.length(), MaxPrograms + 1)
  })
}

///|
/// Failed registrations are not bounded by the program limit — they never
/// become programs — so what they leave behind must not accumulate: a
/// finished cleanup keeps nothing.
async test "finished cleanups of abandoned owners are not retained" {
  @async.with_task_group(group => {
    let mut cleaned = 0
    let service = owned_service(group, owner => {
      owner.on_close(() => {
        @async.sleep(1)
        cleaned += 1
      })
      [leaf(name="gate", execute=Sync(_ => @agent_tool.respond("mine")))]
    })
    for _ in 0..<200 {
      try service.register() catch {
        _ => ()
      } noraise {
        _ => fail("a shadowing tool must be refused")
      }
    }
    // Far more than the 64 programs a session may hold.
    for _ in 0..<2000 {
      if cleaned == 200 {
        break
      }
      @async.sleep(1)
    }
    assert_eq(cleaned, 200)
    assert_true(service.abandoned.is_empty())
    assert_true(service.programs.is_empty())
  })
}

///|
/// Moving to the background keeps the owner. Adoption only tells it the job.
async test "adoption keeps the owner and fills in its job" {
  @async.with_task_group(group => {
    let owners : Array[Owner] = []
    let service = owned_service(group, owner => {
      owners.push(owner)
      [
        leaf(
          name="job",
          concurrent_safe=true,
          execute=Sync(_ => {
            @agent_tool.respond(owner.job().unwrap_or("foreground"))
          }),
        ),
      ]
    })
    let program = service.register()
    defer program.close()
    assert_eq(content(request(program.env(), "job", {})), "foreground")
    program.handoff("bg-7", _ => ())
    assert_eq(content(request(program.env(), "job", {})), "bg-7")
    assert_true(owners is [owner] && owner.id() == "program-1")
    assert_false(owners[0].is_closed())
  })
}

///|
/// Stopping a program ends its owner at once — with no suspension, at the
/// moment the capability is revoked — and closing it waits for whatever the
/// owner's tools left running, before the trace is called final.
async test "stop revokes the owner at once and close joins what it owns" {
  @async.with_task_group(group => {
    let mut stopped = 0
    let mut joining = false
    let mut release = false
    let mut joined = 0
    let owners : Array[Owner] = []
    let service = owned_service(group, owner => {
      owners.push(owner)
      owner.on_stop(() => stopped += 1)
      owner.on_close(() => {
        joining = true
        while !release {
          @async.sleep(2)
        }
        joined += 1
      })
      [leaf(name="start", execute=Sync(_ => @agent_tool.respond("started")))]
    })
    // Whatever happens below, the close hook must be able to finish, or a
    // failed assertion would leave teardown waiting on it forever.
    defer {
      release = true
    }
    let program = service.register()
    assert_eq(content(request(program.env(), "start", {})), "started")
    // The start call has returned; once its handler has unwound, nothing of
    // it is among the active calls a close would join without the hook.
    while !program.active.is_empty() {
      @async.sleep(1)
    }
    program.stop()
    // Synchronous: both are true on the very next line.
    assert_true(owners[0].is_closed())
    assert_eq(stopped, 1)
    // A hook added after the stop runs at once, so a tool that looks late
    // cannot miss it.
    let mut late = false
    owners[0].on_stop(() => late = true)
    assert_true(late)
    let mut closed = false
    let closing = group.spawn(() => {
      program.close()
      closed = true
    })
    // Bounded: a close that skipped the hook must fail here, not hang.
    for _ in 0..<500 {
      if joining || closed {
        break
      }
      @async.sleep(2)
    }
    assert_true(joining)
    @async.sleep(40)
    assert_false(closed)
    release = true
    closing.wait()
    assert_true(closed)
    assert_eq(joined, 1)
    // Stopping again runs no hook twice; closing again waits again, which a
    // close hook must tolerate.
    program.stop()
    assert_eq(stopped, 1)
    program.close()
    assert_eq(joined, 2)
  })
}

///|
/// Session teardown is the same stop and close for every program at once.
async test "session teardown stops and joins every owner" {
  let events : Array[String] = []
  @async.with_task_group(group => {
    let service = owned_service(group, owner => {
      owner.on_stop(() => events.push("stop \{owner.id()}"))
      owner.on_close(() => events.push("close \{owner.id()}"))
      []
    })
    ignore(service.register())
    ignore(service.register())
    service.close()
    // Every capability is revoked before any owner is joined.
    assert_eq(events, [
      "stop program-1", "stop program-2", "close program-1", "close program-2",
    ])
  })
}

///|
/// An owner-bound tool that waits for a person is exempt from the ordinary
/// call deadline and advertised to the script, exactly like a shared one.
async test "an owner-bound approval tool outlives the ordinary deadline" {
  @async.with_timeout(3000, () => {
    @async.with_task_group(group => {
      let service = Service::start(
        group,
        Tools([]),
        owner_tools=_ => {
          [
            leaf(
              name="ask",
              can_request_approval=true,
              execute=Async(_ => {
                @async.sleep(100)
                @agent_tool.respond("asked")
              }),
            ),
            leaf(
              name="slow",
              execute=Async(_ => {
                @async.sleep(100)
                @agent_tool.respond("too late")
              }),
            ),
          ]
        },
        call_timeout_ms=10,
      )
      let program = service.register()
      defer program.close()
      assert_true(
        @json.parse(program.env()["OPENSEEK_PTC"])
        is { "approval_tools": ["ask"], .. },
      )
      // Ten times the deadline, and still answered.
      assert_true(
        request(program.env(), "ask", {})
        is { "is_error": false, "content": "asked", .. },
      )
      // The exemption is the approval flag's, not a side effect of being
      // owner-bound: an ordinary owner-bound tool still meets the deadline.
      assert_true(
        request(program.env(), "slow", {}) is { "is_error": true, .. },
      )
    })
  })
}

///|
/// A program can be stopped while its adoption into the background is still
/// in flight. The job id still reaches the owner, so what the program
/// started can be attributed, and the owner stays stopped.
async test "a job id that arrives after the stop still reaches the owner" {
  @async.with_task_group(group => {
    let owners : Array[Owner] = []
    let service = owned_service(group, owner => {
      owners.push(owner)
      []
    })
    let program = service.register()
    defer program.close()
    program.stop()
    assert_true(owners[0].is_closed())
    assert_true(owners[0].job() is None)
    program.handoff("bg-3", _ => ())
    assert_eq(owners[0].job(), Some("bg-3"))
    assert_true(owners[0].is_closed())
  })
}
