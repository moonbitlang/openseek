# bobzhang/openseek

OpenSeek is a small MoonBit foundation for an OpenAI-compatible coding agent
supporting DeepSeek, Kimi, and Z.AI GLM models. The module is split into pure
data, HTTP transport, agent orchestration, and a CLI entry point so request
encoding can be tested without network access.

For a picture of how the pieces fit together — module architecture, the core
data model, and the life of one agent turn — see
[`docs/architecture.md`](docs/architecture.md).

## Running without a checkout

`cmd/openseek` builds on both native and wasm, and mooncakes.io hosts a
prebuilt wasm binary for every published version. `moonx` fetches and caches it,
so the engine runs with no clone and no build:

```sh
moonx bobzhang/openseek/cmd/openseek --help
DEEPSEEK=sk-... moonx bobzhang/openseek/cmd/openseek run --no-session 'summarize this repo'
```

The coordinate is the package path, not the module: `bobzhang/openseek` alone
resolves to the root package, which is not an executable. Pin a release with
`bobzhang/openseek/cmd/openseek@0.3.1`, or take the newest with `@latest`.
Subprocesses, the filesystem, and HTTPS all work under `moonrun`, so the wasm
binary drives the same tools as the native one.

## Monorepo development

The root [`moon.work`](moon.work) develops OpenSeek, the desktop app, and the
[`moonbitlang/editor`](editor/README.md) source together. The editor keeps its
smaller `editor/moon.work` as a scoped entry point for editor-only builds and
browser tests; root Moon commands are the integration gate across both projects.

A fresh checkout needs the MoonBit toolchain and `just`; `just check` also
requires `jq` to inspect structured compiler diagnostics. The root integration
gates are:

```sh
just check              # native + JS workspace checks and formatting
just test               # native + JS workspace tests and OpenSeek cram tests
just build              # native + JS MoonBit builds
just editor-build       # editor web distribution and server
just editor-test        # editor-only tests on every supported target
just editor-test-browser
```

The editor browser suites additionally need Node.js 18 or newer, the locked npm
dependencies, and a Playwright-managed Chromium installation:

```sh
cd editor
npm ci
npx playwright install chromium
```

Linux hosts that lack Playwright's system dependencies can use the CI form,
`npx playwright install --with-deps chromium`.

Neither editor reference submodule is needed for the normal build, test, or
browser smoke gates. Initialize CodeMirror only for source-reference research;
initialize VS Code only for the opt-in editor performance suite:

```sh
git submodule update --init editor/codemirror # source-reference research
git submodule update --init editor/vscode     # opt-in performance suite
```

## Packages

