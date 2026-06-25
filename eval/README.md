# DeepSeek V4 Pro Evaluation Harnesses

This directory describes proposed harnesses for evaluating OpenSeek with
`deepseek-v4-pro` against stronger and weaker coding-agent baselines.

The checked-in eval support packages are:

- `eval/report`: shared Markdown/JSON report rows, metrics, and file writer.
- `eval/tool_harness`: deterministic host-side harness that dispatches every
  built-in tool through `agent_tool.execute_tool_call`.
- `eval/file_edit`: nondeterministic model-facing file-edit harness that runs
  the real agent against isolated fixtures.
- `eval/prompt_task`: nondeterministic model-facing prompt-task harness that
  runs repeated MoonBit prompt tasks concurrently and validates the final
  generated workspace independently.

Run deterministic harnesses with ordinary tests:

```bash
moon test eval/report eval/tool_harness eval/file_edit/harness eval/prompt_task/harness
```

The design borrows the useful parts of SWE-AGI: each task should be a cold-start
MoonBit project with a fixed public API scaffold, visible public tests for local
iteration, hidden private tests for scoring, and machine-readable run logs and
metrics. SWE-AGI currently packages 22 MoonBit tasks across data formats,
markup, language front-ends, binary decoders, networking/protocol state
machines, template/DSL tasks, and SAT solving.

## Runner Matrix

Use the same task bundle for each runner. Keep prompts, time limits, network
policy, and visible tests identical.

| Runner | Purpose | Invocation Shape |
| --- | --- | --- |
| `openseek-deepseek-v4-pro` | Main subject under test. Measures our agent loop, DeepSeek V4 Pro reasoning, MoonBit prompt, and local tools together. | `moon run cmd/main -- --model deepseek-v4-pro "$(cat TASK.md)"` |
| `codex-strong` | Strong reference agent. Measures whether failures are task difficulty or OpenSeek-specific. | Codex runner with a current strong coding model. |
| `codex-weak` | Lower-cost/weak baseline. Measures whether DeepSeek clears a practical quality bar. | Same Codex runner with a deliberately cheaper model. |
| `deepseek-v4-pro-compat` | Optional control. Measures DeepSeek through an existing SWE-AGI-compatible runner if available. | SWE-AGI-style runner using DeepSeek credentials. |

Record at least:

- final public-test result
- final private-test result
- elapsed wall time
- model/API token usage and cache hit/miss tokens when available
- number of tool calls
- number of repair loops after compiler/test failures
- whether the final diff changes public API beyond the scaffold
- whether the agent called a final submission/finish action before validation

## Workspace Layout

For local experimentation, keep task workspaces isolated. `moon work` can group
multiple harness modules without mixing package boundaries:

```bash
mkdir -p eval/tasks
moon work init
moon work use eval/tasks/json_patch eval/tasks/expr_eval
moon work sync --dry-run
```

For SWE-AGI-compatible scoring, mirror its public/private split:

- `TASK.md`: user-visible task statement and constraints
- `moon.mod.json` and one or more `moon.pkg` files
- `*_spec.mbt`: fixed API scaffold
- `*_pub_test.mbt`: visible tests
- `*_priv_test.mbt`: hidden tests copied only into the scoring checkout
- `run-metrics.json`: runner, elapsed time, exit code, and test summary
- `log.jsonl` and `log.yaml`: raw and readable agent transcript

## Prompt A/B MoonBit Task Set

File-editing evals are useful for checking agent plumbing, but they are too
shallow to measure MoonBit prompt quality. Prompt experiments should use
MoonBit-heavy tasks with real compilation, tests, and CLI probes.

Run each prompt variant with `deepseek-v4-flash` first. Keep the task statement,
workspace scaffold, visible tests, max steps, and model fixed. Run at least
three repetitions per variant before promoting a prompt change; use five when a
task is noisy.

The checked-in prompt-task runner supports five concurrent repeats:

```bash
moon run --target native eval/prompt_task/cmd/main -- \
  --api-key "$DEEPSEEK" \
  --model deepseek-v4-flash \
  --runs 5 \
  --concurrency 5 \
  --min-successes 5 \
  --max-steps 160 \
  --prompt-label flash-current \
  --out .moonagent/eval_runs/toml_flash_current_5x
```

Start with these tasks:

1. **TOML Parser And CLI**
   Build a TOML subset parser with strings, integers, booleans, arrays, tables,
   dotted keys, comments, duplicate-key errors, and a native CLI supporting file
   and stdin input. This is the first serious prompt test because it stresses
   MoonBit syntax, data modeling, parser structure, native CLI args, and
   `moon run -e` probing.

