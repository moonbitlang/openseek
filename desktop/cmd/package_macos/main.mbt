///|
const AppPath : String = "dist/OpenSeek Desktop.app"

///|
const ZipPath : String = "dist/OpenSeek Desktop-macos-arm64.zip"

///|
const ContentsPath : String = AppPath + "/Contents"

///|
const MacOSPath : String = ContentsPath + "/MacOS"

///|
const ResourcesPath : String = ContentsPath + "/Resources"

///|
/// Frontend assets live under Resources, not MacOS: codesign without the
/// deprecated `--deep` treats everything in `Contents/MacOS/` as code and
/// rejects plain data files there.
const AppAssetDir : String = ResourcesPath + "/assets"

///|
const MoonbitSeedDir : String = ResourcesPath +
  "/toolchains/moonbit/macos-arm64"

///|
/// Minimum macOS the produced binaries run on. Without this, clang pins
/// LC_BUILD_VERSION's minos to the build machine's OS version and dyld on
/// any older system refuses to load the binary at all. Must match
/// LSMinimumSystemVersion in the Info.plist.
const MinMacOSVersion : String = "12.0"

///|
async fn build_outputs(ws : @packaging.Workspace) -> Unit {
  let env = { "MACOSX_DEPLOYMENT_TARGET": MinMacOSVersion }
  @packaging.ensure_codegen_tool(ws, @packaging.posix_codegen_tool())
  @packaging.build_frontend_bundle(ws)
  @packaging.build_native_host(ws, extra_env=env)
  @packaging.build_engine(ws, extra_env=env)
}

///|
async fn reset_bundle_dirs(ws : @packaging.Workspace) -> Unit {
  @packaging.remove_path_if_exists(ws.at(AppPath))
  @packaging.remove_path_if_exists(ws.at(ZipPath))
  @packaging.ensure_dir(ws.at(MacOSPath))
  @packaging.ensure_dir(ws.at(ResourcesPath))
  @packaging.ensure_dir(ws.at(AppAssetDir))
}

///|
/// The host binary is the bundle's main executable directly, with no shell
/// launcher in between. Resource lookups derive from argv[0], and the bundled
/// engine is resolved by absolute path, so nothing needs a `cd` or PATH entry.
async fn copy_bundle_files(ws : @packaging.Workspace) -> Unit {
  if !@asyncfs.exists(ws.at(@packaging.native_binary())) {
    raise @packaging.PackageError(
      "native binary not found: \{ws.at(@packaging.native_binary())}",
    )
  }
  if !@asyncfs.exists(ws.repo_at(@packaging.engine_binary())) {
    raise @packaging.PackageError(
      "openseek engine binary not found: \{ws.repo_at(@packaging.engine_binary())}",
    )
  }
  @packaging.copy_file(
    ws.at(@packaging.native_binary()),
    ws.at(MacOSPath + "/openseek-desktop"),
  )
  @packaging.copy_file(
    ws.repo_at(@packaging.engine_binary()),
    ws.at(MacOSPath + "/openseek"),
  )
  @packaging.copy_file(ws.at("index.html"), ws.at(AppAssetDir + "/index.html"))
  @packaging.copy_file(
    ws.at("frontend.js"),
    ws.at(AppAssetDir + "/frontend.js"),
  )
  let target = @packaging.moonbit_macos_arm64_toolchain()
  @packaging.stage_moonbit_toolchain_seed(ws, target, MoonbitSeedDir)
}

///|
fn info_plist_source() -> String {
  let source =
    #|<?xml version="1.0" encoding="UTF-8"?>
    #|<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    #|<plist version="1.0">
    #|<dict>
    #|  <key>CFBundleDevelopmentRegion</key><string>en</string>
    #|  <key>CFBundleDisplayName</key><string>OpenSeek Desktop</string>
    #|  <key>CFBundleExecutable</key><string>openseek-desktop</string>
    #|  <key>CFBundleIdentifier</key><string>community.moonbit.lepus.openseek-desktop</string>
    #|  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    #|  <key>CFBundleName</key><string>OpenSeek Desktop</string>
    #|  <key>CFBundlePackageType</key><string>APPL</string>
    #|  <key>CFBundleShortVersionString</key><string>0.1.0</string>
    #|  <key>CFBundleVersion</key><string>0.1.0</string>
    #|  <key>LSMinimumSystemVersion</key><string>12.0</string>
    #|  <key>NSHighResolutionCapable</key><true/>
    #|</dict>
    #|</plist>
    #|
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
) -> Array[String] {
  if distribution {
    ["--force", "--options", "runtime", "--timestamp", "--sign", identity, path]
  } else {
    ["--force", "--sign", identity, path]
  }
}

