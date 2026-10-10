# Next-message prediction

`generate` makes one auxiliary completion from an immutable session snapshot.
It reuses the provider client and the main agent's tool definitions, but does not
run the agent, execute tools, or append messages to the session.
`GenerationResult` distinguishes `Skipped` (no provider request) from
`Completed(text~, usage~)`. A completed response carries token usage
even when `text` is absent; provider and output-validation failures remain errors.

The prompt predicts the user's likely next message, including natural follow-ups
after a completed task such as testing, committing changes, or opening a PR.
It avoids repeating completed actions or inventing unrelated work. Completion
alone does not suppress a suggestion; unclear next steps still return JSON null.

The request starts with the same `Session::chat_messages()` projection as a
normal agent turn and appends a user message containing the prediction prompt.
System instructions, tool calls/results, reasoning, images, and existing
compaction summaries stay intact. The same tool definitions are passed in the
same order to preserve the provider's cached prefix. There is no separate
prediction truncation policy. Returned tool calls are rejected, never executed.
JSON is requested in the appended prompt and parsed/validated locally. We omit
`response_format`: enabling DeepSeek JSON mode reduced reuse of the main request
cache in controlled API comparisons.
The deadline is eight seconds and the output budget is 1,024 tokens, including
reasoning. Returned text must be a nonempty single line of at most 240 UTF-16
code units, or explicit null.

`openseek serve` uses the current provider/model and thinking setting with one
attempt. Changing thinking mode can invalidate the parent cache prefix.
After a successful turn, the engine starts one prediction automatically if it
remains idle: queued work and goal continuation take priority. No client request,
open composer, or connected frontend is required. New commands, background
context changes, and shutdown cancel pending predictions; failed/cancelled turns
and compaction do not trigger them. Resuming a session does not regenerate an old
prediction.

Only completed predictions are saved to `sessions/<id>/prediction.json`, including
`text: null` when the model chose not to suggest a message. There is no write
before the request, and failures/cancellation are not persisted. Separate engine
processes can still make concurrent requests; there is no cross-process lease.

Saving reuses the session lock, checks that the source snapshot is still current,
and atomically replaces the result. The sidecar follows session archive/delete
moves. It never advances the transcript sequence, enters the agent context, or
counts as main-turn usage. New turns invalidate the old result by sequence.
After saving, the engine emits `prediction_result` with its source sequence and
outcome. It has no client request id.

The Desktop host broadcasts completed results to every connected client. Clients
only receive, cache, and display suggestions; they never request or cancel a
prediction. An empty composer shows the suggestion and Tab copies it into the
draft without sending. Editing or adding attachments hides it locally; clearing
the draft restores it. Navigation or typing in one client does not affect another.
Session loading restores persisted results even without a live engine, and a late
snapshot must not erase a newer broadcast. Codex-backed conversations do not use
this path.

Offline coverage includes provider request/output validation, protocol codecs,
result persistence and invalidation, and Desktop broadcast/composer behavior.
