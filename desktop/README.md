# OpenSeek Desktop

A [Lepus](https://github.com/moonbit-community/lepus) + [Rabbita](https://mooncakes.io/docs/moonbit-community/rabbita) desktop client for the OpenSeek agent, written in MoonBit.

- `main.mbt` — native host: keeps one persistent `openseek --serve` engine per conversation, streams its JSONL events to the webview, exposes `connect` / `start` / `cancel` / `list_sessions` / `load_session` commands.
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

The sidebar lists every durable session in the store, newest first, titled by
the first user message (the host shells out to the bundled engine's
`--session-list-json`). Clicking one replays its event log into the
transcript — reasoning, tool cards, runtime notices, and error bubbles for
turns that were cancelled or failed — and points the conversation at that
session id, so the next prompt continues it with full context. The list
refreshes when the bridge connects and after each run; switching is disabled
while a run is active.

While a turn runs, the UI renders the engine's `reasoning_delta` /
`assistant_delta` events as live "Thinking" and answer bubbles with a
streaming caret; the committed `reasoning_message` / `assistant_message`
events then replace them with permanent transcript items.

## Prerequisites

- The [`moon`](https://www.moonbitlang.com/download) toolchain.
- The `openseek` engine on your `PATH`, for running directly via `moon run` during development. (The packaging script no longer needs it — it builds the engine from the monorepo's `cmd/openseek` source.)

## Setup

```sh
git clone --recurse-submodules <this-repo>
# or, if already cloned:
git submodule update --init --recursive
```

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
