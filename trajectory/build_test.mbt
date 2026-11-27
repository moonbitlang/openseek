///|
/// First span matching `pred`, or `None`. Kept local so the assertions read
/// like "the span that says X" instead of an index.
fn find_span(
  spans : Array[@trajectory.TrajectorySpan],
  pred : (@trajectory.TrajectorySpan) -> Bool,
) -> @trajectory.TrajectorySpan? {
  for span in spans {
    if pred(span) {
      return Some(span)
    }
  }
  None
}

///|
/// All spans matching `pred`.
fn select_spans(
  spans : Array[@trajectory.TrajectorySpan],
  pred : (@trajectory.TrajectorySpan) -> Bool,
) -> Array[@trajectory.TrajectorySpan] {
  let out : Array[@trajectory.TrajectorySpan] = []
  for span in spans {
    if pred(span) {
      out.push(span)
    }
  }
  out
}

///|
/// Serialize a session to the append-only text a session file carries, so the
/// tests feed the builder exactly what the store writes.
fn session_text(session : @agent_session.Session) -> String {
  let out = StringBuilder()
  for event in session.events() {
    let line = ToJson::to_json(event).stringify()
    out <+ "\{line}\n"
  }
  out.to_string()
}

///|
/// One-turn session: a prompt, one model call that asks for a tool, the tool's
/// result, a second model call with usage, and a finished terminal.
fn two_step_session(id : String) -> @agent_session.Session {
  let t0 = 1_000L
  @agent_session.Session(SessionId(id), system_prompt="be brief")
  .append(User(UserMessage(Content([Text("list the files")]))), unix_ms=t0)
  .append(
    Assistant(
      AssistantMessage("I'll look.", tool_calls=[
        ToolCall(id="call_1", name="shell", arguments="{\"cmd\":\"ls\"}"),
      ]),
    ),
    unix_ms=t0 + 400L,
  )
  .append(
    Tool(
      ToolResult(
        tool_call_id="call_1",
        tool_name="shell",
        content=[Text("README.md")],
        brief="ran ls → 1 file",
      ),
    ),
    unix_ms=t0 + 900L,
  )
  .append(
    Assistant(AssistantMessage("There is one file.")),
    unix_ms=t0 + 1_500L,
  )
  .append(Terminal(Finished("There is one file.")), unix_ms=t0 + 1_600L)
}

///|
test "a session becomes one turn holding a model call and a tool call" {
  let log : @trajectory.SessionLog = {
    id: "run",
    text: session_text(two_step_session("run")),
    title: None,
  }
  let trajectory = @trajectory.build_trajectory("run", [log])
  assert_eq(trajectory.stats.turn_count, 1)
  assert_eq(trajectory.stats.session_count, 1)
  assert_false(trajectory.live)
  // run, turn, model call, tool call, model call
  assert_eq(trajectory.spans.length(), 5)
  let run = trajectory.spans[0]
  assert_true(run.kind is Run)
  assert_eq(run.depth, 0)
  let turn = trajectory.spans[1]
  assert_true(turn.kind is Turn)
  assert_eq(turn.parent_id, Some("run:run"))
  assert_eq(turn.depth, 1)
  assert_true(turn.status is Succeeded)
  assert_eq(turn.started_at_ms, 1_000L)
  assert_eq(turn.ended_at_ms, Some(2_600L))
  let first_call = trajectory.spans[2]
  assert_true(first_call.kind is LlmCall)
  assert_eq(first_call.parent_id, Some("run:turn:1"))
  // The model call is read backwards from its response: the turn's input at
  // 1000 to the assistant event at 1400.
  assert_eq(first_call.started_at_ms, 1_000L)
  assert_eq(first_call.ended_at_ms, Some(1_400L))
  let tool = trajectory.spans[3]
  assert_true(tool.kind is ToolExec)
  assert_eq(tool.label, "shell")
  assert_eq(tool.started_at_ms, 1_400L)
  assert_eq(tool.ended_at_ms, Some(1_900L))
  assert_true(tool.status is Succeeded)
  assert_eq(trajectory.stats.llm_ms, 1_000L)
  assert_eq(trajectory.stats.tool_ms, 500L)
  assert_eq(trajectory.t0_ms, 1_000L)
  assert_eq(trajectory.t_end_ms, 2_600L)
}

///|
test "a failed tool result marks its span failed" {
  let text = session_text(
    @agent_session.Session(SessionId("run"), system_prompt="")
    .append(User(UserMessage(Content([Text("edit")]))), unix_ms=10L)
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(id="c1", name="edit", arguments="{}"),
        ]),
      ),
      unix_ms=20L,
    )
    .append(
      Tool(
        ToolResult(
          tool_call_id="c1",
          tool_name="edit",
          content=[Text("no such file")],
          is_error=true,
        ),
      ),
      unix_ms=30L,
    )
    .append(Terminal(Failed("cannot continue")), unix_ms=40L),
  )
  let trajectory = @trajectory.build_trajectory("run", [
    { id: "run", text, title: None, },
  ])
  let tool = trajectory.spans[3]
  assert_true(tool.status is Failed)
  let turn = trajectory.spans[1]
  assert_true(turn.status is Failed)
  assert_true(turn.metadata.get("message") is Some(String(_)))
}

///|
test "a tool call with no result is interrupted when the turn ends" {
  let text = session_text(
    @agent_session.Session(SessionId("run"), system_prompt="")
    .append(User(UserMessage(Content([Text("go")]))), unix_ms=10L)
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(id="c1", name="shell", arguments="{}"),
        ]),
      ),
      unix_ms=20L,
    )
    .append(Terminal(Interrupted("stopped")), unix_ms=100L),
  )
  let trajectory = @trajectory.build_trajectory("run", [
    { id: "run", text, title: None, },
  ])
  let tool = trajectory.spans[3]
  assert_true(tool.status is Interrupted)
  assert_eq(tool.ended_at_ms, Some(100L))
}

