# Agent Runtime

`agent_runtime` owns per-agent-loop infrastructure without knowing about
concrete tools. `AgentRuntime` carries the bounded event queue for background
tool updates, while `AgentTaskScope[X]` carries the structured-concurrency task
group for tools that need bounded background work.

## API Shape

- `AgentRuntime()`: create loop-scoped event state.
- `AgentTaskScope(group)`: wrap a `@async.TaskGroup[X]` inside
  `@async.with_task_group` for stateful tools that need bounded background
  tasks.
- `AgentTaskScope::group`: expose the task group to task-spawning tool
  implementations.
- `AgentRuntime::emit_event`: enqueue a typed runtime event.
- `AgentRuntime::drain_events`: drain pending events for the agent loop.
- `AgentEvent`: open `extenum` extended by concrete tool packages.

Tool packages that need typed background updates extend `AgentEvent` from their
own package. For example, `agent_tool/moon_check` adds `MoonCheckUpdate` without
making this package depend on `moon_check`.
