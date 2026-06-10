# Linux AppImage Packaging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make OpenSeek Desktop build on Linux and add `desktop/package_linux.mbtx`, which produces `dist/OpenSeek-Desktop-linux-x86_64.AppImage`.

**Architecture:** The Lepus framework already supports Linux (system GTK3 + webkit2gtk-4.1 via pkg-config, vendored static `libwebview.a`), and the host binary resolves `assets/` and the bundled `openseek` engine relative to its own executable directory. So no host-code changes are needed: we replicate `desktop/package_macos.mbtx` as a Linux script that lays out an AppDir by hand and runs `appimagetool` over it. The AppImage links against the *system* WebKitGTK (standard for webview AppImages) — we bundle only our two binaries plus frontend assets.

**Tech Stack:** MoonBit `.mbtx` script (`moonbitlang/async` process/fs APIs), `appimagetool` (fetched on demand), GTK3/webkit2gtk-4.1 as system deps.

**Spec:** `docs/superpowers/specs/2026-06-11-linux-appimage-design.md`

**Working directory note:** All commands below run from the monorepo root (`/home/tonyfettes/projects/openseek`) unless stated otherwise. The lepus submodule must be initialized (`git submodule update --init --recursive`).

---

### Task 1: Verify the desktop app builds on Linux

This is the "failing test" for the whole feature: run every build step the packaging script will automate, and fix anything Linux-specific that breaks. The system already has `pkg-config`, GTK3, and webkit2gtk-4.1 dev files (verified with `pkg-config --exists gtk+-3.0 webkit2gtk-4.1`).

**Files:**
- None created — build verification only. (If a step fails with a Linux-specific compile/link error, stop and report; that becomes its own fix task.)

- [ ] **Step 1: Stage the lepus codegen CLI**

Run:
```bash
cd desktop/lepus && moon install ./cli --bin target/lepus-tools
```
Expected: exits 0, `desktop/lepus/target/lepus-tools/lepus_cli` exists. Skip if the file already exists.

- [ ] **Step 2: Build the frontend JS bundle**

Run:
```bash
cd desktop && moon build frontend --target js --release
```
Expected: exits 0.

- [ ] **Step 3: Copy the bundle to `frontend.js`**

Run:
```bash
cd desktop && moon run --target native build_frontend.mbtx
```
Expected: exits 0, `desktop/frontend.js` exists.

- [ ] **Step 4: Build the native host binary**

Run:
```bash
cd desktop && moon build . --target native --release
```
Expected: exits 0, `desktop/_build/native/release/build/openseek_desktop/openseek_desktop.exe` exists. This is the step most likely to surface Linux issues (it links GTK/WebKit via `lepus/native_link_config.mjs`).

- [ ] **Step 5: Build the engine from monorepo source**

Run (from monorepo root):
```bash
moon build cmd/openseek --target native --release
```
Expected: exits 0, `_build/native/release/build/cmd/openseek/openseek.exe` exists.

- [ ] **Step 6: Confirm the host binary links against system webkit**

Run:
```bash
ldd desktop/_build/native/release/build/openseek_desktop/openseek_desktop.exe | grep -E "webkit|gtk" | head -5
```
Expected: lines mentioning `libwebkit2gtk-4.1.so` and `libgtk-3.so` (confirms dynamic linkage to system libs, as the design assumes).

No commit for this task — it produces no source changes.

---

### Task 2: Write `desktop/package_linux.mbtx`

**Files:**
- Create: `desktop/package_linux.mbtx`

- [ ] **Step 1: Create the script**

Write `desktop/package_linux.mbtx` with exactly this content. It mirrors `desktop/package_macos.mbtx` (same `Workspace`, `run_checked`, and build functions) with the macOS bundle/sign/zip stages replaced by AppDir layout + appimagetool:

