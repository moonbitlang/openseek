# OpenSeek CLI

This package is the native-only command-line entry point for OpenSeek. It parses
arguments with `moonbitlang/core/argparse`, reads defaults from environment
variables, and calls `bobzhang/openseek/agent.run` for one-shot tasks or
`agent.run_turn_with_append` for durable sessions.

## Command

```bash
moon run cmd/openseek -- [--api-key sk-...] [--model deepseek-v4-pro] [--max-steps 1000] [--system-prompt-file prompt.md] [--system-prompt-addendum-file addendum.md] [--session session-id] [--session-root .openseek] "task text"
```

Agent runs require `--api-key` or `DEEPSEEK`. `--model` can also be supplied with
`DEEPSEEK_MODEL`; it defaults to `deepseek-v4-pro`. `--max-steps` can also be
supplied with `OPENSEEK_MAX_STEPS`; it defaults to `1000`.
`--system-prompt-file` and `--system-prompt-addendum-file` can also be supplied
with `OPENSEEK_SYSTEM_PROMPT_FILE` and
`OPENSEEK_SYSTEM_PROMPT_ADDENDUM_FILE`. `--session` can also be supplied with
`OPENSEEK_SESSION`; when set, the CLI creates or resumes that session under
`--session-root` / `OPENSEEK_SESSION_ROOT` (default `.openseek`).

Without an explicit prompt file, the CLI selects the built-in prompt by model:
`deepseek-v4-flash` uses `prompt/flash_prompt.md`; `deepseek-v4-pro` uses
`prompt/base_prompt.md`.

## Session Management

The session-management commands are offline and do not require `--api-key`:

```bash
moon run cmd/openseek -- --session-list --session-root .openseek
moon run cmd/openseek -- --session-show --session parser-fix --session-root .openseek
moon run cmd/openseek -- --session parser-fix --session-compact-file summary.txt --session-compact-from 1 --session-compact-to 120
```

`--session-compact-file` appends a typed summary event. It does not delete raw
events from `events.jsonl`; `agent_session.Session::chat_messages` uses the
summary to compact model context on replay.

## Examples

```bash
export DEEPSEEK=sk-...
moon run cmd/openseek -- "run moon test and summarize the result"
```

```bash
DEEPSEEK_MODEL=deepseek-v4-flash moon run cmd/openseek -- "inspect the package docs"
```

```bash
moon run cmd/openseek -- --max-steps 200 "write tests, fix failures, and summarize"
```

```bash
moon run cmd/openseek -- --session parser-fix "continue from the last run"
```

## Package Boundary

This package should stay thin: argument parsing, environment-backed defaults,
model parsing, prompt override file loading, session-store setup, and
delegation to the agent package. The prompt package owns built-in prompt
selection; the agent package owns tool definitions and the execution loop.

Run the package tests with:

```bash
moon test cmd/openseek
```
