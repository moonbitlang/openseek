# De-slop across rebased OpenSeek and core

This evaluation used the real OpenSeek hosted workflow with `deepseek-v4-flash`
on 2026-09-12. Whole-repository runs used `args=["."]`: eight review shards,
two sequential read-only children per shard, three concurrent children per run.
A script scans all configured source; model source review remains a sample.

## Baselines and the separate PR

- OpenSeek: fetched and rebased onto `origin/main` at `11881bbec`; the two
  desktop parsing changes became `fa9905887`. Workflow edits were stashed and
  restored separately. [PR #1484](https://github.com/moonbitlang/openseek/pull/1484)
  contains only `desktop/internal/subrun/probe.mbt`,
  `desktop/frontend/preview/url.mbt`, and its preview regression assertions.
  GitHub subsequently reported it merged, with all checks successful.
- `~/git/core`: rebased branch `caimeox/integer-improve` onto `c06c1467d`.
  Git recognized the old local `dabf4cb6d` patch as already applied; `git cherry`
  independently confirmed patch equivalence. The original tip remains at
  `codex/core-before-deslop-rebase`. The working tree stayed clean.
- The baseline OpenSeek `just check`, `just test`, and `just build` passed;
  core `moon check --deny-warn --target all` passed. Source hashes verified
  that the first-round scouts changed neither repository.

## Failures that changed the workflow

1. **Report validation was not isolated.** In the first core run, a discovery
   citation to `AGENTS.md` omitted its line number. `show_report` raised a
   generic failure, while `workflow.attempt` catches only typed workflow
   failures. The whole task group was cancelled after three reports; no final
   ledger was produced. The outer CLI still exited zero. V2 uses a separate
   `AuditInvalid` channel and collects report errors per shard, preserving
   sibling reports. Cancellation and unexpected engine errors still propagate.
   Offline regressions cover invalid discovery lines and incomplete challenges,
   in addition to the existing child-process failure case.
2. **Package-sized units skewed core's coverage.** `builtin` occupied a
   68,683-line shard while the other seven had about 21,600 lines each. V2
   splits oversized packages while keeping exact-stem source/test families
   together. Its eight core shards have 29,078–29,207 lines each.
3. **Useful test source was excluded.** V2 includes `.mbt.md`: 119 additional
   OpenSeek files and 67 core files. All source files, including those without
   lexical hits, remain assigned exactly once.
4. **Seeds over-weighted comments and repeated files.** The old builtin prompt
   offered two doc-comment examples from one file. V2 retains every hit in its
   inventory but prefers implementation, then tests, then comments/docs, and
   samples four distinct files per unit. These roles are lexical heuristics.
5. **KEEP can be wrong too.** The rebased OpenSeek first round repeated the
   false claim that replacing ASCII-lowering code with `to_lower` changes
   Unicode behavior. The target core implementations are ASCII-only. Criteria
   now require the exact receiver/version/backend evidence for KEEP as well as
   ACCEPT, and prefer checked-out source when auditing core itself.
6. **Compilation does not prove dispatch equivalence.** The first core scout
   proposed removing the apparently redundant `map` below. This became a
   negative control and an explicit implicit-conversion/trait-dispatch check.

## Counterexample: the apparent identity map is necessary

In `quickcheck/shrink/composite.mbt:68`, the existing implementation is:

```moonbit
pub impl[X : Shrink] Shrink for ArrayView[X] with fn shrink(xs) {
  let candidates : Iter[Array[X]] = Shrink::shrink(xs.to_owned())
  candidates.map(candidate => candidate)
}
```

`Shrink::shrink` returns `Iter[Self]`. The typed intermediate selects
`Shrink for Array`, and the map converts each returned Array into an ArrayView.
Changing the body to `Shrink::shrink(xs.to_owned())` instead selects the current
ArrayView implementation after an implicit conversion of its argument.

The isolated trial passed `moon check quickcheck/shrink --target all --deny-warn`,
but the unchanged test suite did not finish within 45 seconds. Generated JS
confirmed an unconditional loop repeatedly owning the view and converting it
back; the original generated JS calls Array's shrink and maps each candidate
into a view. Before the edit and after restoring it, all 60 package tests
passed on each of wasm, wasm-gc, JS and native. The candidate was rejected;
`~/git/core` was never edited by the trial.

The v2 full core scout independently kept this map with the correct conversion
rationale. This is one observed negative control, not a general error-rate
measurement.

## Positive controls in an isolated core worktree

Core's shard 4 proposed replacing the first phase of
`HashSet::symmetric_difference` (`hashset/hashset.mbt:440`) with
`let m = self.difference(other)`. Independent inspection confirmed the same
fresh set, capacity, traversal order, calls to Eq/Hash, and subsequent in-place
insertion of other-only keys. The challenger accepted it but correctly called
the benefit marginal: a two-line policy deduplication, not a performance claim.

The isolated trial passed all 77 existing hashset tests on each of wasm,
wasm-gc, JS and native both before and after, plus module-wide
`moon check --target all --deny-warn`. `moon info && moon fmt` left the public
interfaces unchanged. A reviewable patch is retained locally as
`core-hashset-validated.patch`; it was not applied to `~/git/core` or included
in the desktop PR. No tests or snapshots were changed.

A second accepted candidate removes the temporary `separator.to_owned()` in
`deque/deque.mbt:1786`: `Iter::join` already consumes `StringView` and does not
retain the separator. Existing deque tests passed before and after: 258 on each
of wasm, wasm-gc and JS, and 248 native. Module-wide all-target checking and
`moon info && moon fmt` passed with unchanged interfaces. The two verified edits
are available together in `core-validated-simplifications.patch`.

## Inventory and run results

Results below distinguish lexical coverage, completed candidate decisions and
actually validated changes. A model ACCEPT is still a proposal.

| Run | Source files | Scanned lines | Lexical leads | Completed candidate reviews |
| --- | ---: | ---: | ---: | --- |
| OpenSeek v1 | 1,463 | 443,422 | 957 | 8/8 |
| core v1 | 883 | 219,873 | 686 | 0/8; stopped after three discovery reports |
| OpenSeek v2 | 1,582 | 463,060 | 974 | 7/8 initially; 8/8 after an explicit shard-7 rerun |
| core v2 | 950 | 233,202 | 726 | 8/8 |

Independent inventory comparisons confirmed every configured current source
file was assigned exactly once, and source hashes stayed unchanged. OpenSeek
v2's shards span 57,880–57,886 lines; core v2's span 29,078–29,207. Sources are
counted with the reader's terminal-blank-line convention. Git-ignored content,
submodules, assets and unconfigured extensions are outside the source scan.
The v2 initial inventories recorded 1,152 OpenSeek and 199 core exclusions.

OpenSeek v2 used 16 children / 107 steps / 2,828,269 summed tokens. Shard 7's
challenger returned plain text without `submit_answer`, correctly yielding
`NoReport`; the other seven reports survived. A caller-requested rerun used
2 children / 12 steps / 310,749 tokens, with the same source hashes and shard
assignments. No retry was hidden in the workflow. Core v2's completed run used
16 children / 99 steps / 2,422,357 tokens; the separately cancelled initial
three calls are excluded from these completed-run totals. Summed tokens count
repeated prompt context across steps, not unique source or billing.

Numbered read results returned content for 147 distinct OpenSeek source files
and 103 core source files in the v2 runs (including the OpenSeek retry).
These are **not fully reviewed file counts**: many reads were ranges or
truncated. They returned 11,187 and 10,663 distinct source lines respectively;
`rg` and IDE navigation are not included in these lower bounds. The remaining
inventory received lexical scanning, with no claim of full semantic review.

### OpenSeek triage

The v2 reports plus shard-7 retry contain 15 primary proposals (raw challenger
labels: eight ACCEPT, seven REJECT). No further OpenSeek code edit was applied
in this round. These are review leads, with the caller's corrections below.

| Shard | Sites and raw decisions | Caller triage |
| --- | --- | --- |
| 1 | `agent_tool/mbtx/html/read_output.mbt:8` per-line copies REJECT; `editor/internal/viewer/browser/markdown_document/markdown_document.mbt:313` nested fallback ACCEPT | Guard flattening is unvalidated. The copy rejection's allocation arithmetic is incomplete: successful numbered lines already allocate their split parts, so removing the initial copy can still save one; defer for a full before/after and renderer tests. |
| 2 | `editor/shell/workspace/source.mbt:52` Char predicate REJECT; `inspect/main.mbt:60,86` String interpolation ACCEPT | Rejection correctly established String indexing returns UInt16, not Char. Interpolation removal remains an unvalidated small simplification. |
| 3 | `desktop/frontend/fileeditor/update.mbt:1284,1324` manifest helper REJECT; `editor/server/host` root-relative helper REJECT | Keep distinct manifest sets and differing root-path/failure policies; do not create a helper solely to name one expression. |
| 4 | `desktop/frontend/composer/component.mbt:457` dropping pathless mentions REJECT; `editor/shell/remote_protocol/protocol.mbt` wire-name constant ACCEPT | Reject the behavior-changing sketch. A documented/tested legacy sentinel still needs a separate typed migration under AGENTS.md; documentation does not override that rule. The single constant is a low-benefit proposal, not a validated cleanup. |
| 5 | `agent/goal.mbt:342` regex→last split ACCEPT; `cmd/viz_app/app.mbt:1255` nested-row cache REJECT | Parser rewrite needs repeated-marker/newline/trailing-parenthesis tests; performance caching needs measurement and render-order coverage. Neither applied. |
| 6 | `editor/internal/viewer/contrib/references/browser/reference_results_tree.mbt:943` and `editor/viewer/common/view_layout/lines_layout.mbt:443` sentinel indices ACCEPT | Promising local Option migrations; keep other cache-invalid sentinels separate. Require editor and browser validation. |
| 7 retry | `desktop/frontend/preview/url.mbt:7` ASCII helper ACCEPT; `desktop/internal/engine/engine.mbt:1369` first PATH entry REJECT | ASCII-only semantics confirmed; the report's UTF-8/backend claims are unverified (JS core uses a character loop). The PATH rejection invented an empty-separator risk: `desktop/internal/env/path.mbt:23,28` fixes it to `;` or `:`. Re-evaluate with the actual constants; no automatic edit. |
| 8 | `desktop/internal/skillmarket/library.mbt:114` own→trim→own ACCEPT | Concrete additional copy-removal proposal; retains the final owned result. Not yet tested or applied. |

### core triage

The eight v2 reports contain ten primary proposals (raw challenger labels:
nine ACCEPT, one DEFER). Independent triage retains two tested positive
controls; it does not promote the other ACCEPTs to validated changes.

| Shard | Sites | Caller triage |
| --- | --- | --- |
| 1 | `builtin/bytes_find.mbt:772,795` delegate chop predicates | Unvalidated reuse proposal; preserve empty/overlong affixes and aliasing. |
| 2 | `builtin/array.mbt:1548,1651` delegate chunks/windows to ArrayView | Unvalidated reduction of duplicated algorithms; check panic-location and view construction costs. |
| 3 | `builtin/string_methods.mbt:366,396` delegate strip predicates | Deferred: conflicts with shard 1's KEEP; measure relevant fast paths before deciding. |
| 4 | `list/list.mbt:170` deprecated wrapper delegation; `hashset/hashset.mbt:440` reuse difference | List remains a proposal. HashSet validated in isolation, benefit marginal. The misleading ArrayView identity-map proposal was correctly kept out. |
| 5 | `hashmap/utils.mbt:364,405` remove identity `iter.iter()` | Unvalidated small simplification; retain lazy closures and size hints. |
| 6 | `json/lex_number.mbt:218` own fallback repr in producer instead of four consumers | Unvalidated private-type refactor; preserve lossless numeric text, fast paths and backend layout. |
| 7 | `argparse` option-token predicate helper; error-payload split | Keep the one-line helper unextracted under the workflow's benefit threshold. Error-type migration deferred, as the model also concluded. |
| 8 | `deque/deque.mbt:1786` remove separator copy | Validated in isolation on four targets; patch retained. |

### Verification of the workflow changes

The final `just check`, `just test`, and `just build` passed. The root test
suite reported 3,086 native and 3,204 JS tests, plus cram, CLI lifecycle and
offline hosted-workflow checks. All **38 de-slop fixture modes** passed,
including nine whole-repository cases. Standalone workflow compilation used
Wasm with `--deny-warn`; the script was formatted with moonfmt's MBT input mode.
`moon info && moon fmt` left public interfaces unchanged. No editor source or
browser behavior was changed by the workflow iteration.


## Remaining limits and next improvements

- Lexical seeds still overproduce required owned results and intentional test
  copies. Both repos repeatedly found stronger leads by comparing sibling
  implementations. The next inventory iteration should supply structural
  sibling-operation leads, with receiver/target evidence; adding broader regex
  rewrites would reproduce the false positives this evaluation exposed.
- Cross-shard dependency reads can yield conflicting recommendations. Core
  shard 1 kept the StringView strip implementations for performance reasons,
  while shard 3 accepted delegation to has_prefix/has_suffix. Neither report
  measured performance; the unchanged-buffer Eq fast path also needs attention.
  This candidate stays deferred in the caller's triage. The apply guide now
  explicitly requires reconciling overlapping ACCEPT/KEEP claims.
- Some children spend the read budget before following AGENTS.md's linked
  validation guide. Exact test commands and receiver types should be gathered
  early; do not replace missing evidence with an invented command or a clean
  status heading. Heading correctness and candidate limits are model judgments,
  not mechanically proved by the report validator.
- Model output remains nondeterministic and expensive. Keep source hashes,
  script version, raw reports, explicit uninspected scope and negative controls.
  These two runs establish observations, not recall or a false-positive rate.

## Reproducibility

Raw local records are under `.moonagent/de-slop-cross-repo/` (ignored):

- `rebased-baseline.json` and `v2-baseline.json`: heads and source hashes.
- `workflow-v1.mbtx` and `workflow-v2.mbtx`: exact scripts used in the runs.
- `openseek/`, `core/`, `openseek-v2/`, `core-v2/`: parent/child sessions,
  workflow journals, inventory sidecars, report ledgers and job output.
- `core-identity-map-rejected.patch` and `core-identity-map-generated-js.txt`:
  rejected edit and compiler evidence.
- `core-validation/`: isolated detached worktree for compiler/test experiments.

Core v2's outer caller initially added a redundant `--` to the arguments,
stopped that healthy job and relaunched with exactly `["."]`. The first three
children were cancelled before submitting; the actual full sweep uses the
`wf-33` journal. This was unnecessary caller orchestration, not a workflow
retry, and its interrupted calls must not count as completed coverage.
