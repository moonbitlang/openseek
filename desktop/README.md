# SeekMoon

A [Proton](https://github.com/moonbit-community/proton) + [Rabbita](https://mooncakes.io/docs/moonbit-community/rabbita) desktop client for the OpenSeek agent, written in MoonBit.

Frontend changes must follow the durable interaction principles in
[`UX_GUIDELINES.md`](UX_GUIDELINES.md) and the visual and component conventions
in [`DESIGN.md`](DESIGN.md).

For reproducing and assessing UX issues with real components, follow
[`UX_REVIEW_WORKFLOW.md`](UX_REVIEW_WORKFLOW.md).

The native side is two modules. `backend` is a library and `app` is the
executable that hosts it:

- `backend/` — the backend itself, with no window toolkit: the engine host,
  the host operations, and the remote transports. Packages the window host
  imports sit at its top level; the rest stay under `backend/internal/`.
- `app/main.mbt` — the Proton window host: wires the window manifest, IPC
  extensions, per-user runtime directory, and launch log.

Inside them:

- `backend/api/` — the shared embedded/headless service, with process-owned
  actors and connection-owned watches. `ApiState::start_services` supplies the
  common embedded startup; the daemon owns the headless lifecycle.
- `backend/host_client/`, `backend/cli/`, `backend/headless_installer/` — SSH
  connection, durable daemon lifecycle, and verified package preparation.
- `app/internal/ssh/` — desktop host profiles, reconnect state, and window routing.
- `backend/engine/` — the native process owner: manages persistent
  engines, streaming, conversation storage, and workspace directories.
- `app/internal/extension/` — IPC command registration and bundled frontend asset lookup.
- `backend/internal/skillmarket/` — the mooncakes.io skill registry client and local skills-library manager.
- `backend/env/` — process-environment reads (blank means unset).
- `backend/internal/home/` — the user's home directory and `~` expansion.
- `backend/internal/userdirs/` — platform-specific Documents directory lookup.
- `backend/broadcast/` — native event fan-out to connected windows.
- `frontend/` — the standalone JS (Rabbita) UI module: the Elm-style model/update/view. It is itself the executable, shipped as `frontend.js` both inside the app and as the console bundle openseek-api serves.
- `protocol/`, `commands/`, `uri/`, and `file_search_*` — target-neutral
  packages owned directly by the root `desktop` module.
- `frontend/transcript/` — pure decoders from the engine's wire data to display items: engine events, session-list and session-replay replies, runtime updates.
- `frontend/markdown/` — markdown rendering for transcript content (cmark to Rabbita nodes, panic-guarded).
- `frontend/interop/` — the typed `@js` helpers shared by the frontend; no frontend package embeds raw JavaScript.

The native `backend` and JS `frontend` modules both depend on the root
`desktop` module. They do not depend on each other; backend packaging builds
the frontend workspace member separately and consumes its generated bundle.

## Remote SSH

Use **Add project** to choose Local, a saved SSH host, or **Add remote**.
Local and remote projects appear together in the same window. **Save and
continue** discovers an existing managed package on the SSH destination and
returns to its directory picker. Cancelling returns to the originating picker
and directory; switching locations restores each location's last directory.
Saved remote projects remain in the sidebar while disconnected, with an
explicit unavailable state and Retry instead of a stale directory listing.

For a fresh host, expand **Advanced** and choose **Prepare from local package**.
Supply a local headless package and a dedicated absolute remote data directory.
Preparation verifies, uploads and activates the package, then saves the host
only after it is Ready. Advanced settings also accept an existing absolute
launcher path and exact build ID. Profiles can be managed from **SSH hosts**
in Settings.
The current preparation workflow uses local development artifacts; it does not
download or publish a release. The working host needs Linux, glibc 2.35+,
Python 3.8+, getconf, `/usr/bin/base64`, an executable login shell and key-based
SSH access. OpenSSH config, known-host checking and ProxyJump/ProxyCommand remain
in effect. Agent forwarding is disabled. Worktree/subtask operations also require
Git with `worktree list --porcelain -z`; an unsupported Git is refused before
creation. See [building and installing headless packages](../scripts/headless/README.md)
for complete artifact and resource requirements.

Models, tools, workspaces, Git, search, LSP, session history and
schedules run on the selected host. Desktop windows, clipboard, browsers and
native panels stay local. A remote download explicitly saves a local copy;
remote paths are never interpreted as local paths. Project host badges and connection status show where work runs. Closing the window or application leaves accepted Agent
work and daemon schedules running. Integrated terminals use a separate
`ssh -tt` connection per tab, owned by the local window. The remote sshd
allocates the PTY; the headless app-server does not provide terminal endpoints.
Terminal input, resizing and output continue across app-server reconnections.
Closing a tab, reloading the page or closing its window releases its SSH process.
Terminals start in the selected checkout, including worktrees and resolved scratch
workspaces. File and language state resynchronize independently.

In remote Settings, endpoint/API-key changes affect that working host; local
credentials are not silently copied. Codex requires a separately installed CLI
on the remote service's PATH or an explicitly configured absolute executable.
Its account uses the host data directory's isolated CODEX_HOME. **Show remote
config and login** displays the configuration path and a command for that CLI.
Start `/bin/sh` in a remote terminal before running the command. Device-code
login requires account support; the browser sign-in action manages its callback
tunnel, while manual browser login requires the displayed port forwarding.
Click **Refresh** after terminal login. See [Codex integration](../docs/codex-app-server.md).

**Update from package** installs a selected package and switches only an idle
service. Finish or cancel active work before retrying Busy.
After successful activation, the corresponding host connection adopts the new profile. Cancelling
preparation after activation begins can leave the switch completed: inspect
status and upgrade records before retrying. Reconnecting does not refresh an
already running service's environment or change its selected Codex CLI.

On connection failure, inspect the displayed SSH diagnostic and check the same
alias with system SSH. A changed saved server identity requires investigation;
the client does not silently accept the replacement. An Unknown mutation result
must be reconciled with durable history before another submission. After an
unclean daemon exit, inspect recovery records and external tools before explicit
acknowledgement and restart; missing SSH connectivity is not evidence that work
stopped. See [HostClient diagnostics](backend/host_client/README.md) and
[daemon status/recovery commands](backend/cli/README.md).

## Sessions and streaming

Each conversation is served by one persistent `openseek serve` engine
process: the host spawns it on the conversation's first prompt and then talks
to it over stdio (`{"command": "prompt"|"cancel", ...}` JSONL in, the usual
event stream out). Because the process spans turns, stateful tools survive
turn boundaries — a `moon_check` watcher started in turn 1 keeps reporting in
turn 5 — and cancelling interrupts the turn without killing the engine.

Conversations run concurrently: the host keeps an engine per session id, so
starting a prompt in one conversation never waits on (or disturbs) another.
The frontend keeps per-conversation state — transcript, streaming buffers,
pending steers, composer draft — and routes every engine event by run id, so
you can switch away mid-turn, work elsewhere, and switch back to find the
stream where you left it. A running conversation shows a pulsing dot in the
sidebar. Changing the model, reasoning effort, API key, or endpoint replaces
an idle process before its next start, compaction, or goal; an engine that
dies mid-turn fails that run with
its stderr as diagnostics, and the next prompt respawns on the same durable
session. An engine left idle for twelve hours, with no background job
running, is stopped; the next prompt in that conversation starts a new one.

Each conversation is also backed by a durable engine session: the frontend
generates a `desktop-YYYYMMDD-HHMMSS-mmm` session id at launch and sends it
with every `start`, so the conversation survives the engine process and the
app. The sidebar's **New chat** button rotates to a fresh id — usable at any
time; a conversation that is still running keeps going in the background.
Sessions are stored under the `session_root` start-payload field, falling back
to `~/.openseek` (absolute, so a packaged app whose working directory is `/`
still works). They are interoperable with the CLI/TUI stores: resume one with
`openseek_tui --session-root ~/.openseek --session <id>`.

Each conversation also gets its own workspace directory, used as the engine's
working directory: `Documents/OpenSeek/<session-id>` (Documents as the
platform defines it — the Windows known folder, which OneDrive may relocate,
or the XDG documents folder on Linux; `~/OpenSeek/…` when no Documents folder
exists). The path is
derived from the session id alone — and desktop ids embed their creation
date, so a name-sorted listing reads chronologically — so resuming a
conversation returns to the same directory without recording it anywhere. The
directory is created on the conversation's first prompt, and the topbar
tooltip shows it next to the session id. Session event logs are app data and
stay under `~/.openseek`; the workspace holds only what the agent writes.

The sidebar lists every durable session in the store, newest first, titled by
the first user message (the host shells out to the bundled engine's
`sessions list --format=json`). Clicking one replays its event log into the
transcript — reasoning, tool cards, runtime notices, and error bubbles for
turns that were cancelled or failed — and points the conversation at that
session id, so the next prompt continues it with full context. The list
refreshes when the bridge connects and after each run. Switching while runs
are active is fine — a conversation already open in this app run switches
back instantly with its live state intact, without replaying the store.

While a turn runs, the Desktop renders `reasoning_delta` fragments as plain text
in one open activity card; no partial
Markdown is parsed on every token. `reasoning_message` seals that preview and
renders its complete text as Markdown. When the matching durable assistant
session event arrives, the same keyed card visually de-duplicates the sealed
preview without letting an untagged commit mutate run-scoped streaming state.
The host drains the session follower before each new model step and successful
terminal boundary, so an older commit cannot be mistaken for the next step and
a finish cannot outrun the canonical row. The UI likewise renders
`assistant_delta` as a live answer bubble, while durable `session.event`
commits remain the only permanent transcript source.
If the provider request fails and the engine decides to retry, `stream_retry`
clears both live previews and the heartbeat reads "Retrying · attempt 2/5 ·
reason" until the engine next reports progress on that request (a delta, the
response's usage, a tool result, or the next step). It leaves the
current model step and all durable rows untouched; the retry notice is live
state and is not written to `session.jsonl`.

After a successful OpenSeek turn leaves the engine idle, it generates and saves
one next-message prediction. The host broadcasts the completed result as
`agent.prediction` to all local and relay clients. Frontends do not request or
cancel predictions: an empty composer displays the matching suggestion, Tab
copies it into the draft without sending, and typing hides it only locally.
Clearing the draft restores it; reopening the conversation loads the saved
result. These auxiliary results never enter the transcript.

While a turn runs, the composer exposes a **Steer now / Queue next** selector
beside Send. It starts from Settings → Interface → Follow-up messages, applies
only to this message, and resets to that default after submission. Enter and
the send button use the same selection. Queue keeps the follow-up editable
and deletable above the composer until its turn starts; its Steer button can
apply it to the current turn instead. Editing a queued message exposes Save
and hides the selector. Codex mode currently retains its steer-only action.

Steer adds input to the current turn instead of starting a new prompt: the
text rides the serve engine's lossless steering queue and is folded into the
running turn at its next step boundary. The composer's action group grows
while a turn runs — the interrupt (■) stays available throughout, and typed
text adds the steer submit (↑) beside it, so steering never costs the ability
to stop. Each steer waits in a panel docked above the composer until the
engine settles it — `steer_applied` commits it into the transcript as a real
user message, while `steer_dropped` (the steer raced the turn's end through
the pipes) surfaces a notice asking to resubmit, so the text never vanishes
silently. A turn that is being cancelled cannot be steered; the text stays in
the composer.

## Skills

The sidebar's **Skills** button opens a browser over the
[mooncakes.io](https://mooncakes.io) skill registry — published MoonBit
packages that ship a `SKILL.md` playbook next to a runnable wasm entry point.
Installing one downloads just the `SKILL.md` (the wasm is fetched by `moon
runwasm` when the agent follows the playbook), verifies it against the
registry's sha256 digest, and writes it to the engine's global skills library
(`OPENSEEK_GLOBAL_SKILLS_DIR`, defaulting to `~/.openseek/skills`) as
`<slug>/SKILL.md` with a `.mooncakes.json` provenance marker. The engine
advertises the library in the system prompt of every **new** session — so
installed skills apply to new chats, and to the CLI/TUI as well, since the
library is shared.

The panel also lists what is already in the library. Hand-written skills are
shown but never touched: installs refuse to overwrite a same-named entry that
has no provenance marker, and only entries the app itself installed get an
Uninstall button.

## MCP servers

The agent can use tools from [MCP](https://modelcontextprotocol.io) servers
listed in `~/.openseek/mcp.json`, the `{"mcpServers": {...}}` shape described
in the repository README. The user file is created and edited by hand. The host
also automatically supplies its own tools through a generated `host-mcp.json`
in its runtime directory. The user file follows this default configuration,
so a same-named server in the user file replaces the default entry. When no
user file exists, `OPENSEEK_MCP_CONFIG` from the launching environment still
applies after the host defaults.

An engine connects its servers once, when it starts — one set of server
processes per conversation. The host therefore reads the file before each
prompt and keeps a digest of its content among the things that pin an engine
to its configuration, like the model and the endpoint: an edit starts a new
engine, and with it every server, on that conversation's next prompt, with no
desktop restart. A prompt already queued behind a running turn runs on the
engine it was queued for. Scheduled runs are pointed at the same file.

The engine reads the file itself, a moment after the host does. An edit that
lands in between leaves the engine on newer content than the host recorded,
which costs one more engine start than was needed on the next prompt; only an
edit that is also undone in that moment goes unnoticed until the file changes
again.

A configuration the engine cannot load, and a server that fails to start, to
list its tools, or to fit under the tool limit, raise an error toast naming
the cause; the conversation continues without those tools. A broken file is
reported once, however many conversations start engines on it. MCP tool calls
are not gated by the approval prompt, which only covers the built-in tools'
sandbox escalations. Codex conversations do not
read this file — Codex takes its MCP servers from its own `config.toml`.

### The app's own tools

The app offers tools of its own to the agents it runs, starting with the
dock's browser. An agent works with the Browser tabs of its own conversation:
`browser_tabs` lists them, `browser_open` opens a new one on an address, and
`browser_navigate` loads an address in one, steps back or forward in its
history, or reloads it. The engine connects directly to the host over MCP
Streamable HTTP and registers these tools automatically, including for scheduled
runs. No user configuration is required. To customize the host entry, put an
override like this in `~/.openseek/mcp.json`:

```json
{
  "mcpServers": {
    "seekmoon": {
      "url": "${OPENSEEK_DESKTOP_TOOLS_URL}",
      "headers": {
        "Authorization": "Bearer ${OPENSEEK_DESKTOP_TOOLS_TOKEN}"
      }
    }
  }
}
```

The tools reach the agent as `mcp__seekmoon__<tool>`. The host supplies the
address and conversation token in the engine's environment; no relay process
or credentials on disk are needed. The generated configuration stores only the
placeholders shown above. Outside a desktop-launched engine the variables are
absent, so this entry cannot load. To offer only browser
tools, add
`"X-SeekMoon-Tool-Groups": "browser"` to `headers`; multiple groups are comma
separated. Replace older `"command": "seekmoon", "args": ["mcp"]` entries
with the HTTP entry above; the relay executable is no longer packaged.
See `backend/mcp/README.md`.

## API endpoint

SeekMoon is bring-your-own-key: there is no hosted chat proxy, so requests
go straight from the machine running the host to the configured provider,
billed to that account. The default, **DeepSeek official**, sends requests
to `api.deepseek.com` with your own key; the engine also falls back to the
`DEEPSEEK` environment variable when no key is stored. **Z.AI GLM** sends
requests to `api.z.ai` with its own key (env fallback `GLM`) and offers the
GLM 5.3 models on the composer's model chip. **OpenRouter** configures its
canonical chat-completions endpoint through the existing custom backend; its
setup form only asks for an API key. Choose Flash or Pro in the composer, just
as with DeepSeek official. The shared request encoder maps each tier to its
OpenRouter id (`deepseek/deepseek-v4.1-flash`, `deepseek/deepseek-v4-pro`) and
translates the reasoning fields; Desktop keeps the same model preference for
both endpoints. **Custom URL**
accepts any other OpenAI-compatible chat-completions endpoint, with the key
optional — whether one is needed is the endpoint's business. The provider
choice, the custom URL, and the keys live in the host's settings store
(`engine-settings.json` in the runtime dir), shared by the desktop window
and every remote page; a key is never echoed back to a client, only its
presence. While no usable endpoint is configured, an API-setup modal opens
over the chat (the Settings page's API section lifted out of the page) and
the composer keeps Send disabled, with a notice saying why. The host passes
a custom endpoint to the engine as `OPENSEEK_API_URL`, substituting a
placeholder key when it is configured without one (the engine insists on a
non-empty key). Changing the endpoint mid-conversation retires that
conversation's engine process on the next prompt.

## Updates

After the webview connects, the host fetches the hosted release manifest
(`/desktop/releases/latest.json` on the SeekMoon relay origin, see
`internal/version` for the version it compares against) in the background.
On macOS, when the manifest lists a `macos-arm64` package and the running
bundle is Developer ID signed, the host downloads the zip, checks its
sha256 against the manifest, extracts it, and verifies that the new bundle is
notarized and has a valid code signature from the same team — only then does a
sticky toast offer "restart and update". The updater never removes the
`com.apple.quarantine` attribute to bypass Gatekeeper. Clicking the toast swaps
the bundle on disk (macOS allows renaming a running .app; the old one is parked
as `<name>.app.old` and removed on the next launch), the window closes through
the normal path, and `main` relaunches the new bundle via `open -n` after the
run loop exits. If the current installation cannot be replaced, the Update
button is not shown; a check or installation failure is reported in the
bottom-right notification area. Anything less than the fully verified path —
other platforms, dev binaries, or ad-hoc signatures — degrades to a toast that
opens the release page in the browser.

## Prerequisites

- The [`moon`](https://www.moonbitlang.com/download) toolchain.

No separate `openseek` engine is needed on your `PATH`: both packaging and the
development launcher build it from the monorepo's root CLI package.
Packaged apps run the bundled engine and MoonBit toolchain seed. The unbundled
development host runs that checkout's `_build` engine and resolves a local
MoonBit toolchain through the normal fallback chain.

## Setup

```sh
git clone <this-repo>
```

Proton is an ordinary registry dependency (`moonbit-community/proton` in
`backend/moon.mod`), so a plain clone is complete — `moon` resolves it like
any other package.

The desktop frontend imports the `moonbitlang/editor` workspace member from
`../editor`. Packaging reads its reusable CSS and codicon font from that same
checkout. The shared build program downloads fixed Mermaid and xterm browser
distributions plus a standalone esbuild executable and verifies their
checked-in SHA-256 digests; every desktop and browser package copies the local
outputs beside the frontend bundle, so end users never fetch Mermaid from a
CDN.
`viewer_theme.css` supplies the desktop-owned theme variables; the editor's
reference-shell theme remains development-only.

The file panel imports the pinned `Lampese/office-viewer` Mooncakes package.
Existing `.docx`, `.xlsx`, and `.pdf` paths open in the file panel and are read
as bounded binary payloads (up to 20 MiB). DOCX/XLSX use the standalone viewer's
`office.mbt` reader/layout pipeline. PDFs use its asynchronous PDF.js surface,
with page navigation, zoom, fit to width, rotation, search, and password prompts.
The Office/PDF controls and password prompts follow the application's language
setting. Preview and selection failures show a short message with retry guidance.
DOCX, XLSX, and PDF previews support trackpad pinch zoom and Ctrl+wheel, with
the toolbar percentage following the document's zoom. Ordinary two-finger
scrolling remains available. DOCX/XLSX use the existing 50–200% range and PDFs
use 25–400%; zooming keeps the document position under the pointer when the
scroll range permits it. Selecting content continues to work after zooming.
Selecting text in DOCX/PDF or a cell range in XLSX opens a preview showing its
content and page or sheet/range. **Add to context** keeps the quotation in the
active conversation; **Cancel** leaves the draft unchanged. Further selections
update the pending preview, while separately confirmed quotations accumulate.
Each quotation chip shows its file, location, and content excerpt, with the
selected text in its tooltip. PDF quotations retain a complete
file/hash/parser-bound PDF text-range reference. Image-only pages display
without OCR or selectable text.
The composer's **Attach files** action also accepts PDF, DOCX, and XLSX files
(up to 20 MiB), including clipboard and drop input. A native file already in
the conversation's workspace becomes a file reference immediately. Otherwise,
the composer asks before copying the original into
`.openseek/attachments/<id>/<filename>`; cancelling writes nothing, and the
source file is retained. Browser and remote attachments upload their bytes
after the same confirmation. Imported files are present before sending and
carried into a new task worktree when necessary. Click a file reference to
preview it and select the content to quote; attaching a document creates no
extracted-text or JSON sidecar.
Browser and desktop packages copy the metric-compatible Office fonts and the
accompanying copyright, license and modification notices from the published
`Lampese/office-viewer@0.1.3` package into the final web resource tree. The
browser-ready fonts retain the layout engine's glyphs and metrics and use
distinct internal names for the modified font programs. No separate font
checkout or duplicated font assets are needed.

Moon resolves the viewer from the published module declared in `moon.mod`;
packaging reads its PDF runtime and font assets from the resolved package.
The runtime and pinned PDF.js engine, worker, stylesheet, CMaps,
standard fonts, codecs, ICC profiles, and license are packaged in both hosts;
PDF previews do not fetch runtime resources from a CDN or require a sibling
Office Viewer checkout.

What still needs preparing, beyond the MoonBit packages:

- The native host links `libproton`, which in turn needs CEF. The Proton
  package ships `libproton` for each platform but not CEF, so the first native
  build assembles a runtime from the two — see "Run during development" below.
- The shared build program stages web files, the engine, ripgrep, licenses,
  and the MoonBit seed below `seekmoon/`. Packaged code asks Proton for its resource
  directory and resolves only this fixed relative tree.

## Build

Moon compiles programs, one sequential Node program assembles browser assets
and stages `seekmoon/`, and Proton owns the final package. Check the shared
program and all Moon compatibility entries with:

```sh
just desktop-build-scripts-check
```

Build the current host's debug package with `just desktop-package`. The
`just` recipe selects the existing platform-specific Moon entry, and that
entry forwards its arguments unchanged to `package/build.mjs`. See
[BUILD.md](BUILD.md) for file ownership, execution order, caching, and
validation limits.

## Run during development

From the monorepo root, run:

```sh
just desktop-dev
```

The shared program builds the frontend, viz application, and engine, then runs
`proton_cli dev --no-frontend --setup`. Proton prepares the CEF environment,
builds and launches the bare host. The CLI runs through `moonx`,
which fetches the published CLI into the registry cache rather than installing
anything, and installs the matching CEF runtime and subprocess helper into
Proton's user-level immutable store. That first setup may download a large
archive; later development and platform-package runs reuse the validated store
entries.

The executable in `package/dev` is only a compatibility entry. It accepts no
path or build-mode arguments and contains no build or launch implementation.

Development does not use Moon's `data_dir` and does not assemble a package
asset directory. `desktop-dev.html` is served with the repository as its asset
root: it loads the frontend straight from `_build`, the application's source
CSS, and the generated xterm files under `desktop/target/web/`. Mermaid loads
from the verified distribution staged under that same directory. Production
copies those outputs into the fixed package resource tree.

Desktop CSS conventions, including token scope and the single-owner form focus
contract, live in [`styles/README.md`](styles/README.md).

The launcher declares `desktop/` as Proton's development resource directory.
The host derives the checkout HTML and the fixed native/debug engine from that
directory without passing its executable through those APIs. The executable
location is still used for the worktree-local `desktop/target/dev-state` and
self-update, whose meaning genuinely depends on the running process. The
engine then finds the local MoonBit toolchain through the same deterministic
resolver as production: a bundled seed when one exists, otherwise `moon` on
`PATH`, then `~/.moon/bin`. The development launcher accepts no path arguments.

The shared build program remains the release-layout test. The `just` recipe
builds debug artifacts; release automation passes `--release` through the same
platform command. Package commands cache verified upstream archives below
`desktop/target/vendor-web/cache`; they do not require npm or `node_modules`.

## Test policy

Only add or change Desktop tests when the user explicitly asks. First warn that
agent-written tests can be useless or freeze the current implementation, and
ask which user-visible behavior, external contract, safety property, or prior
regression must be protected; stop if none is specified.

Assert actions against observable UI or host-boundary outcomes, not private
DOM/CSS, `data-*` attributes, timing or ordering constants, or copied fixture
text unless the user names it as part of the contract.

`just test-browser` from `desktop/` builds the browser-console bundle and
mounts the Desktop Rabbita application in Playwright Chromium. It checks
rendered DOM, keyboard and focus behavior, composer send/stop, conversation
creation/archive/restore, settings persistence, skill installation, Codex
login controls and first-turn start/stop, approval decisions, and
narrow-viewport layout without requiring a packaged Desktop host. The
repository root also exposes `just desktop-test-browser` as an alias.

When adding another command-line binary to the Desktop bundle, follow
[`package/README.md`](package/README.md). Copying a file into the package is
only one part of the contract: runtime lookup, child-process and integrated
terminal `PATH`, licensing, signing, platform dependencies, and installed
package smoke tests must move together.

Codex conversations appear beside OpenSeek conversations in the Desktop's
global left sidebar; selecting one uses the same main transcript/composer area,
backed by Codex's `app-server` mode and an isolated `CODEX_HOME` under the
app's per-user runtime directory (`~/Library/Application Support/SeekMoon/codex`
on macOS, `%LOCALAPPDATA%\SeekMoon\codex` on Windows,
`$XDG_DATA_HOME/SeekMoon/codex` on Linux). The Desktop never touches the
CLI's `~/.codex`: Codex account, config, threads, and worktrees in the Desktop
are separate from the CLI, and the first run requires a Desktop-side sign-in.
OpenSeek does not bundle the Codex CLI or store its credentials.
Both packaged and unbundled hosts resolve `codex` from the login-shell `PATH`;
when it is unavailable, the Codex section reports that status without affecting
OpenSeek conversations. See
[`docs/codex-app-server.md`](../docs/codex-app-server.md) for the process,
protocol, approval, and packaging contract.

## Package (Windows)

Build the Windows package on Windows with:

```powershell
cd desktop
moon run package/windows
```

The shared build program builds and verifies the application inputs under
`desktop/seekmoon/`, then calls Proton once to create the portable application,
ZIP, and NSIS outputs under `desktop/dist/`. Proton owns the CEF/runtime files,
package metadata, portable layout, compression, installer layout, and Windows
signing targets. Pass `--release` for optimized MoonBit artifacts. `--target`
is repeatable; for example, build only the portable application and ZIP with:

```powershell
moon run package/windows -- --release --target app --target zip
```

This does not require NSIS. Installer builds require Proton's NSIS dependency,
including `makensis.exe`, on `PATH`.

The Windows package also stages a read-only MoonBit toolchain seed under the
app bundle. At runtime the host copies that seed into the app's per-user
runtime directory, runs `moon bundle --all` and `moon bundle --target wasm-gc`
there, and passes the writable copy as `MOON_HOME` to the engine.

On Windows, the platform native stub embeds the MSVC linker directives that
select the GUI subsystem while retaining MoonBit's generated C `main` entry.
The Windows host requires an MSVC-compatible toolchain; MinGW and GCC-style
Clang are not supported. The shared program patches only the
packaged engine copy to the GUI subsystem; Proton performs the final package
work.

Inside every Windows output, application-owned resources have one fixed path:
`Resources/seekmoon/`, independent of machine and package format.

## Package (macOS)

The shared build program builds the `openseek` engine from the monorepo's
root CLI package and prepares the frontend and MoonBit toolchain inputs.
It delegates the App layout, CEF runtime, helper bundles, package metadata,
signing, ZIP, and DMG to `proton_cli package`. Build a debug app with:

```sh
just desktop-package
# Equivalent macOS entry from the repository root:
moon run ./desktop/package/macos
```

The app-only output is ad-hoc signed by Proton for local use. Codex is not part
of the application bundle or its signing list.

To build a distribution artifact, select `dmg` or `zip`:

```sh
cd desktop
moon run package/macos -- --release --no-open --target dmg
moon run package/macos -- --release --no-open --target zip
```

- `dist/SeekMoon.dmg` is for first-time installation. It
  contains the app and an `/Applications` shortcut so users can install by
  dragging the app into Applications.
- `dist/SeekMoon.app.zip` carries the same app for in-app
  updates.

`--target` is the compatible repeatable package option. The `dmg` and `zip`
targets always include the app bundle they package.

The bundled engine is built from the same checkout, so the desktop app and its
engine never drift out of version with each other.

The app also contains a read-only MoonBit toolchain seed under
`Contents/Resources`. The signed bundle is not modified on first launch; the
host initializes a writable copy under the per-user runtime directory before
setting `MOON_HOME` for the engine.

The `dmg` or `zip` targets fully ad-hoc sign the app bundle when no identity is
supplied. Such output runs on the build machine, but it is not a distributable
build that Gatekeeper will trust on another machine. For distribution, sign
with a Developer ID Application identity (hardened runtime and a secure
timestamp are applied automatically) and notarize:

```sh
# one-time: xcrun notarytool store-credentials openseek \
#   --apple-id you@example.com --team-id TEAMID --password <app-specific-pw>
moon run package/macos -- \
  --release --no-open --target dmg --target zip \
  --sign "Developer ID Application: Your Name (TEAMID)" \
  --notarize openseek
```

`--notarize` passes the configured keychain profile to Proton, which submits the
signed artifact, waits for approval, and staples the resulting ticket. Without
`--notarize`, the artifacts are not notarized; without `--sign`, the app is only
ad-hoc signed. Such outputs are not intended for distribution.

## Package (Linux)

The shared build program builds and verifies the same `seekmoon/` input tree,
then asks Proton to create the AppDir, CEF/runtime layout, launcher, RPATH, metadata, and
final AppImage under `desktop/dist/`. Build debug artifacts with:

```sh
just desktop-package
```

For an optimized AppImage, invoke the Linux entry from `desktop/`:

```sh
moon run package/linux -- --release
```

Build requirements: `pkg-config` plus the GTK3 and WebKitGTK dev packages
(`libgtk-3-dev` and `libwebkit2gtk-4.1-dev` on Debian/Ubuntu; `gtk3` and
`webkit2gtk-4.1` on Arch), and `curl` (used to fetch `appimagetool` on first
run if it is not already on `PATH`).

The AppImage bundles the desktop host, the engine, and the frontend assets,
plus a read-only MoonBit toolchain seed. The first engine run initializes a
writable toolchain copy under the per-user runtime directory and uses that as
`MOON_HOME`. The AppImage still links against the system WebKitGTK: running it
requires GTK3 and
`libwebkit2gtk-4.1` installed on the host system, which is the standard
arrangement for webview-based AppImages. If your system lacks FUSE2, run it
with `APPIMAGE_EXTRACT_AND_RUN=1`.
