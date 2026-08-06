///|
const MinMacOSVersion : String = "12.0"

///|
const PackageInputRoot : String = "target/proton-package-input"

///|
const PackageAssetDir : String = PackageInputRoot + "/assets"

///|
const PackageBinDir : String = PackageInputRoot + "/bin"

///|
/// Proton's default release-build target for the identifier declared in
/// `moon.proton`. Keep this path in sync if that identifier changes.
const ProtonPackageBuildTargetDir : String = "target/proton-package-build/community-moonbit-proton-openseek-desktop"

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
}

///|
fn PackageOptions::command() -> @argparse.Command {
  Command(
    "package/macos",
    about="Prepare OpenSeek inputs and package them with proton_cli.",
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
  { artifacts, sign: { identity, notary_profile } }
}

///|
/// Build the application-specific inputs Proton cannot infer from
/// `moon.proton`. The native host is written directly to Proton's default,
/// identifier-scoped package target so `package --no-build` consumes exactly
/// this specialized, no-mimalloc build.
async fn @packaging.Workspace::build_package_inputs(
  self : @packaging.Workspace,
) -> @xterm_assets.Assets {
  let build_env = {
    "MACOSX_DEPLOYMENT_TARGET": MinMacOSVersion,
    "PROTON_PACKAGE_RPATH": "@executable_path/../Resources/proton/lib",
  }
  @packaging.assemble_cef_runtime(self, @packaging.posix_proton_cli(), extra_env={
    "MACOSX_DEPLOYMENT_TARGET": MinMacOSVersion,
  })
  @packaging.build_frontend_bundle(self, release=true)
  let terminal_assets = @xterm_assets.build(
    self,
    @xterm_assets.macos_arm64_target(),
  )
  @packaging.build_native_host(
    self,
    release=true,
    extra_args=["--target-dir", self.repo_at(ProtonPackageBuildTargetDir)],
    extra_env=build_env,
    disable_mimalloc=true,
  )
  @packaging.build_engine(self, release=true, extra_env={
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
) -> Unit {
  @packaging.remove_path_if_exists(self.at(PackageInputRoot))
  @packaging.ensure_dir(self.at(PackageAssetDir))
  @packaging.ensure_dir(self.at(PackageBinDir))
  for
    pair in [
      ("index.html", PackageAssetDir + "/index.html"),
      ("app.css", PackageAssetDir + "/app.css"),
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
    self.engine_binary(release=true),
    self.at(PackageBinDir + "/openseek"),
  )
  @packaging.run_checked(
    "chmod",
    ["+x", PackageBinDir + "/openseek"],
    dir=self.dir(),
  )
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
  let args = [
    "-C",
    self.dir(),
    "package",
    "--config",
    "moon.proton",
    "--no-build",
    "--target",
    "app",
  ]
  if options.artifacts.zip {
    args.append(["--target", "zip"])
  }
  if options.artifacts.dmg {
    args.append(["--target", "dmg"])
  }
  let package_env : Map[String, String] = {
    "PROTON_MACOS_ENTITLEMENTS": self.at(SigningEntitlementsPath),
    // The OpenSeek moon.work root is above this embedded Proton checkout, so
    // package cannot discover the runtime manifest by walking the workspace.
    "PROTON_NATIVE_DIST": @packaging.proton_runtime_dist(self),
  }
  match options.sign.identity {
    Some(identity) => {
      package_env["PROTON_MACOS_SIGNING_IDENTITY"] = identity
      args.push("--sign")
    }
    None => ()
  }
  match options.sign.notary_profile {
    Some(profile) => {
      package_env["PROTON_NOTARY_PROFILE"] = profile
      args.push("--notarize")
    }
    None => ()
  }
  @packaging.run_checked(
    self.at(@packaging.posix_proton_cli()),
    args,
    dir=self.dir(),
    extra_env=package_env,
  )
}

///|
async fn main {
  let options = PackageOptions::parse()
  let ws = @packaging.locate_workspace()
  let terminal_assets = ws.build_package_inputs()
  ws.stage_package_inputs(terminal_assets)
  ws.package_with_proton(options)
}

///|
test "macOS packaging defaults to Proton app output" {
  let options = PackageOptions::parse(argv=[])
  @debug.assert_eq(options.artifacts, { dmg: false, zip: false })
  assert_true(options.sign.identity is None)
  assert_true(options.sign.notary_profile is None)
}

///|
test "macOS packaging combines optional archive targets" {
  let options = PackageOptions::parse(argv=[
    "--target", "app", "--target", "zip", "--target", "dmg",
  ])
  @debug.assert_eq(options.artifacts, { dmg: true, zip: true })
}
