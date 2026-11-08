# Fixing warnings from a PTC script: per-edit revert guards and structured feedback

Status: implemented 2026-09-16 as #1570 (tally, identity diff, 1024 calls),
#1571 (edit guards and data), #1572 (multi_edit guard and data), #1573
(the bundled script and docs). The outcome section at the end records what
changed against this plan during implementation and review.

## The target loop

The primary use case is a script that fixes most of a project's warnings in
one pass and leaves the rest for a manual fix:

1. Run `moon check --output-json` from the script itself and parse the JSON
   lines: every warning with its path, a `line:col-line:col` span, its code,
   and its message. The sandbox admits `moon check` (the bundled
   `@builtin/check-json.mbtx` does exactly this), and a PTC run uses the same
   policy.
2. For each warning of a class the script knows how to fix, read the file
   (scripts already have workspace read access) and cut `old_string` from the
   span. `start_line` is the span's line. `new_string` comes from the message:
   a deprecation says "use `len` instead", an unused binding gets an underscore
   prefix, an unused import drops a manifest line.
3. Apply each fix with a single `edit` call that carries
   `revert_on_errors: true` and `revert_on_warnings: true`. The tool checks
   the tree before and after the write; if the edit introduced an error or a
   warning it restores the file and says so.
4. Collect the outcomes. Kept edits are done; reverted edits and warnings of
   unhandled classes are printed for the model and the human.

Single edits are the unit on purpose. Each fix is compile-checked alone,
against the tree that already contains the previous kept fixes, so a bad fix
is identified exactly and undone by the tool, with no attribution problem and
no partial batch to untangle. Line numbers never go stale because every edit
is built from the diagnostics of the tree as it is at that moment.

## What exists today

- `multi_edit` already has the post-write guard: write, `moon check`, count
  errors introduced against a baseline, restore on breach, and a report with a
  comparability verdict. `edit` has only the pre-write parse gate and appends
  moon's human one-diagnostic text after a successful write.
- `auto_check` tallies `moon check --output-json` into `CheckErrors`
  (`error_count`, `warning_count`, `errors: [ErrorSite {path, loc, code,
  message}]`, `truncated`). Warnings are counted; their sites are dropped.
- Neither tool sets `ToolOutput.data`; `web_search` does (`sources`,
  `truncated`) and is the precedent. A PTC script already receives
  `result.data : Json?` through the published SDK, so no SDK change is needed.
- A script can spawn `moon check --output-json` (the policy's spawn list
  admits it, and PTC runs build the same policy with the capability injected),
  so the loop seeds itself. Parsing the JSON lines is the script's job; the
  SDK README example shows the pattern.

## Work, in order

### 1. Warning sites and a diff rule (`auto_check`)

Keep warning sites in the tally (`warnings: [ErrorSite]`, capped at 200 with
`warnings_truncated`). Add `CheckErrors::to_json`. Add one pure function that
computes what a change introduced: compare the multisets of
`(path, code, message)` before and after, ignoring `loc`. This is robust to
the line shifts an edit causes below itself, and it catches a fix that
removes one warning and introduces another, which a count comparison cannot.
The same rule serves errors.

### 2. Seeding from the script's own `moon check`

No new tool. The script runs `moon check --output-json` through
`@shell.Cmd`, keeps the lines whose `level` is `warning`, and reads `path`,
`loc`, `error_code`, and `message`. That is the same JSON the host tallies,
so the script and the guard agree on what a warning is. The SDK README
example carries the ten-line parser. Script calls run one after another, so
its own check never overlaps a guard check inside an edit; a script that
spawns tasks must keep it that way.

### 3. Shared revert guard; two new `edit` flags

Move the apply, check, restore, and report machinery out of `multi_edit` into
an internal package. `edit` gains two post-write guards next to its existing
pre-write `revert_on_parse_errors`:

- `revert_on_errors` (default false): restore the file when the edit
  introduced an error.
- `revert_on_warnings` (default false): restore the file when the edit
  introduced a warning.

