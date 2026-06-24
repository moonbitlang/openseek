# Auto-check Analysis A/B - 2026-06-21

## Setup

- Model: `deepseek-v4-pro`
- Task: `eval/prompt_tasks/toml_parser_cli.md`
- Runs: 10 per arm
- Concurrency: 10
- Max steps: 160
- Baseline: `911749d` (`prompt-only-no-analysis-pro`)
- Candidate: `cfd57fe` (`prompt-plus-analysis-pro`)
- Baseline report: `.moonagent/eval_runs/auto_check_analysis_ab_20260621_201903_baseline/report.md`
- Candidate report: `.moonagent/eval_runs/auto_check_analysis_ab_20260621_201903_candidate/report.md`

## Results

| Metric | Baseline | Candidate |
| --- | ---: | ---: |
| Strict successes | 9/10 | 9/10 |
| Validation successes | 10/10 | 9/10 |
| Finished sessions | 9/10 | 10/10 |
| Average steps | 106.3 | 92.4 |
| Median steps | 102 | 99 |
| Max steps | 160 | 123 |
| Average tool errors | 26.5 | 17.4 |
| Average shell failures | 26.0 | 16.9 |
| Average shell uses | 74.0 | 61.8 |

## Failure Modes

- Baseline trial 1 hit the 160-step cap and did not call `finish`, but all validation probes passed.
- Candidate trial 10 called `finish`, but created the project under `tomljson/` instead of the workspace root, so the expected `cmd/tomljson` probes failed.

## Analyzer Usage

The candidate emitted `analysis:` hints in 4/10 trials:

- trial 03: `self` repeated 50 diagnostics, later `r` repeated 4 diagnostics
- trial 05: `eprintln` repeated 4 diagnostics, twice
- trial 07: `eprintln` repeated 7 diagnostics
- trial 09: `UInt16` repeated 5 diagnostics

No trial used a real `...` placeholder implementation. The only source `...`
occurrence was a comment: `/// Parse an array: [value, value, ...]`.

## Conclusion

The analyzer did not improve strict pass rate in this sample, but the candidate
used fewer steps and generated fewer tool errors/shell failures. The observed
hint subjects were mixed: `eprintln` can plausibly be a local helper, but
`self`, `r`, and `UInt16` are more likely syntax/import/API-shape problems than
functions that should be stubbed.

This supports keeping the analyzer as a cautious hint, not a directive. The
prompt wording and auto-check text both say "If these are local helpers you
intend to implement", which matches the observed ambiguity. More runs or a task
designed to trigger repeated missing local helpers would be needed before
claiming a reliable pass-rate improvement.
