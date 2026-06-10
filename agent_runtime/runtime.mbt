///|
/// Capacity of an `AgentRuntime`'s event bus. The bus discards oldest on
/// overflow: runtime updates are progress feedback for the model, so when a
/// noisy watcher outpaces the agent loop, dropping stale updates beats
/// blocking the tool that posts them.
pub let default_agent_event_capacity : Int = 32

///|
/// Open event type for agent-loop runtime updates. Concrete stateful tool
/// packages extend this type with their own typed event constructors.
pub(all) extenum AgentEvent {}

///|
/// Per-agent-loop state shared between the main chat loop and side-effectful
/// tools. It owns runtime updates, while `AgentTaskScope` owns structured
/// background task lifetime for tools that need it.
pub struct AgentRuntime {
  /// Bounded event bus (`DiscardOldest`, see `default_agent_event_capacity`)
  /// that background tools post updates to; the main loop drains it between
  /// steps to surface fresh tool output into the conversation.
  priv events : @aqueue.Queue[AgentEvent]
}

///|
/// Create a runtime with an empty event bus of
/// `default_agent_event_capacity`.
pub fn AgentRuntime::AgentRuntime() -> AgentRuntime {
  { events: Queue(kind=DiscardOldest(default_agent_event_capacity)) }
}

///|
/// Structured-concurrency scope for background work spawned by stateful tools.
/// The type parameter is the return type of the enclosing `with_task_group`.
pub struct AgentTaskScope[X] {
  priv group : @async.TaskGroup[X]
}

///|
/// Wrap the agent loop's task group so stateful tools can spawn background
/// work whose lifetime is bounded by the loop, without taking a dependency on
/// the loop's own types.
pub fn[X] AgentTaskScope::AgentTaskScope(
  group : @async.TaskGroup[X],
) -> AgentTaskScope[X] {
  { group, }
}

///|
/// The underlying task group, for spawning background work that must not
/// outlive the agent loop.
pub fn[X] AgentTaskScope::group(
  self : AgentTaskScope[X],
) -> @async.TaskGroup[X] {
  self.group
}

///|
/// Post one runtime update for the agent loop to pick up on its next step.
/// Never blocks and never fails: on overflow the oldest queued event is
/// discarded, because a fresh update is worth more than a stale one.
pub fn AgentRuntime::emit_event(
  self : AgentRuntime,
  event : AgentEvent,
) -> Unit {
  ignore(self.events.try_put(event) catch { _ => false })
}

///|
/// Take every queued runtime update, oldest first, leaving the bus empty.
/// The agent loop calls this between steps to fold fresh background tool
/// output into the conversation.
pub fn AgentRuntime::drain_events(self : AgentRuntime) -> Array[AgentEvent] {
  let events : Array[AgentEvent] = []
  for ;; {
    let next = self.events.try_get() catch { _ => None }
    match next {
      None => return events
      Some(event) => events.push(event)
    }
  }
}

///|
extenum AgentEvent += {
  RuntimeTestEvent(String)
}

///|
test "runtime drains queued events" {
  let runtime = AgentRuntime()
  runtime.emit_event(RuntimeTestEvent("ok"))
  let events = runtime.drain_events()
  assert_eq(events.length(), 1)
  guard events[0] is RuntimeTestEvent(value) else {
    fail("expected RuntimeTestEvent")
  }
  assert_eq(value, "ok")
  assert_eq(runtime.drain_events().length(), 0)
}

///|
async test "task scope exposes structured task group" {
  @async.with_task_group() <| group => {
    let scope = AgentTaskScope(group)
    scope.group().spawn_bg(no_wait=true) <| () => { () }
  }
}
