# Examples-over-Guidelines Pilot (NEGATIVE result)

Date: 2026-06-12 · Branch: `exp/prompt-matrix` · Model: deepseek-v4-flash ·
Task: `eval/prompt_tasks/toml_parser_cli.md` · 5 trials/arm · concurrency 3 ·
max-steps 160 · same engine binary as the prompt-matrix experiment.

## Hypothesis and design

Compiler-verified worked examples teach flash more per token than imperative
guidelines. Full pre-registered design, metrics, and thresholds in
[PLAN.md](PLAN.md) (reviewed by Codex before execution; all 4 demos verified
with `moon check --deny-warn` plus behavioral runs before entering any
prompt). Arms: A = shipped flash prompt (17,050 B, sha 12f9e1cd…); B =
guideline bodies REPLACED by 4 verified demos (15,997 B, sha 2a35497c…); C =
shipped prompt + demos appended (20,376 B, sha 304c5b7c…). Variant files are
archived alongside this README.

## Results

| arm | passes | finished | targeted errors | untargeted | targeted/compile-invocation | unique targeted/trial |
| --- | --- | --- | --- | --- | --- | --- |
| flash-guidelines | 3/5 | 5/5 | 329 | 442 | 1.82 | 9.8 |
| flash-demos | 3/5 | 3/5 | 237 | 177 | 1.85 | 8 |
| flash-demos-plus | 2/5 | 2/5 | 389 | 290 | 1.73 | 9.4 |

Pre-registered success required >=40% drop in targeted errors per compiler
invocation, untargeted up <=15%, pass rate not below baseline. **B: +1.6%
(flat). C: -5%. Both demo arms regressed finish rate (5/5 -> 3/5 -> 2/5).
Negative on the primary metric; no prompt change ships, and the holdout +
confirmation stages do not run.**

## Reading

- Raw error totals favored B (-28% targeted, -60% untargeted) but normalize
  away: B simply compiled less often, in longer, less decisive sessions.
- The matrix's size lesson reappeared: C (largest prompt) finished only 2/5.
- Baseline drift was real: this fresh A scored 3/5 where the same-everything
  morning arm scored 2/5 — fresh interleaved baselines (a Codex plan-review
  demand) were necessary; reusing the morning arm would have manufactured a
  fake win for B.
- One durable side-find: `StringView::to_string()` is deprecated in favor of
  `.to_owned()` — discovered because demo verification runs warning-strict.
  The shipped prompts already use the live form; external guides may not.

## Session index

Browse with: `moon run cmd/viz_server -- --session-root eval/results/2026-06-12-examples-pilot`

| session | arm | trial | verdict | terminal | targeted errors | compile invocations |
| --- | --- | --- | --- | --- | --- | --- |
| [cli-20260612-052851-115-168566ae380c7](sessions/cli-20260612-052851-115-168566ae380c7/events.jsonl) | flash-guidelines | 1 | fail | finished | 20 | 28 |
| [cli-20260612-052851-115-168556ae380c7](sessions/cli-20260612-052851-115-168556ae380c7/events.jsonl) | flash-guidelines | 2 | fail | finished | 30 | 29 |
| [cli-20260612-052851-115-168546ae380c7](sessions/cli-20260612-052851-115-168546ae380c7/events.jsonl) | flash-guidelines | 3 | pass | finished | 90 | 30 |
| [cli-20260612-053505-571-201632660f016](sessions/cli-20260612-053505-571-201632660f016/events.jsonl) | flash-guidelines | 4 | pass | finished | 72 | 31 |
| [cli-20260612-053703-746-220079f717b71](sessions/cli-20260612-053703-746-220079f717b71/events.jsonl) | flash-guidelines | 5 | pass | finished | 117 | 58 |
| [cli-20260612-055048-181-29018f5c3b84c](sessions/cli-20260612-055048-181-29018f5c3b84c/events.jsonl) | flash-demos | 1 | pass | finished | 70 | 56 |
| [cli-20260612-055048-181-29019f5c3b84c](sessions/cli-20260612-055048-181-29019f5c3b84c/events.jsonl) | flash-demos | 2 | fail | missing | 8 | 6 |
| [cli-20260612-055048-181-29020f5c3b84c](sessions/cli-20260612-055048-181-29020f5c3b84c/events.jsonl) | flash-demos | 3 | fail | missing | 22 | 8 |
| [cli-20260612-055431-045-304463e55a2a8](sessions/cli-20260612-055431-045-304463e55a2a8/events.jsonl) | flash-demos | 4 | pass | finished | 90 | 43 |
| [cli-20260612-055431-312-30459855c6b8e](sessions/cli-20260612-055431-312-30459855c6b8e/events.jsonl) | flash-demos | 5 | pass | finished | 47 | 26 |
| [cli-20260612-060537-144-38906dc7154a3](sessions/cli-20260612-060537-144-38906dc7154a3/events.jsonl) | flash-demos-plus | 1 | fail | failed | 134 | 47 |
| [cli-20260612-060537-144-38908dc7154a3](sessions/cli-20260612-060537-144-38908dc7154a3/events.jsonl) | flash-demos-plus | 2 | pass | finished | 50 | 30 |
| [cli-20260612-060537-144-38909dc7154a3](sessions/cli-20260612-060537-144-38909dc7154a3/events.jsonl) | flash-demos-plus | 3 | fail | failed | 75 | 60 |
| [cli-20260612-061444-602-4625193f90fb2](sessions/cli-20260612-061444-602-4625193f90fb2/events.jsonl) | flash-demos-plus | 4 | pass | finished | 39 | 36 |
| [cli-20260612-061931-934-49897882e0e1c](sessions/cli-20260612-061931-934-49897882e0e1c/events.jsonl) | flash-demos-plus | 5 | fail | failed | 91 | 51 |
