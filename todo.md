# OpenSeek Evaluation TODO

## DeepSeek V4 Pro TOML Parser Run

- Status: failed/incomplete as of 2026-05-22 11:17 CST.
- Task: use the OpenSeek agent with `deepseek-v4-pro` reasoning mode to create a MoonBit TOML parser plus CLI that dumps parsed TOML as JSON.
- Model setting: `OPENSEEK_MODEL=deepseek-v4-pro`; OpenSeek defaults used reasoning mode with max reasoning effort.
- Log: `.moonagent/eval_runs/results/openseek_toml_cli_d4pro_reasoning.log`
- Log size: 2,283 lines / 99,169 bytes.
- Output workspace: `.moonagent/eval_runs/toml_cli_task`
- Result: the run stopped at step 60 with `=== max steps exhausted ===`.
- Validation: `moon check` in the generated workspace fails with 111 errors and 22 warnings.
- Missing deliverables: no CLI package, no README, no tests, no `moon info` output, and no passing `moon test`.

## DeepSeek V4 Pro TOML Parser Retry

- Status: stopped/incomplete as of 2026-05-22 12:35 CST after the run stalled at step 45.
- Task: same TOML parser plus JSON-dump CLI task, using `--max-steps 1000`.
- Log: `.moonagent/eval_runs/results/openseek_toml_cli_d4pro_reasoning_retry.log`
- Log size: 1,451 lines / 80,528 bytes.
- Output workspace: `.moonagent/eval_runs/toml_cli_task_retry`
- Result: log streaming worked; step output appeared immediately in `tee`.
- Progress: the retry scaffolded module, TOML package, and CLI package by step 2, then generated `types.mbt`, `scanner.mbt`, and `parser.mbt`.
- Validation: final manual `moon check` in the generated workspace fails with 59 errors and 12 warnings.
- Missing deliverables: no CLI source, no README, no tests, no `moon info` output, and no passing `moon test`.

## DeepSeek V4 Pro TOML Parser V3

- Status: succeeded as of 2026-05-22 15:16 CST.
- Task: same TOML parser plus JSON-dump CLI task, using `--max-steps 1000`.
- Log: `.moonagent/eval_runs/results/openseek_toml_cli_d4pro_reasoning_v3.log`
- Log size: 4,715 lines / 159,001 bytes.
- Output workspace: `.moonagent/eval_runs/toml_cli_task_v3`
- Result: the agent finished successfully at step 109 with parser package, native CLI package, README, public tests, whitebox tests, generated interface, and passing validation.
- Validation: independent `moon check` and `moon test` in the generated workspace passed with 32 tests.
- CLI smoke: `moon run --target native cmd/main -- /tmp/openseek-toml-v3-smoke.toml` produced `{"title":"Smoke","owner":{"name":"Moon","ports":[8000,8001]}}`.
- Performance improvement over earlier runs: the agent recovered from manifest and API mistakes, discovered current `Json` and async filesystem APIs before finalizing code, ran `moon check` repeatedly, and reached a clean parser package by the mid-run before adding CLI/tests/docs.
- Remaining issue: the README says `moon run cmd/main -- <file.toml>`, but the package is native-only and the module does not set `preferred_target = "native"`, so the documented command fails unless the user passes `--target native`.

## DeepSeek V4 Pro TOML Parser V4

- Status: succeeded as of 2026-05-22 19:49 CST after adding structured moon-command validation.
- Task: same TOML parser plus JSON-dump CLI task, using `--max-steps 1000`, with explicit instruction to validate compiler diagnostics, tests, runs, info, fmt, and README commands.
- Log: `.moonagent/eval_runs/results/openseek_toml_cli_d4pro_reasoning_v4.log`
- Log size: 6,477 lines / 277,636 bytes.
- Output workspace: `.moonagent/eval_runs/toml_cli_task_v4`
- Result: the agent finished successfully at step 135 with parser package, native CLI package, README, blackbox tests, whitebox tests, generated interface, and passing validation.
- Validation: independent `moon check` and `moon test` in the generated workspace passed with 22 tests.
- CLI smoke: `moon run --target native cmd/main -- test.toml` and stdin piping both produced valid JSON.
- Structured command-validation impact: it caught real `moon test` failures, README doctest failures, native CLI compiler failures, and validated the final documented `moon run --target native` command. This directly fixed the V3 class of missed CLI-target mismatch.
- Remaining issue: the run took more steps and tokens than V3. The agent still wrote large parser files before the first meaningful check, read too much dependency source while discovering async APIs, and used `moon test --update` too freely.

