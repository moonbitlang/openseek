# PTC review closure

This is the review record of the whole feature as it was reviewed on
`codex/ptc-standalone` (#1532). The feature then landed as small PRs (see
[the architecture note](programmatic-tool-calls.md)); a second review pass per
slice found and fixed three more defects: a handoff after revocation that kept
the foreground observer, a cancelled gate waiter that failed its task group,
and an ending hook skipped on the session-cancellation path.
The published SDK remains `bobzhang/openseek_tools@0.1.0`; wire v1 and its public
JSON arguments are unchanged.

## Commit review order

1. **Tool contracts and file serialization** — explicit callable opt-in, JSON result
   metadata, and a shared file gate with cancellation-after-grant coverage.
2. **Process and background-job lifecycle** — synchronous ending hooks, bounded
   metadata publication, frozen terminal records, and wire/session metadata.
3. **Bounded PTC service** — loopback admission, capability lifetime, executor
   deadlines, trace bounds, and cancellation regressions.
4. **mbtx and agent integration** — published SDK calls, normal background
   handoff, saved-source snapshots, and agent-loop trace retention.
5. **Desktop nested tool calls** — full/minimal cards, edit diffs, live jobs,
   neutral historical snapshots, and browser regressions.
6. **Prompts and review documentation** — explicit SDK examples, selective PTC
   guidance, architecture invariants, and this review record.
7. **Evaluation harness and results** — reproducible capability/YAML checks and
   historical prompt A/B evidence. Read this last; the JSON reports dominate
   the non-runtime diff and are not production inputs.

