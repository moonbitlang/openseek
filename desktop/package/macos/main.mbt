///|
const AppPath : String = "dist/OpenSeek Desktop.app"

///|
const ZipPath : String = "dist/OpenSeek Desktop-macos-arm64.zip"

///|
const DmgPath : String = "dist/OpenSeek Desktop-macos-arm64.dmg"

///|
const DmgStagingPath : String = "dist/OpenSeek Desktop-dmg-root"

///|
const ContentsPath : String = AppPath + "/Contents"

///|
const MacOSPath : String = ContentsPath + "/MacOS"

///|
const FrameworksPath : String = ContentsPath + "/Frameworks"

///|
const ResourcesPath : String = ContentsPath + "/Resources"

///|
/// The whole assembled Proton runtime (lib/libproton.dylib, the CEF framework,
/// bin/cef_process + GL dylibs, Resources/locales) is copied here as a unit so
/// its internal `@loader_path/..` references keep resolving; the host's rpath is
/// repointed at `proton/lib`. It lives under Resources, not Frameworks:
/// `codesign` requires every entry directly under `Contents/Frameworks` to be a
/// valid framework/dylib bundle, and the runtime's `Resources/*.lproj` data
/// dirs make it reject the tree ("bundle format unrecognized"). Under Resources
/// the tree is sealed as data by the outer app signature. Its nested mach-o keep
/// the valid (linker) adhoc signatures `cef setup` ships; they are only
/// re-signed for Developer ID distribution, never for the adhoc build.
const ProtonRuntimePath : String = ResourcesPath + "/proton"

///|
const CefProcessName : String = "cef_process"

///|
const HelperExecutableBaseName : String = "OpenSeek Desktop Helper"

///|
const HelperProtonRPath : String = "@loader_path/../../../../Resources/proton/lib"

///|
/// The host resolves libproton from the runtime copied into its app bundle.
/// Supplying this at link time avoids rewriting a finished Mach-O, which may
/// not have enough load-command padding for a longer path.
const HostProtonRPath : String = "@executable_path/../Resources/proton/lib"

///|
/// Frontend assets live under Resources, not MacOS: codesign without the
/// deprecated `--deep` treats everything in `Contents/MacOS/` as code and
/// rejects plain data files there.
const AppAssetDir : String = ResourcesPath + "/assets"

///|
const MoonbitSeedDir : String = ResourcesPath +
  "/toolchains/moonbit/macos-arm64"

///|
const AppBundleIdentifier : String = "community.moonbit.proton.openseek-desktop"

///|
const HelperBundleIdentifier : String = AppBundleIdentifier + ".helper"

///|
const SigningEntitlementsPath : String = "dist/OpenSeek Desktop.entitlements"

///|
/// Entitlements for the bundled `moonrun`: it JIT-compiles wasm, so under the
/// hardened runtime it needs `MAP_JIT` (and wasm engines without a
/// pthread_jit_write_protect discipline fall back to unsigned executable
/// memory). Signed onto the seed binary in both the adhoc and distribution
/// paths so a locally built bundle behaves like a notarized one.
const JitEntitlementsPath : String = "dist/moonrun.entitlements"

///|
/// The seed binaries that execute JIT-compiled code and need
/// `JitEntitlementsPath` at signing time.
fn needs_jit_entitlements(file_name : String) -> Bool {
  file_name == "moonrun"
}

///|
/// Minimum macOS the produced binaries run on. Without this, clang pins
/// LC_BUILD_VERSION's minos to the build machine's OS version and dyld on
/// any older system refuses to load the binary at all. Must match
/// LSMinimumSystemVersion in the Info.plist.
const MinMacOSVersion : String = "12.0"

///|
priv struct CefHelperVariant {
  name_suffix : String
  bundle_id_suffix : String
}

///|
fn cef_helper_variants() -> Array[CefHelperVariant] {
  [
    { name_suffix: "", bundle_id_suffix: "" },
    { name_suffix: "Alerts", bundle_id_suffix: ".alerts" },
    { name_suffix: "GPU", bundle_id_suffix: ".gpu" },
    { name_suffix: "Plugin", bundle_id_suffix: ".plugin" },
    { name_suffix: "Renderer", bundle_id_suffix: ".renderer" },
  ]
}

///|
fn CefHelperVariant::executable_name(self : CefHelperVariant) -> String {
  if self.name_suffix.is_empty() {
    HelperExecutableBaseName
  } else {
    "\{HelperExecutableBaseName} (\{self.name_suffix})"
  }
}

