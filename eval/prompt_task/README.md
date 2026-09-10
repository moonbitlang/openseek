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

For a longer, real implementation comparison, `toml_read_ab.py` runs that
TOML subset library-and-CLI task from a fresh project three times per arm. Pass
frozen binaries and their matching resources, as above:

```bash
python3 eval/prompt_task/toml_read_ab.py \
  --baseline /absolute/path/to/main/openseek.exe \
  --baseline-share /absolute/path/to/main/share \
  --candidate /absolute/path/to/pr/openseek.exe \
  --candidate-share /absolute/path/to/pr/share \
  --out .moonagent/eval_runs/toml_read_ab
```

Defaults are `deepseek-v4-flash`, high thinking, 160 steps and 1800 seconds per
trial, in AB/BA/AB order. Both arms get the same task and explicit requirements
for a MoonBit implementation, clean nonzero CLI errors, and no delegation.
Each workspace begins with only a committed `.gitignore`; global skills and MCP
are disabled, while each binary retains its own default prompt and tools.
The runner terminates each command's and agent's process group on every exit,
including success, so abandoned descendants cannot consume CPU in later trials.
This cleanup was added after the recorded September cohort exposed the leak;
the historical report preserves that limitation and links its original runner.

Verify descendant cleanup without a model call:

```bash
python3 -B -m unittest discover -s eval/prompt_task -p 'toml_read_ab_cleanup_test.py'
```

Before model calls, `--prepare-only` verifies Git isolation and cross-checks 29
valid documents and 26 invalid documents against Python's `tomllib`. A reference
adapter must pass all 114 CLI checks and an empty parser must fail them. After
each run, a separate copy of the submission is checked, tested and built, then
its actual native CLI is tested in file and stdin modes against exact expected
JSON values, clean errors, usage handling and deterministic output. The agent
receives none of this feedback. The original workspace must remain unchanged.
A submission without a root `moon.mod` is rejected before running Moon, so
validation never walks into an ancestor project. Modern manifests and actual
black-box tests are also required. This tests the
documented subset, not complete TOML 1.0 compliance; library API design and the
ban on reusing another parser also need source inspection in the final report.

The primary metric is cumulative input tokens, including cached input. The
reporter adds the parent's usage events and each unique `subrun_finished`
summary, so built-in reviews count toward total input, output and steps. Raw
runner `usage` and `results.json` remain parent-only; use the exported report's
`total_model_usage` and `summary` for the end-to-end comparison. Child summaries
do not expose cache hits or misses, so complete cache totals are unavailable
when children run. Missing child completion summaries also leave total usage
unavailable rather than assuming zero. This measures reported tokens, not billing.

Tool calls, independent acceptance results and latency are reported separately.
The original strict `passed` verdict also requires no delegation. The reporter
preserves it while separately recording artifact acceptance and normal delivery;
an unsolicited review is a protocol deviation even if the parser passes.
All fixed trials, including failures, remain in the report.
`--limit` can pause after a fixed number of trials; rerunning resumes completed
results, but an interrupted trial is retained for inspection. The plan hashes
the task, evaluator dependencies, binaries and resources to reject mixed runs.

`--api-url` can supply a common evaluation endpoint. OpenSeek disables
`web_search` for custom endpoints, so record that toolset change for both arms.
For the September run, local DNS returned unreachable DeepSeek addresses. The
optional `deepseek_eval_relay.py` binds only to loopback, connects to a separately
resolved address, verifies TLS for `api.deepseek.com`, and forwards request bodies
unchanged, including native chunked uploads and streamed responses. It logs only
request hashes, byte counts, status and timing. It does not log credentials or
payloads. Keep any interrupted attempt separate rather than replacing its trials.

After all trials finish, reconcile and export their results without rerunning
model calls or changing scores:

```bash
python3 eval/prompt_task/toml_read_ab_report.py \
  .moonagent/eval_runs/toml_read_ab \
  eval/prompt_reports/toml_read_ab.json
```

The September source review also motivated a separate, **post-hoc** library
probe. `toml_read_ab_library_probe.py <run-directory>` refuses to run until all
planned model trials have ended. It makes fresh copies and checks the numeric
payload of both `7` and `-7`, which can disagree with a correct-looking JSON
serialization. It adapts only the public `parse(String)` / `parse(StringView)` /
`parse_string(String)` entry point, locating its unique generated package
interface; inspect unsupported or ambiguous APIs before adapting them. It saves
`library-probe.json` without changing the frozen CLI
scores or original source. Probe output is supplementary evidence, not a
replacement success metric, and an existing probe directory is not overwritten.

See the [completed TOML comparison](../prompt_reports/toml_read_ab_20260910.md)
for all six real runs, full parent-and-review token accounting, the supplementary
API probes, and the delegation/process-isolation limitations of that observation.

The MoonBit suite runner below also defaults to
`eval/prompt_tasks/toml_parser_cli.md`. That runner replaces
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
