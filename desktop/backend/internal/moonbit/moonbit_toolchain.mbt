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
///
/// It orders this process only. Every host process of one user prepares the
/// same payload directory, so the check and the preparation also run under
/// `with_payload_lock`.
let prepare_payload_lock : @semaphore.Semaphore = Semaphore(1, initial_value=1)

///|
fn payload_lock_path(moon_home : @pathx.Path) -> @pathx.Path {
  moon_home.dirname().join(moon_home.basename().to_owned() + ".lock")
}

///|
/// Run `body` holding the payload directory's lock across host processes,
/// waiting for whichever host holds it. Two hosts that start together on a
/// fresh install would otherwise both find no stamp, and one would remove
/// the directory the other is copying the seed into or running `moon bundle`
/// in. Waiting is the point: the host that arrives second finds the stamp
/// the first one wrote and reuses the payload.
///
/// The lock is a file beside the payload directory, not inside it:
/// preparation removes that directory.
async fn[T] with_payload_lock(
  moon_home : @pathx.Path,
  body : async () -> T,
) -> T {
  let lock = @fs.open(
    payload_lock_path(moon_home).to_string(),
    mode=ReadWrite,
    create_mode=OpenOrCreate,
  )
  defer lock.close()
  lock.lock(Exclusive)
  defer lock.unlock()
  body()
}

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
  with_payload_lock(moon_home, () => {
    prepare_moonbit_payload(seed_dir~, moon_home~, version~, runtime_dir?)
    Some(moon_home)
  })
}

///|
/// Leave `moon_home` holding the seed's toolchain with its core bundles
/// built: reused when its stamp names this seed's version, replaced from the
/// seed otherwise. The caller holds both payload locks.
async fn prepare_moonbit_payload(
  seed_dir~ : @pathx.Absolute,
  moon_home~ : @pathx.Path,
  version~ : String,
  runtime_dir? : @pathx.Path,
) -> Unit {
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
    return
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

///|
/// Two host processes of one user prepare the same payload directory. The
/// lock belongs to the open file, so holding it here stands in for the other
/// host. That host is still preparing when this one asks: without the lock
/// this one would find no stamp, remove the directory, and try to build the
/// bundles itself — which this fixture's empty `moon` cannot do.
async test "a host waits for another host's preparation and reuses it" {
  let runtime = @pathx.Path(@fs.tmpdir(prefix="openseek-moonbit-two-hosts-"))
  defer (@fs.rmdir(runtime.to_string(), recursive=true) catch { _ => () })
  let seed_dir = runtime.join("seed").join("macos-arm64").resolve()
  @fs.mkdir(seed_dir.to_string(), recursive=true)
  @fs.write_file(
    moonbit_seed_version_path(seed_dir).to_string(),
    "test-version",
    create_mode=CreateOrTruncate,
  )
  guard prepared_moonbit_payload_dir(seed_dir~, runtime_dir=runtime)
    is Some(moon_home) else {
    fail("no payload directory under the runtime directory")
  }
  let held = @fs.open(
    payload_lock_path(moon_home).to_string(),
    mode=ReadWrite,
    create_mode=OpenOrCreate,
  )
  held.lock(Exclusive)
  let order : Array[String] = []
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      let prepared = prepared_bundled_moonbit_payload(
        seed_dir~,
        runtime_dir=runtime,
      )
      order.push("this host has its toolchain")
      assert_eq(
        prepared.map(path => path.to_string()),
        Some(moon_home.to_string()),
      )
    })
    // Long enough for this host to reach the lock and block on it.
    @async.sleep(100)
    // The other host finishes: a complete payload, its stamp written last.
    let complete = [
      moonbit_command(moon_home),
      moonbit_compiler_command(moon_home),
      moonbit_native_bundle_probe_path(moon_home),
      moonbit_wasm_gc_bundle_probe_path(moon_home),
    ]
    for file in complete {
      @fsx.ensure_dir(file.dirname())
      @fs.write_file(file.to_string(), "", create_mode=CreateOrTruncate)
    }
    @fs.write_file(
      moonbit_bundle_stamp_path(moon_home).to_string(),
      "version=test-version",
      create_mode=CreateOrTruncate,
    )
    order.push("the other host finished")
    held.unlock()
    held.close()
  })
  assert_eq(order, ["the other host finished", "this host has its toolchain"])
  // Reused, not replaced: the other host's files are the ones still there.
  assert_true(@fsx.exists(moonbit_native_bundle_probe_path(moon_home)))
}
