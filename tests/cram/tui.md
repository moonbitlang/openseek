# Verified OpenSeek TUI CLI Documentation

These examples are executed by `moon cram test tests/cram`. The Moon wrapper
builds the native package at `cmd/tui` first, then exposes the executable on
`PATH` as `tui.exe`.

Both commands are offline: they exercise only the argument parser, which runs
before the terminal UI starts, so the suite needs no API key, no TTY, and makes
no network calls. The live, API-backed examples live in
[`tests/live/deepseek.md`](../live/deepseek.md).

## Help Banner

`--help` prints the usage, the available options, and the environment variables
and defaults behind each one, then exits successfully.

```mooncram
$ tui.exe --help
Usage: openseek-tui --api-key <api-key> [options] [task...]

OpenSeek terminal UI.

Arguments:
  task...  Optional initial task description.

Options:
  -h, --help                             Show help information.
  --continue                             Resume the most recently active session in --session-root.
  --api-key <api-key>                    DeepSeek API key. [env: DEEPSEEK]
  --model <model>                        DeepSeek model: deepseek-v4-flash or deepseek-v4-pro. [env: DEEPSEEK_MODEL] [default: deepseek-v4-pro]
  --max-steps <max-steps>                Maximum number of agent loop steps before stopping. [env: OPENSEEK_MAX_STEPS] [default: 1000]
  --thinking <thinking>                  DeepSeek thinking mode: enabled or disabled. [env: OPENSEEK_THINKING] [default: enabled]
  --reasoning-effort <reasoning-effort>  DeepSeek reasoning effort in thinking mode: high or max. [env: OPENSEEK_REASONING_EFFORT] [default: max]
  --engine <engine>                      Agent engine binary to spawn; reads its JSONL event stream from stdout. [env: OPENSEEK_ENGINE] [default: openseek]
  --session <session>                    Create or resume this durable session id. [env: OPENSEEK_SESSION]
  --session-root <session-root>          Directory containing durable OpenSeek sessions. [env: OPENSEEK_SESSION_ROOT] [default: .openseek]
```

## A DeepSeek API Key Is Required

With no `--api-key` flag and no `DEEPSEEK` in the environment, the CLI reports
the missing required argument, prints the usage, and exits non-zero — before the
terminal UI ever starts.

```mooncram
$ env -u DEEPSEEK tui.exe "summarize this project"
error: the following required argument was not provided: 'api-key'

Usage: openseek-tui --api-key <api-key> [options] [task...]

OpenSeek terminal UI.

Arguments:
  task...  Optional initial task description.

Options:
  -h, --help                             Show help information.
  --continue                             Resume the most recently active session in --session-root.
  --api-key <api-key>                    DeepSeek API key. [env: DEEPSEEK]
  --model <model>                        DeepSeek model: deepseek-v4-flash or deepseek-v4-pro. [env: DEEPSEEK_MODEL] [default: deepseek-v4-pro]
  --max-steps <max-steps>                Maximum number of agent loop steps before stopping. [env: OPENSEEK_MAX_STEPS] [default: 1000]
  --thinking <thinking>                  DeepSeek thinking mode: enabled or disabled. [env: OPENSEEK_THINKING] [default: enabled]
  --reasoning-effort <reasoning-effort>  DeepSeek reasoning effort in thinking mode: high or max. [env: OPENSEEK_REASONING_EFFORT] [default: max]
  --engine <engine>                      Agent engine binary to spawn; reads its JSONL event stream from stdout. [env: OPENSEEK_ENGINE] [default: openseek]
  --session <session>                    Create or resume this durable session id. [env: OPENSEEK_SESSION]
  --session-root <session-root>          Directory containing durable OpenSeek sessions. [env: OPENSEEK_SESSION_ROOT] [default: .openseek]

[1]
```
