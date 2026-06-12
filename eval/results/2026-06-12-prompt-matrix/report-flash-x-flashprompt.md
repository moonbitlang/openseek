# Prompt Task Eval

- model: `deepseek-v4-flash`
- prompt: `flash-x-flashprompt`
- task: `eval/prompt_tasks/toml_parser_cli.md`
- result: `2/5 successes`
- concurrency: `3`
- threshold: `1/5`
- passed: `true`
- output: `/tmp/prompt_matrix/runs_flash-x-flashprompt`

| # | Case | Result | Steps | Tool Errors | Finished | Validation | Check | Test | File Probe | Stdin Probe | Dup Probe | Run -e | Run -c | Bad -e | from_str | parse_int | argparse | old argparse | C FFI | env args | containers | try | Exit Code | Reason | Warnings |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `trial-01` | pass | 73 | 12 | true | true | true | true | true | true | true | 0 | 0 | 0 | 7 | 0 | 4 | 0 | 0 | 0 | 15 | 3 | 0 | ok | shell output observed 41 time(s) |
| 2 | `trial-02` | fail | 152 | 42 | false | false | false | false | false | false | false | 2 | 1 | 0 | 4 | 0 | 0 | 0 | 0 | 1 | 1 | 6 | 0 | finish marker missing; moon check: exit 255: Error: [4015]     ╭─[ /private/tmp/prompt_matrix/runs_flash-x-flashprompt/workspaces/02/cmd/tomljson/main.mbt:45:41 ]     │  45 │       @stdio.stderr.write("error: " + e.to_string() + "\n")     │                                         ────...; moon test: exit 1: Error: [4015]     ╭─[ /private/tmp/prompt_matrix/runs_flash-x-flashprompt/workspaces/02/cmd/tomljson/main.mbt:45:41 ]     │  45 │       @stdio.stderr.write("error: " + e.to_string() + "\n")     │                                         ────...; file probe: stdout is not JSON: Unexpected end of file; stdout=; stdin probe: stdout is not JSON: Unexpected end of file; stdout=; duplicate probe: missing duplicate-key message, exit 0: Error: [4015]     ╭─[ /private/tmp/prompt_matrix/runs_flash-x-flashprompt/workspaces/02/cmd/tomljson/main.mbt:45:41 ]     │  45 │       @stdio.stderr.write("error: " + e.to_string() + "\n")     │                                         ────... | shell output observed 113 time(s) |
| 3 | `trial-03` | pass | 113 | 25 | true | true | true | true | true | true | true | 1 | 0 | 0 | 7 | 0 | 3 | 0 | 0 | 0 | 0 | 4 | 0 | ok | shell output observed 83 time(s) |
| 4 | `trial-04` | fail | 160 | 52 | false | true | true | true | true | true | true | 0 | 0 | 0 | 3 | 0 | 2 | 0 | 0 | 16 | 5 | 11 | 0 | finish marker missing | shell output observed 114 time(s) |
| 5 | `trial-05` | fail | 32 | 9 | false | false | false | false | false | false | true | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | finish marker missing; moon check: exit 255: Warning: [0020]    ╭─[ /private/tmp/prompt_matrix/runs_flash-x-flashprompt/workspaces/05/lib/toml_parser.mbt:6:36 ]    │  6 │   let result : Map[String, Json] = Map::new()    │                                    ────┬───      │             ...; moon test: exit 1: Warning: [0020]    ╭─[ /private/tmp/prompt_matrix/runs_flash-x-flashprompt/workspaces/05/lib/toml_parser.mbt:6:36 ]    │  6 │   let result : Map[String, Json] = Map::new()    │                                    ────┬───      │             ...; file probe: stdout is not JSON: Unexpected end of file; stdout=; stdin probe: stdout is not JSON: Unexpected end of file; stdout= | shell output observed 21 time(s) |

## Logs

- `trial-01` trial 1: `/tmp/prompt_matrix/runs_flash-x-flashprompt/logs/01.log`
- `trial-02` trial 2: `/tmp/prompt_matrix/runs_flash-x-flashprompt/logs/02.log`
- `trial-03` trial 3: `/tmp/prompt_matrix/runs_flash-x-flashprompt/logs/03.log`
- `trial-04` trial 4: `/tmp/prompt_matrix/runs_flash-x-flashprompt/logs/04.log`
- `trial-05` trial 5: `/tmp/prompt_matrix/runs_flash-x-flashprompt/logs/05.log`
