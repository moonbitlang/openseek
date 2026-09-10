# Repository map
## Validation recipes (not executed)
Source: justfile. These are recipe definitions, not test results.
```just
default:
    just --list

# Check the two production targets together and verify repository formatting.
check:
    just check-prompt
    moon check --target native --deny-warn
    moon check --target js --deny-warn
    moon fmt --check

# Build every root workspace member for the production targets.
build:
    moon build --target native
    moon build --target js

# The runtime lives outside the repository in ~/.proton/store, keyed by the CEF
# archive digest and layout version pinned in the Proton release, so every
# Proton upgrade that moves either key is a cache miss. The resulting failure
# reads as a missing cef_browser_capi.h rather than a missing runtime.
# Install the CEF runtime Desktop's Proton dependency compiles against.
cef-setup:
    moonx moonbit-community/proton_cefsetup

# Serve recorded sessions in the browser; flags pass through to the server
# (e.g. just inspect --session-root path/to/sessions --port 8081).
inspect *args:
    moon build cmd/viz_app --target js
    moon run inspect -- {{ args }}

# Run workspace MoonBit tests plus the offline OpenSeek CLI documentation tests.
test: test-moon
    moon cram test tests/cram
    just test-turn-finish
    just test-workflows

# Real CLI lifecycle regression with an offline scripted model (Python 3).
test-turn-finish:
    moon build cmd/openseek --target native
    python3 tests/integration/turn_finish.py _build/native/debug/build/bobzhang/openseek/cmd/openseek/openseek.exe

test-moon:
    moon test --target native
    moon test --target js

# Refresh filesystem-derived prompt content even when only share/ changed.
prompt:
    moon run scripts/md_to_mbt_string -- prompt/default_prompt.mbt.md prompt/generated_default_prompt.mbt

check-prompt:
    moon run scripts/md_to_mbt_string -- --check prompt/default_prompt.mbt.md prompt/generated_default_prompt.mbt

# Import the latest markdown build (or a specified commit) and regenerate the prompt.
update-docs commit="latest":
    moon run scripts/update-moonbit-docs.mbtx {{quote(commit)}}

# Build the editor's web distribution and reference server in its scoped workspace.
editor-build:
    just --justfile editor/justfile build

# Run the editor's MoonBit tests on every target supported by its scoped workspace.
editor-test:
    just --justfile editor/justfile test

# Run the editor's required Playwright smoke and component suites.
editor-test-browser:
    just --justfile editor/justfile test-browser-smoke

# Run Desktop's Rabbita views in Chromium through the browser-console bundle.
desktop-test-browser:
    just --justfile desktop/justfile test-browser

# Parse Desktop's checked-in build scripts.
desktop-build-scripts-check:
    just --justfile desktop/justfile build-scripts-check

# Build the current host's Desktop package.
desktop-package:
    just --justfile desktop/justfile package

# Build and launch the unbundled Desktop host.
desktop-dev:
    just --justfile desktop/justfile dev

# Run the session viewer's Rabbita views in Chromium.
viz-test-browser:
    just --justfile cmd/viz_app/justfile test-browser

# Exercise bundled agent workflows against an offline child contract.
test-workflows:
    python3 tests/integration/workflows.py

```
Surveying architecture and one extension point with two read-only scouts…
## architecture
## Module boundaries (from manifests + README)

**Observed.** The root module `bobzhang/openseek` (moon.mod, `preferred_target = "native"`, version 0.3.1) depends on `moonbitlang/async`, `moonbitlang/x`, `moonbitlang/jsonl`, `bobzhang/openseek_protocol`, `rabbita`, `moonbitlang/editor`, `moonbitlang/workflow` (moon.mod:5). The workspace `moon.work:1` holds seven members: root `.`, `./protocol`, `./cmd/viz_app`, `./inspect`, `./editor`, `./editor/server`, `./desktop` — so `cmd/openseek`, `agent*`, `mcp`, `deepseek` are all packages of the *root* module, not separate workspace members.

README packages the split as: pure chat data (`deepseek`), HTTP transport (`deepseek/client`), orchestration (`agent_runtime`, `agent_session`), tools (`agent_tool` + one subpackage per built-in), entry point (`cmd/openseek`) (README.md:74).

## Executable entry point

**Observed.** `cmd/openseek/moon.pkg:44` declares `pkgtype(kind: "executable")`, and `moon.pkg:42` gives `supported_targets = "+wasm+native"`. Entry: `async fn main` at cmd/openseek/main.mbt:12, which calls `dispatch()`, whose argparse tree dispatches `run/serve/review/subrun/mcp/sessions` (main.mbt:44).

**Inference.** cmd/openseek/README.md:3 calls the package "native-only", which conflicts with `supported_targets = "+wasm+native"`; I did not build either target to settle it.

## One traced operation: MCP config → agent tools

`openseek mcp` / session startup path, two source files:
1. cmd/openseek/mcp.mbt:23 `resolve_mcp_tools` reads the `--mcp-config` path (`mcp_config_path`, :12) via `@fs.read_file` (:32); failures emit `McpConfigUnreadable` and return `[]` (:35).
2. It calls `@mcpconfig.decode(@json.parse(text))` (cmd/openseek/mcp.mbt:39), which lands at mcp/config/config.mbt:46 `pub fn decode`, a pure layer that requires an `mcpServers` object and dispatches per entry to `decode_server` (:58, stdio vs `url` HTTP variant). The returned servers feed `@mcptools.build` (cmd/openseek/mcp.mbt:46).

## Suggested reading order
README.md:70 → moon.work:1 → moon.mod:5 → cmd/openseek/moon.pkg → cmd/openseek/README.md → cmd/openseek/main.mbt:12 → agent/README.mbt.md → cmd/openseek/mcp.mbt.

