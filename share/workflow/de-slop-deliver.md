# Deliver de-slop changes as small PRs

Use this as the calling agent's task recipe when the user asks for cleanup and
PR delivery. `de-slop.mbtx --deliver` performs read-only discovery/challenge and
hands control back here; **the calling agent executes the remaining steps**.
This is one end-to-end task, with no user handoff between phases. A successful
audit is an intermediate result. Continue in the same task until the selected
batches have verified PR URLs or concrete no-change/blocker dispositions. Do
not ask again for publication permission already granted by the user. Without PR authorization,
stop at the tested diff and ask only when publication is the remaining step.

## Completion contract

When the user requests PR delivery, the final user-facing answer is **only the
verified PR link(s)**: `[PR #NUMBER](URL)`, one per delivered batch. Put the change explanation, tests and
observed CI status in the PR body; retain discovery, rejected candidates and
workflow feedback in local artifacts. Do not replace delivery with an audit
summary, a tested patch, a proposed next step, or a request to continue.
The script's delivery handoff is internal control flow, not a handoff to the user.

A genuine no-change result or unavoidable blocker is the only exception: give
one concise factual line, without manufacturing a PR. If part of a selected
campaign is blocked, return the completed PR links and name that blocker; do not
present partial delivery as completion of all batches. Do not count a draft with
failing required checks as successful delivery. No summary after a published PR.

## Establish scope and batches

1. Read repository instructions and their linked validation guides. Record
   HEAD, status and existing work. Fetch the requested upstream. Start from its
   current tip in a clean `codex/` branch/worktree; if the user requested their
   existing changes as the baseline, preserve those instead. Never stash,
   reset, stage, commit or publish unrelated work merely to make delivery easy.
2. Reuse a completed discovery/challenge ledger before launching more scouts.
   Record its source/workflow revision and resolve its surviving proposals into
   a batch queue. At a newer upstream, compare each proposal's source **and the
   callers, declarations and manifests its reasoning depends on** with the
   recorded baseline. Reuse unchanged evidence; inspect changed dependencies
   and rechallenge the affected hypothesis when its justification no longer
   holds. Do not pay for a new full sweep or a fresh focused pair for every
   already-reviewed candidate. Invalid/incomplete reports are not reusable
   approvals, and ACCEPT still needs independent caller verification.
   When no usable ledger exists, start with `de-slop.mbtx --deliver .` for
   unknown scope, or `--focus` carrying a concrete candidate verbatim, e.g.
   `args=["--deliver","--focus","reuse difference in symmetric_difference",
   "hashset/hashset.mbt"]`. For repeated exploration, advance `--round N` on a
   recorded stable inventory; preserve the round with `--shard` retries. Use
   `subrun=true`, wait for actual job completion and inspect its ledger; outer
   CLI exit zero is not evidence it succeeded. Before one targeted retry of a
   recoverable format/submission failure, inspect the saved error. Retain both
   attempts; a second failure is a blocker, not grounds to restart the sweep.
   **Phase barrier:** do not edit until challenge succeeds and evidence is
   current. For a new `--deliver` run, wait for its delivery handoff. While it
   runs, only read and run baseline tests. Provisional discovery is not approval
   to implement. The script compares Git-visible scoped source before/after;
   that guard is neither an exclusive lock nor validation of every dependency.
3. Match delivery breadth to the user's request. A narrow cleanup or explicitly
   single-PR request gets one PR. A repository-scale or cross-repository
   delivery request processes the surviving batch queue in the same task;
   **one PR is not the task's stopping condition**. First group candidates by
   maintenance concern and verify all same-concern sites together. Normally
   keep each PR within five files and 100 changed lines, but preserve necessary
   caller/backend fixes rather than splitting them to meet a size guideline.
   Avoid one PR per trivial call site. For every selected batch record its
   concern, sites, evidence, validation and disposition (published, rejected
   with counterexample, deferred with a concrete gap, or blocked). Do not
   silently drop a valid batch after another ships. There is no PR or deletion
   quota: finish the selected queue, not an arbitrary number of PRs. If the
   audit found no valid edits, make no empty commit or PR.

Before starting expensive work, check that the calling environment can run the
repository gates and publish with Git/gh. If an inner CLI policy blocks a
required executable, preserve the branch, diff, job state and exact failure,
and hand that step to the authorized outer host. The host resumes from those
artifacts; it must not duplicate a still-running job or PR. Do not change sandbox
policy or disguise the command to bypass a denial. Partial substitutes for a
required gate do not establish that gate passed.

