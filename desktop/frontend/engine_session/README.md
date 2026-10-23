# Shared OpenSeek command handling

Local and Cloud use this package for command interaction and native event state.
Register a slash action in `slash_action`, add its menu entry in the shared
`Model::engine_commands`, and implement any new UI state in this package once.
A native command without extra interaction uses `Send(command)`.

- `State::act` edits or submits command input and returns a native command effect.
- `State::reject` handles definite refusal; transport uncertainty leaves input pending.
- `State::event`, `State::restore_goal`, and `Stream::event` handle native receipts,
  durable confirmation, and provisional text. They do not append a second transcript.
- Local's adapter resolves placement and launch settings, then calls `agent.command`.
  The host reuses its existing command admission and writer. Run-bound operations
  require an exact run ID belonging to the requested session.
- Cloud's adapter submits HTTP commands and observes the session SSE. HTTP acceptance
  is not native completion. Observation recovery never resubmits commands.

Local receives durable commits; Cloud refreshes the native session document at
semantic boundaries. These synchronization paths remain host-specific, as do
connection ownership and the existing product queues. Neither adapter should
implement a second command-specific editor or event reducer.