///|
test "a steer joins the turn it lands in and leaves a marker" {
  let text = session_text(
    @agent_session.Session(SessionId("run"), system_prompt="")
    .append(User(UserMessage(Content([Text("start")]))), unix_ms=10L)
    .append(User(UserMessage(Content([Text("also check tests")]))), unix_ms=20L)
    .append(Assistant(AssistantMessage("ok")), unix_ms=30L)
    .append(Terminal(Finished("ok")), unix_ms=40L),
  )
  let trajectory = @trajectory.build_trajectory("run", [
    { id: "run", text, title: None, },
  ])
  // One turn, one model call, one steer marker — a steer never opens a turn.
  assert_eq(trajectory.stats.turn_count, 1)
  let steer = trajectory.spans[2]
  assert_true(steer.kind is Milestone)
  assert_true(steer.tag is Some(Steer))
}

///|
test "a context yield closes the turn as yielded" {
  let text = session_text(
    @agent_session.Session(SessionId("run"), system_prompt="")
    .append(User(UserMessage(Content([Text("long task")]))), unix_ms=10L)
    .append(Assistant(AssistantMessage("part one")), unix_ms=20L)
    .append(
      Terminal(ContextYield("[context ceiling] checkpointed")),
      unix_ms=30L,
    ),
  )
  let trajectory = @trajectory.build_trajectory("run", [
    { id: "run", text, title: None, },
  ])
  let turn = trajectory.spans[1]
  assert_true(turn.status is Yielded)
  let marker = trajectory.spans[3]
  assert_true(marker.tag is Some(ContextYield))
}

///|
test "a compaction summary is a milestone on the turn" {
  let text = session_text(
    @agent_session.Session(SessionId("run"), system_prompt="")
    .append(User(UserMessage(Content([Text("go")]))), unix_ms=10L)
    .append(Assistant(AssistantMessage("step")), unix_ms=20L)
    .append(
      Summary(SessionSummary(content="covered", from_sequence=1, to_sequence=2)),
      unix_ms=30L,
    )
    .append(Terminal(Finished("done")), unix_ms=40L),
  )
  let trajectory = @trajectory.build_trajectory("run", [
    { id: "run", text, title: None, },
  ])
  let marker = trajectory.spans[3]
  assert_true(marker.kind is Milestone)
  assert_true(marker.tag is Some(Compaction))
  assert_eq(marker.started_at_ms, 30L)
}

///|
test "sub-run ids name their parent, and stacked suffixes name the nearest" {
  assert_eq(@trajectory.parent_session_of("run"), None)
  assert_eq(@trajectory.parent_session_of("run-sr-1"), Some("run"))
  assert_eq(@trajectory.parent_session_of("run-sr-1-sr-2"), Some("run-sr-1"))
  assert_eq(@trajectory.parent_session_of("run-sr-"), None)
  assert_eq(@trajectory.parent_session_of("run-sr-x"), None)
  assert_eq(@trajectory.parent_session_of("my-sr-7"), Some("my"))
  assert_eq(@trajectory.session_depth_of("run"), 0)
  assert_eq(@trajectory.session_depth_of("run-sr-1"), 1)
  assert_eq(@trajectory.session_depth_of("run-sr-1-sr-2"), 2)
}

///|
/// A parent session that spawns one child through a `subagent` call: the call
/// opens at 1_000 and its result lands at 5_000, while the child writes its
/// first event at 1_800.
fn parent_with_child() -> Array[@trajectory.SessionLog] {
  let parent_text = session_text(
    @agent_session.Session(SessionId("run"), system_prompt="")
    .append(User(UserMessage(Content([Text("delegate")]))), unix_ms=500L)
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(
            id="call_spawn",
            name="subagent",
            arguments="{\"description\":\"scout\"}",
          ),
        ]),
      ),
      unix_ms=1_000L,
    )
    .append(
      Tool(
        ToolResult(tool_call_id="call_spawn", tool_name="subagent", content=[
          Text("found 3 files"),
        ]),
      ),
      unix_ms=5_000L,
    )
    .append(Assistant(AssistantMessage("done")), unix_ms=6_000L)
    .append(Terminal(Finished("done")), unix_ms=6_100L),
  )
  let child_text = session_text(two_step_session("run-sr-1"))
  // Shift the child's clock to sit inside the parent's spawn call.
  let shifted = child_text.replace_all(old="\"ts\":1000", new="\"ts\":1800")
  [
    { id: "run", text: parent_text, title: None, },
    { id: "run-sr-1", text: shifted, title: Some("scout"), },
  ]
}

///|
test "a child session hangs under the step that spawned it" {
  let trajectory = @trajectory.build_trajectory("run", parent_with_child())
  assert_eq(trajectory.stats.session_count, 2)
  let spawn = find_span(trajectory.spans, span => {
    span.label.has_prefix("subagent")
  })
  guard spawn is Some(spawn) else { fail("no subagent span") }
  let child_turn = find_span(trajectory.spans, span => {
    span.session_id == "run-sr-1" && span.kind is Turn
  })
  guard child_turn is Some(child_turn) else { fail("no child turn") }
  assert_eq(child_turn.parent_id, Some(spawn.id))
  assert_eq(child_turn.title, "scout")
  // run → turn → the spawning call → the child's turn
  assert_eq(child_turn.depth, 3)
  // This fixture's spawn result names no session, so the mount is inferred and
  // says so on the lane's first turn.
  assert_true(child_turn.metadata.get("mount") is Some(String("time_window")))
}

///|
test "a spawn result that names the child records an exact mount" {
  // The same run, with the child session written into the tool result — the
  // exact mount, and no guessing even when two children start at once.
  let logs = parent_with_child()
  let logs = [
    for log in logs => {
      if log.id == "run" {
        {
          ..log,
          text: log.text.replace_all(
            old="\"content\":\"found 3 files\"",
            new="\"content\":\"found 3 files\",\"data\":{\"session\":\"run-sr-1\"}",
          ),
        }
      } else {
        log
      }
    }
  ]
  let trajectory = @trajectory.build_trajectory("run", logs)
  let child_turn = find_span(trajectory.spans, span => {
    span.session_id == "run-sr-1" && span.kind is Turn
  })
  guard child_turn is Some(child_turn) else { fail("no child turn") }
  assert_true(child_turn.metadata.get("mount") is Some(String("tool_result")))
  let spawn = find_span(trajectory.spans, span => {
    span.label.has_prefix("subagent")
  })
  guard spawn is Some(spawn) else { fail("no subagent span") }
  assert_eq(child_turn.parent_id, Some(spawn.id))
}

