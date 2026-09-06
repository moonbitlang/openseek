// Checking the hosted release manifest for a newer desktop build. The check
// is a nudge, not a feature the app depends on: fetch failures — offline,
// HTTP error — read as "no update". But a manifest the server actually
// served and that cannot be used is loud: it raises `ManifestError` so the
// caller reports it rather than reading a broken release as "no update".

///|
/// The one manifest the app ever checks, served by the SeekMoon relay
/// origin from its releases directory. There is no other stream and no
/// override: the staging channel went with the Settings server selector
/// (nothing could reach it anymore), and the old
/// OPENSEEK_UPDATE_MANIFEST_URL environment variable is gone because an
/// exported variable silently redirecting the check is exactly how a
/// production install ends up answering from somewhere else.
const ManifestUrl : String = "https://openseek-api.moonbitlang.cn/desktop/releases/latest.json"

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
/// Fetch the manifest and report a release newer than `current`; None means
/// the check succeeded and there is nothing newer. Every failure is typed
/// rather than swallowed: `Unreachable` when the server could not answer,
/// `ManifestError` when it answered with something unusable — the caller
/// chooses what each is worth showing.
pub async fn check_for_update(current~ : String) -> UpdateInfo? {
  let (response, data) = @http.get(ManifestUrl) catch {
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
/// The actionable explanation shared by the capability check and the final
/// apply-time check when the running bundle's directory cannot be changed.
const BundleReplacementFailureMessage : String = "OpenSeek cannot replace the app in its current location. Move SeekMoon.app to Applications, reopen it, and try again."

///|
/// Why `bundle_path` cannot be renamed within its current directory. Rename
/// permission belongs to the parent directory, not to the bundle itself; both
/// write and search access are required. A read-only filesystem reports an
/// error rather than `false`, so every non-cancellation failure has the same
/// concise, actionable user-facing answer.
async fn bundle_replacement_failure(bundle_path : String) -> String? {
  let parent = @pathx.Path(bundle_path).dirname().to_string()
  let replaceable = (@fs.can_write(parent) && @fs.can_execute(parent)) catch {
    error if @async.is_being_cancelled() => raise error
    _ => false
  }
  if replaceable {
    None
  } else {
    Some(BundleReplacementFailureMessage)
  }
}

///|
/// Why this installation cannot swap a downloaded bundle in by itself, or
/// None when it can: it must be a real .app bundle signed by a Developer ID
/// team and its containing directory must permit replacement. This is a UI
/// preflight only; `apply_staged` checks the directory again immediately
/// before touching the running bundle.
pub async fn self_update_unavailable_reason(bundle_path~ : String) -> String? {
  if team_identifier(bundle_path) is Some(_) {
    bundle_replacement_failure(bundle_path)
  } else {
    Some(
      "Update is not available because current application is not signed with Developer ID",
    )
  }
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
    Some({ version, artifact: manifest_artifact(json, platform_key, version~), })
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
  Some({ url, sha256, })
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
  guard hex.iter().all(ch => ch is ('0'..='9' | 'a'..='f')) else { return None }
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
  let parts = [..view.split(".")]
  guard parts.length() == 3 else { return None }
  let numbers = []
  for part in parts {
    let number = @string.parse_int(part) catch { _ => return None }
    guard number >= 0 else { return None }
    numbers.push(number)
  }
  Some((numbers[0], numbers[1], numbers[2]))
}

///|
test "version comparison is numeric per component" {
  assert_true(is_newer("0.2.0", than="0.1.0"))
  assert_true(is_newer("0.1.10", than="0.1.9"))
  assert_true(is_newer("1.0.0", than="0.9.9"))
  assert_false(is_newer("0.1.0", than="0.1.0"))
  assert_false(is_newer("0.1.0", than="0.2.0"))
}

///|
test "version comparison tolerates v prefixes and suffixes" {
  assert_true(is_newer("v0.2.0", than="0.1.0"))
  assert_true(is_newer("0.2.0-beta.1+build5", than="v0.1.0"))
  assert_false(is_newer("0.1.0-hotfix", than="0.1.0"))
}

///|
test "malformed versions are never newer" {
  assert_false(is_newer("latest", than="0.1.0"))
  assert_false(is_newer("0.2", than="0.1.0"))
  assert_false(is_newer("0.2.0", than="unknown"))
  assert_false(is_newer("0.2.x", than="0.1.0"))
}

///|
test "manifest decode demands a strictly newer version" {
  let manifest : Json = {
    "version": "0.2.0",
    "url": "https://github.com/moonbitlang/openseek/releases",
  }
  @debug.assert_eq(
    newer_update(manifest, current="0.1.0", platform_key=None),
    Some({ version: "0.2.0", artifact: None, }),
  )
  @debug.assert_eq(
    newer_update(manifest, current="0.2.0", platform_key=None),
    None,
  )
  // The legacy top-level page url is ignored, present or not.
  let missing_url : Json = { "version": "0.2.0" }
  @debug.assert_eq(
    newer_update(missing_url, current="0.1.0", platform_key=None),
    Some({ version: "0.2.0", artifact: None, }),
  )
}

///|
fn expect_manifest_error(manifest : Json, reason~ : String) -> Unit raise {
  try newer_update(manifest, current="0.1.0", platform_key=None) catch {
    MalformedManifest(reason=actual) => assert_eq(actual, reason)
    _ => fail("unexpected manifest-error constructor")
  } noraise {
    _ => fail("expected a malformed-manifest raise")
  }
}

///|
test "a served manifest that cannot be decoded raises" {
  expect_manifest_error("nonsense", reason="the manifest carries no version")
  expect_manifest_error(
    { "version": 2 },
    reason="the manifest carries no version",
  )
  expect_manifest_error(
    { "version": "latest" },
    reason="the manifest version is not semver: latest",
  )
}

///|
const TestSha : String = "a3f8b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9"

///|
test "a well-formed platforms entry becomes the artifact" {
  let manifest : Json = {
    "version": "0.2.0",
    "url": "https://example.com/releases",
    "platforms": {
      "macos-arm64": {
        "url": "https://example.com/OpenSeek-0.2.0-macos-arm64.zip",
        "sha256": TestSha,
      },
    },
  }
  @debug.assert_eq(
    newer_update(manifest, current="0.1.0", platform_key=Some("macos-arm64")),
    Some({
      version: "0.2.0",
      artifact: Some({
        url: "https://example.com/OpenSeek-0.2.0-macos-arm64.zip",
        sha256: TestSha,
      }),
    }),
  )
  // Another platform's key, or no key at all, is the normal package-less
  // shape, not an error.
  @debug.assert_eq(
    newer_update(manifest, current="0.1.0", platform_key=Some("windows-x64")).unwrap().artifact,
    None,
  )
  @debug.assert_eq(
    newer_update(manifest, current="0.1.0", platform_key=None).unwrap().artifact,
    None,
  )
}

///|
fn expect_malformed(manifest : Json, reason~ : String) -> Unit raise {
  try
    newer_update(manifest, current="0.1.0", platform_key=Some("macos-arm64"))
  catch {
    MalformedArtifact(version~, reason=actual) => {
      assert_eq(version, "0.2.0")
      assert_eq(actual, reason)
    }
    _ => fail("unexpected manifest-error constructor")
  } noraise {
    _ => fail("expected a malformed-artifact raise")
  }
}

///|
test "a malformed platforms entry raises with what is wrong" {
  expect_malformed(
    {
      "version": "0.2.0",
      "url": "https://example.com/releases",
      "platforms": {
        "macos-arm64": { "url": "https://example.com/a.zip", "sha256": "short" },
      },
    },
    reason="the package sha256 is not a hex digest",
  )
  // A schemeless or non-https url — a misconfigured releases base url on
  // the server — must surface, not read as "no package".
  expect_malformed(
    {
      "version": "0.2.0",
      "url": "https://example.com/releases",
      "platforms": {
        "macos-arm64": { "url": "example.com/a.zip", "sha256": TestSha },
      },
    },
    reason="the package url is not https: example.com/a.zip",
  )
  expect_malformed(
    {
      "version": "0.2.0",
      "platforms": { "macos-arm64": { "note": "coming soon" } },
    },
    reason="the platform entry lacks url/sha256",
  )
}

///|
test "manifest digests normalize to bare lowercase hex" {
  @debug.assert_eq(
    normalized_sha256("sha256:\{TestSha.to_upper()}"),
    Some(TestSha),
  )
  @debug.assert_eq(normalized_sha256(TestSha), Some(TestSha))
  @debug.assert_eq(normalized_sha256("zz\{TestSha}"), None)
  @debug.assert_eq(normalized_sha256("deadbeef"), None)
}

///|
pub extend PackageInfo with Debug::{to_repr}

///|
pub extend PackageInfo with Eq::{equal, not_equal}

///|
pub extend UpdateInfo with Debug::{to_repr}

///|
pub extend UpdateInfo with Eq::{equal, not_equal}
