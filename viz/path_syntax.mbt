///|
/// The highlighter for a file body by its path's extension, mirroring the
/// desktop transcript's policy for `write` bodies; `None` (no path, or an
/// extension without a tokenizer) leaves the body as plain text.
fn path_tokenizer(path : String?) -> &@syntax.LineTokenizer? {
  guard path is Some(path) else { return None }
  guard path.replace(old="\\", new="/").split("/").last() is Some(basename) else {
    return None
  }
  let name = basename.to_owned().to_lower()
  let tokenizer : &@syntax.LineTokenizer = if name == "moon.pkg" ||
    name == "moon.mod" {
    (@lang_moon_config.MoonConfigTokenizer() : &@syntax.LineTokenizer)
  } else if name.has_suffix(".mbt") ||
    name.has_suffix(".mbtx") ||
    name.has_suffix(".mbti") ||
    name.has_suffix(".mbt.md") {
    (@lang_moonbit.MoonBitTokenizer() : &@syntax.LineTokenizer)
  } else if name.has_suffix(".js") ||
    name.has_suffix(".mjs") ||
    name.has_suffix(".cjs") {
    (@lang_javascript.JavascriptTokenizer() : &@syntax.LineTokenizer)
  } else if name.has_suffix(".json") || name.has_suffix(".jsonl") {
    (@lang_json.JsonTokenizer() : &@syntax.LineTokenizer)
  } else {
    return None
  }
  Some(tokenizer)
}
