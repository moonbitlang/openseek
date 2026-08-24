///|
/// Model-visible input supplied while a turn is already in progress.
///
/// Prompt steering is ordinary user redirection. Command steering is contextual
/// output collected by the controller, such as an explicit TUI `!` shell
/// command. Notice steering is a system notification pushed by a tool, such as a
/// background job announcing it has finished. All variants are delivered to the
/// model as user-role content, but consumers may render/acknowledge them
/// differently.
pub(all) enum SteerInput {
  Prompt(String)
  Command(String)
  Notice(String)
}

///|
/// Open event type for typed runtime updates emitted by tools.
///
/// `AgentEvent` is an `extenum` so tool packages can add their own event
/// constructors without making `agent_runtime` depend on those tools. The
/// runtime stores and drains values opaquely; interpretation belongs to the
/// agent loop or a tool-specific renderer/query function.
///
/// Use this for background state that should be visible at agent step
/// boundaries, such as long-running tool progress snapshots. Do not use it for
/// mid-turn user steering text; use `queue_steer` for that lossless channel.
pub(all) extenum AgentEvent {}

///|
/// Per-agent-loop runtime state shared with side-effectful tools.
///
/// `AgentRuntime` owns three pieces of loop-scoped state:
///
/// - the raw `workspace_root` used by local tools to resolve relative paths;
/// - a bounded, lossy event bus for typed background runtime updates;
/// - an unbounded, lossless queue for typed mid-turn steering input.
///
/// It does not own background task lifetime. Tools that need to spawn bounded
/// background work receive an `AgentTaskScope` alongside the runtime.
pub struct AgentRuntime {
  /// Workspace root used by local tools when resolving relative paths.
  /// Defaults to "." so direct package users keep current-directory behavior.
  priv workspace_root : String
  /// Bounded event bus (see `default_agent_event_capacity`) that background
  /// tools can post updates to; consumers choose when and how to drain and
  /// render retained tool output.
  priv events : @aqueue.Queue[AgentEvent]
  /// Unbounded queue of typed mid-turn input. Deliberately separate from the
  /// lossy event bus: a noisy watcher may fill `events` and cause later runtime
  /// updates to be ignored, but user-visible input must never be the casualty.
  priv steers : @aqueue.Queue[SteerInput]
  /// Where a tool's permission question goes, when anything can answer one
  /// (see `ask_approval`). `None` is the fail-closed default: a runtime with
  /// no channel refuses every ask without dispatching it anywhere.
  ///
  /// A bare function rather than a service type, so a tool package asking for
  /// approval does not acquire a dependency on the protocol, the engine, or
  /// whichever controller happens to be attached.
  priv approval : (async (ApprovalAsk) -> ApprovalOutcome)?
}

///|
/// Create a loop-scoped runtime.
///
/// `workspace_root` defaults to `"."` and is stored exactly as supplied; this
/// constructor does not canonicalize it, check that it exists, or make it
/// absolute. Local tools decide how to resolve paths against it.
///
/// The returned runtime starts with an empty lossy event bus using
/// `default_agent_event_capacity` and an empty unbounded steering queue. The
/// constructor does not perform I/O.
///
/// `approval` is the channel a tool's permission question is dispatched to.
/// Omitting it is the fail-closed default: `ask_approval` then answers
/// `Unavailable` without asking anyone, which is what every caller that has no
/// human attached — and every test that does not care — wants.
pub fn AgentRuntime::AgentRuntime(
  workspace_root? : String = ".",
  approval? : async (ApprovalAsk) -> ApprovalOutcome,
) -> AgentRuntime {
  {
    workspace_root,
    events: Queue(kind=DiscardOldest(default_agent_event_capacity)),
    steers: Queue(kind=Unbounded),
    approval,
  }
}

///|
/// Return the workspace root string stored in this runtime.
///
/// The value is exactly the constructor argument, or `"."` when omitted. It is
/// not normalized or validated by `agent_runtime`.
pub fn AgentRuntime::workspace_root(self : AgentRuntime) -> String {
  self.workspace_root
}

