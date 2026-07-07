// Checking the hosted release manifest for a newer desktop build. The check
// is a nudge, not a feature the app depends on: fetch failures — offline,
// HTTP error — read as "no update". But a manifest the server actually
// served and that cannot be used is loud: it raises `ManifestError` so the
// caller reports it rather than reading a broken release as "no update".

///|
/// The hosted release manifest, served by openseek-api from its releases
/// directory. Same origin as the default chat endpoint, so the check works
/// wherever the app itself does.
const ManifestUrl : String = "https://openseek-api.moonbitlang.cn/desktop/releases/latest.json"

///|
/// The staging deployment's manifest, for exercising a release before it
/// goes live — a Settings choice, not a build variant.
const StagingManifestUrl : String = "https://openseek-api-staging.moonbitlang.cn/desktop/releases/latest.json"

///|
/// Which release stream to check against. A user-facing Settings choice;
/// Production is the default and the only sensible pick outside of
/// pre-release testing.
pub(all) enum UpdateChannel {
  Production
  Staging
} derive(Eq, Debug)

///|
/// The manifest endpoint the channel names. Nothing else can redirect the
/// check — the old OPENSEEK_UPDATE_MANIFEST_URL environment override is
/// gone, because an exported variable silently outranking a visible
/// Settings choice is exactly how a "Production" check ends up answering
/// from staging.
fn manifest_url(channel : UpdateChannel) -> String {
  match channel {
    Production => ManifestUrl
    Staging => StagingManifestUrl
  }
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
/// A manifest the server actually served (HTTP 200) but that cannot be
/// used, split by how sure we are it is the publisher's fault.
/// `MalformedManifest` — not JSON, no version, version not semver — also
/// happens under captive portals and intercepting proxies, so it is worth
/// a log line but not a user-facing announcement. `MalformedArtifact` — a
/// well-formed manifest whose entry for this platform cannot be used — can
/// only come from the publisher, unlike the absence of an entry (the
/// normal shape for platforms that do not self-update); it carries the
/// release version so the caller can announce the update alongside the
/// reason.
pub suberror ManifestError {
  MalformedManifest(reason~ : String)
  MalformedArtifact(version~ : String, reason~ : String)
}

///|
/// The update server could not be asked at all: offline, DNS, TLS, or a
/// non-200 answer. Routine — the caller decides whether the user was asking
/// (report it) or the app was (stay quiet).
pub suberror Unreachable {
  Unreachable(reason~ : String)
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
/// Fetch the channel's manifest and report a release newer than `current`;
/// None means the check succeeded and there is nothing newer. Every failure
/// is typed rather than swallowed: `Unreachable` when the server could not
/// answer, `ManifestError` when it answered with something unusable — the
/// caller chooses what each is worth showing.
pub async fn check_for_update(
  current~ : String,
  channel~ : UpdateChannel,
) -> UpdateInfo? {
  let (response, data) = @http.get(manifest_url(channel)) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise Unreachable(reason="\{error}")
  }
  guard response.code == 200 else {
    raise Unreachable(reason="the update server answered HTTP \{response.code}")
  }
  let json = data.json() catch {
    error if @async.is_being_cancelled() => raise error
    _ => raise MalformedManifest(reason="the manifest is not valid JSON")
  }
  newer_update(json, current~, platform_key=manifest_platform_key())
}

///|
/// Whether this installation can swap a downloaded bundle in by itself:
/// it must be a real .app bundle signed by a Developer ID team — the same
/// requirement `stage_update` enforces, checked here so a "can I install"
/// answer never turns into a download that was doomed from the start.
pub async fn can_self_update(bundle_path~ : String) -> Bool {
  team_identifier(bundle_path) is Some(_)
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
) -> UpdateInfo? raise ManifestError {
  guard json is { "version": String(version), .. } else {
    raise MalformedManifest(reason="the manifest carries no version")
  }
  guard parse_version(version) is Some(_) else {
    raise MalformedManifest(
      reason="the manifest version is not semver: \{version}",
    )
  }
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
) -> PackageInfo? raise ManifestError {
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
