# Native SSH HostClient

`with_client(SshHost, body)` owns one explicit connection scope. It discovers a
running daemon via `daemon status` over SSH; only an explicit `not_running`
response permits `daemon start`. Authentication, permission, probe, and version
failures never trigger a restart. Discovery returns the loopback port
and instance identity. The client reserves an ephemeral local
loopback port, releases it, and starts `ssh -N -L
127.0.0.1:<local>:127.0.0.1:<remote>` with `ExitOnForwardFailure=yes`.
A collision or disallowed forwarding fails setup and never restarts the daemon.
Multiplexing is disabled for the forwarder so its lifetime belongs to this client.

The client connects its async WebSocket to the local TCP port without an
application token. SSH provides login authentication and tunnel encryption;
loopback processes on both machines are trusted. Build, server, and instance
must match discovery.
This SSH process has no remote command and carries no WebSocket data on stdio.
The daemon owns accepted Agent work; leaving the connection scope cancels the
forwarder and closes only this connection and its watches. Headless SSH hosts
do not expose `terminal.*` endpoints. Native desktop windows provide integrated
terminals through separate `ssh -tt` sessions instead. `terminal_args` constructs
those sessions with multiplexing and SSH escape commands disabled; the local
window owns their PTYs, input, resize, ACK flow control, and cleanup.

The configured OpenSSH alias retains its usual host-key checking, authentication
and ProxyJump configuration. The client uses BatchMode, no PTY, a 10-second TCP
connect timeout and disables agent forwarding. Remote launcher and data paths
must be absolute. Payload paths are POSIX-quoted, then the command is encoded
for the login-shell carrier. Bootstrap
stdin is an independent EOF pipe, so SSH cannot consume the caller's RPC input.

Each SSH control command emits a fresh marker after login initialization and before payload exec. Marker parsing accepts
fragmented banners without requiring a leading newline, but reads at most 64 KiB
within 10 seconds. Control probes are bounded to 25 seconds, and Upgrade and initialize
each have a 10-second deadline. Initialize requires the exact build and protocol;
server/instance identity must agree with discovery on every connection. Supply `expected_server_id`
on subsequent connections to reject a replacement data directory explicitly.

The loopback connection uses the published async HTTP/WebSocket APIs.
Reader, writer and matching-pong watchdog run independently. Requests are bounded
to 32 concurrent calls and 32 MiB per message; outgoing and notification queues
have 64 slots, with a shared 64 MiB retained-payload budget. Cancelled callers do
not release the charge for bytes still waiting in the writer queue; the writer
skips their requests before handoff. Notification
overflow closes the connection and requires resynchronization.

Failed mutations are never replayed automatically. `RequestError` distinguishes
`Unsent` (before writer handoff), `Refused` (a JSON-RPC error response), and
`Unknown` (writer handoff occurred but the result is unavailable). Handoff is
recorded before the first suspending write; partially written frames are unknown.
The JSONL CLI preserves this classification in `error.data.outcome`. Reconnect explicitly,
check server identity, and reload durable session state. The desktop uses the
window-scoped `Connection` supervisor described below for retry and resync.

The minimal CLI accepts JSONL requests with `id`, `method`, and `params`:

```sh
openseek app-server remote --host my-ssh-alias \
  --launcher /absolute/install/bin/openseek \
  --data-dir /absolute/private/data --build-id exact-build
```

Stdout emits `host.connected`, notifications, and JSON-RPC responses. Stdin EOF
closes this connection. The CLI dispatches requests sequentially; the library
supports concurrent calls. Connection/control failures retain up to 8 KiB of SSH
stderr in their error, including the window supervisor’s disconnected event.
The remaining stderr is drained without retention so verbose failures cannot
block SSH; control stdout remains reserved for discovery.

Local process tests run in `just test`. The opt-in
`tests/host_server/test_remote.py` requires a manually staged Linux headless
installation and an existing SSH alias. Its scripted loopback model drives the
real engine, sandboxed mbtx tools through the host-tool SDK, durable storage and
followers. For a verified immutable package, stage `model_fixture.py` outside
the package and set `OPENSEEK_REMOTE_MODEL_FIXTURE` to that remote path.
It checks disconnect continuation, a frozen SSH blackhole, drain,
and hard-crash recovery using only its own temporary service data.

`Host(id="ssh_…", config)` holds the stable profile identity and the pinned
server ID. Share this object between a profile's windows, and give each window
its own `Connection(host)`. The desktop profile store persists both identities;
the SSH alias, forwarding process and connection epoch are not resource identities.

`Connection.run(emit~)` owns the reconnect loop and is cancelled with its window.
It emits typed connecting/connected/notification/disconnected events, each with
an epoch. Pass that epoch to `Connection.request`: stale commands fail Unsent,
and replies that cross a replacement boundary fail Unknown. The supervisor
retries connections only, with full jitter from 500 ms up to 30 seconds. A
successful initialize resets backoff. A changed server identity emits
IdentityBlocked and stops retries; a new instance of the same server is allowed
and requires the consumer's normal resync. The consumer returns false if its
bounded queue overflows, closing the connection and requiring resynchronization.

For process-boundary diagnostics use `app-server remote --reconnect
--host-id ssh_<stable-id>` with the usual host options. It emits
`host.connection` events; JSONL requests additionally require the latest observed
`epoch`. Its output queue has 64 slots and a 64 MiB encoded-byte bound. EOF
cancels retries and closes only this connection, leaving the daemon running.

SSH commands initialize the working user's interactive login shell before
running the POSIX payload. The wrapper handles csh/tcsh login files explicitly
and uses Nushell's environment syntax for the final exec. The command carrier
is Base64 because Nushell rejects adjacent POSIX quote fragments and xonsh
interprets escapes inside single quotes. `/usr/bin/base64` and an executable
`SHELL` are required on the working host. Missing prerequisites fail before
launching a service; startup output remains before the random ready marker.
The wrapper itself does not read protocol or upload stdin, and it removes its
carrier environment variables before starting the payload. The native installer
and Node development installer use the same contract.

The desktop loads its local login environment before creating SSH connections,
so a Dock launch gets the user's ProxyCommand PATH. Reconnecting a running
remote daemon does not replace that daemon's environment; explicitly restart an
idle service after changing its startup configuration.
