// The relay console's app downloads, read from the relay's published
// desktop manifest. The sign-in page lists them inline; the sidebar opens
// the same list in a dialog.

///|
/// `Unavailable` covers a deployment without a manifest as well as a failed
/// or malformed fetch: either way the list points at the GitHub releases.
#derive(Eq)
pub enum Model {
  // No fetch has been started.
  Idle
  Loading
  Ready(version~ : String, page_url~ : String, targets~ : Array[Target])
  Unavailable
}

///|
pub extend Model with Eq::{equal, not_equal}

///|
/// One downloadable artifact, labeled for display.
#derive(Eq)
pub struct Target {
  label : String
  url : String
}

///|
pub extend Target with Eq::{equal, not_equal}

///|
/// The reply to the `fetch` command the caller passes to `load` and `open`:
/// a GET of `ManifestPath`.
pub(all) enum Msg {
  Fetched(status~ : Int32, body~ : String)
  FetchFailed
}

///|
pub const ManifestPath : String = "/desktop/releases/latest.json"

///|
const DialogId : String = "download-dialog"

///|
const FallbackReleasesUrl : String = "https://github.com/moonbitlang/openseek/releases/latest"

///|
pub fn Model::Model() -> Model {
  Idle
}

///|
pub fn Model::load(fetch : @cmd.Cmd) -> (@cmd.Cmd, Model) {
  (fetch, Loading)
}

///|
/// The dialog reuses a loaded or loading manifest and retries one that never
/// loaded or could not be read, so at most one fetch is ever in flight.
pub fn Model::open(self : Model, fetch : @cmd.Cmd) -> (@cmd.Cmd, Model) {
  match self {
    Ready(..) | Loading => (@dialog.show(DialogId), self)
    Idle | Unavailable => (@cmd.batch([@dialog.show(DialogId), fetch]), Loading)
  }
}

///|
pub fn Model::update(msg : Msg) -> Model {
  match msg {
    Fetched(status=200, body~) => parse_manifest(body)
    Fetched(..) | FetchFailed => Unavailable
  }
}

///|
/// The platforms a person can install, in display order.
let platforms : Array[(String, String)] = [
  ("macos-arm64", "macOS · Apple Silicon"),
  ("macos-x64", "macOS · Intel"),
  ("windows-x64", "Windows · x64"),
  ("windows-arm64", "Windows · ARM64"),
  ("linux-x64", "Linux · x64"),
  ("linux-arm64", "Linux · ARM64"),
  ("android", "Android · APK"),
]

///|
fn entry_url(entry : Json?) -> String? {
  guard entry is Some(Object(fields)) && fields.get("url") is Some(String(url)) else {
    return None
  }
  Some(url)
}

///|
fn parse_manifest(body : String) -> Model {
  guard (@json.parse(body) catch { _ => return Unavailable }) is Object(fields) &&
    fields.get("version") is Some(String(version)) &&
    fields.get("url") is Some(String(page_url)) &&
    fields.get("platforms") is Some(Object(entries)) else {
    return Unavailable
  }
  let targets : Array[Target] = []
  for platform in platforms {
    let (key, label) = platform
    // macOS publishes its updater archive under the bare key and the
    // installer a person downloads under `<key>-dmg`.
    match (entry_url(entries.get("\{key}-dmg")), entry_url(entries.get(key))) {
      (Some(url), _) | (None, Some(url)) => targets.push({ label, url, })
      (None, None) => ()
    }
  }
  Ready(version~, page_url~, targets~)
}
