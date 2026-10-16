# Local headless packages

The builder produces a relocatable, verified Linux x64 or arm64 directory. It
uses the current **local workspace** artifacts and pinned published dependencies.
It does not publish dependencies, push a release, install on a host, or upgrade
an existing service. Those are separate steps.

Git is a host prerequisite, not bundled. Worktree creation and subtask geometry
require `git worktree list --porcelain -z` (Git 2.34 does not support it). The
service checks this capability before creating a worktree and returns Git's
actual refusal. Supply a supported Git in the launcher's PATH and explicitly
restart an idle service to change its environment. Reconnecting alone keeps
the running service's PATH. Do not substitute line-delimited output: older Git
can emit literal newlines inside worktree paths.

Use Node 18.17+ and tar on Linux or macOS. Build Wasm and the visualizer in the checkout:

```sh
moon build . --target wasm
moon build cmd/viz_app --target js
node scripts/headless/fetch-vendors.mjs --platform linux-x64 --output /tmp/headless-vendors
node scripts/headless/package.mjs --platform linux-x64 --build-id dev-my-build \
  --vendor-dir /tmp/headless-vendors \
  --output /tmp/seekmoon-headless-linux-x64
```

`--wasm` and `--viz` accept explicit previously built workspace artifacts, allowing
packaging on a Linux staging machine without rebuilding the checkout there.
Give a changed payload a new build ID;
reusing an ID must never replace a different installed manifest. The builder validates the ELF machine
of the runtime, compiler, moon, moonx and ripgrep; this is architecture
validation, not execution proof. Run the package on its target before accepting
it. arm64 emulation is useful evidence but does not replace arm64 hardware QA.

The package includes `bin/openseek`, `bin/moonrun`, `bin/rg`,
`lib/openseek.wasm`, `share/`, `web/viz/`, licenses,
and `toolchains/moonbit/<platform>/`. It contains no CEF/Proton GUI host or
Desktop frontend. The launcher calculates its root after relocation and passes
explicit seed/platform/viz/build paths; user arguments remain separate
argv entries. It prepends only package `bin/` to PATH; the seed is preparation
input, never an executable toolchain. Host engines, language services,
semantic search and Pattern Repair select the writable prepared toolchain under
the data directory. Direct CLI commands outside app-server need a usable
MoonBit toolchain on their incoming PATH. The seed's `moonx`
is a regular copy of `moon`, preserving its argv[0] alias without shipping links.
Registry credentials and caches retain the user's MOON_HOME. Codex is separately
preinstalled and can be selected through OPENSEEK_HOST_CODEX_COMMAND.

`manifest.json` declares format/build/protocol/data schema, platform, SDK version,
shared-resource digest, and every regular file's path, byte length, mode and
SHA-256. The runtime baseline is glibc 2.35 (Ubuntu 22.04). Data schema 1 records
the initial managed format; this packaging step performs no data migration.
Output is published by renaming a completed, verified sibling staging directory;
an existing output is never replaced. Failed builds remove their temporary tree.
The installer must compare the expected manifest digest and verify the full file
set before executing a package. These hashes establish integrity against the
selected local artifact, not an independent publisher signature.

Vendor URLs and SHA-256 values are fixed in `vendors.json`. The optional fetch
command has bounded downloads and only publishes a cache entry after its digest
matches. Packaging itself is offline. MoonBit binary/core archives use the pinned
version in `desktop/.moonbit-version`; their downloaded byte digests are recorded
in the lock. Ripgrep 15.1.0 digests are from the
[upstream release assets](https://github.com/BurntSushi/ripgrep/releases/expanded_assets/15.1.0).
Update pins deliberately, then rerun both architecture package checks.

```sh
node --test scripts/headless/package.test.mjs
```


## Install and update from Desktop

In **Add remote → Advanced**, choose **Prepare from local package**, select the
package directory, and enter an SSH destination and dedicated absolute data
directory. The native controller verifies the local manifest and every file,
probes the remote platform, then streams the archive through system SSH.
The remote bootstrap requires Linux, glibc 2.35+, Python 3.8+, `getconf`,
`/usr/bin/base64`, and an executable login shell. It installs no system packages.
Local Node and Python are not required by the desktop installer.

The bootstrap verifies the archive digest, paths, file set, sizes, modes and
hashes before executing the runtime. It rejects archive links and publishes
under `~/.local/share/seekmoon/host-packages/versions/<build-id>/<platform>` by
atomic rename while holding the installation lock. Exact reuse re-verifies the
installed tree; a same-ID/different-manifest conflict is an error. Interrupted
uploads leave installed versions intact. A retry removes only marked abandoned
staging directories under the same lock.

The profile is saved after activation confirms the selected build, protocol
and server identity. **Update from package** preserves an existing host's
identity and changes its saved profile only after successful activation.
A busy service keeps running: finish or cancel its work, then retry.
Closing the dialog cancels the owned operation. Once activation starts,
cancellation cannot prove the remote service did not switch; inspect status
and upgrade records before retrying.

## Daemon activation and recovery

The installed launcher can activate an idle service directly:

```sh
/absolute/installed/bin/openseek app-server daemon upgrade --data-dir /absolute/private/data
```

For an associated host, also pass `--expected-server-id` with its saved identity.
The check runs under the lifecycle lock before reuse, stopping or starting a
service. The upgrade barrier rejects active logins, mutations, agent/Codex turns
and scheduled work with `status: busy`. A same-build call reuses the instance.

`data-schema.json`, `launch.json` and private `upgrades/<attempt-id>.json` records
track the schema, selected launch and upgrade outcome. Schema 1 performs no data
migration; unknown schemas are rejected before stopping a running service.
A missing or malformed launch record requires inspection and explicit stop/start.
An explicitly configured Codex executable is retained unless overridden by the
new launcher. MoonBit and visualizer resources come from the selected package.

Failed upgrades do not force-stop an uncertain instance or roll back its data.
Inspect the attempt record, daemon log, owner status and recovery journal.
Unknown external effects require inspection and explicit acknowledgement with
`daemon recover --acknowledge-instance ... --confirm-external-tools-stopped`.
See the [working-host CLI](../../desktop/backend/cli/README.md).
