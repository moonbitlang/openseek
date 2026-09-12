# De-slop: simplify, challenge, validate

Use this workflow to sweep a large repository, then simplify supported sites
without changing their contract. For an authorized small PR, follow
[the end-to-end delivery recipe](de-slop-deliver.md) and pass `--deliver`; the
calling agent continues through edits, tests, final diff review and publication
in the same task. Its final response is only the verified PR link; audit details
stay in local artifacts and validation belongs in the PR body.
The script itself remains a read-only audit and emits a delivery handoff only
after successful candidate review. `--deliver` additionally requires Git-visible
source and compares scoped file contents before and after the audit; concurrent
edits invalidate the handoff. This covers configured source extensions, including
untracked/unignored files, but is not a lock or a dependency/environment snapshot.
A useful result includes reasons to KEEP code;
it does not classify authorship or assign an "AI code" score.

```json
{"description":"Sweep all of OpenSeek","filename":"@builtin/de-slop.mbtx","args":["."],"subrun":true}
```

Whole-repository mode requires Git and a hosted journal. It enumerates tracked
and untracked, unignored files with NUL-delimited `git ls-files`, deduplicates
paths, and scans every regular source file for six lead families:
direct collection operations, ownership/materialization, prefix/suffix handling,
possible absence sentinels, explicit trim character sets, and repeated
nontrivial MoonBit function bodies. These are search leads, not findings.
Explicit trim arguments include non-default values; only resolved declaration
evidence establishes redundancy. The function-body comparison strips comments
and blank lines within MoonBit blocks, ignores short wrappers/tests, and links
matching sites even across packages; it proves text similarity, not type or
behavioral equivalence. Multiline trim arguments and non-identical equivalent
bodies can still be missed.
The configured source extensions are `.mbt`, `.mbt.md`, `.mbtx`, `.ts`, `.tsx`, `.js`,
`.jsx`, `.mjs`, `.c`, `.h`, `.py`, `.sh`, `.ps1`, `.rs`, and `.go`. The manifest
records other listed files and absent/nonregular source files as exclusions;
Git-ignored files and submodule contents are not enumerated. Symlinks are not
followed. Read/stat errors other than absence fail the inventory.

Source directories normally stay together. A directory larger than twice the
repository-wide target (total scanned lines / eight) is split into review units,
keeping exact-stem `.mbt`, `_test.mbt`, `_wbtest.mbt`, and `.mbt.md` families
together. A single large family remains indivisible. Units are assigned largest
first by scanned line count to the lightest of up to eight shards. Every source appears exactly
once in the manifest, and scouts receive exact assigned filenames. Each shard
has sequential discovery and challenge, with a 16-step ceiling per child and
at most three children running concurrently. Discovery targets at most two
candidates from different review units and also considers non-lexical issues.
Sampled leads prefer explicit-trim/repeated-body implementation hits, then
other implementation lines, tests, and comments/docs,
interleaving each file's first hit before its second hit, and so on. Each unit
supplies at most four hits. `args=["--round","2","."]` advances that window
by four on the same inventory; continue with positive rounds up to 1,000,000
when repeated use is requested. Every retained hit is eventually suggested,
including later hits in a single file. Windows wrap when exhausted; this is
reproducible sampling, not a persistent coverage database or a guarantee that
a scout read a suggested site. Shard assignments do not change with the round.
The version-4 manifest records the round and the exact sampled leads as well
as **all** hits and their roles; a lexical role is a heuristic, not a parser classification.
It needs two reserved child slots per shard, up to sixteen for a full sweep.
There are no automatic retries that silently multiply model spend.

The host journal's `.inventory.json` sidecar contains every source path and
all lexical hit locations; `.report.json` contains successful challenged
reports and failed shard IDs. Raw discovery and challenge reports stay in the
journal, including reports that fail validation. Stdout shows at most 750
Unicode characters per shard (at most 3000 UTF-8 bytes), with full decisions
and citations in the report artifact.
A failed child or invalid report makes its shard fail while preserving the
other results. Report errors use a separate typed channel: workflow `attempt`
alone catches child failures, not arbitrary validation exceptions. Cancellation
and unexpected engine errors still propagate. With
the **same working tree and workflow version**, rerun one failed shard using
`args=["--shard","N","--round","R","."]` (round defaults to 1); it prints how many shards were unscheduled and
must be combined with the earlier reports. Shards are deterministically rebuilt
from the current tree; after edits, do not combine new shard numbers with an
old inventory. Re-audit explicit changed paths instead.