| Package | Purpose | Docs |
| --- | --- | --- |
| `bobzhang/openseek` | Root package and module overview. | `README.mbt.md` |
| `bobzhang/openseek/deepseek` | Pure chat data, provider-aware JSON encoding, and response decoding. | `deepseek/README.mbt.md` |
| `bobzhang/openseek/deepseek/client` | HTTP transport (native or wasm) for supported chat-completions providers. | `deepseek/client/README.mbt.md` |
| `bobzhang/openseek/agent_runtime` | Agent task-group (native or wasm) and extensible runtime event queue. | `agent_runtime/README.mbt.md` |
| `bobzhang/openseek/agent_session` | Typed durable conversation state and DeepSeek message projection. | `agent_session/README.mbt.md` |
| `bobzhang/openseek/agent_session/store` | Native filesystem-backed append-only session store. | `agent_session/store/README.mbt.md` |
| `bobzhang/openseek/agent_session/log` | Lenient session-file reader: header plus events, with per-line error capture. | — |
| `bobzhang/openseek/agent_session/compact` | Context-checkpoint (compaction) request building and summary handling. | — |
| `bobzhang/openseek/agent_tool` | Tool registry, executor, output, and control-action types; one subpackage per built-in tool. | `agent_tool/README.mbt.md` |
| `bobzhang/openseek/agent_skill` | Workspace skills: markdown playbooks discovered from skill libraries and listed in the system prompt. | `agent_skill/README.mbt.md` |
| `bobzhang/openseek/jsonrpc` | Duplex JSON-RPC 2.0 client (concurrent requests, notifications, out-of-order replies). | — |
| `bobzhang/openseek/mcp` (+ `config`, `stdio`, `streamhttp`, `tools`) | MCP client: `mcp.json` decoding, stdio and Streamable HTTP transports, and the bridge that namespaces server tools into the registry. | — |
| `bobzhang/openseek/prompt` | Built-in system prompt text (generated from Markdown) and prompt-selection policy. | `prompt/README.mbt.md` |
| `bobzhang/openseek_protocol` | Typed engine event stream (own module): the `openseek run`/`serve` stdout wire contract, decodable on every backend. | `protocol/README.mbt.md` |
| `bobzhang/openseek_protocol/emit` | Writer for that stream (native or wasm): owns each event's log level. | `protocol/emit/README.mbt.md` |
| `bobzhang/openseek/agent` | OpenSeek agent loop (native or wasm) and local tool dispatch. | `agent/README.mbt.md` |
| `bobzhang/openseek/agent_review` | Read-only, compiler-grounded code-review engine behind `openseek review`. | `agent_review/README.mbt.md` |
| `bobzhang/openseek/cmd/openseek` | Headless automation CLI (`openseek`), built for native or wasm. | `cmd/openseek/README.md` |
| `bobzhang/openseek/cli` | Shared command-main helpers: the agent options (`--api-key`, `--model`, …) and failure-text sanitizer used by `openseek` and the out-of-tree `openseek_tui`. | — |
| `bobzhang/openseek/viz` | Browser viewer for durable session logs (JS). | `viz/README.md` |
| `bobzhang/inspect` (in `inspect/`, own module) | HTTP server (native or wasm) that serves the visualizer over recorded sessions. | `inspect/README.md` |
| `bobzhang/openseek-viz-app` (in `cmd/viz_app/`, own module) | JS entry point compiled into the visualizer bundle. | `viz/README.md` |
| `moonbitlang/editor` (in `editor/`, own module) | Reusable readonly editor plus its reference browser shell and server. | `editor/README.md` |
| `bobzhang/openseek/internal/{cli,workspace_path}` | Shared CLI accessors and workspace-path resolution for the command mains. | — |
| `bobzhang/openseek/testkit/filesystem` | JSON-backed virtual filesystem for tests and eval fixtures. | `testkit/filesystem/README.mbt.md` |
| `bobzhang/openseek/eval/report` | Shared Markdown/JSON report primitive for deterministic and model evals. | `eval/report/README.mbt.md` |
| `bobzhang/openseek/eval/tool_harness` | Deterministic host-side harness that dispatches every built-in tool. | `eval/tool_harness/README.mbt.md` |
| `bobzhang/openseek/eval/file_edit/cases` | Deterministic file-editing eval case definitions. | `eval/file_edit/README.md` |
| `bobzhang/openseek/eval/file_edit/harness` | Reusable file-editing eval runner, oracle, and reporter. | `eval/file_edit/README.md` |
| `bobzhang/openseek/eval/file_edit/cmd/main` | Native-only CLI wrapper for the file-editing eval harness. | `eval/file_edit/README.md` |
| `bobzhang/openseek/eval/prompt_task/harness` | Prompt-task eval: runs the real agent over isolated per-trial workspaces. | `eval/prompt_task/README.md` |
| `bobzhang/openseek/eval/session_analyzer` | Post-hoc session-log analyzer producing Markdown/HTML/JSON reports. | — |
| `openseek_desktop` (in `desktop/`, own module) | Desktop app: CEF shell (Proton, a registry dependency) plus a JS frontend driving the engine over JSONL. | `desktop/README.md` |

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

It depends on `moonbitlang/async/http` and builds on both native and wasm.

The `agent_tool` package exposes the local tool registry and typed executor
boundary. Tool executors return `ToolAction`: normal tools use
`Respond(ToolOutput(...))`, while control tools such as `finish` use
`Control(Finish(...))`.

The `agent_runtime` package owns loop-scoped task-group access and an extensible
event queue available to stateful tools.

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

The `cmd/openseek` package is the headless automation entry point — a subcommand
tree (`run`/`serve`/`review`/`subrun`/`mcp`/`sessions`). The interactive terminal
UI is the separate `openseek_tui` binary, maintained in its own repository,
[moonbitlang/openseek_tui](https://github.com/moonbitlang/openseek_tui). `openseek run` parses arguments and
runs the agent package. The agent sends DeepSeek native function tools and
supports eleven local tools: `mbtx` — both the scripting surface and the
command runner, spawning processes through the shell-free
`moonbitlang/async/shell` API, with
`job_output` and `job_stop` watching anything it detaches as a background job —
plus `read`, `edit`, `multi_edit`, `write`, `remove`, `plan`, `goal`, and
`finish`. There is no shell tool, so no command ever goes through a shell.

```bash
export DEEPSEEK=sk-...
moon run cmd/openseek -- run "inspect this project and finish with a short summary"
```

For Kimi models, set `KIMI` instead:

```bash
export KIMI=sk-...
moon run cmd/openseek -- --model kimi-k2.7-code-highspeed run "inspect this project"
```

For Z.AI GLM models, set `GLM`:

```bash
export GLM=...
moon run cmd/openseek -- --model glm-5.3 run "inspect this project"
```

`OPENSEEK_MODEL` is optional and defaults to `deepseek-v4-flash`.
`OPENSEEK_MAX_STEPS` is optional; when omitted, turns are bounded by the
model's context window (a checkpoint summary carries each turn into the
next) rather than a step count. Pass `--max-steps` to cap steps for one run.
`--thinking no|high|max` controls thinking mode and effort (default: high); GLM
maps `no` to its lowest supported effort because GLM 5.3 always reasons.
Pass `--dir <workspace>` to run one-shot commands against another workspace
while still launching from the current shell. The default is `.`; if the final
directory component is missing and its parent exists, OpenSeek creates it and
logs `workspace_created`.

