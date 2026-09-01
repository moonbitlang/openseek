# Bundling command-line binaries

This guide covers adding a third-party or project-built command-line binary to
SeekMoon's Desktop packages. Ripgrep is the current complete example:
`backend/package/internal/ripgrep_assets` acquires it, the three platform
packagers stage it, and `backend/internal/host` makes the installed copy
available to Host operations, agents, and integrated terminals.

Putting a file in `dist/` is not sufficient. A bundled command is complete only
when all of these statements are true:

1. The build obtains an exact, verified binary for every supported platform.
2. Every platform package contains the binary, its required libraries, and its
   license material.
3. Host code resolves the installed path without depending on the launch
   working directory.
4. Processes that invoke the command by name receive the packaged directory at
   the front of `PATH`, including after an integrated terminal's login shell
   has changed `PATH`.
5. Signing, deployment-target, architecture, and runtime dependency checks
   cover the new executable.
6. Tests exercise missing, development, and installed layouts, followed by a
   smoke test of the actual package artifact.

Adding a directory to `PATH` only makes commands discoverable. It does not
change agent approval policy or filesystem/process sandbox permissions.

## 1. Acquire and verify the binary

Put acquisition code in a focused package under
`desktop/backend/package/internal/<tool>_assets/`; use
`desktop/backend/package/internal/ripgrep_assets/` as the reference.

- Pin the upstream version in source.
- Define each supported OS/architecture explicitly. Record the upstream target
  name, archive format, executable name, and SHA-256 digest.
- Download only over HTTPS. Bound redirects and report the original HTTP or
  checksum failure.
- Cache the archive under `desktop/target/vendor-<tool>/cache/`. Recheck its
  digest before every reuse; delete and redownload a corrupt cache entry.
- Extract into a target-specific work directory under
  `desktop/target/vendor-<tool>/work/`. Do not extract over a previous version.
- Verify that the executable, licenses, and any required data files exist after
  extraction. Return those paths as one typed asset value to the packagers.
- Add tests for the pinned filenames and hashes. A version bump must make the
  expected archive and digest diff visible in review.
- Prefer upstream static builds when their license and platform support allow
  it. Otherwise list and stage every dynamic library deliberately.

Do not silently use a system copy while producing an installed package. A
system fallback is acceptable only for a recognized development layout whose
contract explicitly permits it.

## 2. Stage every platform layout

Each platform packager must import the asset package, build the matching target,
copy the results, and fail when a required source file is absent.

| Platform | Installed command directory | Packager requirements |
|---|---|---|
| macOS | `SeekMoon.app/Contents/Resources/target/proton-package-input/bin/` | Stage under `target/proton-package-input/bin/`, make it executable, include it in Proton resources, and list executable code under `package.sign.binaries` in `desktop/proton.project.json`. |
| Linux | `SeekMoon.AppDir/usr/bin/` | Copy into `usr/bin`, add it to the `chmod +x` list, and ensure AppRun/library paths cover any shipped shared libraries. |
| Windows | `dist/windows-x64/SeekMoon/` | Copy the `.exe` into the bundle root. Put required DLLs where the Windows loader actually searches, normally beside the executable. The portable ZIP and NSIS installer consume this whole directory. |

Also stage license and notice files:

- macOS: `target/proton-package-input/licenses/<tool>/`
- Linux: `SeekMoon.AppDir/usr/share/licenses/<tool>/`
- Windows: `SeekMoon/licenses/<tool>/`

If the upstream license requires attribution elsewhere, update the product's
notices as well. Shipping only the executable is not license-complete.

### macOS code and signing

`package.resources` copies files into the app, but executable code additionally
needs signing coverage. Add every Mach-O executable and nested dynamic library
to the Proton signing input expected by the current package configuration.
Check whether the command needs entitlements; do not copy the Host's
entitlements without establishing that need.

Build with the same `MACOSX_DEPLOYMENT_TARGET` as the package where possible.
After packaging, inspect every shipped Mach-O with `vtool -show-build`; the
app's `Info.plist` minimum version does not override an executable built for a
newer macOS. Check architectures and install names/RPATHs as well.

### Linux libraries

An executable being present does not prove it runs on the oldest supported
distribution. Inspect it with `file` and `ldd` on the build artifact. If it is
dynamic, either rely on a documented system dependency or stage the libraries
and set a package-relative RPATH or launcher library path. Do not accidentally
link against a library that exists only on the build machine.

### Windows libraries

Check the target architecture and imported DLLs. The Windows loader does not
recursively search arbitrary package subdirectories. Keep private DLLs beside
the executable unless the binary has a tested alternative loader policy. If
Windows package signing is added, include the new executable and DLLs in it;
the current Windows packager does not provide that guarantee automatically.

## 3. Define runtime lookup

Choose how each caller finds the command:

- Host-owned features should prefer an executable-relative absolute path. This
  makes the selected version explicit and supports a fail-closed installed
  package. Workspace text search follows this rule for ripgrep.
- Agent shell commands and other general child processes may invoke the command
  by name. They need the packaged command directory in `PATH`.
- Development builds may use a documented system `PATH` fallback. Installed
  builds should not fall through to a different machine-global version when a
  required packaged file is missing.

`desktop/backend/internal/host/bundle.mbt` owns `PackagedTools`, including the current
macOS resource path and Linux/Windows adjacent layouts. When adding or removing
the binary used to recognize that directory, update its resolution tests. Add
an absolute-path accessor when a Host feature needs to invoke the new command
directly rather than through `PATH`.

