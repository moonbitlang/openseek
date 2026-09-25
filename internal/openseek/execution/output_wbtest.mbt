///|
/// Render `events` through one renderer, joining each stream.
fn render_all(events : Array[@protocol.Event]) -> (String, String) {
  let renderer = TextRenderer()
  let answer = StringBuilder()
  let progress = StringBuilder()
  for event in events {
    let text = renderer.render(event)
    answer.write_string(text.answer)
    progress.write_string(text.progress)
  }
  (answer.to_string(), progress.to_string())
}

///|
test "the answer goes to stdout and the progress to stderr" {
  let usage : @protocol.Usage = {
    prompt_tokens: 100,
    completion_tokens: 7,
    total_tokens: 107,
    prompt_cache_hit_tokens: 60,
    prompt_cache_miss_tokens: 40,
  }
  let (answer, progress) = render_all([
    SessionStarted(
      session="s1",
      session_root="/w/.openseek",
      workspace_root=None,
    ),
    AgentStep(step=1),
    ReasoningDelta(content="hmm"),
    AssistantDelta(content="Let me"),
    AssistantMessage(content="Let me read\nthe module."),
    ToolResult(
      tool_call_id="c1",
      tool_name="read",
      is_error=false,
      content="body",
      brief=Some("read moon.mod"),
    ),
    ToolResult(
      tool_call_id="c2",
      tool_name="edit",
      is_error=true,
      content="\nno match\nfor old_string",
      brief=None,
    ),
    ToolResult(
      tool_call_id="c3",
      tool_name="job_wait",
      is_error=false,
      content="done",
      brief=None,
    ),
    Usage(usage~),
    GoalUpdated(goal=Some("ship")),
    AgentStep(step=2),
    AssistantDelta(content="Hi"),
    AssistantMessage(content="Hi there\u{1b}[31m\n\n"),
    AgentFinished(answer="Hi there\u{1b}[31m\n\n"),
  ])
  inspect(
    answer,
    content=(
      #|Hi there[31m
      #|
    ),
  )
  inspect(
    progress,
    content=(
      #|session s1 (/w/.openseek)
      #|Let me read the module.
      #|· read moon.mod
      #|tool error: edit: no match
      #|
    ),
  )
}

///|
test "a finish-tool answer, and runs that stop early" {
  let (answer, progress) = render_all([
    SessionStarted(
      session="s2",
      session_root="/w/.openseek",
      workspace_root=None,
    ),
    AssistantMessage(content="checking the tests"),
    AgentFinished(answer="all green"),
  ])
  inspect(
    answer,
    content=(
      #|all green
      #|
    ),
  )
  inspect(
    progress,
    content=(
      #|session s2 (/w/.openseek)
      #|checking the tests
      #|
    ),
  )
  let (answer, progress) = render_all([
    SessionStarted(
      session="s3",
      session_root="/w/.openseek",
      workspace_root=None,
    ),
    AssistantMessage(content="half done"),
    ContextYield(to_sequence=9, answer="[context ceiling] checkpointed"),
  ])
  inspect(answer, content="")
  inspect(
    progress,
    content=(
      #|session s3 (/w/.openseek)
      #|half done
      #|stopped at the model's context window · continue with --session s3
      #|
    ),
  )
  // Without a recorded session there is nothing to continue.
  let (_, progress) = render_all([MaxStepsExhausted])
  inspect(
    progress,
    content=(
      #|stopped: max steps exhausted
      #|
    ),
  )
}

///|
test "a fleet separates its answers and drops interleaved messages" {
  let (answer, progress) = render_all([
    FleetStarted(runs=2, task="t"),
    AssistantMessage(content="A is thinking aloud"),
    AssistantMessage(content="All of A"),
    AgentFinished(answer="All of A"),
    AgentFinished(answer="B via finish"),
  ])
  inspect(
    answer,
    content=(
      #|All of A
      #|---
      #|B via finish
      #|
    ),
  )
  inspect(
    progress,
    content=(
      #|fleet: 2 runs
      #|
    ),
  )
}

///|
test "a blank answer prints nothing instead of borrowing a message" {
  let (answer, progress) = render_all([
    AssistantMessage(content="wrapping up"),
    AgentFinished(answer=""),
  ])
  inspect(answer, content="")
  inspect(
    progress,
    content=(
      #|wrapping up
      #|
    ),
  )
  // In a fleet, attempt A's message must never become attempt B's answer.
  let (answer, progress) = render_all([
    FleetStarted(runs=2, task="t"),
    McpConfigIgnored(reason="fleet mode does not support MCP servers"),
    AssistantMessage(content="A, still working"),
    AgentFinished(answer=""),
  ])
  inspect(answer, content="")
  inspect(
    progress,
    content=(
      #|fleet: 2 runs
      #|MCP config ignored: fleet mode does not support MCP servers
      #|
    ),
  )
}