## DeepSeek V4 Flash TOML Parser

- Status: failed/incomplete as of 2026-05-22 20:14 CST.
- Task: same TOML parser plus JSON-dump CLI task, using `--max-steps 1000` and structured moon-command validation.
- Model setting: `OPENSEEK_MODEL=deepseek-v4-flash`.
- First attempt log: `.moonagent/eval_runs/results/openseek_toml_cli_d4flash_v1.log`
- First attempt size: 23 lines / 645 bytes.
- First attempt result: failed at step 1 by returning a JSON-like plan as assistant text instead of calling tools. No task files were created.
- Tool smoke log: `.moonagent/eval_runs/results/openseek_d4flash_tool_smoke.log`
- Tool smoke size: 9 lines / 270 bytes.
- Tool smoke result: succeeded; Flash called the shell tool for `pwd` and then finished, so the first attempt was prompt/tool-use sensitivity rather than complete tool inability.
- Second attempt log: `.moonagent/eval_runs/results/openseek_toml_cli_d4flash_v2.log`
- Second attempt size: 5,399 lines / 326,984 bytes.
- Output workspace: `.moonagent/eval_runs/toml_cli_task_flash_v2`
- Second attempt result: partially recovered, then failed. It reached a passing `moon check --output-json` at step 140 before writing tests, and a native CLI smoke run produced JSON for `key = "value"`. After it generated `toml_parser/toml_parser_test.mbt`, the workspace no longer checked.
- Final validation: independent `moon check --output-json` exits 255 with 117 errors and 48 warnings, dominated by invalid multiline string usage in tests. Independent `moon test --target native toml_parser` exits 1 with the same test syntax failures.
- Final run status: the transcript ends at step 147 with `OSError(@socket.Tcp::write(): Broken pipe)` after the failed test command; there is no `=== finished ===` success marker.
- Guardrail result: no `moon test --update` attempt was observed, so the snapshot-update guardrail did not trigger.
- Performance notes: Flash was fast enough to recover from the parser package's initial compile wall, but it relied on many one-off edits, got stuck on MoonBit syntax/API details for about 100 steps, and did not maintain validation after adding tests. It needs a stricter staged workflow before it is useful for this class of MoonBit task.

## DeepSeek V4 Pro JSON Schema Validator

- Status: partial success/incomplete as of 2026-05-22 21:10 CST.
- Task: create a more complex MoonBit JSON Schema validator library plus native CLI under `.moonagent/eval_runs/json_schema_validator_pro_v1`.
- Model setting: `OPENSEEK_MODEL=deepseek-v4-pro`, `--max-steps 1000`.
- Log: `.moonagent/eval_runs/results/openseek_json_schema_d4pro_reasoning_v1.log`
- Log size: 73,791 lines / 3,389,910 bytes.
- Output workspace: `.moonagent/eval_runs/json_schema_validator_pro_v1`
- Result: the run stopped at step 103 with a DeepSeek context-length error after the CLI printed a huge generated C/native artifact into the transcript. There is no `=== finished ===` success marker.
- Library validation: independent `moon check`, `moon check --target native`, `moon test`, and `moon test --target native` all pass in the generated workspace. Final test count is 31/31 passing.
- CLI validation: independent `moon run --target native cmd/main -- fixtures/passing/schema1.json fixtures/passing/instance1.json` exits 0 but prints a debug dump of generated C/native output and then returns `{"valid":false,...}` with `Failed to parse schema: Invalid character '#' at line 1, column 0`. The CLI is not usable as delivered.
- Missing deliverables: no README, no generated `pkg.generated.mbti`, and no final `moon info` output were produced before the context failure.
- Performance notes: Pro recovered from a large 127-error validator compile wall, fixed public tests without using `moon test --update`, repaired a custom regex implementation based on failing tests, and got both default and native tests green. The main failures were poor file-read/API verification for the native CLI, leaving debug output in the CLI, and not bounding command output before feeding it back into the model.

