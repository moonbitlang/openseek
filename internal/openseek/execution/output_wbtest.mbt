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
