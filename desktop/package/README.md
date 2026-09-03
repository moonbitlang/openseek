# Bundling command-line binaries

`package/build.mjs` acquires and stages the native tools shipped with
SeekMoon. Ripgrep is the reference implementation.

Adding a binary is complete only when acquisition, package layout, runtime
lookup, child-process `PATH`, licensing, signing, and installed-artifact
validation all agree.

## Build input

Keep platform facts together in `Hosts`:

- exact upstream version and target name;
- archive type and executable suffix;
- SHA-256 for every downloaded third-party binary;
- supported operating system and architecture.

Download over HTTPS into `desktop/target/vendor-<tool>/cache/`. Recheck a
cached archive before reuse. On mismatch, delete it and fail or redownload; do
not stage unverified bytes. Extract into a target-specific work directory
after deleting its previous contents.

The MoonBit seed is selected by `desktop/.moonbit-version`. Packaging verifies
the extracted compiler with `moonc -v` and writes the seed stamp only after the
version matches.

## Package layout

Application-owned files live below Proton's resource directory:

```text
seekmoon/
  bin/
  licenses/
  toolchains/
  web/
```

Add the executable and its licenses in `Build.stage`. Preserve platform
suffixes and executable permissions. If a macOS binary requires signing, also
add its `seekmoon/...` path to `package.sign.binaries` in
`proton.project.json`.

Do not resolve package files from the process working directory. Host features
append canonical paths to `@proton.resource_dir()`. Installed lookup must fail
closed rather than silently use a system copy.

## Process environment

The intended `PATH` precedence is:

```text
bundled MoonBit bin : packaged command bin : login-shell PATH
```

Check the Desktop process, engine, Codex app-server, integrated terminals, and
children created with `inherit_env=false`. Login shells can replace `PATH`, so
terminal activation must restore the packaged directories afterward. On
Windows, avoid creating separate `Path` and `PATH` entries.

Development may use a documented system command because `package/dev` does
not stage the production resource tree. A successful development run is not
evidence that the installed lookup works.

## Validation

Run source checks:

```sh
just desktop-build-scripts-check
moon -C desktop test internal/host --target native
just check
just test
just build
```

Then build on every target operating system:

```sh
moon run ./desktop/package/macos -- --no-open
moon run ./desktop/package/linux
moon run ./desktop/package/windows
```

These commands download fixed Mermaid and xterm browser distributions plus a
standalone esbuild executable, verify their checked-in SHA-256 digests, and
cache only the archives below `desktop/target/vendor-web/cache`. They do not
require npm.

Inspect the installed copy, not the extraction directory:

- run the packaged binary's harmless version probe;
- confirm licenses and executable permissions;
- inspect architecture and dynamic libraries;
- verify macOS deployment targets and strict signatures;
- test Windows portable ZIP and installer outputs;
- run the Linux AppImage with and without FUSE when supported;
- test on a machine without a system copy of the command;
- remove the packaged binary in a disposable package copy and confirm installed
  features report it missing.
