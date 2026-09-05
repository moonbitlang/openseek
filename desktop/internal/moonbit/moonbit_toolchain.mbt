///|
/// Environment overrides for running the payload's own tools during
/// preparation. The payload's `moon`/`moonc` locate their compiler assets
/// relative to their own executables, so a path prepend is all they need;
/// `MOON_HOME` stays whatever the user has (it holds registry credentials
/// and caches, not the toolchain).
fn moonbit_process_env(moon_home : @pathx.Path) -> Map[String, String] {
  {
    "PATH": @env.prepend_to_path_env(
      moonbit_bin_dir(moon_home).to_string(),
      @env.get("PATH"),
    ),
  }
}

///|
async fn bundled_moonbit_seed_version(seed_dir : @pathx.Absolute) -> String? {
  guard @fsx.read_text_if_exists(moonbit_seed_version_path(seed_dir).to_path())
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
  runtime_dir : @pathx.Path?,
  command : @pathx.Path,
) -> &@process.ProcessInput {
  let path = if runtime_dir is Some(dir) {
    dir.join("moonbit-tool.stdin")
  } else {
    "\{command}.stdin"
  }
  @fs.write_file(path.to_string(), "", create_mode=CreateOrTruncate)
  @process.redirect_from_file(path.to_string())
}

///|
async fn is_moonbit_bundled(moon_home : @pathx.Path, version : String) -> Bool {
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
  moon_home : @pathx.Path,
  args : Array[String],
  runtime_dir : @pathx.Path?,
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
    no_console_window=true,
  )
  if code != 0 {
    fail(
      "failed to initialize bundled MoonBit toolchain: " +
      output.text().trim().to_owned(),
    )
  }
}

///|
async fn copy_moonbit_seed_dir(
  source : @pathx.Absolute,
  destination : @pathx.Path,
) -> Unit {
  @fsx.copy_dir(source.to_path(), destination)
}

///|
/// Build the copied seed's core bundles against the version packaging already
/// verified with `moonc -v`. The seed version stamp is authoritative here: it
/// is written only after extraction, executable-bit normalization, and the
/// compiler-version check have all succeeded.
async fn initialize_moonbit(
  moon_home : @pathx.Path,
  version : String,
  runtime_dir : @pathx.Path?,
) -> Unit {
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
/// Serializes bundled-toolchain preparation process-wide. The engine pump
/// already serializes its own spawns and the LSP pool its own command
/// resolution, but the two subsystems share this one payload directory with
/// nothing ordering them against each other: on a fresh install or after a
/// seed bump (no valid stamp yet), an LSP spawn and an engine spawn could
/// interleave `remove_if_exists` with the other side's seed copy or `moon
/// bundle`. Preparation runs for seconds across many suspension points, so
/// the lock is load-bearing; the stamp check after acquiring turns the
/// losing caller into a cheap reuse.
let prepare_payload_lock : @semaphore.Semaphore = Semaphore(1, initial_value=1)

///|
async fn prepared_bundled_moonbit_payload(
  seed_dir~ : @pathx.Absolute,
  runtime_dir? : @pathx.Path,
) -> @pathx.Path? {
  guard prepared_moonbit_payload_dir(seed_dir~, runtime_dir?) is Some(moon_home) else {
    return None
  }
  prepare_payload_lock.acquire()
  defer prepare_payload_lock.release()
  guard bundled_moonbit_seed_version(seed_dir) is Some(version) else {
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
  if is_moonbit_bundled(moon_home, version) {
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
  initialize_moonbit(moon_home, version, runtime_dir)
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
async test "prepared payload dir accepts existing toolchain root" {
  let runtime = @pathx.Path(@fs.tmpdir(prefix="openseek-moonbit-runtime-"))
  defer (@fs.rmdir(runtime.to_string(), recursive=true) catch { _ => () })
  let root = runtime.join("toolchains/moonbit")
  @fs.mkdir(root.to_string(), recursive=true)
  let expected = root.join("macos-arm64").to_string()
  let result = prepared_moonbit_payload_dir(
    seed_dir=runtime.join("seed").join("macos-arm64").resolve(),
    runtime_dir=runtime,
  )
  let actual = result.map(path => path.to_string()).unwrap_or("<none>")
  assert_eq(actual, expected)
}
