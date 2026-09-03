///|
/// Maps common source extensions to the language ids used by tokenizer and
/// feature registries.
pub fn infer_language_id(path_or_name : String) -> String {
  if is_moon_config_path(path_or_name) {
    "moonbit-config"
  } else if path_or_name.has_suffix(".mbt") ||
    path_or_name.has_suffix(".mbt.md") ||
    path_or_name.has_suffix(".mbtx") {
    "moonbit"
  } else if path_or_name.has_suffix(".js") || path_or_name.has_suffix(".mjs") {
    "javascript"
  } else if path_or_name.has_suffix(".ts") {
    "typescript"
  } else if path_or_name.has_suffix(".json") {
    "json"
  } else if path_or_name.has_suffix(".md") {
    "markdown"
  } else if path_or_name.has_suffix(".css") {
    "css"
  } else if path_or_name.has_suffix(".html") {
    "html"
  } else if path_or_name.has_suffix(".txt") {
    "plaintext"
  } else {
    "moonbit"
  }
}

///|
/// Exact current MoonBit manifest basenames, accepting either path separator.
fn is_moon_config_path(path_or_name : String) -> Bool {
  path_or_name == "moon.pkg" ||
  path_or_name == "moon.mod" ||
  path_or_name.has_suffix("/moon.pkg") ||
  path_or_name.has_suffix("/moon.mod") ||
  path_or_name.has_suffix("\\moon.pkg") ||
  path_or_name.has_suffix("\\moon.mod")
}

///|
fn contains_null(value : String) -> Bool {
  for unit in value.code_units() {
    if unit == 0 {
      return true
    }
  }
  false
}

///|
fn is_windows_drive_path(path : String) -> Bool {
  path.length() >= 2 &&
  is_ascii_alpha(path[0].to_int()) &&
  path[1].to_int() == 58
}

///|
fn is_ascii_alpha(unit : Int) -> Bool {
  (65 <= unit && unit <= 90) || (97 <= unit && unit <= 122)
}