With either flag set the tool checks before the write and after it: two
checks per edit. `multi_edit`'s lazy baseline (check the baseline only when
the post-batch count breaches the threshold) does not pay here, because in a
warning-heavy tree the post-edit warnings are never zero, so lazy would mean
three checks with a restore in the middle. Without either flag `edit` behaves
exactly as today. `multi_edit` gets `revert_on_warnings` from the same code.

### 4. `data` payloads

One `outcome` discriminator per tool; other fields appear only for the
outcomes that produce them.

```
edit:       { "outcome": "applied" | "reverted" | "rejected" | "preview" | "not_found" | "error",
              "path", "lines": { "start", "end" },
              "check": CHECK,                                   // applied, reverted
              "introduced": { "errors": [site], "warnings": [site] },   // reverted
              "parse_errors": [{ "loc", "message" }],           // rejected
              "edits": [{ "file", "old_string", "new_string", "start_line" }] }   // preview

multi_edit: { "outcome": "applied" | "reverted" | "rejected" | "failed",
              "files": [{ "path", "edits": n }], "edit_count": n,
              "failures": [{ "file", "index", "range", "message" }],        // failed
              "parse_errors": { "<path>": [{ "loc", "message" }] },         // rejected
              "check": CHECK, "introduced": { "errors": [site], "warnings": [site] },
              "threshold": n,
              "verdict": "over_match" | "breakage" | "inconclusive"
                       | "certified_reach" | "plausible_reach", "verdict_reason",
              "new_in_edited": [site], "new_breaking": [site], "new_in_dependents": [site],
              "new_independent": n, "reissue_with": n, "restore_failures": [path] }

CHECK:      { "error_count", "warning_count", "truncated",
              "errors":   [{ "path", "loc", "code", "message" }],
              "warnings": [{ "path", "loc", "code", "message" }], "warnings_truncated" }
```

