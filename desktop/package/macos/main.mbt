///|
const MinMacOSVersion : String = "12.0"

///|
const PackageInputRoot : String = "target/proton-package-input"

///|
const PackageAssetDir : String = PackageInputRoot + "/assets"

///|
const PackageBinDir : String = PackageInputRoot + "/bin"

///|
const SigningEntitlementsPath : String = "package/macos/SeekMoon.entitlements"

///|
/// Proton always produces the macOS app bundle. Keep only the optional archive
/// choices here instead of carrying Proton's string-valued CLI arguments into
/// the packaging model.
priv struct ArtifactPlan {
  dmg : Bool
  zip : Bool
} derive(Debug, Eq)

///|
fn ArtifactPlan::parse(values : Array[String]) -> ArtifactPlan raise {
  let mut dmg = false
  let mut zip = false
  for value in values {
    match value {
      "app" => ()
      "dmg" => dmg = true
      "zip" => zip = true
      value =>
        raise @packaging.PackageError(
          "unsupported macOS package target: \{value} (expected app, zip, or dmg)",
        )
    }
  }
  { dmg, zip }
}

///|
priv struct SignConfig {
  identity : String?
  notary_profile : String?
}

///|
priv struct PackageOptions {
  artifacts : ArtifactPlan
  sign : SignConfig
  release : Bool
}

///|
fn PackageOptions::command() -> @argparse.Command {
  Command(
    "package/macos",
    about="Prepare OpenSeek inputs and package them with proton_cli.",
    flags=[
      FlagArg(
        "release",
        about="Build optimized release artifacts instead of debug artifacts.",
      ),
    ],
    options=[
      OptionArg(
        "target",
        action=Append,
        about="Artifact to produce: app, dmg, or zip. Repeatable; defaults to app.",
      ),
      OptionArg(
        "sign",
        about="Developer ID Application identity for Proton signing.",
      ),
      OptionArg(
        "notarize",
        about="notarytool keychain profile for Proton notarization.",
        requires=["sign"],
      ),
    ],
  )
}

///|
fn PackageOptions::parse(argv? : ArrayView[String]) -> PackageOptions raise {
  let matches = PackageOptions::command().parse(argv?)
  let artifacts = ArtifactPlan::parse(
    matches.values.get("target").unwrap_or([]),
  )
  let identity = match matches.values.get("sign") {
    Some([value, ..]) => Some(value)
    _ => None
  }
  let notary_profile = match matches.values.get("notarize") {
    Some([value, ..]) => Some(value)
    _ => None
  }
  if notary_profile is Some(_) && !artifacts.dmg {
    raise @packaging.PackageError("--notarize requires --target dmg")
  }
  // A Developer ID signature marks distributable output. Require an explicit
  // archive target instead of signing only the intermediate app bundle.
  if identity is Some(_) && !artifacts.dmg && !artifacts.zip {
    raise @packaging.PackageError(
      "--sign requires a distribution target (--target dmg or --target zip)",
    )
  }
  {
    artifacts,
    sign: { identity, notary_profile },
    release: matches.flags.get("release").unwrap_or(false),
  }
}

///|
/// Build the exact Proton command arguments for this package selection. The
/// release flag must reach Proton even with `--no-build`, because Proton uses
/// it to select the native host from its debug or release target directory.
fn PackageOptions::proton_args(
  self : PackageOptions,
  workspace : @packaging.Workspace,
) -> Array[String] {
  let args = [
    "-C",
    workspace.dir(),
    "package",
    "--config",
    "proton.project.json",
    "--no-build",
    "--target",
    "app",
  ]
  if self.release {
    args.push("--release")
  }
  if self.artifacts.zip {
    args.append(["--target", "zip"])
  }
  if self.artifacts.dmg {
    args.append(["--target", "dmg"])
  }
  if self.sign.identity is Some(_) {
    args.push("--sign")
  }
  if self.sign.notary_profile is Some(_) {
    args.push("--notarize")
  }
  args
}

///|
/// Build the application-specific inputs Proton cannot infer from
/// `proton.project.json`. The native host builds into the workspace's
/// default `_build` tree in the selected mode, which is where
/// `package --no-build` looks the executable up since lepus #116 removed
/// the identifier-scoped package target directories.
async fn @packaging.Workspace::build_package_inputs(
  self : @packaging.Workspace,
  release~ : Bool,
) -> @xterm_assets.Assets {
  let build_env = {
    "MACOSX_DEPLOYMENT_TARGET": MinMacOSVersion,
    "PROTON_PACKAGE_RPATH": "@executable_path/../Resources/proton/lib",
  }
  self.prepare_checkout_proton_runtime(@packaging.posix_proton_cli(), extra_env={
    "MACOSX_DEPLOYMENT_TARGET": MinMacOSVersion,
  })
  @packaging.build_frontend_bundle(self, release~)
  let terminal_assets = @xterm_assets.build(
    self,
    @xterm_assets.macos_arm64_target(),
  )
  @packaging.build_native_host(self, release~, extra_env=build_env)
  @packaging.build_engine(self, release~, extra_env={
    "MACOSX_DEPLOYMENT_TARGET": MinMacOSVersion,
  })
  terminal_assets
}

