///|
/// `parse` against literal lines, with no `emit` in sight.
///
/// These run on every backend the module supports — js, wasm, wasm-gc, native —
/// which is the point of keeping the decoder free of `@xlog`: a client that
/// reads the stream does not have to be a native binary. The round-trip against
/// the real encoder lives in the `emit` package, which is native-only.
fn decode(line : String) -> @openseek_protocol.Event? {
  @openseek_protocol.parse(@json.parse(line) catch { _ => return None })
}

///|
test "decodes a streaming delta" {
  debug_inspect(
    decode(
      (
        #|{"event":"assistant_delta","content":"Hel"}
      ),
    ),
    content=(
      #|Some(AssistantDelta(content="Hel"))
    ),
  )
}

///|
test "decodes a reasoning delta" {
  debug_inspect(
    decode(
      (
        #|{"event":"reasoning_delta","content":"thinking"}
      ),
    ),
    content=(
      #|Some(ReasoningDelta(content="thinking"))
    ),
  )
}

///|
/// The envelope is ignored: a reader cares about the event, not about which
/// line of the engine reported it.
test "decodes with the envelope absent" {
  debug_inspect(
    decode(
      (
        #|{"event":"agent_step","step":7}
      ),
    ),
    content=(
      #|Some(AgentStep(step=7))
    ),
  )
}

///|
test "decodes the nested usage payload" {
  debug_inspect(
    decode(
      (
        #|{"event":"usage","usage":{"prompt_tokens":11,"completion_tokens":22,"total_tokens":33,"prompt_cache_hit_tokens":4,"prompt_cache_miss_tokens":7}}
      ),
    ),
    content=(
      #|Some(
      #|  Usage(
      #|    usage={
      #|      prompt_tokens: 11,
      #|      completion_tokens: 22,
      #|      total_tokens: 33,
      #|      prompt_cache_hit_tokens: 4,
      #|      prompt_cache_miss_tokens: 7,
      #|    },
      #|  ),
      #|)
    ),
  )
}

///|
/// A null optional field and an absent one are the same value — the property
/// that let the three `tool_result` call sites converge on one shape.
test "a null optional field reads as absent" {
  debug_inspect(
    decode(
      (
        #|{"event":"tool_result","tool_call_id":"c1","tool_name":"read","is_error":false,"content":"body","brief":null}
      ),
    ),
    content=(
      #|Some(
      #|  ToolResult(
      #|    tool_call_id="c1",
      #|    tool_name="read",
      #|    is_error=false,
      #|    content="body",
      #|    brief=None,
      #|  ),
      #|)
    ),
  )
  debug_inspect(
    decode(
      (
        #|{"event":"tool_result","tool_call_id":"c1","tool_name":"read","is_error":false,"content":"body"}
      ),
    ),
    content=(
      #|Some(
      #|  ToolResult(
      #|    tool_call_id="c1",
      #|    tool_name="read",
      #|    is_error=false,
      #|    content="body",
      #|    brief=None,
      #|  ),
      #|)
    ),
  )
}

///|
/// An engine older than 2026-06-25 (9b2f6c43) emits `steer_applied` with only
/// `content`. The TUI launches whichever `openseek` is on PATH, so that pairing
/// is real, and a reader that dropped those lines would silently lose steers.
/// `kind` therefore defaults instead of being required — the rule every client
/// applied by hand before this package, now written down once and tested.
test "an older engine's steer_applied still decodes" {
  debug_inspect(
    decode(
      (
        #|{"event":"steer_applied","content":"go left"}
      ),
    ),
    content=(
      #|Some(SteerApplied(kind="prompt", content="go left"))
    ),
  )
}

///|
/// `session_started` predates `--dir`: engines between d11e04c2 (which added the
/// event) and d5d0b208 (which added the workspace option) emit only `session`
/// and `session_root`. Same rule as `steer_applied`'s `kind` — a field added
/// after its event must not decide whether the event decodes.
test "an older engine's session_started still decodes" {
  debug_inspect(
    decode(
      (
        #|{"event":"session_started","session":"cli-1","session_root":".openseek"}
      ),
    ),
    content=(
      #|Some(
      #|  SessionStarted(
      #|    session="cli-1",
      #|    session_root=".openseek",
      #|    workspace_root=None,
      #|  ),
      #|)
    ),
  )
}

