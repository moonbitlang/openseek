# OpenSeek native host protocol

This document describes the protocol owned by the OpenSeek Desktop native
process. It covers the shared method catalog, JSON-RPC WebSocket transport,
durable session delivery, and the outbound relay connection.

It does not add the browser transport to the frontend, mobile layout, sign-in,
or Remote access product UI. The desktop page continues to use Proton's
in-process command extension through a temporary compatibility profile.

## Process boundary

The native process owns:

- engine processes and their durable session followers;
- filesystem watchers and language servers;
- the Proton command-extension connection;
- the relay control WebSocket and every relayed client WebSocket;
- one notification hub shared by the Proton and WebSocket transports.

The process runs these owners as actors for the application lifetime. Request
callbacks post work or call the shared dispatcher; they do not own long-lived
connections, subprocesses, language servers, or filesystem watchers.

The actors are:

- `DesktopBridgeActor`: the current Proton page attachment;
- `EngineActor`: serve processes and durable session followers;
- `FsWatchActor`: the requested root and active watcher;
- `LspPoolActor` plus `LspServerActor`: language-server processes;
- `RelayActor` plus one `WsClientActor` per relayed client.

Closing the Proton application returns from `app.run`; the enclosing task group
then cancels these actors together.

## Shared method catalog

The Proton extension and every client WebSocket call the same dispatcher.
Catalog method names use dotted namespaces:

- `agent.start`, `agent.cancel`, `agent.steer`, `agent.compact`, `agent.runs`
- `session.list`, `session.load`, `session.list_archived`,
  `session.archive`, `session.unarchive`
- `settings.get`, `settings.set`
- `workspace.list`, `workspace.add`, `workspace.remove`
- `git.branch`
- `fs.read_file`, `fs.read_directory`, `fs.list_files`, `fs.stat_files`,
  `fs.watch`, `fs.unwatch`, `fs.browse`
- `lsp.open`, `lsp.hover`, `lsp.workspace_symbols`
- `skills.catalog`, `skills.install`, `skills.installed`, `skills.uninstall`
- `update.check`, `update.download`, `update.apply`
- `app.list`, `app.launch`
- `host.open_path`, `host.meta`

Method parameters are always JSON objects. Optional fields are omitted rather
than encoded as empty sentinel values.

The host owns engine endpoint credentials and WSL settings. They are persisted
in `engine-settings.json`; clients edit them through `settings.get` and
`settings.set`. Secret values are never returned—status replies only report
whether a key is present.

## Proton compatibility profile

The frontend currently on `main` still calls the original names such as
`connect`, `start`, `list_sessions`, and `read_file`. The native extension
registers those names only for the Proton window and maps them to the catalog.

The old page also models a run id as an integer. Catalog run ids are opaque
host-wide strings. `DesktopBridgeActor` therefore keeps a page-local
integer-to-string table:

- Proton requests translate their integer id before dispatch;
- catalog replies and notifications translate the opaque id back;
- WebSocket clients always see the opaque string unchanged.

Legacy endpoint fields sent by the desktop page are written into the
host-owned settings store immediately before `start` or `compact`. This keeps
the existing Settings page functional until the frontend migration lands.

The local `pick_workspace` operation remains outside the shared catalog
because a remote browser must not open a native folder dialog.

## JSON-RPC WebSocket

After the relay pairs a browser socket with a host data socket, the host reads
JSON text frames using JSON-RPC 2.0:

```json
{"jsonrpc":"2.0","id":1,"method":"session.list","params":{}}
{"jsonrpc":"2.0","id":1,"result":{"groups":[]}}
{"jsonrpc":"2.0","method":"agent.connected","params":{}}
```

Request ids belong to one client connection and are echoed unchanged.
Requests may complete out of order. Batch requests and client notifications
have no catalog behavior.

Errors use these codes:

| Code | Meaning |
|---:|---|
| `-32700` | Unparsable JSON text |
| `-32600` | Invalid JSON-RPC request |
| `-32601` | Unknown method |
| `-32602` | Malformed method parameters |
| `-32603` | Unexpected internal error |
| `-32000` | Engine operation failed |
| `-32001` | Host operation failed |

One writer task owns each socket. Request tasks and notification forwarding
enqueue complete envelopes into a bounded queue. A client that stops draining
is disconnected after the queue fills; notifications are never silently
dropped while the connection stays open.

`agent.connected` is the first notification placed into a new connection's
queue. The client treats it as a readiness and resynchronization boundary.

## Reconnect and durable delivery

The WebSocket does not replay transient frames. After reconnecting, a client
rebuilds state with `session.list`, `session.load`, and `agent.runs`.

A named session's canonical transcript comes from:

1. the `session.load` snapshot and its `watermark`;
2. later `session.event` notifications.

A session event has this shape:

```json
{
  "session": "session-id",
  "sequence": 8,
  "event": {
    "sequence": 8,
    "ts": 1785200000,
    "item": {}
  }
}
```

The sequence is the item's one-based position in the durable record. The host
publishes `session.event` only after that item has been committed.

For a client watermark `W`:

- sequence `<= W`: already present, ignore it;
- sequence `== W + 1`: apply it and advance;
- sequence `> W + 1`: a gap exists, reload the session and reconcile buffered
  commits against the new watermark.

Each live engine has one follower reading the durable log. The follower owns
its file cursor, publishes commits in order, and performs a final scan after
the engine exits. Engine lifecycle publication waits for the follower boundary
needed to distinguish a complete durable turn from a failed write.

`agent.runs` returns the currently active starts. When supplied with exact
known run or submission identities, it also returns matching process-lifetime
settlements. This lets a reconnecting client close a run whose terminal
notification was missed without exposing unrelated completion history.

## Relay tunnel

The host does not listen on a local HTTP port. Remote access is outbound:

1. `RelayActor` connects to `/v1/tunnel`;
2. it sends `register` with a device token and name;
3. the service replies with `registered`, or rejects it with `fail`;
4. each `open` control frame asks the host to connect to
   `/v1/tunnel/<stream>`;
5. a `WsClientActor` serves JSON-RPC on that data connection.

The `desktop/tunnel` package owns only the four control-frame JSON shapes.
Socket ownership and retry behavior live in `desktop/internal/remote`; the
public service, authentication, device ownership, and stream pairing live in
the `openseek-api` repository.

For development and protocol testing, the desktop connector is enabled only
when both variables are present:

- `OPENSEEK_RELAY_URL`
- `OPENSEEK_DEVICE_TOKEN`

`OPENSEEK_DEVICE_NAME` is optional and defaults to `desktop`.

Ordinary network failures reconnect after three seconds. A `fail` frame stops
the actor because retrying the same fixed credentials cannot recover. Persisted
sign-in and live configuration changes belong to the later product change.