```moonbit
///|
import {
  "moonbitlang/async@0.19.1",
  "moonbitlang/async@0.19.1/fs",
  "moonbitlang/async@0.19.1/io",
  "moonbitlang/async@0.19.1/process",
  "moonbitlang/core/string",
}

///|
const FrontendPackage : String = "frontend"

///|
const NativePackage : String = "."

///|
const NativeBinary : String =
  "_build/native/release/build/openseek_desktop/openseek_desktop.exe"

///|
/// The openseek engine package, built from the monorepo root (one level up
/// from this desktop workspace) so the bundled engine always matches the
/// checkout instead of whatever happens to be on PATH.
const EnginePackage : String = "cmd/openseek"

///|
/// Path to the freshly built engine binary, relative to the desktop workspace.
const EngineBinary : String =
  "../_build/native/release/build/cmd/openseek/openseek.exe"

///|
/// Path to the lepus codegen CLI, staged inside the submodule. The clipboard
/// extension's pre-build step shells out to it, so a fresh checkout must build
/// it before the native target can link.
const CodegenTool : String = "lepus/target/lepus-tools/lepus_cli"

///|
const AppDirPath : String = "dist/OpenSeek-Desktop.AppDir"

///|
const AppImagePath : String = "dist/OpenSeek-Desktop-linux-x86_64.AppImage"

///|
const UsrBinPath : String = AppDirPath + "/usr/bin"

///|
const AppAssetDir : String = UsrBinPath + "/assets"

///|
/// Where a downloaded appimagetool is cached between runs. Lives outside the
/// AppDir so reset_bundle_dirs never deletes it.
const AppImageToolCache : String = "dist/tools/appimagetool"

///|
const AppImageToolUrl : String =
  "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"

///|
suberror PackageError {
  PackageError(String)
}

///|
/// The desktop workspace this script packages. Every command runs with the
/// workspace as its working directory and every path is joined onto it, so the
/// script works both from inside the workspace (`moon run package_linux.mbtx`)
/// and from the monorepo root (`moon run desktop/package_linux.mbtx`).
priv struct Workspace {
  dir : String
}

///|
async fn locate_workspace() -> Workspace raise {
  for candidate in [".", "desktop"] {
    if @fs.exists(candidate + "/package_linux.mbtx") &&
      @fs.exists(candidate + "/lepus") {
      return { dir: candidate }
    }
  }
  raise PackageError(
    "cannot locate the desktop workspace; run from the desktop directory or the monorepo root",
  )
}

///|
fn Workspace::at(self : Workspace, relative : String) -> String {
  self.dir + "/" + relative
}

///|
/// The monorepo root, one level up from the desktop workspace.
fn Workspace::repo(self : Workspace) -> String {
  self.dir + "/.."
}

///|
async fn run_checked(
  command : String,
  args : Array[String],
  dir~ : String,
) -> Unit raise {
  let joined_args = args.join(" ")
  println("$ [\{dir}] \{command} \{joined_args}")
  let code = @process.run(command, args, inherit_env=true, cwd=dir.view())
  if code != 0 {
    raise PackageError("command failed with exit code \{code}: \{command}")
  }
}

///|
/// Build the openseek engine from the monorepo source. Runs from the repo root
/// since the engine lives in a separate moon module from this desktop
/// workspace.
async fn build_engine(ws : Workspace) -> Unit raise {
  run_checked(
    "moon",
    ["build", EnginePackage, "--target", "native", "--release"],
    dir=ws.repo(),
  )
  if !@fs.exists(ws.at(EngineBinary)) {
    raise PackageError(
      "openseek engine binary not found: \{ws.at(EngineBinary)}",
    )
  }
}

///|
/// Build the lepus codegen CLI into the submodule if it is not already staged.
async fn ensure_codegen_tool(ws : Workspace) -> Unit raise {
  if @fs.exists(ws.at(CodegenTool)) {
    return
  }
  run_checked(
    "moon",
    ["install", "./cli", "--bin", "target/lepus-tools"],
    dir=ws.at("lepus"),
  )
}

///|
async fn build_outputs(ws : Workspace) -> Unit raise {
  ensure_codegen_tool(ws)
  run_checked(
    "moon",
    ["build", FrontendPackage, "--target", "js", "--release"],
    dir=ws.dir,
  )
  run_checked(
    "moon",
    ["run", "--target", "native", "build_frontend.mbtx"],
    dir=ws.dir,
  )
  run_checked(
    "moon",
    ["build", NativePackage, "--target", "native", "--release"],
    dir=ws.dir,
  )
  build_engine(ws)
}

///|
async fn reset_bundle_dirs(ws : Workspace) -> Unit raise {
  run_checked("rm", ["-rf", AppDirPath, AppImagePath], dir=ws.dir)
  run_checked(
    "mkdir",
    ["-p", UsrBinPath, AppAssetDir, "dist/tools"],
    dir=ws.dir,
  )
}

///|
async fn copy_bundle_files(ws : Workspace) -> Unit raise {
  if !@fs.exists(ws.at(NativeBinary)) {
    raise PackageError("native binary not found: \{ws.at(NativeBinary)}")
  }
  run_checked(
    "cp",
    [NativeBinary, UsrBinPath + "/openseek-desktop-bin"],
    dir=ws.dir,
  )
  run_checked("cp", [EngineBinary, UsrBinPath + "/openseek"], dir=ws.dir)
  run_checked("cp", ["index.html", AppAssetDir + "/index.html"], dir=ws.dir)
  run_checked("cp", ["frontend.js", AppAssetDir + "/frontend.js"], dir=ws.dir)
}

///|
/// The AppRun launcher resolves its own absolute directory and execs the host
/// binary; every resource lookup in the host derives from the executable's
/// path, and the engine is found on PATH next to it. Mirrors the macOS
/// launcher: it deliberately does NOT `cd` into the AppDir, since the host
/// keeps its runtime state in absolute per-user paths.
fn apprun_source() -> String {
  let source = #|#!/bin/sh
  #|set -eu
  #|
  #|APP_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
  #|export PATH="$APP_DIR/usr/bin:$PATH"
  #|exec "$APP_DIR/usr/bin/openseek-desktop-bin" "$@"
  #|
  source
}

///|
fn desktop_entry_source() -> String {
  let source = #|[Desktop Entry]
  #|Type=Application
  #|Name=OpenSeek Desktop
  #|Exec=openseek-desktop-bin
  #|Icon=openseek-desktop
  #|Categories=Development;
  #|Terminal=false
  #|
  source
}

///|
fn icon_source() -> String {
  let source = #|<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
  #|  <rect width="256" height="256" rx="48" fill="#1a1b26"/>
  #|  <circle cx="128" cy="128" r="64" fill="none" stroke="#7aa2f7" stroke-width="16"/>
  #|  <circle cx="128" cy="128" r="20" fill="#7aa2f7"/>
  #|</svg>
  #|
  source
}

///|
async fn write_bundle_metadata(ws : Workspace) -> Unit raise {
  @fs.write_file(
    ws.at(AppDirPath) + "/AppRun",
    apprun_source(),
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    ws.at(AppDirPath) + "/openseek-desktop.desktop",
    desktop_entry_source(),
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    ws.at(AppDirPath) + "/openseek-desktop.svg",
    icon_source(),
    create_mode=CreateOrTruncate,
  )
  // appimagetool uses .DirIcon as the AppImage's embedded icon.
  run_checked(
    "ln",
    ["-sf", "openseek-desktop.svg", AppDirPath + "/.DirIcon"],
    dir=ws.dir,
  )
  run_checked(
    "chmod",
    [
      "+x",
      AppDirPath + "/AppRun",
      UsrBinPath + "/openseek-desktop-bin",
      UsrBinPath + "/openseek",
    ],
    dir=ws.dir,
  )
}

///|
/// Resolve an appimagetool to run: a previously downloaded copy, then one on
/// PATH, then a fresh download of the official release.
async fn ensure_appimagetool(ws : Workspace) -> String raise {
  if @fs.exists(ws.at(AppImageToolCache)) {
    return AppImageToolCache
  }
  let probe = @process.run(
    "sh",
    ["-c", "command -v appimagetool >/dev/null 2>&1"],
    inherit_env=true,
    cwd=ws.dir.view(),
  )
  if probe == 0 {
    return "appimagetool"
  }
  run_checked(
    "curl",
    ["-fL", "-o", AppImageToolCache, AppImageToolUrl],
    dir=ws.dir,
  )
  run_checked("chmod", ["+x", AppImageToolCache], dir=ws.dir)
  AppImageToolCache
}

///|
/// APPIMAGE_EXTRACT_AND_RUN lets the appimagetool AppImage run without FUSE;
/// ARCH pins the output architecture (the vendored webview lib is x64-only).
async fn build_appimage(ws : Workspace, tool : String) -> Unit raise {
  run_checked(
    "env",
    [
      "APPIMAGE_EXTRACT_AND_RUN=1",
      "ARCH=x86_64",
      tool,
      AppDirPath,
      AppImagePath,
    ],
    dir=ws.dir,
  )
}

///|
async fn main raise {
  let ws = locate_workspace()
  build_outputs(ws)
  println("built openseek engine: \{ws.at(EngineBinary)}")
  reset_bundle_dirs(ws)
  copy_bundle_files(ws)
  write_bundle_metadata(ws)
  let tool = ensure_appimagetool(ws)
  build_appimage(ws, tool)
  println("generated \{ws.at(AppImagePath)}")
}
```

