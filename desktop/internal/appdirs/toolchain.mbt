///|
const MoonbitBundleStampFile : String = ".openseek-moonbit-bundle-version"

///|
const MoonbitSeedVersionFile : String = ".openseek-moonbit-seed-version"

///|
fn join_path(base : String, child : String) -> String {
  @mbpath.Path(base).join(child).normalize().to_string()
}

///|
fn moonbit_toolchain_dir(base : @mbpath.Path, name : String) -> String {
  base.join("toolchains").join("moonbit").join(name).normalize().to_string()
}

///|
fn macos_resources_toolchain_dir(command_dir : @mbpath.Path) -> String {
  command_dir
  .join("..")
  .join("Resources")
  .join("toolchains")
  .join("moonbit")
  .join("macos-arm64")
  .normalize()
  .to_string()
}

///|
async fn executable_exists(root : String, name : String) -> Bool {
  @mbfs.exists(join_path(root, "bin/" + name)) ||
  @mbfs.exists(join_path(root, "bin/" + name + ".exe"))
}

///|
async fn moonbit_seed_looks_complete(path : String) -> Bool {
  executable_exists(path, "moon") &&
  executable_exists(path, "moonc") &&
  @mbfs.exists(join_path(path, "lib/core/moon.mod"))
}

///|
pub async fn bundled_moonbit_seed_dir(engine_command : String) -> String? {
  let command_dir = (engine_command : @mbpath.Path).dirname().resolve()
  let candidates = [
    moonbit_toolchain_dir(command_dir, "windows-x64"),
    moonbit_toolchain_dir(command_dir, "linux-x64"),
    moonbit_toolchain_dir(command_dir, "macos-arm64"),
    macos_resources_toolchain_dir(command_dir),
  ]
  for candidate in candidates {
    if moonbit_seed_looks_complete(candidate) {
      return Some(candidate)
    }
  }
  None
}

///|
pub async fn prepared_moonbit_payload_dir(seed_dir : String) -> String? {
  guard prepared_runtime_dir() is Some(runtime_dir) else { return None }
  let seed_name = (seed_dir : @mbpath.Path).basename().to_owned()
  if seed_name.is_empty() {
    return None
  }
  let root = join_path(runtime_dir, "toolchains/moonbit")
  @mbfs.mkdir(root, recursive=true) catch {
    _ => return None
  }
  Some(join_path(root, seed_name))
}

///|
pub fn moonbit_bin_dir(moon_home : String) -> String {
  join_path(moon_home, "bin")
}

///|
fn moonbit_executable_suffix() -> String {
  if @env.get("OS") is Some("Windows_NT") {
    ".exe"
  } else {
    ""
  }
}

///|
pub fn moonbit_command(moon_home : String) -> String {
  join_path(moon_home, "bin/moon" + moonbit_executable_suffix())
}

///|
pub fn moonbit_compiler_command(moon_home : String) -> String {
  join_path(moon_home, "bin/moonc" + moonbit_executable_suffix())
}

///|
pub fn moonbit_bundle_stamp_path(moon_home : String) -> String {
  join_path(moon_home, MoonbitBundleStampFile)
}

///|
pub fn moonbit_seed_version_path(seed_dir : String) -> String {
  join_path(seed_dir, MoonbitSeedVersionFile)
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
  let separator = if @env.get("OS") is Some("Windows_NT") { ";" } else { ":" }
  match current_path {
    Some(path) if !path.is_empty() => bin_dir + separator + path
    _ => bin_dir
  }
}