## Not verified
No commands were run (read-only survey); `just check/test/build` (justfile:6) were not executed. I did not read `agent/`, `desktop/`, `editor/`, or `inspect/` sources.

Supporting references (file/line checks, not claim verification):
- CHECKED: {"file":"moon.work","line":1,"note":"workspace member list"}
- CHECKED: {"file":"moon.mod","line":5,"note":"module name/deps/version"}
- CHECKED: {"file":"README.md","line":74,"note":"package purpose table"}
- CHECKED: {"file":"cmd/openseek/moon.pkg","line":44,"note":"pkgtype executable"}
- CHECKED: {"file":"cmd/openseek/moon.pkg","line":42,"note":"supported_targets +wasm+native"}
- CHECKED: {"file":"cmd/openseek/main.mbt","line":12,"note":"async fn main entry"}
- CHECKED: {"file":"cmd/openseek/mcp.mbt","line":39,"note":"resolve_mcp_tools calls @mcpconfig.decode"}
- CHECKED: {"file":"mcp/config/config.mbt","line":46,"note":"pub fn decode implementation"}

Not verified: Not inspected: the agent turn loop (agent/agent.mbt, turn_loop.mbt), desktop/, editor/, inspect/, and cmd/openseek's run/serve handlers beyond the dispatch table at main.mbt:44 — so the run_task_command → agent.run_turn_in_scope link rests on cmd/openseek/README.md:8, not on read source. cmd/openseek/README.md:3 calls the CLI native-only while cmd/openseek/moon.pkg:42 lists wasm+native; no build was run to resolve this. cmd/openseek's pkg.generated.mbti is empty (no public symbols), so no re-export surface was available. No build/test/install commands were executed.
## extension-points
# Extension point: `agent_runtime`'s extensible runtime event queue

**Named in README** — "`agent_runtime` … extensible runtime event queue" (`README.md:77`, restated at `README.md:130`).

**Definition (observed)** — `pub(all) extenum AgentEvent {}` at `agent_runtime/runtime.mbt:27`. Its doc comment states the intent: because it is an `extenum`, "tool packages can add their own event constructors without making `agent_runtime` depend on those tools"; the runtime stores/drains values opaquely (`agent_runtime/runtime.mbt:19`). Transport is `emit_event` → bounded lossy queue (`agent_runtime/exports.mbt:40`, capacity in `agent_runtime/exports.mbt:16`) and `drain_events` (`agent_runtime/exports.mbt:25`).

**Hypothetical additive feature** — a tool package declaring its own variant, e.g. `agent_tool/bgjobs` adding `BgJobProgress(…)/BgJobFinished(…)` and calling `runtime.emit_event(...)` at step boundaries. Implementation lives in that tool package (e.g. `agent_tool/bgjobs/wait.mbt`), *not* in `agent_runtime`; the in-repo precedent is the same-file extension `extenum AgentEvent += { RuntimeTestEvent(String) }` at `agent_runtime/runtime.mbt:190`. No `agent_runtime` edit is required (inference from the extenum contract and its doc).

**Existing test of the extension (observed)** — `test "runtime drains queued events"` at `agent_runtime/runtime.mbt:195`: it emits the extended variant and asserts it comes back from `drain_events` (lines 198–205). The sibling lossiness test at `agent_runtime/runtime.mbt:215` floods the bus and asserts `drain_events().length() == default_agent_event_capacity` (`:229`).

**Suggested reading order** — `README.md:77` → `agent_runtime/pkg.generated.mbti` (public surface: `AgentEvent`, `emit_event`, `drain_events`) → `agent_runtime/runtime.mbt:16-27` + `:190` → `agent_runtime/exports.mbt` → the embedded tests at `runtime.mbt:195`/`:215`. Relevant recipes visible in `justfile:41` (`moon test --target native`) and `justfile:7` (`moon check --target native --deny-warn`); `agent_runtime` declares `supported_targets = "+wasm+native"` (`agent_runtime/moon.pkg:8`).

## Not verified
No production caller of `emit_event` outside `agent_runtime` was inspected, so I cannot claim which tool package currently exercises this path; the only observed consumer is the embedded test above.

Supporting references (file/line checks, not claim verification):
- CHECKED: {"file":"README.md","line":77,"note":"names agent_runtime's extensible runtime event queue"}
- CHECKED: {"file":"agent_runtime/runtime.mbt","line":27,"note":"pub(all) extenum AgentEvent {} definition"}
- CHECKED: {"file":"agent_runtime/runtime.mbt","line":19,"note":"doc: tool packages add their own event constructors"}
- CHECKED: {"file":"agent_runtime/runtime.mbt","line":190,"note":"in-repo extenum extension: AgentEvent += RuntimeTestEvent"}
- CHECKED: {"file":"agent_runtime/runtime.mbt","line":195,"note":"embedded test of the selected extension: drains queued events"}
- CHECKED: {"file":"agent_runtime/runtime.mbt","line":215,"note":"sibling lossiness test vs default_agent_event_capacity"}
- CHECKED: {"file":"agent_runtime/exports.mbt","line":40,"note":"emit_event uses lossy try_put"}
- CHECKED: {"file":"agent_runtime/exports.mbt","line":16,"note":"default_agent_event_capacity = 32"}

Not verified: No production/exported caller of AgentRuntime::emit_event outside agent_runtime was inspected (budget spent on the definition, its tests, and the package interface), so which tool package currently emits AgentEvents — and whether any does — is unknown. Only the embedded test at agent_runtime/runtime.mbt:195 is confirmed as a consumer of an added AgentEvent variant. agent_runtime/README.mbt.md was not read, so its own framing of the extension point is unverified. No build/test command was executed (read-only survey).
scouts=2 replayed=0 tokens=114414
