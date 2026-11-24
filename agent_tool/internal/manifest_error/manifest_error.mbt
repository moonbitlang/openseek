///|
/// Guard rail for writes to MoonBit manifests: returns the error to feed back
/// to the model for known errors in current manifests or generated interfaces.
pub fn write_error(path : String, content : String) -> String? {
  let trimmed = content.trim()
  if @manifest_path.is_generated_mbti_path(path) {
    return Some(
      "*.generated.mbti files are generated; run moon info instead of editing them",
    )
  }
  if @manifest_path.is_moon_mod_path(path) {
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
  if @manifest_path.is_moon_pkg_path(path) {
    // Tiny moon.pkg files are normal for dummy packages; keep guarding syntax
    // shapes that are known agent mistakes.
    if trimmed.has_prefix("#") {
      return Some("moon.pkg use // for comment syntax, not #")
    }
    if trimmed.has_prefix("{") {
      return Some("moon.pkg uses current text syntax, not JSON")
    }
  }
  None
}
