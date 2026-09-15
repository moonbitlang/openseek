# Structured edit feedback for PTC scripts

Status: proposal. Nothing here is implemented yet.

## Problem

A PTC script receives `edit` and `multi_edit` results as `content` text only;
`data` is `None` for both. The text already carries everything a script would
want to react to: the `moon check` status line, the first ten errors, the
comparability verdict of a reverted batch with its site lists, the parse-gate
excerpts, and (for `replace_all_preview`) a ready-to-use `multi_edit` edits
array. But it is prose, so a script that wants to drop the over-matching edits
and retry the rest, or loop until a deprecation warning is gone, has to parse
sentences. `web_search` already sets `data` (`sources`, `truncated`); this plan
does the same for the two edit tools and answers the dry-run question.

## What feedback exists today

| Path | Text today | Structured source behind it |
|---|---|---|
| `edit` applied | `ok: replaced …` plus the human output of `moon check --diagnostic-limit 1` | none: `append_summary` captures moon's text, one diagnostic |
| `edit` rejected | parse-gate report with excerpts | `ParseGate { errors: [{loc, message, context}], truncated }` |
| `edit` not found | file context excerpt | none needed beyond `outcome` |
| `edit` preview | site list plus a JSON edits array inside the text | `PreviewSite`, entries already built as `Json` then stringified |
| `multi_edit` failed | `file edit[i] range: message` per problem, nothing written | `EditFailure { file, index, range, message }` |
| `multi_edit` rejected | per-file parse-gate report, nothing written | `ParseGate` per file |
| `multi_edit` applied | `moon check: ok — 0 errors, N warning(s)` or `applied with E error(s) kept …` plus first errors | `CheckErrors { error_count, warning_count, errors: [ErrorSite], truncated }` |
| `multi_edit` reverted | head line, first errors, `comparability:` verdict and site lists, re-issue value | `Comparability` fields plus `Verdict` |

Two gaps in the sources themselves: `tally_diagnostics` counts warnings but
drops their sites, and `edit` runs the human-format check rather than the JSON
tally, so it has no structured diagnostics to expose at all.

## Phase 1: `data` payloads (model text unchanged)

One `outcome` discriminator per tool; every other field is present only when
that outcome produces it.

```
edit:       { "outcome": "applied" | "rejected" | "preview" | "not_found" | "error",
              "path", "lines": { "start", "end" },
              "check": CHECK,                       // applied, MoonBit file
              "parse_errors": [{ "loc", "message" }], "introduced": n,   // rejected
              "edits": [{ "file", "old_string", "new_string", "start_line" }],
              "sites_omitted": n }                  // preview

multi_edit: { "outcome": "applied" | "reverted" | "rejected" | "failed",
              "files": [{ "path", "edits": n }], "edit_count": n,
              "failures": [{ "file", "index", "range", "message" }],       // failed
              "parse_errors": { "<path>": [{ "loc", "message" }] },        // rejected
              "check": CHECK, "introduced": n, "threshold": n,             // applied, reverted
              "verdict": "over_match" | "breakage" | "inconclusive"
                       | "certified_reach" | "plausible_reach",            // reverted
              "verdict_reason": "…",
              "new_in_edited": [site], "new_breaking": [site], "new_in_dependents": [site],
              "new_independent": n, "reissue_with": n,
              "restore_failures": [path] }

CHECK:      { "error_count", "warning_count", "truncated",
              "errors":   [{ "path", "loc", "code", "message" }],
              "warnings": [{ "path", "loc", "code", "message" }], "warnings_truncated" }
```

Work items, in dependency order:

1. `auto_check`: keep warning sites in `tally_diagnostics` (cap 200, flag
   `warnings_truncated`) and add `CheckErrors::to_json`. `ErrorSite` is already
   `pub(all)`.
2. `multi_edit`: build the payload alongside the existing eight `respond`
   sites. `Comparability` gains `to_json`; `Verdict` maps to the five strings.
   The text is untouched.
3. `edit`: switch `commit_edit` from `append_summary` (human text, one
   diagnostic) to `count_errors` (JSON tally) and render the same one-line
   status `multi_edit` uses. This is the one place the model-facing text
   changes: the trailing check line becomes `moon check: ok — 0 errors, N
   warning(s)` or `moon check: E error(s)` plus the first errors, instead of
   moon's raw one-diagnostic output. One `moon check` per edit either way, same
   30 s timeout, larger capture budget (400 K vs 12 K characters).
4. `edit` preview: put the same entries array in `data.edits`. The text keeps
   its array for the direct-call path.