## Prove and apply

Repeat steps 4–9 for each selected batch, using separate clean branches for
independent concerns. Each published head needs its own required gate results;
one batch's tests do not establish another batch's correctness.

4. Independently read the selected sites, callers, current library declarations
   and tests. Treat ACCEPT, KEEP and REJECT as claims. A correct rejection with a false compiler/allocation explanation is still workflow feedback; preserve the actual counterexample instead of treating the label alone as success. Resolve contradictory
   reports before editing; do not vote on them. Verify constants at their
   declarations, defaults by semantic equality (not character order), receiver
   types, backend behavior and trait dispatch. Keep non-default trim character
   sets and documented protocol choices. Never erase a type conversion merely
   because its source spells `map(x => x)`.
5. Run the smallest existing tests that cover the behavior before changing it.
   Apply only that batch, with file edit tools. Do not add helpers for repeated
   one-liners, migrate public/wire types incidentally, weaken tests, update
   snapshots to accept a regression, or edit the workflow itself in this PR.
   Add tests only for a concrete uncovered risk; syntax-only tests add no value.
6. Run focused tests after the edit, plus all repository-required gates. Bound
   each command's execution and retain its exit/result; a command starting or
   compiling is not a pass. For OpenSeek run `just check`, `just test`, and
   `just build`; follow the additional editor/browser gates when applicable.
   Run `moon info && moon fmt`, inspect `.mbti` changes, and rerun affected gates
   if formatting or fixes changed source. If any test fails, fix the batch or
   revert only its own edits and record the counterexample. Do not publish a
   failed batch as a completed cleanup. If failures are caused by the evaluation
   launcher environment, establish that from the actual diff/output and rerun
   with the repository's normal test environment. For example, an injected
   `OPENSEEK_REFERENCES` adds a line to CLI environment snapshots; remove that
   test-only override rather than changing snapshots to match the launcher.
7. Review the **actual final diff**, not the original proposal. Use the bundled
   `review.mbtx` with the recorded base SHA and a focused behavior-preservation
   criterion and the recorded gate results. Explicitly ask for source/diff
   inspection without rerunning build, test or benchmark commands: the caller
   already owns validation. If review identifies a concrete uncovered risk,
   verify that its proposed inputs actually reach the claimed branch, then have
   the caller run the smallest additional check once. Resolve blockers
   and material inspection gaps before publication.
   Read the findings and limits even if the script exits zero. Recheck every
   changed file, public interface and executed test command yourself. Do not
   expand the scope with unrelated follow-up suggestions from this review.
   Distinguish a current contract violation from a hypothetical future library
   change: the latter alone is not grounds to undo a verified default-argument
   cleanup or add repetitive call-site tests. Missing per-wrapper coverage is
   not itself a defect in a delegation whose current bodies and dispatch are
   equivalent. Record source equivalence separately from executed coverage;
   add a regression for a concrete changed-path risk, not every touched line.

## Publish and verify

8. Inspect the staged diff and commit only the selected paths. Record the
   tested commit SHA, base SHA, changed paths, commands/results, and the
   ownership/behavior argument in a local delivery record. Push this branch
   without force. Create a PR using the repository's template; explain the
   concrete before/after and validation in one or two short paragraphs. Use
   structured arguments or a body file to preserve text. Reuse an existing PR
   for this branch instead of creating a duplicate. Do not merge or enable
   auto-merge.
9. Read the PR back: verify its repository/base, changed-file list and remote
   head SHA match the tested commit. If the head changed, previous validation
   no longer establishes the published revision. Take **one** CI snapshot with
   `gh pr checks` or `@builtin/ci-watch.mbtx --once`. Do not write a polling loop
   or wait for CI to settle unless the user explicitly requested that. Pending
   CI does not delay returning the verified PR link. Pending means pending,
   not green. Address
   failures introduced by the patch. Put the exact simplification, tests and
   observed CI state in the PR body; retain its verified link for the final response.
   A published draft with an unresolved blocker is partial delivery, not a
   completed task.

After each publication, resume the existing queue when campaign delivery was
requested. Finish when every selected batch has an evidenced disposition. Keep
unselected/deferred candidates and their reasons in the ledger; neither a large
inventory nor a few shipped PRs proves exhaustive semantic review. Start another
sweep only when the request calls for further exploration and the current ledger
has no actionable candidates. Judge the run by verified maintenance reductions
and unresolved gaps, not scout count, deleted lines or PR count alone.