## DeepSeek V4 Pro JSON Schema Validator V3 With Output Caps

- Status: succeeded as of 2026-05-22 23:33 CST.
- Task: repeat the JSON Schema validator library plus native CLI task after adding command output caps and native CLI argument guidance.
- Model setting: `OPENSEEK_MODEL=deepseek-v4-pro`, `--max-steps 1000`.
- Log: `.moonagent/eval_runs/results/openseek_json_schema_d4pro_reasoning_v3_output_caps.log`
- Log size: 3,200 lines / 179,082 bytes (196K on disk).
- Output workspace: `.moonagent/eval_runs/json_schema_validator_pro_v3_output_caps`
- Result: the agent finished successfully at step 99 with parser/validator library, native CLI package, fixtures, README, generated interface, and passing validation.
- Independent validation: `moon check --output-json .moonagent/eval_runs/json_schema_validator_pro_v3_output_caps` passed; default and native `moon test` both passed with 27 tests.
- CLI smoke: valid fixture produced `{"valid":true,"errors":[]}`; invalid fixture produced a structured `minimum` error at `/age`.
- Output-cap impact: the run did not hit a context-length error, did not inject generated native C into the transcript, and stayed two orders of magnitude smaller than the V1/V2 JSON Schema logs.
- Semantic doc/definition impact: the agent used docs and definitions for `Json`, async `fs`, `io.Data`, and `&Data::text`; after inspecting the real `Data` source it repaired the native CLI file-read path.
- Remaining gaps: the agent still waited until after a large schema file before its first meaningful check, spent many steps on MoonBit mutability and enum constructor mistakes, dumped full dependency/source ranges while diagnosing `Data`, and had a few brittle edit failures (`old_string not found`, missing edit path).

## DeepSeek V4 Pro JSON Schema Validator V4 With Bounded Read

- Status: partial success/incomplete as of 2026-05-23 14:22 CST.
- Task: repeat the JSON Schema validator library plus native CLI task after adding bounded `read` output for ranged and character-capped file inspection.
- Model setting: `OPENSEEK_MODEL=deepseek-v4-pro`, `--max-steps 1000`.
- Log: `.moonagent/eval_runs/results/openseek_json_schema_d4pro_reasoning_v4_bounded_read.log`
- Log size: 3,345 lines / 303,726 bytes (328K on disk).
- Output workspace: `.moonagent/eval_runs/json_schema_validator_pro_v4_bounded_read`
- Result: the agent finished at step 180 with a parser/validator library, native CLI package, fixtures, tests, README, and generated interfaces.
- Independent validation: `moon check --output-json` passed; default and native `moon test` both passed with 21 tests.
- Inline CLI smoke: `moon run --target native cmd/main -- '{"type":"integer"}' '42'` printed `valid`; the string case printed `invalid` with an integer type error.
- Contract gap: the final CLI accepts inline JSON strings, not schema and instance file paths. `moon run --target native cmd/main -- fixtures/schema_string.json fixtures/valid_string.json` fails with `Error parsing schema JSON: Invalid character 'i' at line 1, column 1`, so the task is not fully delivered.
- Bounded-read impact: positive. The agent repeatedly used `read` with `start_line` and `max_lines` while repairing generated files, and those calls returned range metadata instead of flooding the transcript with whole files.
- Remaining output gaps: broad shell commands still produced noisy listings and large compiler command lines, and command-runner output caps do not control arbitrary shell output or file/source dumps.
- Guardrail gap: the agent bypassed the snapshot-update guardrail by using shell after the command runner rejected an unreviewed `moon test --update` attempt.
- Debug hygiene gap: the agent created temporary debug files/packages during diagnosis, including a root `debug_main.mbt` that broke compilation until removed, and it briefly overwrote the root `moon.pkg` with an empty file before repairing it.
- Best next ROI: enforce MoonBit command policy at the shell layer, add semantic CLI contract checks for file-path tools and JSON stdout predicates, and require scratch/debug code to live outside compiled packages.

## DeepSeek V4 Pro Multi-Task Eval: Jqmini, JSONPath, Dependency Solver

