# OpenSeek Visualizer Server

`cmd/viz_server` is the native HTTP server for browsing recorded OpenSeek
sessions. It serves `web/index.html`, the compiled `cmd/viz_app` JavaScript
bundle, and read-only session JSONL APIs.

## Build

From the repository root, build before starting the server:

```sh
moon build
```

This builds both the native server and the JavaScript visualizer app. The server
auto-locates the frontend bundle from Moon's build output, normally:

```text
_build/js/debug/build/bobzhang/openseek-viz-app/openseek-viz-app.js
```

## Run

Start the server from the repository root:

```sh
moon run --target native cmd/viz_server
```

By default it listens on `127.0.0.1:8080`, serves `web/index.html`, and scans
the current directory recursively for `.openseek` session roots.

Useful options:

```sh
moon run --target native cmd/viz_server -- --port 8081
moon run --target native cmd/viz_server -- --search-dir path/to/project
moon run --target native cmd/viz_server -- --session-root-name .openroot
```

If the server cannot find the generated JavaScript bundle, pass it explicitly:

```sh
moon run --target native cmd/viz_server -- --bundle _build/js/debug/build/bobzhang/openseek-viz-app/openseek-viz-app.js
```
