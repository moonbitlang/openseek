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
/// A newer hosted release: the version to announce and the download page to
/// open when the announcement is clicked.
pub struct UpdateInfo {
  version : String
  url : String
} derive(Eq, Debug)

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
  newer_update(json, current~)
}

///|
/// Decode a manifest and keep it only when it names a strictly newer
/// version and a web download page. Pure, so tests can cover the manifest
/// contract without a server.
fn newer_update(json : Json, current~ : String) -> UpdateInfo? {
  guard json is { "version": String(version), "url": String(url), .. } else {
    return None
  }
  // The URL is opened in the user's browser; anything but a web link
  // (file:, custom schemes) has no business in a manifest.
  guard url.has_prefix("https://") else { return None }
  if is_newer(version, than=current) {
    Some({ version, url })
  } else {
    None
  }
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
