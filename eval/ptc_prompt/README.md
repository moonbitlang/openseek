# PTC capability and prompt evaluation

A focused, manual evaluation of tool orchestration guidance using the real
OpenSeek CLI and `deepseek-v4-flash`. It is not a general MoonBit coding
benchmark. The `ptc_eval.mbtx` script, run from the repository root, stages
byte-exact fixtures and scores nested PTC metadata, which the general
prompt-task harness does not currently score. API credentials are inherited
from `DEEPSEEK`, never copied into commands or reports.

## Capability A/B

SDK 0.1.0 is published and the host's real-script tests pass. Build a baseline
engine from the SDK-only PR (#1518, original host tools) and a candidate from
the host bridge (#1519). Then compare free tool choice with an identical prompt:

```sh
moon run eval/ptc_prompt/ptc_eval.mbtx run \
  --baseline-engine /absolute/path/to/sdk-only-openseek \
  --engine /absolute/path/to/ptc-openseek \
  --out .moonagent/eval_runs/ptc_capability_ab --runs 5 --concurrency 3
```

The runner uses the current rendered prompt for **both** variants and records
both binary hashes and equal prompt hashes. Supplying `--require-ptc` is rejected
in capability mode because the baseline does not offer it. Keep these results separate from the historical prompt-only comparison below.
The current release comparison is recorded in `capability-results-2026-09-15.md`.

All trials share model, fixture bytes, step cap (24), and timeout (600s). Pair
launch order alternates across repetitions. Output directories must be new.

Cases (repeat `--cases` to select a subset; all three by default):

- `single_edit`: direct-call control; exact bytes and protected file unchanged.
- `computed_edits`: calculate twelve replacements from CSV data, preserve input
  and all unrelated bytes, and report the count and sum.
- `search`: two documentation topics, JSON answer, official documentation hosts,
  distinct source URLs present in structured search results, at least two search
  calls. The strict host oracle accepts `docs.python.org` and
  `doc.rust-lang.org`; it can reject official repository documentation or a
  URL whose fragment the model changed. Review those failures manually.
  This checks format and provenance, **not** the semantic quality of the pages.
  Live search availability introduces noise; review the returned sources too.

## Historical prompt-only A/B

`baseline.md`, `candidate.md`, `candidate_expanded.md`, and the 2026-09-15 results
preserve the original injected-client experiment. Both variants had PTC. The
current SDK prompt is not the prompt tested in those artifacts.

To reproduce the original experiment, use an engine built from `c5c1210d2`
(original PR #1516) and explicitly select `--prompt-ab`:

```sh
moon run eval/ptc_prompt/ptc_eval.mbtx run --prompt-ab \
  --engine /absolute/path/to/original-injected-client-openseek \
  --base-prompt /absolute/path/to/original-system-prompt.md \
  --out .moonagent/eval_runs/historical_prompt_ab --runs 3 --concurrency 3
```

`--base-prompt` is the plain-text system prompt of that historical checkout
(decode its `prompt/generated_default_prompt.mbt`, or dump it from the engine).
The runner splices the two variants over the `### Programmatic tool calls`
section; the current checkout's section documents the published SDK rather
than the historical injected client, so the comparison needs the prompt the
original binary was run with, and the runner refuses a base prompt without
that section.

Historical mode splices the saved PTC sections into the rendered prompt and uses
one engine for both variants. `--require-ptc --cases computed_edits` reproduces
the separate execution cohort. Do not pool it with free-choice performance
results. Three repeats are exploratory, not a cross-model guarantee.

## Analyze without API calls

```sh
moon run eval/ptc_prompt/ptc_eval.mbtx run --analyze-only \
  --out .moonagent/eval_runs/ptc_prompt_ab
moon test eval/ptc_prompt/ptc_eval.mbtx
```

Each trial keeps its raw CLI log, durable session, workspace, and summary JSON.
`results.json` combines the summaries. Metrics distinguish outer calls, nested
calls, outer/nested errors, interrupted requests, model-visible tool output,
model steps, wall time, and provider token/cache usage. Missing usage is `null`.
An outer error can describe the same failure as a nested error; do not add those
counts as if they were independent failures. Token totals cover the agent's
reported usage; separate search-provider token costs are not included.

Review traces for unnecessary retries, unchecked results, detached work,
verification before finish, and unsupported final claims. A passing file oracle
alone does not prove that the agent followed the requested editing tool policy.
Do not promote a prompt merely because it increases PTC usage or wins one run.

## YAML parser coding comparison

The `yaml` subcommand compares the same two engines with free tool choice on a
larger implementation task. Each fresh MoonBit project contains an API stub,
a written contract, and six visible smoke tests. The contract defines a
JSON-compatible YAML subset; it is not a claim of full YAML conformance.

```sh
moon run eval/ptc_prompt/ptc_eval.mbtx yaml \
  --baseline-engine /absolute/path/to/sdk-only-openseek \
  --engine /absolute/path/to/ptc-openseek \
  --out /absolute/path/to/new-yaml-results --runs 2 --concurrency 2 \
  --max-steps 128 --timeout 1800
```

Both sides receive identical system prompts, tasks, model settings, and a
128-step allowance by default. After each run, a separate grading project compiles the
implementation against 30 valid-input and 16 rejection tests. Candidate tests
are excluded; the grader supplies the module manifest and selects only its own
oracle cases. The fixture manifest and visible tests must remain unchanged.
The oracle is authored independently of the generated implementations.

Record byte-identical prompt/spec/oracle hashes and distinct binary hashes.
The oracle hash of runs made by the retired Python runner differs (its test
source spelled the same JSON values differently); do not compare it across runners.
Report valid and invalid cases separately: a parser that rejects everything
can pass the rejection cases without implementing any parsing. Report tool
errors, actual PTC use, wall time, and token usage alongside correctness.
Two repetitions per variant are exploratory evidence, not a statistical
non-regression guarantee. Raw code and transcripts remain in the run directory.

The initial parser cohort used 64 steps and 900 seconds. The first pair passed
all withheld parser tests but did not finish their review workflows within those
limits. A separate matched follow-up uses 128 steps and 1800 seconds; keep the
cohorts separate when analyzing results.

See [the YAML parser report](yaml-results-2026-09-15.md) for artifact
correctness, workflow completion, actual PTC use, and budget limits. The
runners write `manifest.json` (model, limits, prompt and binary hashes) and
`results.json` (per-trial metrics and artifact paths) next to their logs;
both are regenerated on each run and are not committed.

The reader selects the named parent session when review children exist. Token
usage from the parent event log excludes child usage when the workflow journal
does not retain it; report child counts/steps and do not treat that number as
total cost. Execution timing is checkpointed before grading so a scoring error
cannot discard it. `--analyze-only --out ...` regrades saved implementations
without rerunning the model. Recovered timing without a checkpoint is explicitly
labeled as a log active span, which can omit silent waits.