## MCP Servers

OpenSeek can use tools from [MCP](https://modelcontextprotocol.io) servers.
Point `--mcp-config` (or `OPENSEEK_MCP_CONFIG`) at a JSON file in the de-facto
standard shape — an existing Claude/Cursor-style `mcp.json` works as-is:

```json
{
  "mcpServers": {
    "codex": { "command": "codex", "args": ["mcp-server"] },
    "remote": { "url": "https://example.com/mcp", "headers": { "Authorization": "Bearer …" } }
  }
}
```

A `command` entry is launched as a stdio subprocess (in the agent's workspace,
inheriting the environment plus any `env` overrides); a `url` entry speaks the
Streamable HTTP transport. Each server's tools join the agent's registry as
`mcp__<server>__<tool>` for `run`, `serve`, and the TUI (which forwards
`OPENSEEK_MCP_CONFIG` to its engine). A server that fails to start, handshake,
or list its tools is logged and skipped — MCP never breaks a session. Tool
results are size-capped, calls are bounded by a timeout, and tool names are
sanitized to the provider's function-name rules.

Validate a configuration without starting a session:

```bash
moon run cmd/openseek -- mcp --mcp-config mcp.json
```

Resources and prompts (the other MCP capabilities) are not consumed: openseek's
agent is tool-driven, and a server that wants to feed it context can expose a
tool. This keeps the surface small; revisit if a concrete need appears.

## Skills

Reusable markdown playbooks the agent loads on demand. A skill is a
`<name>.md` file or a `<name>/SKILL.md` directory layout with optional
`name:`/`description:` frontmatter. Two libraries are merged: the global one
(`~/.openseek/skills`, or `--global-skills-dir`) and the workspace one
(`.openseek/skills`), with workspace skills shadowing same-named global ones.
The system prompt lists each skill's name, description, and file path; the
agent reads the file before applying it. See `agent_skill/README.mbt.md`.

## Terminal UI

The interactive terminal UI is the `openseek_tui` binary, maintained in its own
repository: [moonbitlang/openseek_tui](https://github.com/moonbitlang/openseek_tui). It depends on this module
(`bobzhang/openseek` on mooncakes) for the agent, session, and provider
packages, and spawns the `openseek` engine built here in `serve` mode. Its
sessions are interoperable with the CLI's: `moon run cmd/openseek -- sessions
list` shows what is resumable from either.

See each package README for API boundaries, examples, and package-specific test
notes.

## Verified CLI Documentation (cram)

The CLI behaviour is documented as executable cram tests under `tests/`, built
and run with `moon cram test`. The wrapper compiles the native `cmd/*` packages
and exposes each on `PATH` as `<name>.exe` (e.g. `openseek.exe`).

- [`tests/cram/cli.md`](tests/cram/cli.md) — offline `openseek` subcommand
  examples (top-level and `run` help, and the `run`/`serve`/`sessions` behaviors).
  They make no network calls and run in CI via `moon cram test tests/cram`.
- [`tests/cram/subrun.md`](tests/cram/subrun.md) — the offline internal child-mode
  wire contract: JSON input on stdin, JSONL events on stdout, typed reports, and
  failure-event delivery. It uses the modelless `echo` kind and needs no API key.
- [`tests/live/deepseek.md`](tests/live/deepseek.md) — a real, non-mock DeepSeek
  round trip. It is opt-in (`DEEPSEEK=sk-... moon cram test tests/live`) and
  parses the agent's JSONL log with MoonBit itself: a `moon run -e` script reads
  the stream through the published [`moonbitlang/jsonl`](https://mooncakes.io/docs/moonbitlang/jsonl)
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
