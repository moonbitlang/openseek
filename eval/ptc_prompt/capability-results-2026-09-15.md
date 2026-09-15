# Published SDK capability comparison — 2026-09-15

## Setup

SDK-only baseline `70b2af753` versus the session-owned PTC host. Both received
the identical updated system prompt, `deepseek-v4-flash`, free tool choice,
24 steps, and 600 seconds. Three repetitions of each case per variant;
concurrency three. Binary and prompt hashes are in the accompanying JSON ledger.

The search scorer accepts either the baseline's Markdown source bullets or
the candidate's structured sources. This normalization fixes a candidate-only
scoring requirement; all completed trials were rescored. File checks compare
bytes, including line endings.

## Results

| Case | Baseline pass | Candidate pass | Median seconds B / C | Mean total tokens B / C |
|---|---:|---:|---:|---:|
| single_edit | 3/3 | 3/3 | 9.26 / 10.32 | 122,673 / 143,505 |
| computed_edits | 3/3 | 3/3 | 19.19 / 23.88 | 181,446 / 243,283 |
| search | 0/3 | 0/3 | 88.40 / 98.03 | 328,588 / 403,919 |

Both variants passed all six edit trials and failed all three strict search
format/provenance trials. Neither variant used PTC in free-choice trials.
The candidate consumed 2,372,122 total tokens versus 1,898,120 for the baseline
(25.0% more across these nine trials). With this small, noisy sample and no
PTC use, this does not establish either a PTC efficiency gain or its causal cost.

A separate, explicitly requested SDK-use execution smoke passed the twelve-file
computed edit oracle using one `@tools.multi_edit` call through the published
SDK. It took 42.88 seconds, 323,304 tokens, and recovered from four outer tool
errors; no nested call failed. This validates model-driven SDK use, not a
performance comparison.

## Limits and follow-up

Search checks require an exact observed URL on an official documentation host;
they can reject reformatted fragments and do not grade page semantics. The
edit cases are small and do not exercise a realistic parser implementation.
No claim of universal non-regression follows from these results.

The requested larger comparison is a MoonBit YAML parser with independent
withheld tests; its setup and results are recorded separately.

Raw logs and workspaces remain at `/tmp/openseek-ptc-capability-ab-20260915`
and `/tmp/openseek-ptc-sdk-smoke-20260915`. No credentials are copied to the ledger.
