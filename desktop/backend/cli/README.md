# Working-host CLI

The foreground entry point runs the shared backend `ApiState` on native or wasm:

```sh
openseek app-server --data-dir /absolute/private/data \
  --listen 127.0.0.1:0 --engine /absolute/openseek --build-id workspace
```

`--listen` defaults to `127.0.0.1:0` (an OS-selected TCP port). Other addresses
are rejected. `OPENSEEK_HOST_ENGINE` and `OPENSEEK_HOST_BUILD_ID` can supply the
launcher configuration. The data directory defaults to `$XDG_DATA_HOME/seekmoon`
or `$HOME/.local/share/seekmoon`; async filesystem APIs create/chmod it to 0700
and reject a symlink at that directory. Use a trusted parent directory.

The service holds an async exclusive owner lock. Once listening it atomically
publishes `endpoint.json` (0600): TCP port and instance ID. HTTP Upgrade at
`/host` requires no application token. SSH provides remote login authentication
and tunnel encryption; loopback processes on both machines are trusted. Browser
Origin headers are rejected. Graceful exit removes the endpoint after all
connection tasks join. A stale file is never evidence of a running service.

The first RPC is `server.initialize` with the exact build and protocol version.
Identity and instance checks remain mandatory. `server.status` reports state;
`server.shutdown` closes admission, sends its response, drains accepted work for
`shutdown_grace_seconds` (0–300, default 60), then cancels and joins resources.
SIGINT/SIGTERM use the same drain path. Connections own watches; the service
owns admitted mutations and Agent/Codex work. Headless terminals remain unavailable.

`app-server daemon start|status|stop|restart|upgrade` serializes lifecycle changes
with an async filesystem lock. `spawn_orphan`, stdin from `/dev/null`, and a
private daemon log detach the service. Start/status return the
initialized identity plus the private `endpoint` discovery record. A live instance
is reused; stop/restart/upgrade wait for owner-lock release. `daemon-process.json`
records the launched PID for diagnostics only, never as proof of process identity.

The connection path is:

```text
Client WebSocket → local 127.0.0.1 port → ssh -N -L
  → remote 127.0.0.1 port → app-server
```

Discovery/start runs in a separate SSH control session. See
[`host_client`](../host_client/README.md) for connection scope and limits.

The durable recovery journal still records intent before effects and writes a
clean marker only after settled work and joined resources. Unclean instances
block mutation admission until explicit inspection and acknowledgement:
`daemon recover --acknowledge-instance <id> --confirm-external-tools-stopped`,
then restart. Existing clean and acknowledged records remain readable.

OS process-identity inspection is unavailable. `server.recovery` explicitly reports `process_inspection:
"unavailable"`; child PIDs are diagnostic only. The user must verify external
tools have stopped before acknowledgement. No missing inspection is interpreted
as proof that an external tool exited. Upgrade retains its idle barrier, instance
fence, schema checks, and durable records, but its exit fence is owner-lock
release after all service tasks join.

Use `--codex-command /absolute/path/to/codex` (or
`OPENSEEK_HOST_CODEX_COMMAND`) for a preinstalled Codex CLI outside the service's
PATH. The path is passed as one argument through daemon detach, including spaces.
A relative explicit path is rejected before restart can stop the running owner.
The default remains `codex` on the service's startup PATH. A missing or
incompatible explicit executable reports Codex unavailable; it never falls back
to another Codex and does not disable other working-host operations.

A running service keeps its startup configuration when `daemon start` reuses it.
To change the executable, use an explicit restart with the new option. Put a
persistent selection in the installation launcher's environment, or repeat the
option for each start/restart; the controller does not infer an omitted value
from a previous invocation. Reconnecting a window does not reload process
configuration or restart Codex.

Headless MoonBit resources are explicit. Configure both `--moonbit-platform`
(`linux-x64` or `linux-arm64`) and `--moonbit-seed-dir` (absolute directory), or
set `OPENSEEK_HOST_MOONBIT_PLATFORM` / `OPENSEEK_HOST_MOONBIT_SEED_DIR` in the
launcher. The async process API runs `uname -sm` to check the host architecture; the seed must carry
its completed version stamp. These checks run before restart stops an owner.
The selected seed survives detach and is prepared below
`<data-dir>/toolchains/moonbit/<platform>`. Engines, scheduled runs,
and language services all use that selection; a broken explicit seed never
falls back to a different MoonBit. `MOON_HOME` retains the user's registry
identity and caches. Without either option, headless uses the working host's
PATH, then `~/.moon/bin`; it does not scan desktop bundle layouts. The macOS
arm64 seed selector also supports local daemon integration tests. Like the
Codex option, persistent selection belongs in the launcher environment or must
be repeated on each start/restart. This interface does not install a seed.
