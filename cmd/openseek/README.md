# OpenSeek CLI

This package is the native-only entry point for OpenSeek — the single `openseek`
binary. It is a subcommand tree: the interactive terminal UI is the **default**
(see [`cmd/tui`](../tui/README.md)), and the headless engine lives under named
subcommands. It parses arguments with `moonbitlang/core/argparse`, reads defaults
from environment variables, and drives turns through
`bobzhang/openseek/agent.run_turn_in_scope` (both one-shot `run` and durable
sessions; fleet mode's independent attempts use `agent.run_turn_with_append`).

```
openseek [--prompt "…"]        interactive UI (default)
openseek tui [--prompt "…"]    the UI, explicitly
openseek run [options] TASK    run one task headlessly; JSONL events on stdout
openseek serve                 JSONL command server (stdin: prompt/steer/cancel/compact)
openseek review [--base REF]   read-only code review of REF...HEAD → one JSON report
openseek sessions list|show <id>|compact <id> …   manage durable sessions
```

The whole CLI is **one `moonbitlang/core/argparse` command tree**: the root's
default action is the interactive UI, and `tui`/`run`/`serve`/`review`/`sessions`
are subcommands (argparse owns parsing, `--help`, and rejecting unknown
subcommands). There is **no free-form top-level prompt** — a bare word that is
not a subcommand is rejected by the parser rather than silently opening the UI
with that word. (argparse does not yet suggest a near-miss subcommand the way it
does for options; that gap is tracked upstream in `moonbitlang/core`.) Only the
options shared with the engine (`--api-key`, `--model`, …) sit on the root, as
globals; the UI's own options (`--prompt`, `--engine`, `--continue`) live on the
`tui` subcommand, so launch the UI with an initial prompt via `openseek tui
--prompt "fix the bug"`.

## `openseek run`

```bash
moon run cmd/openseek -- run [--api-key sk-...] [--model deepseek-v4-pro] [--api-url https://api.deepseek.com/chat/completions] [--dir .] [--max-steps N] [--system-prompt-file prompt.md] [--system-prompt-addendum-file addendum.md] [--session session-id] [--session-root .openseek] "task text"
```

Runs require `--api-key` or the provider-specific environment variable:
`DEEPSEEK` for DeepSeek models, `KIMI` for Kimi models, and `GLM` for Z.AI GLM
models. `--model` can also be supplied with `OPENSEEK_MODEL`; it accepts
`deepseek-v4-flash`, `deepseek-v4-pro`, `kimi-k2.7-code`,
`kimi-k2.7-code-highspeed`, `glm-5.3`, and `glm-5.3-flash`, and defaults to
`deepseek-v4-pro`. `--max-steps` can also be supplied with
`OPENSEEK_MAX_STEPS`; when omitted, turns are bounded by the model's context
window instead of a step count. `--api-url` can also be supplied
with `OPENSEEK_API_URL`; when omitted, OpenSeek uses the official endpoint for
the model's provider.
`--dir` defaults to `.` and becomes the workspace root for relative prompt
files, sessions, workspace skills, and agent tools. If the directory itself is
missing but its parent exists, OpenSeek creates that final component and logs a
`workspace_created` event. Missing parents are rejected, so `--dir a/b/c`
creates only `c` when `a/b` already exists.
`--system-prompt-file` and `--system-prompt-addendum-file` can also be supplied
with `OPENSEEK_SYSTEM_PROMPT_FILE` and
`OPENSEEK_SYSTEM_PROMPT_ADDENDUM_FILE`. `--session` explicitly creates or
resumes that session under `--session-root` (default `.openseek`). Relative
session roots are resolved under `--dir`.
`--review-deadline` bounds one review audit (the model-callable `review` tool or
the `--review-gate` audit) to that many milliseconds; the default is 900000
(15 minutes).

Every run records a durable session: without `--session`, a generated
`cli-YYYYMMDD-HHMMSS-mmm` id is used and announced by a `session_started` event
on stdout, so the conversation is reviewable afterwards with `openseek sessions
list` / `openseek sessions show <id>` (or the viz server) and resumable with
`--session <id>`. Pass `--no-session` to run ephemerally; combining it with
`--session` is rejected.

Without an explicit prompt file, the CLI uses the default built-in prompt
(`prompt/default_prompt.mbt.md`) for the supported DeepSeek, Kimi, and GLM model
names. The older base prompt remains in `prompt/base_prompt.mbt.md` for
comparison and experiments, but it is not selected by default.

## `openseek sessions`

The session-management subcommands are offline and do not require `--api-key`:

```bash
moon run cmd/openseek -- sessions list --session-root .openseek
moon run cmd/openseek -- sessions list --format=json --session-root .openseek
moon run cmd/openseek -- sessions show parser-fix --session-root .openseek
moon run cmd/openseek -- sessions compact parser-fix --file summary.txt --from 1 --to 120
```

`sessions list --format=json` is the machine-readable form of the listing,
consumed by clients such as the desktop app's sidebar: one JSON array of
`{id, title, updated_at_ms}` objects, most recently active first. `title` is the
first line of the session's first user prompt; `updated_at_ms` is `null` for a
directory whose session files cannot be stat-ed (such husks sort last, like the
human-readable listing).

`sessions compact <id> --file <f> --from <n> --to <n>` appends a typed summary
event. It does not delete raw events from the session file;
`agent_session.Session::chat_messages` uses the summary to compact model context
on replay.

## `openseek serve`

In `serve` mode, controllers can ask the engine to generate and append a summary
without using a temporary file:

```jsonl
{"command":"compact"}
```

The engine handles this in command order, waits for any active turn to finish,
generates the summary with the configured model endpoint, appends a `Summary`
event covering the current session, and emits `compaction_started`,
`compaction_finished`, or `compaction_failed` JSONL events. With `--session`, the
summary is persisted to the durable session log. With `--no-session`, it only
updates the live in-memory session for the current serve process.

`serve` is what the terminal UI spawns for each session; it is also the stable
protocol for other integrations.

## Examples

```bash
export DEEPSEEK=sk-...
moon run cmd/openseek -- run "run moon test and summarize the result"
```

```bash
OPENSEEK_MODEL=deepseek-v4-flash moon run cmd/openseek -- run "inspect the package docs"
```

```bash
moon run cmd/openseek -- run --max-steps 200 "write tests, fix failures, and summarize"
```

```bash
moon run cmd/openseek -- run --dir ../another-workspace "run moon test"
```

```bash
moon run cmd/openseek -- run --session parser-fix "continue from the last run"
```

Best-of-N: run the same task in N sibling copies of `--dir` concurrently, each
recording its own session, then print a summary. The original `--dir` is never
written to (a present `--dir` is copied — keeping `.git` and `.openseek/skills`,
skipping `_build`/`node_modules` and the session store; an absent one yields
empty workspaces to build from scratch).

The copy is a plain filesystem copy: in-workspace file symlinks are dereferenced
(content copied), and a **linked git worktree/submodule** copy is *not* itself a
git checkout — its `.git` pointer is dropped so the copy can never write the
original repo. Each run's session lives under its run directory.

```bash
# 3 attempts at the same fix in dir_run_1 / dir_run_2 / dir_run_3
moon run cmd/openseek -- run --concurrency 3 --dir myproject "fix the failing test"
```

`run --concurrency` (env `OPENSEEK_CONCURRENCY`, default `1`) cannot be combined
with `--session` or `--no-session`.

## Package Boundary

This package should stay thin: subcommand dispatch, argument parsing,
environment-backed defaults, model parsing, prompt override file loading,
session-store setup, and delegation to the agent package. The interactive UI is
the `cmd/tui` library, launched via the `tui` subcommand; the prompt package owns
built-in prompt selection; the agent package owns tool definitions and the
execution loop.

Run the package tests with:

```bash
moon test cmd/openseek
```
