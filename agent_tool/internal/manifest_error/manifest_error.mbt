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
  if path_error(path) is Some(error) {
    return Some(error)
  }
  let check_module = @manifest_path.is_moon_mod_path(path)
  guard check_module || @manifest_path.is_moon_pkg_path(path) else {
    return None
  }
  let trimmed = content.trim()
  content_error(
    path,
    trimmed.iter().next(),
    check_module && trimmed.contains("\"name\""),
    check_module && trimmed.contains("name ="),
  )
}

///|
/// Rules that can reject a destination before its contents are read.
pub async fn path_error(path : String) -> String? {
  if @manifest_path.is_generated_mbti_path(path) {
    return Some(
      "*.generated.mbti files are generated; run moon info instead of editing them",
    )
  }
  if @manifest_path.is_moon_mod_json_path(path) && !@fs.exists(path) {
    return Some(
      "moon.mod.json is legacy; create moon.mod for new MoonBit projects",
    )
  }
  None
}

///|
fn content_error(
  path : String,
  first : Char?,
  has_json_name : Bool,
  has_module_name : Bool,
) -> String? {
  if @manifest_path.is_moon_mod_path(path) {
    if first is None {
      return Some("moon.mod must not be empty")
    }
    if first == Some('{') || has_json_name {
      return Some("moon.mod uses current text syntax, not JSON")
    }
    if !has_module_name {
      return Some("moon.mod should include a module `name = ...` entry")
    }
  }
  if @manifest_path.is_moon_pkg_path(path) {
    // Tiny moon.pkg files are normal for dummy packages; keep guarding syntax
    // shapes that are known agent mistakes.
    if first == Some('#') {
      return Some("moon.pkg use // for comment syntax, not #")
    }
    if first == Some('{') {
      return Some("moon.pkg uses current text syntax, not JSON")
    }
  }
  None
}

///|
/// Validate UTF-8 and collect only the text facts used by the manifest rules.
/// The reader handles UTF-8 code points split across chunks.
pub async fn file_error(paths : Array[String], source : String) -> String? {
  let file = @fs.open(source, mode=ReadOnly)
  defer file.close()
  let check_module = paths.any(@manifest_path.is_moon_mod_path)
  let check_rules = check_module || paths.any(@manifest_path.is_moon_pkg_path)
  let mut first : Char? = None
  let mut has_json_name = false
  let mut has_module_name = false
  let mut suffix = ""
  try {
    while file.text.read() is Some(chunk) {
      if check_rules && first is None {
        first = chunk.trim().iter().next()
      }
      if check_module {
        let text = suffix + chunk
        has_json_name = has_json_name || text.contains("\"name\"")
        has_module_name = has_module_name || text.contains("name =")
        // Both tokens have six characters, so retain five across reads.
        suffix = text[(text.length() - 5).max(0):].to_owned()
      }
    }
  } catch {
    MalformedText =>
      return Some("source and manifest content must be valid UTF-8")
    error => raise error
  }
  for path in paths {
    if content_error(path, first, has_json_name, has_module_name) is Some(error) {
      return Some(error)
    }
  }
  None
}