The output separates complete file enumeration/lexical scanning from sampled
semantic review. Eight successful candidate reviews do not mean every function
was read, every kind of slop was detected, or the repository is clean. Counts
and paths make the limits inspectable. Inventory exceeds 8 MiB, a source file
exceeds 16 MiB, or a shard's prompt inventory exceeds 40,000 characters: the
run fails explicitly rather than silently omitting files. Choose explicit
subtrees for repositories beyond these bounds.

For a focused follow-up, pass one to eight existing files/directories:

```json
{"description":"Challenge local simplifications","filename":"@builtin/de-slop.mbtx","args":["agent_tool/mbtx"],"subrun":true}
```

`cwd` selects the workspace. Paths must resolve inside it, including through
symlinks. Only the single argument `.` selects whole-repository mode;
`--shard` and `--round` require it. `--focus TEXT` accepts one candidate (1–2000 characters)
with explicit paths and passes it to both scouts; it cannot be combined with
whole-repository scope. This preserves the candidate from a previous sweep or
user feedback instead of asking the scouts to discover unrelated changes.
`args=["--help"]` works without a hosted handoff.
Scope selects candidates; callers/dependencies, including a repeated-body peer outside the shard, can be read to verify them. A proposed exported API or visibility change is DEFER, never ACCEPT with a caveat.
This is model guidance, not an additional filesystem sandbox.

For explicit paths, the script launches two **sequential, read-only** `explore` children, each
with a 24-step ceiling. Discovery proposes at most three changes and identifies
something worth keeping. The challenger reads the source again and decides
ACCEPT, REJECT, or DEFER for each candidate, looking for counterexamples.
It may reject all proposals. Both phases must submit through `submit_answer`;
plain final text is not a report. They do not edit files or execute validation.
The eight-read/API-call budget and prohibition on scratch experiments are
prompt guidance. The engine enforces the 24-step ceiling and read-only
workspace access; a step can contain multiple tool calls.

A focused run requires two reserved child slots before launching either phase.
It rejects empty/oversized answers, missing workspace citations, malformed local
line numbers, unreadable/escaping local references, and lines beyond EOF.
Explore reports may also cite installed dependency sources or API links;
external references are printed as **not checked**, never opened, and cannot
replace the required workspace evidence. Reference checks
prove only that the location exists. Decisions, semantic equivalence, scope
adherence, and the three-candidate limit remain model judgments. KEEP claims
require API evidence too: names do not establish Unicode or allocation behavior.
When auditing core itself, use the checked-out source, follow target-specific
implementations and implicit conversions, and check trait delegation for cycles. The final
answer must begin with `# Audit complete` or `# Audit incomplete` on its own
line. Incomplete or missing status fails the run. The `unresolved` field stays
visible as limitations; unexecuted tests alone do not make source inspection
incomplete. Discovery evidence remains visible if the
challenger fails; an incomplete run must not be treated as "nothing to fix."
Successful exit means the audit returned inspectable evidence, not that code
was changed or tests passed. It uses model tokens and the hosted journal/event
stream, like the other agent workflows.

## Apply and iterate

The calling agent owns this loop; no extra approval is required when the user
has already requested the cleanup.

1. Read repository instructions. Record HEAD, `git status --short`, and the
   existing diff so user edits and baseline failures remain attributable.
   Start with the full repository sweep; select one coherent accepted batch
   and state its behavior/API constraints. Keep the tree
   stable during the audit; the workflow does not lock or snapshot its files.
2. Run the workflow. Verify the workflow job itself completed successfully and
   inspect its report ledger; the outer CLI can exit zero after a failed job.
   Check ACCEPT proposals against their code, callers, and
   current library APIs. A citation is not proof. Keep REJECT cases and leave
   DEFER cases outside this behavior-preserving batch. Missing evidence calls
   for a targeted read, not speculative editing. Compare all shard reports
   before editing: dependency reads can overlap, and an ACCEPT can conflict
   with another shard's KEEP. Resolve that specific claim from source/tests or
   defer it; neither majority votes nor successful headings settle a conflict.
