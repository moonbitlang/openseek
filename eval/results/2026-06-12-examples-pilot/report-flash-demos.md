# Prompt Task Eval

- model: `deepseek-v4-flash`
- prompt: `flash-demos`
- task: `eval/prompt_tasks/toml_parser_cli.md`
- result: `3/5 successes`
- concurrency: `3`
- threshold: `1/5`
- passed: `true`
- output: `/tmp/prompt_demos/runs_flash-demos`

| # | Case | Result | Steps | Tool Errors | Finished | Validation | Check | Test | File Probe | Stdin Probe | Dup Probe | Run -e | Run -c | Bad -e | from_str | parse_int | argparse | old argparse | C FFI | env args | containers | try | Exit Code | Reason | Warnings |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `trial-01` | pass | 106 | 27 | true | true | true | true | true | true | true | 0 | 1 | 0 | 0 | 4 | 5 | 0 | 0 | 0 | 2 | 0 | 0 | ok | shell output observed 74 time(s) |
| 2 | `trial-02` | fail | 39 | 15 | false | false | false | false | false | false | false | 0 | 0 | 0 | 0 | 13 | 0 | 0 | 0 | 0 | 2 | 0 | 1 | agent process exited 1; finish marker missing; moon check: exit 255: Error: [4074] Missing type annotation for the parameter . Warning: [0027]    ╭─[ /private/tmp/prompt_demos/runs_flash-demos/workspaces/02/toml.mbt:3:26 ]    │  3 │ priv suberror ParseError(String)    │                          ───┬──      │...; moon test: exit 1: Error: [4074] Missing type annotation for the parameter . Warning: [0027]    ╭─[ /private/tmp/prompt_demos/runs_flash-demos/workspaces/02/toml.mbt:3:26 ]    │  3 │ priv suberror ParseError(String)    │                          ───┬──      │...; file probe: exit 255: Error: Cannot find package to build based on input path `/private/tmp/prompt_demos/runs_flash-demos/workspaces/02/cmd/tomljson`. Hint: The provided path `/private/tmp/prompt_demos/runs_flash-demos/workspaces/02/cmd/tomljson` is inside the p...; stdin probe: exit 255: Error: Cannot find package to build based on input path `/private/tmp/prompt_demos/runs_flash-demos/workspaces/02/cmd/tomljson`. Hint: The provided path `/private/tmp/prompt_demos/runs_flash-demos/workspaces/02/cmd/tomljson` is inside the p...; duplicate probe: missing duplicate-key message, exit 255: Error: Cannot find package to build based on input path `/private/tmp/prompt_demos/runs_flash-demos/workspaces/02/cmd/tomljson`. Hint: The provided path `/private/tmp/prompt_demos/runs_flash-demos/workspaces/02/cmd/tomljson` is inside the p... | shell output observed 22 time(s) |
| 3 | `trial-03` | fail | 29 | 5 | false | false | true | false | false | false | false | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 1 | 0 | 1 | agent process exited 1; finish marker missing; moon test: exit 2: [user/toml] test lib/toml_test.mbt:35 ("string escapes") failed: lib/toml_test.mbt:41:3-41:40@user/toml FAILED: `false` is not true [user/toml] test lib/toml_test.mbt:83 ("duplicate table key error") failed: lib/toml_test.mbt:88:10-88:52@us...; file probe: exit 255: Error: failed to resolve path `cmd/tomljson`  Caused by:     No such file or directory (os error 2); stdin probe: exit 255: Error: failed to resolve path `cmd/tomljson`  Caused by:     No such file or directory (os error 2); duplicate probe: missing duplicate-key message, exit 255: Error: failed to resolve path `cmd/tomljson`  Caused by:     No such file or directory (os error 2) | shell output observed 18 time(s) |
| 4 | `trial-04` | pass | 134 | 15 | true | true | true | true | true | true | true | 1 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 13 | 0 | 0 | 0 | ok | shell output observed 82 time(s) |
| 5 | `trial-05` | pass | 93 | 22 | true | true | true | true | true | true | true | 0 | 0 | 0 | 0 | 10 | 0 | 0 | 0 | 1 | 4 | 0 | 0 | ok | shell output observed 52 time(s) |

## Logs

- `trial-01` trial 1: `/tmp/prompt_demos/runs_flash-demos/logs/01.log`
- `trial-02` trial 2: `/tmp/prompt_demos/runs_flash-demos/logs/02.log`
- `trial-03` trial 3: `/tmp/prompt_demos/runs_flash-demos/logs/03.log`
- `trial-04` trial 4: `/tmp/prompt_demos/runs_flash-demos/logs/04.log`
- `trial-05` trial 5: `/tmp/prompt_demos/runs_flash-demos/logs/05.log`
