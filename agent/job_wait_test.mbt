///|
fn wait_call_payload(name : String, args : Json) -> String {
  let payload : Json = {
    "choices": [
      {
        "delta": {
          "tool_calls": [
            {
              "index": 0,
              "id": "wait-call",
              "type": "function",
              "function": { "name": name, "arguments": args.stringify() },
            },
          ],
        },
      },
    ],
  }
  payload.stringify()
}

///|
priv enum WaitWake {
  Complete
  UserInput
  GoalChange
  Stop
  Cancel
}

///|
/// A real process held by stdin EOF, with a scripted model. Release is driven
/// after the wait call is durably recorded, not by a wall-clock sleep.
#cfg(not(platform="windows"))
async fn exercise_job_wait(wake : WaitWake) -> Unit {
  @async.with_timeout(10000, () => {
    @async.with_task_group(group => {
      let runtime = @agent_runtime.AgentRuntime()
      let scope = @agent_runtime.AgentTaskScope(group)
      let jobs = @bgjobs.BgJobRuntime(scope, on_job_exit=job => {
        runtime.queue_steer(Notice("JOB-COMPLETE \{job.id}"))
      })
      let (input, release) = @process.write_to_process()
      defer release.close()
      let id = jobs.start(
        program="/bin/cat",
        args=[],
        command="gated result",
        stdin=input,
      )
      let bodies : Array[String] = []
      let responses = [
        wait_call_payload("job_wait", { "job_ids": [id] }),
        wait_call_payload("finish", { "answer": "processed" }),
      ]
      guard goal_check_test_server(group, bodies, responses) is Some(url) else {
        return
      }
      let ready : @async.Queue[Unit] = Queue(kind=Unbounded)
      let mut saved = @agent_session.Session(
        SessionId("job-wait"),
        system_prompt="system",
      )
      let tools = @agent_tool.Tools(
        [@job_wait.definition(), @finish.definition()],
        background_jobs=jobs,
      )
      let task = group.spawn(
        () => {
          @agent.run_turn_in_scope(
            runtime~,
            scope~,
            api_key="test",
            model=Deepseek(V4Flash),
            session=saved,
            task="process the result",
            tools~,
            api_url=url,
            max_steps=3,
            append_item=(session, item) => {
              saved = session.append(item)
              if item is Assistant(message) &&
                message.tool_calls().any(call => call.name == "job_wait") {
                ready.put(())
              }
              saved
            },
          )
        },
        allow_failure=true,
      )
      ready.get()
      // Let the loop enter its wait. This yields cooperatively; no duration is
      // used to arrange completion and no model calls can be made meanwhile.
      @async.pause()
      assert_eq(bodies.length(), 1)
      match wake {
        Complete => {
          release.write("RESULT\n")
          release.close()
        }
        UserInput => runtime.queue_steer(Prompt("NEW-DIRECTION"))
        GoalChange => runtime.queue_steer(Notice("NEW-GOAL"), wake=true)
        Stop => {
          let _ = jobs.stop(id)
        }
        Cancel => task.cancel()
      }
      if wake is Cancel {
        let _ = task.wait() catch { _ => saved }
        assert_eq(bodies.length(), 1)
        assert_true(
          saved.events().iter().any(e => e.item() is Terminal(Interrupted(_))),
        )
        assert_true(
          saved
          .events()
          .iter()
          .any(e => e.item() is Tool(r) && r.content().contains("cancelled")),
        )
      } else {
        let result = task.wait()
        assert_eq(bodies.length(), 2)
        assert_true(
          result.events().peek() is Some(e) &&
          e.item() is Terminal(Finished("processed")),
        )
        match wake {
          Complete => {
            assert_true(bodies[1].contains("JOB-COMPLETE"))
            assert_true(bodies[1].contains("job_completed"))
            assert_true(bodies[1].contains("exit=0"))
            let output_tools = @agent_tool.Tools([@job_output.definition(jobs)])
            let output = @agent_tool.execute_tool_call(
              AgentToolCall(
                ToolCall(
                  id="read-result",
                  name="job_output",
                  arguments="{\"job_id\":\"\{id}\"}",
                ),
              ),
              output_tools,
            )
            assert_true(
              output is Respond(out) && out.content.contains("RESULT"),
            )
          }
          UserInput => {
            assert_true(bodies[1].contains("NEW-DIRECTION"))
            assert_true(bodies[1].contains("user_input"))
            assert_true(jobs.snapshot(id) is Some(job) && job.status is Running)
          }
          GoalChange => {
            assert_true(bodies[1].contains("NEW-GOAL"))
            assert_true(bodies[1].contains("user_input"))
            assert_true(jobs.snapshot(id) is Some(job) && job.status is Running)
          }
          Stop => assert_true(bodies[1].contains("stopped"))
          Cancel => ()
        }
        assert_eq(
          result.events().filter(e => e.item() is User(_)).length(),
          if wake is UserInput {
            2
          } else {
            1
          },
        )
      }
      let _ = jobs.stop(id)
    })
  })
}

