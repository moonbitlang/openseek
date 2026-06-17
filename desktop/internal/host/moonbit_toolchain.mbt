///|
fn moonbit_process_env(moon_home : @path.Path) -> Map[String, String] {
  {
    "MOON_HOME": moon_home.to_string(),
    "PATH": @appdirs.prepend_to_path_env(
      @appdirs.moonbit_bin_dir(moon_home).to_string(),
      @env.get("PATH"),
    ),
  }
}

///|
async fn path_exists(path : @path.Path) -> Bool {
  @fs.exists(path.to_string())
}

///|
async fn read_text(path : @path.Path) -> String {
  @fs.read_file(path.to_string()).text()
}

///|
async fn read_text_if_exists(path : @path.Path) -> String? {
  if path_exists(path) {
    Some(read_text(path))
  } else {
    None
  }
}

///|
async fn bundled_moonbit_seed_version(seed_dir : @path.Path) -> String? {
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
async fn moonbit_compiler_version(moon_home : @path.Path) -> String {
  let moonc = @appdirs.moonbit_compiler_command(moon_home)
  let child_stdin = prepare_engine_stdin(moonc)
  let (code, output) = @process.collect_output_merged(
    moonc.to_string(),
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
async fn bundled_moonbit_ready(
  moon_home : @path.Path,
  version : String,
) -> Bool {
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
async fn run_moonbit_bundle(
  moon_home : @path.Path,
  args : Array[String],
) -> Unit {
  let moon = @appdirs.moonbit_command(moon_home)
  let core_dir = moon_home.join("lib/core")
  let child_stdin = prepare_engine_stdin(moon)
  let (code, output) = @process.collect_output_merged(
    moon.to_string(),
    args,
    inherit_env=true,
    extra_env=moonbit_process_env(moon_home),
    stdin=child_stdin,
    cwd=core_dir.to_string().view(),
  )
  if code != 0 {
    fail(
      "failed to initialize bundled MoonBit toolchain: " +
      output.text().trim().to_owned(),
    )
  }
}

///|
async fn remove_path_if_exists(path : @path.Path) -> Unit {
  let path = path.to_string()
  if !@fs.exists(path) {
    return
  }
  if @fs.kind(path) is Directory {
    @fs.rmdir(path, recursive=true)
  } else {
    @fs.remove(path)
  }
}

///|
async fn copy_file(source : @path.Path, destination : @path.Path) -> Unit {
  @fs.write_file(
    destination.to_string(),
    @fs.read_file(source.to_string()),
    create_mode=CreateOrTruncate,
  )
}

///|
async fn copy_dir_recursive(
  source : @path.Path,
  destination : @path.Path,
) -> Unit {
  @fs.mkdir(destination.to_string(), recursive=true)
  for entry in @fs.readdir(source.to_string(), include_hidden=true) {
    let source_entry = source.join(entry)
    let destination_entry = destination.join(entry)
    if @fs.kind(source_entry.to_string()) is Directory {
      copy_dir_recursive(source_entry, destination_entry)
    } else {
      copy_file(source_entry, destination_entry)
    }
  }
}

///|
async fn copy_moonbit_seed_dir(
  source : @path.Path,
  destination : @path.Path,
) -> Unit {
  copy_dir_recursive(source, destination)
}

///|
async fn initialize_bundled_moonbit(moon_home : @path.Path) -> Unit {
  let version = moonbit_compiler_version(moon_home)
  if bundled_moonbit_ready(moon_home, version) {
    return
  }
  run_moonbit_bundle(moon_home, ["bundle", "--warn-list", "-a", "--all"])
  run_moonbit_bundle(moon_home, [
    "bundle", "--warn-list", "-a", "--target", "wasm-gc", "--quiet",
  ])
  @fs.write_file(
    @appdirs.moonbit_bundle_stamp_path(moon_home).to_string(),
    "version=\{version}",
    create_mode=CreateOrTruncate,
  )
}

///|
async fn prepared_bundled_moonbit_payload(seed_dir : @path.Path) -> @path.Path? {
  guard @appdirs.prepared_moonbit_payload_dir(seed_dir) is Some(moon_home) else {
    return None
  }
  if bundled_moonbit_seed_version(seed_dir) is Some(version) &&
    bundled_moonbit_ready(moon_home, version) {
    return Some(moon_home)
  }
  remove_path_if_exists(moon_home)
  copy_moonbit_seed_dir(seed_dir, moon_home)
  initialize_bundled_moonbit(moon_home)
  Some(moon_home)
}

///|
async fn moonbit_env_for_engine(config : RunConfig) -> Map[String, String] {
  guard config.host is Native else { return {} }
  guard @appdirs.bundled_moonbit_seed_dir(config.engine) is Some(seed_dir) else {
    return {}
  }
  guard prepared_bundled_moonbit_payload(seed_dir) is Some(moon_home) else {
    return {}
  }
  moonbit_process_env(moon_home)
}