///|
test "a mbtx run that moved to the background gets a job span" {
  let text = session_text(
    @agent_session.Session(SessionId("run"), system_prompt="")
    .append(User(UserMessage(Content([Text("build")]))), unix_ms=10L)
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(id="c1", name="mbtx", arguments="{\"source\":\"build\"}"),
        ]),
      ),
      unix_ms=20L,
    )
    .append(
      Tool(
        ToolResult(tool_call_id="c1", tool_name="mbtx", content=[
          Text(
            "moved to the background as job job-9 (nothing was lost; read its output with job_output)",
          ),
        ]),
      ),
      unix_ms=120L,
    )
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(
            id="c2",
            name="job_wait",
            arguments="{\"job_ids\":[\"job-9\"]}",
          ),
        ]),
      ),
      unix_ms=130L,
    )
    .append(
      Tool(
        ToolResult(tool_call_id="c2", tool_name="job_wait", content=[
          Text("job job-9 exited 0"),
        ]),
      ),
      unix_ms=9_000L,
    )
    .append(Terminal(Finished("built")), unix_ms=9_100L),
  )
  let trajectory = @trajectory.build_trajectory("run", [
    { id: "run", text, title: None, },
  ])
  let job = find_span(trajectory.spans, span => span.kind is BackgroundJob)
  guard job is Some(job) else { fail("no background job span") }
  assert_eq(job.job_id, Some("job-9"))
  // The wait that observed the job end closes it.
  assert_eq(job.ended_at_ms, Some(9_000L))
  assert_true(job.status is Succeeded)
  let wait = find_span(trajectory.spans, span => span.kind is JobWait)
  guard wait is Some(wait) else { fail("no wait span") }
  assert_eq(wait.job_id, Some("job-9"))
  assert_eq(trajectory.stats.wait_ms, 8_870L)
}

///|
test "nested PTC calls hang under the script span as untimed markers" {
  let calls : Array[Json] = [
    { "name": "web_search", "arguments": { "q": "x" }, "status": "done" },
    { "name": "edit", "arguments": {}, "status": "interrupted" },
  ]
  let data : Map[String, Json] = { "ptc_calls": Json(calls) }
  let text = session_text(
    @agent_session.Session(SessionId("run"), system_prompt="")
    .append(User(UserMessage(Content([Text("script")]))), unix_ms=10L)
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(id="c1", name="mbtx", arguments="{}"),
        ]),
      ),
      unix_ms=20L,
    )
    .append(
      Tool(
        ToolResult(
          tool_call_id="c1",
          tool_name="mbtx",
          content=[Text("ok")],
          data=Json::object(data),
        ),
      ),
      unix_ms=400L,
    )
    .append(Terminal(Finished("ok")), unix_ms=500L),
  )
  let trajectory = @trajectory.build_trajectory("run", [
    { id: "run", text, title: None, },
  ])
  let script = find_span(trajectory.spans, span => span.kind is WorkflowScript)
  guard script is Some(script) else { fail("no script span") }
  let calls = select_spans(trajectory.spans, span => span.kind is PtcToolCall)
  assert_eq(calls.length(), 2)
  assert_eq(calls[0].parent_id, Some(script.id))
  assert_eq(calls[0].label, "ptc: web_search")
  assert_true(calls[0].status is Succeeded)
  assert_true(calls[1].status is Interrupted)
  assert_true(calls[0].metadata.get("timing") is Some(String("unknown")))
}

///|
test "the trace encodes to one JSON document with every span" {
  let log : @trajectory.SessionLog = {
    id: "run",
    text: session_text(two_step_session("run")),
    title: None,
  }
  let json = @trajectory.build_trajectory("run", [log]).to_json()
  guard json
    is {
      "root_session_id": String("run"),
      "t0_ms": Number(_, ..),
      "t_end_ms": Number(_, ..),
      "live": False,
      "spans": Array(spans),
      "stats": { "turn_count": Number(_, ..), "critical_path": Array(path), .. },
      ..
    } else {
    fail("unexpected trace shape: \{json.stringify()}")
  }
  assert_eq(spans.length(), 5)
  assert_true(path.length() >= 2)
  guard spans[2]
    is {
      "kind": String("llm"),
      "status": String("succeeded"),
      "metadata": Object(_),
      ..
    } else {
    fail("unexpected span shape")
  }
}

///|
test "an unrelated session in the same directory is ignored" {
  let trajectory = @trajectory.build_trajectory("run", [
    { id: "run", text: session_text(two_step_session("run")), title: None, },
    { id: "other", text: session_text(two_step_session("other")), title: None, },
  ])
  assert_eq(trajectory.stats.session_count, 1)
}

///|
test "a running session reports live and leaves spans open" {
  let text = session_text(
    @agent_session.Session(SessionId("run"), system_prompt="")
    .append(User(UserMessage(Content([Text("work")]))), unix_ms=10L)
    .append(Assistant(AssistantMessage("starting")), unix_ms=60L),
  )
  let trajectory = @trajectory.build_trajectory("run", [
    { id: "run", text, title: None, },
  ])
  assert_true(trajectory.live)
  let turn = trajectory.spans[1]
  assert_eq(turn.ended_at_ms, None)
  assert_true(turn.status is Running)
  assert_true(trajectory.spans[0].status is Running)
}