///|
#cfg(not(platform="windows"))
async test "job_wait completion resumes the same turn with its notice" {
  exercise_job_wait(Complete)
}

///|
#cfg(not(platform="windows"))
async test "job_wait user input resumes without stopping its job" {
  exercise_job_wait(UserInput)
}

///|
#cfg(not(platform="windows"))
async test "job_wait requested stop wakes without a completion notice" {
  exercise_job_wait(Stop)
}

///|
#cfg(not(platform="windows"))
async test "job_wait cancellation seals the turn without another model request" {
  exercise_job_wait(Cancel)
}

///|
#cfg(not(platform="windows"))
async fn exercise_plain_finish(existing : Bool) -> Unit {
  @async.with_task_group(group => {
    let runtime = @agent_runtime.AgentRuntime()
    let scope = @agent_runtime.AgentTaskScope(group)
    let jobs = @bgjobs.BgJobRuntime(scope)
    let (input, release) = @process.write_to_process()
    defer release.close()
    async fn start_job() -> Unit {
      let _ = jobs.start(
        program="/bin/cat",
        args=[],
        command="long lived server",
        stdin=input,
      )
    }
    if existing {
      start_job()
    }
    let bodies : Array[String] = []
    guard goal_check_test_server(
        group,
        bodies,
        [
          final_answer_payload("server started"),
          wait_call_payload("finish", { "answer": "intentionally done" }),
        ],
        on_request=() => if !existing && bodies.length() == 1 { start_job() },
      )
      is Some(url) else {
      return
    }
    let result = @agent.run_turn_in_scope(
      runtime~,
      scope~,
      api_key="test",
      model=Deepseek(V4Flash),
      session=Session(SessionId("finish-live-job"), system_prompt="system"),
      task="start server",
      api_url=url,
      max_steps=3,
      tools=Tools(
        [@job_wait.definition(), @finish.definition()],
        background_jobs=jobs,
      ),
      append_item=(session, item) => session.append(item),
    )
    guard jobs.list() is [job] else { fail("missing job") }
    let id = job.id
    if existing {
      assert_eq(bodies.length(), 1)
      assert_true(
        result.events().peek() is Some(e) &&
        e.item() is Terminal(Finished("server started")),
      )
    } else {
      assert_eq(bodies.length(), 2)
      assert_true(bodies[1].contains("Background jobs still need a decision"))
      assert_true(bodies[1].contains(id))
      assert_true(
        result.events().peek() is Some(e) &&
        e.item() is Terminal(Finished("intentionally done")),
      )
    }
    assert_true(jobs.snapshot(id) is Some(job) && job.status is Running)
    let _ = jobs.stop(id)
  })
}

///|
#cfg(not(platform="windows"))
async test "plain text with a new job asks for a decision and explicit finish is respected" {
  exercise_plain_finish(false)
}

