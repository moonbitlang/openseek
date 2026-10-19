///|
/// Path classification for MoonBit manifests and generated interfaces, shared
/// by the write and edit tools so both agree on what counts as a `moon.mod` /
/// `moon.pkg` / `*.generated.mbti` path. Backslashes are normalized to `/` so a
/// Windows path classifies the same as its POSIX form.
fn normalized(path : String) -> String {
  path.replace_all(old="\\", new="/")
}

///|
/// Whether `path` names `name`: either the whole path or its last component.
/// Backslashes count as separators, so a Windows path classifies like its POSIX
/// form.
fn is_named_file(path : String, name : String) -> Bool {
  let path = normalized(path)
  path == name || path.has_suffix("/\{name}")
}

///|
/// Whether `path` is a `moon.mod` module manifest (the non-JSON form).
pub fn is_moon_mod_path(path : String) -> Bool {
  is_named_file(path, "moon.mod")
}

///|
/// Whether `path` is a `moon.mod.json` module manifest.
pub fn is_moon_mod_json_path(path : String) -> Bool {
  is_named_file(path, "moon.mod.json")
}

///|
/// Whether `path` is a `moon.pkg` package manifest (the non-JSON form).
pub fn is_moon_pkg_path(path : String) -> Bool {
  is_named_file(path, "moon.pkg")
}

///|
/// Whether `path` is a generated interface file (`*.generated.mbti`).
pub fn is_generated_mbti_path(path : String) -> Bool {
  normalized(path).has_suffix(".generated.mbti")
}
