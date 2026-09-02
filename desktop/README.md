# SeekMoon

A [Proton](https://github.com/moonbit-community/proton) + [Rabbita](https://mooncakes.io/docs/moonbit-community/rabbita) desktop client for the OpenSeek agent, written in MoonBit.

Frontend changes must follow the durable interaction principles in
[`UX_GUIDELINES.md`](UX_GUIDELINES.md) and the visual and component conventions
in [`DESIGN.md`](DESIGN.md).

- `main.mbt` — entry point: wires the window manifest, the IPC extensions, the per-user runtime directory, and the launch log.
- `internal/engine/` — the native host: keeps one persistent `openseek serve` engine per conversation, streams its JSONL events to the webview, and owns where conversations live on disk (per-session workspace directories, the durable session store root, and archiving).
- `internal/extension/` — the IPC bridge registration: the `connect` / `start` / `steer` / `cancel` / `list_sessions` / `load_session` handlers, the `skills_*` / `skill_*` ops backing the Skills panel, and bundled frontend asset lookup.
- `internal/skillmarket/` — the mooncakes.io skill registry client and the local skills-library manager: catalog browsing, digest-verified installs into the engine's global skills directory, and uninstall of what the app itself installed.
- `internal/env/` — process-environment reads (blank means unset).
- `internal/home/` — the user's home directory and `~` expansion.
- `internal/userdirs/` — the user's Documents folder, answered by each platform's authority: the Windows known folder, the XDG user-dirs override, or `~/Documents`.
- `internal/event/` — engine event decoding.
- `internal/menu/` — the macOS main menu (App/Edit/Window): macOS dispatches ⌘ key equivalents through the main menu and the webview library never creates one, so without it the editing shortcuts (⌘A/⌘C/⌘V, undo, quit) are silently dropped. No-op on other platforms.
- `frontend/` — the JS (Rabbita) UI core: the Elm-style model/update/view plus the command files talking to the host bridge. Two thin shells bundle it: `frontend/desktop/` (the app's `frontend.js`) and `frontend/browser/` (the `browser.js` console bundle openseek-api serves).
- `frontend/transcript/` — pure decoders from the engine's wire data to display items: engine events, session-list and session-replay replies, runtime updates.
- `frontend/markdown/` — markdown rendering for transcript content (cmark to Rabbita nodes, panic-guarded).
- `frontend/interop/` — the typed `@js` helpers shared by the frontend; no frontend package embeds raw JavaScript.

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
session. Idle engines stay alive until the app exits.

Each conversation is also backed by a durable engine session: the frontend
generates a `desktop-YYYYMMDD-HHMMSS-mmm` session id at launch and sends it
with every `start`, so the conversation survives the engine process and the
app. The sidebar's **New chat** button rotates to a fresh id — usable at any
time; a conversation that is still running keeps going in the background.
Sessions are stored under the `session_root` start-payload field, falling back
to `~/.openseek` (absolute, so a packaged app whose working directory is `/`
still works). They are interoperable with the CLI/TUI stores: resume one with
`openseek tui --session-root ~/.openseek --session <id>`.

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

Submitting while a turn runs steers it instead of starting a new prompt: the
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

## API endpoint

SeekMoon is bring-your-own-key: there is no hosted chat proxy, so requests
go straight from the machine running the host to the configured provider,
billed to that account. The default, **DeepSeek official**, sends requests
to `api.deepseek.com` with your own key; the engine also falls back to the
`DEEPSEEK` environment variable when no key is stored. **Z.AI GLM** sends
requests to `api.z.ai` with its own key (env fallback `GLM`) and offers the
GLM 5.3 models on the composer's model chip. **Custom URL**
accepts any OpenAI-compatible chat-completions endpoint, with the key
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
development launcher build it from the monorepo's `cmd/openseek` source.
Packaged apps run the bundled engine and MoonBit toolchain seed. The unbundled
development host runs that checkout's `_build` engine and resolves a local
MoonBit toolchain through the normal fallback chain.

## Setup

```sh
git clone <this-repo>
```

Proton is an ordinary registry dependency (`moonbit-community/proton` in
`moon.mod`), so a plain clone is complete — `moon` resolves it like any other
package.

The desktop frontend imports the `moonbitlang/editor` workspace member from
`../editor`. Packaging reads its reusable CSS and codicon font from that same
checkout, and invokes the editor-owned Mermaid asset builder to download and
SHA-256-verify `mermaid@11.16.0`. Every desktop and browser package copies
that local ESM tree beside the frontend bundle, so MoonBit code and browser
assets cannot drift between registry and source versions and end users never
fetch Mermaid from a CDN. `viewer_theme.css` supplies the desktop-owned theme
variables; the editor's reference-shell theme remains development-only.

What still needs preparing, beyond the MoonBit packages:

- The native host links `libproton`, which in turn needs CEF. The Proton
  package ships `libproton` for each platform but not CEF, so the first native
  build assembles a runtime from the two — see "Run during development" below.
- The desktop host expects `assets/index.html`, `assets/app.css`,
  `assets/frontend.js`, the generated `assets/mermaid/` tree, and an
  `openseek` engine executable beside it when packaged.

## Build

Build the frontend bundle and the native binary:

```sh
moon build frontend/desktop --target js
cp ../_build/js/debug/build/openseek_desktop/frontend/desktop/desktop.js frontend.js
moon build . --target native         # build the native binary
```

The native binary is written to
`_build/native/debug/build/openseek_desktop/openseek_desktop.exe`. Add
`--release` to each build command for optimized output; those artifacts use the
corresponding `_build/*/release/` directories.

## Run during development

From the monorepo root, run:

```sh
moon run ./desktop/package/dev
```

The launcher detects the desktop workspace, builds the frontend, engine, and
native host with Moon's normal incremental build, prepares the Proton/CEF
runtime, and launches the bare host. Setup runs `proton_cli` through `moonx`,
which fetches the published CLI into the registry cache rather than installing
anything, and installs the matching CEF runtime and subprocess helper into
Proton's user-level immutable store. That first setup may download a large
archive; later development and platform-package runs reuse the validated store
entries.

The executable implementation lives in `package/dev`; it accepts no path or
build-mode arguments.

Development does not use Moon's `data_dir` and does not assemble a package
asset directory. `desktop-dev.html` is served with the repository as its asset
root: it loads the frontend straight from `_build`, imports the application's
split CSS through `desktop/app.css`, imports the editor's source styles as
separate files, and loads xterm's upstream browser files without esbuild.
Production packagers concatenate the application sources into
`desktop/app.generated.css` before copying it into their asset layouts.
Mermaid and xterm archives are downloaded, checksum-verified, and extracted
once under ignored `target/` directories; they are reused until their pinned
versions change.

Desktop CSS conventions, including token scope and the single-owner form focus
contract, live in [`styles/README.md`](styles/README.md).

The host recognizes its `_build/native/<profile>/build/openseek_desktop`
location and derives the checkout HTML, matching engine, and worktree-local
`desktop/target/dev-state` from it. Packaged layouts are checked first. The
engine then finds the local MoonBit toolchain through the same deterministic
resolver as production: a bundled seed when one exists, otherwise `moon` on
`PATH`, then `~/.moon/bin`. No frontend, engine, state, or toolchain path
argument is needed.

Platform package commands remain the release-layout test. They build debug
MoonBit artifacts by default; pass `--release` after `--` when you need
optimized artifacts.

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

The scripted Windows path is:

```powershell
moon -C desktop run --target native package/windows
```

It prepares the Proton/CEF runtime if needed, builds the frontend and native
host, builds the `openseek` engine from the monorepo root, writes
`dist/windows-x64/SeekMoon/`, and creates `dist/SeekMoon-windows-x64.zip`.

This development command builds debug MoonBit artifacts. Add `-- --release`
for an optimized bundle and archives.

Without additional arguments, the command builds every output: the
`dist/windows-x64/SeekMoon/` bundle directory, the
`dist/SeekMoon-windows-x64.zip` portable zip, and the
`dist/SeekMoon-Setup.exe` NSIS installer.

Use repeatable `--target` options to select `app`, `zip`, or `installer`.
The app bundle is always built; selecting `app` alone skips both distribution
archives. For example, build only the bundle and portable zip with:

```powershell
moon -C desktop run --target native package/windows -- --target zip
```

This still builds the bundle directory and portable zip, but does not require
NSIS and does not create `dist/SeekMoon-Setup.exe`.

To build the per-user NSIS installer, install NSIS so `makensis.exe` is on
`PATH`, or extract portable NSIS to
`desktop/dist/tools/nsis-3.12/makensis.exe`.

The installer installs under
`%LOCALAPPDATA%\Programs\SeekMoon`, creates Start Menu shortcuts,
offers optional desktop-shortcut and launch-after-install checkboxes, and
registers an HKCU uninstall entry, so it does not require administrator
privileges.

The Windows package also stages a read-only MoonBit toolchain seed under the
app bundle. At runtime the host copies that seed into the app's per-user
runtime directory, runs `moon bundle --all` and `moon bundle --target wasm-gc`
there, and passes the writable copy as `MOON_HOME` to the engine.

The manual steps below are useful when debugging the package script.

From the repository root, assemble the Proton/CEF runtime the native host
links against:

```powershell
moonx moonbit-community/proton_cli@<version> cef setup
```

`<version>` is whatever `moon.mod` pins `moonbit-community/proton` to; the
packagers read it from there rather than repeating it.

Build the frontend bundle, copy it to `frontend.js`, and build the native host:

```powershell
moon build frontend/desktop --target js --release
Copy-Item ..\_build\js\release\build\openseek_desktop\frontend\desktop\desktop.js frontend.js
moon build . --target native --release
```

On Windows, the platform native stub embeds the MSVC linker directives that
select the GUI subsystem while retaining MoonBit's generated C `main` entry.
The Windows host requires an MSVC-compatible toolchain; MinGW and GCC-style
Clang are not supported.

Build the `openseek` engine from the monorepo root:

```powershell
cd ..
moon build cmd/openseek --target native --release
cd desktop
```

For a runnable development bundle, place these files together:

```text
dist/windows-x64/SeekMoon/
  openseek-desktop.exe
  openseek.exe
  assets/index.html
  assets/app.css
  assets/frontend.js
```

The files come from:

```text
openseek-desktop.exe <- desktop/_build/native/release/build/openseek_desktop/openseek_desktop.exe
openseek.exe         <- _build/native/release/build/cmd/openseek/openseek.exe
assets/index.html    <- desktop/index.html
assets/app.css       <- desktop/app.generated.css (assembled from desktop/app.css imports)
assets/frontend.js   <- desktop/frontend.js
```

## Package (macOS)

`package/macos` runs all of the above (including the runtime preparation),
builds the `openseek` engine from the monorepo's `cmd/openseek` source, and
prepares the frontend and MoonBit toolchain inputs. It then delegates the App
layout, CEF runtime, helper bundles, package metadata, signing, ZIP, and DMG to
`proton_cli package`. The application-specific MoonBit artifacts are debug by
default, and the command produces `dist/SeekMoon.app`:

```sh
moon run --target native package/macos
# or, from the monorepo root:
moon -C desktop run --target native package/macos
```

The app-only output is ad-hoc signed by Proton for local use. Scripts may pass
`--target app` to request the same output explicitly. Pass `--release` after
`--` to build the frontend, host, and engine as optimized release artifacts.
Codex is not part of the application bundle or its signing list.

To build a distribution artifact, select `dmg` or `zip`:

```sh
moon run --target native package/macos -- --release --target dmg
moon run --target native package/macos -- --release --target zip
```

- `dist/SeekMoon.dmg` is for first-time installation. It
  contains the app and an `/Applications` shortcut so users can install by
  dragging the app into Applications.
- `dist/SeekMoon.app.zip` carries the same app for in-app
  updates.

`--target` is repeatable. The `dmg` and `zip` targets always include the app
bundle they package. With no `--target`, the command produces only the local app
bundle.

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
moon run --target native package/macos -- \
  --release \
  --target dmg \
  --target zip \
  --sign "Developer ID Application: Your Name (TEAMID)" \
  --notarize openseek
```

`--notarize` passes the configured keychain profile to Proton, which submits the
signed artifact, waits for approval, and staples the resulting ticket. Without
`--notarize`, the artifacts are not notarized; without `--sign`, the app is only
ad-hoc signed. Such outputs are not intended for distribution.

## Package (Linux)

`package/linux` runs the same build steps (including the runtime
preparation), builds the `openseek` engine from the monorepo's `cmd/openseek`
source, and produces `dist/SeekMoon-linux-x86_64.AppImage`. It builds debug
MoonBit artifacts by default:

```sh
moon run --target native package/linux
# or, from the monorepo root:
moon -C desktop run --target native package/linux
```

For an optimized AppImage, pass the package flag after Moon's `--` separator:

```sh
moon run --target native package/linux -- --release
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