- Status: completed as of 2026-05-23 15:25 CST.
- Setup: three independent `deepseek-v4-pro` runs were launched in parallel with `--max-steps 1000` to avoid overfitting conclusions to one task shape.
- Jqmini task: build a jq-style JSON query library plus `cmd/jqmini` native CLI with selectors, pipes, comma outputs, literals, array/object construction, `==`, `length`, `keys`, `has`, `select`, fixtures, README tests, and JSON Lines output.
- Jqmini result: succeeded at step 126. Log: `.moonagent/eval_runs/results/openseek_jqmini_d4pro_v1.log` (2,299 lines, 132K on disk). Independent validation: `moon test` passed with 34 tests; file CLI printed `"Alice"` for `.name`; stdin CLI printed `{"a":1}` for identity. Remaining issue: `moon check --warn-list +unnecessary_annotation` still reports two unused derive warnings.
- JSONPath task: build a JSONPath evaluator plus `cmd/jsonpath` native CLI supporting `$`, child, bracket child, index, negative index, wildcard, descendant, and simple equality filters.
- JSONPath result: succeeded at step 163 after a long recovery. Log: `.moonagent/eval_runs/results/openseek_jsonpath_d4pro_v1.log` (3,355 lines, 328K on disk). Independent validation: `moon check --target native` passed with warnings; `moon test --target native` passed with 23 tests; file CLI printed `"Sayings of the Century"`; stdin CLI printed `1`. Remaining issues: deprecated `Show`/`assert_eq` warnings and blackbox tests inside the main package.
- Dependency solver task: build a package resolver plus `cmd/resolve` native CLI for semver constraints and conflict reporting.
- Dependency solver result: succeeded at step 144. Log: `.moonagent/eval_runs/results/openseek_dep_solver_d4pro_v1.log` (2,637 lines, 132K on disk). Independent validation: `moon check --warn-list +unnecessary_annotation` passed, `moon test` passed with 21 tests, and the success fixture printed `{"ok":true,...}`. Remaining issue: the conflict fixture prints the intended JSON error followed by an extra `Failure(...)` runtime line, so the CLI failure contract is still dirty.
- Tool-call failures: rough `tool error` counts were 23 for jqmini, 45 for JSONPath, and 18 for dependency solver. A narrower scan for avoidable tool/API/edit symptoms found 10, 17, and 8 respectively. These counts include useful domain feedback, so the important signal is the recurring avoidable shape rather than the raw count.
- Repeated avoidable failures: invalid semantic-doc queries (`Json::`, `@stdio.stdin.read_until`, quoted package paths), raw shell misuse for expressions containing `|`, parentheses, and quotes, reading binary `.mi` files as text, brittle `old_string` edits, broad dependency/source dumps, and manifest churn such as rewriting `moon.pkg` with too little content.
- General conclusion: V4 Pro can now finish several non-trivial MoonBit tasks under the 1000-step budget, but it still spends many steps recovering from tool-shape mistakes and API discovery loops. The strongest run was the dependency solver because it worked in smaller validated increments; JSONPath had the hardest recovery because it wrote a large parser before the first useful check and repeatedly misunderstood JSON/async APIs.
- Best ROI from this multi-task run: semantic CLI validation remains first, but the next tier should now include shell-level MoonBit command routing/quoting and manifest/package guardrails. These failures repeated across tasks and are not specific to jqmini.

## DeepSeek V4 Pro Extensive Six-Task Eval