///|
test "a trace round-trips through its JSON encoding" {
  let trajectory = @trajectory.build_trajectory("run", [
    {
      id: "run",
      text: session_text(two_step_session("run")),
      title: Some("demo run"),
    },
  ])
  let json = trajectory.to_json()
  let back = @trajectory.parse_trajectory(json)
  assert_eq(back.root_session_id, "run")
  assert_eq(back.t0_ms, trajectory.t0_ms)
  assert_eq(back.t_end_ms, trajectory.t_end_ms)
  assert_eq(back.spans.length(), trajectory.spans.length())
  assert_eq(back.stats.turn_count, trajectory.stats.turn_count)
  assert_eq(back.sessions[0].title, "demo run")
  let pair = (trajectory.spans[3], back.spans[3])
  assert_eq(pair.0.id, pair.1.id)
  assert_true(pair.1.kind is ToolExec)
  assert_true(pair.1.metadata.get("brief") is Some(_))
}

///|
test "an unknown span kind is skipped instead of failing the trace" {
  let text =
    #|{"root_session_id":"run","t0_ms":0,"t_end_ms":10,"live":false,
    #|"sessions":[],"stats":{},
    #|"spans":[
    #|{"id":"a","session_id":"run","title":"main","depth":0,"kind":"run",
    #| "status":"succeeded","label":"run","started_at_ms":0,"ended_at_ms":10},
    #|{"id":"b","session_id":"run","title":"main","depth":1,
    #| "kind":"future-kind","status":"succeeded","label":"x","started_at_ms":0}]}
  let trace = @trajectory.parse_trajectory(@json.parse(text))
  assert_eq(trace.spans.length(), 1)
}

///|
test "a lane title keeps only the prompt's first line" {
  assert_eq(
    @trajectory.lane_title("Fix the failing test\nand then report back"),
    "Fix the failing test",
  )
  assert_eq(@trajectory.lane_title("  padded  "), "padded")
  let long = "x".repeat(80)
  assert_eq(@trajectory.lane_title(long).length(), 61)
  assert_eq(@trajectory.lane_title(""), "")
}

///|
test "the headline number is the longest step, not a sum of envelopes" {
  let trajectory = @trajectory.build_trajectory("run", [
    { id: "run", text: session_text(two_step_session("run")), title: None, },
  ])
  // The second model call (1900→2500) is the longest measured step. Summing
  // the nested envelopes instead reported 1600 ms of double-counted clock.
  assert_eq(trajectory.stats.critical_path_ms, 600L)
  guard trajectory.stats.critical_path.last() is Some(leaf) else {
    fail("the chain must end at the step it reports")
  }
  assert_true(leaf.contains(":span:"))
}

///|
test "the headline number is the widest step, even when it has children" {
  // The spawning call (1_000 -> 5_000) is the widest step of this run; the
  // child's own longest step (600 ms) happens inside it. Reporting the deepest
  // leaf of the heaviest chain answered 600 for a run that spent four seconds
  // on one call.
  let trajectory = @trajectory.build_trajectory("run", parent_with_child())
  assert_eq(trajectory.stats.critical_path_ms, 4_000L)
  let spawn = find_span(trajectory.spans, span => {
    span.label.has_prefix("subagent")
  })
  guard spawn is Some(spawn) else { fail("no subagent span") }
  // The chain ends at the step it reports, not at the sliver below it.
  assert_eq(trajectory.stats.critical_path.last(), Some(spawn.id))
}

///|
test "an open background job counts the time it has already run" {
  let text = session_text(
    @agent_session.Session(SessionId("run"), system_prompt="")
    .append(User(UserMessage(Content([Text("build")]))), unix_ms=10L)
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(id="c1", name="mbtx", arguments="{\"source\":\"build\"}"),
        ]),
      ),
      unix_ms=20L,
    )
    .append(
      Tool(
        ToolResult(tool_call_id="c1", tool_name="mbtx", content=[
          Text("moved to the background as job job-9 (nothing was lost)"),
        ]),
      ),
      unix_ms=120L,
    )
    .append(Terminal(Finished("built")), unix_ms=200L),
  )
  let trajectory = @trajectory.build_trajectory("run", [
    { id: "run", text, title: None, },
  ])
  let job = find_span(trajectory.spans, span => span.kind is BackgroundJob)
  guard job is Some(job) else { fail("no background job span") }
  assert_true(job.ended_at_ms is None)
  // It has been running from the call that started it (20) to the last event
  // (200). Reporting nothing would contradict the bar on screen.
  assert_eq(trajectory.stats.job_ms, 180L)
}

///|
test "job_wait closes every job it names, each with its own outcome" {
  let text = session_text(
    @agent_session.Session(SessionId("run"), system_prompt="")
    .append(User(UserMessage(Content([Text("build both")]))), unix_ms=10L)
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(id="c1", name="mbtx", arguments="{\"source\":\"one\"}"),
          ToolCall(id="c2", name="mbtx", arguments="{\"source\":\"two\"}"),
        ]),
      ),
      unix_ms=20L,
    )
    .append(
      Tool(
        ToolResult(tool_call_id="c1", tool_name="mbtx", content=[
          Text("moved to the background as job job-1 (nothing was lost)"),
        ]),
      ),
      unix_ms=120L,
    )
    .append(
      Tool(
        ToolResult(tool_call_id="c2", tool_name="mbtx", content=[
          Text("moved to the background as job job-2 (nothing was lost)"),
        ]),
      ),
      unix_ms=130L,
    )
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(
            id="c3",
            name="job_wait",
            arguments="{\"job_ids\":[\"job-1\",\"job-2\"]}",
          ),
        ]),
      ),
      unix_ms=200L,
    )
    .append(
      Tool(
        ToolResult(tool_call_id="c3", tool_name="job_wait", content=[
          Text(
            "job_wait reason=job_completed\njob-1 exit=0\njob-2 exit=3\nRead output with job_output.",
          ),
        ]),
      ),
      unix_ms=900L,
    )
    .append(Terminal(Finished("done")), unix_ms=950L),
  )
  let trajectory = @trajectory.build_trajectory("run", [
    { id: "run", text, title: None, },
  ])
  let jobs = select_spans(trajectory.spans, span => span.kind is BackgroundJob)
  assert_eq(jobs.length(), 2)
  // Both jobs ended when the wait observed them, not when one of them did.
  assert_eq(jobs[0].ended_at_ms, Some(900L))
  assert_eq(jobs[1].ended_at_ms, Some(900L))
  // A nonzero exit is a failure, even though the wait itself succeeded.
  assert_true(jobs[0].status is Succeeded)
  assert_true(jobs[1].status is Failed)
  assert_eq(trajectory.stats.wait_ms, 700L)
}

