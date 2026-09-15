# SDK-first programmatic tool calls

## Architecture and standalone review

1. **SDK — #1518, merged and published.** `bobzhang/openseek_tools@0.1.0`
   exposes `@tools.call("edit", arguments)`, `@tools.call("multi_edit", arguments)`,
   `@tools.call("web_search", arguments)`, and `@tools.call(name, arguments)`.
   Every arguments value is the same JSON object used by the direct tool.
   Validation and defaults belong to the host. `CallResult` has `content`,
   `is_error`, and optional `data`. Wire protocol v1 and the SDK API are unchanged.
2. **Host.** One session-owned loopback HTTP listener dispatches
   registered leaf tools. Each script receives a separate random capability,
   active-call set, and trace. The SDK discovers it through `OPENSEEK_PTC`.
   The host does not rewrite source or inject declarations.
3. **Desktop.** Reuse existing tool cards and edit diffs for nested
   results. Background jobs display live calls and retain them after reload.
   Cleanup errors are visible even when the process exited with code zero.
4. **Prompts and evaluation.** Document the version-pinned SDK import,
   direct `moonbitlang/async` import, default activation, background behavior,
   error handling, and printed-output boundary. Keep direct calls and
   `multi_edit(edits_file=...)` available.

The feature landed as small PRs split from #1532, each reviewed on its own:
#1541 structured result data and the `program_callable` opt-in, #1542 the
shared file gate, #1543 the job finish sequence and ending hook, #1546 desktop
nested cards, #1545 the PTC service package, then the mbtx/agent integration,
these prompts and docs, and #1547 the evaluation harness. The already-merged
SDK #1518 is separate. The [review record](ptc-review-closure.md) documents
the whole-feature review that preceded the split.

## Default activation and lifetime

PTC defaults to true when a session service is available and the run is wasm
without escalation or subrun. Explicit false opts out. Explicit true in an
incompatible mode errors; omitting it preserves those other modes.

Normal mbtx timing stays unchanged: quick scripts return inline; longer scripts
move to background jobs. The job retains its registration and publishes trace
updates through the existing job metadata path. `job_output` returns the trace;
`job_stop` stops the process and its active calls. No second scheduler or RPC
server is created for the background job. Standalone hosts without a session
service create a scoped `Service` and pass it to mbtx. Without a job runtime,
the same registration stays foreground. There is no second mbtx setup API.

At process completion, stop, or session teardown:

1. Revoke capabilities synchronously at stop initiation or observed process exit,
   before output draining or publication. Mark pending calls interrupted immediately.
2. Cancel and join active leaf calls without holding a file or publication lock.
3. Retain the final trace, including on launcher or handoff failure.
4. Finish launcher cleanup and publish the terminal job record.

An exit-zero process with unfinished calls records a cleanup error. Completed
mutations are not rolled back by cancellation. Transport failure can follow a
successful mutation; neither client nor host retries it automatically. A socket
disconnect is not an acknowledged cancellation. Accepted calls remain owned by
the program until completion, timeout, program exit, or explicit stop.

## Race and deadlock invariants

The RPC listener runs beside the child-process wait and invokes executors
directly. It never asks the waiting agent loop to dispatch a nested request.
The outer mbtx wait owns no file-operation gate. Direct and RPC file operations
share the session's `FileStateMap` gate over validation, writes, checks, and
rollback. After acquiring the gate, recheck cancellation before entering the
mutation: a lock handoff can otherwise win against a cancelled waiter. Stateful
RPC leaves also serialize across script registrations.

Only explicitly enabled leaf tools are callable. Recursive mbtx, finish, goal,
plan, and job controls remain unavailable. Callable executors must not reacquire
the file gate or wait for work on the blocked agent loop. Sequential client
calls alone would not establish these invariants.

After handoff, trace observers publish to the owning job, not the foreground
result slot. Cleanup joins request executors before releasing their registration;
HTTP handler cancellation also joins its executor. Closed registrations cannot
acquire a new observer. Terminal records reject later metadata updates and
freeze their data instead of retaining a live program supplier. Transcript
results render unfinished calls as historical snapshots, without live spinners
or success checks; the job panel follows live metadata.

## Bounds

- Random per-script bearer capability; loopback listener rejects unauthenticated
  and browser-origin requests.
- 64 active registrations, 16 connections per session; 64 calls and four active
  calls per script.
- 8 KiB aggregate request line/headers, 64 KiB request bodies, 128 KiB total
  framing; a five-second admission deadline starts at acceptance. One HTTP/1.1
  POST per connection, with Content-Length or plain chunked framing.
- 120-second executor deadline including initial trace publication and queueing; 125-second SDK request
  deadline; bounded sends.
- 64K-character serialized replies. Oversized results explicitly state that
  execution occurred and must not be retried just to retrieve output.
- 512 KiB retained trace plus framing, below the durable job reader's 1 MiB cap.
  The client receives its full bounded response even when the retained trace
  explicitly omits that result. Reserve trace space before executing a request.

## Validation and release

The published SDK resolves in real `.mbtx` processes. SDK-only tests exercise
public calls through environment discovery and mock HTTP on native and wasm.
Host regression tests cover background edits, stale edits after foreground
changes, opt-out, active and queued cancellation, session teardown, unfinished
calls at process exit, trace bounds, and durable job metadata. The same real-SDK
background fixtures pass with a wasm OpenSeek host.

Required repository gates are `just check`, `just test`, and `just build`.
Desktop adds JS transcript/component/jobs tests and browser reload, diff, live
status, and cleanup-failure tests. The standalone PR includes the completed
review fixes; merging #1518 did not authorize merging this feature.

For capability A/B, compare SDK-only baseline commit `70b2af753` against the
candidate with the **same prompt**, model, fixture bytes, limits, and free tool
choice. Record both binary hashes and equal prompt hashes. Do not require PTC
from the baseline. Use byte-exact edit oracles and observed-source URL checks.

The prior 48-trial experiment remains historical prompt-only evidence: both
sides used the old injected PTC client. It does not establish performance or
regression claims for this implementation. Record new results separately and
state the limits of the sample.

The published-SDK [capability comparison](../../eval/ptc_prompt/capability-results-2026-09-15.md)
and [YAML parser comparison](../../eval/ptc_prompt/yaml-results-2026-09-15.md)
are complete. The parser's initial 64-step/15-minute cohort finished no runs;
the fresh 128-step/30-minute pair both finished and passed all 46 withheld cases.
One initial candidate demonstrated a computed 42-edit SDK batch. The expanded
pair chose no PTC, so it establishes no PTC efficiency gain. Keep selective
prompt guidance, direct tools, and the larger coding-benchmark allowance.

Trace notifications have a separate five-second deadline. Cancellation records
interruption in memory and joins the executor; it does not repeat protected
publication from the executor's cancellation handler. Finalization publishes
the final snapshot. Publication failures are retained as `ptc_trace_error` and
surface as an outer result or job cleanup error. Job storage writes also have a
five-second deadline while holding the publication gate; timeout releases that gate
and emits the existing persistence-error field. Saved script reads use the file
gate only to capture a consistent source snapshot, before compilation begins.

Deadlines are cooperative: already-submitted filesystem I/O and protected
rollback must settle safely. They are not a hard-stop guarantee for hung storage.
