# DeepSeek vs Kimi Coding-Agent Benchmark

A head-to-head evaluation of `deepseek-v4-pro` and `kimi-k2.7-code` driving the
**identical** OpenSeek agent loop. Only the model swaps; the agent loop, tools,
system prompt, task text, workspace scaffold, validation probes, step budget,
and concurrency are held constant. What remains is a measurement of model
reasoning, tool use, instruction-following, and MoonBit familiarity.

It reuses the checked-in `eval/prompt_task` suite runner, which drives every
`(model × problem × repeat)` combo through the real `openseek` engine and emits
a combined Markdown/JSON/HTML comparison. Artifacts:

- Task set: `eval/prompt_tasks/*.md`
- Suite config: `eval/prompt_tasks/deepseek_vs_kimi_suite.json`

## Why these tasks

Each task isolates one capability and is scored by **hidden** validation probes
(CLI behavior on inputs the agent never sees), not by grading prose. Every task
fixes a `stdin`-primary CLI contract so probes are deterministic.

| # | Task file | Axis it isolates | What the hidden probes catch |
|---|-----------|------------------|------------------------------|
| A1 | `json_patch_cli.md` | Long-horizon spec fidelity | `~0`/`~1` pointer escaping, array `-` append, failed `test` op → clean error, diff emits valid JSON |
| A2 | `uri_normalizer_cli.md` | Spec / state-machine fidelity (RFC 3986) | dot-segment removal, scheme+host case folding, relative resolution (§5.4.1), malformed input → error |
| B1 | `expr_eval_cli.md` | Algorithmic reasoning | precedence, right-associative `^`, float division, variables, parse error → error |
| B2 | `sat_solver_cli.md` | Algorithmic depth (language-agnostic) | SAT + model line, UNSAT contradiction, comment lines, empty clause → UNSAT |
| C1 | `rpn_repair.md` | Debugging + minimal-diff discipline | operand order, div-by-zero / underflow / leftover / unknown-token all → clean error (no panic) |
| D1 | `dir_stats_cli.md` | Ecosystem fluency (`moonbitlang/async`, native) | exact concurrent byte/line counts, empty file, unreadable path → error |
| E1 | `utf8_decode_cli.md` | Byte-level robustness / defensive parsing | 4-byte decode, ASCII, overlong / truncated / surrogate all rejected |

C1 is a genuine repair task: the prompt ships a small, verified-buggy `eval`
(reversed operand order, no zero check, no underflow/leftover/unknown-token
handling) and asks the agent to fix it behind a fixed public signature. Its
hidden probes go beyond the two visible failing tests, so an agent that only
games the visible tests still fails.

E1 replaces the originally-considered Git loose-object decoder: a real loose
object needs a zlib-compressed **binary** fixture, which the text-only probe
harness (`write_content` is a string) cannot supply cleanly. A hex-in UTF-8
decoder exercises the same byte-level / defensive axis with pure-text fixtures.

## Fairness controls

- **Same everything but the model.** The suite runner guarantees identical task
  text, probes, `max_steps`, and concurrency across models; do not pass a
  model-specific `--system-prompt-file`.
- **Both models reason at full effort.** `deepseek-v4-pro` runs at the default
  `--thinking max`. `kimi-k2.7-code` ignores the thinking parameter entirely
  because its "Preserved Thinking" is always on (see `deepseek/json_encode.mbt`).
  So the default already pits full-strength reasoning against full-strength
  reasoning.
- **Repeats, not a single bit.** Agent runs are nondeterministic; the suite runs
  `runs_per_combo = 3` and reports a success *rate* per `(model, problem)`.
- **`min_successes = 0`.** The run is a measurement, not a pass/fail gate, so it
  never exits non-zero on a weak combo — every trial's data is retained.

## Metrics

The analyzer records, per trial: overall success, agent `steps`, `tool_errors`,
`finished`, per-probe validation pass/fail, `parse_errors`, and a set of
MoonBit-idiom counters. The suite report surfaces, per `(model, problem)`:
Successes, Avg Steps, Avg Tool Errors, Finished, and Validation.

## Running it

Both providers authenticate from the environment. This is enabled by a small
harness change: an empty `--api-key` means "inherit each model's provider key
from the environment" (`DEEPSEEK` for `deepseek-*`, `KIMI` for `kimi-*`) — the
only way one suite can span providers, since a single shared key cannot
authenticate both. `run_suite` validates every listed provider up front.

```bash
export DEEPSEEK=<deepseek key>
export KIMI=<kimi key>

# Build a prebuilt engine once so trials exec it directly instead of
# recompiling cmd/openseek per trial.
moon build --target native cmd/openseek
ENGINE="$PWD/_build/native/debug/build/bobzhang/openseek/cmd/openseek/openseek.exe"

# Run the full suite (7 problems × 2 models × 3 repeats). No --api-key: keys are
# inherited from the environment per provider.
moon run --target native eval/prompt_task/cmd/main -- \
  --suite-file eval/prompt_tasks/deepseek_vs_kimi_suite.json \
  --engine "$ENGINE" \
  --out .moonagent/eval_runs/deepseek_vs_kimi \
  --repo-root .

# Re-generate the comparison report from a completed run without re-running any
# agents.
moon run --target native eval/prompt_task/cmd/main -- \
  --analyze-only \
  --out .moonagent/eval_runs/deepseek_vs_kimi
```

The suite writes `report.md`, `report.json`, and `report.html` under `--out`,
plus per-combo run manifests, workspaces, raw process logs, and recorded session
`openseek_session-<id>.jsonl` transcripts for deeper inspection.
