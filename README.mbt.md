# bobzhang/openseek

OpenSeek is a small MoonBit foundation for a DeepSeek-backed coding agent. The
module is split into pure data, HTTP transport, agent orchestration, and a CLI
entry point so request encoding can be tested without network access.

## Packages

| Package | Purpose | Docs |
| --- | --- | --- |
| `bobzhang/openseek` | Root package and module overview. | `README.mbt.md` |
| `bobzhang/openseek/deepseek` | Pure DeepSeek chat data, JSON encoding, and response decoding. | `deepseek/README.mbt.md` |
| `bobzhang/openseek/deepseek/client` | Native-only HTTP transport for DeepSeek chat completions. | `deepseek/client/README.mbt.md` |
| `bobzhang/openseek/agent_runtime` | Native-only agent task-group and extensible runtime event queue. | `agent_runtime/README.mbt.md` |
| `bobzhang/openseek/agent_session` | Typed durable conversation state and DeepSeek message projection. | `agent_session/README.mbt.md` |
| `bobzhang/openseek/agent_session/store` | Native filesystem-backed append-only session store. | `agent_session/store/README.mbt.md` |
| `bobzhang/openseek/agent_tool` | Tool registry, executor, output, and control-action types. | `agent_tool/README.mbt.md` |
| `bobzhang/openseek/agent` | Native-only OpenSeek agent loop and local tool dispatch. | `agent/README.mbt.md` |
| `bobzhang/openseek/cmd/openseek` | Native-only command-line entry point. | `cmd/openseek/README.md` |
| `bobzhang/openseek/testkit/filesystem` | JSON-backed virtual filesystem for tests and eval fixtures. | `testkit/filesystem/README.mbt.md` |
| `bobzhang/openseek/eval/report` | Shared Markdown/JSON report primitive for deterministic and model evals. | `eval/report/README.mbt.md` |
| `bobzhang/openseek/eval/tool_harness` | Deterministic host-side harness that dispatches every built-in tool. | `eval/tool_harness/README.mbt.md` |
| `bobzhang/openseek/eval/file_edit/cases` | Deterministic file-editing eval case definitions. | `eval/file_edit/README.md` |
| `bobzhang/openseek/eval/file_edit/harness` | Reusable file-editing eval runner, oracle, and reporter. | `eval/file_edit/README.md` |
| `bobzhang/openseek/eval/file_edit/cmd/main` | Native-only CLI wrapper for the file-editing eval harness. | `eval/file_edit/README.md` |

The `deepseek` subpackage is pure and exposes chat data plus JSON helpers:

- `Model` and `Role`
- `ChatMessage(role, content=...)` with strongly typed `Role` values
- `ToolDefinition(name, description, parameters, strict?)` for native tool calls
- `ChatResponse` with `FromJson` response decoding

It has no HTTP dependency and is suitable for blackbox tests and portable
request/response handling.

The `deepseek/client` subpackage exposes the HTTP client:

- `Client(api_key~, model?, api_url?)`
- `Client::chat(messages, tools?)`

It depends on `moonbitlang/async/http` and is native-only.

The `agent_tool` package exposes the local tool registry and typed executor
boundary. Tool executors return `ToolAction`: normal tools use
`Respond(ToolOutput(...))`, while control tools such as `finish` use
`Control(Finish(...))`.

The `agent_runtime` package owns loop-scoped task-group access and an extensible
event queue used by stateful tools such as `moon_check`.

The `agent_session` package owns typed durable conversation state, append-only
session events, JSON round-tripping, and projection from a session into
DeepSeek chat messages. It is separate from TUI transcript rendering so
resumable sessions can be type-safe and process-independent. The native
`agent_session/store` package persists those sessions as a small header plus an
append-only JSONL event log.

The `agent` subpackage contains the OpenSeek agent loop, native DeepSeek
tool-call handling, and local tool dispatch. It depends on `deepseek/client`,
filesystem, and process APIs.

## Agent CLI

The `cmd/openseek` package is the CLI entry point. It parses arguments and runs
the agent package. The agent sends DeepSeek native function tools and supports
six local tools: `shell`, `read`, `edit`, `write`, `moon_check`, and `finish`.

```bash
export DEEPSEEK=sk-...
moon run cmd/openseek -- "inspect this project and finish with a short summary"
```

`DEEPSEEK_MODEL` is optional and defaults to `deepseek-v4-pro`.
`OPENSEEK_MAX_STEPS` is optional and defaults to `1000`; pass `--max-steps` on
the CLI to override it for one run.

See each package README for API boundaries, examples, and package-specific test
notes.

## Verified CLI Documentation (cram)

The CLI behaviour is documented as executable cram tests under `tests/`, built
and run with `moon cram test`. The wrapper compiles the native `cmd/*` packages
and exposes each on `PATH` as `<name>.exe` (e.g. `openseek.exe`, `tui.exe`).

- [`tests/cram/cli.md`](tests/cram/cli.md) — offline `cmd/openseek` examples (the
  full help banner and the missing-API-key error). They make no network calls,
  use no output-processing tools, and run in CI via `moon cram test tests/cram`.
- [`tests/cram/tui.md`](tests/cram/tui.md) — offline `cmd/tui` examples (the help
  banner and the missing-API-key error). The argument parser runs before the
  terminal UI starts, so these need no API key and no TTY.
- [`tests/live/deepseek.md`](tests/live/deepseek.md) — a real, non-mock DeepSeek
  round trip. It is opt-in (`DEEPSEEK=sk-... moon cram test tests/live`) and
  parses the agent's JSONL log with MoonBit itself: a `moon run -e` script reads
  the stream through the published [`bobzhang/jsonl`](https://mooncakes.io/docs/bobzhang/jsonl)
  package and asserts on typed `Json` values — no `jq` — without pinning
  nondeterministic content such as token counts or model phrasing.

For the evaluation-backed roadmap, see
[`agent-improvement-guide.md`](agent-improvement-guide.md). It explains why the
next highest-ROI work is semantic CLI validation, native CLI/error-handling
guidance, MoonBit command routing, shaped IDE output, and manifest/debug/edit
guardrails.

The file-editing eval harness is available under `eval/file_edit`. It runs the
real agent against isolated fixtures and checks exact final file state, making
it suitable for cheap Flash baselines such as 8 successful edits out of 10.

The deterministic tool harness under `eval/tool_harness` exercises each built-in
tool through `agent_tool.execute_tool_call` with temporary fixtures. It is meant
for ordinary `moon test` coverage of tool wiring and observable side effects,
not for model quality scoring.

The `testkit/filesystem` package provides reusable JSON-backed text fixtures for
mock tests and evals. It materializes flat path-to-content JSON objects under a
temporary root and compares listed files against disk.