///|
test "tool lines name what the call did and background jobs read as work" {
  fn job(
    state : @protocol.JobState,
    description : String?,
  ) -> @protocol.JobRecord {
    {
      generation: "g",
      id: "AaDYX7yddAWvcOUJBd6j4g",
      revision: 1,
      command: "mbtx: fn main { … }",
      description,
      cwd: None,
      state,
      started_at_ms: 0,
      backgrounded_at_ms: 0,
      finished_at_ms: None,
      last_output_at_ms: None,
      output_file: None,
      output_persistent: false,
      output_bytes: 0,
      output_chars: 0,
      output_truncated: false,
      invalid_utf8: false,
      output_error: None,
      persistence_error: None,
      cleanup_error: None,
      data: None,
    }
  }

  let walk = "Walk the tree for lib.mbt"
  let (_, progress) = render_all([
    // A brief that is only the tool name, or none at all, prints nothing.
    ToolResult(
      tool_call_id="c1",
      tool_name="mbtx",
      is_error=false,
      content="ok",
      brief=None,
    ),
    ToolResult(
      tool_call_id="c2",
      tool_name="mbtx",
      is_error=false,
      content="ok",
      brief=Some("mbtx"),
    ),
    ToolResult(
      tool_call_id="c3",
      tool_name="mbtx",
      is_error=false,
      content="ok",
      brief=Some("Check git status"),
    ),
    // A background handoff: the job's lines replace the handoff and polling.
    JobChanged(kind=Started, job=job(Running, Some(walk))),
    ToolResult(
      tool_call_id="c4",
      tool_name="mbtx",
      is_error=false,
      content="moved to the background",
      brief=Some("mbtx → bg AaDYX7yddAWvcOUJBd6j4g"),
    ),
    JobChanged(kind=Updated, job=job(Running, Some(walk))),
    ToolResult(
      tool_call_id="c5",
      tool_name="job_output",
      is_error=false,
      content="…",
      brief=Some("job AaDYX7yddAWvcOUJBd6j4g (running): \{walk}"),
    ),
    JobChanged(kind=Finished, job=job(Exited(0), Some(walk))),
    JobChanged(kind=Finished, job=job(Exited(2), None)),
    // Exit 0 is not success when the runtime reports the job `Failed`.
    JobChanged(kind=Failed, job={
      ..job(Exited(0), Some(walk)),
      cleanup_error: Some("script exited with unfinished tool calls\nmore"),
    }),
    // An error names the call and its reason, without the tool's wrapper.
    ToolResult(
      tool_call_id="c6",
      tool_name="mbtx",
      is_error=true,
      content="[mbtx: BUILD failed (exit 1) — the program never ran; the output below is the build's]\nError: x is unbound",
      brief=Some("mbtx build"),
    ),
  ])
  inspect(
    progress,
    content=(
      #|· Check git status
      #|· Walk the tree for lib.mbt (in the background)
      #|· Walk the tree for lib.mbt (finished)
      #|tool error: mbtx: fn main { … }: exited 2
      #|tool error: Walk the tree for lib.mbt: script exited with unfinished tool calls
      #|tool error: mbtx build: BUILD failed (exit 1)
      #|
    ),
  )
}

///|
test "commentary before a backgrounded call comes first, the answer stays out" {
  let job : @protocol.JobRecord = {
    generation: "g",
    id: "j1",
    revision: 1,
    command: "mbtx: fn main { … }",
    description: Some("Run the tests"),
    cwd: None,
    state: Running,
    started_at_ms: 0,
    backgrounded_at_ms: 0,
    finished_at_ms: None,
    last_output_at_ms: None,
    output_file: None,
    output_persistent: false,
    output_bytes: 0,
    output_chars: 0,
    output_truncated: false,
    invalid_utf8: false,
    output_error: None,
    persistence_error: None,
    cleanup_error: None,
    data: None,
  }
  let (answer, progress) = render_all([
    AssistantMessage(content="I will run the tests."),
    // The runtime reports the job before the call's own result.
    JobChanged(kind=Started, job~),
    ToolResult(
      tool_call_id="c1",
      tool_name="mbtx",
      is_error=false,
      content="moved to the background",
      brief=Some("mbtx → bg j1"),
    ),
    AssistantMessage(content="All tests pass."),
    // The job ends while the final answer is held; the answer stays stdout's.
    JobChanged(kind=Finished, job={ ..job, state: Exited(0), }),
    AgentFinished(answer="All tests pass."),
  ])
  inspect(
    progress,
    content=(
      #|I will run the tests.
      #|· Run the tests (in the background)
      #|· Run the tests (finished)
      #|
    ),
  )
  inspect(
    answer,
    content=(
      #|All tests pass.
      #|
    ),
  )
}