///|
fn CefHelperVariant::app_name(self : CefHelperVariant) -> String {
  self.executable_name() + ".app"
}

///|
fn CefHelperVariant::bundle_identifier(self : CefHelperVariant) -> String {
  HelperBundleIdentifier + self.bundle_id_suffix
}

///|
fn CefHelperVariant::app_path(self : CefHelperVariant) -> String {
  FrameworksPath + "/" + self.app_name()
}

///|
fn CefHelperVariant::contents_path(self : CefHelperVariant) -> String {
  self.app_path() + "/Contents"
}

///|
fn CefHelperVariant::macos_path(self : CefHelperVariant) -> String {
  self.contents_path() + "/MacOS"
}

///|
fn CefHelperVariant::executable_path(self : CefHelperVariant) -> String {
  self.macos_path() + "/" + self.executable_name()
}

///|
async fn build_outputs(ws : @packaging.Workspace) -> Unit {
  let env = { "MACOSX_DEPLOYMENT_TARGET": MinMacOSVersion }
  let host_env = {
    "MACOSX_DEPLOYMENT_TARGET": MinMacOSVersion,
    "PROTON_PACKAGE_RPATH": HostProtonRPath,
  }
  // Assemble the CEF runtime first: native_link_config reads
  // `.proton/runtime.json` to link the host against libproton/CEF. Forward
  // the deployment target so native artifacts match LSMinimumSystemVersion.
  @packaging.assemble_cef_runtime(
    ws,
    @packaging.posix_proton_cli(),
    extra_env=env,
  )
  // Then replace the assembled dist's libproton with one built from the
  // submodule's sources. The darwin prebuilt is usually fresh, but building
  // here removes the dependency on that habit — and the deployment-target
  // env reaches the compile, so the dylib's Mach-O version stamp matches the
  // bundle's LSMinimumSystemVersion (prebuilt artifacts keep whatever stamp
  // they were built with).
  @packaging.rebuild_libproton(
    ws,
    [
      ("lib/libproton.dylib", "lib/libproton.dylib"),
      ("bin/cef_process", "bin/cef_process"),
    ],
    extra_env=env,
  )
  @packaging.build_frontend_bundle(ws)
  // Build the host without mimalloc: its static malloc/free override crashes
  // against CEF's PartitionAlloc default zone on the first `@fs.realpath`.
  @packaging.build_native_host(ws, extra_env=host_env, disable_mimalloc=true)
  @packaging.build_engine(ws, extra_env=env)
}

///|
async fn reset_bundle_dirs(ws : @packaging.Workspace) -> Unit {
  @packaging.remove_path_if_exists(ws.at(AppPath))
  @packaging.remove_path_if_exists(ws.at(ZipPath))
  @packaging.remove_path_if_exists(ws.at(DmgPath))
  @packaging.remove_path_if_exists(ws.at(DmgStagingPath))
  @packaging.ensure_dir(ws.at(MacOSPath))
  @packaging.ensure_dir(ws.at(ResourcesPath))
  @packaging.ensure_dir(ws.at(AppAssetDir))
}

///|
/// The host binary is the bundle's main executable directly, with no shell
/// launcher in between. Resource lookups derive from argv[0], and the bundled
/// engine is resolved by absolute path, so nothing needs a `cd` or PATH entry.
async fn copy_bundle_files(ws : @packaging.Workspace) -> Unit {
  let native_binary = ws.native_binary()
  let engine_binary = ws.engine_binary()
  if !@asyncfs.exists(native_binary) {
    raise @packaging.PackageError("native binary not found: \{native_binary}")
  }
  if !@asyncfs.exists(engine_binary) {
    raise @packaging.PackageError(
      "openseek engine binary not found: \{engine_binary}",
    )
  }
  @packaging.copy_file(native_binary, ws.at(MacOSPath + "/openseek-desktop"))
  @packaging.copy_file(engine_binary, ws.at(MacOSPath + "/openseek"))
  @packaging.copy_file(ws.at("index.html"), ws.at(AppAssetDir + "/index.html"))
  @packaging.copy_file(
    ws.at("frontend.js"),
    ws.at(AppAssetDir + "/frontend.js"),
  )
  @packaging.copy_file(ws.at("viewer.css"), ws.at(AppAssetDir + "/viewer.css"))
  // Checked-in icns built from appicon.svg (the design-system mark on the
  // accent squircle). Regenerate with rsvg-convert at the iconset sizes and
  // `iconutil -c icns` when the mark changes.
  @packaging.copy_file(
    ws.at("package/macos/AppIcon.icns"),
    ws.at(ResourcesPath + "/AppIcon.icns"),
  )
  // The codicon font is served at the site root (`/codicon.ttf`), so it sits
  // next to `viewer.css` rather than under `fonts/`.
  @packaging.copy_file(
    ws.at("codicon.ttf"),
    ws.at(AppAssetDir + "/codicon.ttf"),
  )
  @packaging.copy_tree(ws.at("fonts"), ws.at(AppAssetDir + "/fonts"))
  bundle_proton_runtime(ws)
  let target = @moonbit.moonbit_macos_arm64_toolchain()
  @moonbit.stage_moonbit_toolchain_seed(ws, target, MoonbitSeedDir)
}