2. **JSONPath Query CLI**
   Implement `$`, child access, bracket access, array indexes, wildcards,
   descendants, and simple equality filters over `Json`. This tests API
   discovery, structured errors, and command quoting/log behavior.

3. **Markdown Frontmatter Indexer**
   Parse frontmatter and Markdown headings across many files, then expose stable
   JSON/JSON Lines filters through a CLI. This tests filesystem traversal,
   malformed input handling, stable ordering, and stdout/stderr hygiene.

4. **Async File Statistics Pipeline**
   Build a native-only async CLI that walks a directory, reads files
   concurrently, and emits deterministic JSON statistics. This directly probes
   whether the prompt improves `moonbitlang/async` API discovery and repair.

5. **Failing Package Repair**
   Give the agent a package with a fixed public API and 10-20 failing tests.
   Require it to repair behavior without changing the generated `.mbti` surface.
   This measures practical debugging discipline, minimal diffs, and whether the
   prompt makes the agent validate before finishing.

6. **Expression Parser And Evaluator**
   Implement a Pratt or precedence-climbing parser with spans and structured
   diagnostics. This separates general algorithmic reasoning from MoonBit
   syntax/tooling failures.

For each run, monitor the log in addition to final tests:

- `moon run -e` and stdin probe use when syntax/API uncertainty appears
- any `moon run -c` mention, which should trend to zero
- compiler/test repair loops and whether the same root cause repeats
- avoidable tool-call failures: bad schema fields, stale edits, shell bypasses,
  and malformed MoonBit command arguments
- validation coverage before finish: `moon check`, targeted `moon test`,
  `moon info`, `moon fmt`, and task-specific CLI probes
- CLI contract quality: file mode, stdin mode, exit codes, valid JSON/JSON
  Lines, clean stdout/stderr, and no leaked runtime debug output
- final-summary honesty: whether the agent accurately reports commands it ran
  and any remaining caveats

Keep a prompt change only when it improves task outcomes and the behavior trace.
Do not promote a wording change that merely gets lucky on pass/fail while
increasing repeated tool errors, API guessing, or unverified final claims.

## Ten Non-TOML Harnesses

### 1. Moon Workspace Dependency Planner

Task: build a CLI that reads a workspace containing several MoonBit modules and
prints a deterministic dependency-version sync plan.

Why it helps: this targets current MoonBit workflow knowledge, `moon work`
semantics, JSON parsing, filesystem traversal, and careful CLI output.

Public tests should cover two modules with one drifted dependency. Private tests
should include cyclic directory layouts, missing manifests, already-synced
workspaces, and dry-run output stability.

Primary signal: can the agent discover current `moon work` behavior and produce
a conservative tool instead of hard-coding guesses?

### 2. JSON Patch And Diff CLI

Task: implement JSON Pointer, JSON Patch application, and a simple structural
diff CLI for MoonBit `Json`.

Why it helps: the domain is specification-heavy but small enough for an eval
run. It tests edge cases, path escaping, array-index semantics, and precise
error reporting.

Public tests should cover add/remove/replace and object paths. Private tests
should cover escaped pointer segments, array bounds, move/copy, invalid patches,
and idempotent diff/apply round trips.

Primary signal: long-horizon spec following with clean data modeling.

### 3. Expression Parser And Evaluator

Task: implement a Pratt or precedence-climbing parser for arithmetic,
variables, function calls, and structured errors.

Why it helps: many agents can write a toy evaluator; fewer can preserve
precedence, associativity, spans, and useful diagnostics while keeping tests
blackbox.

Public tests should cover arithmetic and variables. Private tests should cover
nested calls, unary/binary ambiguity, bad tokens, recovery after errors, and
large expression depth.

Primary signal: algorithmic reasoning plus parser architecture.

### 4. Glob Engine And Mini Grep

Task: implement glob matching with `*`, `?`, character classes, escaping,
recursive `**`, and a CLI that filters paths.

Why it helps: this tests finite-state reasoning, path normalization, and CLI
ergonomics without relying on external libraries.

Public tests should cover basic wildcards. Private tests should cover escaped
metacharacters, hidden files, path separators, nested `**`, empty segments, and
Windows-like paths as plain data.

Primary signal: edge-case discipline and portable path handling.

### 5. Markdown Frontmatter Indexer

Task: parse Markdown files with YAML-like frontmatter, build an in-memory index,
and expose filters through a CLI.

