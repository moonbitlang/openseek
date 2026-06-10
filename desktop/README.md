# OpenSeek Desktop

A [Lepus](https://github.com/moonbit-community/lepus) + [Rabbita](https://mooncakes.io/docs/moonbit-community/rabbita) desktop client for the OpenSeek agent, written in MoonBit.

- `main.mbt` — native host: spawns the `openseek` engine, streams its JSONL events to the webview, exposes `start` / `cancel` commands.
- `frontend/` — the JS (Rabbita) UI bundled to `frontend.js`.
- `internal/event/` — engine event decoding.
- `lepus/` — the Lepus framework, vendored as a git submodule.

## Sessions and streaming

Each conversation is backed by a durable engine session: the frontend generates
a `desktop-YYYYMMDD-HHMMSS-mmm` session id at launch and sends it with every
`start`, so consecutive prompts share context through the engine's session
store instead of running amnesiac one-shots. The sidebar's **New chat** button
rotates the id and clears the transcript. Sessions are stored under the first
of: the `session_root` start-payload field, `OPENSEEK_SESSION_ROOT`, or
`~/.openseek` (absolute, so a packaged app whose working directory is `/`
still works). They are interoperable with the CLI/TUI stores: resume one with
`openseek-tui --session-root ~/.openseek --session <id>`.

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