3. Apply one coherent batch. Preserve staged and unrelated edits. Do not use
   repository-wide regex replacement or reset/checkout to undo a failed idea.
   If a candidate does not compile or changes a required behavior, restore
   just that edit and record why it was kept.
4. Run the smallest relevant compiler/test checks first. Use `moon ide doc`
   for API/receiver uncertainty and `moon check` for type/ownership evidence.
   A type-correct rewrite can still recurse: removing a typed intermediate in
   core's ArrayView shrink changed trait inference, and its apparent identity
   map actually converted arrays to views. Run existing behavioral tests with
   bounded execution; add a regression only for a concrete risk
   such as duplicate delimiters, empty input, Unicode, side effects, or a
   missing/error distinction. Don't add tests merely to recognize new syntax.
   Preserve negative and platform cases when consolidating fixtures.
5. Run the repository's required gates. In OpenSeek these are `just check`,
   `just test`, and `just build`; changes under `editor/` also need
   `just editor-test`, and browser behavior needs `just editor-test-browser`.
   Follow `desktop/AGENTS.md` for desktop changes. In each affected module,
   finish with `moon info && moon fmt`, review the generated `.mbti` diff,
   and verify formatting. An unexpected public API change is a reason to
   revise the batch, not a snapshot to accept automatically. Rerun checks
   when a subsequent edit affects their result; don't repeatedly run broad
   gates on unchanged code.
6. For PR delivery, use the final-diff review and publication checks in
   [de-slop-deliver.md](de-slop-deliver.md); do not stop at an ACCEPT report or
   restart full discovery merely to accumulate more changes.
   For an audit/iteration task, rerun on the changed scope to check for supported
   simplifications. Default to at most two apply/validate rounds per scope;
   stop earlier when no candidates survive. If a round repeats a rejected
   candidate, explain the existing counterexample rather than rewriting it.
   Remaining substantial work becomes a named follow-up; don't broaden scope
   or create an abstraction to keep the loop busy.

Report the concrete simplifications, deliberate KEEP decisions, actual
commands/results, and unresolved risks. Count reduced allocations, duplicated
contracts, or unnecessary exposed symbols only when evidenced. Deleted lines
alone are not a quality metric. Never describe audit output as passing tests.

## Where the criteria came from

The baseline for this study is `707fba910` (2026-09-12). Searching main's
non-merge commit messages, including `Co-authored-by`, yields 129 SeekMoon
matches; author-only search misses most of this history. This is a selected
study of representative diffs and their follow-up fixes, not a claim that all
129 commits were independently audited. Reproduce discovery with:

```sh
git log 707fba910 --no-merges -i --grep=seekmoon --format='%h %s'
git show 4fba5323a -- agent_tool/plan/plan.mbt
git show 3508c4091 -- agent_tool/mbtx/filename.mbt
git show fc02ebc0e -- agent_session/goal.mbt agent_session/goal_test.mbt
git show b856e7228 -- agent_session/goal.mbt agent_session/goal_test.mbt
```

