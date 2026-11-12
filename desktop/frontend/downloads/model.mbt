// The relay console's app downloads, read from the relay's published
// desktop manifest. The sign-in page lists them inline; the sidebar opens
// the same list in a dialog.

///|
/// Each fetch advances the generation, so a reply from an earlier fetch
/// cannot replace the current one.
#derive(Eq)
pub struct Model {
  generation : Int32
  release : Release
}

///|
pub extend Model with Eq::{equal, not_equal}

///|
/// `Unavailable` covers a deployment without a manifest as well as a failed
/// or malformed fetch: either way the list points at the GitHub releases.
#derive(Eq, Debug)
pub enum Release {
  // No fetch has been started.
  Idle
  Loading
  Ready(version~ : String, page_url~ : String, targets~ : Array[Target])
  Unavailable
}

///|
pub extend Release with Eq::{equal, not_equal}

///|
pub extend Release with @debug.Debug::{to_repr}

///|
/// One downloadable artifact, labeled for display.
#derive(Eq, Debug)
pub struct Target {
  label : String
  url : String
}

///|
pub extend Target with Eq::{equal, not_equal}

///|
pub extend Target with @debug.Debug::{to_repr}

///|
pub(all) enum Msg {
  Fetched(generation~ : Int32, status~ : Int32, body~ : String)
  FetchFailed(generation~ : Int32)
}

///|
const DialogId : String = "download-dialog"

///|
const ManifestPath : String = "/desktop/releases/latest.json"

///|
const FallbackReleasesUrl : String = "https://github.com/moonbitlang/openseek/releases/latest"

///|
pub fn Model::Model() -> Model {
  { generation: 0, release: Idle, }
}

///|
pub fn Model::load(self : Model, emit : @cmd.Emit[Msg]) -> (@cmd.Cmd, Model) {
  let generation = self.generation + 1
  (fetch_manifest(emit, generation), { generation, release: Loading, })
}

///|
/// The dialog reuses a loaded or loading manifest and retries one that never
/// loaded or could not be read.
pub fn Model::open(self : Model, emit : @cmd.Emit[Msg]) -> (@cmd.Cmd, Model) {
  match self.release {
    Ready(..) | Loading => (@dialog.show(DialogId), self)
    Idle | Unavailable => {
      let (fetch, model) = self.load(emit)
      (@cmd.batch([@dialog.show(DialogId), fetch]), model)
    }
  }
}

///|
pub fn Model::update(self : Model, msg : Msg) -> Model {
  let generation = match msg {
    Fetched(generation~, ..) | FetchFailed(generation~) => generation
  }
  guard generation == self.generation else { return self }
  match msg {
    Fetched(status=200, body~, ..) => { ..self, release: parse_manifest(body), }
    Fetched(..) | FetchFailed(..) => { ..self, release: Unavailable, }
  }
}

///|
fn fetch_manifest(emit : @cmd.Emit[Msg], generation : Int32) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let base : String = @js.Value::cast_from(@dom.document()).get_with_string(
        "baseURI",
      )
      guard @base_browser.resolve_url(ManifestPath, base~) is Ok((url, _)) else {
        scheduler.add(emit(FetchFailed(generation~)))
        return
      }
      let (response, body) = @http.get(url) catch {
        _ => {
          scheduler.add(emit(FetchFailed(generation~)))
          return
        }
      }
      let body = @utf8.decode_lossy(body.binary(), ignore_bom=true)
      scheduler.add(emit(Fetched(generation~, status=response.code, body~)))
    })
    |> ignore
  })
}

///|
/// The canonical platform order; unknown keys keep the manifest's own order
/// after these.
let known_platforms : Array[String] = [
  "macos-arm64", "macos-x64", "windows-x64", "windows-arm64", "linux-x64", "linux-arm64",
  "android",
]

///|
fn platform_label(key : String) -> String {
  match key {
    "macos-arm64" => "macOS · Apple Silicon"
    "macos-x64" => "macOS · Intel"
    "windows-x64" => "Windows · x64"
    "windows-arm64" => "Windows · ARM64"
    "linux-x64" => "Linux · x64"
    "linux-arm64" => "Linux · ARM64"
    "android" => "Android · APK"
    _ => key
  }
}

///|
fn entry_url(entry : Json?) -> String? {
  guard entry is Some(Object(fields)) && fields.get("url") is Some(String(url)) else {
    return None
  }
  Some(url)
}

///|
fn parse_manifest(body : String) -> Release {
  guard (@json.parse(body) catch { _ => return Unavailable }) is Object(fields) &&
    fields.get("version") is Some(String(version)) &&
    fields.get("platforms") is Some(Object(platforms)) else {
    return Unavailable
  }
  let page_url = if fields.get("url") is Some(String(url)) {
    url
  } else {
    FallbackReleasesUrl
  }
  let targets : Array[Target] = []
  // A platform's `<key>-dmg` entry is its manual installer, which is what a
  // person should download; the bare key is the updater archive.
  let push_platform = (key : String) => {
    let url = if entry_url(platforms.get("\{key}-dmg")) is Some(url) {
      Some(url)
    } else {
      entry_url(platforms.get(key))
    }
    if url is Some(url) {
      targets.push({ label: platform_label(key), url, })
    }
  }
  for key in known_platforms {
    push_platform(key)
  }
  for key, _ in platforms {
    // `browser` is the relay console's own archive, not an app to install.
    if !known_platforms.contains(key) &&
      key != "browser" &&
      !key.has_suffix("-dmg") {
      push_platform(key)
    }
  }
  Ready(version~, page_url~, targets~)
}
