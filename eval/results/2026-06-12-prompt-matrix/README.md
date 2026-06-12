# Prompt-Matrix Experiment: One System Prompt or Two?

Date: 2026-06-12 · Branch: `exp/prompt-matrix` (PR #107 docs/eval branch merged
with PR #108 default session recording) · Task: `eval/prompt_tasks/toml_parser_cli.md`
· 5 trials/arm · concurrency 3 · max-steps 160 · prebuilt engine, prompts
injected via `--system-prompt-file`.

## Question

OpenSeek maintains two system prompts — `prompt/base_prompt.mbt.md` (~16K
tokens, served to deepseek-v4-pro) and `prompt/flash_prompt.mbt.md` (~4.7K
tokens, served to deepseek-v4-flash). The split was never A/B'd. This 2×2
measures every model × prompt combination to decide whether one prompt can
serve both models, and which.

## Results

| arm | passes | mean wall | mean turns | doc misses | completion tokens | cache hit |
| --- | --- | --- | --- | --- | --- | --- |
| flash-x-flashprompt | 2/5 | 458.9s | 105.6 | 40 | 179K | 98.7% |
| flash-x-baseprompt | 0/5 | 347.0s | 68.8 | 16 | 152K | 98.7% |
| pro-x-baseprompt | 3/5 | 777.3s | 120.6 | 24 | 245K | 98.7% |
| pro-x-flashprompt | 4/5 | 802.1s | 120.8 | 42 | 303K | 98.5% |

Passes are the harness's independent workspace validation (`moon check`/`moon
test` + three CLI probes), except flash-x-baseprompt: that arm scored below
`--min-successes`, the runner aborted **before writing any report** (harness
bug, noted in `improvement.md`), and its 0/5 derives from session terminal
states — no trial even called `finish`, so none could have validated.

## Findings

1. **flash collapses on the big prompt (2/5 → 0/5).** Beyond the score: two
   of five trials made essentially no tool calls at all (0–1 doc queries,
   0 reads — the model never engaged the workspace), and one spent 48 doc
   queries against 3 reads, querying in circles. The condensed prompt is
   not an optimization for flash; it is load-bearing.
2. **pro does not need the big prompt (3/5 vs 4/5).** Within n=5 noise, pro
   on the 4.7K condensed prompt was no worse — directionally better — than
   on the 16K guide it ships with, at identical turn counts. The 12K extra
   tokens of guidance showed no measurable benefit on this task.
3. **pro vs flash (the performance read).** Pro trials run ~1.8× flash's
   wall clock (777–802s vs 347–459s) and ~1.5× the completion tokens, but
   pass 7/10 vs flash's 2/10. Flash's only passes came on its tuned prompt;
   on this task tier flash is not economical — its cheaper trials mostly
   buy failed runs. Prefix caching held ~98.7% across all arms, so prompt
   size cost is negligible; attention, not tokens, is what the big prompt
   spends.
4. **Failure modes worth keeping an eye on:** pro misplaced the project
   root once more (built outside the workspace root — the same mode as the
   2026-06-12 docs A/B), and two pro failures were quality misses on the
   duplicate-key probe rather than crashes.

## Recommendation

The burden of proof has flipped: the condensed prompt is the candidate
single source of truth, and the 16K base prompt is the one that now needs a
justifying experiment. Before deleting anything, replicate pro-x-flashprompt
vs pro-x-baseprompt on a second task type (the matrix here is one task,
n=5). If it holds, unify on the condensed prompt and keep the base guide as
documentation rather than prompt text.

## Session index

Every trial's durable session (recorded by default — PR #108) is archived
under `sessions/`. Browse them with the visualizer:

    moon run cmd/viz_server -- --session-root eval/results/2026-06-12-prompt-matrix

| session | arm | trial | verdict | wall | turns | reason / terminal |
| --- | --- | --- | --- | --- | --- | --- |
| [cli-20260612-030601-103-61369d0dfb6d4](sessions/cli-20260612-030601-103-61369d0dfb6d4/events.jsonl) | flash-x-flashprompt | 1 | pass | 433.3s | 73 | ok |
| [cli-20260612-030601-103-61368d0dfb6d4](sessions/cli-20260612-030601-103-61368d0dfb6d4/events.jsonl) | flash-x-flashprompt | 2 | fail | 583.8s | 151 | finish marker missing; moon check: exit 255: Error: [4015]     ╭─[ /private/tmp/ |
| [cli-20260612-030601-103-61367d0dfb6d4](sessions/cli-20260612-030601-103-61367d0dfb6d4/events.jsonl) | flash-x-flashprompt | 3 | pass | 431.8s | 113 | ok |
| [cli-20260612-031314-113-692983789636](sessions/cli-20260612-031314-113-692983789636/events.jsonl) | flash-x-flashprompt | 4 | fail | 693.8s | 160 | finish marker missing |
| [cli-20260612-031315-046-69387a6932912](sessions/cli-20260612-031315-046-69387a6932912/events.jsonl) | flash-x-flashprompt | 5 | fail | 151.9s | 31 | finish marker missing; moon check: exit 255: Warning: [0020]    ╭─[ /private/tmp |
| [cli-20260612-032448-886-7770575a0b0ab](sessions/cli-20260612-032448-886-7770575a0b0ab/events.jsonl) | flash-x-baseprompt | 1 | no-report (missing) | 423.0s | 79 | missing |
| [cli-20260612-032448-886-7770675a0b0ab](sessions/cli-20260612-032448-886-7770675a0b0ab/events.jsonl) | flash-x-baseprompt | 2 | no-report (failed) | 846.5s | 160 | failed |
| [cli-20260612-032448-886-7770775a0b0ab](sessions/cli-20260612-032448-886-7770775a0b0ab/events.jsonl) | flash-x-baseprompt | 3 | no-report (missing) | 442.5s | 96 | missing |
| [cli-20260612-033214-408-81556f507d7e2](sessions/cli-20260612-033214-408-81556f507d7e2/events.jsonl) | flash-x-baseprompt | 4 | no-report (missing) | 10.4s | 4 | missing |
| [cli-20260612-033216-048-81778f3de45de](sessions/cli-20260612-033216-048-81778f3de45de/events.jsonl) | flash-x-baseprompt | 5 | no-report (missing) | 12.7s | 5 | missing |
| [cli-20260612-033856-090-84018ae46c0cd](sessions/cli-20260612-033856-090-84018ae46c0cd/events.jsonl) | pro-x-baseprompt | 1 | pass | 777.4s | 114 | ok |
| [cli-20260612-033856-090-84017ae46c0cd](sessions/cli-20260612-033856-090-84017ae46c0cd/events.jsonl) | pro-x-baseprompt | 2 | pass | 891.2s | 130 | ok |
| [cli-20260612-033856-090-84019ae46c0cd](sessions/cli-20260612-033856-090-84019ae46c0cd/events.jsonl) | pro-x-baseprompt | 3 | fail | 753.6s | 109 | moon check: exit 255: Error: not in a Moon project (no moon.mod, moon.mod.json,  |
| [cli-20260612-035130-251-89180be87f9ec](sessions/cli-20260612-035130-251-89180be87f9ec/events.jsonl) | pro-x-baseprompt | 4 | fail | 777.4s | 123 | duplicate probe: missing duplicate-key message, exit 0: Parse error |
| [cli-20260612-035154-968-8955023ff5600](sessions/cli-20260612-035154-968-8955023ff5600/events.jsonl) | pro-x-baseprompt | 5 | pass | 686.7s | 127 | ok |
| [cli-20260612-040428-623-95263d0ed9f91](sessions/cli-20260612-040428-623-95263d0ed9f91/events.jsonl) | pro-x-flashprompt | 1 | fail | 724.1s | 118 | duplicate probe: missing duplicate-key message, exit 0: Error: invalid TOML inpu |
| [cli-20260612-040428-623-95264d0ed9f91](sessions/cli-20260612-040428-623-95264d0ed9f91/events.jsonl) | pro-x-flashprompt | 2 | pass | 694.4s | 133 | ok |
| [cli-20260612-040428-623-95265d0ed9f91](sessions/cli-20260612-040428-623-95265d0ed9f91/events.jsonl) | pro-x-flashprompt | 3 | pass | 832.7s | 144 | ok |
| [cli-20260612-041603-712-3133cc4ddae](sessions/cli-20260612-041603-712-3133cc4ddae/events.jsonl) | pro-x-flashprompt | 4 | pass | 1046.5s | 110 | ok |
| [cli-20260612-041633-590-363350c09ff3](sessions/cli-20260612-041633-590-363350c09ff3/events.jsonl) | pro-x-flashprompt | 5 | pass | 712.6s | 99 | ok |

`summary.json` holds the full per-trial metrics (tool mix, doc queries,
token usage). `report-<arm>.md` are the harness reports (three arms; see
above for the missing one). Sessions store the typed conversation; token
usage comes from the stdout telemetry captured in the harness logs, which
are not archived here (large; regenerate by rerunning).