- [ ] **Step 2: Type-check the script**

Run:
```bash
cd desktop && moon check package_linux.mbtx --target native
```
Expected: exits 0 with no errors. If `moon check` does not accept a single `.mbtx` argument in this toolchain version, substitute the dry confirmation in Task 3 Step 1 (running the script) as the check.

If the check fails on API details (e.g. `@process.run` parameter names, `@fs.write_file` modes), compare against `desktop/package_macos.mbtx` — it uses the identical APIs and is known to compile; make the Linux script match its usage exactly.

- [ ] **Step 3: Commit**

```bash
git add desktop/package_linux.mbtx
git commit -m "feat(desktop): add Linux AppImage packaging script

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Run the packaging script end-to-end and verify the AppImage

**Files:**
- None created in-repo (outputs land in `desktop/dist/`, which should be untracked — confirm `git status` stays clean apart from intended files).

- [ ] **Step 1: Run the packaging script**

Run (from monorepo root):
```bash
moon run --target native ./desktop/package_linux.mbtx
```
Expected: every `$ [...]` step echoes and exits 0; final lines:
```
generated desktop/dist/OpenSeek-Desktop-linux-x86_64.AppImage
```
First run downloads appimagetool to `desktop/dist/tools/appimagetool` (~6 MB) unless one is on PATH.

- [ ] **Step 2: Inspect the AppImage**

Run:
```bash
ls -la desktop/dist/OpenSeek-Desktop-linux-x86_64.AppImage && file desktop/dist/OpenSeek-Desktop-linux-x86_64.AppImage
```
Expected: the file exists, is executable, and `file` reports an ELF executable (AppImages are ELF with embedded squashfs).

- [ ] **Step 3: Launch the AppImage and confirm it stays up**

Run:
```bash
cd desktop/dist && APPIMAGE_EXTRACT_AND_RUN=1 ./OpenSeek-Desktop-linux-x86_64.AppImage & APP_PID=$!; sleep 5; kill -0 $APP_PID && echo "ALIVE" || echo "DEAD"; kill $APP_PID 2>/dev/null
```
Expected: `ALIVE` — the host process survived 5 seconds, meaning the webview window opened and assets loaded (the host exits immediately on missing assets). `APPIMAGE_EXTRACT_AND_RUN=1` sidesteps FUSE so this works regardless of whether `fuse2` is installed. Requires a graphical session (`$DISPLAY`/`$WAYLAND_DISPLAY` set); if running headless, report that this step needs a manual check by the user instead of faking it.

- [ ] **Step 4: Ask the user to verify interactively (checkpoint)**

The automated check only proves the window opens. Ask the user to launch the AppImage and confirm a prompt round-trips through the bundled engine (sessions list loads, a message streams back). This is a verification checkpoint, not a code step.

---

### Task 4: Document Linux packaging in the README

**Files:**
- Modify: `desktop/README.md` (append after the "Package (macOS)" section)

- [ ] **Step 1: Add the Linux section**

Append this to `desktop/README.md`, directly after the macOS packaging section:

```markdown
## Package (Linux)

