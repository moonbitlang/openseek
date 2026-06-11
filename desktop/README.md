# OpenSeek Desktop

A [Lepus](https://github.com/moonbit-community/lepus) + [Rabbita](https://mooncakes.io/docs/moonbit-community/rabbita) desktop client for the OpenSeek agent, written in MoonBit.

- `main.mbt` — native host: keeps one persistent `openseek --serve` engine per conversation, streams its JSONL events to the webview, exposes `connect` / `start` / `steer` / `cancel` / `list_sessions` / `load_session` commands.
- `frontend/` — the JS (Rabbita) UI bundled to `frontend.js`.
- `internal/event/` — engine event decoding.
- `lepus/` — the Lepus framework, vendored as a git submodule.

## Sessions and streaming

Each conversation is served by one persistent `openseek --serve` engine
process: the host spawns it on the conversation's first prompt and then talks
to it over stdio (`{"command": "prompt"|"cancel", ...}` JSONL in, the usual
event stream out). Because the process spans turns, stateful tools survive
turn boundaries — a `moon_check` watcher started in turn 1 keeps reporting in
turn 5 — and cancelling interrupts the turn without killing the engine.
Switching conversations (or changing the model/API key) retires the old
process gracefully and spawns a fresh one; an engine that dies mid-turn fails
that run with its stderr as diagnostics, and the next prompt respawns on the
same durable session.

Each conversation is also backed by a durable engine session: the frontend
generates a `desktop-YYYYMMDD-HHMMSS-mmm` session id at launch and sends it
with every `start`, so the conversation survives the engine process and the
app. The sidebar's **New chat** button rotates the id and clears the
transcript. Sessions are stored under the first
of: the `session_root` start-payload field, `OPENSEEK_SESSION_ROOT`, or
`~/.openseek` (absolute, so a packaged app whose working directory is `/`
still works). They are interoperable with the CLI/TUI stores: resume one with
`openseek-tui --session-root ~/.openseek --session <id>`.

Each conversation also gets its own workspace directory, used as the engine's
working directory: `Documents/OpenSeek/<session-id>` (the XDG documents
folder on Linux; `~/OpenSeek/…` when no Documents folder exists). The path is
derived from the session id alone — and desktop ids embed their creation
date, so a name-sorted listing reads chronologically — so resuming a
conversation returns to the same directory without recording it anywhere. The
directory is created on the conversation's first prompt, and the topbar
tooltip shows it next to the session id. Session event logs are app data and
stay under `~/.openseek`; the workspace holds only what the agent writes.

The sidebar lists every durable session in the store, newest first, titled by
the first user message (the host shells out to the bundled engine's
`--session-list --format=json`). Clicking one replays its event log into the
transcript — reasoning, tool cards, runtime notices, and error bubbles for
turns that were cancelled or failed — and points the conversation at that
session id, so the next prompt continues it with full context. The list
refreshes when the bridge connects and after each run; switching is disabled
while a run is active.

While a turn runs, the UI renders the engine's `reasoning_delta` /
`assistant_delta` events as live "Thinking" and answer bubbles with a
streaming caret; the committed `reasoning_message` / `assistant_message`
events then replace them with permanent transcript items.

Submitting while a turn runs steers it instead of starting a new prompt: the
text rides the serve engine's lossless steering queue and is folded into the
running turn at its next step boundary. It shows as a dimmed pending bubble
until the engine settles it — `steer_applied` commits it as a real user
message, while `steer_dropped` (the steer raced the turn's end through the
pipes) surfaces a notice asking to resubmit, so the text never vanishes
silently. A turn that is being cancelled cannot be steered; the text stays in
the composer.

## Prerequisites

- The [`moon`](https://www.moonbitlang.com/download) toolchain.
- The `openseek` engine on your `PATH`, for running directly via `moon run` during development. (The packaging script no longer needs it — it builds the engine from the monorepo's `cmd/openseek` source.)

## Setup

```sh
git clone --recurse-submodules <this-repo>
# or, if already cloned:
git submodule update --init --recursive
```

Why the bootstrap is a little involved:

- `lepus/` is a git submodule, so a plain clone does not contain the framework
  sources until submodules are initialized.
- The clipboard extension uses Lepus build-time codegen. A fresh checkout must
  build and stage the Lepus CLI before the native app can compile.
- Windows native builds include WebView2 COM headers. The headers are not kept
  in the repository, so they must be installed from the Microsoft WebView2 NuGet
  package once per checkout.
- The desktop host expects `assets/index.html`, `assets/frontend.js`, and an
  `openseek` engine executable beside it when packaged.

## Build

The clipboard extension is generated at build time by a Lepus codegen CLI, so a
fresh checkout must stage that tool once:

```sh
( cd lepus && moon install ./cli --bin target/lepus-tools )
```

Then build the frontend bundle and the native binary:

```sh
moon build frontend --target js --release      # produce the JS bundle
moon run --target native build_frontend.mbtx   # copy it to ./frontend.js
moon build . --target native --release         # build the native binary
```

The native binary is written to
`_build/native/release/build/openseek_desktop/openseek_desktop.exe`.

## Bootstrap Lepus on Windows

The scripted Windows path is:

```powershell
moon run --target native .\desktop\package_windows.mbtx
```

It builds the Lepus codegen tool if needed, installs WebView2 SDK headers if
needed, builds the frontend and native host, builds the `openseek` engine from
the monorepo root, writes `dist/windows-x64/OpenSeek Desktop/`, and creates
`dist/OpenSeek Desktop-windows-x64.zip`.

The manual steps below are useful when debugging the package script.

From the repository root, initialize the Lepus submodule. If Git for Windows
cannot run `git submodule` from PowerShell because Unix helper tools are missing
from `PATH`, run the command from Git Bash instead.

```powershell
git submodule update --init --recursive desktop/lepus
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
moon run --target native build_frontend.mbtx
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

`package_macos.mbtx` runs all of the above (including the codegen bootstrap),
builds the `openseek` engine from the monorepo's `cmd/openseek` source, and
produces a signed `dist/OpenSeek Desktop.app` plus a zip:

```sh
moon run --target native package_macos.mbtx
# or, from the monorepo root:
moon run --target native ./desktop/package_macos.mbtx
```

The bundled engine is built from the same checkout, so the desktop app and its
engine never drift out of version with each other.

By default the bundle is ad-hoc signed: it runs on the build machine, but
Gatekeeper quarantines it everywhere else. For distribution, sign with a
Developer ID Application identity (hardened runtime and a secure timestamp
are applied automatically) and optionally notarize:

```sh
# one-time: xcrun notarytool store-credentials openseek \
#   --apple-id you@example.com --team-id TEAMID --password <app-specific-pw>
MACOS_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
MACOS_NOTARY_PROFILE=openseek \
moon run --target native package_macos.mbtx
```

`MACOS_NOTARY_PROFILE` submits the zip with `notarytool --wait`, staples the
ticket to the app, and rebuilds the zip; without it the app is signed but
unnotarized (Gatekeeper still warns on other machines).

## Package (Linux)

`package_linux.mbtx` runs the same build steps (including the codegen
bootstrap), builds the `openseek` engine from the monorepo's `cmd/openseek`
source, and produces `dist/OpenSeek-Desktop-linux-x86_64.AppImage`:

```sh
moon run --target native package_linux.mbtx
# or, from the monorepo root:
moon run --target native ./desktop/package_linux.mbtx
```

Build requirements: `pkg-config` plus the GTK3 and WebKitGTK dev packages
(`libgtk-3-dev` and `libwebkit2gtk-4.1-dev` on Debian/Ubuntu; `gtk3` and
`webkit2gtk-4.1` on Arch), and `curl` (used to fetch `appimagetool` on first
run if it is not already on `PATH`).

The AppImage bundles the desktop host, the engine, and the frontend assets,
but links against the system WebKitGTK: running it requires GTK3 and
`libwebkit2gtk-4.1` installed on the host system, which is the standard
arrangement for webview-based AppImages. If your system lacks FUSE2, run it
with `APPIMAGE_EXTRACT_AND_RUN=1`.