///|
/// Copy the assembled Proton runtime into the bundle. The host is linked with
/// `HostProtonRPath` by `build_outputs`, so it already resolves libproton from
/// this copied tree without a post-link Mach-O rewrite.
async fn bundle_proton_runtime(ws : @packaging.Workspace) -> Unit {
  let dist = @packaging.proton_runtime_dist(ws)
  @packaging.copy_tree(dist, ws.at(ProtonRuntimePath))
  stage_cef_helper_app(ws)
}

///|
/// Chromium derives its macOS MachPort rendezvous base bundle id by walking
/// outward from the helper executable. A bare `cef_process` under Resources has
/// no enclosing helper app, so CEF subprocesses compute a different rendezvous
/// service name from the browser and die during startup. Keep the real runtime
/// under Resources, but launch subprocesses from the CEF macOS helper app
/// family. Chromium selects the process-type-specific helper by app/executable
/// name, so the copied binary must be named after each helper bundle instead of
/// the source `cef_process` name.
async fn stage_cef_helper_app(ws : @packaging.Workspace) -> Unit {
  let source = ProtonRuntimePath + "/bin/" + CefProcessName
  for helper in cef_helper_variants() {
    @packaging.ensure_dir(ws.at(helper.macos_path()))
    @packaging.write_text(
      ws.at(helper.contents_path() + "/Info.plist"),
      helper_info_plist_source(helper),
    )
    @packaging.copy_file(ws.at(source), ws.at(helper.executable_path()))
    @packaging.run_checked(
      "chmod",
      ["+x", helper.executable_path()],
      dir=ws.dir(),
    )
    patch_helper_rpath(ws, helper.executable_path())
  }
}

///|
async fn patch_helper_rpath(
  ws : @packaging.Workspace,
  helper_path : String,
) -> Unit {
  let helper = ws.at(helper_path)
  let _ = @process.run(
    "install_name_tool",
    ["-delete_rpath", "@loader_path/../lib", helper],
    inherit_env=true,
    cwd=ws.dir().view(),
  )
  let _ = @process.run(
    "install_name_tool",
    ["-delete_rpath", "@loader_path/../Frameworks", helper],
    inherit_env=true,
    cwd=ws.dir().view(),
  )
  @packaging.run_checked(
    "install_name_tool",
    ["-add_rpath", HelperProtonRPath, helper],
    dir=ws.dir(),
  )
}

///|
fn helper_info_plist_source(helper : CefHelperVariant) -> String {
  let name = helper.executable_name()
  let source =
    $|<?xml version="1.0" encoding="UTF-8"?>
    $|<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    $|<plist version="1.0">
    $|<dict>
    $|  <key>CFBundleDevelopmentRegion</key><string>en</string>
    $|  <key>CFBundleDisplayName</key><string>\{name}</string>
    $|  <key>CFBundleExecutable</key><string>\{name}</string>
    $|  <key>CFBundleIdentifier</key><string>\{helper.bundle_identifier()}</string>
    $|  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    $|  <key>CFBundleName</key><string>\{name}</string>
    $|  <key>CFBundlePackageType</key><string>APPL</string>
    $|  <key>LSUIElement</key><true/>
    $|  <key>CFBundleShortVersionString</key><string>\{@version.AppVersion}</string>
    $|  <key>CFBundleVersion</key><string>\{@version.AppVersion}</string>
    $|  <key>LSMinimumSystemVersion</key><string>\{MinMacOSVersion}</string>
    $|</dict>
    $|</plist>
    $|
  source
}

///|
fn signing_entitlements_source() -> String {
  let source =
    $|<?xml version="1.0" encoding="UTF-8"?>
    $|<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    $|<plist version="1.0">
    $|<dict>
    $|  <key>com.apple.security.cs.allow-jit</key><true/>
    $|  <key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/>
    $|  <key>com.apple.security.cs.disable-executable-page-protection</key><true/>
    $|  <key>com.apple.security.cs.disable-library-validation</key><true/>
    $|</dict>
    $|</plist>
    $|
  source
}

