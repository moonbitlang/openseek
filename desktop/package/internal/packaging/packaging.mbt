///|
/// The desktop shell entry. Its `frontend/browser` sibling is the console
/// bundle served by openseek-api and is not shipped inside the desktop app.
const FrontendPackage : String = "frontend/desktop"

///|
/// The JS bundle's path below MoonBit's target/profile build directory.
const FrontendBundleArtifact : String = "build/openseek_desktop/frontend/desktop/desktop.js"

///|
/// The stable path the host and packagers read the frontend bundle from.
const FrontendBundleOutput : String = "frontend.js"

///|
/// The generated application stylesheet staged by production packagers.
/// Development keeps loading the checked-in `app.css` import manifest, while
/// packaged layouts receive this single concatenated file under that name.
const AppStyleOutput : String = "app.generated.css"

///|
/// The stylesheet the embedded code viewer needs, assembled from the editor
/// dependency's CSS. `index.html` links it by this name next to `frontend.js`.
const ViewerStyleOutput : String = "viewer.css"

///|
/// Application CSS sources in cascade order, relative to the desktop module.
/// Keep the checked-in `app.css` development imports in the same order.
fn app_css_sources() -> Array[String] {
  [
    "app_font.css", "styles/tokens.css", "styles/base.css", "styles/terminal.css",
    "styles/file_panel.css", "styles/sidebar.css", "styles/main_header.css", "styles/transcript.css",
    "styles/composer.css", "styles/codex.css", "styles/pages.css", "styles/overlays.css",
    "styles/responsive.css",
  ]
}

///|
/// The editor workspace member. The viewer's reusable CSS and font assets are
/// read from the same checkout as the desktop that imports its MoonBit
/// packages. The path is relative to the monorepo root and therefore resolves
/// through `repo_at`, not `at`.
const EditorDepRoot : String = "editor"

///|
/// The published editor package deliberately excludes its reference shell,
/// including that shell's theme. The desktop owns this small theme bridge so
/// the reusable viewer styles still receive their `--vscode-*` variables.
const ViewerThemeSource : String = "viewer_theme.css"

///|
/// The editor CSS files the embedded viewer depends on (relative to
/// `EditorDepRoot`), in cascade order. Re-sync this list on an editor version
/// bump. Reference-shell CSS is deliberately absent from the package; the
/// desktop supplies its own theme, panel layout, and file tree.
fn viewer_css_sources() -> Array[String] {
  [
    "viewer/browser/view/codicon/codicon.css", "viewer/browser/view/editor.css",
    "viewer/ui/scrollbar/scrollable_element.css", "viewer/browser/view_parts/view_lines/view_lines.css",
    "viewer/browser/view_parts/selections/view_overlays.css", "viewer/browser/view_parts/content_widgets/content_widgets.css",
    "viewer/browser/view_parts/overlay_widgets/overlay_widgets.css", "viewer/browser/view_parts/selections/selections.css",
    "viewer/browser/view_parts/current_line_highlight/current_line_highlight.css",
    "viewer/browser/view_parts/decorations/decorations.css", "viewer/browser/view_parts/view_cursors/view_cursors.css",
    "viewer/browser/view_parts/margin/margin.css", "viewer/browser/view_parts/margin/lines_decorations.css",
    "viewer/browser/view_parts/view_lines/tokens.css", "viewer/browser/view_parts/view_lines/markers.css",
    "viewer/browser/diff_editor/diff_editor.css", "viewer/contrib/folding/browser/folding.css",
    "viewer/contrib/contextmenu/browser/contextmenu.css", "viewer/contrib/definition/browser/definition.css",
    "viewer/contrib/references/browser/references.css", "viewer/contrib/hover/hover.css",
    "viewer/contrib/quick_diff/browser/quick_diff.css", "viewer/browser/unified_diff/unified_diff.css",
    "viewer/contrib/agent_feedback/browser/agent_feedback.css", "viewer/browser/diagram_viewport/diagram_viewport.css",
    "viewer/contrib/markdown_comments/browser/markdown_comments.css", "internal/viewer/browser/markdown_document/markdown_document.css",
  ]
}

///|
/// The vendored codicon icon font `codicon.css`'s `@font-face` loads at the
/// site root (`url("/codicon.ttf")`), exactly like the editor's own web
/// build serves it. Proton resolves `/codicon.ttf` against the
/// `proton://app/` origin and maps it to the asset directory root, so the
/// desktop ships the upstream CSS unmodified and just places the font next
/// to `viewer.css`.
const CodiconFontSource : String = "viewer/browser/view/codicon/codicon.ttf"

///|
const CodiconFontOutput : String = "codicon.ttf"

///|
/// The verified Mermaid runtime staged by the editor-owned asset builder. The
/// platform packagers copy this tree beside their frontend bundle.
const MermaidAssetOutput : String = "target/vendor-mermaid/dist"

///|
const NativePackage : String = "."

///|
const NativeBinary : String = "build/openseek_desktop/openseek_desktop.exe"

///|
const EnginePackage : String = "cmd/openseek"

///|
const EngineBinary : String = "build/bobzhang/openseek/cmd/openseek/openseek.exe"

///|
/// Raised when a packaging helper cannot complete a filesystem, build, or
/// toolchain step.
///
/// The `Show` impl renders the payload message: an uncaught `PackageError`
/// surfaces through the async runtime's `println(err)` (via the
/// `%error.to_string` intrinsic), which would otherwise print only the
/// qualified constructor name and drop the message.
pub(all) suberror PackageError {
  /// A packaging failure with a human-readable diagnostic.
  PackageError(String)
}

