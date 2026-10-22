# SSH working hosts

The desktop uses the existing host-qualified channel and resource URI model:

```text
renderer -> native client -> local loopback TCP/WebSocket
         -> ssh -N -L -> remote loopback TCP/WebSocket -> openseek-app-server
```

`ssh` uses the user's SSH configuration and agent, and requests interactive
authentication in the existing desktop dialog when needed.
A temporary bootstrap SSH command starts `openseek-app-server` with `nohup`
in the background and reads its loopback port and process instance ID through
an owner-only temporary file. Bootstrap stdout is not an RPC transport. Server
stderr goes to `~/.openseek/ssh/app-server.log` so neither output holds the SSH
channel open. The temporary endpoint file is removed when bootstrap exits.
The WebSocket initialize response must name the discovered instance. The server
rejects browser Origins and binds only `127.0.0.1`; forwarding also binds only
`127.0.0.1` and refuses a port collision. No application bearer token is added.

## Usage

Adding a host downloads the native CLI archive for the configured release
version from `https://cli.moonbitlang.com/openseek/cli/releases/v<version>/`, verifies it against
`SHA256SUMS`, and runs `openseek setup` on the remote host. The UI shows download,
setup and connection progress and supports cancellation. Automatic preparation
supports Linux x64/arm64 and macOS arm64 with SSH, a POSIX shell, curl, tar, and
sha256sum or shasum. The matching CLI release must include `openseek-app-server`.
CLI 0.7.3 or later is required for the WebSocket lifetime handoff; older
releases stop the server when the bootstrap SSH input closes.

Desktop release CI stamps `CliRelease` in `version.mbt` from the root OpenSeek
`moon.mod`, the same manifest used by the CLI release workflow. Local builds
keep the checked-in default unless it is explicitly stamped. This version is
independent of the Desktop application's own version. The matching CLI release must be published
before a fresh remote host can download it.

The prepared distribution is cached under `~/.openseek/ssh/v<version>`; reconnect
reuses it without downloading or reinstalling. Setup installs missing MoonBit
tools and the CLI distribution under `~/.moon` and `~/.openseek`. The SSH host
runs the versioned executable and its companion together, even if the user's
normal PATH contains an older working CLI. No shell startup files are changed.

Use **Add project → Add SSH host**, or **Settings → SSH hosts → Add SSH host**. Enter
`ssh user@host`, `ssh alias`, or a command with `-p`, `-i`, `-J`, `-l`, or `-F`.
The parser preserves quoted arguments and never evaluates the input as a local
shell command. Put additional connection settings in SSH config. Passwords,
private-key passphrases, and keyboard-interactive challenges appear only when
OpenSSH requests them. First-use host trust is a separate confirmation showing
OpenSSH's fingerprint and prompt. Changed host keys fail normally; the app uses
`StrictHostKeyChecking=ask`, never automatic trust. New profiles need only an SSH command.

After connecting to add a project, the remote folder picker opens. Browse to a
remote directory and add it. Cancelling host creation returns to the previous
folder selection. Saved hosts can also connect through **Add project**.

An optional display name overrides the SSH alias or hostname. Projects use a
compact single-line row with the folder name and a separate host label. Open
**Connection details** from the project's menu for connection status, rename,
or retry a failed connection. Opening a saved remote project or
conversation connects its host automatically. An established connection that
drops unexpectedly gets one automatic connection attempt; if that fails,
**Retry connection** is offered. Cancelled connections stay offline
until the user opens a remote project or conversation again. There are no regular
Connect/Disconnect controls. The host details also offer **Remove host**, which
forgets the profile on this computer and disconnects its running tasks after confirmation. Remote files,
project registration, conversation history and installed tools remain on the
host. A failed profile write keeps the host available so removal can be retried.
The original command is available under **Connection details**. Renaming preserves
the host ID, connection, project positions and execution command. Older profile
files without a display name continue to load. The sidebar combines local and remote projects, with host-qualified
identities. Chat, history, approvals, attachments, worktrees, file browsing,
file watching, search, Git changes/history/review, language navigation/hover,
and PTYs reuse the existing backend API and frontend components. MoonBit tools,
`rg`, Git and Codex must be available on the remote host. Remote Codex uses that
host's normal `~/.codex` credentials; sign in with `codex login --device-auth`
in the remote terminal, then refresh the account in settings.

## Lifetime and scope

SSH connections select a fallback credential from the local desktop's API
settings at connect time. DeepSeek uses `DEEPSEEK` and GLM uses `GLM`; a custom
key uses `DEEPSEEK`, `KIMI` or `GLM` according to the local default model family
(`OPENSEEK_MODEL`, or the existing default when unset). Only the selected key
is sent. The native host sends three literal lines through SSH stdin for these
fixed names, leaving unselected slots empty. Empty slots leave the remote
environment unchanged. Values must be single lines (no CR, LF or NUL); they
are never evaluated as shell code or put in arguments, SSH profiles or the
remote settings file.