///|
test "two children spawned in one batch mount on their own calls" {
  let parent_text = session_text(
    @agent_session.Session(SessionId("run"), system_prompt="")
    .append(User(UserMessage(Content([Text("delegate twice")]))), unix_ms=500L)
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(id="c1", name="subagent", arguments="{\"label\":\"one\"}"),
          ToolCall(id="c2", name="subagent", arguments="{\"label\":\"two\"}"),
        ]),
      ),
      unix_ms=1_000L,
    )
    .append(
      Tool(
        ToolResult(
          tool_call_id="c1",
          tool_name="subagent",
          content=[Text("started")],
          data={ "job_id": "job-1", "session": "run-sr-1" },
        ),
      ),
      unix_ms=5_000L,
    )
    .append(
      Tool(
        ToolResult(
          tool_call_id="c2",
          tool_name="subagent",
          content=[Text("started")],
          data={ "job_id": "job-2", "session": "run-sr-2" },
        ),
      ),
      unix_ms=5_100L,
    )
    .append(Terminal(Finished("done")), unix_ms=6_000L),
  )
  let child_one = session_text(two_step_session("run-sr-1")).replace_all(
    old="\"ts\":1000",
    new="\"ts\":1800",
  )
  let child_two = session_text(two_step_session("run-sr-2")).replace_all(
    old="\"ts\":1000",
    new="\"ts\":1900",
  )
  let trajectory = @trajectory.build_trajectory("run", [
    { id: "run", text: parent_text, title: None, },
    { id: "run-sr-1", text: child_one, title: Some("one"), },
    { id: "run-sr-2", text: child_two, title: Some("two"), },
  ])
  let spawns = select_spans(trajectory.spans, span => {
    span.kind is ToolExec && span.label.has_prefix("subagent")
  })
  assert_eq(spawns.length(), 2)
  let turn_of = (session : String) => {
    find_span(trajectory.spans, span => {
      span.session_id == session && span.kind is Turn
    })
  }
  guard turn_of("run-sr-1") is Some(one) && turn_of("run-sr-2") is Some(two) else {
    fail("both child turns must exist")
  }
  // Both children start inside both tool spans, so the time-window heuristic
  // used to mount them on the same (later) call. The result's own `session`
  // field is exact.
  assert_eq(one.parent_id, Some(spawns[0].id))
  assert_eq(two.parent_id, Some(spawns[1].id))
}

///|
test "a span remembers the event it was read from" {
  let trajectory = @trajectory.build_trajectory("run", [
    { id: "run", text: session_text(two_step_session("run")), title: None, },
  ])
  let turn = find_span(trajectory.spans, span => span.kind is Turn)
  let call = find_span(trajectory.spans, span => span.kind is LlmCall)
  let tool = find_span(trajectory.spans, span => span.kind is ToolExec)
  guard turn is Some(turn) && call is Some(call) && tool is Some(tool) else {
    fail("expected a turn, a model call and a tool call")
  }
  // two_step_session writes user=1, assistant=2, tool result=3. A tool span
  // keeps the call's position: the result only closes it, and the call is
  // where a reader wants to land.
  assert_eq(turn.sequence, Some(1))
  assert_eq(call.sequence, Some(2))
  assert_eq(tool.sequence, Some(2))
  // The synthetic run span belongs to no single event.
  assert_eq(trajectory.spans[0].sequence, None)
  // And the position survives the wire, so the viewer can open it.
  let back = @trajectory.parse_trajectory(trajectory.to_json())
  let again = find_span(back.spans, span => span.kind is ToolExec)
  assert_eq(again.unwrap().sequence, Some(2))
}

///|
test "activity counts calls per slice, and failures separately" {
  let trajectory = @trajectory.build_trajectory("run", [
    { id: "run", text: session_text(two_step_session("run")), title: None, },
  ])
  let whole = @trajectory.activity_of(trajectory, 10_000L, buckets=1)
  assert_eq(whole.length(), 1)
  assert_eq(whole[0].llm, 2)
  assert_eq(whole[0].tool, 1)
  assert_eq(whole[0].failed, 0)
  // More slices than calls: every call still lands in exactly one slice.
  let many = @trajectory.activity_of(trajectory, 10_000L, buckets=40)
  assert_eq(many.length(), 40)
  let mut llm = 0
  for bucket in many {
    llm += bucket.llm
  }
  assert_eq(llm, 2)
  // True scale counts the same calls; only the widths differ.
  let scaled = @trajectory.activity_of(
    trajectory,
    10_000L,
    buckets=40,
    compress=false,
  )
  let mut tools = 0
  for bucket in scaled {
    tools += bucket.tool
  }
  assert_eq(tools, 1)
}

