///|
const DisableBundledMoonEnv : String = "OPENSEEK_DISABLE_BUNDLED_MOON"

///|
const OverrideMoonHomeEnv : String = "OPENSEEK_MOON_HOME"

///|
fn moonbit_process_env(moon_home : String) -> Map[String, String] {
  {
    "MOON_HOME": moon_home,
    "PATH": @appdirs.prepend_to_path_env(
      @appdirs.moonbit_bin_dir(moon_home),
      @env.get("PATH"),
    ),
  }
}

///|
async fn path_exists(path : String) -> Bool {
  @fs.exists(path) catch {
    _ => false
  }
}

///|
async fn read_text(path : String) -> String {
  @fs.read_file(path).text()
}

///|
async fn read_text_if_exists(path : String) -> String? {
  if path_exists(path) {
    Some(read_text(path))
  } else {
    None
  }
}

///|
async fn bundled_moonbit_seed_version(seed_dir : String) -> String? {
  guard read_text_if_exists(@appdirs.moonbit_seed_version_path(seed_dir))
    is Some(version) else {
    return None
  }
  let version = version.trim().to_owned()
  if version.is_empty() {
    None
  } else {
    Some(version)
  }
}

///|
async fn moonbit_compiler_version(moon_home : String) -> String {
  let moonc = @appdirs.moonbit_compiler_command(moon_home)
  let child_stdin = prepare_engine_stdin(moonc)
  let (code, output) = @process.collect_output_merged(
    moonc,
    ["-v"],
    inherit_env=true,
    extra_env=moonbit_process_env(moon_home),
    stdin=child_stdin,
  )
  if code != 0 {
    fail(
      "failed to read bundled MoonBit compiler version: " +
      output.text().trim().to_owned(),
    )
  }
  let compiler_version = output.text().trim().split(" ").collect()[0].to_owned()
  if compiler_version.has_prefix("v") {
    compiler_version[1:].to_owned()
  } else {
    compiler_version
  }
}

///|
async fn bundled_moonbit_ready(moon_home : String, version : String) -> Bool {
  guard read_text_if_exists(@appdirs.moonbit_bundle_stamp_path(moon_home))
    is Some(stamp) else {
    return false
  }
  if stamp != "version=\{version}" {
    return false
  }
  path_exists(@appdirs.moonbit_command(moon_home)) &&
  path_exists(@appdirs.moonbit_compiler_command(moon_home)) &&
  path_exists(@appdirs.moonbit_native_bundle_probe_path(moon_home)) &&
  path_exists(@appdirs.moonbit_wasm_gc_bundle_probe_path(moon_home))
}

///|
async fn run_moonbit_bundle(moon_home : String, args : Array[String]) -> Unit {
  let moon = @appdirs.moonbit_command(moon_home)
  let core_dir = moon_home + "/lib/core"
  let child_stdin = prepare_engine_stdin(moon)
  let (code, output) = @process.collect_output_merged(
    moon,
    args,
    inherit_env=true,
    extra_env=moonbit_process_env(moon_home),
    stdin=child_stdin,
    cwd=core_dir.view(),
  )
  if code != 0 {
    fail(
      "failed to initialize bundled MoonBit toolchain: " +
      output.text().trim().to_owned(),
    )
  }
}

///|
async fn remove_path_if_exists(path : String) -> Unit {
  if !path_exists(path) {
    return
  }
  if @fs.kind(path) is Directory {
    @fs.rmdir(path, recursive=true)
  } else {
    @fs.remove(path)
  }
}

///|
#cfg(platform="windows")
async fn copy_file(source : String, destination : String) -> Unit {
  @fs.write_file(
    destination,
    @fs.read_file(source),
    create_mode=CreateOrTruncate,
  )
}

///|
#cfg(platform="windows")
async fn copy_dir_recursive(source : String, destination : String) -> Unit {
  @fs.mkdir(destination, recursive=true)
  for entry in @fs.readdir(source, include_hidden=true) {
    let source_entry = source + "/" + entry
    let destination_entry = destination + "/" + entry
    if @fs.kind(source_entry) is Directory {
      copy_dir_recursive(source_entry, destination_entry)
    } else {
      copy_file(source_entry, destination_entry)
    }
  }
}

///|
#cfg(platform="windows")
async fn copy_moonbit_seed_dir(source : String, destination : String) -> Unit {
  copy_dir_recursive(source, destination)
}

///|
#cfg(not(platform="windows"))
async fn copy_moonbit_seed_dir(source : String, destination : String) -> Unit {
  let (code, output) = @process.collect_output_merged(
    "cp",
    ["-pR", source, destination],
    inherit_env=true,
  )
  if code != 0 {
    fail(
      "failed to copy bundled MoonBit toolchain seed: " +
      output.text().trim().to_owned(),
    )
  }
}

///|
async fn initialize_bundled_moonbit(moon_home : String) -> Unit {
  let version = moonbit_compiler_version(moon_home)
  if bundled_moonbit_ready(moon_home, version) {
    return
  }
  run_moonbit_bundle(moon_home, ["bundle", "--warn-list", "-a", "--all"])
  run_moonbit_bundle(moon_home, [
    "bundle", "--warn-list", "-a", "--target", "wasm-gc", "--quiet",
  ])
  @fs.write_file(
    @appdirs.moonbit_bundle_stamp_path(moon_home),
    "version=\{version}",
    create_mode=CreateOrTruncate,
  )
}

///|
async fn prepared_bundled_moonbit_payload(seed_dir : String) -> String? {
  guard @appdirs.prepared_moonbit_payload_dir(seed_dir) is Some(moon_home) else {
    return None
  }
  match bundled_moonbit_seed_version(seed_dir) {
    Some(version) =>
      if bundled_moonbit_ready(moon_home, version) {
        return Some(moon_home)
      }
    None => ()
  }
  remove_path_if_exists(moon_home)
  copy_moonbit_seed_dir(seed_dir, moon_home)
  initialize_bundled_moonbit(moon_home)
  Some(moon_home)
}

///|
async fn moonbit_env_for_engine(config : RunConfig) -> Map[String, String] {
  if @env.get(DisableBundledMoonEnv) is Some(_) {
    return {}
  }
  if @env.get(OverrideMoonHomeEnv) is Some(moon_home) {
    return moonbit_process_env(moon_home)
  }
  guard config.host is Native else { return {} }
  guard @appdirs.bundled_moonbit_seed_dir(config.engine) is Some(seed_dir) else {
    return {}
  }
  guard prepared_bundled_moonbit_payload(seed_dir) is Some(moon_home) else {
    return {}
  }
  moonbit_process_env(moon_home)
}