5. Bounds: a PTC reply is capped at 64 K characters including `data`, the
   retained trace at 512 KiB per job, and the durable record at 1 MiB. Cap
   `errors` and `warnings` at 200 each and every site list at 50; if the
   payload would still exceed 24 K characters, drop `warnings`, then `errors`
   beyond the first 10, and set `truncated`. Text stays complete.
6. Docs: one paragraph in `agent_tool/ptc/description.mbt` naming the
   `outcome`, `check`, `verdict`, and `edits` fields, the same way it names the
   search shape; the two tool READMEs; the SDK README example.
7. Tests: `to_json` unit tests; one `data` assertion per outcome in the edit
   and multi_edit suites; one SDK fixture script that reads
   `result.data` and prints a verdict, run through the wasm host like the
   existing `agent_tool/mbtx/ptc_test.mbt` cases.

No SDK change: `CallResult.data : Json?` already exists.

## Phase 2: how a script filters with it

These are the four loops the payload is designed for. Patterns 1 and 3 go into
the SDK README as the canonical example once phase 1 lands.

1. **Preview, filter, apply.** `edit` with `replace_all_preview` returns
   `data.edits`; the script drops entries by predicate (path, line text, a
   regex on `old_string`'s surroundings) and passes the rest to `multi_edit`.
   This is the filter the direct-call model does by eye today.
2. **Validate, drop failures, apply.** `multi_edit` with `dry_run` (phase 3)
   returns `data.failures`; the script removes those indexes and applies the
   remainder in one call instead of failing the whole batch.
3. **Apply with `revert_when_errors_above: 0`, then decide.** On
   `outcome == "reverted"`: `over_match` drops the edits whose file and line
   appear in `new_in_edited` and re-applies; `certified_reach` re-issues the
   unchanged batch with `reissue_with`; `breakage` and `inconclusive` stop and
   print the sites for the model. The tool already computes all of this; the
   script only branches on it.
4. **Warning-driven loops.** After a deprecation rename, `check.warnings`
   filtered by `code` says what remains; the script loops while the count
   drops and stops on no progress. The 64-call budget per script bounds it.

## Phase 3: dry-run

Three candidates were considered.

**A. `dry_run: true` on `multi_edit` and `edit`: matching and parse gate only.**
Resolve every edit against the current file content, run the parse gate on the
candidate content, write nothing, and return `outcome: "validated"` with the
per-edit resolution (`file`, `index`, resolved line range) and any parse
errors. Cost: one `moonc syncheck` per touched file, no `moon check`. It is
deterministic, side-effect free, and takes the file gate only for consistent
reads. This is the recommended shape.

**B. Full compile dry-run: apply, `moon check`, always restore.** Not
recommended. It costs a pre-batch and a post-batch check (each with a 30 s
timeout) and, more importantly, the files transiently hold the candidate
content. The file gate serializes tool-side file operations only, so a
background `moon test` job, the editor, or the user's shell can observe the
transient tree. `revert_when_errors_above: 0` already gives "keep the batch
only if it introduces no new error" at the same cost with no extra mode, and
with phase 1 its report is machine-usable. The only thing B adds, seeing the
errors of a batch without keeping it even when clean, is not worth a second
write-and-restore path.

**C. `replace_all_preview` on `edit`** is already a dry-run for match sites;
phase 1 makes its output structured. Nothing more to build.

So: dry-run = A plus C. The name is `dry_run` for discoverability, and its
description says in the first sentence that it runs matching and the parse
gate but not `moon check`, so nobody expects compile feedback from it.

## Phase 4: measure

Add one case to `eval/ptc_prompt`: a rename where the old name also appears in
comments, string literals, and a same-named method on another receiver, so a
naive batch over-matches. Baseline is the current tools; candidate is phase 1
plus the README patterns. Compare steps, nested-call counts, and byte oracles
with the existing harness (`require_ptc` case shape). Expect the candidate to
recover from the first reverted batch inside the script instead of returning
to the model.

## PR split

1. `auto_check`: warning sites and `to_json` (small, no behavior change).
2. `multi_edit` payload plus tests.
3. `edit` payload, preview `data.edits`, and the check-line alignment.
4. `dry_run` on both tools.
5. Descriptions, READMEs, SDK example, eval case.

Each is independently reviewable and lands behind the one before it.

## Decisions needed

1. Accept the `edit` check-line change in phase 1 item 3 (recommended: yes;
   it is the only way `edit` gets structured diagnostics without a second
   `moon check`).
2. Dry-run semantics: validation only (recommended) versus full compile
   dry-run.
3. Retain warning sites in `CHECK` (recommended: yes, capped at 200; they are
   the feedback pattern 4 depends on).