///|
pub impl Show for PackageError with fn output(self, logger) {
  match self {
    PackageError(message) => logger.write_string("package error: \{message}")
  }
}

///|
/// The desktop workspace being packaged. The value is opaque to callers so
/// all path decisions stay centralized here. `root` is absolute, so every
/// path derived from it is absolute too and a subprocess's working directory
/// can never change which file a path names.
struct Workspace {
  // Absolute, normalized path to the desktop workspace directory.
  root : String
}

///|
/// Locate the desktop workspace from either the workspace directory itself or
/// the monorepo root. The matched directory is resolved to an absolute path so
/// later path math is independent of any later working-directory change.
pub async fn locate_workspace() -> Workspace {
  for candidate in [".", "desktop"] {
    if @asyncfs.exists(candidate + "/moon.mod") &&
      @asyncfs.exists(candidate + "/frontend") {
      return { root: absolute_path(candidate) }
    }
  }
  raise PackageError(
    "cannot locate the desktop workspace; run from the desktop directory or the monorepo root",
  )
}

///|
/// Return the absolute desktop workspace directory.
pub fn Workspace::dir(self : Workspace) -> String {
  self.root
}

///|
/// Resolve a path relative to the desktop workspace directory, as an absolute
/// path.
pub fn Workspace::at(self : Workspace, relative : String) -> String {
  join_path(self.root, relative)
}

///|
/// The monorepo root, one level up from the desktop workspace, absolute.
pub fn Workspace::repo(self : Workspace) -> String {
  (self.root : @path.Path).dirname().to_string()
}

///|
/// Resolve a path relative to the monorepo root, as an absolute path.
pub fn Workspace::repo_at(self : Workspace, relative : String) -> String {
  join_path(self.repo(), relative)
}

///|
/// Return the staged local Mermaid runtime directory.
pub fn Workspace::mermaid_assets(self : Workspace) -> String {
  self.at(MermaidAssetOutput)
}

///|
/// Return the generated application stylesheet consumed by package layouts.
pub fn Workspace::app_stylesheet(self : Workspace) -> String {
  self.at(AppStyleOutput)
}

///|
/// Join `relative` onto an absolute `base` using host path rules, yielding an
/// absolute path. Centralizing the join keeps every workspace path absolute.
fn join_path(base : String, relative : String) -> String {
  (base : @path.Path).join((relative : @path.Path)).to_string()
}

///|
/// Return the selected-mode native desktop host binary path under the
/// monorepo root, where the single root moon.work places all build output.
pub fn Workspace::native_binary(self : Workspace, release~ : Bool) -> String {
  let mode = if release { "release" } else { "debug" }
  self.repo_at("_build/native/\{mode}/\{NativeBinary}")
}

///|
/// Return the selected-mode openseek engine binary path under the monorepo
/// root.
pub fn Workspace::engine_binary(self : Workspace, release~ : Bool) -> String {
  let mode = if release { "release" } else { "debug" }
  self.repo_at("_build/native/\{mode}/\{EngineBinary}")
}

///|
/// Return the selected-mode JavaScript frontend artifact emitted by Moon.
/// Development serves this file in place; packagers copy the same artifact
/// into their stable resource layout.
pub fn Workspace::frontend_binary(self : Workspace, release~ : Bool) -> String {
  let mode = if release { "release" } else { "debug" }
  self.repo_at("_build/js/\{mode}/\{FrontendBundleArtifact}")
}

///|
/// Read the desktop module version used as the package source of truth.
/// Proton writes this value into its package manifest; platform tooling that
/// has not migrated to Proton yet reads the same field instead of keeping a
/// second version constant.
pub async fn Workspace::module_version(self : Workspace) -> String {
  let manifest = self.at("moon.mod")
  let text = @asyncfs.read_file(manifest).text()
  for line in text.split("\n") {
    let line = line.trim().to_owned()
    if line.has_prefix("version = \"") && line.has_suffix("\"") {
      let version = line
        .unsafe_substring(start=11, end=line.length() - 1)
        .to_string()
      if !version.is_empty() {
        return version
      }
    }
  }
  raise PackageError("desktop version not found in \{manifest}")
}

///|
/// Return the openseek engine package path relative to the monorepo root.
pub fn engine_package() -> String {
  EnginePackage
}

///|
/// How the desktop module spells its dependency on the Proton library.
const ProtonPackagePrefix : String = "moonbit-community/proton@"

///|
/// The pinned Proton release, read back from the desktop module's own
/// dependency on the Proton library. `moonbit-community/proton_cli` and
/// `moonbit-community/proton` are published together from one version line,
/// so deriving the CLI from the library pin keeps `moon.mod` the single place
/// a Proton bump is spelled — a second constant here would silently drift.
pub async fn Workspace::proton_version(self : Workspace) -> String {
  let manifest = self.at("moon.mod")
  let text = @asyncfs.read_file(manifest).text()
  for line in text.split("\n") {
    for field in line.split("\"") {
      if field.strip_prefix(ProtonPackagePrefix) is Some(version) &&
        !version.is_empty() {
        return version.to_owned()
      }
    }
  }
  raise PackageError("no \{ProtonPackagePrefix}<version> found in \{manifest}")
}

///|
/// The registry coordinate `moonx` resolves the Proton CLI from.
async fn Workspace::proton_cli_package(self : Workspace) -> String {
  "moonbit-community/proton_cli@\{self.proton_version()}"
}

///|
/// `cef setup` runs at the monorepo root, not in the desktop workspace: the
/// root is where Moon resolves `.mooncakes`, and the Proton package's
/// platform prebuilt below it is what the CLI assembles the runtime from.
/// The manifest it writes (`.proton/runtime.json`) lands beside them.
fn Workspace::proton_project_dir(self : Workspace) -> String {
  self.repo()
}