///|
#cfg(not(platform="windows"))
async test "a preexisting server does not add a finish reminder to a later turn" {
  exercise_plain_finish(true)
}

///|
#cfg(not(platform="windows"))
async test "a user goal notice wakes job_wait without becoming a user message" {
  exercise_job_wait(GoalChange)
}

///|
async test "job_wait unknown ids return a tool error and let the model recover" {
  @async.with_task_group(group => {
    let runtime = @agent_runtime.AgentRuntime()
    let scope = @agent_runtime.AgentTaskScope(group)
    let jobs = @bgjobs.BgJobRuntime(scope)
    let bodies : Array[String] = []
    guard goal_check_test_server(group, bodies, [
        wait_call_payload("job_wait", { "job_ids": ["missing"] }),
        final_answer_payload("recovered"),
      ])
      is Some(url) else {
      return
    }
    let result = @agent.run_turn_in_scope(
      runtime~,
      scope~,
      api_key="test",
      model=Deepseek(V4Flash),
      session=Session(SessionId("wait-invalid"), system_prompt="system"),
      task="test",
      api_url=url,
      max_steps=2,
      tools=Tools([@job_wait.definition()], background_jobs=jobs),
      append_item=(session, item) => session.append(item),
    )
    assert_true(bodies[1].contains("no background job with id missing"))
    assert_true(
      result.events().peek() is Some(e) &&
      e.item() is Terminal(Finished("recovered")),
    )
  })
}

///|
async test "job_wait in the last model step records an error rather than waiting" {
  @async.with_task_group(group => {
    let bodies : Array[String] = []
    guard goal_check_test_server(group, bodies, [
        wait_call_payload("job_wait", { "job_ids": ["bg-1"] }),
      ])
      is Some(url) else {
      return
    }
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test",
      model=Deepseek(V4Flash),
      session=Session(SessionId("wait-budget"), system_prompt="system"),
      task="test",
      api_url=url,
      max_steps=1,
      tools=Tools([@job_wait.definition()]),
      append_item=(session, item) => session.append(item),
    )
    assert_eq(bodies.length(), 1)
    assert_true(
      result
      .events()
      .iter()
      .any(e => e.item() is Tool(r) && r.content().contains("budget")),
    )
    assert_true(
      result.events().peek() is Some(e) &&
      e.item() is Terminal(Failed("max steps exhausted")),
    )
  })
}

///|
async test "mixed job_wait batch returns an error and executes the following tool" {
  @async.with_task_group(group => {
    let bodies : Array[String] = []
    // Both arguments decode, so only the batch rule can reject the wait.
    let payload : Json = {
      "choices": [
        {
          "delta": {
            "tool_calls": [
              {
                "index": 0,
                "id": "w",
                "type": "function",
                "function": {
                  "name": "job_wait",
                  "arguments": "{\"job_ids\":[\"bg-1\"]}",
                },
              },
              {
                "index": 1,
                "id": "f",
                "type": "function",
                "function": {
                  "name": "finish",
                  "arguments": "{\"answer\":\"done\"}",
                },
              },
            ],
          },
        },
      ],
    }
    guard goal_check_test_server(group, bodies, [payload.stringify()])
      is Some(url) else {
      return
    }
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test",
      model=Deepseek(V4Flash),
      session=Session(SessionId("wait-mixed"), system_prompt="system"),
      task="test",
      api_url=url,
      max_steps=2,
      tools=Tools([@job_wait.definition(), @finish.definition()]),
      append_item=(session, item) => session.append(item),
    )
    assert_eq(bodies.length(), 1)
    assert_true(
      result
      .events()
      .iter()
      .any(e => e.item() is Tool(r) && r.content().contains("alone")),
    )
    assert_eq(result.events().filter(e => e.item() is Tool(_)).length(), 2)
    assert_true(
      result.events().peek() is Some(e) &&
      e.item() is Terminal(Finished("done")),
    )
  })
}
