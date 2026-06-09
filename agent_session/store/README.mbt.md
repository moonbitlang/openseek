# OpenSeek Agent Session Store

`bobzhang/openseek/agent_session/store` is the native filesystem persistence
layer for typed OpenSeek sessions.

Each session lives under:

```text
<root>/sessions/<session-id>/
  session.json
  events.jsonl
```

`session.json` stores the small typed header. `events.jsonl` is the append-only
event log; loading a session replays those typed `SessionEvent` records into an
immutable `agent_session.Session`.

Use `SessionStore::compact` to append a validated summary event. The covered raw
events remain in the JSONL log, but `Session::chat_messages` replaces those
events with the summary when building model context.

Use `SessionStore::list` to enumerate known sessions under the store root.
