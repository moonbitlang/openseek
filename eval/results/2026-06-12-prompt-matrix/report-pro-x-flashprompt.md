# Prompt Task Eval

- model: `deepseek-v4-pro`
- prompt: `pro-x-flashprompt`
- task: `eval/prompt_tasks/toml_parser_cli.md`
- result: `4/5 successes`
- concurrency: `3`
- threshold: `1/5`
- passed: `true`
- output: `/tmp/prompt_matrix/runs_pro-x-flashprompt`

| # | Case | Result | Steps | Tool Errors | Finished | Validation | Check | Test | File Probe | Stdin Probe | Dup Probe | Run -e | Run -c | Bad -e | from_str | parse_int | argparse | old argparse | C FFI | env args | containers | try | Exit Code | Reason | Warnings |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `trial-01` | fail | 119 | 13 | true | false | true | true | true | true | false | 1 | 0 | 0 | 18 | 0 | 38 | 0 | 0 | 0 | 4 | 0 | 0 | duplicate probe: missing duplicate-key message, exit 0: Error: invalid TOML input | shell output observed 39 time(s) |
| 2 | `trial-02` | pass | 134 | 41 | true | true | true | true | true | true | true | 6 | 0 | 0 | 1 | 0 | 3 | 0 | 0 | 0 | 1 | 0 | 0 | ok | shell output observed 79 time(s) |
| 3 | `trial-03` | pass | 145 | 36 | true | true | true | true | true | true | true | 3 | 0 | 0 | 5 | 0 | 1 | 0 | 0 | 0 | 24 | 0 | 0 | ok | shell output observed 84 time(s) |
| 4 | `trial-04` | pass | 110 | 41 | true | true | true | true | true | true | true | 0 | 0 | 0 | 28 | 0 | 98 | 0 | 0 | 9 | 0 | 0 | 0 | ok | shell output observed 59 time(s) |
| 5 | `trial-05` | pass | 100 | 18 | true | true | true | true | true | true | true | 0 | 0 | 0 | 21 | 0 | 34 | 0 | 0 | 0 | 5 | 0 | 0 | ok | shell output observed 40 time(s) |

## Logs

- `trial-01` trial 1: `/tmp/prompt_matrix/runs_pro-x-flashprompt/logs/01.log`
- `trial-02` trial 2: `/tmp/prompt_matrix/runs_pro-x-flashprompt/logs/02.log`
- `trial-03` trial 3: `/tmp/prompt_matrix/runs_pro-x-flashprompt/logs/03.log`
- `trial-04` trial 4: `/tmp/prompt_matrix/runs_pro-x-flashprompt/logs/04.log`
- `trial-05` trial 5: `/tmp/prompt_matrix/runs_pro-x-flashprompt/logs/05.log`