Why it helps: this combines file IO, partial parsing, stable output ordering,
and pragmatic data modeling.

Public tests should cover title/tags/date filters. Private tests should cover
missing delimiters, malformed fields, repeated keys, Unicode text, and many-file
ordering.

Primary signal: real-world workflow completion with imperfect input.

### 6. Async File Statistics Pipeline

Task: build a native-only async CLI that walks a directory, reads files
concurrently, and emits JSON line/count/byte statistics.

Why it helps: DeepSeek previously needed better native CLI and async examples.
This harness directly measures whether it can discover and use `moonbitlang/async`
packages correctly.

Public tests should cover a small fixture directory. Private tests should cover
empty directories, unreadable paths, concurrency limits, binary-ish files, and
deterministic JSON ordering.

Primary signal: MoonBit async API discovery and repair from compiler feedback.

### 7. Git Object Decoder

Task: decode loose Git object files: zlib inflate, object header parsing, blob,
tree, commit, and tag summaries.

Why it helps: binary formats force byte-level care, robust validation, and
useful error surfaces.

Public tests should cover a blob and a simple commit. Private tests should cover
tree entries, malformed sizes, truncated data, invalid object kinds, and
round-trip fixtures.

Primary signal: binary parsing accuracy and defensive programming.

### 8. URI/URL Normalizer

Task: implement a standards-informed URI parser, resolver, and normalizer with
a CLI.

Why it helps: this is a compact protocol/state-machine task with many corner
cases. It also aligns with SWE-AGI categories.

Public tests should cover scheme/host/path/query parsing. Private tests should
cover dot-segment removal, percent encoding, IPv6 literals, relative resolution,
empty authority, and invalid inputs.

Primary signal: spec comprehension and incremental correction.

### 9. Small SAT Solver

Task: implement a DIMACS CNF parser plus a DPLL solver with unit propagation
and pure-literal elimination.

Why it helps: this gives a clean algorithmic benchmark with objective answers.
It is less MoonBit-specific than parser tasks, so it separates reasoning from
language familiarity.

Public tests should cover satisfiable/unsatisfiable toy formulas. Private tests
should cover parsing comments, empty clauses, larger propagation chains,
deterministic models, and timeout-safe branching.

Primary signal: algorithmic depth and testable correctness.

### 10. Failing Package Repair

Task: give the agent an existing MoonBit package with a fixed public API and
10-20 failing public tests. Ask it to repair behavior without changing the
generated `.mbti` surface.

Why it helps: this is closest to day-to-day coding-agent work. It measures
debugging, minimal diffs, and respect for API boundaries.

Public tests should reveal a representative subset of bugs. Private tests should
cover the same behavior more broadly plus API-surface checks from `moon info`.

Primary signal: practical agent usefulness under compiler and test feedback.

## Scoring

Use a small score vector instead of a single pass/fail bit:

| Metric | Weight | Notes |
| --- | ---: | --- |
| Private tests pass | 40 | Main correctness gate. |
| Public tests pass | 10 | Catches non-submission and basic regressions. |
| API scaffold preserved | 10 | Compare generated `.mbti` against expected surface. |
| Validation discipline | 10 | Did the agent run `moon check`, `moon test`, `moon info`, and `moon fmt` before finalizing? |
| Diff quality | 10 | Minimal, idiomatic, no unrelated churn. |
| Repair efficiency | 10 | Fewer repeated compiler/test failures for the same root cause. |
| Cost and cache behavior | 10 | Token/API cost, cache hit rate, wall time. |

Report both raw pass/fail and this score. A model that passes after 40 wasteful
repair loops is different from one that passes after three targeted loops.

## Recommended First Batch

Start with five harnesses:

1. Moon Workspace Dependency Planner
2. JSON Patch And Diff CLI
3. Expression Parser And Evaluator
4. Async File Statistics Pipeline
5. Failing Package Repair

This mix covers MoonBit-specific tooling, spec following, algorithmic reasoning,
async/native APIs, and real repair behavior. Add the other five after the runner
and logging path is stable.

## References

- SWE-AGI repository: <https://github.com/moonbitlang/SWE-AGI>
- SWE-AGI task packaging: <https://github.com/moonbitlang/SWE-AGI/blob/main/tasks/README.md>
- SWE-AGI public/private evaluation protocol: <https://github.com/moonbitlang/SWE-AGI/blob/main/tasks/EVALUATION.md>
- SWE-AGI Docker runner and metrics: <https://github.com/moonbitlang/SWE-AGI/blob/main/docker/README.md>