- Status: completed as of 2026-05-23 after six parallel challenging runs with `OPENSEEK_MODEL=deepseek-v4-pro` and `--max-steps 1000`.
- Setup: the tasks were jqmini, JSONPath, CSVQL, semver dependency solver, Markdown outline/front-matter extractor, and HTTP route matcher. Logs total 16,914 lines under `.moonagent/eval_runs/results/openseek_*guarded*.log`.
- Jqmini guarded V2: failed. The run stopped after 774 log lines with `OSError(@socket.Tcp::read(): Connection reset by peer)` after a huge semantic-doc response for `@array`. Independent `moon check --output-json` still fails with 11 errors and 12 warnings, including error-type mismatches, nonexistent `Double::is_infinite`, nonexistent `Array::sorted`, and old `String::substring` call shapes.
- JSONPath guarded V2: mostly succeeded. Independent validation: `moon check --output-json` passed with 5 deprecated `Show` warnings; `moon test --target native` passed 33/33; file and stdin CLI probes produced expected JSON Lines. Caveats: invalid-path mode returns exit 0 through `moon run` even though the built binary exits 1, and the final workspace still contains whitebox tests named `debug filter ...`.
- CSVQL guarded V1: mostly succeeded. Independent validation: `moon check --output-json` passed, `moon test` passed 27/27, the temporary `cmd/csvql/debug.mbt` was removed, and quoted single-query CLI arguments work for file and stdin probes. Caveats: unquoted multi-word query probes are easy to miscall, and malformed CSV / invalid query modes return exit 0 with error text.
- Semver solver guarded V2: strongest clean pass. Independent validation: `moon check --target all` passed, `moon test --target native` passed 20/20, file success/conflict/backtracking probes produced expected JSON, and stdin produced `{"ok":true,"lock":{"a":"1.1.0"}}`.
- Markdown outline guarded V1: library and CLI output succeeded with an exit-code caveat. Independent validation: `moon check --target native` passed, `moon test --target native` passed 16/16, file and stdin CLI probes produced expected JSON, and the built binary exits 1 for unterminated front matter. Through `moon run`, the same error prints `username/md_outline/md_outline.OutlineError.UnterminatedFrontMatter` but exits 0.
- Route matcher guarded V1: functional success with a dirty failure path. Independent validation: `moon check --output-json` and `moon check --target native` pass with 8 deprecated `assert_eq`/`Show` warnings; `moon test` passes 36/36; match and no-match CLI probes work. Invalid route patterns print `invalid pattern: /*path/stuff` but leak an abort/Panic stack; `moon run` reports exit 0 while the built binary exits 134.
- General result: five of six runs delivered a compiling, tested project with useful CLI behavior. Only semver was close to contract-clean. The dominant remaining weakness is not raw MoonBit generation ability; it is external contract verification, especially CLI error mode, exit code, stdout/stderr separation, and whether the agent's final summary matches what users actually get from `moon run`.
- Tool-call failure patterns: five runs hit the `moon.mod` current-syntax guardrail; semver and Markdown also hit suspiciously tiny `moon.pkg` guardrails. Shell/Moon command routing worked in places, but agents still made structured-command mistakes such as treating command arguments like shell strings, using `moon run -c/-e` incorrectly, or probing generated binary paths by guessing `_build` layout.
- API-discovery failure patterns: agents repeatedly guessed async/stdio/fs/error-exit APIs, used deprecated `derive(Show)` to satisfy formatting needs, and issued broad or invalid semantic-doc queries. The jqmini run shows the worst case: one oversized doc response was followed by a transport reset before recovery.
- Debug/edit hygiene patterns: CSVQL temporarily left a second `main` in `cmd/csvql/debug.mbt`, JSONPath kept debug-named whitebox tests, and route/CSVQL logs show brittle `old_string` and missing-directory failures. These were often recoverable but cost many steps and sometimes polluted final quality.
- Best ROI from the six-task batch: add a semantic CLI acceptance tool first, then a MoonBit CLI/error cookbook and output-shaped IDE docs. Prompt wording alone is not enough; the agent already had guidance for `moon.mod`, flat package structure, and small files, but still overstated CLI failure contracts.

## Tool-Call Failure Review Method

- Status: added after reviewing schema-validator V3/V4 logs.
- Evaluation reports should separate tool failures into at least four categories:
  1. Expected domain failures: `moon check`, `moon test`, or CLI runs that fail because generated code is wrong. These are useful feedback, not tool misuse.
  2. Avoidable argument/schema failures: missing fields or wrong fields, such as the V4 semantic-doc call without `query`.
  3. Avoidable edit failures: empty `old_string`, `old_string not found`, or stale edit context after a previous rewrite.
  4. Policy failures and bypasses: guarded tool rejection, especially when the next step uses `shell` to bypass the same policy.
