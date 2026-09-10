# Prompt Task Eval

This harness runs a MoonBit prompt task through the real OpenSeek agent with
isolated workspaces, per-trial raw logs, durable `openseek_session-<id>.jsonl` session files,
and bounded parallelism. Reporting is a separate analyzer pass, so reports can
be regenerated without rerunning model/API trials.

For the standalone `read` versus builtin `@builtin/read.mbtx` comparison, use
`read_workflow_ab.py`. It runs three paired task types (batch extraction, focused
ranges and filesystem edge cases, and a three-file MoonBit repair), three times
per arm by default, sequentially with alternating AB/BA order. Each fixture has
its own committed Git repository and isolated Git configuration: `git status`
and `git diff` cannot walk into the enclosing project. The preflight checks
this boundary before model calls:

```bash
python3 eval/prompt_task/read_workflow_ab.py \
  --baseline /absolute/path/to/old/openseek.exe \
  --baseline-share /absolute/path/to/old/share \
  --candidate /absolute/path/to/new/openseek.exe \
  --candidate-share /absolute/path/to/new/share \
  --out .moonagent/eval_runs/read_workflow_ab
```

Credentials are inherited from the provider's normal environment variables and
are never written into the command or manifest. The default is
`deepseek-v4-flash`, high thinking, 24 steps, and a 240-second limit per trial.
`--prepare-only` checks the repair fixture and independent oracle without a model
call. `--limit 2` runs the first pair; rerunning the same command without the limit
resumes the rest. Completed trials are never rerun; an interrupted trial without
a result requires inspection. The configuration, binaries, resources and evaluator
are hashed to prevent silently mixing variants during a resumed experiment.

The output retains source fixtures, prompts, expected answers, raw events, durable
sessions, decoded calls, individual results and `results.json`. Read-task scoring
requires an exact JSON object (an optional surrounding Markdown fence is accepted;
additional prose fails). Repair scoring uses an independent oracle with pristine
manifests and tests. Both also check protected files and normal completion. See
[the September 2026 pilot](../prompt_reports/read_workflow_ab_20260910.md) for
the historical results and their Git-isolation correction. The
[token follow-up](../prompt_reports/read_workflow_tokens_20260910.md) compares
the original and shortened builtin prompts using independently committed Git
fixtures. Both reports separately state the more lenient content-correctness metric.

The default task is `eval/prompt_tasks/toml_parser_cli.md`. The runner replaces
`{{WORKSPACE}}` in the task template with each trial workspace path and starts
the agent with `openseek --dir <trial-workspace>` and an explicit per-trial
session id. Each session log stays under the trial workspace's `.openseek`
directory. The analyzer loads the run manifest, recursively resolves the
workspace-local session logs, evaluates each loaded agent session independently,
then combines those eval results into a run-level report. Workspace validation
for the TOML task checks:

- `moon check --target native`
- `moon test --target native`
- file-input `cmd/tomljson` JSON probe
- stdin `cmd/tomljson` JSON probe
- duplicate-key invalid-input probe with no panic/debug stack

Run five Flash TOML trials concurrently:

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

Analyze the finished run later:

```bash
moon run --target native eval/prompt_task/cmd/main -- \
  --analyze-only \
  --out .moonagent/eval_runs/toml_flash_current_5x
```

Run a multi-problem suite:

```bash
moon run --target native eval/prompt_task/cmd/main -- \
  --api-key "$DEEPSEEK" \
  --suite-file .repos/openseek-eval-experiments/suites/moonbit_cli_suite_v1/suite.json \
  --out .repos/openseek-eval-experiments/runs/moonbit_cli_suite_v1_100x \
  --repo-root .
```

Suite mode flattens every model/problem/repeat into one global queue controlled
by `--suite-file`'s `concurrency`. It writes one `suite_manifest.json` and a
normal `run_manifest.json` under each model/problem combo directory. The same
analyze-only command works for suites; it detects `suite_manifest.json`,
regenerates each combo report, then writes the combined suite Markdown, JSON,
and HTML report.

Run an A/B comparison by using different output directories and prompt labels:

```bash
moon run --target native eval/prompt_task/cmd/main -- \
  --api-key "$DEEPSEEK" \
  --model deepseek-v4-flash \
  --runs 5 \
  --concurrency 5 \
  --min-successes 5 \
  --max-steps 160 \
  --prompt-label flash-candidate \
  --system-prompt-file prompt/default_prompt.mbt.md \
  --out .moonagent/eval_runs/toml_flash_candidate_5x
```

The runner writes `run_manifest.json`, `workspaces/`, and `logs/`. Agent
session logs remain in each workspace at `.openseek/sessions/<session>/`.
The analyzer writes aggregate `report.md`, `report.json`, and `report.html`
files under the run output directory. It also writes one independently
renderable eval result under `eval_results/<trial>/` with its own markdown,
JSON, and HTML report. The reports record success rate, typed-session metrics,
validation pass/fail, prompt-sensitive counters, and paths to each raw log.
