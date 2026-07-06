// The publishable release layout. `dist/releases/` mirrors the server's
// releases directory: one `v<version>/` directory of artifacts plus a
// `latest.json` derived from whatever artifacts are in it — so the manifest
// is never written by hand, and assembling a multi-platform release is
// "collect every platform's artifact into the directory, regenerate".

///|
/// Where release files download from by default: openseek-api's
/// `/desktop/releases/` routes. Override with OPENSEEK_RELEASES_BASE_URL to
/// publish the artifacts elsewhere (an OSS bucket / CDN) — the manifest is
/// data, so the client follows whatever https URL it names.
const DefaultReleasesBaseUrl : String = "https://openseek-api.moonbitlang.cn/desktop/releases"

///|
const ReleasesBaseUrlEnv : String = "OPENSEEK_RELEASES_BASE_URL"

///|
/// The page the update toast opens when in-app install is unavailable.
const ReleasePageUrl : String = "https://github.com/moonbitlang/openseek/releases/latest"

///|
/// Artifacts are published as `OpenSeek-Desktop-<platform>.<extension>`;
/// the infix is the manifest `platforms` key the client looks itself up
/// by (`macos-arm64` today). Names must survive the server's URL path
/// guard: alphanumeric start, then alphanumerics, `.`, `-`, `_`.
const ReleaseArtifactPrefix : String = "OpenSeek-Desktop-"

///|
/// The workspace-relative release layout root.
pub const ReleasesLayoutDir : String = "dist/releases"

///|
fn releases_base_url() -> String {
  guard @env.get(ReleasesBaseUrlEnv) is Some(base) else {
    return DefaultReleasesBaseUrl
  }
  base.trim_end(chars="/").to_owned()
}

///|
priv struct ReleaseArtifact {
  url : String
  sha256 : String
} derive(ToJson)

///|
/// The manifest the desktop's update checker consumes; see
/// `internal/update` for the decoding contract.
priv struct ReleaseManifest {
  version : String
  url : String
  platforms : Map[String, ReleaseArtifact]
} derive(ToJson)

///|
/// The manifest platforms key an artifact file publishes under: the
/// filename minus the product prefix and the extension. Anything not
/// matching the naming convention is not an artifact.
fn artifact_platform_key(file_name : String) -> String? {
  guard file_name.strip_prefix(ReleaseArtifactPrefix) is Some(rest) else {
    return None
  }
  let rest = rest.to_owned()
  guard rest.rev_find(".") is Some(dot) && dot > 0 else { return None }
  Some(rest.view(end_offset=dot).to_owned())
}

///|
fn release_manifest_source(
  version : String,
  platforms : Map[String, ReleaseArtifact],
) -> String {
  let manifest : ReleaseManifest = { version, url: ReleasePageUrl, platforms }
  manifest.to_json().stringify(indent=2) + "\n"
}

///|
/// Regenerate `latest.json` from the artifacts staged under the version's
/// directory, computing each digest here so the manifest can never
/// disagree with the files it points at. Platform packagers call this
/// after staging their own artifact; `package/release` reruns it after
/// other platforms' artifacts are dropped in.
pub async fn write_release_manifest(ws : Workspace, version : String) -> Unit {
  let layout = ws.at(ReleasesLayoutDir)
  let versioned = "\{layout}/v\{version}"
  guard @asyncfs.exists(versioned) else {
    raise PackageError("no staged artifacts: \{versioned} does not exist")
  }
  let platforms : Map[String, ReleaseArtifact] = {}
  for file_name in @asyncfs.readdir(versioned, sort=true) {
    guard artifact_platform_key(file_name) is Some(key) else {
      println("release manifest: skipping non-artifact file \{file_name}")
      continue
    }
    let digest = @crypto.bytes_to_hex_string(
      @crypto.sha256(@asyncfs.read_file("\{versioned}/\{file_name}").binary()),
    ).to_lower()
    platforms[key] = {
      url: "\{releases_base_url()}/v\{version}/\{file_name}",
      sha256: digest,
    }
  }
  guard !platforms.is_empty() else {
    raise PackageError("no release artifacts found in \{versioned}")
  }
  write_text(
    "\{layout}/latest.json",
    release_manifest_source(version, platforms),
  )
  println("wrote \{layout}/latest.json (\{platforms.length()} platform(s))")
}