///|
async fn sign_moonbit_seed_binaries(
  ws : @packaging.Workspace,
  identity : String,
  distribution~ : Bool,
) -> Unit {
  let bin_dir = ws.at(MoonbitSeedDir + "/bin")
  if !@asyncfs.exists(bin_dir) {
    return
  }
  for entry in @asyncfs.readdir(bin_dir, sort=true) {
    let path = bin_dir + "/" + entry
    if @asyncfs.kind(path) is Directory {
      continue
    }
    if is_macho_file(path) {
      @packaging.run_checked(
        "codesign",
        codesign_file_args(identity, path, distribution~),
        dir=ws.dir(),
      )
    }
  }
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
fn parse_sign_config() -> SignConfig raise {
  let usage = "usage: moon run cmd/package_macos -- [--sign <identity>] [--notarize <keychain-profile>]"
  let args = @env.args()
  let mut identity : String? = None
  let mut notary_profile : String? = None
  // args[0] is the program itself; the package's own arguments follow.
  let mut index = 1
  while index < args.length() {
    let arg = args[index]
    guard arg is ("--sign" | "--notarize") else {
      raise @packaging.PackageError("unknown argument: \{arg}\n\{usage}")
    }
    guard args.get(index + 1) is Some(value) && !value.trim().is_empty() else {
      raise @packaging.PackageError("\{arg} needs a value\n\{usage}")
    }
    let value = value.trim().to_owned()
    if arg == "--sign" {
      identity = Some(value)
    } else {
      notary_profile = Some(value)
    }
    index += 2
  }
  if notary_profile is Some(_) && identity is None {
    raise @packaging.PackageError(
      "--notarize requires --sign: ad-hoc signed apps cannot be notarized",
    )
  }
  { identity, notary_profile }
}

///|
async fn sign_app(ws : @packaging.Workspace, sign : SignConfig) -> Unit {
  guard sign.identity is Some(identity) else {
    sign_moonbit_seed_binaries(ws, "-", distribution=false)
    @packaging.run_checked(
      "codesign",
      ["--force", "--deep", "--sign", "-", AppPath],
      dir=ws.dir(),
    )
    return
  }
  // Real distribution signing: hardened runtime and a secure timestamp are
  // notarization requirements. Sign inside-out: nested executables first, then
  // the bundle, because deprecated `--deep` signs nested code with the wrong
  // designated requirements.
  sign_moonbit_seed_binaries(ws, identity, distribution=true)
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
    [
      "--force",
      "--options",
      "runtime",
      "--timestamp",
      "--sign",
      identity,
      AppPath,
    ],
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
/// Notarize and staple when `--notarize` named a keychain profile. The zip is
/// rebuilt afterwards so the distributed archive carries the stapled ticket.
async fn notarize_if_configured(
  ws : @packaging.Workspace,
  sign : SignConfig,
) -> Unit {
  guard sign.notary_profile is Some(profile) else { return }
  @packaging.run_checked(
    "xcrun",
    ["notarytool", "submit", ZipPath, "--keychain-profile", profile, "--wait"],
    dir=ws.dir(),
  )
  @packaging.run_checked("xcrun", ["stapler", "staple", AppPath], dir=ws.dir())
  @packaging.remove_path_if_exists(ws.at(ZipPath))
  zip_app(ws)
}

///|
async fn sign_and_zip(ws : @packaging.Workspace, sign : SignConfig) -> Unit {
  sign_app(ws, sign)
  zip_app(ws)
  notarize_if_configured(ws, sign)
}

///|
async fn main {
  // Parse first: a mistyped flag must fail before the build, not after it.
  let sign = parse_sign_config()
  let ws = @packaging.locate_workspace()
  build_outputs(ws)
  println("built openseek engine: \{ws.repo_at(@packaging.engine_binary())}")
  reset_bundle_dirs(ws)
  copy_bundle_files(ws)
  write_bundle_metadata(ws)
  sign_and_zip(ws, sign)
  println("generated \{ws.at(AppPath)}")
  println("generated \{ws.at(ZipPath)}")
}
