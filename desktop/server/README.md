# Shared SeekMoon server

`openseek_desktop/server` runs the desktop backend without Proton. Terminal
clients and desktop windows share its engine processes, Codex app-server,
conversations, workspaces, schedules, settings, and notification stream. Every
connection owns its filesystem watches and PTYs.

Run it from the repository root:

```sh
moon build . desktop/server --target native
moon run desktop/server --target native -- \
  --engine _build/native/debug/build/moonbitlang/openseek/openseek.exe \
  --ready-file /tmp/seekmoon-server.json
```

The server binds loopback on port 27184, falling back to an available port
when needed. `--port 0` always chooses an available port. Its first stdout
line and the private ready file contain `url` (the JSON-RPC WebSocket),
`token` (this launch's authentication capability), and `entry_url` (the
desktop frontend URL). Readiness is published after backend initialization.

Native clients authenticate with `Cookie: seekmoon_session_<port>=<token>`
on the returned WebSocket URL.
The server retains the cookie and browser Origin checks used by Desktop's
existing development console.

To share this server with a desktop window, build the browser frontend and
visualizer, then supply their paths:

```sh
moon run desktop/package/browser --target native
moon build cmd/viz_app --target js
moon run desktop/server --target native -- \
  --engine _build/native/debug/build/moonbitlang/openseek/openseek.exe \
  --root desktop/dist/browser \
  --viz-shell web/index.html \
  --viz-bundle _build/js/debug/build/moonbitlang/openseek-viz-app/openseek-viz-app.js \
  --ready-file /tmp/seekmoon-server.json
```

Launch SeekMoon with `--server-url` set to `entry_url`, or set
`SEEKMOON_SHARED_SERVER_URL`. This window uses the server's frontend and backend.
Its token-bearing URL sets the session cookie before the WebSocket connects.
Opening the same URL in a system browser also works.

`--runtime-dir` chooses backend state, including isolated Codex state,
persisted relay sign-in, and exports. By default the server uses SeekMoon's
per-user application-data directory. Export saves a uniquely named HTML
file under `exports/`; Share uses the same authenticated upload as Desktop.
Both need `--viz-shell` and `--viz-bundle`. Missing assets produce an explicit
operation error while other features remain available.

The reusable `host.Server` API binds the same server inside another native
host, starts its services with `run`, and exposes the same connection details.
Cancelling its owner closes client sockets and their PTYs.

To build on a machine without Node or the Proton window runtime, use the
server's scoped workspace:

```sh
moon -C desktop/server build . --target native --release
```

Backend logs go to `openseek-server.log` in the runtime directory. SIGINT
and SIGTERM use the async runtime's cancellation handlers: services unwind,
client connections close, and their PTYs are reaped before exit.

Run the process smoke against that executable (Python 3 and Git required):

```sh
python3 desktop/server/smoke.py desktop/server/_build/native/release/build/openseek_desktop/server/server.exe
```

It isolates HOME and backend state, checks authenticated RPC and frontend
assets, then sends SIGTERM with a live PTY child and verifies it was reaped.
