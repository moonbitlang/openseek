# bobzhang/openseek/cmd/tui

The OpenSeek terminal UI: a scrolling transcript with a live composer, built
on the reusable [`tui`](../../tui/README.md) controller package.

The TUI runs no agent code itself. For every submitted prompt it spawns the
engine binary (`openseek` from `PATH`; override with `--engine` or
`OPENSEEK_ENGINE`) and renders the engine's JSONL event stream: streamed
thinking and answer text move live on the activity line, each turn's reasoning
is kept as a dim `✻` transcript aside above its answer, and tool results land
as `⏺` blocks.

## Sessions

Every launch converses in a durable session — the engine only carries context
between prompts through the session store, so without one each prompt would be
an amnesiac one-shot. A generated id (`tui-YYYYMMDD-HHMMSS-mmm`, named in the
startup banner) stores the conversation under `--session-root` (default
`.openseek/`).

- `--continue` resumes the most recently active session.
- `--session <id>` resumes (or creates) a specific one; combining it with
  `--continue` is rejected.
- `openseek --session-list` (on the engine CLI) lists what is resumable.

## Configuration

`--api-key` (env `DEEPSEEK`) is required. `--model`, `--max-steps`,
`--thinking`, and `--reasoning-effort` mirror the engine's flags and are
forwarded to it through the environment, alongside the session settings.

The full flag reference lives in the executable help — verified verbatim in
[`tests/cram/tui.md`](../../tests/cram/tui.md).