This uses the existing environment fallback in the released v0.7.1 CLI and
app-server. Remote saved credentials take priority over the injected key.
The remote provider, endpoint and model selection remain unchanged; injecting
a GLM or Kimi key does not select that provider. Local API URLs and model
settings are not forwarded. The released app-server's custom-endpoint behavior
also remains unchanged, so this is not a general fallback for all local API
configurations.

Change the fallback key in the local API settings and reconnect each SSH host
to apply it. The remote API section links to those local settings. No new
environment variable or remote settings receiver is required.

The service belongs to one connection, with no reusable daemon, upgrade journal,
or crash-recovery subsystem. Before a valid initialize, bootstrap stdin EOF or
a 20-minute startup deadline stops the service. The first valid WebSocket claims
ownership before its initialize reply; failed or additional handshakes cannot
claim or stop that owner. After the reply, Desktop closes bootstrap stdin and
waits for the first SSH process to exit normally. Only the forwarding SSH remains.
The owner WebSocket ending stops the service, running turns and PTYs. The server
uses native WebSocket Ping/Pong every 30 seconds, with a 30-second deadline for
writes and matching Pong replies. An unresponsive connection is reclaimed within
60 seconds without adding an application-level heartbeat protocol.
Closing/reloading the window or disconnecting closes the WebSocket and its tunnel.
Conversation history and project registration remain on the remote disk.
Reconnect re-reads that state; it never replays an unanswered write.
Remote profiles persist locally in `~/.openseek/ssh-profiles.json` and start
offline when the app reopens. The client remembers each host's last project
list for the sidebar, so an existing project can be opened without adding it
again. Opening it connects on demand; the remote registry then replaces the
cached list. Removing a host clears its local project cache too.
Local-only export, system file opening, document
preview and browser tooling retain their existing limits.

Each native connection has a monotonically increasing epoch. Native delivery
and frontend requests reject events/replies from retired connections. An absent
connection is `Unsent`, an explicit RPC error is `Refused`, and a lost reply is
`Unknown`; there is no fallback to the local host.

`SEEKMOON_SSH_PROFILES` isolates profile storage for QA.
`OPENSEEK_ENGINE` overrides the engine used by the server for source builds.
By default the server uses the `openseek` executable beside it.

## Interactive authentication

The host re-executes its **own signed executable** as `SSH_ASKPASS`, with
`SSH_ASKPASS_REQUIRE=force`. The helper entry in `desktop/app/main.mbt` runs
before CLI parsing, logging, login-shell probing, or Proton/window startup.
There is no separate helper artifact or runtime interpreter dependency. The
transport and helper implementation live in `backend/ssh/auth.mbt`, independent
of Proton. The host supplies the executable path to `Connection`.

Each connection owns a loopback IPC listener and a random capability token.
Only its SSH children receive the address/token environment. The helper sends
OpenSSH's actual prompt and waits for one tagged response; only its stdout
returns the answer to OpenSSH. Bootstrap stdin/stdout remain exclusively owned
by the startup lifetime/endpoint protocol. Both bootstrap and forwarding SSH
use this channel; neither caches a password or reuses a verification code.

`ssh.connect` carries a frontend attempt identity; native events add the native
epoch. `ssh.auth.respond` is always a Local command and checks host, attempt,
epoch, request identity and answer kind. Duplicate connects reuse an active
native connection, duplicate submissions are rejected, and cancellation,
window closure, reload and SSH exit retire pending helpers and waiters.
Requests from different hosts are retained separately. Background challenges
show **Authentication required / Enter password** without opening a dialog or
stealing focus; this feature does not add a reconnect scheduler.

Input is kept in the current DOM field rather than the frontend model or
message history, cleared on submission, and discarded when the field closes.
Its stable position in the shell preserves the input node during responsive
layout and toast changes without copying the secret into a render snapshot.
The only answer copies are in the transient command, IPC and OpenSSH handoff;
there is no credential store and no promise of physical memory zeroization.
No secret is put in argv, environment variables, profile files, or application
logs. The UI permits empty input as distinct from Cancel. Only an explicit
OpenSSH password-rejection message marks the next password challenge as a
retry; another process, key or verification challenge is not called a failure.

Cancel, Escape and the close button terminate an in-progress connection.
Clicking the backdrop or changing application focus preserves it. A details
reconnect stays in details on success/cancellation; a workspace reconnect
returns to that workspace. Project and conversation identity are retained, but
remote processes and PTYs still belong to the connection and are not resumed.

Bootstrap and forwarding each have a 20-minute upper bound including user
input, with an explicit timeout error. Forwarding additionally limits socket
readiness to 15 seconds **outside** an active input request, followed by a
15-second WebSocket handshake bound. SSH server timeouts can end an attempt
sooner. Process exit clears the input and exposes a fresh connection retry.

The helper mode requires an OpenSSH client supporting `SSH_ASKPASS_REQUIRE`
([OpenSSH 8.4](https://www.openssh.org/txt/release-8.4) or later). The packaged macOS application is the acceptance host;
Linux and Windows execution must be validated on those platforms before
claiming equivalent interactive-authentication support.