///|
/// Structured-concurrency handle exposed to stateful tools.
///
/// `AgentTaskScope[X]` wraps the `@async.TaskGroup[X]` owned by the enclosing
/// agent loop. Tools use it to spawn background tasks that must terminate when
/// the loop's task group exits. The type parameter `X` is the return type of
/// that enclosing task group; it is carried through so MoonBit's task-group type
/// remains precise.
pub struct AgentTaskScope[X] {
  priv group : @async.TaskGroup[X]
}

///|
/// Wrap an existing task group for tool-facing use.
///
/// This constructor does not create a task group. Call it inside
/// `@async.with_task_group` and pass the active group. The resulting scope is a
/// thin capability object: whoever receives it can spawn work in that group.
pub fn[X] AgentTaskScope::AgentTaskScope(
  group : @async.TaskGroup[X],
) -> AgentTaskScope[X] {
  { group, }
}

///|
/// Return the wrapped task group.
///
/// Use this to call `spawn` or `spawn_bg` for background tool work. Tasks
/// spawned through this group follow the normal `@async.with_task_group`
/// lifetime and failure rules; `AgentTaskScope` does not add its own
/// cancellation or error handling.
pub fn[X] AgentTaskScope::group(
  self : AgentTaskScope[X],
) -> @async.TaskGroup[X] {
  self.group
}

///|
/// Queue one typed steering input for the agent loop.
///
/// Steering is the lossless companion channel to `emit_event`: it is stored in
/// an unbounded queue, so event-bus overflow cannot discard it. The text is
/// stored exactly as supplied inside its variant; this method does not trim,
/// deduplicate, or drop blank strings. The agent loop may apply its own
/// filtering when it drains.
pub fn AgentRuntime::queue_steer(
  self : AgentRuntime,
  input : SteerInput,
) -> Unit {
  ignore(self.steers.try_put(input) catch { _ => false })
}

///|
/// Drain all queued steering inputs, oldest first.
///
/// The returned array contains exactly the raw values queued since the previous
/// drain, unless another caller drained them first. The queue is empty after
/// this call. This method does not trim or filter; consumers decide how to treat
/// blank steering input.
pub fn AgentRuntime::drain_steers(self : AgentRuntime) -> Array[SteerInput] {
  drain_queue(self.steers)
}

///|
/// Drain a queue into an array, oldest retained first, until it reports empty.
///
/// Shared by `drain_events` and `drain_steers`. `try_get` may raise on a closed
/// queue; that outcome is treated as "no more items" so draining terminates.
fn[T] drain_queue(queue : @aqueue.Queue[T]) -> Array[T] {
  let items : Array[T] = []
  while (queue.try_get() catch { _ => None }) is Some(item) {
    items.push(item)
  }
  items
}

///|
extenum AgentEvent += {
  RuntimeTestEvent(String)
}

///|
test "runtime drains queued events" {
  let runtime = AgentRuntime()
  assert_eq(runtime.workspace_root(), ".")
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
test "runtime stores an explicit workspace root" {
  let runtime = AgentRuntime(workspace_root="/tmp/openseek-workspace")
  assert_eq(runtime.workspace_root(), "/tmp/openseek-workspace")
}

///|
test "steering input survives an event-bus flood" {
  let runtime = AgentRuntime()
  runtime.queue_steer(Prompt("turn left"))
  // Flood the lossy event bus far past its capacity: later runtime updates may
  // be ignored, but the steering queue is a separate lossless channel.
  for index in 0..<(default_agent_event_capacity * 3) {
    runtime.emit_event(RuntimeTestEvent("noise \{index}"))
  }
  runtime.queue_steer(Prompt("turn right"))
  let steers = runtime.drain_steers()
  assert_eq(steers.length(), 2)
  assert_true(steers[0] is Prompt("turn left"))
  assert_true(steers[1] is Prompt("turn right"))
  assert_eq(runtime.drain_steers().length(), 0)
  assert_eq(runtime.drain_events().length(), default_agent_event_capacity)
}

///|
async test "task scope exposes structured task group" {
  @async.with_task_group() <| group => {
    let scope = AgentTaskScope(group)
    scope.group().spawn_bg(no_wait=true) <| () => { () }
  }
}