///|
/// A token counter is an integer. `Usage`'s derived `FromJson` would read `1.5`
/// as `1`; every other integer on the wire is rejected instead of truncated, and
/// a fabricated count is worse than a dropped line.
test "a fractional usage counter is rejected, not truncated" {
  assert_eq(
    decode(
      (
        #|{"event":"usage","usage":{"prompt_tokens":1.5,"completion_tokens":2,"total_tokens":3,"prompt_cache_hit_tokens":0,"prompt_cache_miss_tokens":1}}
      ),
    ),
    None,
  )
}

///|
/// Keys the decoder does not know are ignored. An engine older than this
/// package wrote every event through `@xlog`, so its lines carry the logger's
/// envelope (`timestamp`, `level`, `source`); a client built against the
/// current wire still reads them.
test "extra keys on a line are ignored" {
  debug_inspect(
    decode(
      (
        #|{"timestamp":"t","level":"INFO","source":"s","event":"assistant_delta","content":"Hel"}
      ),
    ),
    content=(
      #|Some(AssistantDelta(content="Hel"))
    ),
  )
}

///|
/// A line from a newer engine, or one that is not an event at all, is ignored
/// rather than failing the reader.
test "unknown and malformed lines are ignored" {
  assert_eq(@openseek_protocol.parse(Json("not an object")), None)
  assert_eq(@openseek_protocol.parse({ "hello": "world" }), None)
  assert_eq(@openseek_protocol.parse({ "event": "from_a_newer_engine" }), None)
  // `agent_step` without its required payload.
  assert_eq(@openseek_protocol.parse({ "event": "agent_step" }), None)
  // A fractional `step` is not an Int.
  assert_eq(
    @openseek_protocol.parse({ "event": "agent_step", "step": 1.5 }),
    None,
  )
}

///|
test "decodes a workflow's lifecycle brackets" {
  // A workflow announces where it will write and which child ordinals it
  // reserved: the reader is told, because a run inside an opaque `mbtx` call
  // cannot be found by looking.
  debug_inspect(
    decode(
      (
        #|{"event":"workflow_started","id":"wf-5","journal":"/s/run7-wf-5.jsonl","events":"/s/run7-wf-5.events.jsonl","first_child":5,"child_count":32}
      ),
    ),
    content=(
      #|Some(
      #|  WorkflowStarted(
      #|    id="wf-5",
      #|    journal="/s/run7-wf-5.jsonl",
      #|    events="/s/run7-wf-5.events.jsonl",
      #|    first_child=5,
      #|    child_count=32,
      #|  ),
      #|)
    ),
  )
  debug_inspect(
    decode(
      (
        #|{"event":"workflow_finished","id":"wf-5"}
      ),
    ),
    content=(
      #|Some(WorkflowFinished(id="wf-5"))
    ),
  )
}

///|
test "a workflow line missing any coordinate is not an event" {
  // Fail closed: a half-read bracket would point a reader at a path that is
  // not there, or at an ordinal range that is not this run's.
  assert_eq(
    decode(
      (
        #|{"event":"workflow_started","id":"wf-5","journal":"/s/j.jsonl","events":"/s/e.jsonl","first_child":5}
      ),
    ),
    None,
  )
}

///|
test "a workflow's brackets survive the wire unchanged" {
  // `to_json` is the one encoder and `parse` the one decoder; a field the
  // encoder writes under a name the decoder does not read would make an
  // announced run unfindable, silently.
  let started : @openseek_protocol.Event = WorkflowStarted(
    id="wf-5",
    journal="/s/run7-wf-5/journal.jsonl",
    events="/s/run7-wf-5/events.jsonl",
    first_child=5,
    child_count=32,
  )
  assert_eq(@openseek_protocol.parse(started.to_json()), Some(started))
  let finished : @openseek_protocol.Event = WorkflowFinished(id="wf-5")
  assert_eq(@openseek_protocol.parse(finished.to_json()), Some(finished))
}
