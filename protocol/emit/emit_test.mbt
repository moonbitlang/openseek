///|
/// The event's line as it reaches stdout, read back off the sink `emit` wrote
/// it to — the real path, so the bytes are the contract. There is no log
/// envelope: events no longer go through `@xlog`, so no `timestamp`, `source`,
/// or `category` on the line.
fn wire(event : @protocol.Event) -> String raise {
  @emit.open()
  // A line an earlier emit in this process left behind is not this event's.
  while @emit.poll_line() is Some(_) {

  }
  @emit.emit(event)
  guard @emit.poll_line() is Some(line) else { fail("emit wrote no line") }
  line
}

///|
/// The sink drops events until it is opened and again once it is closed, so a
/// process that never drains — a report-printing command, a test binary —
/// cannot accumulate lines nobody reads.
test "emits are dropped unless the sink is open" {
  @emit.close()
  @emit.emit(AgentStep(step=1))
  @emit.open()
  assert_eq(@emit.poll_line(), None)
  @emit.emit(AgentStep(step=2))
  guard @emit.poll_line() is Some(line) else { fail("expected a line") }
  inspect(
    line,
    content=(
      #|{"event":"agent_step","step":2}
    ),
  )
  @emit.close()
  @emit.emit(AgentStep(step=3))
  assert_eq(@emit.poll_line(), None)
  @emit.open()
  assert_eq(@emit.poll_line(), None)
}

///|
/// `protocol` owns `Usage`, so the sample is built directly rather than decoded
/// out of a provider's response type.
fn usage_sample() -> @protocol.Usage {
  {
    prompt_tokens: 11,
    completion_tokens: 22,
    total_tokens: 33,
    prompt_cache_hit_tokens: 4,
    prompt_cache_miss_tokens: 7,
  }
}

///|
/// One sample per `Event` variant. `derive(Eq)` plus the round-trip test below
/// makes this list the encoder/decoder contract.
///
/// One gap this list does not close, worth knowing before adding a variant.
/// Exhaustiveness covers `to_json` and `parse` — `emit` itself matches nothing,
/// it delegates — but nothing forces a new variant to be added *here*, so one
/// added without a sample is silently untested.
fn all_events() -> Array[@protocol.Event] {
  [
    AgentSetupFailed(error="boom"),
    AgentStep(step=3),
    AgentAborted(reason="interrupted"),
    AgentFinished(answer="done"),
    MaxStepsExhausted,
    TurnFailed(error="turn boom"),
    AssistantDelta(content="Hel"),
    ReasoningDelta(content="thinking"),
    AssistantMessage(content="Hello"),
    ReasoningMessage(content="thinking"),
    Usage(usage=usage_sample()),
    ToolResult(
      tool_call_id="call_1",
      tool_name="read",
      is_error=false,
      content="file body",
      brief=Some("read moon.mod"),
    ),
    ToolResult(
      tool_call_id="call_2",
      tool_name="shell",
      is_error=true,
      content="exit 1",
      brief=None,
    ),
    ToolCallDecodeError(
      tool_call_id="call_3",
      tool_name="edit",
      error="bad args",
    ),
    ApprovalRequested(
      id="ap-1",
      tool_name="mbtx",
      detail="run without the sandbox policy",
      body=Some("fn main { println(1) }"),
    ),
    ApprovalRequested(
      id="ap-2",
      tool_name="mbtx",
      detail="run without the sandbox policy",
      body=None,
    ),
    ApprovalResolved(id="ap-1", outcome="allowed_once"),
    ApprovalResolved(id="ap-2", outcome="rejected"),
    ApprovalResolved(id="ap-3", outcome="cancelled"),
    SteerApplied(kind="prompt", content="also fix docs"),
    SteerDropped(content="too late"),
    BackgroundNotice(content="job 2 exited"),
    GoalUpdated(goal=Some("ship it")),
    GoalUpdated(goal=None),
    GoalBlocked(reason="needs a key"),
    GoalUnblocked,
    GoalCheck(content="is it met?"),
    GoalReminder(content="remember the goal"),
    GoalContinue(remaining=4),
    GoalBudgetExhausted(turns=20),
    PlanReminder(content="update the plan"),
    CompactionStarted(from_sequence=1, to_sequence=9),
    CompactionFinished(from_sequence=1, to_sequence=9, summary="recap"),
    CompactionFailed(error="cancelled"),
    AutoCompactionStarted(from_sequence=1, to_sequence=12),
    AutoCompactionFinished(from_sequence=1, to_sequence=12, summary="recap"),
    AutoCompactionFailed(error="summary boom"),
    ContextYield(to_sequence=30, answer="partial"),
    SubrunStarted(id="sr-1", kind="review", label="goal review"),
    SubrunFinished(
      id="sr-1",
      status="captured",
      steps=12,
      prompt_tokens=34_000,
      completion_tokens=5_600,
    ),
    SessionStarted(
      session="cli-1",
      session_root=".openseek",
      workspace_root=Some("/w"),
    ),
    SessionStarted(
      session="cli-1",
      session_root=".openseek",
      workspace_root=None,
    ),
    SessionError(error="failed to append user"),
    WorkspaceCreated(dir="/w"),
    CommandError(error="command stream: bad json"),
    FleetStarted(runs=3, task="port it"),
    McpConfigIgnored(reason="fleet mode does not support MCP servers"),
    McpConfigUnreadable(path="/mcp.json", error="no such file"),
    McpConfigInvalid(path="/mcp.json", error="bad shape"),
    McpToolsRegistered(servers=2, tools=3, names=["a", "b", "c"]),
    McpToolDuplicate(server="fs", tool="read"),
    McpToolRenamed(from="read", to="fs_read"),
    McpToolsCapped(server="fs", kept=64),
    McpServerSkippedOverCap(server="fs"),
    McpConnectFailed(server="fs", error=Some("spawn failed")),
    McpConnectFailed(server="fs", error=None),
    McpListToolsFailed(server="fs", error="timeout"),
    McpListToolsTimeout(server="fs"),
    McpNoTools(server="fs"),
  ]
}

