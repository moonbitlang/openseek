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

## One server per set of sessions

Starting `inspect` on a port that is already taken does not fail when the
server holding it is an `inspect` for the same sessions (same `--session-root`
and search directories, compared by real path): it prints
`openseek viz: already serving these sessions at <url>` and exits 0. Any other
program on the port, or an `inspect` for other sessions, is still an error.
`GET /api/info` answers `{"server", "version", "identity"}` for exactly this
check.

`--ensure` is for tools that start `inspect` in the background, such as the
TUI:

```sh
moonx moonbitlang/inspect --ensure --watch --session-root .openseek
```

- It creates the session root if needed and derives a port from its real path
  (a window of 16 ports inside 41000–41899), so each project has a stable home.
  An explicit `--port` pins it instead.
- If an `inspect` for the same sessions already listens there, it prints that
  server's URL and exits 0. Otherwise it binds the port (only one process can,
  so two callers starting at once cannot both win) and serves.
- It listens on `127.0.0.1` only, and every route but `/api/info` needs the
  token from the printed URL (`?t=<token>`; opening that URL stores it in an
  HttpOnly cookie for the page's own requests) and a loopback `Host` header,
  which stops DNS-rebinding pages.
- It keeps `{port, token, version}` in `<session-root>/inspect.json`, readable
  only by you, for the next caller to find.
- It exits after 60 minutes without a request (`--idle-exit <minutes>`, 0 to
  never exit); a watching browser tab keeps it alive.
- It also exits once its session root is deleted, so a server started for a
  temporary directory (a test, a scratch run) does not outlive it.

Either way the last line it prints is `openseek viz: open <url>`, with
` (already running)` appended when it reused a server. Add `#s=<session id>`
to open a session directly.

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

## Trajectory waterfall

`GET /api/trajectory/<root session id>` folds one run — the root session plus
every `<root>-sr-N` sub-run it spawned — into a single JSON document: every
session, turn, model call, tool step, `.mbtx` script and its nested PTC calls,
background job and `job_wait` block on one millisecond axis, each with a start,
an end (absent while the work is still open) and a status.

The folding is derived from the durable `.jsonl` events alone, so it works on
old logs and needs no new log format. Two things are recovered rather than
stored: a child session's parent is its id (`<parent>-sr-N`), and the step that
spawned it is the parent's tool call that was open when the child's first event
landed. When no call covers that instant the child's turn hangs under the run
span itself, and the metadata says which rule placed it.

A `.mbtx` program's nested PTC calls arrive in the tool result's trace. When that
trace carries the unix milliseconds the call opened and ended — the PTC server
stamps both — the call is a real interval under the script; a call the program
never closed runs to the program's own end and reads as interrupted. A trace
written before those stamps existed keeps its zero-width marker at the script's
end, flagged `timing: unknown`, rather than a bar invented from nothing.

In the viewer, the `Trajectory` link in a session header opens the waterfall at
`#t=<root session id>`. The axis folds idle stretches into fixed slots by
default, so a run resumed the next morning still reads as one screen; a slot is
hatched and labelled with how long that stretch really was, and `Idle at scale`
switches the same axis to true wall-clock spacing. `--watch` keeps it live: a
run that has not finished is re-folded every poll and its newest span is drawn
to the reader's clock. A frozen `--export` archive bakes one document per run it
holds, so its runs offer the same link; a run it never saw has none, because
there is no server there to fold one.

`?cursor=<token>` makes that poll cheap. The reply carries a `cursor` that
stamps every participating file (mtime, seconds and nanoseconds, folded to one
short token); echoing it back asks "has anything moved?". When nothing has, the
answer is `{"unchanged": true, "cursor": "..."}` and the server reads no file
at all. Otherwise it re-reads only the files whose stamp moved and reuses the
parsed events of the rest, which is what keeps a long run's idle children off
the hot path. Lane labels come from those same events, so this route never pays
the sidebar's per-file prompt read.

## A job's own output

A background job's text is not in the session log — the log names the job and
records when it ran, and the bytes it wrote stay in their own file under
`<store>/sessions/<id>/jobs/<generation>/`. The waterfall's job rows ask for
them here:

`GET /api/sessions/<key>/jobs/<job>` answers
`{found, job, output}`, where `job` is the durable record narrowed to what a
reader draws — state (and exit code), command, size, whether the engine stopped
keeping the whole log — and `output` is one page of the file:
`{text, start_offset, next_offset, size, head_omitted, stale}`.

- Without a cursor the page is the **tail**, up to 64 KiB, so a 40 MB log still
  answers in one reply; `head_omitted` says earlier output exists and was not
  sent.
- `?cursor=<byte>` continues from where a page ended. That is how an open log
  follows a running job: the viewer re-asks on the same tick as the trace and
  appends what the file gained.
- `?start=<ms>` picks among generations. A legacy counter id (`bg-1`) repeats
  across a session's engine runs; the record whose `started_at_ms` is closest to
  the instant the waterfall drew the span wins. Without it the newest record
  answers.
- Pages are cut on UTF-8 boundaries, so a window that starts mid-character still
  decodes. A cursor the file outgrew (a rewritten or truncated log) answers
  `stale: true` with no text, and the viewer reads the tail again.
- No record, no output file, or a file that cannot be read answers with an
  `error` string; a directory of copied logs has no jobs directory beside it and
  says so. This route never writes, so pointing `inspect` at a live store stays
  safe.

## Standalone export

`--export <path>` writes a single self-contained HTML file with every discovered
session baked in, then exits without serving:

```sh
moon run inspect -- \
  --session-root path/to/archive --export sessions.html
```

The exported file inlines the compiled frontend bundle and bakes each API
response the server would return — the `/api/sessions` listing, one envelope per
session, and one `/api/trajectory/<root>` document per run the archive holds —
into a `window.__OPENSEEK_DATA__` map. The frontend answers its fetches from that
map before touching the network, so the file opens directly from disk
(`file://`), with no server and no network: the waterfall of an exported run is
as available as its session log. A run's document is keyed by its root and folds
the `<root>-sr-N` children beside it, so the archive's lanes match the live
ones. Because the bundle that understands these logs ships alongside them, an
export keeps rendering unchanged as the live `.jsonl` format and parser evolve —
it is a frozen archive, not a live view.

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
