# Deliver one small de-slop PR

Use this as the calling agent's task recipe when the user asks for cleanup and
PR delivery. `de-slop.mbtx --deliver` performs read-only discovery/challenge and
hands control back here; **the calling agent executes the remaining steps**.
This is one end-to-end task, with no user handoff between phases. A successful
audit is an intermediate result. Continue in the same task until there is one
verified PR URL, an evidenced no-change result, or an unavoidable blocker. Do
not ask again for publication permission already granted by the user. Without PR authorization,
stop at the tested diff and ask only when publication is the remaining step.

## Completion contract

When the user requests PR delivery, the final user-facing answer is **only the
verified PR link**: `[PR #NUMBER](URL)`. Put the change explanation, tests and
observed CI status in the PR body; retain discovery, rejected candidates and
workflow feedback in local artifacts. Do not replace delivery with an audit
summary, a tested patch, a proposed next step, or a request to continue.
The script's delivery handoff is internal control flow, not a handoff to the user.

A genuine no-change result or unavoidable blocker is the only exception: give
one concise factual line, without manufacturing a PR. Do not count a draft with
failing required checks as successful delivery. No summary after a published PR.

## Establish the batch

1. Read repository instructions and their linked validation guides. Record
   HEAD, status and existing work. Fetch the requested upstream. Start from its
   current tip in a clean `codex/` branch/worktree; if the user requested their
   existing changes as the baseline, preserve those instead. Never stash,
   reset, stage, commit or publish unrelated work merely to make delivery easy.
2. Start with `de-slop.mbtx --deliver .` when the scope is unknown. When a
   previous sweep or user feedback supplies a concrete candidate, use a focused
   invocation with `--focus` carrying that candidate verbatim, e.g.
   `args=["--deliver","--focus","reuse difference in symmetric_difference",
   "hashset/hashset.mbt"]`, instead of paying
   for the whole scan again. Use `subrun=true`. Wait for the actual workflow
   job and inspect its ledger; outer CLI exit zero is not evidence it succeeded.
   **Phase barrier:** do not edit until the challenge has finished successfully
   and emitted the delivery handoff. While it runs, only read and run baseline
   tests. Provisional discovery output is not approval to implement. The script
   compares Git-visible scoped source before/after and refuses the handoff if
   it changed; this is a stale-evidence check, not an exclusive filesystem lock.
3. Choose **one maintenance concern**, normally no more than five files and
   100 changed lines. Prefer a direct default-argument, copy or duplicated-body
   simplification with existing behavior tests. Those limits are a batching
   guideline, not a reason to split a necessary caller fix. Default to one PR
   per task, not one PR per file. No candidate quota: if none survives, report
   the actual reasons and make no empty commit/PR.

Before starting expensive work, check that the calling environment can run the
repository gates and publish with Git/gh. If an inner CLI policy blocks a
required executable, preserve the branch, diff, job state and exact failure,
and hand that step to the authorized outer host. The host resumes from those
artifacts; it must not duplicate a still-running job or PR. Do not change sandbox
policy or disguise the command to bypass a denial. Partial substitutes for a
required gate do not establish that gate passed.

## Prove and apply

4. Independently read the selected sites, callers, current library declarations
   and tests. Treat ACCEPT, KEEP and REJECT as claims. Resolve contradictory
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
   have the caller run the smallest additional check once. Resolve blockers
   and material inspection gaps before publication.
   Read the findings and limits even if the script exits zero. Recheck every
   changed file, public interface and executed test command yourself. Do not
   expand the scope with unrelated follow-up suggestions from this review.
   Distinguish a current contract violation from a hypothetical future library
   change: the latter alone is not grounds to undo a verified default-argument
   cleanup or add repetitive call-site tests.

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
   observed CI state in the PR body; the final response contains only its link.
   A published draft with an unresolved blocker is partial delivery, not a
   completed task.

Leave remaining candidates in the audit report. Do not restart a full sweep
or open more PRs to fill a quota after this coherent batch has shipped.
