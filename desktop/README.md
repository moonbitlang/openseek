# OpenSeek Desktop

A [Lepus](https://github.com/moonbit-community/lepus) + [Rabbita](https://mooncakes.io/docs/moonbit-community/rabbita) desktop client for the OpenSeek agent, written in MoonBit.

- `main.mbt` — entry point: wires the window manifest, the IPC extensions, the per-user runtime directory, and the launch log.
- `internal/host/` — the native host: keeps one persistent `openseek serve` engine per conversation, streams its JSONL events to the webview, exposes `connect` / `start` / `steer` / `cancel` / `list_sessions` / `load_session` commands plus the `skills_*` / `skill_*` ops backing the Skills panel.
- `internal/skillmarket/` — the mooncakes.io skill registry client and the local skills-library manager: catalog browsing, digest-verified installs into the engine's global skills directory, and uninstall of what the app itself installed.
- `internal/appdirs/` — the installed app's own footprint: bundled frontend, engine, and MoonBit seed lookup, plus the per-user runtime directory.
- `internal/sessiondirs/` — where conversations live on disk: per-session workspace directories and the durable session store root.
- `internal/env/` — process-environment reads (blank means unset).
- `internal/home/` — the user's home directory and `~` expansion.
- `internal/userdirs/` — the user's Documents folder, answered by each platform's authority: the Windows known folder, the XDG user-dirs override, or `~/Documents`.
- `internal/event/` — engine event decoding.
- `internal/menu/` — the macOS main menu (App/Edit/Window): macOS dispatches ⌘ key equivalents through the main menu and the webview library never creates one, so without it the editing shortcuts (⌘A/⌘C/⌘V, undo, quit) are silently dropped. No-op on other platforms.
- `frontend/` — the JS (Rabbita) UI bundled to `frontend.js`: the Elm-style model/update/view plus the command files talking to the host bridge.
- `frontend/transcript/` — pure decoders from the engine's wire data to display items: engine events, session-list and session-replay replies, runtime updates.
- `frontend/markdown/` — markdown rendering for transcript content (cmark to Rabbita nodes, panic-guarded).
- `frontend/interop/` — the typed `@js` helpers shared by the frontend; no frontend package embeds raw JavaScript.
- `lepus/` — the Lepus framework, vendored as a git submodule.

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
sidebar. Changing the model, API key, or endpoint retires that conversation's
process on its next prompt; an engine that dies mid-turn fails that run with
its stderr as diagnostics, and the next prompt respawns on the same durable
session. Idle engines stay alive until the app exits.

Each conversation is also backed by a durable engine session: the frontend
generates a `desktop-YYYYMMDD-HHMMSS-mmm` session id at launch and sends it
with every `start`, so the conversation survives the engine process and the
app. The sidebar's **New chat** button rotates to a fresh id — usable at any
time; a conversation that is still running keeps going in the background.
Sessions are stored under the first
of: the `session_root` start-payload field, `OPENSEEK_SESSION_ROOT`, or
`~/.openseek` (absolute, so a packaged app whose working directory is `/`
still works). They are interoperable with the CLI/TUI stores: resume one with
`openseek-tui --session-root ~/.openseek --session <id>`.

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

While a turn runs, the UI renders the engine's `reasoning_delta` /
`assistant_delta` events as live "Thinking" and answer bubbles with a
streaming caret; the committed `reasoning_message` / `assistant_message`
events then replace them with permanent transcript items.

Submitting while a turn runs steers it instead of starting a new prompt: the
text rides the serve engine's lossless steering queue and is folded into the
running turn at its next step boundary. The composer's button morphs while a
turn runs — an empty composer shows the interrupt (■), typed text turns it
into the steer submit (↑). Each steer waits in a panel docked above the
composer until the engine settles it — `steer_applied` commits it into the
transcript as a real user message, while `steer_dropped` (the steer raced
the turn's end through the pipes) surfaces a notice asking to resubmit, so
the text never vanishes silently. A turn that is being cancelled cannot be
steered; the text stays in the composer.

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

The settings popup offers three endpoints. The default, **OpenSeek**, routes
requests through `openseek-api.moonbitlang.cn` and needs no user API key, so
the app works out of the box. **DeepSeek official** sends requests straight
to `api.deepseek.com` with your own key (BYOK). **Custom URL** accepts any
DeepSeek-compatible chat-completions endpoint, with the key optional —
whether one is needed is the endpoint's business. The choice, the custom
URL, and the key persist in the webview's localStorage; the key entered for
the official endpoint is never sent to any other endpoint. The host passes
the endpoint to the engine as `OPENSEEK_API_URL`, substituting a placeholder
key when a custom endpoint is configured without one (the engine insists on
a non-empty key). Changing the endpoint mid-conversation retires that
conversation's engine process on the next prompt.

Requests to the OpenSeek proxy authenticate with a client token instead of a
user key: release packaging stamps it into the host from the packaging
machine's `OPENSEEK_CLIENT_TOKEN` (in CI, the secret of the same name), and
the host sends it as the bearer key for that endpoint only. Unstamped
development builds fall back to the placeholder key, which the proxy accepts
only while its `OPENSEEK_CLIENT_TOKENS` enforcement is off; set
`OPENSEEK_CLIENT_TOKEN` in the app's environment to test against an
enforcing proxy.

## Updates

After the webview connects, the host fetches the hosted release manifest
(`/desktop/releases/latest.json` on the OpenSeek proxy origin, see
`internal/version` for the version it compares against) in the background.
On macOS, when the manifest lists a `macos-arm64` package and the running
bundle is Developer ID signed, the host downloads the zip, checks its
sha256 against the manifest, extracts it, and verifies the new bundle's
code signature carries the same team — only then does a sticky toast offer
"restart and update". Clicking it swaps the bundle on disk (macOS allows
renaming a running .app; the old one is parked as `<name>.app.old` and
removed on the next launch), the window closes through the normal path,
and `main` relaunches the new bundle via `open -n` after the run loop
exits. Anything less than that fully verified path — other platforms, dev
binaries, ad-hoc signatures, a failed download — degrades to a toast that
opens the release page in the browser, and every check failure just means
no toast at all.

## Prerequisites

- The [`moon`](https://www.moonbitlang.com/download) toolchain.

No separate `openseek` engine is needed on your `PATH`: the packaging flow
builds the engine from the monorepo's `cmd/openseek` source and bundles it, and
the desktop app always runs that bundled engine alongside its bundled MoonBit
toolchain seed. Development uses the same bundle flow — see
[Run during development](#run-during-development).

## Setup

```sh
git clone <this-repo>
# From the repository root, initialize only the desktop's top-level submodules:
git submodule update --init desktop/lepus desktop/editor
```

Do not add `--recursive`: `desktop/editor` contains the reference-only `vscode`
and `codemirror` submodules. The desktop build does not use them, and cloning
them makes setup substantially slower.

Why the bootstrap is a little involved:

- `lepus/` and `editor/` are git submodules, so a plain clone does not contain
  their sources until those two top-level submodules are initialized.
- The clipboard extension uses Lepus build-time codegen. A fresh checkout must
  build and stage the Lepus CLI before the native app can compile.
- Windows native builds include WebView2 COM headers. The headers are not kept
  in the repository, so they must be installed from the Microsoft WebView2 NuGet
  package once per checkout.
- The desktop host expects `assets/index.html`, `assets/frontend.js`, and an
  `openseek` engine executable beside it when packaged.

## Build

Several Lepus extensions are generated at build time by a Lepus codegen CLI,
so a fresh checkout must stage that tool once:

```sh
( cd lepus && moon install ./cli --bin target/lepus-tools )
```

Re-run that command after every lepus submodule update (pull, rebase, branch
switch) — the staged binary is a build product of the checkout it was built
from, not of the current one. If the codegen itself changed, also run
`moon clean`: moon caches pre-build outputs by their *input* hash, so a stale
cache keeps replaying the old binary's output even after restaging. The
symptom of either staleness is `extensions/*/extension.g.mbt` showing up as
modified inside the submodule after a build; never commit that drift —
restage, clean, and rebuild until the submodule tree stays clean.

Then build the frontend bundle and the native binary:

```sh
moon build frontend --target js --release      # produce the JS bundle
cp _build/js/release/build/openseek_desktop/frontend/frontend.js frontend.js
moon build . --target native --release         # build the native binary
```

The native binary is written to
`_build/native/release/build/openseek_desktop/openseek_desktop.exe`.

## Run during development

Run the app through the packaging flow for your platform and launch the produced
bundle — for example, on macOS:

```sh
moon run --target native package/macos
open "dist/OpenSeek Desktop.app"
```

(Use `package/linux` for the AppImage or `package/windows` for the Windows
bundle; see the Package sections below.) The host resolves its frontend assets,
the `openseek` engine, and the bundled MoonBit toolchain seed relative to the
packaged layout, so running the bare `openseek_desktop` binary unbundled — or
pointing it at an `openseek` on `PATH` — is not supported. To iterate on the UI,
rebuild the frontend bundle and re-run the package command; the engine and seed
are rebuilt and re-staged from the same checkout, so the app never drifts out of
version with them.

## Bootstrap desktop submodules on Windows

The scripted Windows path is:

```powershell
moon -C desktop run --target native package/windows
```

It builds the Lepus codegen tool if needed, installs WebView2 SDK headers if
needed, builds the frontend and native host, builds the `openseek` engine from
the monorepo root, writes `dist/windows-x64/OpenSeek Desktop/`, and creates
`dist/OpenSeek Desktop-windows-x64.zip`.

The command takes no arguments and always builds every output: the
`dist/windows-x64/OpenSeek Desktop/` bundle directory, the
`dist/OpenSeek Desktop-windows-x64.zip` portable zip, and the
`dist/OpenSeek-Desktop-Setup.exe` NSIS installer.

To build the per-user NSIS installer, install NSIS so `makensis.exe` is on
`PATH`, or extract portable NSIS to
`desktop/dist/tools/nsis-3.12/makensis.exe`.

The installer installs under
`%LOCALAPPDATA%\Programs\OpenSeek Desktop`, creates Start Menu shortcuts,
offers optional desktop-shortcut and launch-after-install checkboxes, and
registers an HKCU uninstall entry, so it does not require administrator
privileges.

The Windows package also stages a read-only MoonBit toolchain seed under the
app bundle. At runtime the host copies that seed into the app's per-user
runtime directory, runs `moon bundle --all` and `moon bundle --target wasm-gc`
there, and passes the writable copy as `MOON_HOME` to the engine.

The manual steps below are useful when debugging the package script.

From the repository root, initialize the two top-level desktop submodules
without recursing into the editor's reference-only submodules. If Git for
Windows cannot run `git submodule` from PowerShell because Unix helper tools are
missing from `PATH`, run the command from Git Bash instead.

```powershell
git submodule update --init desktop/lepus desktop/editor
```

Install the Lepus codegen CLI:

```powershell
cd desktop\lepus
moon install ./cli --bin target/lepus-tools
```

Install WebView2 SDK headers used by Lepus native Windows sources:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\install_webview2_headers.ps1
cd ..
```

Build the frontend bundle, copy it to `frontend.js`, and build the native host:

```powershell
moon build frontend --target js --release
Copy-Item _build\js\release\build\openseek_desktop\frontend\frontend.js frontend.js
moon build . --target native --release
```

On Windows, `native_link_config.mjs` passes GUI subsystem linker flags to the
host executable so double-clicking `openseek-desktop.exe` does not open an extra
terminal window. It detects common compiler driver styles:

- `clang`/`clang++`: `-Wl,/SUBSYSTEM:WINDOWS -Wl,/ENTRY:mainCRTStartup`
- `clang-cl`/`cl`: `/link /SUBSYSTEM:WINDOWS /ENTRY:mainCRTStartup`
- MinGW/GCC: `-mwindows`

Set `OPENSEEK_DESKTOP_LINK_STYLE=clang`, `msvc`, or `mingw` to override the
auto-detection.

Build the `openseek` engine from the monorepo root:

```powershell
cd ..
moon build cmd/openseek --target native --release
cd desktop
```

For a runnable development bundle, place these files together:

```text
dist/windows-x64/OpenSeek Desktop/
  openseek-desktop.exe
  openseek.exe
  assets/index.html
  assets/frontend.js
```

The files come from:

```text
openseek-desktop.exe <- desktop/_build/native/release/build/openseek_desktop/openseek_desktop.exe
openseek.exe         <- _build/native/release/build/cmd/openseek/openseek.exe
assets/index.html    <- desktop/index.html
assets/frontend.js   <- desktop/frontend.js
```

The target machine also needs Microsoft WebView2 Runtime installed.

## Package (macOS)

`package/macos` runs all of the above (including the codegen bootstrap),
builds the `openseek` engine from the monorepo's `cmd/openseek` source, and
produces a signed `dist/OpenSeek Desktop.app` plus a zip:

```sh
moon run --target native package/macos
# or, from the monorepo root:
moon -C desktop run --target native package/macos
```

The bundled engine is built from the same checkout, so the desktop app and its
engine never drift out of version with each other.

The app also contains a read-only MoonBit toolchain seed under
`Contents/Resources`. The signed bundle is not modified on first launch; the
host initializes a writable copy under the per-user runtime directory before
setting `MOON_HOME` for the engine.

By default the bundle is ad-hoc signed: it runs on the build machine, but
Gatekeeper quarantines it everywhere else. For distribution, sign with a
Developer ID Application identity (hardened runtime and a secure timestamp
are applied automatically) and optionally notarize:

```sh
# one-time: xcrun notarytool store-credentials openseek \
#   --apple-id you@example.com --team-id TEAMID --password <app-specific-pw>
moon run --target native package/macos -- \
  --sign "Developer ID Application: Your Name (TEAMID)" \
  --notarize openseek
```

`--notarize` submits the zip with `notarytool --wait`, staples the ticket to
the app, and rebuilds the zip; without it the app is signed but unnotarized
(Gatekeeper still warns on other machines).

## Package (Linux)

`package/linux` runs the same build steps (including the codegen
bootstrap), builds the `openseek` engine from the monorepo's `cmd/openseek`
source, and produces `dist/OpenSeek-Desktop-linux-x86_64.AppImage`:

```sh
moon run --target native package/linux
# or, from the monorepo root:
moon -C desktop run --target native package/linux
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