///|
fn jit_entitlements_source() -> String {
  let source =
    $|<?xml version="1.0" encoding="UTF-8"?>
    $|<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    $|<plist version="1.0">
    $|<dict>
    $|  <key>com.apple.security.cs.allow-jit</key><true/>
    $|  <key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/>
    $|</dict>
    $|</plist>
    $|
  source
}

///|
fn info_plist_source() -> String {
  let source =
    $|<?xml version="1.0" encoding="UTF-8"?>
    $|<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    $|<plist version="1.0">
    $|<dict>
    $|  <key>CFBundleDevelopmentRegion</key><string>en</string>
    $|  <key>CFBundleDisplayName</key><string>OpenSeek Desktop</string>
    $|  <key>CFBundleExecutable</key><string>openseek-desktop</string>
    $|  <key>CFBundleIconFile</key><string>AppIcon</string>
    $|  <key>CFBundleIdentifier</key><string>\{AppBundleIdentifier}</string>
    $|  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    $|  <key>CFBundleName</key><string>OpenSeek Desktop</string>
    $|  <key>CFBundlePackageType</key><string>APPL</string>
    $|  <key>CFBundleShortVersionString</key><string>\{@version.AppVersion}</string>
    $|  <key>CFBundleVersion</key><string>\{@version.AppVersion}</string>
    $|  <key>LSMinimumSystemVersion</key><string>\{MinMacOSVersion}</string>
    $|  <key>NSHighResolutionCapable</key><true/>
    $|</dict>
    $|</plist>
    $|
  source
}

///|
async fn write_bundle_metadata(ws : @packaging.Workspace) -> Unit {
  @packaging.write_text(
    ws.at(ContentsPath + "/Info.plist"),
    info_plist_source(),
  )
  @packaging.run_checked(
    "chmod",
    ["+x", MacOSPath + "/openseek-desktop", MacOSPath + "/openseek"],
    dir=ws.dir(),
  )
}

///|
async fn is_macho_file(path : String) -> Bool {
  let (code, output) = @process.collect_output_merged(
    "file",
    [path],
    inherit_env=true,
  )
  code == 0 && output.text().contains("Mach-O")
}

///|
fn codesign_file_args(
  identity : String,
  path : String,
  distribution~ : Bool,
  entitlements? : String,
) -> Array[String] {
  let args = ["--force"]
  if distribution {
    args.append(["--options", "runtime", "--timestamp"])
  }
  if entitlements is Some(entitlements) {
    args.append(["--entitlements", entitlements])
  }
  args.append(["--sign", identity, path])
  args
}

///|
fn codesign_app_bundle_args(
  identity : String,
  path : String,
  entitlements : String,
  distribution~ : Bool,
) -> Array[String] {
  if distribution {
    [
      "--force", "--options", "runtime", "--timestamp", "--entitlements", entitlements,
      "--sign", identity, path,
    ]
  } else {
    ["--force", "--entitlements", entitlements, "--sign", identity, path]
  }
}

///|
fn codesign_cef_process_args(
  identity : String,
  path : String,
  distribution~ : Bool,
) -> Array[String] {
  if distribution {
    [
      "--force",
      "--options",
      "runtime",
      "--timestamp",
      "-i",
      CefProcessName,
      "--sign",
      identity,
      path,
    ]
  } else {
    ["--force", "-i", CefProcessName, "--sign", identity, path]
  }
}

///|
async fn sign_moonbit_seed_binaries(
  ws : @packaging.Workspace,
  identity : String,
  jit_entitlements : String,
  distribution~ : Bool,
) -> Unit {
  // `ws.at(...)` is absolute, so the walked paths name the same file no matter
  // which cwd `codesign` runs in.
  let seed_dir = ws.at(MoonbitSeedDir)
  if !@asyncfs.exists(seed_dir) {
    return
  }
  sign_macho_files_under(
    ws,
    seed_dir,
    identity,
    jit_entitlements,
    distribution~,
  )
}

