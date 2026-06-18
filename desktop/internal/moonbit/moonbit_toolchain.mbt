///|
fn moonbit_process_env(moon_home : @path.Path) -> Map[String, String] {
  {
    "MOON_HOME": moon_home.to_string(),
    "PATH": prepend_to_path_env(
      moonbit_bin_dir(moon_home).to_string(),
      @env.get("PATH"),
    ),
  }
}

///|
async fn bundled_moonbit_seed_version(seed_dir : @path.Path) -> String? {
  guard @fsx.read_text_if_exists(moonbit_seed_version_path(seed_dir))
    is Some(version) else {
    return None
  }
  let version = version.trim()
  if version.is_empty() {
    None
  } else {
    Some(version.to_owned())
  }
}

///|
async fn prepare_tool_stdin(
  runtime_dir : @path.Path?,
  command : @path.Path,
) -> &@process.ProcessInput {
  let path = if runtime_dir is Some(dir) {
    dir.join("moonbit-tool.stdin")
  } else {
    command.to_string() + ".stdin"
  }
  @fs.write_file(path.to_string(), "", create_mode=CreateOrTruncate)
  @process.redirect_from_file(path.to_string())
}

///|
async fn get_moonc_version(
  moon_home : @path.Path,
  runtime_dir : @path.Path?,
) -> String {
  let moonc = moonbit_compiler_command(moon_home)
  let child_stdin = prepare_tool_stdin(runtime_dir, moonc)
  let (code, output) = @process.collect_output_merged(
    moonc.to_string(),
    ["-v"],
    inherit_env=true,
    extra_env=moonbit_process_env(moon_home),
    stdin=child_stdin,
  )
  if code != 0 {
    fail(
      "failed to read bundled MoonBit compiler version: \{output.text().trim()}",
    )
  }
  match output.text().trim().split(" ").collect() {
    [['v', .. version], ..] => version.to_owned()
    [version, ..] => version.to_owned()
    [] => ""
  }
}

///|
async fn is_moonbit_bundled(moon_home : @path.Path, version : String) -> Bool {
  guard @fsx.read_text_if_exists(moonbit_bundle_stamp_path(moon_home))
    is Some(stamp) else {
    return false
  }
  if stamp != "version=\{version}" {
    return false
  }
  @fsx.exists(moonbit_command(moon_home)) &&
  @fsx.exists(moonbit_compiler_command(moon_home)) &&
  @fsx.exists(moonbit_native_bundle_probe_path(moon_home)) &&
  @fsx.exists(moonbit_wasm_gc_bundle_probe_path(moon_home))
}

///|
async fn bundle_moonbit(
  moon_home : @path.Path,
  args : Array[String],
  runtime_dir : @path.Path?,
) -> Unit {
  let moon = moonbit_command(moon_home)
  let core_dir = moon_home.join("lib/core")
  let child_stdin = prepare_tool_stdin(runtime_dir, moon)
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
async fn copy_dir_recursive(
  source : @path.Path,
  destination : @path.Path,
) -> Unit {
  @fsx.ensure_dir(destination)
  let dir = @fs.opendir(source.to_string())
  defer dir.close()
  while dir.next() is Some(entry) {
    let source_entry = source.join(entry.name)
    let destination_entry = destination.join(entry.name)
    if entry.is_dir {
      copy_dir_recursive(source_entry, destination_entry)
    } else {
      @fsx.copy_file(source_entry, destination_entry)
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
async fn initialize_moonbit(
  moon_home : @path.Path,
  runtime_dir : @path.Path?,
) -> Unit {
  let version = get_moonc_version(moon_home, runtime_dir)
  @xlog.debug() <?
    {
      "event": "desktop_moonbit_initialize",
      "moon_home": moon_home.to_string(),
      "version": version,
    }
  if is_moonbit_bundled(moon_home, version) {
    @xlog.debug() <?
      {
        "event": "desktop_moonbit_initialize_reuse",
        "moon_home": moon_home.to_string(),
        "version": version,
      }
    return
  }
  bundle_moonbit(
    moon_home,
    ["bundle", "--warn-list", "-a", "--all"],
    runtime_dir,
  )
  bundle_moonbit(
    moon_home,
    ["bundle", "--warn-list", "-a", "--target", "wasm-gc", "--quiet"],
    runtime_dir,
  )
  @fs.write_file(
    moonbit_bundle_stamp_path(moon_home).to_string(),
    "version=\{version}",
    create_mode=CreateOrTruncate,
  )
  @xlog.debug() <?
    {
      "event": "desktop_moonbit_initialize_complete",
      "moon_home": moon_home.to_string(),
      "version": version,
    }
}

///|
async fn prepared_bundled_moonbit_payload(
  seed_dir~ : @path.Path,
  runtime_dir? : @path.Path,
) -> @path.Path? {
  guard prepared_moonbit_payload_dir(seed_dir~, runtime_dir?) is Some(moon_home) else {
    return None
  }
  @xlog.debug() <?
    {
      "event": "desktop_moonbit_prepare_payload",
      "seed_dir": seed_dir.to_string(),
      "moon_home": moon_home.to_string(),
      "moon_exists": @fsx.exists(moonbit_command(moon_home)),
      "moonc_exists": @fsx.exists(moonbit_compiler_command(moon_home)),
    }
  if bundled_moonbit_seed_version(seed_dir) is Some(version) &&
    is_moonbit_bundled(moon_home, version) {
    @xlog.debug() <?
      {
        "event": "desktop_moonbit_prepare_payload_reuse",
        "seed_dir": seed_dir.to_string(),
        "moon_home": moon_home.to_string(),
        "version": version,
      }
    return Some(moon_home)
  }
  @xlog.debug() <?
    {
      "event": "desktop_moonbit_prepare_payload_refresh",
      "seed_dir": seed_dir.to_string(),
      "moon_home": moon_home.to_string(),
    }
  @fsx.remove_if_exists(moon_home)
  copy_moonbit_seed_dir(seed_dir, moon_home)
  initialize_moonbit(moon_home, runtime_dir)
  @xlog.debug() <?
    {
      "event": "desktop_moonbit_prepare_payload_complete",
      "seed_dir": seed_dir.to_string(),
      "moon_home": moon_home.to_string(),
      "moon_exists": @fsx.exists(moonbit_command(moon_home)),
      "moonc_exists": @fsx.exists(moonbit_compiler_command(moon_home)),
    }
  Some(moon_home)
}

///|
pub async fn prepare_bundled_home(
  engine_command : String,
  runtime_dir? : @path.Path,
) -> @path.Path {
  @xlog.debug() <?
    {
      "event": "desktop_moonbit_prepare_home",
      "engine_command": engine_command,
      "runtime_dir": runtime_dir.map(dir => dir.to_string()).unwrap_or(""),
    }
  guard bundled_moonbit_seed_dir(engine_command) is Some(seed_dir) else {
    fail("bundled MoonBit toolchain seed not found")
  }
  guard prepared_bundled_moonbit_payload(seed_dir~, runtime_dir?)
    is Some(moon_home) else {
    fail("failed to prepare bundled MoonBit toolchain")
  }
  @xlog.debug() <?
    {
      "event": "desktop_moonbit_prepare_home_complete",
      "engine_command": engine_command,
      "seed_dir": seed_dir.to_string(),
      "moon_home": moon_home.to_string(),
    }
  moon_home
}
