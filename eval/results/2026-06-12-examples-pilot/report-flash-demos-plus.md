# Prompt Task Eval

- model: `deepseek-v4-flash`
- prompt: `flash-demos-plus`
- task: `eval/prompt_tasks/toml_parser_cli.md`
- result: `2/5 successes`
- concurrency: `3`
- threshold: `1/5`
- passed: `true`
- output: `/tmp/prompt_demos/runs_flash-demos-plus`

| # | Case | Result | Steps | Tool Errors | Finished | Validation | Check | Test | File Probe | Stdin Probe | Dup Probe | Run -e | Run -c | Bad -e | from_str | parse_int | argparse | old argparse | C FFI | env args | containers | try | Exit Code | Reason | Warnings |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `trial-01` | fail | 160 | 55 | false | false | true | false | true | true | false | 0 | 0 | 0 | 10 | 0 | 0 | 0 | 0 | 19 | 66 | 0 | 0 | finish marker missing; moon test: exit 2: Warning: [0020]     ╭─[ /private/tmp/prompt_demos/runs_flash-demos-plus/workspaces/01/lib.mbt:43:10 ]     │  43 │       if not (last_ch is Some(']')) {     │          ─┬─       │           ╰─── Warning (deprecated): Use !expr instead ────╯ ...; duplicate probe: missing duplicate-key message, exit 0: error: parse failure | shell output observed 87 time(s) |
| 2 | `trial-02` | pass | 112 | 22 | true | true | true | true | true | true | true | 0 | 0 | 0 | 8 | 6 | 18 | 0 | 0 | 0 | 14 | 3 | 0 | ok | shell output observed 76 time(s) |
| 3 | `trial-03` | fail | 160 | 29 | false | true | true | true | true | true | true | 0 | 0 | 0 | 5 | 2 | 89 | 0 | 0 | 9 | 0 | 7 | 0 | finish marker missing | shell output observed 107 time(s) |
| 4 | `trial-04` | pass | 98 | 25 | true | true | true | true | true | true | true | 0 | 0 | 0 | 2 | 39 | 4 | 0 | 0 | 0 | 2 | 0 | 0 | ok | shell output observed 66 time(s) |
| 5 | `trial-05` | fail | 160 | 34 | false | true | true | true | true | true | true | 0 | 0 | 0 | 7 | 0 | 11 | 0 | 2 | 4 | 0 | 2 | 0 | finish marker missing | shell output observed 138 time(s) |

## Logs

- `trial-01` trial 1: `/tmp/prompt_demos/runs_flash-demos-plus/logs/01.log`
- `trial-02` trial 2: `/tmp/prompt_demos/runs_flash-demos-plus/logs/02.log`
- `trial-03` trial 3: `/tmp/prompt_demos/runs_flash-demos-plus/logs/03.log`
- `trial-04` trial 4: `/tmp/prompt_demos/runs_flash-demos-plus/logs/04.log`
- `trial-05` trial 5: `/tmp/prompt_demos/runs_flash-demos-plus/logs/05.log`