///|
/// Sign every Mach-O file under `dir`, an absolute path so the recursive
/// traversal and the `codesign` invocation resolve the same file regardless of
/// the process or command working directory. Binaries that JIT wasm get the
/// JIT entitlements; everything else is signed bare.
async fn sign_macho_files_under(
  ws : @packaging.Workspace,
  dir : String,
  identity : String,
  jit_entitlements : String,
  distribution~ : Bool,
) -> Unit {
  for entry in @asyncfs.readdir(dir, sort=true) {
    let path = dir + "/" + entry
    if @asyncfs.kind(path) is Directory {
      sign_macho_files_under(
        ws,
        path,
        identity,
        jit_entitlements,
        distribution~,
      )
    } else if is_macho_file(path) {
      let args = if needs_jit_entitlements(entry) {
        codesign_file_args(
          identity,
          path,
          distribution~,
          entitlements=jit_entitlements,
        )
      } else {
        codesign_file_args(identity, path, distribution~)
      }
      @packaging.run_checked("codesign", args, dir=ws.dir())
    }
  }
}

///|
/// Sign the bundled CEF runtime for Developer ID distribution. The loose dylibs
/// and the runtime's loose `cef_process` binary are signed individually. The
/// Chromium framework is signed inside-out: notarization rejects any nested
/// mach-o without a Developer ID signature and secure timestamp, so its
/// `Libraries/*.dylib` are signed first, then the bundle signature seals over
/// them. (Touching inner files AFTER the bundle signature is what breaks the
/// seal, not signing them before.)
async fn sign_proton_runtime_for_distribution(
  ws : @packaging.Workspace,
  identity : String,
) -> Unit {
  let root = ws.at(ProtonRuntimePath)
  sign_runtime_machos_outside_framework(ws, root, identity)
  let frameworks_dir = root + "/Frameworks"
  if @asyncfs.exists(frameworks_dir) {
    for entry in @asyncfs.readdir(frameworks_dir, sort=true) {
      if entry.has_suffix(".framework") {
        let framework = frameworks_dir + "/" + entry
        let libraries_dir = framework + "/Libraries"
        if @asyncfs.exists(libraries_dir) {
          for library in @asyncfs.readdir(libraries_dir, sort=true) {
            let library_path = libraries_dir + "/" + library
            if @asyncfs.kind(library_path) is Regular &&
              is_macho_file(library_path) {
              @packaging.run_checked(
                "codesign",
                [
                  "--force", "--options", "runtime", "--timestamp", "--sign", identity,
                  library_path,
                ],
                dir=ws.dir(),
              )
            }
          }
        }
        @packaging.run_checked(
          "codesign",
          [
            "--force", "--options", "runtime", "--timestamp", "--sign", identity,
            framework,
          ],
          dir=ws.dir(),
        )
      }
    }
  }
}

///|
/// Sign every mach-o under `dir` except those inside a `.framework` bundle,
/// which must be signed as a unit by the caller. `cef_process` keeps its
/// identifier so CEF's helper bootstrap accepts it.
async fn sign_runtime_machos_outside_framework(
  ws : @packaging.Workspace,
  dir : String,
  identity : String,
) -> Unit {
  for entry in @asyncfs.readdir(dir, sort=true) {
    let path = dir + "/" + entry
    if @asyncfs.kind(path) is Directory {
      if entry.has_suffix(".framework") {
        continue
      }
      sign_runtime_machos_outside_framework(ws, path, identity)
    } else if is_macho_file(path) {
      let args = if entry == "cef_process" {
        codesign_cef_process_args(identity, path, distribution=true)
      } else {
        [
          "--force", "--options", "runtime", "--timestamp", "--sign", identity, path,
        ]
      }
      @packaging.run_checked("codesign", args, dir=ws.dir())
    }
  }
}

///|
async fn sign_cef_helper(
  ws : @packaging.Workspace,
  identity : String,
  entitlements : String,
  distribution~ : Bool,
) -> Unit {
  for helper in cef_helper_variants() {
    let app_path = ws.at(helper.app_path())
    if !@asyncfs.exists(app_path) {
      continue
    }
    @packaging.run_checked(
      "codesign",
      codesign_app_bundle_args(identity, app_path, entitlements, distribution~),
      dir=ws.dir(),
    )
  }
}

///|
async fn write_signing_entitlements(ws : @packaging.Workspace) -> String {
  let path = ws.at(SigningEntitlementsPath)
  @packaging.write_text(path, signing_entitlements_source())
  path
}

///|
async fn write_jit_entitlements(ws : @packaging.Workspace) -> String {
  let path = ws.at(JitEntitlementsPath)
  @packaging.write_text(path, jit_entitlements_source())
  path
}

///|
priv struct ArtifactPlan {
  dmg : Bool
  zip : Bool
} derive(Debug, Eq)

