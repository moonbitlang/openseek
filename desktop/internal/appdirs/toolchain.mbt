///|
const BundledMoonbitRelativeDir : String = "toolchains/moonbit/windows-x64"

///|
const MoonbitBundleStampFile : String = ".openseek-moonbit-bundle-version"

///|
fn join_path(base : String, child : String) -> String {
  (base : @mbpath.Path).join(child).normalize().to_string()
}

///|
fn moonbit_payload_looks_complete(path : String) -> Bool {
  @mbfs.path_exists(join_path(path, "bin/moon.exe")) &&
  @mbfs.path_exists(join_path(path, "lib/core/moon.mod"))
}

///|
pub fn bundled_moonbit_payload_dir(engine_command : String) -> String? {
  let command_dir = (engine_command : @mbpath.Path).dirname().resolve()
  let path = command_dir.join(BundledMoonbitRelativeDir).normalize().to_string()
  if moonbit_payload_looks_complete(path) {
    Some(path)
  } else {
    None
  }
}

///|
pub fn moonbit_bin_dir(moon_home : String) -> String {
  join_path(moon_home, "bin")
}

///|
pub fn moonbit_bundle_stamp_path(moon_home : String) -> String {
  join_path(moon_home, MoonbitBundleStampFile)
}

///|
pub fn moonbit_native_bundle_probe_path(moon_home : String) -> String {
  join_path(
    moon_home, "lib/core/_build/native/release/bundle/prelude/prelude.mi",
  )
}

///|
pub fn moonbit_wasm_gc_bundle_probe_path(moon_home : String) -> String {
  join_path(
    moon_home, "lib/core/_build/wasm-gc/release/bundle/prelude/prelude.mi",
  )
}

///|
pub fn prepend_to_path_env(bin_dir : String, current_path : String?) -> String {
  match current_path {
    Some(path) if !path.is_empty() => bin_dir + ";" + path
    _ => bin_dir
  }
}
