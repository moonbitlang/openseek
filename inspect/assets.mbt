///|
/// Where one viewer asset is served from: a file on disk, the copy built into
/// this binary (`generated_assets.mbt`), or nowhere.
priv enum AssetSource {
  File(String)
  Embedded(String)
  Missing
}

///|
/// The viewer shell: the first existing disk candidate, else the embedded copy.
async fn resolve_shell(candidates : Array[String]) -> AssetSource {
  match first_existing(candidates) {
    Some(path) => File(path)
    None => embedded_or_missing(embedded_index_html)
  }
}

///|
/// The frontend bundle: the disk candidate `locate_bundle` picks, else the
/// embedded copy.
async fn resolve_bundle(candidates : Array[String]) -> AssetSource {
  match locate_bundle(candidates) {
    Some(path) => File(path)
    None => embedded_or_missing(embedded_viz_app_js)
  }
}

///|
fn embedded_or_missing(content : String) -> AssetSource {
  if content == "" {
    Missing
  } else {
    Embedded(content)
  }
}

///|
/// The asset's text, or `None` when it is missing.
async fn AssetSource::text(self : AssetSource) -> String? {
  match self {
    File(path) => Some(read_text_lossy(path))
    Embedded(content) => Some(content)
    Missing => None
  }
}

///|
/// For the startup log: where the asset is being served from.
fn AssetSource::describe(self : AssetSource) -> String {
  match self {
    File(path) => "'\{path}'"
    Embedded(_) => "the copy built into this binary"
    Missing => "nowhere (not found)"
  }
}

///|
test "an empty embedded asset counts as missing" {
  assert_true(embedded_or_missing("") is Missing)
  assert_true(embedded_or_missing("<html>") is Embedded("<html>"))
}
