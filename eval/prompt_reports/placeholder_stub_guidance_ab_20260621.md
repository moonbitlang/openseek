# Placeholder Stub Guidance A/B - 2026-06-21

## Setup

- Baseline engine: detached `origin/main` at `a85d568`
- Candidate engine: `codex/moon-check-placeholder-prompt`
- Task: `eval/prompt_tasks/toml_parser_cli.md`
- Runs: 10 per arm
- Concurrency: 10 per arm
- Max steps: 160
- Raw artifacts are under `.moonagent/eval_runs/` and ignored by git.

## MoonBit Behavior Check

Verified separately in a temporary MoonBit project:

- A real generic function with a `...` body type-checks under `moon check`.
- A real method with a `...` body type-checks under `moon check`.
- `moon check` reports `Warning (todo): unfinished code`.
- `moon check --deny-warn` fails on the placeholder warning, so unfinished code remains blocking when warnings are denied.

This confirms the prompt guidance is technically valid: typed placeholder bodies can reduce missing-name cascades while leaving an explicit compiler warning.

## Results: DeepSeek V4 Flash

| Metric | Baseline | Candidate |
| --- | ---: | ---: |
| Successful trials | 7/10 | 5/10 |
| Finished trials | 8/10 | 7/10 |
| Workspace validation passed | 7/10 | 6/10 |
| `moon check` passed | 10/10 | 10/10 |
| `moon test` passed | 10/10 | 10/10 |
| File CLI probe passed | 7/10 | 7/10 |
| Stdin CLI probe passed | 7/10 | 7/10 |
| Duplicate-key probe passed | 8/10 | 6/10 |
| Max-step failures | 1/10 | 3/10 |
| Average steps | 115.7 | 121.3 |
| Average tool errors | 19.1 | 18.5 |
| C FFI mentions | 15 | 33 |
| `@env.args` mentions | 26 | 74 |
| Placeholder stub usage in event writes | 0/10 | 0/10 |
| `Warning (todo)` / unfinished-code hits | 0/10 | 0/10 |
| Final `.mbt` placeholder bodies | 0/10 | 0/10 |

Raw artifacts:

- Baseline: `.moonagent/eval_runs/placeholder_stub_ab_20260621_154403_baseline`
- Candidate: `.moonagent/eval_runs/placeholder_stub_ab_20260621_154403_candidate`

Notes:

- Baseline trial 06 hung in a native compile while running a CLI stdin probe. It was terminated so the run could finish; the analyzer then recorded that trial as failed.
- Candidate trial 08 passed all workspace validation probes but exhausted the agent step cap before calling `finish`, so it is counted as a failed agent trial.
- In both arms, all workspaces reached a state where `moon check` and `moon test` passed. The pass-rate differences came from CLI contract probes, step exhaustion, wrong CLI package paths, and duplicate-key message quality.

## Results: DeepSeek V4 Pro

| Metric | Baseline | Candidate |
| --- | ---: | ---: |
| Successful trials | 8/10 | 8/10 |
| Finished trials | 9/10 | 10/10 |
| Workspace validation passed | 8/10 | 8/10 |
| `moon check` passed | 10/10 | 10/10 |
| `moon test` passed | 10/10 | 10/10 |
| File CLI probe passed | 8/10 | 9/10 |
| Stdin CLI probe passed | 8/10 | 9/10 |
| Duplicate-key probe passed | 8/10 | 8/10 |
| Max-step failures | 0/10 | 0/10 |
| Average steps | 104.6 | 108.3 |
| Average tool errors | 19.1 | 16.5 |
| C FFI mentions | 0 | 0 |
| `@env.args` mentions | 12 | 21 |
| Placeholder stub usage in event writes | 0/10 | 0/10 |
| `Warning (todo)` / unfinished-code hits | 0/10 | 0/10 |
| Final `.mbt` placeholder bodies | 0/10 | 0/10 |

Raw artifacts:

- Baseline: `.moonagent/eval_runs/placeholder_stub_ab_pro_20260621_171123_baseline`
- Candidate: `.moonagent/eval_runs/placeholder_stub_ab_pro_20260621_171123_candidate`

Failure notes:

- Baseline trial 08 built and tested successfully, but put the CLI somewhere other than the requested `cmd/tomljson`, so external CLI probes failed.
- Baseline trial 10 exited before an event log was written; `moon check` and `moon test` still passed in the workspace, but external probes could not find `cmd/tomljson`.
- Candidate trial 05 passed file and stdin probes, but duplicate-key output was only `Error: invalid TOML input`, which failed the duplicate-key contract.
- Candidate trial 07 built and tested successfully, but external probes could not resolve `cmd/tomljson`.
- One candidate event log contained the phrase `unfinished code` only because the agent ran a broad grep command for TODO/debug cleanup. No event write/edit call contained a `...` body, and no final `.mbt` file contained one.

## Conclusion

The placeholder-stub instruction is correct MoonBit guidance, but neither model variant actually used it on this TOML benchmark. The DeepSeek V4 Flash run looked noisy and candidate-worse, while the DeepSeek V4 Pro run tied at 8/10 validated successes with no max-step failures in either arm.

Current read: the prompt line is not harmful under DeepSeek V4 Pro, but it also is not a general performance improvement for this task. It should stay framed as targeted diagnostic advice for the "hundreds of missing local functions" failure mode, not as a broad coding-quality optimization.