///|
/// The Proton package's platform prebuilts below the monorepo's resolved
/// dependency tree. `cef setup` copies these artifacts verbatim into the
/// assembled runtime, so they are also what the staleness check compares
/// against.
const ProtonPrebuiltRoot : String = ".mooncakes/moonbit-community/proton/prebuilt"

///|
fn Workspace::proton_project_at(self : Workspace, relative : String) -> String {
  join_path(self.proton_project_dir(), relative)
}

///|
/// Run the pinned Proton CLI. `moonx` fetches the published executable into
/// the registry cache and runs it straight from there, so there is no install
/// step, no binary of ours to keep fresh, and no per-host path to spell.
/// `args` is the CLI's own grammar, `-C` included: the callers do not agree on
/// one root, since `cef setup` reads the monorepo's resolved dependencies
/// while `package` acts on the desktop workspace.
pub async fn run_proton_cli(
  ws : Workspace,
  args : Array[String],
  extra_env? : Map[String, String] = Map([]),
) -> Unit {
  run_checked(
    "moonx",
    [ws.proton_cli_package(), ..args],
    dir=ws.dir(),
    extra_env~,
  )
}

///|
/// Ensure a Proton CEF runtime matching this checkout is available. A complete
/// runtime recorded by `.proton/runtime.json` is reused by development and all
/// platform packagers; `cef setup` runs only when that runtime is missing,
/// incomplete, or belongs to another platform or Proton version.
pub async fn ensure_cef_runtime(
  ws : Workspace,
  extra_env? : Map[String, String] = Map([]),
) -> Unit {
  let cached = try ws.validated_proton_runtime_dist() catch {
    error if @async.is_being_cancelled() => raise error
    error => {
      println("existing Proton runtime cannot be reused: \{error}")
      None
    }
  } noraise {
    dist => Some(dist)
  }
  if cached is Some(dist) {
    println("reusing Proton CEF runtime: \{dist}")
    return
  }
  run_proton_cli(
    ws,
    ["-C", ws.proton_project_dir(), "cef", "setup"],
    extra_env~,
  )
  let dist = ws.validated_proton_runtime_dist()
  println("prepared Proton CEF runtime: \{dist}")
}

///|
/// Read the Proton runtime dist directory from `.proton/runtime.json`, the
/// manifest `cef setup` writes. Current Proton CLIs record an absolute path
/// into the user-level runtime cache, while older manifests recorded a path
/// relative to the Proton project root; both classify to an absolute path
/// here. Raises when the manifest is missing or malformed.
pub async fn proton_runtime_dist(ws : Workspace) -> @pathx.Absolute {
  ws.proton_runtime_path_field("dist")
}

///|
/// Read the exact CEF distribution selected by Proton. The active manifest
/// records an absolute path because the cache may live in the shared user-level
/// `~/.proton/cache/cef` directory or a `PROTON_CEF_CACHE` override; consumers
/// must not reconstruct the older project-local cache layout.
async fn Workspace::proton_cef_root(self : Workspace) -> @pathx.Absolute {
  self.proton_runtime_path_field("cef")
}

///|
/// The Proton project checkout as a typed absolute root. The workspace root is
/// absolute by construction, so resolving restates that invariant in the type
/// instead of consulting the working directory.
fn Workspace::proton_project_root(self : Workspace) -> @pathx.Absolute {
  @pathx.Path(self.proton_project_dir()).resolve()
}

///|
/// Classify a path recorded in a Proton manifest. The Proton CLI records
/// absolute cache paths, while older manifests recorded paths relative to the
/// Proton project root; a relative spelling therefore resolves against that
/// checkout rather than the working directory.
fn Workspace::proton_manifest_path(
  self : Workspace,
  fields : Map[String, Json],
  manifest : String,
  field : String,
) -> @pathx.Absolute raise PackageError {
  let path = @pathx.Path(
    Workspace::proton_manifest_string(fields, manifest, field),
  )
  if path.to_relative() is Some(relative) {
    self.proton_project_root().join(relative)
  } else {
    // Already host-absolute, so resolving only restates the classification.
    path.resolve()
  }
}

///|
/// Read one Proton JSON manifest as an object. Keeping parsing here lets the
/// reuse check compare the active and checked-in manifests without running
/// the Proton CLI.
async fn Workspace::read_proton_manifest(
  manifest : String,
) -> Map[String, Json] {
  if !@asyncfs.exists(manifest) {
    raise PackageError("Proton runtime manifest not found: \{manifest}")
  }
  let text = @asyncfs.read_file(manifest).text()
  match @json.parse(text) {
    Object(fields) => fields
    _ => raise PackageError("Proton runtime manifest is not an object: \{text}")
  }
}

///|
/// Read a required string from a parsed Proton manifest.
fn Workspace::proton_manifest_string(
  fields : Map[String, Json],
  manifest : String,
  field : String,
) -> String raise PackageError {
  if fields.get(field) is Some(String(value)) {
    return value
  }
  raise PackageError(
    "Proton runtime manifest has no string field \"\{field}\": \{manifest}",
  )
}

///|
/// Read a path field from the active runtime manifest written by `cef setup`.
async fn Workspace::proton_runtime_path_field(
  self : Workspace,
  field : String,
) -> @pathx.Absolute {
  let manifest = self.proton_project_at(".proton/runtime.json")
  let fields = Workspace::read_proton_manifest(manifest)
  self.proton_manifest_path(fields, manifest, field)
}