///|
test "a timed PTC call is drawn as its own interval" {
  // The PTC server stamps a call when it opens and when it ends, in the same
  // unix milliseconds the session log uses for its events.
  let recorded : Array[Json] = [
    {
      "name": "web_search",
      "arguments": { "q": "x" },
      "status": "done",
      "started_at_ms": 100,
      "ended_at_ms": 250,
    },
    // Still open when the program stopped: the script's end bounds it.
    {
      "name": "edit",
      "arguments": {},
      "status": "running",
      "started_at_ms": 300,
    },
    // A trace written before calls were timed keeps its marker.
    { "name": "older", "arguments": {}, "status": "done" },
  ]
  let data : Map[String, Json] = { "ptc_calls": Json(recorded) }
  let text = session_text(
    @agent_session.Session(SessionId("run"), system_prompt="")
    .append(User(UserMessage(Content([Text("script")]))), unix_ms=10L)
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(id="c1", name="mbtx", arguments="{}"),
        ]),
      ),
      unix_ms=20L,
    )
    .append(
      Tool(
        ToolResult(
          tool_call_id="c1",
          tool_name="mbtx",
          content=[Text("ok")],
          data=Json::object(data),
        ),
      ),
      unix_ms=400L,
    )
    .append(Terminal(Finished("ok")), unix_ms=500L),
  )
  let trajectory = @trajectory.build_trajectory("run", [
    { id: "run", text, title: None, },
  ])
  let calls = select_spans(trajectory.spans, span => span.kind is PtcToolCall)
  assert_eq(calls.length(), 3)
  assert_eq(calls[0].started_at_ms, 100L)
  assert_eq(calls[0].ended_at_ms, Some(250L))
  assert_true(calls[0].metadata.get("timing") is Some(String("measured")))
  // A call the program never closed runs to the program's own end and is
  // interrupted, not still running.
  assert_eq(calls[1].started_at_ms, 300L)
  assert_eq(calls[1].ended_at_ms, Some(400L))
  assert_true(calls[1].status is Interrupted)
  assert_true(
    calls[1].metadata.get("timing") is Some(String("open_at_program_end")),
  )
  assert_eq(calls[2].started_at_ms, 400L)
  assert_eq(calls[2].ended_at_ms, Some(400L))
  assert_true(calls[2].metadata.get("timing") is Some(String("unknown")))
  // The timed calls now carry their own width into the tools pool.
  assert_true(trajectory.stats.tool_ms >= 150L + 100L)
}

///|
test "a model step is as wide as its recorded request" {
  // The answer landed at 9_000; its request was issued at 4_000, after the
  // prompt that opened the turn at 1_000.
  let text = session_text(
    @agent_session.Session(SessionId("run"), system_prompt="")
    .append(User(UserMessage(Content([Text("go")]))), unix_ms=1_000L)
    .append(
      Assistant(AssistantMessage("done", started_at_ms=4_000L)),
      unix_ms=9_000L,
    )
    .append(Terminal(Finished("done")), unix_ms=9_100L),
  )
  let trajectory = @trajectory.build_trajectory("run", [
    { id: "run", text, title: None, },
  ])
  let call = find_span(trajectory.spans, span => span.kind is LlmCall)
  guard call is Some(call) else { fail("no model call") }
  assert_eq(call.started_at_ms, 4_000L)
  assert_eq(call.ended_at_ms, Some(9_000L))
  // A log written before the request clock is bounded by the previous event.
  let older = session_text(
    @agent_session.Session(SessionId("old"), system_prompt="")
    .append(User(UserMessage(Content([Text("go")]))), unix_ms=1_000L)
    .append(Assistant(AssistantMessage("done")), unix_ms=9_000L)
    .append(Terminal(Finished("done")), unix_ms=9_100L),
  )
  let older_trajectory = @trajectory.build_trajectory("old", [
    { id: "old", text: older, title: None, },
  ])
  let older_call = find_span(older_trajectory.spans, span => {
    span.kind is LlmCall
  })
  guard older_call is Some(older_call) else { fail("no model call") }
  assert_eq(older_call.started_at_ms, 1_000L)
}

///|
test "a child spawned inside a script hangs under that PTC call" {
  // The script calls `subagent` through PTC, and the call's own result names
  // the child: the mount is exact, not the script span, and not a time window.
  let call : Json = {
    "name": "subagent",
    "arguments": { "kind": "explore" },
    "status": "done",
    "started_at_ms": 1_200,
    "ended_at_ms": 4_000,
    "result": { "data": { "session": "run-sr-1" } },
  }
  let parent_text = session_text(
    @agent_session.Session(SessionId("run"), system_prompt="")
    .append(User(UserMessage(Content([Text("script")]))), unix_ms=500L)
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(id="c1", name="mbtx", arguments="{}"),
        ]),
      ),
      unix_ms=1_000L,
    )
    .append(
      Tool(
        ToolResult(
          tool_call_id="c1",
          tool_name="mbtx",
          content=[Text("ok")],
          data=Json::object({ "ptc_calls": Json([call]) }),
        ),
      ),
      unix_ms=4_500L,
    )
    .append(Terminal(Finished("done")), unix_ms=4_600L),
  )
  let child_text = session_text(
    @agent_session.Session(SessionId("run-sr-1"), system_prompt="")
    .append(User(UserMessage(Content([Text("scout")]))), unix_ms=1_500L)
    .append(Terminal(Finished("done")), unix_ms=3_000L),
  )
  let trajectory = @trajectory.build_trajectory("run", [
    { id: "run", text: parent_text, title: None, },
    { id: "run-sr-1", text: child_text, title: Some("scout"), },
  ])
  let ptc = find_span(trajectory.spans, span => span.kind is PtcToolCall)
  guard ptc is Some(ptc) else { fail("no ptc call") }
  let child_turn = find_span(trajectory.spans, span => {
    span.session_id == "run-sr-1" && span.kind is Turn
  })
  guard child_turn is Some(child_turn) else { fail("no child turn") }
  assert_eq(child_turn.parent_id, Some(ptc.id))
  assert_true(child_turn.metadata.get("mount") is Some(String("tool_result")))
}