Commits are ordered for cumulative review, with dependent constructor/codec
updates beside their owning layer. (Historical: this describes the unsplit PR.
The SDK implementation was already on main (#1518) and later moved to a
call-only API in 823bb9cdb; the split PRs changed no SDK files.)

## Design

One session-owned loopback service invokes existing leaf executors. Each program
owns a revocable capability and bounded trace. The same registration moves to
its background job; no second server or scheduler is created. Supported wasm
runs default to PTC, retain normal background handoff, and support explicit opt-out.

Both direct and RPC file operations share the file gate. A saved-script read
also takes that gate to capture a consistent snapshot, then releases it before
compilation or waiting for the child. Stateful custom RPC tools retain their own
serialization gate. Both gates check cancellation after acquiring access, since
a mutex grant can win against cancellation before its waiter resumes.

Stop initiation and observed process exit revoke admission synchronously, before
output draining. Finalization joins calls without holding either execution gate,
publishes their final trace, and releases the live observer. Terminal jobs freeze
their data. Completed mutations remain in the trace on launcher or handoff error.

Trace publication is part of the admission-to-execution deadline and also has a
separate bound. Cancellation records interruption in memory; it does not repeat
protected publication from the executor. `Started`/`Updated` storage writes under
the publication gate have a five-second deadline and expose persistence failures;
the once-per-job terminal write is exempt so it is delayed, never lost. This
removes the PTC-induced unbounded publication wait without adding a
notification scheduler.

## Review findings resolved

| Finding | Resolution |
|---|---|
| Revocation followed output draining/publication | Synchronous execution-ending hook; asynchronous join remains separate. |
| Cancelled waiter could still mutate after receiving a lock | Cancellation checks after both gate acquisitions, with grant-before-cancel tests. |
| Cancellation reached a timeout wrapper before the actual executor | Track the executor directly; expiry revokes and cancels it synchronously before unwinding the HTTP waiter. |
| Saved source could expose a partial edit or rollback | Capture source and validate bundled containment inside the file gate. |
| Handoff failure discarded completed RPC traces | Normalize ordinary errors inside the registration and attach its final trace. |
| Incomplete/oversized headers bypassed request limits | Bounded one-request HTTP admission before executor reservation. |
| Publication lay outside deadlines and repeated during cancellation | Include initial publication in the request budget; bound notification/storage waits; publish interruption in finalization. |
| Immutable transcript snapshots showed live calls forever | Explicit neutral Snapshot outcome and owning job reference; live jobs retain live status. |
| Terminal jobs retained live program suppliers | Freeze final metadata after cleanup. |
| Tests swallowed assertion failures | Correct the expected budget message and assert wrapper success outside callbacks. |

The async HTTP dependency does not expose a bounded-header parser. The host
therefore reads a deliberately small HTTP envelope: one HTTP/1.1 POST,
Content-Length or plain chunked framing, bounded headers/body/total bytes, and no
connection reuse, extensions, trailers, or ambiguous framing. It still uses the
existing HTTP response writer and published SDK. No dependency fork is required.

The client-side consequences (disconnect is not a cancellation, a lost reply may
follow a successful mutation, no automatic retry) are specified in the README's
[protocol section](../../agent_tool/ptc/README.mbt.md#protocol-and-bounds).

## Simplifications retained

- One Service-based mbtx setup path; remove the separate `program_tools` route
  and production `ptc.run` bracket.
- Decode mbtx input once and filter callable tools once.
- Reuse existing process supervision, job persistence, file validation, rollback,
  and Desktop cards.
- Keep the execution and publication milestones that encode real ownership
  boundaries. Further boolean/enum or callback cleanup is optional, not a reason
  to disturb working lifecycle code.

## Independent review

Fresh Codex CLI sessions reviewed the entire cumulative feature with high
reasoning, read-only access, no memories, and no subagents. The final verification
approved the architecture: the remaining deadline/grant P2 is closed and no
concrete blocker remains. It verified immediate cancellation before timer unwind,
post-acquire guards, timer cleanup, trace reservation, join-before-acknowledgment,
and preservation of completed calls. The final verdict was: "Architecture
sign-off: approved. The sole remaining P2 is closed; no concrete blocker remains."
That review covered the complete pre-rebase feature; the standalone rebase
retains it and is validated separately below. Full raw review transcripts remain
local under `.moonagent/eval_runs/ptc-whole-review-20260915/`.

This is an engineering review and test result, not a proof against all failures.
The submitted-I/O limitation below remains explicit.

## Validation

The results below cover the completed pre-rebase feature. On the standalone
branch, `moon info`, `moon fmt`, `just check`, and all 13 evaluation-harness
tests passed. The PR records the fresh full test/build and browser results.
A byte comparison against the preserved reviewed tree found only upstream
Desktop import/module names and comments, plus this review documentation.


- `just check` and `just build`: passed (native and JS).
- Full offline `just test`: **3,179 native**, **3,269 JS**, **38 cram** cases,
  plus CLI turn-finish and bundled-workflow integration.
- Final RPC regressions: **23/23 native and 23/23 wasm**. These include HTTP
  framing/fragmentation, both cancellation orderings, publication/deadline waits,
  handled timeout errors, trace retention, and capability lifecycle.
- Real published-SDK fixtures with a wasm host: foreground calls, background
  handoff, stale edits, stop, unfinished calls at exit, failed adoption, and
  consistent saved-source reads passed.
- Wasm process/job tests: **46/46**, plus the file-gate grant/cancel regression.
- Browser suite: **22/23 passed**. All PTC full/minimal, live-job, edit-diff,
  and reload cases passed. The unrelated Codex partial-output case fails during
  draft setup because Send remains disabled, before it starts any tool. A focused
  retry reproduced this; no production Codex draft code was changed here.

The first full native run passed 3,168 of 3,169 tests. Its sole failure was the
unrelated live Kimi multi-turn smoke test: the remote model did not produce the
expected final response. The offline gate and focused final regressions above passed.

## A/B interpretation

The [expanded YAML results](../../eval/ptc_prompt/yaml-results-2026-09-15.md) and
[capability results](../../eval/ptc_prompt/capability-results-2026-09-15.md)
carry the numbers. Neither expanded run chose PTC, so they establish no PTC
efficiency gain, and the earlier budget-limited runs support no no-regression
claim either.