///|
/// Return the one Proton platform supported by each desktop packager. These
/// names are also the directory names below `ProtonPrebuiltRoot`.
fn Workspace::proton_platform() -> String raise PackageError {
  if @platform.win32 || @platform.win64 {
    "win32-x64"
  } else if @platform.apple_os_mac {
    "darwin-arm64"
  } else if @platform.linux {
    "linux-x64"
  } else {
    raise PackageError("CEF packaging is unsupported on this platform")
  }
}

///|
/// Files the desktop build and launcher consume from an assembled runtime.
/// Checking the complete Proton-required layout prevents a partially removed
/// runtime from being mistaken for a cache hit.
fn Workspace::proton_runtime_required_files(
  platform : String,
) -> Array[String] raise PackageError {
  match platform {
    "win32-x64" =>
      [
        "bin/proton.dll", "bin/cef_process.exe", "lib/proton.lib", "include/proton_native.h",
        "bin/libcef.dll", "bin/icudtl.dat", "Resources/icudtl.dat", "Resources/locales",
      ]
    "linux-x64" =>
      [
        "bin/cef_process", "lib/libproton.so", "include/proton_native.h", "bin/libcef.so",
        "bin/icudtl.dat", "bin/v8_context_snapshot.bin", "Resources/icudtl.dat",
        "Resources/locales",
      ]
    "darwin-arm64" =>
      [
        "bin/cef_process", "lib/libproton.dylib", "include/proton_native.h", "bin/libEGL.dylib",
        "bin/libGLESv2.dylib", "bin/libvk_swiftshader.dylib", "Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework",
        "Frameworks/Chromium Embedded Framework.framework/Libraries/libcef_sandbox.dylib",
        "Resources/icudtl.dat",
      ]
    _ => raise PackageError("unsupported Proton runtime platform: \{platform}")
  }
}

///|
/// Resolve and validate the existing runtime without installing or invoking
/// the Proton CLI. The active platform must match this packager, the resolved
/// Proton package's prebuilt must have the same Proton version, every runtime
/// file consumed by Proton must exist, and the runtime must still carry the
/// exact bytes of that prebuilt's artifacts. The runtime carries no manifest
/// of its own: `cef setup` names the dist directory after the prebuilt and
/// CEF identities, so the active manifest is the one record of its
/// location.
async fn Workspace::validated_proton_runtime_dist(
  self : Workspace,
) -> @pathx.Absolute {
  let active_path = self.proton_project_at(".proton/runtime.json")
  let active = Workspace::read_proton_manifest(active_path)
  let platform = Workspace::proton_manifest_string(
    active, active_path, "platform",
  )
  let expected_platform = Workspace::proton_platform()
  if platform != expected_platform {
    raise PackageError(
      "Proton runtime platform mismatch: expected \{expected_platform}, got \{platform}",
    )
  }
  let prebuilt_path = self.proton_project_at(
    "\{ProtonPrebuiltRoot}/\{platform}/manifest.json",
  )
  let prebuilt = Workspace::read_proton_manifest(prebuilt_path)
  let prebuilt_platform = Workspace::proton_manifest_string(
    prebuilt, prebuilt_path, "platform",
  )
  if prebuilt_platform != platform {
    raise PackageError(
      "Proton prebuilt platform mismatch: expected \{platform}, got \{prebuilt_platform}",
    )
  }
  let active_version = Workspace::proton_manifest_string(
    active, active_path, "proton_version",
  )
  let prebuilt_version = Workspace::proton_manifest_string(
    prebuilt, prebuilt_path, "proton_version",
  )
  if active_version != prebuilt_version {
    raise PackageError(
      "Proton runtime version mismatch: expected \{prebuilt_version}, got \{active_version}",
    )
  }
  let dist = self.proton_manifest_path(active, active_path, "dist")
  // Nothing rewrites the dist after `cef setup` assembles it, so on every
  // platform it must still carry the prebuilt's exact bytes. The version
  // comparison above cannot stand in for this: a republished prebuilt keeps
  // its Proton version, and only the content comparison spots a runtime
  // assembled from the older one.
  Workspace::require_fresh_prebuilt_artifacts(
    prebuilt,
    prebuilt_path,
    self
    .proton_project_root()
    .join(Relative("\{ProtonPrebuiltRoot}/\{platform}")),
    dist,
  )
  let cef_root = self.proton_manifest_path(active, active_path, "cef")
  if !@asyncfs.exists(cef_root.0) {
    raise PackageError("Proton CEF cache not found: \{cef_root}")
  }
  for relative in Workspace::proton_runtime_required_files(platform) {
    let required = dist.join(Relative(relative))
    if !@asyncfs.exists(required.0) {
      raise PackageError("Proton runtime file not found: \{required}")
    }
  }
  dist
}

///|
/// Require every artifact the prebuilt manifest declares to be byte-identical
/// between the resolved prebuilt and the assembled runtime. `cef setup`
/// copies these files verbatim, so any difference means the runtime predates
/// the current prebuilt and must be reassembled.
async fn Workspace::require_fresh_prebuilt_artifacts(
  prebuilt : Map[String, Json],
  prebuilt_path : String,
  prebuilt_root : @pathx.Absolute,
  dist : @pathx.Absolute,
) -> Unit {
  guard prebuilt.get("artifacts") is Some(Object(artifacts)) else {
    raise PackageError(
      "Proton prebuilt manifest has no \"artifacts\" object: \{prebuilt_path}",
    )
  }
  for name, value in artifacts {
    guard value is String(spelled) else {
      raise PackageError(
        "Proton prebuilt artifact \"\{name}\" is not a string path: \{prebuilt_path}",
      )
    }
    guard @pathx.Path(spelled).to_relative() is Some(relative) else {
      raise PackageError(
        "Proton prebuilt artifact \"\{name}\" is not a relative path: \{prebuilt_path}",
      )
    }
    let shipped = prebuilt_root.join(relative)
    let assembled = dist.join(relative)
    if !@asyncfs.exists(assembled.0) {
      raise PackageError("Proton runtime file not found: \{assembled}")
    }
    if @asyncfs.read_file(shipped.0).binary() !=
      @asyncfs.read_file(assembled.0).binary() {
      raise PackageError(
        "Proton runtime is stale: \{assembled} differs from prebuilt \{shipped}",
      )
    }
  }
}

