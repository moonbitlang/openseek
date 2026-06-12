# Prompt Task Eval

- model: `deepseek-v4-pro`
- prompt: `pro-x-baseprompt`
- task: `eval/prompt_tasks/toml_parser_cli.md`
- result: `3/5 successes`
- concurrency: `3`
- threshold: `1/5`
- passed: `true`
- output: `/tmp/prompt_matrix/runs_pro-x-baseprompt`

| # | Case | Result | Steps | Tool Errors | Finished | Validation | Check | Test | File Probe | Stdin Probe | Dup Probe | Run -e | Run -c | Bad -e | from_str | parse_int | argparse | old argparse | C FFI | env args | containers | try | Exit Code | Reason | Warnings |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `trial-01` | pass | 114 | 10 | true | true | true | true | true | true | true | 0 | 0 | 0 | 0 | 15 | 7 | 0 | 0 | 0 | 6 | 0 | 0 | ok | shell output observed 41 time(s) |
| 2 | `trial-02` | pass | 130 | 31 | true | true | true | true | true | true | true | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 3 | 1 | 0 | 0 | ok | shell output observed 48 time(s) |
| 3 | `trial-03` | fail | 109 | 12 | true | false | false | false | false | false | false | 0 | 0 | 0 | 0 | 7 | 0 | 0 | 0 | 4 | 1 | 3 | 0 | moon check: exit 255: Error: not in a Moon project (no moon.mod, moon.mod.json, or moon.work found starting from /private/tmp/prompt_matrix/runs_pro-x-baseprompt/workspaces/03 or its ancestors); moon test: exit 255: Error: not in a Moon project (no moon.mod, moon.mod.json, or moon.work found starting from /private/tmp/prompt_matrix/runs_pro-x-baseprompt/workspaces/03 or its ancestors); file probe: exit 255: Error: failed to resolve path `cmd/tomljson`  Caused by:     No such file or directory (os error 2); stdin probe: exit 255: Error: failed to resolve path `cmd/tomljson`  Caused by:     No such file or directory (os error 2); duplicate probe: missing duplicate-key message, exit 255: Error: failed to resolve path `cmd/tomljson`  Caused by:     No such file or directory (os error 2) | shell output observed 50 time(s) |
| 4 | `trial-04` | fail | 123 | 19 | true | false | true | true | true | true | false | 0 | 0 | 0 | 0 | 5 | 21 | 0 | 0 | 7 | 14 | 6 | 0 | duplicate probe: missing duplicate-key message, exit 0: Parse error | shell output observed 50 time(s) |
| 5 | `trial-05` | pass | 127 | 11 | true | true | true | true | true | true | true | 0 | 0 | 0 | 0 | 0 | 12 | 0 | 0 | 3 | 0 | 1 | 0 | ok | shell output observed 74 time(s) |

## Logs

- `trial-01` trial 1: `/tmp/prompt_matrix/runs_pro-x-baseprompt/logs/01.log`
- `trial-02` trial 2: `/tmp/prompt_matrix/runs_pro-x-baseprompt/logs/02.log`
- `trial-03` trial 3: `/tmp/prompt_matrix/runs_pro-x-baseprompt/logs/03.log`
- `trial-04` trial 4: `/tmp/prompt_matrix/runs_pro-x-baseprompt/logs/04.log`
- `trial-05` trial 5: `/tmp/prompt_matrix/runs_pro-x-baseprompt/logs/05.log`
