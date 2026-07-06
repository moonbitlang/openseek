// Checking the hosted release manifest for a newer desktop build. The check
// is a nudge, not a feature the app depends on: every failure — offline,
// HTTP error, malformed manifest, unparsable versions — reads as "no
// update".

///|
/// The hosted release manifest, served by openseek-api from its releases
/// directory. Same origin as the default chat endpoint, so the check works
/// wherever the app itself does.
const ManifestUrl : String = "https://openseek-api.moonbitlang.cn/desktop/releases/latest.json"

///|
/// A newer hosted release: the version to announce, the download page to
/// open as the fallback action, and — when the manifest carries one for
/// this platform — the package the app can install by itself.
pub struct UpdateInfo {
  version : String
  url : String
  artifact : PackageInfo?
} derive(Eq, Debug)

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
/// None — including on any failure, so the nudge can never surface as an
/// app error.
pub async fn check_for_update(current~ : String) -> UpdateInfo? {
  let (response, data) = @http.get(ManifestUrl) catch {
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
/// version and a web download page. Pure, so tests can cover the manifest
/// contract without a server.
fn newer_update(
  json : Json,
  current~ : String,
  platform_key~ : String?,
) -> UpdateInfo? {
  guard json is { "version": String(version), "url": String(url), .. } else {
    return None
  }
  // The URL is opened in the user's browser; anything but a web link
  // (file:, custom schemes) has no business in a manifest.
  guard url.has_prefix("https://") else { return None }
  if is_newer(version, than=current) {
    Some({ version, url, artifact: manifest_artifact(json, platform_key) })
  } else {
    None
  }
}

///|
/// The manifest's package entry for this platform, if it is well-formed: a
/// web URL plus a plausible sha256 (optionally `sha256:`-prefixed). A
/// malformed entry reads as "no package" — the page URL still works.
fn manifest_artifact(json : Json, platform_key : String?) -> PackageInfo? {
  guard platform_key is Some(key) else { return None }
  guard json is { "platforms": Object(platforms), .. } else { return None }
  guard platforms.get(key)
    is Some({ "url": String(url), "sha256": String(sha256), .. }) else {
    return None
  }
  guard url.has_prefix("https://") else { return None }
  guard normalized_sha256(sha256) is Some(sha256) else { return None }
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
