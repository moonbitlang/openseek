# Easy Harness Batch: OpenSeek + DeepSeek V4 Pro

Date: 2026-05-18

Runner: `openseek-deepseek-v4-pro`

Command shape:

```bash
moon run cmd/main -- --model deepseek-v4-pro "$(cat .moonagent/eval_runs/<task>/TASK.md)"
```

The easy batch here means the self-contained harnesses that do not require
native async, Git object inflation, or workspace dependency scanning:

- Expression Parser And Evaluator
- Glob Engine And Mini Grep
- Markdown Frontmatter Indexer
- Small SAT Solver
- JSON Patch And Diff CLI
- URI/URL Normalizer

## Summary

| Task | Public Result | Private Result | Outcome |
| --- | ---: | ---: | --- |
| Expression Parser And Evaluator | 4/4 | 10/10 total | Pass |
| Glob Engine And Mini Grep | 3/3 | 8/8 total | Pass |
| Markdown Frontmatter Indexer | 2/2 | 7/7 total | Pass |
| Small SAT Solver | 3/3 | 7/7 total | Pass |
| JSON Patch And Diff CLI | Did not compile | Not run | Fail |
| URI/URL Normalizer | Did not compile | Not run | Fail |

Fresh runs in this batch passed 3 of 5 tasks. Including the earlier expression
run, the easy set is 4 of 6.

## Notes

Expression Parser And Evaluator is recorded separately in
`eval/results/expr-eval-openseek-deepseek-v4-pro.md`.

Glob passed after one compiler repair loop. Public tests passed, then hidden
tests were copied into the workspace and `moon check --warn-list
+unnecessary_annotation && moon test` passed with 8 total tests. The agent ran
the requested validation commands, but the process was stopped after it became
idle following validation.

Markdown Frontmatter passed after one compiler repair loop around iterator,
tuple destructuring, and in-place sorting APIs. The final agent run finished
normally. Hidden scoring passed with 7 total tests.

Small SAT passed after one compiler repair loop around warning-as-error
`unused_mut`, tuple destructuring in `for`, and `StringBuilder` APIs. Hidden
scoring passed with 7 total tests.

JSON Patch was stopped after 21 steps. The final workspace still failed
`moon check --warn-list +unnecessary_annotation` with 76 errors. The main
failure modes were old postfix `?`, `try!` misuse with `Result`, using read-only
`Json` constructors directly, `StringView` conversion mistakes, and deprecated
`not(...)` syntax. A first aborted attempt also exposed a harness issue:
`debug_inspect` prints `Json` constructors, so the public tests were corrected
to compare `Json` values or `stringify()` before the retry.

URI/URL Normalizer was stopped after 21 steps. The final workspace still failed
`moon check --warn-list +unnecessary_annotation` with 93 errors. The main
failure modes were invented `String::index_of`/`rindex_of` APIs, uninitialized
non-mut `let` bindings, postfix `?`, `StringView` versus `String` mismatches,
and reserved identifier warnings.

## Validation Commands

Passing task workspaces were scored independently after hidden tests were added:

```bash
cd .moonagent/eval_runs/<task>
cp ../private/<task>_priv_test.mbt <task>_priv_test.mbt
moon check --warn-list +unnecessary_annotation
moon test
```

Observed scored totals:

```text
expr_eval_task: Total tests: 10, passed: 10, failed: 0.
glob_task: Total tests: 8, passed: 8, failed: 0.
frontmatter_task: Total tests: 7, passed: 7, failed: 0.
sat_task: Total tests: 7, passed: 7, failed: 0.
```
