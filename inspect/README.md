# OpenSeek Inspect

`inspect` (module `moonbitlang/inspect`) is the HTTP server for browsing recorded
OpenSeek sessions. It serves `web/index.html`, the compiled `cmd/viz_app`
JavaScript bundle, and read-only session JSONL APIs. It builds for the wasm
backend (the default — it compiles noticeably faster, since native also pays
C-stub compilation and linking) and for native.

## Run without a checkout

The published package carries the viewer shell and a release frontend bundle
inside the binary, so it runs anywhere through `moonx`, from the directory
whose sessions you want to browse:

```sh
moonx moonbitlang/inspect --watch --host 127.0.0.1
```

Outside a checkout the server serves its built-in copies and ignores any
`web/` or `_build/` in the current directory; `--web-dir` and `--bundle` still
override them explicitly.

## Build

From the repository root, build before starting the server:

```sh
moon build
```

This builds both the server and the JavaScript visualizer app. The server
auto-locates the frontend bundle from Moon's build output (freshest artifact by mtime wins, so a stale release build never shadows a fresh debug one; an explicit --bundle overrides), normally:

```text
_build/js/debug/build/moonbitlang/openseek-viz-app/openseek-viz-app.js
```

## Run

The one-command path from the repository root — refreshes the frontend bundle,
then starts the server, passing any flags through:

```sh
just inspect --session-root path/to/sessions --port 8081
```

Or directly (the server itself compiles on demand; only the bundle needs a
prior `moon build`):

```sh
moon run inspect
```

This runs the wasm build under `moonrun`. To run the native build instead:

```sh
moon run --target native inspect
```

Note that `moon test inspect` follows the same default: under wasm only the
pure white-box tests run; the full suite (async server tests) needs
`moon test --target native inspect`, which is what CI runs.

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
moon run inspect -- --port 8081
moon run inspect -- --host 127.0.0.1   # local only
moon run inspect -- --search-dir path/to/project
moon run inspect -- --session-root path/to/copied-jsonl-dir
moon run inspect -- --session-root-name .openroot
```

Session rows come from files named `openseek_session-*.jsonl`. The server
ignores `.DS_Store`, lock files, and malformed/husk directories, and it can
serve a normal `.openseek` store, a directory of copied JSONL files, or a single
matching JSONL file.

## Watch

`--watch` (or `OPENSEEK_VIZ_WATCH=1`) keeps the browser live while sessions are
being written, for example by the TUI or `openseek serve`:

```sh
moon run inspect -- --watch --host 127.0.0.1
```

The served page re-checks the open session every second, sending the log size
it already has (`GET /api/sessions/<key>?known_bytes=N`). While the size is
unchanged the server answers `{"found": true, "unchanged": true, ...}` without
the log; once the log grows the page re-renders with the new events. A reader
at the bottom of the log follows it; one scrolled up stays put. The session
list refreshes every few seconds so new sessions appear. The setting is handed
to the page as `window.__OPENSEEK_WATCH_MS__` in the served shell, so a
standalone export never polls.

## Standalone export

`--export <path>` writes a single self-contained HTML file with every discovered
session baked in, then exits without serving:

```sh
moon run inspect -- \
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
moon run inspect -- --bundle _build/js/debug/build/moonbitlang/openseek-viz-app/openseek-viz-app.js
```

## Publishing

Bump `version` in `moon.mod`, then dispatch the `publish-inspect` workflow. It
runs `node scripts/publish.mjs inspect`, which builds the release frontend
(`moon build --target js --release cmd/viz_app`), stages this package, and
overwrites the staged `generated_assets.mbt` with `web/index.html` and that
bundle (`scripts/embed_inspect_assets.mjs`) before `moon publish`. The copy of
`generated_assets.mbt` in git stays empty, so the 2 MB bundle never enters the
history, and a checkout build keeps serving the files from disk. To build
exactly what would be published without publishing it:

```sh
node scripts/publish.mjs inspect --stage-only /tmp/inspect
cd /tmp/inspect && MOON_WORK=off moon build --target wasm --release
```

The staged package compiles against the `moonbitlang/openseek` release named in
this module's `moon.mod`, so publish the root module first when `inspect`
needs its newer APIs.