///|
test "a live critical path includes a still-running step" {
  let text = session_text(
    @agent_session.Session(SessionId("run"), system_prompt="")
    .append(User(UserMessage(Content([Text("work")]))), unix_ms=1_000L)
    .append(
      Assistant(
        AssistantMessage(
          "",
          tool_calls=[ToolCall(id="fast", name="read_image", arguments="{}")],
          started_at_ms=1_000L,
        ),
      ),
      unix_ms=1_050L,
    )
    .append(
      Tool(
        ToolResult(tool_call_id="fast", tool_name="read_image", content=[
          Text("ok"),
        ]),
      ),
      unix_ms=1_100L,
    )
    .append(
      Assistant(
        AssistantMessage(
          "",
          tool_calls=[ToolCall(id="slow", name="subagent", arguments="{}")],
          started_at_ms=1_100L,
        ),
      ),
      unix_ms=1_200L,
    )
    .append(Runtime(RuntimeNotice("still working")), unix_ms=20_200L),
  )
  let trajectory = @trajectory.build_trajectory("run", [
    { id: "run", text, title: None, },
  ])
  assert_true(trajectory.live)
  assert_eq(trajectory.stats.critical_path_ms, 19_000L)
  guard trajectory.stats.critical_path.last() is Some(id) else {
    fail("expected critical path leaf")
  }
  let slow = find_span(trajectory.spans, span => span.label == "subagent")
  guard slow is Some(slow) else { fail("missing subagent span") }
  assert_eq(id, slow.id)
}

///|
test "time_window mount prefers subagent over a concurrent leaf tool" {
  let parent_text = session_text(
    @agent_session.Session(SessionId("run"), system_prompt="")
    .append(User(UserMessage(Content([Text("work")]))), unix_ms=500L)
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(id="c_sub", name="subagent", arguments="{}"),
          ToolCall(id="c_leaf", name="read_image", arguments="{}"),
        ]),
      ),
      unix_ms=1_000L,
    )
    .append(
      Tool(
        ToolResult(tool_call_id="c_sub", tool_name="subagent", content=[
          Text("done"),
        ]),
      ),
      unix_ms=5_000L,
    )
    .append(
      Tool(
        ToolResult(tool_call_id="c_leaf", tool_name="read_image", content=[
          Text("img"),
        ]),
      ),
      unix_ms=5_000L,
    )
    .append(Terminal(Finished("done")), unix_ms=5_100L),
  )
  let child_text = session_text(
    @agent_session.Session(SessionId("run-sr-1"), system_prompt="")
    .append(User(UserMessage(Content([Text("child")]))), unix_ms=1_500L)
    .append(Terminal(Finished("ok")), unix_ms=3_000L),
  )
  let trajectory = @trajectory.build_trajectory("run", [
    { id: "run", text: parent_text, title: None, },
    { id: "run-sr-1", text: child_text, title: None, },
  ])
  let sub = find_span(trajectory.spans, span => span.label == "subagent")
  guard sub is Some(sub) else { fail("missing subagent span") }
  let child_turn = find_span(trajectory.spans, span => {
    span.session_id == "run-sr-1" && span.kind is Turn
  })
  guard child_turn is Some(child_turn) else { fail("missing child turn") }
  assert_eq(child_turn.parent_id, Some(sub.id))
}

///|
test "job_result_status ignores failure words inside unrelated arguments" {
  let text = session_text(
    @agent_session.Session(SessionId("run"), system_prompt="")
    .append(User(UserMessage(Content([Text("run job")]))), unix_ms=10L)
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(id="c1", name="mbtx", arguments="{}"),
        ]),
      ),
      unix_ms=20L,
    )
    .append(
      Tool(
        ToolResult(tool_call_id="c1", tool_name="mbtx", content=[
          Text("moved to the background as job job-1"),
        ]),
      ),
      unix_ms=100L,
    )
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(
            id="c2",
            name="job_wait",
            arguments="{\"job_ids\":[\"job-1\"]}",
          ),
        ]),
      ),
      unix_ms=200L,
    )
    .append(
      Tool(
        ToolResult(tool_call_id="c2", tool_name="job_wait", content=[
          Text("job-1 exit=0 pytest -k failed"),
        ]),
      ),
      unix_ms=900L,
    )
    .append(Terminal(Finished("done")), unix_ms=950L),
  )
  let trajectory = @trajectory.build_trajectory("run", [
    { id: "run", text, title: None, },
  ])
  let job = find_span(trajectory.spans, span => span.kind is BackgroundJob)
  guard job is Some(job) else { fail("no background job span") }
  assert_true(job.status is Succeeded)
}

///|
test "a child session with an arbitrary id joins the run via tool result" {
  let parent_text = session_text(
    @agent_session.Session(SessionId("run"), system_prompt="")
    .append(User(UserMessage(Content([Text("delegate")]))), unix_ms=500L)
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(id="c1", name="subagent", arguments="{}"),
        ]),
      ),
      unix_ms=1_000L,
    )
    .append(
      Tool(
        ToolResult(
          tool_call_id="c1",
          tool_name="subagent",
          content=[Text("done")],
          data=Json::object({ "session": Json("worker-alpha") }),
        ),
      ),
      unix_ms=4_000L,
    )
    .append(Terminal(Finished("done")), unix_ms=4_100L),
  )
  let child_text = session_text(
    @agent_session.Session(SessionId("worker-alpha"), system_prompt="")
    .append(User(UserMessage(Content([Text("alpha")]))), unix_ms=1_500L)
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(id="c2", name="subagent", arguments="{}"),
        ]),
      ),
      unix_ms=1_600L,
    )
    .append(
      Tool(
        ToolResult(
          tool_call_id="c2",
          tool_name="subagent",
          content=[Text("ok")],
          data=Json::object({ "session": Json("worker-beta") }),
        ),
      ),
      unix_ms=2_500L,
    )
    .append(Terminal(Finished("ok")), unix_ms=2_600L),
  )
  let grandchild_text = session_text(
    @agent_session.Session(SessionId("worker-beta"), system_prompt="")
    .append(User(UserMessage(Content([Text("beta")]))), unix_ms=1_800L)
    .append(Terminal(Finished("ok")), unix_ms=2_200L),
  )
  let trajectory = @trajectory.build_trajectory("run", [
    { id: "worker-beta", text: grandchild_text, title: Some("beta"), },
    { id: "worker-alpha", text: child_text, title: Some("alpha"), },
    { id: "run", text: parent_text, title: None, },
  ])
  assert_eq(trajectory.stats.session_count, 3)
  let alpha_turn = find_span(trajectory.spans, span => {
    span.session_id == "worker-alpha" && span.kind is Turn
  })
  guard alpha_turn is Some(alpha_turn) else { fail("missing worker-alpha") }
  assert_true(alpha_turn.metadata.get("mount") is Some(String("tool_result")))
  let beta_turn = find_span(trajectory.spans, span => {
    span.session_id == "worker-beta" && span.kind is Turn
  })
  guard beta_turn is Some(beta_turn) else { fail("missing worker-beta") }
  assert_true(beta_turn.metadata.get("mount") is Some(String("tool_result")))
}

