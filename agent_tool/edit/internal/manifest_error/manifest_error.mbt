///|
/// Guard rail for writes to MoonBit manifests: returns the error to feed back
/// to the model when writing `content` to `path` would produce a known-bad
/// manifest, or `None` when the write may proceed.
///
/// Models trained on older MoonBit emit legacy shapes — `moon.mod.json`
/// files, JSON syntax inside `moon.mod`/`moon.pkg` — that the toolchain no
/// longer accepts. Rejecting the write with a corrective message at the tool
/// boundary fixes the mistake in one round trip, instead of letting a broken
/// manifest fail every later build step.
pub async fn write_error(path : String, content : String) -> String? {
  let trimmed = content.trim().to_owned()
  if is_moon_mod_json_path(path) && !@fs.exists(path) {
    return Some(
      "moon.mod.json is legacy; create moon.mod for new MoonBit projects",
    )
  }
  if is_moon_mod_path(path) {
    if trimmed == "" {
      return Some("moon.mod must not be empty")
    }
    if trimmed.has_prefix("{") || trimmed.contains("\"name\"") {
      return Some("moon.mod uses current text syntax, not JSON")
    }
    if !trimmed.contains("name =") {
      return Some("moon.mod should include a module `name = ...` entry")
    }
  }
  if is_moon_pkg_path(path) {
    if trimmed.length() < 8 {
      return Some("moon.pkg content is suspiciously small")
    }
    if trimmed.has_prefix("{") {
      return Some("moon.pkg uses current text syntax, not JSON")
    }
  }
  None
}

///|
fn is_moon_mod_path(path : String) -> Bool {
  path == "moon.mod" || path.has_suffix("/moon.mod")
}

///|
fn is_moon_mod_json_path(path : String) -> Bool {
  path == "moon.mod.json" || path.has_suffix("/moon.mod.json")
}

///|
fn is_moon_pkg_path(path : String) -> Bool {
  path == "moon.pkg" || path.has_suffix("/moon.pkg")
}
