# Prompt Task Eval

- model: `deepseek-v4-flash`
- prompt: `flash-guidelines`
- task: `eval/prompt_tasks/toml_parser_cli.md`
- result: `3/5 successes`
- concurrency: `3`
- threshold: `1/5`
- passed: `true`
- output: `/tmp/prompt_demos/runs_flash-guidelines`

| # | Case | Result | Steps | Tool Errors | Finished | Validation | Check | Test | File Probe | Stdin Probe | Dup Probe | Run -e | Run -c | Bad -e | from_str | parse_int | argparse | old argparse | C FFI | env args | containers | try | Exit Code | Reason | Warnings |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `trial-01` | fail | 87 | 12 | true | false | true | true | true | true | false | 0 | 0 | 0 | 13 | 0 | 0 | 0 | 0 | 0 | 1 | 2 | 0 | duplicate probe: missing duplicate-key message, exit 0: Error: invalid TOML input | shell output observed 47 time(s) |
| 2 | `trial-02` | fail | 60 | 21 | true | false | true | true | false | false | false | 0 | 0 | 0 | 5 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | file probe: exit 255: Error: Cannot find package to build based on input path `/private/tmp/prompt_demos/runs_flash-guidelines/workspaces/02/cmd/tomljson`. Hint: The provided path `/private/tmp/prompt_demos/runs_flash-guidelines/workspaces/02/cmd/tomljson` is in...; stdin probe: exit 255: Error: Cannot find package to build based on input path `/private/tmp/prompt_demos/runs_flash-guidelines/workspaces/02/cmd/tomljson`. Hint: The provided path `/private/tmp/prompt_demos/runs_flash-guidelines/workspaces/02/cmd/tomljson` is in...; duplicate probe: missing duplicate-key message, exit 255: Error: Cannot find package to build based on input path `/private/tmp/prompt_demos/runs_flash-guidelines/workspaces/02/cmd/tomljson`. Hint: The provided path `/private/tmp/prompt_demos/runs_flash-guidelines/workspaces/02/cmd/tomljson` is in... | shell output observed 38 time(s) |
| 3 | `trial-03` | pass | 95 | 23 | true | true | true | true | true | true | true | 1 | 0 | 0 | 2 | 0 | 11 | 0 | 0 | 0 | 6 | 4 | 0 | ok | shell output observed 67 time(s) |
| 4 | `trial-04` | pass | 121 | 18 | true | true | true | true | true | true | true | 0 | 0 | 0 | 2 | 0 | 12 | 0 | 0 | 0 | 5 | 0 | 0 | ok | shell output observed 55 time(s) |
| 5 | `trial-05` | pass | 127 | 33 | true | true | true | true | true | true | true | 1 | 0 | 0 | 19 | 3 | 0 | 0 | 0 | 6 | 0 | 1 | 0 | ok | shell output observed 108 time(s) |

## Logs

- `trial-01` trial 1: `/tmp/prompt_demos/runs_flash-guidelines/logs/01.log`
- `trial-02` trial 2: `/tmp/prompt_demos/runs_flash-guidelines/logs/02.log`
- `trial-03` trial 3: `/tmp/prompt_demos/runs_flash-guidelines/logs/03.log`
- `trial-04` trial 4: `/tmp/prompt_demos/runs_flash-guidelines/logs/04.log`
- `trial-05` trial 5: `/tmp/prompt_demos/runs_flash-guidelines/logs/05.log`
