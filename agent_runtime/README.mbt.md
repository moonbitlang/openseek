# OpenSeek Agent Runtime

`bobzhang/openseek/agent_runtime` owns the small piece of per-agent-loop state
that side-effectful tools need but concrete tool packages should not own:

- the workspace root used by local tools to resolve relative paths;
- a bounded runtime event bus for background tool updates;
- a lossless steering queue for mid-turn user input;
- a task-group wrapper for structured background work.

The package deliberately does not know about concrete tools. Tool packages add
their own variants to the open `AgentEvent` type and decide how to render or
query those variants later.

## API Contracts

The public API is intentionally small:

```mbt nocheck
let runtime = @agent_runtime.AgentRuntime(workspace_root=".")
let root = runtime.workspace_root()

runtime.emit_event(MyToolUpdate("done"))
let events = runtime.drain_events()

runtime.queue_steer(Prompt("also check tests"))
let steers = runtime.drain_steers()

@async.with_task_group() <| group => {
  let scope = @agent_runtime.AgentTaskScope(group)
  scope.group().spawn_bg(no_wait=true) <| () => { ... }
}
```

`AgentRuntime(workspace_root=...)` stores the workspace root exactly as supplied.
It does not canonicalize, validate, create, or stat the directory. The default is
`"."`.

`emit_event` writes to a lossy queue with capacity
`default_agent_event_capacity` (`32`). `emit_event` uses nonblocking `try_put`;
when the bus is full, the incoming event is ignored and already queued events
are retained. Runtime events are for progress/status feedback, where losing some
updates is better than blocking the tool that posts them.

`queue_steer` writes typed `SteerInput` values to a separate unbounded queue.
Steering input is lossless with respect to event-bus overflow and is stored
exactly as supplied; the runtime does not trim, deduplicate, or drop blank
strings inside either variant.

`drain_events` and `drain_steers` return queued values oldest-first and leave
their respective queues empty.

`AgentTaskScope[X]` wraps an existing `@async.TaskGroup[X]`. It does not create a
task group or add cancellation behavior; it just passes the loop's structured
concurrency capability to tools that need bounded background tasks.

## Runtime Events

`AgentEvent` is an open `extenum`. A tool package extends it with typed event
constructors, then emits those values through `AgentRuntime::emit_event`.

```mbt check
///|
extenum @agent_runtime.AgentEvent += {
  ReadmeRuntimeEvent(String)
  ReadmeFloodEvent(Int)
}

///|
fn readme_event_text(event : @agent_runtime.AgentEvent) -> String {
  match event {
    ReadmeRuntimeEvent(text) => text
    ReadmeFloodEvent(index) => "event \{index}"
    _ => "unknown"
  }
}

///|
test "drain typed runtime events" {
  let runtime = @agent_runtime.AgentRuntime(workspace_root="/tmp/workspace")
  debug_inspect(
    [runtime.workspace_root()],
    content=(
      #|["/tmp/workspace"]
    ),
  )

  runtime.emit_event(ReadmeRuntimeEvent("moon_check: running"))
  runtime.emit_event(ReadmeRuntimeEvent("moon_check: done"))

  debug_inspect(
    [
      for event in runtime.drain_events() => readme_event_text(event)
    ],
    content=(
      #|["moon_check: running", "moon_check: done"]
    ),
  )
  debug_inspect(
    [
      for event in runtime.drain_events() => readme_event_text(event)
    ],
    content=(
      #|[]
    ),
  )
}
```

## Event Overflow

The runtime event bus is bounded. Once it is full, later `emit_event` calls do
not displace retained events; the incoming event is ignored. This keeps noisy
background tools from blocking the agent loop or accumulating unbounded memory.

```mbt check
///|
test "event bus keeps retained events when full" {
  let runtime = @agent_runtime.AgentRuntime()
  for index in 0..<(@agent_runtime.default_agent_event_capacity + 2) {
    runtime.emit_event(ReadmeFloodEvent(index))
  }

  let drained = [
    for event in runtime.drain_events() => readme_event_text(event)
  ]
  debug_inspect(drained.length(), content="32")
  debug_inspect(
    [drained[0], drained[drained.length() - 1]],
    content=(
      #|["event 0", "event 31"]
    ),
  )
}
```

## Steering Queue

Steering input is a separate lossless channel. It survives event-bus overflow
and drains oldest-first. The runtime stores typed raw input; filtering blank or
whitespace-only steering is the agent loop's responsibility.

```mbt check
///|
test "steering drains losslessly and raw" {
  let runtime = @agent_runtime.AgentRuntime()
  runtime.queue_steer(Prompt("turn left"))
  for index in 0..<(@agent_runtime.default_agent_event_capacity * 3) {
    runtime.emit_event(ReadmeFloodEvent(index))
  }
  runtime.queue_steer(Prompt(""))
  runtime.queue_steer(Command(" turn right "))

  let drained = runtime.drain_steers()
  assert_eq(drained.length(), 3)
  assert_true(drained[0] is Prompt("turn left"))
  assert_true(drained[1] is Prompt(""))
  assert_true(drained[2] is Command(" turn right "))
  assert_eq(runtime.drain_steers().length(), 0)
}
```

## Task Scope

Use `AgentTaskScope` only inside an existing `@async.with_task_group`. It exposes
the same task group to stateful tools, so background work follows the loop's
normal structured-concurrency lifetime.

```mbt check
///|
async test "task scope exposes the active task group" {
  @async.with_task_group() <| group => {
    let scope = @agent_runtime.AgentTaskScope(group)
    scope.group().spawn_bg(no_wait=true) <| () => { () }
    debug_inspect(true, content="true")
  }
}
```

## When To Use Each Channel

Use `emit_event` for typed, lossy background updates:

- watcher snapshots;
- progress updates;
- best-effort status updates where loss is acceptable.

Use `queue_steer` for user-authored text that must not be dropped:

- mid-turn steering;
- corrections;
- extra instructions gathered while tools are running.

Use `AgentTaskScope` for background tasks that must not outlive the agent loop.
Do not store the raw task group globally or spawn detached work outside the
scope; the point is to keep tool background work bounded by the loop that owns
it.
