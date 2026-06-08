///|
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
pub fn[X] AgentTaskScope::AgentTaskScope(
  group : @async.TaskGroup[X],
) -> AgentTaskScope[X] {
  { group, }
}

///|
pub fn[X] AgentTaskScope::group(
  self : AgentTaskScope[X],
) -> @async.TaskGroup[X] {
  self.group
}

///|
pub fn AgentRuntime::emit_event(
  self : AgentRuntime,
  event : AgentEvent,
) -> Unit {
  ignore(self.events.try_put(event) catch { _ => false })
}

///|
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