///|
/// `parse` is `emit`'s inverse for every variant: the pair cannot drift without
/// this failing, which is the property the package exists to provide.
test "every event round-trips through emit and parse" {
  for event in all_events() {
    let encoded = @json.parse(wire(event))
    assert_eq(@protocol.parse(encoded), Some(event))
  }
}

///|
/// `brief` and `mcp_connect_failed`'s `error` are always written, `null` when
/// absent. Every decoder reads them with a lookup that rejects a non-string, so
/// a null and a missing key are the same value downstream — the uniform shape
/// costs nothing and keeps one variant per event.
test "optional payload fields are written as null, never omitted" {
  inspect(
    wire(
      ToolResult(
        tool_call_id="call_2",
        tool_name="shell",
        is_error=true,
        content="exit 1",
        brief=None,
      ),
    ),
    content=(
      #|{"event":"tool_result","tool_call_id":"call_2","tool_name":"shell","is_error":true,"content":"exit 1","brief":null}
    ),
  )
  // A present value is the bare string. MoonBit's own `Some(v)` encoding is the
  // one-element array `[v]`, which would read as absent to every decoder.
  inspect(
    wire(
      ToolResult(
        tool_call_id="call_1",
        tool_name="read",
        is_error=false,
        content="file body",
        brief=Some("read moon.mod"),
      ),
    ),
    content=(
      #|{"event":"tool_result","tool_call_id":"call_1","tool_name":"read","is_error":false,"content":"file body","brief":"read moon.mod"}
    ),
  )
  inspect(
    wire(McpConnectFailed(server="fs", error=None)),
    content=(
      #|{"event":"mcp_connect_failed","server":"fs","error":null}
    ),
  )
  inspect(
    wire(GoalUpdated(goal=None)),
    content=(
      #|{"event":"goal_updated","goal":null}
    ),
  )
}

///|
/// The struct's `ToJson` derive is the wire format for `usage`:
/// renaming a field of `@protocol.Usage` changes this line and every client
/// parsing it — which is exactly why the type is owned here and not borrowed
/// from the provider layer.
test "usage carries the protocol struct verbatim" {
  inspect(
    wire(Usage(usage=usage_sample())),
    content=(
      #|{"event":"usage","usage":{"prompt_tokens":11,"completion_tokens":22,"total_tokens":33,"prompt_cache_hit_tokens":4,"prompt_cache_miss_tokens":7}}
    ),
  )
}

///|
/// `workspace_root` is `String?` because it postdates the event, but a current
/// engine always has one — so the line a current engine writes is the bare
/// string, byte for byte what it was before the field became optional. This is
/// what stops "make it optional for old engines" from quietly changing the wire
/// for new ones.
test "session_started still writes workspace_root as a bare string" {
  inspect(
    wire(
      SessionStarted(
        session="cli-1",
        session_root=".openseek",
        workspace_root=Some("/w"),
      ),
    ),
    content=(
      #|{"event":"session_started","session":"cli-1","session_root":".openseek","workspace_root":"/w"}
    ),
  )
}

///|
/// The wire line carries no log envelope: events do not pass through `@xlog`,
/// so the keys its handler added (`timestamp`, `level`, `source`, `category`)
/// are gone from every line. No reader ever consulted `level`; a client that
/// wants a severity derives it from the variant it decoded.
test "the wire line has no log envelope" {
  for event in all_events() {
    guard @json.parse(wire(event)) is Object(fields) else {
      fail("expected an object")
    }
    assert_false(fields.contains("timestamp"))
    assert_false(fields.contains("level"))
    assert_false(fields.contains("source"))
    assert_false(fields.contains("category"))
  }
}
