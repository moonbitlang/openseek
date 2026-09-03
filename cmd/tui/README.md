# bobzhang/openseek/cmd/tui

The OpenSeek terminal UI: a scrolling transcript with a live composer, built on
the reusable [`tui`](../../tui/README.md) controller package. It ships as a
library launched by the dedicated `openseek_tui` binary (a thin executable
package that builds this package's `cli_command`); the headless engine is the
separate `openseek` binary.

The UI runs no agent code itself. It spawns the `openseek` engine — by default
the `openseek` CLI binary, re-launched in `serve` mode (so the UI and engine can
never drift out of sync), resolved from `argv[0]` when invoked by path (rewriting
`openseek_tui` to `openseek`) and otherwise from `PATH`; override with `--engine`
— **once per session** and drives it over stdin commands, rendering the engine's
JSONL event stream: streamed thinking and answer text move live on the activity
line, each turn's reasoning is kept as a dim `✻` transcript aside above its
answer, and tool results land as `⏺` blocks. Pressing Enter while a task runs
steers it mid-turn; Ctrl-C cancels the turn (a second Ctrl-C kills the engine,
and the next prompt respawns it on the same session).

A custom or recorded-stream engine that only speaks the original
one-process-per-prompt protocol works with `--engine-mode oneshot`; it spawns
`<engine> run --session=<id>
--session-root=<root> -- <task>` per prompt, steering is unavailable, and it
requires an explicit `--engine` (re-launching the `openseek_tui` binary in
oneshot would only lose steering for no gain).

Because the UI takes over the terminal, launching it without a TTY (a pipe, CI
log, or cron) is refused with a pointer to `openseek run` / `openseek serve`.

## Sessions

Every launch converses in a durable session — the engine only carries context
between prompts through the session store, so without one each prompt would be
an amnesiac one-shot. A generated id (`tui-YYYYMMDD-HHMMSS-mmm`, named in the
startup banner) stores the conversation under `--session-root` (default
`.openseek/`).

- `--continue` resumes the most recently active session.
- `--session <id>` resumes (or creates) a specific one; combining it with
  `--continue` is rejected.
- `openseek sessions list` lists what is resumable.

## Configuration

`--api-key` or a provider-specific key env is required: `DEEPSEEK` for DeepSeek
models, `KIMI` for Kimi models, and `GLM` for Z.AI GLM models. `--model`, `--api-url`,
`--max-steps`, and `--thinking` mirror the engine's flags and are forwarded to
it through the environment, alongside the session settings.

The full flag reference lives in the executable help — verified verbatim in
[`tests/cram/tui.md`](../../tests/cram/tui.md).
