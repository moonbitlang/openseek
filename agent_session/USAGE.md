# Model usage records

Model accounting lives in the existing per-session JSONL file,
`openseek_session-<id>.jsonl`. New writers use header version 2. Readers accept
versions 1 and 2. The first write to a version-1 file upgrades it atomically;
conversation records and their sequence numbers are preserved. Older binaries
that only understand version 1 cannot resume version-2 files.

## Records and reporting

Successful ordinary agent responses retain the existing assistant `usage`
object. Its five numeric fields and zero defaults are unchanged. An optional
`usage_record` beside it adds the attempt's identity and reporting facts.

Compaction and attempts without a durable assistant carrier use a separate
line in the **same file**:

```json
{
  "type": "model_usage",
  "record": {
    "session_id": "example",
    "call": 2,
    "attempt": 1,
    "after_sequence": 4,
    "purpose": "manual_compaction",
    "model": "deepseek-v4-flash",
    "response_id": "provider-response-id",
    "outcome": "completed",
    "report": {
      "reported": true,
      "prompt_tokens": 100,
      "completion_tokens": 0
    }
  }
}
```

- `call` is a session-local model invocation ordinal, including compaction.
  `attempt` is the one-based HTTP attempt within that invocation. A tool loop
  creates a new call for each model request; retrying keeps the call number.
- `after_sequence` anchors the invocation in conversation history. It does not
  consume a message sequence or count as an agent step. Metadata is never sent
  to the model. Atomic rewrites can place metadata after conversation records;
  use its anchor and identity rather than physical line adjacency.
- `purpose` is `agent`, `manual_compaction`, or `auto_compaction`.
- `outcome` is `completed`, `failed`, or `interrupted` for the HTTP attempt.
  `completed` does not imply that later summary validation, tool execution or
  message persistence succeeded. Provider response IDs are optional.
- `report.reported` says whether a usable usage object was returned. Optional
  count fields contain only provider-reported nonnegative integers in the
  supported range. Missing fields are omitted and mean **unknown**; an explicit
  `0` means reported zero. Do not derive missing totals or cache-miss counts.
  Empty usage objects are distinguished from absent usage. Malformed fields
  remain unknown, even when legacy decoding supplies a numeric default.

Within an SSE attempt the latest usage snapshot replaces earlier snapshots;
these are not additive deltas. A valid buffered usage payload is observed on
interruption without delivering extra text callbacks or changing retry policy.

## Reading and deduplication

- `SessionStore::load` restores both conversation and accounting records.
  `Session::usage_records()` returns new-format attempt records in call/attempt
  order, gathering assistant metadata and supplemental lines once each.
- `agent_session/log.parse_with_usage(text)` returns the existing `ParsedLog`
  plus all attempt records in file order, including assistant metadata. Check
  the parsed errors before accounting. `parse_events` remains a compatible
  conversation-only reader and accepts valid metadata lines without errors.
- The JSONL event stream keeps the ordinary `usage` event and adds the same
  `usage_record` field. Supplemental attempts emit `event: "model_usage"` with
  that field. `emit.drain_json` and stdout expose both. The original typed
  `Event` constructors and `emit.drain` remain unchanged; typed consumers keep
  seeing ordinary events and skip metadata-only notifications.

Deduplicate by **`(session_id, call, attempt)`** across the event stream,
assistant records, and standalone lines. Count each key once. A successful
response whose assistant append later fails can appear first as a usage event
and later as a supplemental record with that same key. Session identity is
caller-owned: ephemeral convenience paths can reuse placeholder IDs such as
`one-shot` or a kind name. Keep the enclosing invocation/request scope when
combining those streams, or supply distinct session IDs to the session-based
APIs. This change does not introduce a global ID service.

Each subagent records calls in its own session. Existing child launch metadata
links that session to its parent. `SubagentUsage`, `SubrunFinished` and run-result
`usage` remain legacy successful-response summaries: do not add them to detailed
child attempt records. They exclude compaction and failed attempts and do not
establish whether zero-filled fields were reported. For accounting across
forked histories, inherited records retain the original session identity, so
copying history does not create new spend.

Older assistant records without `usage_record` lack reporting provenance. Their
numeric usage remains readable, but missing usage and zero defaults cannot be
reconstructed into exact counts. An empty new-format record list does not prove
that an old session consumed zero tokens. For each field, sum known reports and
retain an incomplete/unknown indication if any relevant attempt or historical
response lacks that field.

## Persistence hooks and limits

`Client::chat(..., on_attempt=...)` optionally observes each HTTP attempt once,
including errors and cancellation, without changing retry decisions. It captures
usage before response/message decoding and before streamed delta callbacks.

Agent entry points accept an optional `append_usage` hook, parallel to
`append_item`; filesystem adapters should use `SessionStore::append_usage` for
immediate persistence. CLI, serve and managed child entry points wire this hook.
Existing append-item-only adapters still work: their next store-backed message
append atomically flushes queued accounting after checking the durable prefix.
For manual compaction, the optional `on_record` callback exposes the latest
session even when summary generation or validation subsequently fails.

No usage is estimated for transport failures, missing provider reports or
unreported fields. Process termination before cleanup/persistence, storage
failure, and payload bytes that never form valid JSON cannot be recovered into
known usage. Hard termination of a child before it flushes may therefore leave
its accounting incomplete. No disk sidecar, billing system or pricing model is
introduced.
