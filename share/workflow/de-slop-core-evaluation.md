# Repeated core campaign — 2026-09-14

The user requested another repository-scale run after rebasing `~/git/core`
on `origin/main`. The clean `caimeox/integer-improve` branch fast-forwarded to
`2a34e7a358266dcd6b653f424f40fe08284bb5dc`; it had no unique commits or local
edits. All audits read that exact checkout. Independent delivery worktrees
start from the same commit. OpenSeek's workflow branch was rebased onto
`cceead9344ba3697fb4abe42ad417e227f5202cf`, preserving both upstream launch
prefixes and the earlier hosted-child cwd override. The rebuilt OpenSeek CLI
uses workflow 0.7.1; all model calls use `deepseek-v4-flash`.

## Scope and completion

| Run | Source files | Scanned lines | Lexical leads | Challenged shards |
| --- | ---: | ---: | ---: | --- |
| Round 3 | 950 | 233,143 | 876 | 7/8 initially |
| Round 3, shard 8 retry | Same inventory | Same inventory | Same inventory | 1/1 scheduled |
| Round 4 with `--known` | 950 | 233,143 | 876 | 8/8 |

These are 950 distinct files scanned twice, not 1,900 different files reviewed.
Shard membership is identical across rounds; only sampled lead windows change.
The two sweeps and one recovery started 33 scouts. All source is enumerated and
lexically scanned; semantic reads remain sampled. Successful shard reports do
not establish complete semantic coverage or repository cleanliness.

Round 3's eighth discovery used ordinary final text rather than `submit_answer`.
Its apparent “Audit complete” was therefore a real `NoReport` failure. The host
inspected that exact failure and retried only shard 8 against the same tree and
immutable workflow snapshot. Both attempts remain in the local journal. Full
CLI runs took about 496 s and 484 s; the targeted recovery took about 199 s.
These include caller overhead, not just scout execution, and are not performance
benchmarks. Parent callers still spent unnecessary reads inspecting metadata;
completion and cost are taken from actual artifacts rather than progress prose.

## What changed in the workflow

