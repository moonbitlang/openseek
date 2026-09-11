# File Edit Eval

This harness measures whether a model can use OpenSeek's file-editing tools
reliably. The case definitions live in `eval/file_edit/cases`; the reusable
runner, deterministic oracles, and report writer live in `eval/file_edit/harness`;
the `eval/file_edit/cmd/main` package is only the CLI wrapper around that
harness. Case fixtures use `bobzhang/openseek/testkit/filesystem`, and report
output is rendered through `bobzhang/openseek/eval/report`, so both fixture and
report code can be reused by other mock tests and harnesses.

To see the harness without calling DeepSeek, run the dry-run oracle test:

```bash
moon test eval/file_edit/harness --filter "dry run exact replacement oracle"
```

The default baseline is cheap Flash:

```bash
moon run --target native eval/file_edit/cmd/main -- \
  --api-key "$DEEPSEEK" \
  --model deepseek-v4-flash \
  --runs 10 \
  --concurrency 1 \
  --min-successes 8 \
  --max-steps 200 \
  --out .moonagent/eval_runs/file_edit_flash
```

## Prompt A/B Testing

Use `--prompt-label` plus a prompt file or addendum file to compare prompt
variants with the same cheap Flash runner. The report records the prompt label
and log-derived metrics such as `moon_cmd` use, `moon run -e` mentions,
`moon run -c` mentions, `moon check`, `moon test`, `moon info`, `moon fmt`,
tool errors, and step counts.

Run A with the built-in prompt:

```bash
moon run --target native eval/file_edit/cmd/main -- \
  --api-key "$DEEPSEEK" \
  --model deepseek-v4-flash \
  --runs 10 \
  --concurrency 1 \
  --min-successes 8 \
  --max-steps 200 \
  --prompt-label builtin \
  --out .moonagent/eval_runs/file_edit_flash_builtin
```

Run B with an addendum:

```bash
moon run --target native eval/file_edit/cmd/main -- \
  --api-key "$DEEPSEEK" \
  --model deepseek-v4-flash \
  --runs 10 \
  --concurrency 1 \
  --min-successes 8 \
  --max-steps 200 \
  --prompt-label moonbit_probe_discipline \
  --system-prompt-addendum-file eval/prompts/moonbit_probe_discipline.md \
  --out .moonagent/eval_runs/file_edit_flash_probe
```

Compare `report.md`, `report.json`, and the logs in each output directory.
For this addendum, useful signals are fewer `Run -c` mentions, more successful
`Run -e` or stdin probes when a case requires MoonBit validation, fewer repeated
tool errors, and no regression in pass rate or final validation.

To estimate reliability faster, run repeated trials concurrently. For example,
five Flash repeats with five concurrent agent processes:

```bash
moon run --target native eval/file_edit/cmd/main -- \
  --api-key "$DEEPSEEK" \
  --model deepseek-v4-flash \
  --runs 5 \
  --concurrency 5 \
  --min-successes 5 \
  --max-steps 200 \
  --prompt-label builtin \
  --out .moonagent/eval_runs/file_edit_flash_5x
```

The eval is intentionally not part of ordinary `moon test`: it calls the real
DeepSeek API and is nondeterministic. Use it as a manual or scheduled baseline.

## Pass Criteria

A trial passes only when:

- expected files match exactly,
- protected files remain unchanged,
- case-specific validation passes,
- the final log contains the requested `file-edit-eval:<case>` marker.

The report records successes, prompt labels, steps, tool errors,
MoonBit command/probe metrics, edit/write successes, log paths, and final
failure reasons.
