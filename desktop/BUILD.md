# Desktop build

The Desktop build has one sequential implementation:
`package/build.mjs`. It runs on Node 22 and uses only Node's standard library
plus the project tools already required by the build (`moon`, `moonx`, `curl`,
and `tar`).

| Owner | Responsibility |
| --- | --- |
| Moon | Compile the host, engine, and JavaScript frontends. |
| `package/build.mjs` | Download verified browser/native inputs, generate browser assets, and stage SeekMoon resources. |
| Proton | Run development CEF, create packages, sign, and notarize. |

The packages at `package/macos`, `package/windows`, `package/linux`,
`package/browser`, and `package/dev` preserve the existing `moon run`
commands. Each contains only a main function that forwards untouched arguments
through `package/internal/cli`; all parsing and build decisions live in
`build.mjs`.

## Commands

From the repository root:

```sh
# Current host's debug package
just desktop-package

# Development host
just desktop-dev

# Browser console
moon run ./desktop/package/browser

# Static checks for the build program and Moon entry packages
just desktop-build-scripts-check
```

The platform commands remain compatible:

```sh
# macOS; defaults to a debug app and opens it
moon run ./desktop/package/macos
moon run ./desktop/package/macos -- \
  --release --no-open --target dmg --target zip \
  --sign "Developer ID Application: Name (TEAMID)" \
  --notarize openseek

# Windows; defaults to ZIP and installer
moon run ./desktop/package/windows
moon run ./desktop/package/windows -- --release --target zip

# Linux AppImage
moon run ./desktop/package/linux -- --release

# Browser release and development host
moon run ./desktop/package/browser -- --release
moon run ./desktop/package/dev
```

Browser inputs and the standalone esbuild executable are fixed-version
upstream distributions with checked-in SHA-256 digests. Builds cache only
their downloaded archives; extraction and generated files are recreated on
every run.

`--notarize` requires `--sign` and `--target dmg`. `--sign` requires a
distribution target (`dmg` or `zip`). A failed ripgrep SHA-256 check deletes
the invalid archive and stops immediately.

## Execution order

Package commands perform these steps:

1. download and verify pinned Mermaid/xterm and standalone esbuild archives, then build the browser assets;
2. Moon frontend, viz, host, and engine builds;
3. Proton CEF setup;
4. ripgrep download and SHA-256 verification;
5. MoonBit seed download and `moonc -v` verification;
6. staging of the fixed `seekmoon/` tree;
7. one `proton_cli package` invocation for the requested formats.

`package/dev` builds the frontend, viz, and engine, then calls
`proton_cli dev --no-frontend --setup`. Proton supplies the CEF environment and
runs the Desktop package; there is no second development launcher.

## Resource tree

All installed platforms receive the same application-owned tree:

```text
seekmoon/
  web/
    index.html
    frontend.js
    app.css
    viewer.css
    codicon.ttf
    xterm.js
    xterm.css
    mermaid/
    fonts/
    viz/
  bin/
    openseek[.exe]
    rg[.exe]
  toolchains/moonbit/<platform>/
  licenses/ripgrep/
```

`proton.project.json` includes `seekmoon/**`. Runtime code starts at
`@proton.resource_dir()` and appends paths below this tree. The platform outer
directories remain Proton details:

- macOS: `SeekMoon.app/Contents/Resources/seekmoon/`
- Linux: `usr/Resources/seekmoon/`
- Windows: `Resources/seekmoon/`

On macOS, native package objects use `target/moonbuild/macos-12.0` so
`MACOSX_DEPLOYMENT_TARGET=12.0` cannot reuse an incompatible Moon cache entry.
On Windows, only the staged engine copy has its PE subsystem changed to GUI.

Downloaded archives stay under `desktop/target/`. Generated browser assets are
written below `desktop/target/web/`; source entrypoints live under
`desktop/frontend/build/`.

## Validation limits

The shared JavaScript parses on every host, but final native packages must
still be tested on their target operating systems. In particular, validate
AppImage dependencies on Linux, the portable ZIP and installer on Windows, and
the actual signatures and notarization ticket on macOS.