///|
/// Recursively copy a directory tree, replacing the destination. Uses the
/// host's `cp -R`; packaging runs on the build host so this stays simple.
pub async fn copy_tree(source : String, destination : String) -> Unit {
  remove_path_if_exists(destination)
  let parent = (destination : @path.Path).dirname().to_string()
  ensure_dir(parent)
  run_checked("cp", ["-R", source, destination], dir=parent)
}

///|
/// Resolve a path to an absolute path using the host filesystem rules.
pub fn absolute_path(path : String) -> String {
  (path : @path.Path).resolve().to_string()
}

///|
/// Run a subprocess in `dir`, inherit the current environment, and raise
/// `PackageError` when the command exits with a non-zero status.
pub async fn run_checked(
  command : String,
  args : Array[String],
  dir~ : String,
  extra_env? : Map[String, String] = Map([]),
) -> Unit {
  let joined_args = args.join(" ")
  println("$ [\{dir}] \{command} \{joined_args}")
  let code = @process.run(
    command,
    args,
    inherit_env=true,
    extra_env~,
    cwd=dir.view(),
  )
  if code != 0 {
    raise PackageError("command failed with exit code \{code}: \{command}")
  }
}

///|
/// Build the frontend package in the selected mode. Moon owns the artifact and
/// its dependency graph, so repeated development launches get its normal
/// incremental build without copying or rewriting the result.
pub async fn build_frontend(ws : Workspace, release~ : Bool) -> Unit {
  let release_args = if release { ["--release"] } else { [] }
  run_checked(
    "moon",
    ["build", FrontendPackage, "--target", "js", ..release_args],
    dir=ws.dir(),
  )
  let frontend = ws.frontend_binary(release~)
  if !@asyncfs.exists(frontend) {
    raise PackageError("desktop frontend artifact not found: \{frontend}")
  }
}

///|
/// Build the frontend package and copy the generated JS bundle to the stable
/// `frontend.js` path consumed by packaged layouts. Development calls
/// `build_frontend` directly and serves Moon's artifact in place.
pub async fn build_frontend_bundle(ws : Workspace, release~ : Bool) -> Unit {
  build_frontend(ws, release~)
  copy_file(ws.frontend_binary(release~), ws.at(FrontendBundleOutput))
  build_app_stylesheet(ws)
  build_viewer_stylesheet(ws)
  build_mermaid_assets(ws)
}

///|
/// Download, verify, and stage the editor's pinned official Mermaid ESM
/// distribution for packaging beside the frontend bundle.
pub async fn build_mermaid_assets(ws : Workspace) -> Unit {
  @mermaid_assets.stage(
    ws.repo_at("\{EditorDepRoot}/target/vendor-mermaid/cache"),
    ws.mermaid_assets(),
    ws.dir(),
  )
}

///|
/// Concatenate the application CSS sources into the single stylesheet shipped
/// by every production layout. Development loads the same sources through the
/// checked-in `app.css` import manifest, so editing CSS needs no Moon rebuild.
pub async fn build_app_stylesheet(ws : Workspace) -> Unit {
  write_text(ws.app_stylesheet(), assembled_app_stylesheet(ws))
}

///|
/// Read the application CSS in cascade order without rewriting declarations or
/// resource URLs. `app_font.css` stays at the desktop root so its `fonts/` URL
/// resolves identically before and after concatenation.
async fn assembled_app_stylesheet(ws : Workspace) -> String {
  let css = StringBuilder::new()
  for source in app_css_sources() {
    let absolute = ws.at(source)
    if !@asyncfs.exists(absolute) {
      raise PackageError("application stylesheet not found: \{absolute}")
    }
    let text = @asyncfs.read_file(absolute).text()
    css.write_string(text)
    if !text.has_suffix("\n") {
      css.write_string("\n")
    }
  }
  css.to_string()
}

///|
async test "development app stylesheet imports every production source" {
  let ws = locate_workspace()
  let development = @asyncfs.read_file(ws.at("app.css")).text()
  let imports : Array[String] = []
  for line in development.split("\n") {
    if line.has_prefix("@import ") {
      imports.push(line.to_owned())
    }
  }
  let expected : Array[String] = []
  for source in app_css_sources() {
    expected.push("@import url(\"./" + source + "\");")
  }
  assert_eq(imports, expected)
}

///|
/// Concatenate the embedded viewer's CSS into a single `viewer.css` next to the
/// frontend bundle, mirroring the editor's own `scripts/build-web` step. The
/// viewer ships its styles as many files, none of which are loaded unless
/// assembled here; without them the viewer paints its raw measurement probes
/// over the panel instead of a styled editor.
pub async fn build_viewer_stylesheet(ws : Workspace) -> Unit {
  write_text(ws.at(ViewerStyleOutput), assembled_viewer_stylesheet(ws))
  copy_file(
    ws.repo_at("\{EditorDepRoot}/\{CodiconFontSource}"),
    ws.at(CodiconFontOutput),
  )
}

