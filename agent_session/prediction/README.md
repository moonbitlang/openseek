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
`predict` carries a request id and the durable source sequence. It is accepted
only while idle after a successful turn. Each engine remembers its last attempted
source sequence in memory, so failures, cancellation, and duplicate requests do
not trigger another model call for that version while the process is alive.
A cached completed result is returned on repeat requests.

Only completed predictions are saved to `sessions/<id>/prediction.json`, including
`text: null` when the model chose not to suggest a message. There is no write
before the request, and failures/cancellation are not persisted. Restarting the
engine after an unsuccessful attempt permits another request; older attempt-only or failed
records are ignored. Separate engine processes may make concurrent requests.

Saving reuses the session lock, checks that the source snapshot is still current,
and atomically replaces the result. A late result cannot overwrite a newer turn.
The sidecar follows session archive/delete moves. It never advances the transcript
sequence, enters the agent context, or counts as main-turn usage. New turns
invalidate the old result by sequence. `prediction_result` remains a private
process reply.

The Desktop host forwards requests only to an already live engine. The composer
requests a suggestion for an empty draft after a completed OpenSeek turn, shows
it as placeholder text, and lets Tab copy it into the draft. Acceptance does not
send. Editing, attachments, navigation, and source-version
changes invalidate pending results. Provider failures silently leave the normal
placeholder. Session loading returns matching cached metadata even when no
engine is running, so reopening a chat restores its suggestion without a new
LLM request. Ready suggestions survive local navigation, acceptance, and editing.
They are hidden while the draft has content and reappear when it is cleared,
without another model request. A new turn makes the old suggestion ineligible
by source sequence. Editing still cancels pending requests and ignores late replies.
Codex-backed conversations do not use this path.

There is no global time-based rate limit across different sessions. The 150 ms
composer heartbeat checks eligibility and does not repeatedly call the model:
process-local once-per-version state and saved results deduplicate requests.

Offline coverage includes provider request/output validation, protocol codecs,
composer state transitions, and browser keyboard interaction. Store tests cover
reopening saved results, transcript isolation, legacy attempts, empty suggestions,
stale versions, and malformed metadata. Browser tests verify cancellation and
reopening without a second prediction request.