///|
fn parse_artifact_plan(values : ArrayView[String]) -> ArtifactPlan raise {
  if values.is_empty() {
    return { dmg: true, zip: true }
  }
  let mut dmg = false
  let mut zip = false
  for value in values {
    match value {
      "app" => ()
      "dmg" => dmg = true
      "zip" => zip = true
      value =>
        raise @packaging.PackageError(
          "unsupported macOS package target '\{value}'; expected app, dmg, or zip",
        )
    }
  }
  { dmg, zip }
}

///|
/// Signing configuration from the package arguments: `--sign <identity>` names
/// a Developer ID Application identity for distribution, `--notarize <profile>`
/// names a notarytool keychain profile.
priv struct SignConfig {
  identity : String?
  notary_profile : String?
}

///|
priv struct PackageOptions {
  artifacts : ArtifactPlan
  sign : SignConfig
}

///|
fn package_command() -> @argparse.Command {
  Command(
    "package/macos",
    about="Build the macOS app bundle, DMG, and zip archive.",
    options=[
      OptionArg(
        "target",
        action=Append,
        about="Artifact to produce: app, dmg, or zip. Repeatable; defaults to dmg and zip.",
      ),
      OptionArg(
        "sign",
        about="Developer ID Application identity for distribution signing.",
      ),
      OptionArg(
        "notarize",
        about="notarytool keychain profile for notarization.",
        requires=["sign"],
      ),
    ],
  )
}

///|
fn parsed_option_value(
  matches : @argparse.Matches,
  name : String,
) -> String? raise {
  match matches.values.get(name) {
    Some([value]) => {
      let text = value.trim()
      if text.is_empty() {
        raise @packaging.PackageError("--\{name} needs a non-empty value")
      }
      Some(text.to_owned())
    }
    _ => None
  }
}

///|
fn parse_package_options(argv? : ArrayView[String]) -> PackageOptions raise {
  let matches = package_command().parse(argv?)
  let artifacts = match matches.values.get("target") {
    Some(values) => parse_artifact_plan(values)
    None => parse_artifact_plan([])
  }
  let sign = {
    identity: parsed_option_value(matches, "sign"),
    notary_profile: parsed_option_value(matches, "notarize"),
  }
  if sign.notary_profile is Some(_) && !artifacts.dmg {
    raise @packaging.PackageError("--notarize requires --target dmg")
  }
  { artifacts, sign }
}

///|
async fn sign_app(ws : @packaging.Workspace, sign : SignConfig) -> Unit {
  let entitlements = write_signing_entitlements(ws)
  let jit_entitlements = write_jit_entitlements(ws)
  guard sign.identity is Some(identity) else {
    sign_moonbit_seed_binaries(ws, "-", jit_entitlements, distribution=false)
    sign_cef_helper(ws, "-", entitlements, distribution=false)
    // Do NOT re-sign the bundled CEF runtime. `cef setup` ships it
    // linker-signed (a valid adhoc signature); re-signing with `codesign`
    // replaces that with a plain adhoc signature. The runtime under Resources
    // is sealed as data by the outer app signature. Only our own binaries and
    // helper app copies need signing.
    @packaging.run_checked(
      "codesign",
      ["--force", "--sign", "-", MacOSPath + "/openseek"],
      dir=ws.dir(),
    )
    @packaging.run_checked(
      "codesign",
      codesign_app_bundle_args("-", AppPath, entitlements, distribution=false),
      dir=ws.dir(),
    )
    return
  }
  // Real distribution signing: hardened runtime and a secure timestamp are
  // notarization requirements. Sign inside-out: nested executables first, then
  // the bundle, because deprecated `--deep` signs nested code with the wrong
  // designated requirements.
  sign_moonbit_seed_binaries(ws, identity, jit_entitlements, distribution=true)
  // Sign the bundled CEF runtime inside-out before the app so every executable
  // carries the hardened-runtime signature notarization requires. UNVALIDATED:
  // no Developer ID host here. Unlike the adhoc path (which must leave the
  // runtime's linker signatures untouched), notarization forces a re-sign — so
  // do it the way CEF tolerates: sign the loose dylibs and the `cef_process`
  // helper while preserving the helper's `cef_process` identifier (a mangled id
  // SIGTRAPs the helper), then sign the framework as a bundle, never walking
  // into its inner mach-o (that breaks the framework seal).
  sign_proton_runtime_for_distribution(ws, identity)
  sign_cef_helper(ws, identity, entitlements, distribution=true)
  @packaging.run_checked(
    "codesign",
    [
      "--force",
      "--options",
      "runtime",
      "--timestamp",
      "--sign",
      identity,
      MacOSPath + "/openseek",
    ],
    dir=ws.dir(),
  )
  @packaging.run_checked(
    "codesign",
    codesign_app_bundle_args(identity, AppPath, entitlements, distribution=true),
    dir=ws.dir(),
  )
  @packaging.run_checked(
    "codesign",
    ["--verify", "--strict", "--verbose=2", AppPath],
    dir=ws.dir(),
  )
}