///|
/// Read and concatenate the desktop-owned theme followed by every editor
/// workspace stylesheet. Keeping assembly separate from the output write lets
/// tests exercise the real member files without mutating the checkout.
async fn assembled_viewer_stylesheet(ws : Workspace) -> String {
  let css = StringBuilder::new()
  let theme_path = ws.at(ViewerThemeSource)
  if !@asyncfs.exists(theme_path) {
    raise PackageError("viewer theme not found: \{theme_path}")
  }
  let theme = @asyncfs.read_file(theme_path).text()
  css.write_string("/* " + ViewerThemeSource + " */\n")
  css.write_string(theme)
  if !theme.has_suffix("\n") {
    css.write_string("\n")
  }
  css.write_string("\n")
  for source in viewer_css_sources() {
    let absolute = ws.repo_at("\{EditorDepRoot}/\{source}")
    if !@asyncfs.exists(absolute) {
      raise PackageError("viewer stylesheet not found: \{absolute}")
    }
    css.write_string("/* " + source + " */\n")
    let text = @asyncfs.read_file(absolute).text()
    css.write_string(text)
    if !text.has_suffix("\n") {
      css.write_string("\n")
    }
    css.write_string("\n")
  }
  css.to_string()
}

///|
async test "development viewer stylesheet imports every production source" {
  let ws = locate_workspace()
  let development = @asyncfs.read_file(ws.at("dev/viewer.css")).text()
  for source in viewer_css_sources() {
    assert_true(development.contains("../../editor/" + source))
  }
}

///|
/// Build the native desktop host in the selected mode.
pub async fn build_native_host(
  ws : Workspace,
  release~ : Bool,
  extra_args? : Array[String] = [],
  extra_env? : Map[String, String] = Map([]),
  runtime_dist? : String,
) -> Unit {
  // Resolve the read-only runtime prerequisite before starting the build.
  let runtime_dist = if runtime_dist is Some(path) {
    path
  } else {
    proton_runtime_dist(ws).0
  }
  // The assembled runtime lives in the user-level Proton cache, outside the
  // checkout entirely. Pass it explicitly so the prebuild linker config
  // cannot fall back to a stale runtime it discovers on its own.
  let build_env : Map[String, String] = Map([])
  for name, value in extra_env {
    build_env[name] = value
  }
  build_env["PROTON_NATIVE_DIST"] = runtime_dist
  let release_args = if release { ["--release"] } else { [] }
  run_checked(
    "moon",
    ["build", NativePackage, "--target", "native", ..release_args, ..extra_args],
    dir=ws.dir(),
    extra_env=build_env,
  )
}

///|
/// Build the openseek engine from the monorepo source so the bundled engine
/// always matches the checkout instead of whatever happens to be on PATH.
pub async fn build_engine(
  ws : Workspace,
  release~ : Bool,
  extra_env? : Map[String, String] = Map([]),
) -> Unit {
  let release_args = if release { ["--release"] } else { [] }
  run_checked(
    "moon",
    ["build", EnginePackage, "--target", "native", ..release_args],
    dir=ws.repo(),
    extra_env~,
  )
  let engine_binary = ws.engine_binary(release~)
  if !@asyncfs.exists(engine_binary) {
    raise PackageError("openseek engine binary not found: \{engine_binary}")
  }
}

///|
/// Copy a file, replacing the destination if it already exists.
pub async fn copy_file(source : String, destination : String) -> Unit {
  @asyncfs.write_file(
    destination,
    @asyncfs.read_file(source),
    create_mode=CreateOrTruncate,
  )
}

///|
/// Write UTF-8 text to a file, replacing the file if it already exists.
pub async fn write_text(path : String, content : String) -> Unit {
  @asyncfs.write_file(path, content, create_mode=CreateOrTruncate)
}

///|
/// Create a directory and any missing parents if the path does not exist.
pub async fn ensure_dir(path : String) -> Unit {
  if @asyncfs.exists(path) {
    return
  }
  @asyncfs.mkdir(path, recursive=true) catch {
    // A concurrent caller can win the creation race on this directory or a
    // shared ancestor between the existence check and mkdir.
    @os_error.OSError(_) as error if error.is_EEXIST() => ()
    error => raise error
  }
}

///|
/// Remove a file or directory tree if it already exists.
pub async fn remove_path_if_exists(path : String) -> Unit {
  if !@asyncfs.exists(path) {
    return
  }
  if @asyncfs.kind(path) is Directory {
    @asyncfs.rmdir(path, recursive=true)
  } else {
    @asyncfs.remove(path)
  }
}

///|
/// The workspace derives every path from an absolute root, so the results are
/// absolute and independent of any later working-directory change. These pin
/// the join/parent math the packagers rely on.
test "workspace derives absolute paths from an absolute root" {
  let ws : Workspace = { root: "/abs/repo/desktop" }
  assert_eq(ws.dir(), "/abs/repo/desktop")
  assert_eq(ws.at("dist/app"), "/abs/repo/desktop/dist/app")
  assert_eq(ws.repo(), "/abs/repo")
  assert_eq(ws.repo_at("cmd/openseek"), "/abs/repo/cmd/openseek")
}

///|
// The bundle names carry no spaces, but a checkout path still can, so the
// space this pins is in the workspace root.
test "workspace path join preserves spaces and nested segments" {
  let ws : Workspace = { root: "/My Checkouts/w" }
  assert_eq(
    ws.at("dist/SeekMoon.app/Contents/Resources/toolchains/moonbit/macos-arm64"),
    "/My Checkouts/w/dist/SeekMoon.app/Contents/Resources/toolchains/moonbit/macos-arm64",
  )
}

