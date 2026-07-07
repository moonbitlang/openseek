// Checking the hosted release manifest for a newer desktop build. The check
// is a nudge, not a feature the app depends on: fetch failures — offline,
// HTTP error, garbage, unparsable versions — read as "no update". The one
// loud case is `MalformedArtifact`: a manifest that names a package this
// platform cannot use is a publisher error, raised so it gets reported.

///|
/// The hosted release manifest, served by openseek-api from its releases
/// directory. Same origin as the default chat endpoint, so the check works
/// wherever the app itself does.
const ManifestUrl : String = "https://openseek-api.moonbitlang.cn/desktop/releases/latest.json"

///|
/// The manifest endpoint actually queried: the packaged default, or the
/// OPENSEEK_UPDATE_MANIFEST_URL override for exercising the flow against a
/// staging server (launch the bundle's executable from a terminal so the
/// variable is inherited). https only, like everything else here.
fn manifest_url() -> String {
  guard @env.get("OPENSEEK_UPDATE_MANIFEST_URL") is Some(url) &&
    url.has_prefix("https://") else {
    return ManifestUrl
  }
  url
}

///|
/// A newer hosted release: the version to announce, and — when the manifest
/// carries one for this platform — the package the app can install by
/// itself. Without a package the announcement is informational only.
pub struct UpdateInfo {
  version : String
  artifact : PackageInfo?
} derive(Eq, Debug)

///|
/// A manifest whose entry for this platform exists but cannot be used — a
/// publisher error, unlike the absence of an entry (the normal shape for
/// platforms that do not self-update). It carries the release version so
/// the caller can still announce the update alongside the reason.
pub suberror MalformedArtifact {
  MalformedArtifact(version~ : String, reason~ : String)
}

///|
/// A downloadable update package: where to fetch it and the hex sha256 the
/// download must match.
pub struct PackageInfo {
  url : String
  sha256 : String
} derive(Eq, Debug)

///|
/// The manifest `platforms` key this build installs from. Only the macOS
/// arm64 bundle self-updates today; elsewhere the manifest's page URL is
/// the whole story.
fn manifest_platform_key() -> String? {
  if @platform.is_darwin() {
    Some("macos-arm64")
  } else {
    None
  }
}

///|
/// Fetch the hosted manifest and report a release newer than `current`, or
/// None. Fetch and parse failures — offline, HTTP errors, garbage — all
/// read as "no update", so the nudge can never surface as an app error; a
/// malformed platform entry is the one exception, raised so the caller can
/// report the publisher error instead of silently not installing.
pub async fn check_for_update(current~ : String) -> UpdateInfo? {
  let (response, data) = @http.get(manifest_url()) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return None
  }
  guard response.code == 200 else { return None }
  let json = data.json() catch {
    error if @async.is_being_cancelled() => raise error
    _ => return None
  }
  newer_update(json, current~, platform_key=manifest_platform_key())
}

///|
/// Decode a manifest and keep it only when it names a strictly newer
/// version. The manifest's top-level page `url` is ignored: older builds
/// required it, so the server still publishes one, but nothing here opens
/// it anymore. Pure, so tests can cover the manifest contract without a
/// server.
fn newer_update(
  json : Json,
  current~ : String,
  platform_key~ : String?,
) -> UpdateInfo? raise MalformedArtifact {
  guard json is { "version": String(version), .. } else { return None }
  if is_newer(version, than=current) {
    Some({ version, artifact: manifest_artifact(json, platform_key, version~) })
  } else {
    None
  }
}

///|
/// The manifest's package entry for this platform, when there is one: a web
/// URL plus a plausible sha256 (optionally `sha256:`-prefixed). An entry
/// that exists but fails those checks raises, naming what is wrong with it.
fn manifest_artifact(
  json : Json,
  platform_key : String?,
  version~ : String,
) -> PackageInfo? raise MalformedArtifact {
  guard platform_key is Some(key) else { return None }
  guard json is { "platforms": Object(platforms), .. } else { return None }
  guard platforms.get(key) is Some(entry) else { return None }
  guard entry is { "url": String(url), "sha256": String(sha256), .. } else {
    raise MalformedArtifact(
      version~,
      reason="the platform entry lacks url/sha256",
    )
  }
  guard url.has_prefix("https://") else {
    raise MalformedArtifact(
      version~,
      reason="the package url is not https: \{url}",
    )
  }
  guard normalized_sha256(sha256) is Some(sha256) else {
    raise MalformedArtifact(
      version~,
      reason="the package sha256 is not a hex digest",
    )
  }
  Some({ url, sha256 })
}

///|
/// The lowercase hex form of a manifest digest, tolerating a `sha256:`
/// prefix; None unless it is exactly 64 hex characters.
fn normalized_sha256(text : String) -> String? {
  let text = text.trim()
  let text = if text.strip_prefix("sha256:") is Some(rest) {
    rest.to_owned()
  } else {
    text.to_owned()
  }
  let hex = text.to_lower()
  guard hex.length() == 64 else { return None }
  for ch in hex {
    if !(ch is ('0'..='9' | 'a'..='f')) {
      return None
    }
  }
  Some(hex)
}

///|
/// Whether `candidate` is a strictly newer semantic version than `than`:
/// numeric `major.minor.patch` compare, tolerant of a leading `v` and a
/// trailing pre-release or build suffix (which is otherwise ignored).
/// Malformed versions are never newer.
fn is_newer(candidate : String, than~ : String) -> Bool {
  guard parse_version(candidate) is Some(candidate) else { return false }
  guard parse_version(than) is Some(current) else { return false }
  candidate > current
}

///|
/// The numeric `(major, minor, patch)` of a version string, or None when it
/// does not look like semver.
fn parse_version(text : String) -> (Int, Int, Int)? {
  let mut view = text.trim()
  if view.strip_prefix("v") is Some(rest) {
    view = rest
  }
  // `1.2.3-beta.1+build` compares by its numeric triple.
  for stop in ["-", "+"] {
    if view.find(stop) is Some(index) {
      view = view[:index]
    }
  }
  let parts = view.split(".").collect()
  guard parts.length() == 3 else { return None }
  let numbers = []
  for part in parts {
    let number = @string.parse_int(part) catch { _ => return None }
    guard number >= 0 else { return None }
    numbers.push(number)
  }
  Some((numbers[0], numbers[1], numbers[2]))
}