///|
async fn zip_app(ws : @packaging.Workspace) -> Unit {
  @packaging.run_checked(
    "ditto",
    ["-c", "-k", "--sequesterRsrc", "--keepParent", AppPath, ZipPath],
    dir=ws.dir(),
  )
}

///|
async fn create_dmg(ws : @packaging.Workspace, sign : SignConfig) -> Unit {
  @packaging.remove_path_if_exists(ws.at(DmgStagingPath))
  @packaging.ensure_dir(ws.at(DmgStagingPath))
  // ditto preserves the signed bundle's metadata while placing it beside the
  // conventional /Applications shortcut used by drag-to-install DMGs.
  @packaging.run_checked(
    "ditto",
    [AppPath, DmgStagingPath + "/OpenSeek Desktop.app"],
    dir=ws.dir(),
  )
  @packaging.run_checked(
    "ln",
    ["-s", "/Applications", DmgStagingPath + "/Applications"],
    dir=ws.dir(),
  )
  @packaging.run_checked(
    "hdiutil",
    [
      "create",
      "-volname",
      "OpenSeek Desktop",
      "-srcfolder",
      DmgStagingPath,
      "-format",
      "UDZO",
      "-ov",
      DmgPath,
    ],
    dir=ws.dir(),
  )
  @packaging.remove_path_if_exists(ws.at(DmgStagingPath))
  if sign.identity is Some(identity) {
    @packaging.run_checked(
      "codesign",
      ["--force", "--timestamp", "--sign", identity, DmgPath],
      dir=ws.dir(),
    )
    @packaging.run_checked(
      "codesign",
      ["--verify", "--strict", "--verbose=2", DmgPath],
      dir=ws.dir(),
    )
  }
  @packaging.run_checked("hdiutil", ["verify", DmgPath], dir=ws.dir())
}

///|
/// Submit only the signed DMG when `--notarize` names a keychain profile.
/// Apple records tickets for the outer image and its nested app in that one
/// submission, so both artifacts can be stapled and validated before the
/// updater zip is built from the now-stapled source app.
async fn notarize_if_configured(
  ws : @packaging.Workspace,
  sign : SignConfig,
) -> Unit {
  guard sign.notary_profile is Some(profile) else { return }
  @packaging.run_checked(
    "xcrun",
    ["notarytool", "submit", DmgPath, "--keychain-profile", profile, "--wait"],
    dir=ws.dir(),
  )
  @packaging.run_checked("xcrun", ["stapler", "staple", DmgPath], dir=ws.dir())
  @packaging.run_checked("xcrun", ["stapler", "staple", AppPath], dir=ws.dir())
  @packaging.run_checked(
    "xcrun",
    ["stapler", "validate", DmgPath],
    dir=ws.dir(),
  )
  @packaging.run_checked(
    "xcrun",
    ["stapler", "validate", AppPath],
    dir=ws.dir(),
  )
  @packaging.run_checked("hdiutil", ["verify", DmgPath], dir=ws.dir())
}

///|
async fn sign_and_package(
  ws : @packaging.Workspace,
  sign : SignConfig,
  artifacts : ArtifactPlan,
) -> Unit {
  sign_app(ws, sign)
  if artifacts.dmg {
    create_dmg(ws, sign)
    notarize_if_configured(ws, sign)
  }
  if artifacts.zip {
    zip_app(ws)
  }
}

///|
async fn main {
  // Parse first: a mistyped flag must fail before the build, not after it.
  let options = parse_package_options()
  let ws = @packaging.locate_workspace()
  @packaging.ensure_cmake(ws)
  build_outputs(ws)
  println("built openseek engine: \{ws.engine_binary()}")
  reset_bundle_dirs(ws)
  copy_bundle_files(ws)
  write_bundle_metadata(ws)
  sign_and_package(ws, options.sign, options.artifacts)
  println("generated \{ws.at(AppPath)}")
  if options.artifacts.dmg {
    println("generated \{ws.at(DmgPath)}")
  }
  if options.artifacts.zip {
    println("generated \{ws.at(ZipPath)}")
    println(
      "release with scripts/publish-release.sh — it uploads the zip to openseek-api and publishes the version",
    )
  }
}