///|
/// Rebuild the declarative resource tree consumed by `bundle.resources`.
/// Proton preserves this project-relative tree below `Contents/Resources`;
/// runtime lookup code deliberately knows this one stable prefix.
async fn @packaging.Workspace::stage_package_inputs(
  self : @packaging.Workspace,
  terminal_assets : @xterm_assets.Assets,
  release~ : Bool,
) -> Unit {
  @packaging.remove_path_if_exists(self.at(PackageInputRoot))
  @packaging.ensure_dir(self.at(PackageAssetDir))
  @packaging.ensure_dir(self.at(PackageBinDir))
  @packaging.copy_file(
    self.app_stylesheet(),
    self.at(PackageAssetDir + "/app.css"),
  )
  for
    pair in [
      ("index.html", PackageAssetDir + "/index.html"),
      ("frontend.js", PackageAssetDir + "/frontend.js"),
      ("viewer.css", PackageAssetDir + "/viewer.css"),
      ("codicon.ttf", PackageAssetDir + "/codicon.ttf"),
    ] {
    let (source, destination) = pair
    @packaging.copy_file(self.at(source), self.at(destination))
  }
  @packaging.copy_file(
    terminal_assets.javascript,
    self.at(PackageAssetDir + "/xterm.js"),
  )
  @packaging.copy_file(
    terminal_assets.stylesheet,
    self.at(PackageAssetDir + "/xterm.css"),
  )
  @packaging.copy_tree(
    self.mermaid_assets(),
    self.at(PackageAssetDir + "/mermaid"),
  )
  @packaging.copy_tree(self.at("fonts"), self.at(PackageAssetDir + "/fonts"))
  @packaging.copy_file(
    self.engine_binary(release~),
    self.at(PackageBinDir + "/openseek"),
  )
  @packaging.run_checked(
    "chmod",
    ["+x", PackageBinDir + "/openseek"],
    dir=self.dir(),
  )
  // Proton applies the static `bundle.sign.binaries` list to both ad-hoc and
  // Developer ID signing, so every macOS app must stage these seed binaries.
  let target = @moonbit.moonbit_macos_arm64_toolchain()
  @moonbit.stage_moonbit_toolchain_seed(
    self,
    target,
    PackageInputRoot + "/" + target.seed_relative_dir(),
  )
}

///|
/// Hand the prepared host and resource tree to Proton. From here Proton owns
/// the App layout, CEF helper bundles, package metadata, signatures,
/// notarization, ZIP, and DMG.
async fn @packaging.Workspace::package_with_proton(
  self : @packaging.Workspace,
  options : PackageOptions,
) -> Unit {
  let args = options.proton_args(self)
  let package_env : Map[String, String] = {
    "PROTON_MACOS_ENTITLEMENTS": self.at(SigningEntitlementsPath),
    // The OpenSeek moon.work root is above this embedded Proton checkout, so
    // package cannot discover the runtime manifest by walking the workspace.
    "PROTON_NATIVE_DIST": @packaging.proton_runtime_dist(self),
  }
  match options.sign.identity {
    Some(identity) => package_env["PROTON_MACOS_SIGNING_IDENTITY"] = identity
    None => ()
  }
  match options.sign.notary_profile {
    Some(profile) => package_env["PROTON_NOTARY_PROFILE"] = profile
    None => ()
  }
  @packaging.run_checked(
    self.at(@packaging.posix_proton_cli()),
    args,
    dir=self.dir(),
    extra_env=package_env,
  ) catch {
    error if @async.is_being_cancelled() => raise error
    error => {
      // Keep Proton's original failure as the authority. This extra hint is
      // deliberately conditional because proton_cli also handles non-signing
      // stages, while a running moon-lsp is only one possible cause of a
      // damaged macOS app seal.
      println(
        "hint: if codesign verification failed, a running moon-lsp may have modified a sealed app file; stop moon-lsp and retry",
      )
      raise error
    }
  }
}

///|
async fn main {
  let options = PackageOptions::parse()
  let ws = @packaging.locate_workspace()
  let terminal_assets = ws.build_package_inputs(release=options.release)
  ws.stage_package_inputs(terminal_assets, release=options.release)
  ws.package_with_proton(options)
  let _ = @process.run("open", [ws.at("dist/SeekMoon.app")])
}

///|
test "macOS packaging defaults to Proton app output" {
  let options = PackageOptions::parse(argv=[])
  @debug.assert_eq(options.artifacts, { dmg: false, zip: false })
  assert_true(options.sign.identity is None)
  assert_true(options.sign.notary_profile is None)
  assert_false(options.release)
}

///|
test "macOS packaging accepts release builds" {
  let options = PackageOptions::parse(argv=["--release"])
  assert_true(options.release)
}

///|
async test "macOS packaging passes the selected mode to Proton" {
  let workspace = @packaging.locate_workspace()
  let debug_args = PackageOptions::parse(argv=[]).proton_args(workspace)
  assert_false(debug_args.contains("--release"))
  let release_args = PackageOptions::parse(argv=["--release"]).proton_args(
    workspace,
  )
  assert_true(release_args.contains("--release"))
}

///|
test "macOS packaging combines optional archive targets" {
  let options = PackageOptions::parse(argv=[
    "--target", "app", "--target", "zip", "--target", "dmg",
  ])
  @debug.assert_eq(options.artifacts, { dmg: true, zip: true })
}

///|
test "macOS signing requires a distribution target" {
  try PackageOptions::parse(argv=["--sign", "Developer ID"]) catch {
    error =>
      assert_true(
        error.to_string().contains("--sign requires a distribution target"),
      )
  } noraise {
    _ => fail("expected --sign without a distribution target to fail")
  }
}
