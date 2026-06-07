///|
pub let default_agent_event_capacity : Int = 32

///|
/// Open event type for agent-loop runtime updates. Concrete stateful tool
/// packages extend this type with their own typed event constructors.
pub(all) extenum AgentEvent {}

///|
/// Per-agent-loop state shared between the main chat loop and side-effectful
/// tools. Constructed once inside `@async.with_task_group` and threaded into
/// tool definitions that need bounded background tasks or runtime updates.
pub struct AgentRuntime[X] {
  /// Task group the agent runs under; tools spawn background tasks as children
  /// of this group so their lifetime is bounded by the agent's.
  priv group : @async.TaskGroup[X]
  /// Bounded event bus (`DiscardOldest`, see `default_agent_event_capacity`)
  /// that background tools post updates to; the main loop drains it between
  /// steps to surface fresh tool output into the conversation.
  priv events : @aqueue.Queue[AgentEvent]
}

///|
pub fn[X] AgentRuntime::AgentRuntime(
  group : @async.TaskGroup[X],
) -> AgentRuntime[X] {
  { group, events: Queue(kind=DiscardOldest(default_agent_event_capacity)) }
}

///|
pub fn[X] AgentRuntime::group(self : AgentRuntime[X]) -> @async.TaskGroup[X] {
  self.group
}

///|
pub fn[X] AgentRuntime::emit_event(
  self : AgentRuntime[X],
  event : AgentEvent,
) -> Unit {
  ignore(self.events.try_put(event) catch { _ => false })
}

///|
pub fn[X] AgentRuntime::drain_events(
  self : AgentRuntime[X],
) -> Array[AgentEvent] {
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
async test "runtime drains queued events" {
  @async.with_task_group() <| group => {
    let runtime = AgentRuntime(group)
    runtime.emit_event(RuntimeTestEvent("ok"))
    let events = runtime.drain_events()
    assert_eq(events.length(), 1)
    guard events[0] is RuntimeTestEvent(value) else {
      fail("expected RuntimeTestEvent")
    }
    assert_eq(value, "ok")
    assert_eq(runtime.drain_events().length(), 0)
  }
}