`edit` comes first (it is the loop's unit), `multi_edit` second. The
model-facing text of `multi_edit` is unchanged. For `edit`, the trailing check
line after a successful write becomes the same one-line status `multi_edit`
prints (`moon check: ok — 0 errors, N warning(s)`, or the error count plus the
first errors) instead of moon's raw one-diagnostic output, because the JSON
tally is the only way `edit` gets structured diagnostics without a second
check.

### 5. Docs and the SDK example

One paragraph in `agent_tool/ptc/description.mbt` naming `outcome`, `check`,
and `introduced`, the way it names the search shape; the two tool READMEs; the
warning-fix loop as the canonical SDK README example, run as a fixture through
the wasm host like the existing `agent_tool/mbtx/ptc_test.mbt` cases.

### 6. Eval case

A fixture with a few dozen deprecation and unused-binding warnings across
several files, plus a couple of fixes that would introduce a warning or an
error so the guards have something to revert. Baseline is the current tools;
candidate is items 1 to 5 (item 2 is the script's own doing). Measure rounds, nested-call counts, how many
warnings remain, and whether `moon check --deny-warn` passes afterwards.

## Bounds

- A PTC script may make 64 calls, so one run fixes about sixty warnings. For
  larger backlogs the script runs again, or the per-script call budget is
  raised (the 512 KiB trace budget remains the hard bound on retained data;
  edit results are small). See decisions.
- A PTC reply is capped at 64 K characters including `data`, the retained
  trace at 512 KiB per job, the durable record at 1 MiB. Cap `errors` and
  `warnings` at 200 each and every site list at 50; if a payload would still
  exceed 24 K characters, drop `warnings`, then `errors` beyond the first 10,
  and set `truncated`. Text stays complete.
- `moon check` skips the dependents of a failing package, so the warnings list
  is complete only when the error count is zero. The script fixes errors
  first, or accepts that later rounds surface more warnings as the build
  reaches further.

## Deferred

- `dry_run` (matching plus parse gate, no `moon check`) on both tools. The
  per-edit loop does not need it: a non-matching `old_string` already fails
  before any write, and the loop rebuilds edits from fresh diagnostics each
  round. Worth adding later for batch-oriented scripts.
- Batch-oriented loops on `multi_edit` (preview, filter, apply; branch on the
  revert verdict). The payload above supports them; they are not the first
  use case.
- A full compile dry-run that always restores: rejected. `revert_on_*` already
  gives "keep only if clean", and always-restore would only add a transient
  tree visible to background jobs and the editor.

## PR split

1. `auto_check`: warning sites, `to_json`, the introduced-diff rule.
2. Shared revert guard; `edit` gains `revert_on_errors` and
   `revert_on_warnings`; `multi_edit` gains `revert_on_warnings`.
3. `edit` payload and check-line alignment; preview `data.edits`.
4. `multi_edit` payload.
5. Descriptions, READMEs, SDK example (with the warning-fix loop and its
   JSON-lines parser), eval case.

## Decisions

1. Defaults for `revert_on_errors` and `revert_on_warnings` on `edit`
   (recommended: both off at first, revisit after the eval; on would also
   protect direct model edits the way `multi_edit` already does).
2. Accept the `edit` check-line change in item 4 (recommended: yes).
3. Raise the per-script call budget from 64 (for example to 256) so one run
   covers a larger backlog, or keep 64 and run the script more than once.

## Outcome

What the implementation and its reviews changed against the plan above:

- **No cap in the tally.** Warning sites are kept in full (as errors were);
  only the JSON form caps at 200 per severity. A capped list would have made
  the identity diff wrong on the primary workload (fixing one of 201 warnings
  brings a hidden one into view). An overflowed capture is refused by the
  guards as `unverified` instead of compared.
- **A failed run is not a clean tree.** `check(path)` distinguishes
  `NotApplicable`, `Unavailable(reason)`, `Failed(code, tally)` (moon exited
  non-zero with no diagnostic), and `Checked(tally)`. A guarded edit is not
  written when the baseline cannot be measured, and is rolled back when the
  post-write check fails. `count_errors` keeps its old reading for the
  `multi_edit` error guard.
- **Occurrence selection.** `edit` takes no column, so the script anchors
  `old_string` on the whole line prefix through the diagnosed span; the first
  match at that line is exactly that occurrence. It works bottom-up per file
  and right to left per line, so no span goes stale and no second check per
  site is needed; the host's post-edit counts confirm progress.
- **Links.** A file reached through a link is compiled by every module either
  spelling belongs to, so the guards check each project (compared by
  canonical directory) and merge the tallies. `multi_edit`'s error guard keeps
  reading the first project; its warning guard reads them all.
- **Cancellation and containment.** Guarded writes register their rollback
  before the write (which truncates before it writes) under
  `protect_from_cancel`, and the restore goes through the same containment
  rule as the write.
- **Payload size.** `edit` carries a compact check (counts plus the first ten
  error sites, no warning list); `multi_edit` carries the bounded full form.
  `data.edits` on preview was left out (its text array already sits near the
  reply cap).
- **The check line after an unguarded `edit`** is rendered from the JSON
  tally with one concrete diagnostic kept visible (the first warning on a
  clean tree), and an overflowed zero-error capture is reported as
  incomplete rather than clean.
- **Qualified spans.** moon reports `@a.length` as the span of a qualified
  call, so the script keeps the qualifier (`@a.`, `Type::`) and swaps only
  the name.
- **Measured cost** on this repository: an incremental `moon check` after a
  one-line edit is about 0.5 s, so a guarded edit costs about a second.
- **Thresholds, not booleans.** On review the guards became integer
  thresholds, `revert_when_errors_above` and `revert_when_warnings_above`
  on both tools (absent = off, `0` = revert on any introduced diagnostic,
  `N` = tolerate up to N), matching `multi_edit`'s existing error
  threshold, and every guarded result's `data` carries `introduced_count`
  and `removed_count` per severity so the delta is quantified even when
  the edit is kept. The warning-fix script passes `0` for both.
- **Not done:** the eval harness case and a live-model run; the two
  host-backed tests exercise the script end to end without a model.