Round 3 rediscovered the ASCII and BigInt proposals already in open core PRs
[#4235](https://github.com/moonbitlang/core/pull/4235) and
[#4236](https://github.com/moonbitlang/core/pull/4236), plus the argparse batch
already being processed. Rotating lexical windows alone did not carry campaign
history. The new `--known` input supplies both scouts with bounded, human-curated
site/function dispositions, tied to the exact clean HEAD. Stale, dirty, malformed,
missing, outside-workspace and oversized records fail before any child starts.
The manifest preserves the normalized record; no source is excluded.

Round 4 did not nominate those recorded existing PR edits again. It found
additional work in argparse's same files (environment assignment and unused
private parameters), as well as scalar and Set candidates. That demonstrates
same-file eligibility in this run, not guaranteed novelty. Round number, prompt
changes and stochastic model behavior also changed, so this is not a controlled
estimate of how much `--known` improved discovery. The concurrently recovered
Buffer candidate also appeared in round 4; it was not yet in round 4's input
record and was consolidated into one delivery batch.

Round 3's first discovery proposed String padding wrappers entirely outside
its assigned shard; the challenger rejected the scope violation. Report
validation now requires at least one checked citation within the actual assigned
scope. Dependency/caller citations outside it are still allowed. This rejects
all-outside evidence; it does not prove every claimed edit obeys its scope.

The String `all`/`any` delegation was ACCEPTed by both scouts. The caller tried
exactly `self[:].all(f)` / `.any(f)` while retaining `#locals`: the current
compiler returned error 4163, “This parameter is expected to be local, but it
escapes.” Both probe edits were restored. Criteria now require retaining local
callback/effect contracts and explicitly warn that forwarding between local
methods may still fail compilation. A successful challenge is not a typecheck.

## Candidate dispositions

The delivery batches are argparse value policy, Buffer signed writes, debug
compact formatting, Set mutation probes, and builtin scalar operations. Each
uses a separate branch based on the recorded core commit; the two argparse
rounds belong to one PR rather than duplicate PRs. Publication details appear below.

Other reports retain concrete no-change dispositions:

- Existing ASCII/BigInt/container PRs are reused as history, not republished.
- String `all`/`any` is rejected by the observed compiler failure.
- String padding wrappers are not selected from invalid scope evidence.
- Edit-distance trimming is deferred: the discovery sketch incorrectly omitted
  the prefix offset, which both DP loops still read. A corrected three-value
  helper needs allocation/inlining evidence on early-return paths before its
  maintenance benefit is accepted.
- SortedMap reverse traversal sharing is deferred: yielding key/value pairs to
  implement separate key/value iterators introduces pair construction per
  element. Existing forward iteration is not evidence that this added cost is
  acceptable on reverse iteration.
- Shared cross-package growth, `scalbn`, hex decoding and sorted collection
  builders remain API/ownership follow-ups. The hex sentinel also requires a
  typed migration rather than cementing it in a new shared helper.
- Bitstring receiver unification, a one-line JSON ownership helper and a
  quickcheck diagnostic fragment helper were rejected for concrete receiver/
  allocation concerns or insufficient reduction in maintenance cost.

The Set ACCEPT sketch moved hashing across growth. The implementation instead
keeps each public method's original order and shares only the insertion probe;
identical callback counts alone would not justify reordering user code. This
is a caller correction to the sketch, not a demonstrated runtime regression.
The final diff review must assess the corrected implementation.

## Verification and limits

The final workflow review identified a real isolation defect in the new scope
check. A source removed after inventory caused raw `realpath` failure to abort
the sweep. A fault-injection fixture reproduced that failure before the fix;
resolving scope paths through the typed `AuditInvalid` channel now leaves seven
other shard reports intact and marks only the affected shard incomplete.
The cancellation rethrow was checked by source inspection, not by a cancellation
fault injection. The scout criteria now state the same in-scope
citation requirement enforced by the validator.

That review also caught a vacuous oversized-record test: non-JSON text failed
regardless of the length guard. Its replacement uses valid JSON with otherwise
valid fields and oversized padding, asserting the exact length diagnostic.
Separate blank, over-6,000-character and syntactically invalid decision records
cover the remaining rejection paths. These post-round-4 fixes were verified
with offline regression tests; they were not a third whole-core model sweep.
A focused follow-up confirmed the four fixes. Its request to pin the JSON
parser diagnostic was declined: the contract requires invalid-input rejection
before child launch, which the non-JSON fixture asserts; rejecting through the
shape check instead would still satisfy it. Its cancellation-coverage note is
recorded above as inspection-only evidence.


The offline workflow suite passes all 72 de-slop modes: the existing 59, eleven
known-record modes and two scope-citation/error cases. The fixtures check both
scout prompts and unchanged source enumeration. While developing the feature,
a fixture caught accidental Option encoding in manifest JSON; the stored record
is now an object (or JSON null), not an Option tag. Offline fixtures establish
orchestration behavior; the live runs above assess model behavior separately.

OpenSeek `moon info`, `moon fmt`, `just check`, `just test` and `just build` pass.
The full test gate reports 3,114 native and 3,223 JS tests, plus its offline cram,
CLI lifecycle and workflow gates. No editor files changed. Hosted cwd/mbtx
focused tests pass 115/115 after rebase. No public interface change is introduced
by this iteration; the earlier optional reservation override remains in the PR.

The workflow is useful for repeated assisted delivery, but these runs still
needed caller verification, one report-submission recovery, compiler rejection
and a corrected insertion sketch. They do not establish unattended delivery,
measured recall, or a reason to stop checking ACCEPT and KEEP explanations.
Raw journals, immutable workflow snapshots, probe failure, per-command gate
receipts and publication records are retained under the ignored local artifact
root `.moonagent/de-slop-core-20260914/`.

## Delivered PRs

| Batch | PR | Verified head | Diff |
| --- | --- | --- | --- |
| argparse | [#4238](https://github.com/moonbitlang/core/pull/4238) | `7d8e888f8a0a4838a6b6e28a2462bd0ba180667a` | 3 files, +26/−89 |
| buffer | [#4239](https://github.com/moonbitlang/core/pull/4239) | `bc41f2aee5d87b1fa17bbffc83342dc799267105` | 1 files, +2/−18 |
| debug | [#4240](https://github.com/moonbitlang/core/pull/4240) | `aa058cd10b79446e904df814b297402e4b116270` | 1 files, +19/−24 |
| set | [#4241](https://github.com/moonbitlang/core/pull/4241) | `97c6c2ed1bd87b937b841550d1d998fcbf2383c3` | 1 files, +11/−43 |
| scalars | [#4242](https://github.com/moonbitlang/core/pull/4242) | `ea1e0c45ba7ed4602b7aea4ae09461d03a9b0516` | 3 files, +16/−7 |

Every published head passes `moon check --target all --deny-warn`, its focused
all-target suite, the full all-target core suite, `moon bundle --all`, `moon info`
and `moon fmt`. For argparse, Buffer, debug and Set, full totals are wasm 7,609,
wasm-gc 7,636, JS 7,569 and native 7,524. The scalar branch adds one exhaustive
256-input population-count test, so each total increases by one. Buffer and
scalar focused suites also pass release tests on all four targets. Interfaces
and snapshots are unchanged. These are independent per-branch receipts, not
one shared test result applied to five different heads.

Final reviewers found no functional issues. The caller declined one Set nit:
changing a private precondition comment into a doc comment or another reserve
wrapper would not enforce it; both real callers already reserve capacity. The
eight-read prompt target was still exceeded by several reviewers, and the
workflow reviewer searched broadly for dependency source. Review cost and API
navigation remain weaknesses; these runs do not show a reliable hard reading
budget. The earlier argparse review was repeated only because round 4 added
two changed files to its already-published batch.

Each PR was read back for the exact remote head, `main` base and changed paths.
At publication, argparse had GitGuardian pending and a Devin status marked
pass with review skipped; the other four had no checks reported yet. Those
snapshots are not claims that GitHub CI passed. No PR was merged. The user’s
rebased `~/git/core` checkout remains clean.
