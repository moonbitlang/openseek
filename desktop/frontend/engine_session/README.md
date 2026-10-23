# Shared OpenSeek command handling

Local and Cloud use this package for command interaction and native event state.
Local and Cloud share the full `Model::openseek_commands` catalog, including
prompt workflows (`/simplify` and `/ultrareview`). The shared composer expands
prompt commands before normal submission. Cloud offers the same catalog before
and after session creation. Any actual command submission creates the session
when needed, establishes its SSE baseline, then sends that command once. Opening
a menu or editing a goal does not create a session. The shared composer moves its
cached editor state to the returned session identity, retaining unsent input.

For a native command, register its action in `slash_action`, add its menu entry
to that shared catalog, and implement any new UI state in this package once.
A native command without extra interaction uses `Send(command)`.

- Each Local and Cloud conversation stores `State` directly. Goal drafts, pending
  identities and compaction phases are not mirrored in host-specific fields.
  Each host also stores `Stream` directly for provisional response and reasoning.
- `State::act` edits or submits command input and returns a native command effect.
- Adapters normalize transport responses to `Delivery`. `State::delivered` handles
  acceptance, definite refusal and unknown delivery, fencing late callbacks by
  request identity. Acceptance alone never completes goal or compaction.
- `State::observe_compaction` restores control snapshots without erasing a newer
  in-flight request on the same observation connection.
- `State::event`, `State::restore_goal`, and `Stream::event` handle native receipts,
  durable confirmation, and provisional text. They do not append a second transcript.
- Local's adapter resolves placement and launch settings, then calls `agent.command`.
  The host uses native commands with shared launch settings and its existing
  admission checks and writer. Retired goal/compact endpoints have no adapters. Run-bound operations
  require an exact run ID belonging to the requested session.
- Cloud's adapter submits HTTP commands and observes the session SSE. HTTP acceptance
  is not native completion. Observation recovery never resubmits commands.

Local receives durable commits; Cloud refreshes the native session document at
semantic boundaries. These synchronization paths remain host-specific, as do
connection ownership and the existing product queues. Neither adapter should
implement a second command-specific editor or event reducer.