///|
test "macos package args default to ad-hoc signing" {
  let options = parse_package_options(argv=[])
  assert_true(options.sign.identity is None)
  assert_true(options.sign.notary_profile is None)
  assert_eq(options.artifacts, { dmg: true, zip: true })
}

///|
test "macos helper plist describes cef helper app" {
  let helper = cef_helper_variants()[0]
  let plist = helper_info_plist_source(helper)
  assert_true(
    plist.contains(
      "<key>CFBundleExecutable</key><string>\{HelperExecutableBaseName}</string>",
    ),
  )
  assert_true(
    plist.contains(
      "<key>CFBundleIdentifier</key><string>\{HelperBundleIdentifier}</string>",
    ),
  )
  assert_true(
    plist.contains(
      "<key>LSMinimumSystemVersion</key><string>\{MinMacOSVersion}</string>",
    ),
  )
  assert_true(plist.contains("<key>LSUIElement</key><true/>"))
}

///|
test "macos renderer helper plist uses cef helper variant name" {
  let helper = cef_helper_variants()[4]
  let plist = helper_info_plist_source(helper)
  assert_eq(helper.executable_name(), "OpenSeek Desktop Helper (Renderer)")
  assert_eq(
    helper.executable_path(),
    "dist/OpenSeek Desktop.app/Contents/Frameworks/OpenSeek Desktop Helper (Renderer).app/Contents/MacOS/OpenSeek Desktop Helper (Renderer)",
  )
  assert_true(
    plist.contains(
      "<key>CFBundleExecutable</key><string>OpenSeek Desktop Helper (Renderer)</string>",
    ),
  )
  assert_true(
    plist.contains(
      "<key>CFBundleIdentifier</key><string>community.moonbit.proton.openseek-desktop.helper.renderer</string>",
    ),
  )
}

///|
test "macos base helper path points at chromium helper executable name" {
  let helper = cef_helper_variants()[0]
  assert_eq(
    helper.executable_path(),
    "dist/OpenSeek Desktop.app/Contents/Frameworks/OpenSeek Desktop Helper.app/Contents/MacOS/OpenSeek Desktop Helper",
  )
}

///|
test "macos helper executable rpath points back to bundled proton runtime" {
  assert_eq(HelperProtonRPath, "@loader_path/../../../../Resources/proton/lib")
}

///|
test "macos host executable rpath points at bundled proton runtime" {
  assert_eq(HostProtonRPath, "@executable_path/../Resources/proton/lib")
}

///|
test "macos package args parse signing and notarization" {
  let options = parse_package_options(argv=[
    "--sign", "Developer ID Application: Example", "--notarize", "notary",
  ])
  assert_true(
    options.sign.identity is Some("Developer ID Application: Example"),
  )
  assert_true(options.sign.notary_profile is Some("notary"))
}

///|
test "macos notarization requires distribution signing" {
  try parse_package_options(argv=["--notarize", "notary"]) catch {
    err =>
      assert_true(
        err
        .to_string()
        .contains(
          "required argument was not provided: 'sign' (required by 'notarize')",
        ),
      )
  } noraise {
    _ => fail("expected --notarize without --sign to fail")
  }
}

///|
test "macos package target app skips distribution archives" {
  let options = parse_package_options(argv=["--target", "app"])
  assert_eq(options.artifacts, { dmg: false, zip: false })
}

///|
test "macos package target dmg includes the app but skips zip" {
  let options = parse_package_options(argv=["--target", "dmg"])
  assert_eq(options.artifacts, { dmg: true, zip: false })
}

///|
test "macos package targets can be repeated" {
  let options = parse_package_options(argv=[
    "--target", "app", "--target", "zip",
  ])
  assert_eq(options.artifacts, { dmg: false, zip: true })
}

///|
test "macos package rejects an unsupported target" {
  try parse_package_options(argv=["--target", "pkg"]) catch {
    err =>
      assert_true(
        err
        .to_string()
        .contains(
          "unsupported macOS package target 'pkg'; expected app, dmg, or zip",
        ),
      )
  } noraise {
    _ => fail("expected unsupported target to fail")
  }
}

///|
test "macos notarization requires the dmg target" {
  try
    parse_package_options(argv=[
      "--target", "app", "--sign", "Developer ID Application: Example", "--notarize",
      "notary",
    ])
  catch {
    err =>
      assert_true(err.to_string().contains("--notarize requires --target dmg"))
  } noraise {
    _ => fail("expected app-only notarization to fail")
  }
}