| Observed change | Transferable rule | Counterexample to check |
| --- | --- | --- |
| [4fba5323a](https://github.com/moonbitlang/openseek/commit/4fba5323a): `input.steps.iter().any(f)` → `input.steps.any(f)` | Use the receiver's existing operation. | The adjacent `iter().find_first(...)` stays; not every receiver or iterator operation has a direct equivalent. |
| [3508c4091](https://github.com/moonbitlang/openseek/commit/3508c4091): 97 view-to-owned removals | Remove copies when consumers already accept views; compiler-check each site. | Returned/stored owned values still require ownership. Compilation alone cannot establish mutation/lifetime equivalence. |
| [2bbbbc06e](https://github.com/moonbitlang/openseek/commit/2bbbbc06e): strip `@builtin/` with one pattern instead of testing then slicing at 9 | Make recognition and extraction one operation. | Empty remainder, Unicode, repeated delimiters, and suffix anchoring must retain their behavior. |
| [fc02ebc0e](https://github.com/moonbitlang/openseek/commit/fc02ebc0e), followed by [b856e7228](https://github.com/moonbitlang/openseek/commit/b856e7228): simplify goal-baseline parsing, then reject repeated `dirty` fields | Test the accepted language of a parser, not just ordinary inputs. | A shorter pattern can accept a second delimiter inside the captured prefix; trailing-junk coverage alone missed this. |
| [7f49016be](https://github.com/moonbitlang/openseek/commit/7f49016be), [8b92c560d](https://github.com/moonbitlang/openseek/commit/8b92c560d): abstract private-field types and hide/deprecate promoted trait methods | Public surface should reflect intended use. | Local absence of callers is not proof of external disuse. Preserve compatibility/deprecation paths; review `.mbti`. |
| [6026f9d6e](https://github.com/moonbitlang/openseek/commit/6026f9d6e): remove unnecessary qualifiers and enable the corresponding warning | Let the toolchain enforce a recurring mechanical rule. | Do not weaken warnings, invent assertion-only tests, or broaden a cleanup to unrelated diagnostics. |
| [287457a37](https://github.com/moonbitlang/openseek/commit/287457a37), [73dce1f0b](https://github.com/moonbitlang/openseek/commit/73dce1f0b): replace accumulation with spreads/comprehensions | Express collection construction directly when it helps reading. | Preserve evaluation order, short-circuiting, early exits, and intentional mutation. |

Adjacent maintainer fixes add two broader checks (these are not attributed to
SeekMoon): [eec09d0b7](https://github.com/moonbitlang/openseek/commit/eec09d0b7)
renders the spawn-command documentation from its actual allowlist, removing
drifting copies; [1b7b57636](https://github.com/moonbitlang/openseek/commit/1b7b57636)
represents an unresolved realpath with an option, and
[707fba910](https://github.com/moonbitlang/openseek/commit/707fba910) propagates
UUID errors. These illustrate eliminating duplicated truth and preserving
failure semantics, which matter more than making an expression shorter.

## Validation

`just test-workflows` compiles the actual script as Wasm and runs it through
the hosted contract with offline fixture children. It checks ordered evidence
handoff, explicit scope (including spaces), zero-change success, resolved and
unresolved gaps, pending validation versus incomplete inspection, missing
status, partial failure, malformed output/references, external references versus
missing workspace evidence, missing host, insufficient capacity, help, and
invalid/escaping scope. No model credentials
are needed. This validates orchestration and output handling, not the model's
ability to recognize unnecessary code. Whole-repository fixtures also check
complete, duplicate-free assignment of nested and untracked sources, ignored/
deleted/symlink exclusions, executable Markdown, oversized packages with intact
source/test pairs, implementation seeds ahead of doc examples, equivalent and
non-default trim leads, repeated bodies versus near-matches/test copies, all eight
discovery/challenge pairs, child failure **and invalid-report** isolation,
durable reports, capacity preflight, single-shard reruns, delivery handoff only
on success (including no-change guidance), and combined
Unicode output below the transport limit.

For a model evaluation, use an isolated copy with both positive and negative
controls: a direct-predicate opportunity, a removable temporary owned copy,
a required owned return, distinct Missing/Failed cases, and a parser with
empty/Unicode/repeated-delimiter cases. Run the real workflow, inspect both
reports, apply only supported candidates, and run the original tests. Re-audit
the result. A false positive on a negative control or an unsupported ACCEPT
is a prompt defect to fix before increasing the scope. Keep raw sessions and
commands with the evaluation; model runs are observations, not deterministic
CI gates.

The 2026-09-12 development smoke test used `deepseek-v4-flash` through the
real OpenSeek hosted workflow. The final positive-control run submitted both
reports in 5 + 4 steps and accepted the direct predicate, prefix extraction,
and temporary-copy removals while preserving the owned return and error
distinctions. Applying those three edits passed all three unchanged fixture
tests and left the generated interface byte-identical, including the
`Option::map` callback's effect. A post-cleanup run submitted in 7 + 3 steps
and recommended no further edits. These small controls establish the tested
examples, not a general false-positive rate; missing submissions and incomplete
evidence still fail the workflow.

For the full OpenSeek run, coverage, rejected proposals, and applied/tested
changes, see [the repository evaluation](de-slop-evaluation.md).

For the rebased OpenSeek/core comparison, concrete failures, and subsequent
workflow changes, see [the cross-repository evaluation](de-slop-cross-repo.md).

For the default-argument feedback, negative controls, delivery phase failure
and a real small PR, see [the delivery evaluation](de-slop-delivery-evaluation.md).

The [two-round scale evaluation](de-slop-scale-evaluation.md) records both real
PR deliveries, progressive reading coverage, negative controls and remaining
failures, including the corrected reviewer instruction conflict.