///|
test "package build paths select debug or release" {
  let ws : Workspace = { root: "/abs/repo/desktop" }
  assert_eq(ws.app_stylesheet(), "/abs/repo/desktop/app.generated.css")
  assert_eq(
    ws.native_binary(release=false),
    "/abs/repo/_build/native/debug/build/openseek_desktop/openseek_desktop.exe",
  )
  assert_eq(
    ws.engine_binary(release=false),
    "/abs/repo/_build/native/debug/build/bobzhang/openseek/cmd/openseek/openseek.exe",
  )
  assert_eq(
    ws.native_binary(release=true),
    "/abs/repo/_build/native/release/build/openseek_desktop/openseek_desktop.exe",
  )
}

///|
async test "workspace module version reads moon.mod" {
  let ws = locate_workspace()
  assert_eq(ws.module_version(), "0.1.5")
}

///|
/// The Proton CLI coordinate must track the library pin, not a copy of it:
/// `cef setup` assembles the runtime from the very prebuilt that
/// `moonbit-community/proton` ships, so a CLI from a different release would
/// assemble something the packaged host does not link against.
async test "proton CLI version follows the moon.mod library pin" {
  let ws = locate_workspace()
  assert_eq(
    ws.proton_cli_package(),
    "moonbit-community/proton_cli@\{ws.proton_version()}",
  )
  assert_true(ws.proton_version().has_prefix("0.1."))
}

///|
/// A throwaway workspace for the Proton-runtime tests, in a private temporary
/// directory. `proton_project_dir` is the monorepo root — the parent of the
/// workspace — so the fixture needs two levels: `<tmp>/desktop` is the
/// workspace and `<tmp>` stands in for the repository above it.
///
/// The temporary root matters. These tests ran under the live `desktop/target`
/// before, which every one of them created and removed concurrently; that is
/// a shared mutable ancestor between async tests, and it produced a
/// use-after-delete on Linux CI that never reproduced on macOS. A per-test
/// `tmpdir` has no ancestor any sibling touches.
async fn fixture_workspace(name : String) -> (String, Workspace) {
  let root = @asyncfs.tmpdir(prefix="openseek-\{name}-")
  let workspace = join_path(root, "desktop")
  ensure_dir(workspace)
  (root, { root: workspace })
}

///|
/// Proton owns the CEF cache location and records it in the active runtime
/// manifest. Keep package rebuilding on that path instead of assuming the
/// cache remains inside the resolved Proton package.
async test "Proton CEF root follows the active runtime manifest" {
  let (fixture_root, fixture) = fixture_workspace(
    "proton-runtime-manifest-test",
  )
  let manifest = fixture.proton_project_at(".proton/runtime.json")
  ensure_dir((manifest : @path.Path).dirname().to_string())
  let cef_root = fixture.at("shared-cache/cef")
  write_text(
    manifest,
    Json::object({ "cef": Json::string(cef_root) }).stringify(),
  )
  assert_eq(fixture.proton_cef_root().0, cef_root)
  remove_path_if_exists(fixture_root)
}

///|
async test "matching Proton runtime is reused without invoking setup" {
  let (fixture_root, fixture) = fixture_workspace("proton-runtime-reuse-test")
  let platform = Workspace::proton_platform()
  let version = "0.1.14-test"
  let relative_dist = ".proton/runtimes/\{platform}/test-runtime"
  let dist = fixture.proton_project_at(relative_dist)
  let cef_root = fixture.at("cef-cache")
  ensure_dir(cef_root)
  let active_path = fixture.proton_project_at(".proton/runtime.json")
  ensure_dir((active_path : @path.Path).dirname().to_string())
  write_text(
    active_path,
    Json::object({
      "schema_version": Json::number(1),
      "platform": Json::string(platform),
      "proton_version": Json::string(version),
      "cef_version": Json::string("cef-test"),
      "cef": Json::string(cef_root),
      "dist": Json::string(relative_dist),
    }).stringify(),
  )
  let prebuilt_path = fixture.proton_project_at(
    "\{ProtonPrebuiltRoot}/\{platform}/manifest.json",
  )
  ensure_dir((prebuilt_path : @path.Path).dirname().to_string())
  write_text(
    prebuilt_path,
    Json::object({
      "platform": Json::string(platform),
      "proton_version": Json::string(version),
      "artifacts": Json::object({
        "header": Json::string("include/proton_native.h"),
      }),
    }).stringify(),
  )
  let shipped_header = fixture.proton_project_at(
    "\{ProtonPrebuiltRoot}/\{platform}/include/proton_native.h",
  )
  ensure_dir((shipped_header : @path.Path).dirname().to_string())
  write_text(shipped_header, "fixture")
  for relative in Workspace::proton_runtime_required_files(platform) {
    let required = join_path(dist, relative)
    ensure_dir((required : @path.Path).dirname().to_string())
    write_text(required, "fixture")
  }
  // Setup must not run: the fixture root has no resolved Proton package, so
  // a `cef setup` invocation would fail to find a prebuilt and raise here
  // rather than quietly reassembling.
  ensure_cef_runtime(fixture)
  assert_eq(proton_runtime_dist(fixture).0, dist)
  remove_path_if_exists(fixture_root)
}

