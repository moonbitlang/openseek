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
## Module boundaries (observed)
- Root module `bobzhang/openseek` v0.3.1, `preferred_target = "native"` (`moon.mod:25`). The root `moon.pkg` sets only warnings — it declares no package and no `pkgtype`, so the root is not an executable (`moon.pkg:1`).
- `moon.work` splits the repo into 7 members: root, `./protocol`, `./cmd/viz_app`, `./inspect`, `./editor`, `./editor/server`, `./desktop` (`moon.work:2`).
- Layering named by the README package table: `deepseek` = pure chat data + provider-aware JSON encoding, `deepseek/client` = HTTP transport, `agent_*` = orchestration/session/tools, `cmd/openseek` = CLI (`README.md:75`).
- Editor and desktop are separately scoped workspaces; root Moon commands are the integration gate (`justfile:7`, `AGENTS.md:58`).

## One verified entry point
- `cmd/openseek/main.mbt:12` — `async fn main` calls `dispatch()`, which parses one argparse tree and switches on `run`/`serve`/`review`/`subrun`/`mcp`/`sessions` (`main.mbt:43-51`).
- `cmd/openseek/moon.pkg:44` declares `pkgtype(kind: "executable")` with `supported_targets = "+wasm+native"` (line 42).
- Conflict worth flagging: `cmd/openseek/README.md:3` calls this "native-only", while the manifest and root README (`README.md:14`) say native **and** wasm.

## Traced operation: chat-request encoding (two files)
`encode_chat_request` (`deepseek/json_encode.mbt:104`) assembles an ordered `Map` of `model`, `messages`, `stream`, then conditional `response_format`/`stream_options`/`tools`/thinking fields; the model's wire name comes from `Show for Model` (`deepseek/deepseek.mbt:59`). Each message is serialized by `ToJson for ChatMessage` (`json_encode.mbt:46`), where an assistant message with tool calls and empty content becomes JSON `null` (`json_encode.mbt:47-51`). Behavior is pinned by tests in the same file (`json_encode.mbt:134`, `:199`).

## Suggested reading order
`moon.work` → `moon.mod` → `AGENTS.md:10-16` → `README.md:70-82` → `cmd/openseek/README.md` → `cmd/openseek/main.mbt`. Build/test commands live in `justfile:7-33`.

## Not verified
- Only six file reads; the root README excerpt ends at line 82, so the package table is incomplete.
- `cmd/openseek/pkg.generated.mbti` and `agent/` internals were not read.
- No build, test, or `moon` command was run (forbidden here), so `justfile` recipes are unexecuted evidence only.

Supporting references (file/line checks, not claim verification):
- CHECKED: {"file":"moon.work","line":2,"note":"7 workspace members"}
- CHECKED: {"file":"moon.mod","line":25,"note":"root module identity and preferred target"}
- CHECKED: {"file":"moon.pkg","line":1,"note":"root manifest declares no package"}
- CHECKED: {"file":"README.md","line":75,"note":"package-boundary table: deepseek = pure data/encoding"}
- CHECKED: {"file":"cmd/openseek/moon.pkg","line":44,"note":"executable package type; supported_targets on line 42"}
- CHECKED: {"file":"cmd/openseek/main.mbt","line":12,"note":"async fn main entry point, dispatch on line 43"}
- CHECKED: {"file":"deepseek/json_encode.mbt","line":104,"note":"encode_chat_request; ChatMessage ToJson at line 46"}
- CHECKED: {"file":"deepseek/deepseek.mbt","line":59,"note":"Show for Model supplies the wire name"}

Not verified: Root README package table truncated at line 82, so packages listed after `agent_tool` were not inspected. cmd/openseek/pkg.generated.mbti not read. The native-only vs native+wasm discrepancy between cmd/openseek/README.md:3 and cmd/openseek/moon.pkg:42 is reported but not adjudicated (no build run). No executable was executed; the entry point is verified by source and manifest only. Other executables (cmd/viz_app, inspect, agent_workflow/fixit, eval/bgjobs_capability) were not examined.
## extension-points
INCOMPLETE: agent 'repo-map:extension-points' failed: subrun explore failed: Failure(deepseek/client/client.mbt:265:20-265:63@bobzhang/openseek FAILED: Model request failed: <@os_error.OSError: "@socket.Tcp::connect(): Operation timed out">. The retry limit was reached. Model: deepseek-v4-flash; stage: connect; attempts: 5/5; elapsed: 386303 ms)
scouts=2 replayed=0 tokens=106568
Failure(repo-map.mbtx:136:7-136:63@moon/test/single FAILED: repo-map incomplete; see the failed lenses above)