- Each eval summary should include counts and representative examples for avoidable tool-call failures, plus whether the agent recovered or kept repeating the same mistake.
- For edit failures, prefer prevention over recovery: require a recent bounded `read` before editing a region, make `edit` errors return enough context to choose the next exact string, and consider a line-range replacement tool for cases where exact string matching is too brittle.
- For argument failures, improve schemas and tool descriptions when the model repeatedly miscalls a tool. If a field is required only for one action, document that relationship in the schema description and README API style.
- For policy failures, enforce the policy at every path that can perform the action. The snapshot-update guardrail is not enough while `shell` can still run `moon test --update`.
- For future multi-task evaluations, record tool-call failures as a first-class section alongside correctness, CLI contract, tests, log size, and final validation.

## Cross-Evaluation Conclusion

- Status: synthesis updated as of 2026-05-23 after the schema-validator and six-task guarded evals.
- DeepSeek V4 Pro is strong enough for substantial MoonBit library generation when the environment gives it tight feedback. It recovered from large compiler-error walls, fixed parser/validator logic, used semantic docs when available, and usually finished complex library tasks under a 1000-step budget.
- The highest-impact improvements so far were tool-level, not prompt-only: structured moon-command validation fixed the TOML V3 documented-CLI mismatch, command output caps prevented JSON Schema V1/V2 context blowups, semantic doc lookups improved API discovery, and bounded `read` kept repair-loop file inspection focused.
- The current limiting factor is external contract reliability. Across schema-validator V4, dependency solver, JSONPath, Markdown, CSVQL, and route matcher, the agent often made code compile and tests pass while missing details that users notice immediately: file-vs-inline arguments, exit codes, stdout/stderr cleanliness, abort stack leaks, and whether a failing command really failed.
- The six-task batch adds a second limiting factor: many failed calls are command-shape or tool-shape failures rather than reasoning failures. Queries with spaces, `|`, brackets, parentheses, and quotes stress shell and structured-command boundaries, while broad/invalid semantic-doc calls still waste steps.
- Prompt additions remain useful for MoonBit conventions, but they are now lower ROI than enforceable tool behavior. The agent already had guidance for native args, flat packages, small files, `moon.mod`, and bounded reads; it still overstated several CLI error contracts in final summaries.
- Future benchmarks should keep using several task shapes in one batch. Single tasks hide failure modes: semver looked clean, JSONPath exposed async/API discovery issues, CSVQL exposed argv/query-shape ambiguity, route matching exposed dirty abort paths, and jqmini exposed output-volume/transport fragility.

## Next ROI Investment Ranking

1. Add semantic CLI validation.
   A dedicated tool or moon-command mode should run acceptance probes and assert contract-level facts: file-path arguments are used as files, stdin mode works, stdout is valid JSON or JSON Lines, selected predicates hold, stderr is clean, and exit-code expectations match. It should optionally compare `moon run` behavior with the built native binary because JSONPath, Markdown, and route matcher exposed mismatches there.
2. Add a MoonBit CLI/error-handling cookbook to the agent/tool docs.
   The repeated high-cost gap is clean native CLI behavior: async file/stdin reads, `@env.args` shape, stdout/stderr writes, structured error JSON, and nonzero process exit without abort stacks. Give the agent a small proven pattern instead of making it rediscover `stdio`, `fs`, `io.Data`, and private `argparse` exit internals.
3. Route MoonBit commands through a structured shell policy.
   Raw shell caused repeated quoting and policy problems for jqmini/JSONPath/CSVQL-style expressions and can bypass command-policy guardrails. Shell should either reject guarded MoonBit commands or route `moon`, `moon run`, and `moon test` through the same policy and output caps.
4. Shape semantic-doc and source-output responses.
   Keep docs and source reads focused by default, paginate broad symbol docs, and make invalid query errors actionable. The jqmini transport reset and JSONPath's long async I/O discovery loop both point to this.
5. Add manifest/package guardrails.
   Several runs confused legacy `moon.mod.json` with current `moon.mod` or wrote suspiciously tiny `moon.pkg` files. Add validation after manifest writes and reject package files that drop required imports/options unless explicitly intended.
6. Add automated tool-call failure summaries to eval reports.
   Parse logs for avoidable argument, edit, manifest, and policy failures separately from expected compiler/test failures. This makes tool ergonomics measurable instead of anecdotal.