Never resolve package files from the process working directory. Finder,
desktop launchers, installers, and remote starts do not promise a useful cwd.

## 4. Propagate `PATH` to every command surface

The intended order is:

```text
MoonBit toolchain bin : packaged command bin : user/login-shell PATH
```

The MoonBit directory is first so the app's selected `moon` remains
authoritative. Packaged commands are still ahead of Homebrew, system, or user
copies.

Check every surface:

- `desktop/main.mbt`: apply the user's login-shell environment first, then put
  `PackagedTools` at the front of the Desktop process `PATH`.
- OpenSeek engine: its explicit child environment starts from the Desktop
  process environment, then prepends the selected MoonBit toolchain.
- Codex app-server: it inherits the Desktop environment; its isolated
  `CODEX_HOME` must not replace `PATH`.
- Integrated terminal: a login shell can reset `PATH` in rc/profile files.
  `desktop/backend/internal/host/terminal_ops.mbt` therefore sends one shell-specific
  PATH activation after startup, listing MoonBit first and packaged commands
  second.
- Any child spawned with `inherit_env=false`: copy the already-adjusted PATH
  into its explicit environment. Do not assume a parent mutation reaches it.

Use `desktop/backend/internal/shellenv.path_prepend_command` for integrated terminals.
It handles the repository's supported POSIX shells, fish, csh/tcsh,
PowerShell, and cmd quoting. Unknown shells intentionally receive no command;
adding support requires syntax-specific tests.

On Windows, treat `Path` and `PATH` as the same environment name and avoid
leaving both spellings in an explicit child environment. On every platform,
quote directories containing spaces or apostrophes and avoid adding the same
leading entry twice.

## 5. Keep development and package behavior deliberate

`backend/package/dev` does not assemble the production resource tree. Decide
whether development should:

- use a system-installed command from `PATH`, or
- build/extract the pinned command and explicitly expose that development path.

Whichever choice is made, test it separately from installed-package lookup.
Do not make a successful development run evidence that the packaged layout is
correct.

## 6. Validation

Run source-level checks from the repository root:

```sh
moon -C desktop/backend test package/internal/<tool>_assets --target native
moon -C desktop/backend test internal/host --target native
moon -C desktop/backend check --target native --deny-warn
moon -C desktop/backend info
moon -C desktop/backend fmt
just check
just build
```

Run each package builder on its target operating system. macOS builds used for
validation should not open the app automatically:

```sh
moon -C desktop/backend run --target native package/macos -- --no-open
moon -C desktop/backend run --target native package/linux
moon -C desktop/backend run --target native package/windows -- --target app
```

The package command may need network access the first time it fetches a pinned
archive or Proton/CEF input. A network or sandbox failure is a validation
boundary, not evidence that an upstream credential or archive is invalid.

Inspect and execute the installed copy, not the extraction work directory:

- Confirm the binary and licenses are present at the platform paths above.
- Run the packaged absolute path with `--version` or an equivalent harmless
  probe.
- Check executable permission on macOS/Linux and architecture on all systems.
- On macOS run `codesign --verify --deep --strict` on the app, inspect every
  Mach-O deployment target with `vtool -show-build`, and assess the actual
  signed/notarized distribution artifact when distribution is in scope.
- On Linux inspect dependencies and run the AppImage, using
  `APPIMAGE_EXTRACT_AND_RUN=1` where FUSE2 is unavailable.
- On Windows test the bundle directory, portable ZIP, and installer output that
  are in scope; inspect imported DLLs and signatures when applicable.

Finally exercise every runtime route:

1. Use the Host feature that calls the binary by absolute path.
2. In both an OpenSeek agent and a Codex task, run the command's version probe
   and confirm the reported executable/version is the packaged one.
3. In the integrated terminal, use `command -v <tool>` and `<tool> --version`
   on POSIX, or `Get-Command <tool>` and `<tool> --version` in PowerShell.
4. Repeat the terminal check with a controlled login-shell configuration that
   resets PATH; post-start activation must restore the packaged directory.
5. Test on a machine or account without a system copy of the command.
6. Remove or rename the packaged file in a disposable package copy and confirm
   installed Host features report it unavailable rather than silently using a
   system version.

## Review checklist

- [ ] Version, target names, filenames, HTTPS URLs, and SHA-256 hashes are pinned.
- [ ] Cached archives are reverified and corrupt entries are replaced.
- [ ] Extraction verifies the executable, licenses, and required data files.
- [ ] macOS, Linux, and Windows packagers stage the correct target artifact.
- [ ] Executable bits, architectures, libraries, and loader paths are correct.
- [ ] License and notice obligations are included in every distribution shape.
- [ ] macOS signing inputs and deployment targets cover every new Mach-O.
- [ ] Installed Host operations use executable-relative absolute lookup.
- [ ] Installed lookup fails closed; any development PATH fallback is explicit.
- [ ] Desktop, OpenSeek engine, Codex app-server, and integrated terminal PATHs are covered.
- [ ] Login-shell PATH reset and Windows `Path` casing are tested.
- [ ] Explicit `inherit_env=false` children carry the adjusted PATH.
- [ ] Package-specific tests, `moon info`, formatting, `just check`, and `just build` pass.
- [ ] Actual macOS, Linux, and Windows artifacts are inspected on their target OS.
- [ ] Agent, terminal, missing-system-command, and missing-packaged-file smoke tests pass.