///|
test "job_wait records all job_ids and round-trips through JSON" {
  let text = session_text(
    @agent_session.Session(SessionId("run"), system_prompt="")
    .append(User(UserMessage(Content([Text("wait all")]))), unix_ms=10L)
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(
            id="w1",
            name="job_wait",
            arguments="{\"job_ids\":[\"job-1\",\"job-2\",\"job-3\"]}",
          ),
        ]),
      ),
      unix_ms=100L,
    )
    .append(
      Tool(
        ToolResult(tool_call_id="w1", tool_name="job_wait", content=[
          Text("job-1 exit=0\njob-2 exit=0\njob-3 exit=0"),
        ]),
      ),
      unix_ms=500L,
    )
    .append(Terminal(Finished("done")), unix_ms=550L),
  )
  let trajectory = @trajectory.build_trajectory("run", [
    { id: "run", text, title: None, },
  ])
  let wait = find_span(trajectory.spans, span => span.kind is JobWait)
  guard wait is Some(wait) else { fail("missing wait span") }
  assert_eq(wait.job_ids, ["job-1", "job-2", "job-3"])
  let decoded = @trajectory.parse_trajectory(trajectory.to_json())
  let decoded_wait = find_span(decoded.spans, span => span.kind is JobWait)
  guard decoded_wait is Some(decoded_wait) else {
    fail("missing decoded wait span")
  }
  assert_eq(decoded_wait.job_ids, ["job-1", "job-2", "job-3"])
}

///|
test "an earlier-engine recovered worker falls back to run_span rather than the last turn" {
  let parent_text = session_text(
    @agent_session.Session(SessionId("run"), system_prompt="")
    .append(User(UserMessage(Content([Text("turn 1")]))), unix_ms=5_000L)
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(id="rec1", name="subagent", arguments="{}"),
        ]),
      ),
      unix_ms=5_100L,
    )
    .append(
      Tool(
        ToolResult(
          tool_call_id="rec1",
          tool_name="subagent",
          content=[Text("recovered worker")],
          data={ "recovered": [{ "session": "old-worker" }] },
        ),
      ),
      unix_ms=5_200L,
    )
    .append(Terminal(Finished("done")), unix_ms=5_300L),
  )
  let worker_text = session_text(
    @agent_session.Session(SessionId("old-worker"), system_prompt="")
    .append(User(UserMessage(Content([Text("earlier")]))), unix_ms=1_000L)
    .append(Terminal(Finished("done")), unix_ms=1_200L),
  )
  let trajectory = @trajectory.build_trajectory("run", [
    { id: "run", text: parent_text, title: None, },
    { id: "old-worker", text: worker_text, title: None, },
  ])
  let worker_turn = find_span(trajectory.spans, span => {
    span.session_id == "old-worker" && span.kind is Turn
  })
  guard worker_turn is Some(worker_turn) else { fail("missing worker turn") }
  assert_eq(worker_turn.parent_id, Some("run:run"))
  assert_true(worker_turn.metadata.get("mount") is Some(String("run_span")))
}

///|
test "job_records supplies exact finished_at_ms and outcome for late-waited and unwaited jobs" {
  let text = session_text(
    @agent_session.Session(SessionId("run"), system_prompt="")
    .append(User(UserMessage(Content([Text("start jobs")]))), unix_ms=100L)
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(id="j1", name="shell_exec", arguments="{}"),
          ToolCall(id="j2", name="shell_exec", arguments="{}"),
        ]),
      ),
      unix_ms=200L,
    )
    .append(
      Tool(
        ToolResult(tool_call_id="j1", tool_name="shell_exec", content=[
          Text("started in background as job bg-1"),
        ]),
      ),
      unix_ms=300L,
    )
    .append(
      Tool(
        ToolResult(tool_call_id="j2", tool_name="shell_exec", content=[
          Text("started in background as job bg-2"),
        ]),
      ),
      unix_ms=350L,
    )
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(
            id="w1",
            name="job_wait",
            arguments="{\"job_ids\":[\"bg-1\"]}",
          ),
        ]),
      ),
      unix_ms=5_000L,
    )
    .append(
      Tool(
        ToolResult(tool_call_id="w1", tool_name="job_wait", content=[
          Text("bg-1 exit=0"),
        ]),
      ),
      unix_ms=5_200L,
    )
    .append(Terminal(Finished("done")), unix_ms=5_300L),
  )
  let trajectory = @trajectory.build_trajectory(
    "run",
    [{ id: "run", text, title: None, }],
    job_records=[
      {
        session_id: "run",
        job_id: "bg-1",
        started_at_ms: 210L,
        finished_at_ms: Some(1_210L),
        status: Succeeded,
      },
      {
        session_id: "run",
        job_id: "bg-2",
        started_at_ms: 220L,
        finished_at_ms: Some(2_220L),
        status: Failed,
      },
    ],
  )
  let bg1 = find_span(trajectory.spans, span => {
    span.kind is BackgroundJob && span.job_id == Some("bg-1")
  })
  guard bg1 is Some(bg1) else { fail("missing bg-1") }
  assert_eq(bg1.started_at_ms, 210L)
  assert_eq(bg1.ended_at_ms, Some(1_210L))
  assert_true(bg1.status is Succeeded)
  let bg2 = find_span(trajectory.spans, span => {
    span.kind is BackgroundJob && span.job_id == Some("bg-2")
  })
  guard bg2 is Some(bg2) else { fail("missing bg-2") }
  assert_eq(bg2.ended_at_ms, Some(2_220L))
  assert_true(bg2.status is Failed)
}