`package_linux.mbtx` runs the same build steps (including the codegen
bootstrap), builds the `openseek` engine from the monorepo's `cmd/openseek`
source, and produces `dist/OpenSeek-Desktop-linux-x86_64.AppImage`:

```sh
moon run --target native package_linux.mbtx
# or, from the monorepo root:
moon run --target native ./desktop/package_linux.mbtx
```

Build requirements: `pkg-config` plus the GTK3 and WebKitGTK dev packages
(`libgtk-3-dev` and `libwebkit2gtk-4.1-dev` on Debian/Ubuntu; `gtk3` and
`webkit2gtk-4.1` on Arch), and `curl` (used to fetch `appimagetool` on first
run if it is not already on `PATH`).

The AppImage bundles the desktop host, the engine, and the frontend assets,
but links against the system WebKitGTK: running it requires GTK3 and
`libwebkit2gtk-4.1` installed on the host system, which is the standard
arrangement for webview-based AppImages. If your system lacks FUSE2, run it
with `APPIMAGE_EXTRACT_AND_RUN=1`.
```

(Note: the inner ```sh fence is nested inside the markdown block above — in the actual README it is a normal top-level code fence, matching the macOS section's formatting.)

- [ ] **Step 2: Commit**

```bash
git add desktop/README.md
git commit -m "docs(desktop): document Linux AppImage packaging

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Self-review notes

- **Spec coverage:** system-webkit decision → Task 1 Step 6 + Task 4 docs; hand-rolled AppDir layout → Task 2 (`copy_bundle_files`, `write_bundle_metadata`); appimagetool acquisition with PATH-then-download and `APPIMAGE_EXTRACT_AND_RUN=1` → Task 2 (`ensure_appimagetool`, `build_appimage`); output name → `AppImagePath` const; README section → Task 4; verification → Task 3. No CI work (out of scope per spec).
- **Risk:** `.mbtx` single-file script APIs (`@process.run`, `@fs.write_file`) are copied verbatim from the compiling `package_macos.mbtx`, so API drift is unlikely; Task 2 Step 2 catches it if so.
- The `ln -sf` for `.DirIcon` is the one addition beyond the spec's file list — appimagetool expects it for the embedded icon and warns/fails without it on some versions.
