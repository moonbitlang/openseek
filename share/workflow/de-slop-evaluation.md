# OpenSeek repository evaluation — 2026-09-12

This evaluation started at `707fba910` after rebasing onto `origin/main`.
The workflow implementation was uncommitted; records include the working diff.
The real native OpenSeek CLI used `deepseek-v4-flash` and the bundled script
through `mbtx(subrun=true)`. No scripted model supplied these review decisions.

## Why the workflow changed

The original two-scout design was exercised with `args=["."]`. Its discovery
child used all 24 steps, concentrated on a handful of tool packages, and
submitted 11 citations against the eight-citation contract. The workflow failed
before challenge. That was a failed large-repository test, despite the parent
CLI returning exit zero. It motivated deterministic inventory, eight balanced
shards, independent challenge per shard, and durable per-shard results.

## Full-repository run

The sharded run completed all **8/8 candidate reviews**, with 16 real children,
92 total model steps, and 2,137,216 summed prompt/completion tokens. Token totals
include repeated/cached context and are not a cost estimate. Every child
submitted a captured report; stdout was 19,283 bytes and contained the successful
sweep marker. We checked the child events, journal, and workflow job output,
not just the parent process's exit code.

| Workspace module | Source files assigned |
| --- | ---: |
| root | 308 |
| `cmd/viz_app` | 5 |
| `desktop` | 428 |
| `editor` | 695 |
| `editor/server` | 17 |
| `inspect` | 2 |
| `protocol` | 14 |
| **Total** | **1469** |

An independent comparison with Git's current-file inventory verified that each
configured regular source file was assigned exactly once. Source hashes stayed
unchanged throughout the audit. The script scanned 444,266 lines, counting the
terminal blank line as the reader does, and recorded 959 lexical lead locations.
There was no depth or directory-count cutoff. Shards had 29–37 directories and
123–214 files each, balanced to 55,531–55,535 scanned lines.

Coverage has limits. The configured extensions are documented in de-slop.md;
1276 listed files were excluded from lexical scanning (including Markdown,
generated interfaces, data/configuration and assets), and ignored files were
not enumerated. Executable examples in `.mbt.md` were not lexical-scan inputs;
scouts could still read them as tests. Child transcripts confirm numbered
content returned for 85 distinct files, including 80 source files; some reads
were ranges or truncated. This is a lower bound on source reads because it
excludes `rg` and API navigation, and is **not** a count of fully reviewed files.
The remainder of the source inventory received lexical scanning only.

## Decisions and independent triage

There were 13 numbered primary candidates: the challengers labelled 11 ACCEPT,
one REJECT, and one DEFER. These labels are model judgments; they are not eleven
validated edits. Additional KEEP/dependency checks were also reported.

| Shard | Primary candidates | Evaluation outcome |
| --- | --- | --- |
| 1 | Manifest-basename helper; subrun parser temporary copy | Parser copy applied. Helper retained for further scrutiny: naming a tiny repeated expression and adding suffix interpolation is not automatically an improvement. |
| 2 | Markdown fence token ownership | Accepted by challenger; left as an unvalidated follow-up. |
| 3 | Quick-open selection sentinel; symbol mention sentinel | Local selection change accepted as a proposal; mention representation deferred after tracing producers and the parse round trip. Neither applied here. |
| 4 | Collapse ARIA presence/value into `String?` | Rejected: the DOM test binding returns `Some("")` for absence, so the presence marker is required. |
| 5 | Injected-text builder copy; preview URL split | URL split applied. Editor builder proposal left for its own validation. ASCII-only case handling kept. |
| 6 | Turn model/effort projection; NUL split helper | Left as proposals. The one-line NUL helper did not justify new indirection. |
| 7 | Trailing-slash helper | Challenger corrected a String/StringView mismatch, but its amended version adds a copy on another path. Left unchanged. |
| 8 | Reference-row index sentinel; revision decode helper | Roving change left for editor/browser validation. Revision helper would preserve a forbidden sentinel and still leave encoder wire names duplicated; not applied. |

