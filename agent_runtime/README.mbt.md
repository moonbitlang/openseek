# Agent Runtime

`agent_runtime` owns the generic per-agent-loop runtime: the structured
concurrency task group and a bounded event queue for background tool updates.
It deliberately does not know about concrete tools.

## API Shape

- `AgentRuntime(group)`: create loop-scoped runtime state inside
  `@async.with_task_group`.
- `AgentRuntime::group`: expose the task group to stateful tools that need
  bounded background tasks.
- `AgentRuntime::emit_event`: enqueue a typed runtime event.
- `AgentRuntime::drain_events`: drain pending events for the agent loop.
- `AgentEvent`: open `extenum` extended by concrete tool packages.

Tool packages that need typed background updates extend `AgentEvent` from their
own package. For example, `agent_tool/moon_check` adds `MoonCheckUpdate` without
making this package depend on `moon_check`.
