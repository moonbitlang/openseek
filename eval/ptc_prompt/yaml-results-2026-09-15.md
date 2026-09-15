# YAML parser capability comparison — 2026-09-15

## Question and setup

Does making SDK-based programmatic tool calls available improve a realistic
coding task when the model chooses its tools freely?

The task implements a specified JSON-compatible YAML subset in MoonBit. It
has six visible examples and 46 independently authored withheld cases: 30
valid inputs and 16 malformed or explicitly unsupported inputs. This is not
a full YAML conformance benchmark. The grader compiles a separate project
containing the generated implementation and trusted tests; generated tests
are excluded. A positive-control implementation passed 46/46, while a stub
that always rejects input passed only the 16 negative cases.

Both variants use `deepseek-v4-flash`, identical updated system prompts,
identical tasks, and free tool choice. The baseline is the SDK-only merge
`70b2af753`; the candidate adds the session-owned PTC host. Thus this measures
capability availability under the new guidance, not the isolated effect of
changing the prompt. The same frozen binaries are used in both budget cohorts.
The candidate predates the later empty-trace event optimization and Desktop
recovery display fix. Binary, prompt, task, and oracle hashes are in the ledger.

## Initial cohort: 64 steps, 15 minutes

Two trials per variant, concurrency two, alternating pair launch order.
Both the step limit and wall-clock limit can stop a run.

| Trial | Valid / 30 | Reject / 16 | Own tests | Parent steps | Stop condition | PTC calls |
|---|---:|---:|---:|---:|---|---:|
| Baseline 1 | 30 | 16 | 21/21 | 49 | 900 s cap | 0 |
| Candidate 1 | 30 | 16 | 23/23 | 64 | Step cap | 1 |
| Baseline 2 | 30 | 16 | 60/60 | 63 | 900 s cap | 0 |
| Candidate 2 | 29 | 16 | 30/30 | 64 | Step cap | 0 |

None reached a successful finish. Three artifacts passed every withheld test.
The remaining artifact rejects `[1, # comment\n 2, 3]`: its block parser passes
only the first physical line to its flow parser. All of its own 30 tests pass,
showing why independent coverage matters. This run never used PTC, so this
single defect does not identify a failure in the RPC implementation.

| Trial | Outer calls / errors | Parent tokens | Review children / steps | Protected bytes preserved |
|---|---:|---:|---:|---|
| Baseline 1 | 69 / 9 | 6,107,335 | 3 / 68 | No: formatting only |
| Candidate 1 | 81 / 10 | 9,280,864 | 1 / 3 | No: formatting only |
| Baseline 2 | 73 / 12 | 9,080,304 | 1 / 12 | Yes |
| Candidate 2 | 74 / 13 | 9,450,006 | 1 / 7 | No: formatting only |

The first pair had working parsers but spent the remaining budget on review
workflows. Candidate 1 started its review at parent step 62 of 64; Baseline 1
started at step 39 and its three review children accumulated 68 steps. This
motivates a larger allowance for completion; it does not establish that a
larger allowance guarantees a better parser.

## Expanded follow-up: 128 steps, 30 minutes

A fresh matched pair follows the user's observation that 64 steps may be too
small. It starts after the initial cohort ends, uses the same inputs and
binaries, and has one trial per variant. Keep it separate from the original
cohort: the budget change was chosen after observing the first results.

| Variant | Valid / 30 | Reject / 16 | Own tests | Parent steps | Wall time | Finished / preserved bytes |
|---|---:|---:|---:|---:|---:|---|
| Baseline | 30 | 16 | 29/29 | 105 | 1,356.78 s (22.6 min) | Yes / Yes |
| PTC candidate | 30 | 16 | 128/128 | 96 | 1,523.03 s (25.4 min) | Yes / Yes |

Both exited zero, emitted a successful finish, and passed the full strict
oracle including fixture preservation. Both used a review subagent and
completed the subsequent fixes. Their protected files were restored after
formatting, addressing another issue left unfinished in the initial cohort.

| Variant | Outer calls / errors | Parent tokens | Review children / steps | PTC calls |
|---|---:|---:|---:|---:|
| Baseline | 105 / 11 | 16,504,505 | 1 / 25 | 0 |
| PTC candidate | 117 / 18 | 15,933,961 | 1 / 33 | 0 |

The candidate took 12.3% longer in this pair, with 3.5% fewer recorded parent
tokens. Neither is evidence of a PTC effect: the candidate did not import the
SDK or make a nested call, child token costs are unavailable, and this is one
pair. Including review children, the model-step counts were nearly identical
(130 baseline, 129 candidate).

## Observed PTC use

The first candidate used a script importing the published
`bobzhang/openseek_tools@0.1.0` SDK to read three test files, calculate 42
line-anchored helper renames, and call `@tools.multi_edit(Json::object(args))`.
The mbtx call omitted the `ptc` flag, exercising default activation. The nested
call completed without error; the parent journal records 745 ms for the
enclosing script and batch. This demonstrates a useful computed batch, not
an end-to-end speedup or general algorithmic improvement.

Across the initial four trials, 11 direct edit calls were rejected because
`old_string` was not found at the supplied anchor. Computing anchors from the
current file is a plausible use for PTC. The successful batch illustrates that
use, but there is no matched direct-call counterfactual for this exact rename.

The expanded pair used direct tools throughout, with zero SDK imports and
zero nested call traces in the candidate.

## Interpretation and limits

**64 steps was too small for end-to-end completion of these parser workflows.**
The initial cohort finished 0/4 runs; the fresh 128-step/30-minute pair finished
2/2, both scoring 46/46. Keep 128 steps and 30 minutes as the default allowance
for this benchmark. The small sample does not prove every run will finish;
64 steps remains useful as an explicitly budget-limited stress test.

**PTC works, but an end-to-end efficiency gain is not established.** The initial
computed rename demonstrates useful model-driven SDK batching. Most work in
these tasks remained implementation, testing, and review, and the larger pair
chose no PTC. Keep the system prompt's selective guidance and direct tools.
Do not force PTC merely to increase adoption in the benchmark, or describe
added capability as a guarantee of better model behavior.

Correctness, workflow completion, and fixture preservation are separate
outcomes. Three initial runs reformatted the protected manifest and visible
tests; the byte check fails even though their meaning is unchanged. The second
candidate's independent oracle failure is a separate parsing defect.

The first runner could not select a parent journal when review children
existed. Analysis was repaired and frozen artifacts regraded without rerunning
those trials. Their exact OS exit codes and wall times were not checkpointed;
reconstructed log active spans exclude silent waits and are not used for a
latency comparison. The follow-up records execution status and time before
analysis. Step-limit terminal events remain available in the parent journals.

Token figures cover parent usage only when review children exist. Child
counts and steps are reported separately because their full token usage is
unavailable. Cached prompt tokens dominate the reported totals; token counts
are not a dollar-cost estimate. Do not compare them as complete workflow cost.

Passing the 46 cases is evidence for those cases, not proof for every input
in the contract. This small, single-model experiment cannot establish universal
non-regression or statistical superiority. The RPC lifecycle tests address
cancellation, background handoff, shared file state, and teardown directly; model coding
trials are additional behavioral evidence.

Raw artifacts remain in `/tmp/openseek-ptc-yaml-ab-20260915` and
`/tmp/openseek-ptc-yaml-ab-expanded-20260915`. The committed ledger omits raw
model logs and credentials.
