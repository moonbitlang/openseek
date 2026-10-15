# Native CLI releases and setup

The **CLI release** GitHub Actions workflow publishes standalone Linux x64 and
arm64 executables under tags named `cli-v<root module version>`. These are
separate from the desktop application and Mooncakes packages. A version becomes
downloadable only after the workflow has published its GitHub Release.

For a published tag, the download base is:

```text
https://github.com/moonbitlang/openseek/releases/download/cli-v<VERSION>/
```

Download `openseek-linux-x64` or `openseek-linux-arm64`, verify its digest against
`SHA256SUMS` (also available in `cli-release.json`), make it executable, and keep
it at a stable location such as `~/.local/bin/openseek`. The native executable
can show help and run setup before MoonBit is installed:

```sh
chmod +x ~/.local/bin/openseek
~/.local/bin/openseek setup
```

The initial release targets Linux with glibc 2.35 or newer. Setup requires
`bash`, `curl`, `tar` with gzip support, normal system CA certificates, and a
writable user data directory. It does not need Node, Python, sudo, or a C compiler.
Git and Codex remain user-installed; setup does not install or update either.
Model access and project-specific dependencies are configured separately.

## What setup installs

Setup downloads `https://cli.moonbitlang.com/install/unix.sh` to a local file,
then runs it with `bash` and the release's fixed MoonBit version. The official
installer downloads the SDK and core library, creates `moonx`, and bundles the
standard library. Its `HOME` and `MOON_HOME` apply only to the installer child
process and point inside the staging directory, so it cannot replace the user's
existing SDK or edit their shell profile. Setup trusts the official HTTPS
installer and verifies the installed compiler version before enabling it.

Each CLI also embeds the exact URL and SHA-256 of its release resource archive,
which contains ripgrep (`rg`), OpenSeek's `share/` documentation, workflow scripts,
examples, and licenses. The archive checksum pins these resources; it does not
cover downloads performed by the official MoonBit installer. `--runtime-url`
changes only the resource archive location.

The MoonBit version and rg inputs live in `scripts/cli-release/vendors.json`.
The version must agree with `desktop/.moonbit-version`. Packages invoked through
`moonx`, including semantic-search providers, keep their existing registry and
cache behavior; setup does not replace the user's registry credentials.

Installation lives under
`${XDG_DATA_HOME:-$HOME/.local/share}/openseek/runtimes/<archive-sha256>/`.
Concurrent setup calls take the same installation lock. Downloads and extraction
use a private sibling staging directory, and only a verified, executable
runtime is published. A failed attempt removes its staging directory and can be
retried. Existing versions are retained. Hard-killed attempts can leave unused
`.setup-*` directories, which can be removed when no setup is running.

Repeating setup verifies and reuses the installed runtime without downloading.
An incomplete or unusable existing installation reports an error rather than
replacing files under a running process. After stopping users of that runtime,
remove the reported version directory and rerun setup to repair it.

New `run`, `serve`, and `mcp` processes automatically prepend the selected
runtime's toolchain and rg directories to their own child PATH and select its
documentation. There is no shell-profile modification or global PATH change.
`MOON_HOME` retains its ordinary registry/cache meaning. Installing a new CLI
does not switch or stop an already-running process. Development, desktop, and
Mooncakes builds retain their previous environment and bundled-resource policy.

## Automation

```sh
openseek setup --json
```

Stdout contains one JSON object per line:

```json
{"event":"progress","stage":"download"}
{"event":"progress","stage":"verify_runtime"}
{"event":"ready","release":"cli-v0.6.2","platform":"linux-x64","runtime_dir":"/home/me/.local/share/openseek/runtimes/<sha256>","reused":false}
```

Success exits 0. Failure emits `{"event":"error","message":"..."}` and exits
nonzero; stderr also contains human-readable diagnostics. Callers should use the
final `ready` event and exit status, not infer success from a progress event.

An HTTPS mirror may be selected explicitly:

```sh
openseek setup --json --runtime-url https://mirror.example/openseek-runtime-linux-x64.tar.gz
```

The embedded checksum remains authoritative. This flag changes the download
location, not the selected version or accepted content. curl's proxy and CA
environment settings remain available.

## Maintainer release procedure

1. Update the root `moon.mod` version for each new CLI release. Update dependency
   pins when changing MoonBit or rg.
2. Merge the change to main. PR checks build both architectures on Ubuntu 22.04
   and run setup over local HTTPS in a clean home, install MoonBit through the
   real official script, and execute a tool-using Agent against an offline
   scripted model. First-time setup requires network
   access to both GitHub and cli.moonbitlang.com.
3. Dispatch **CLI release** on main. The build stages package the matching
   resources, stamp the CLI's embedded release manifest, and compile
   the native executable. Generated `installation/release.mbt` is build output
   and must not be committed.
4. Publication validates both architecture artifacts, creates `cli-release.json`
   and `SHA256SUMS`, uploads everything to a draft Release, and only then makes it
   public. It does not change GitHub's repository-wide latest-release selection.

The workflow refuses to overwrite an existing release/tag. After interrupted
publication, inspect and remove the incomplete draft before retrying. Publishing
requires the repository's `GITHUB_TOKEN` contents-write permission; no additional
third-party upload credential is required. Adding this workflow does not
automatically publish a release.

Useful local checks:

```sh
moon test installation internal/openseek/options --target native
node --test scripts/cli-release/release.test.mjs
python3 scripts/cli-release/smoke.py <native-cli> <asset-directory> linux-x64
```