///|
/// A prebuilt refresh that keeps the Proton version (a routine native rebuild)
/// must still invalidate the assembled runtime; only the artifact bytes reveal
/// the difference.
async test "refreshed prebuilt bytes invalidate the assembled runtime" {
  let (fixture_root, fixture) = fixture_workspace("proton-prebuilt-stale-test")
  let prebuilt_root = fixture.proton_project_at(
    "\{ProtonPrebuiltRoot}/test-platform",
  )
  let prebuilt_path = join_path(prebuilt_root, "manifest.json")
  let prebuilt : Map[String, Json] = {
    "artifacts": Json::object({
      "header": Json::string("include/proton_native.h"),
    }),
  }
  let dist = fixture.at("runtime-dist")
  let shipped = join_path(prebuilt_root, "include/proton_native.h")
  let assembled = join_path(dist, "include/proton_native.h")
  ensure_dir((shipped : @path.Path).dirname().to_string())
  ensure_dir((assembled : @path.Path).dirname().to_string())
  write_text(shipped, "prebuilt-v2")
  write_text(assembled, "prebuilt-v1")
  try
    Workspace::require_fresh_prebuilt_artifacts(
      prebuilt,
      prebuilt_path,
      @pathx.Path(prebuilt_root).resolve(),
      @pathx.Path(dist).resolve(),
    )
  catch {
    error => assert_true(error.to_string().contains("Proton runtime is stale"))
  } noraise {
    _ => fail("expected differing prebuilt artifact bytes to fail validation")
  }
  write_text(assembled, "prebuilt-v2")
  Workspace::require_fresh_prebuilt_artifacts(
    prebuilt,
    prebuilt_path,
    @pathx.Path(prebuilt_root).resolve(),
    @pathx.Path(dist).resolve(),
  )
  remove_path_if_exists(fixture_root)
}

///|
/// Newer Proton CLIs record the runtime dist as an absolute path into the
/// user-level cache; the packager must consume it verbatim instead of joining
/// it below the Proton project root.
async test "absolute runtime dist paths pass through unchanged" {
  let (fixture_root, fixture) = fixture_workspace("proton-absolute-dist-test")
  let dist = fixture.at("user-cache/runtimes/test-platform/test-runtime")
  let active_path = fixture.proton_project_at(".proton/runtime.json")
  ensure_dir((active_path : @path.Path).dirname().to_string())
  write_text(
    active_path,
    Json::object({ "dist": Json::string(dist) }).stringify(),
  )
  assert_eq(proton_runtime_dist(fixture).0, dist)
  remove_path_if_exists(fixture_root)
}

///|
async test "viewer stylesheet assembles from the editor workspace member" {
  let ws = locate_workspace()
  let css = assembled_viewer_stylesheet(ws)
  assert_true(css.contains("/* viewer_theme.css */"))
  assert_true(
    css.contains(
      "/* viewer/contrib/markdown_comments/browser/markdown_comments.css */",
    ),
  )
  assert_true(css.contains("/* viewer/browser/diff_editor/diff_editor.css */"))
  let font = ws.repo_at("\{EditorDepRoot}/\{CodiconFontSource}")
  guard @asyncfs.exists(font) else {
    fail("missing workspace viewer font: \{font}")
  }
}

///|
async test "application stylesheet assembles without development imports" {
  let ws = locate_workspace()
  let css = assembled_app_stylesheet(ws)
  assert_true(css.has_prefix("/* Geist Mono is bundled"))
  assert_true(css.contains("/* ---------- terminal panel ---------- */"))
  assert_true(css.contains("/* ---------- narrow (phone) layout ---------- */"))
  assert_true(!css.contains("@import"))
  // Keep the semantic-token migration closed over every packaged source. This
  // catches a new component copied from an older stylesheet before undefined
  // custom properties silently erase its colors, borders, or shadows.
  for
    retired in [
      "mono", "paper", "surface", "surface-2", "ink", "ink-2", "ink-3", "line", "line-2",
      "accent", "accent-ink", "on-accent-ink", "accent-soft", "accent-line", "add",
      "add-bg", "add-line", "del", "del-bg", "del-line", "warn", "tool", "tool-bg",
      "tool-line", "code", "radius", "shadow", "shadow-pop",
    ] {
    assert_false(css.contains("--\{retired}:"))
    assert_false(css.contains("var(--\{retired})"))
    assert_false(css.contains("var(--\{retired},"))
  }
}

///|
async test "form field focus styling stays in the base stylesheet" {
  let ws = locate_workspace()
  let base = @asyncfs.read_file(ws.at("styles/base.css")).text()
  assert_true(base.contains("[data-focus-owner]:focus"))
  assert_true(
    base.contains("[data-focus-owner]:has([data-focus-target]:focus)"),
  )
  assert_true(base.contains("[data-focus-target]:focus"))
  // Discrete actions may use :focus-visible in their component stylesheet.
  // Form fields and composite wrappers go through the marker contract above;
  // keeping these older patterns out prevents a second border from returning.
  for source in app_css_sources() {
    if source != "styles/base.css" {
      let component = @asyncfs.read_file(ws.at(source)).text()
      guard !component.contains("input:focus") &&
        !component.contains("textarea:focus") &&
        !component.contains("select:focus") &&
        !component.contains(":focus-within") &&
        !component.contains(":focus {") else {
        fail("form field focus styling must stay in styles/base.css: " + source)
      }
    }
  }
}

///|
/// An uncaught `PackageError` reaches the user through the async runtime's
/// `println(err : Error)`; this pins that the message survives that path
/// (the intrinsic falls back to the bare constructor name without the Show
/// impl).
test "a PackageError shown as an Error keeps its message" {
  let error : Error = PackageError("viewer stylesheet not found: /x.css")
  assert_eq(
    error.to_string(),
    "package error: viewer stylesheet not found: /x.css",
  )
}

///|
pub extend PackageError with Show::{output, to_string}