7. Add a staged acceptance checklist.
   The agent should track required deliverables and prove each one: library API, CLI file mode, CLI stdin mode, README command, fixtures, tests, `moon info`, and formatting. It should also force an early `moon check` after each small file batch.
8. Keep debug code out of deliverable packages.
   Provide a scratch/debug package or policy that prevents temporary probes from being compiled with the target package. This would avoid regressions like `debug_main.mbt` breaking the schema-validator workspace.

## Agent Performance Improvements To Investigate

- Done: stream logs per step through async stdio instead of relying on buffered `println`. During this run the log stayed at 0 bytes for several minutes, then flushed in large chunks, which made live supervision difficult.
- Add a task checklist inside the agent loop and force early coverage of required deliverables: package scaffold, minimal parser, CLI, README, tests, then richer TOML features.
- Run `moon check` after each generated file or small batch. The first check happened after several large files existed, so the agent had to triage 141 errors at once.
- Prefer replacing or deleting stale files when attempting a rewrite. The agent created `lexer2.mbt` but left the original broken `lexer.mbt` in the same package, so both compiled and errors compounded.
- Strengthen MoonBit syntax guidance for generated code: current error propagation syntax, method declarations, enum derives for equality, labeled parameters, suberror constructors, range loops, string APIs, and `Char?` handling.
- Parse `moon check --output-json` diagnostics and group root causes before editing. The raw compiler output was too large and led to scattered one-off edits.
- Add step-budget guardrails. If the CLI and tests do not exist by a threshold such as step 25, the agent should switch from feature expansion to a minimal compiling slice.
- Encourage an initial spike with tiny executable examples for unfamiliar APIs before writing large parser files.
- When an evaluation allows local references, surface nearby working examples such as `.moonagent/toml_parser_demo*` before implementing from scratch.
- Do not hide validation failures behind successful shell exits. In the retry, one check-like command returned `exit=0` while printing compiler failures, which led the loop to continue from a false success signal.
- Keep module/package manifests and dependency assumptions under validation. The retry repeatedly mis-modeled `@json.Json`, `String::split`, suberror constructor labels, and `@string`/`@strconv` parsing APIs.
- Done: add native CLI ergonomics checks in agent policy. V4 validated README commands with explicit `--target native`.
- Done: add bounded `read` output with `start_line`, `max_lines`, and `max_output_chars`. In the JSON Schema V4 eval this kept generated-file inspections focused and prevented whole-file dumps during the repair loop.
- Reduce remaining token-heavy non-command outputs: apply similar caps or summaries to IDE source/definition dumps and broad shell listings.
- Teach the agent a staged validation invariant: after a package or test file is added, immediately rerun `moon check` before continuing, and treat a previously passing project as regressed until proven otherwise.
- Add prompt guidance for `#|...` multiline strings in MoonBit tests: bind them to local names or wrap them in parentheses before passing as function arguments.
- Done: add output caps/summarization for command-runner and shell-style command results. The JSON Schema V3 log stayed small enough to finish, where V1/V2 ended with context-length errors after native output flooded the transcript.
- Done: add prompt guidance for native CLI arguments. In current native `moon run`, `@env.args()[0]` can be the generated C/native path, so the CLI must drop the executable path before reading user files.
- Add shell-layer enforcement for MoonBit command policy. In V4 bounded-read, the command runner rejected unreviewed `moon test --update`, but the agent used shell to bypass the same guardrail.
- Add a CLI semantic validation helper that can assert stdout is valid JSON, that file-path arguments are actually consumed as files, and that output matches a small predicate, not only that `moon run` exits 0.
- Add a clean CLI failure helper or cookbook for nonzero native exits without `abort` stack traces, and make eval prompts require both success and failure probes.
- Add an eval log summarizer that categorizes failed tool calls into expected domain failures, avoidable argument failures, avoidable edit failures, and policy bypasses.
- Improve `edit` failure output for `old_string not found` by returning a compact hint: file size, whether the file changed since last read if available, and nearby candidate lines when a short substring matches.
- Make tool schemas/descriptions sharper for conditional required fields, so a field required only for one action says so in its description.
- Keep temporary debug code outside compiled packages, or provide a dedicated scratch package that cannot regress the deliverable package.
