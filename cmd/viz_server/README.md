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

By default it listens on `0.0.0.0:8080` (all interfaces), serves
`web/index.html`, and scans the current directory recursively for `.openseek`
session roots. On startup it prints both the loopback URL and this machine's LAN
URL, so another machine on the same network can open it directly:

```
openseek viz: open http://127.0.0.1:8080 (this machine)
openseek viz: open http://192.168.1.42:8080 (LAN, reachable from other machines)
```

Because the default binds to all interfaces, anything on your network can read
the served sessions (the server is read-only). To restrict it to this machine,
bind to loopback with `--host 127.0.0.1` (or set `OPENSEEK_VIZ_HOST`).

Useful options:

```sh
moon run --target native cmd/viz_server -- --port 8081
moon run --target native cmd/viz_server -- --host 127.0.0.1   # local only
moon run --target native cmd/viz_server -- --search-dir path/to/project
moon run --target native cmd/viz_server -- --session-root path/to/copied-jsonl-dir
moon run --target native cmd/viz_server -- --session-root-name .openroot
```

Session rows come from files named `openseek_session-*.jsonl`. The server
ignores `.DS_Store`, lock files, and malformed/husk directories, and it can
serve a normal `.openseek` store, a directory of copied JSONL files, or a single
matching JSONL file.

## Standalone export

`--export <path>` writes a single self-contained HTML file with every discovered
session baked in, then exits without serving:

```sh
moon run --target native cmd/viz_server -- \
  --session-root path/to/archive --export sessions.html
```

The exported file inlines the compiled frontend bundle and bakes each API
response the server would return — the `/api/sessions` listing plus one envelope
per session — into a `window.__OPENSEEK_DATA__` map. The frontend answers its two
fetches from that map before touching the network, so the file opens directly
from disk (`file://`), with no server and no network. Because the bundle that
understands these logs ships alongside them, an export keeps rendering unchanged
as the live `.jsonl` format and parser evolve — it is a frozen archive, not a
live view.

If the server cannot find the generated JavaScript bundle, pass it explicitly:

```sh
moon run --target native cmd/viz_server -- --bundle _build/js/debug/build/bobzhang/openseek-viz-app/openseek-viz-app.js
```
