///|
test "terminal failures are normalized by the host" {
  assert_false(host_reports_terminal_error(AgentStep))
  assert_false(host_reports_terminal_error(AgentFinished("done")))
  assert_true(host_reports_terminal_error(AgentAborted("interrupted")))
  assert_true(host_reports_terminal_error(MaxStepsExhausted))
  assert_true(host_reports_terminal_error(AgentError("boom")))
}

///|
test "trailing steer settle events keep the terminal run id" {
  let tracker = SteerRunTracker::new()
  tracker.begin_run()
  tracker.record_sent("old steer")
  tracker.record_terminal(41)
  tracker.begin_run()
  tracker.record_sent("fresh steer")
  let old_drop : Json = { "event": "steer_dropped", "content": "old steer" }
  let fresh_apply : Json = {
    "event": "steer_applied",
    "content": "fresh steer",
  }
  assert_eq(tracker.run_id_for_event(old_drop, 42), 41)
  assert_eq(tracker.run_id_for_event(fresh_apply, 42), 42)
}

///|
test "new turn events clear stale settling state" {
  let tracker = SteerRunTracker::new()
  tracker.begin_run()
  tracker.record_sent("old steer")
  tracker.record_terminal(7)
  assert_eq(
    tracker.run_id_for_event({ "event": "agent_step", "step": 1 }, 8),
    8,
  )
  assert_eq(
    tracker.run_id_for_event(
      { "event": "steer_dropped", "content": "old steer" },
      8,
    ),
    8,
  )
}

///|
test "bundled moonbit bin is prepended to native engine path" {
  assert_eq(prepend_to_path_env("/toolchain/bin", None), "/toolchain/bin")
  assert_eq(prepend_to_path_env("/toolchain/bin", Some("")), "/toolchain/bin")
  assert_eq(
    prepend_to_path_env("/toolchain/bin", Some("/usr/bin")),
    "/toolchain/bin\{PathSep}/usr/bin",
  )
}

///|
async test "native engine env has one authoritative bundled moon path" {
  let ambient_path = @sys.get_env_var("PATH")
  let root = @path.Path(@fs.tmpdir(prefix="openseek-engine-env-"))
  let engine = root.join("Contents/MacOS/openseek")
  let seed = root.join("Contents/Resources/toolchains/moonbit/macos-arm64")
  let runtime = root.join("runtime")
  let moon_home = runtime.join("toolchains/moonbit/macos-arm64")
  prepare_fake_moonbit_seed(seed, version="0.10.0-test") catch {
    error => {
      @fs.rmdir(root.to_string(), recursive=true) catch {
        _ => ()
      }
      raise error
    }
  }
  prepare_fake_bundled_moonbit_home(moon_home, version="0.10.0-test") catch {
    error => {
      @fs.rmdir(root.to_string(), recursive=true) catch {
        _ => ()
      }
      raise error
    }
  }
  let config : RunConfig = {
    task: "t",
    api_key: "k",
    api_url: None,
    model: "m",
    max_steps: 1,
    engine: engine.to_string(),
    host: Native,
    cwd: None,
    session: None,
    session_root: None,
  }
  let env = engine_process_env(config, Some(runtime)) catch {
    error => {
      @fs.rmdir(root.to_string(), recursive=true) catch {
        _ => ()
      }
      raise error
    }
  }
  @fs.rmdir(root.to_string(), recursive=true)
  let moon_bin = moon_home.join("bin").to_string()
  let expected_path = if ambient_path is Some(path) && !path.is_empty() {
    moon_bin + PathSep + path
  } else {
    moon_bin
  }
  assert_eq(env["PATH"], expected_path)
}

///|
async fn prepare_fake_moonbit_seed(
  seed : @path.Path,
  version~ : String,
) -> Unit {
  write_fake_file(seed.join("bin/moon"))
  write_fake_file(seed.join("bin/moonc"))
  write_fake_file(seed.join("lib/core/moon.mod"))
  @fs.write_file(
    seed.join(".openseek-moonbit-seed-version").to_string(),
    version,
    create_mode=CreateOrTruncate,
  )
}

///|
async fn prepare_fake_bundled_moonbit_home(
  moon_home : @path.Path,
  version~ : String,
) -> Unit {
  prepare_fake_moonbit_seed(moon_home, version~)
  @fs.write_file(
    moon_home.join(".openseek-moonbit-bundle-version").to_string(),
    "version=\{version}",
    create_mode=CreateOrTruncate,
  )
  write_fake_file(
    moon_home.join("lib/core/_build/native/release/bundle/prelude/prelude.mi"),
  )
  write_fake_file(
    moon_home.join("lib/core/_build/wasm-gc/release/bundle/prelude/prelude.mi"),
  )
}

///|
async fn write_fake_file(path : @path.Path) -> Unit {
  @fsx.ensure_dir(path.dirname())
  @fs.write_file(path.to_string(), "", create_mode=CreateOrTruncate)
}