The weak helper ACCEPTs caused another criteria iteration: reject helpers that
merely name a repeated expression, compare the whole allocation/indirection
change, and defer helpers that entrench forbidden sentinels. This is a prompt
quality limitation exposed by the run, not a claim of a measured false-positive
rate.

The following real-model run completed discovery/challenge in 5 + 6 steps
(281,867 summed tokens). It kept the NUL-split and manifest helpers unextracted,
and deferred the protocol sentinel migration. It left the two applied edits
intact and proposed three additional follow-ups: use the existing ASCII-lowering
operation, avoid a second collected URL split, and remove an intermediate copy
in `agent_subtask/scope.mbt`. These were not applied in this evaluation batch.

That follow-up also corrected a false KEEP from the broad run: the installed
`String::to_lower` and `StringView::to_lower` are ASCII-only, despite an earlier
scout's assumption about Unicode case folding. Independent inspection of both
native and JS core implementations confirmed the documented ASCII behavior.
The report's original claim that replacing the helper would change Unicode
semantics must not be carried forward. This illustrates why KEEP decisions
also require API evidence, and why the reports are review leads rather than
an automated rewrite authority.

## Applied changes and checks

- `desktop/internal/subrun/probe.mbt`: keep the trimmed decoded JSON as a view
  instead of immediately allocating another owned String; owned carry bytes stay.
- `desktop/frontend/preview/url.mbt`: use `rev_split_once("@")` instead of
  building all segments and selecting the last. The returned host remains owned;
  ASCII case conversion and IPv6 handling stay intact.

Added assertions for repeated `@`, trailing `@`/empty host, and a non-ASCII host.
All 12 preview JS tests passed with these assertions both before and after the
parser edit. All eight existing subrun native tests passed after the copy
removal. Public interfaces remained byte-identical after `moon info && moon fmt`.
A first preview command selected native and was rejected because that package
supports JS only; the actual executed preview gate used `--target js`.

Final repository gates passed: `just check`, `just test`, and `just build`.
`just test` reported 3110/3110 native and 3198/3198 JS tests, plus the offline
cram, real-CLI lifecycle, and workflow suites. There are 36 de-slop fixture modes,
including seven whole-repository cases. No snapshots were updated and no public
interface changed. Since the applied changes are outside `editor/`, its extra
all-target/browser gates were not required for this batch.

The offline workflow suite additionally covers a failing shard retaining seven
successful reports, single-shard reruns, complete disjoint inventory, and long
CJK/emoji reports fitting the output transport. The latter prompted a deterministic
Unicode-safe excerpt limit; full reports remain in session artifacts.

## Local reproducibility records

Raw records are retained under `.moonagent/de-slop-openseek/` (ignored, not
packaged with the workflow):

- `full-audit-*`: failed original whole-repository attempt.
- `sharded-audit-*`, `sharded-baseline.*`: complete eight-shard real-model run.
- `sharded-coverage-verification.json`: independent inventory check and source hashes.
- `sharded-observed-reads.json`: numbered-read paths and truncation observations.
- `sessions/openseek-sharded-audit-wf-1/journal.jsonl.inventory.json`: all assigned files and every lexical hit.
- `sessions/openseek-sharded-audit-wf-1/journal.jsonl.report.json`: all eight challenged reports.
- `refined-audit-*`: follow-up real-model run with the stricter helper criteria.

The shipped script's invocation remains `args=["."]` for a full sweep. Reports
are evidence for the caller's apply/test loop; successful orchestration does
not establish that all code is clean or that a proposed rewrite is correct.

## Rebased cross-repository follow-up

The two desktop changes were rebased and submitted separately as
[PR #1484](https://github.com/moonbitlang/openseek/pull/1484). The workflow was
not part of that PR. See [the subsequent OpenSeek/core evaluation](de-slop-cross-repo.md)
for inventory v2, full reruns, and counterexamples that changed the criteria.
