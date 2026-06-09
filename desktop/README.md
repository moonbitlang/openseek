# OpenSeek Desktop

A [Lepus](https://github.com/moonbit-community/lepus) + [Rabbita](https://mooncakes.io/docs/moonbit-community/rabbita) desktop client for the OpenSeek agent, written in MoonBit.

- `main.mbt` — native host: spawns the `openseek` engine, streams its JSONL events to the webview, exposes `start` / `cancel` commands.
- `frontend/` — the JS (Rabbita) UI bundled to `frontend.js`.
- `internal/event/` — engine event decoding.
- `lepus/` — the Lepus framework, vendored as a git submodule.

## Prerequisites

- The [`moon`](https://www.moonbitlang.com/download) toolchain.
- The `openseek` engine on your `PATH` (used at runtime, and bundled by the packaging script).

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

`package_macos.mbtx` runs all of the above (including the codegen bootstrap) and
produces a signed `dist/OpenSeek Desktop.app` plus a zip:

```sh
moon run --target native package_macos.mbtx
```
