// Shared fixtures for this package's whitebox tests: the ambient-env
// serialization lock, env save/restore helpers, fake toolchain seeds and
// the per-area test configs. Test-only - nothing here ships.

///|
/// Serializes every test that reads or writes the two process-global
/// variables deciding where a conversation lives: `OPENSEEK_SESSION_ROOT`
/// (the registry, and the global store records migrate out of) and `HOME`
/// (where the default workspace lands, and so where a run works). Both are
/// process-wide, so a test that moves either is not isolated from a test that
/// merely reads it — and a test that starts a run reads `HOME`, whether or not
/// it mentions it.
///
/// Holding this lock is also how a test gets a disposable `HOME`, so the
/// default workspace it attaches lands in its own temporary tree instead of
/// the developer's real one.
///
/// Other ambient variables the tests touch — `OPENSEEK_DIR`,
/// `OPENSEEK_API_URL` — need no lock: the host always writes them explicitly
/// into a child's environment, so nothing reads the ambient value except the
/// test that set it.
let ambient_env_test_lock : @async.Mutex = Mutex()

///|
fn restore_session_root_env(previous : String?) -> Unit {
  if previous is Some(value) {
    @sys.set_env_var("OPENSEEK_SESSION_ROOT", value)
  } else {
    @sys.unset_env_var("OPENSEEK_SESSION_ROOT")
  }
}

///|
#cfg(not(platform="windows"))
fn restore_home_env(previous : String?) -> Unit {
  if previous is Some(value) {
    @sys.set_env_var("HOME", value)
  } else {
    @sys.unset_env_var("HOME")
  }
}

///|
async fn prepare_fake_moonbit_seed(
  seed : @pathx.Path,
  version~ : String,
) -> Unit {
  write_fake_executable(seed.join("bin/moon"))
  write_fake_executable(seed.join("bin/moonc"))
  write_fake_file(seed.join("lib/core/moon.mod"))
  @fs.write_file(
    seed.join(".openseek-moonbit-seed-version").to_string(),
    version,
    create_mode=CreateOrTruncate,
  )
}

///|
async fn prepare_fake_bundled_moonbit_home(
  moon_home : @pathx.Path,
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
fn pump_test_config(session : String) -> RunConfig {
  {
    task: "test",
    api_key: "test",
    api_url: None,
    model: "test",
    max_steps: 1,
    engine: "unused",
    cwd: None,
    session,
    session_root: Some(@pathx.Path("/tmp/openseek-pump-test").resolve()),
  }
}

///|
#cfg(not(platform="windows"))
fn follower_test_config(
  engine : String,
  session : String,
  root : @pathx.Absolute,
) -> RunConfig {
  {
    task: "test",
    api_key: "test",
    api_url: None,
    model: "test",
    max_steps: 1,
    engine,
    cwd: None,
    session,
    session_root: Some(root),
  }
}

///|
fn follower_state_fixture(session : String) -> SessionFollower {
  {
    session,
    root: @pathx.Path("/tmp/follower-state-fixture").resolve(),
    inbox: Queue(kind=Blocking(3)),
    load_requests: Queue(kind=Blocking(1)),
    kick_pending: false,
    load_pending: false,
    stopping: false,
    retired: false,
    stop_generation: 0,
    completed_stop_generation: 0,
    completed_stop_error: None,
    stop_observers: 0,
    durable_finishes: [],
    watermark: 0,
    consumed: None,
  }
}

///|
async fn with_settings_dir(
  body : async (@pathx.Path, EngineManager) -> Unit,
) -> Unit {
  // The status payload reads the DEEPSEEK fallback from the process
  // environment; hold it steady so the expectations here cannot depend on
  // the developer's shell. That includes other tests' writes: every test
  // that mutates ambient env holds this lock, and reading the fallback
  // concurrently with one of them (config placement sets a fake key) is
  // the same race — so the readers here must hold it too.
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous_key = @sys.get_env_var("DEEPSEEK")
  @sys.unset_env_var("DEEPSEEK")
  defer (if previous_key is Some(value) { @sys.set_env_var("DEEPSEEK", value) })
  let dir : @pathx.Path = Path(@fs.tmpdir(prefix="openseek-settings-"))
  body(dir, new_engine_manager("openseek", runtime_dir=dir)) catch {
    error => {
      @fs.rmdir(dir.to_string(), recursive=true) catch {
        _ => ()
      }
      raise error
    }
  }
  @fs.rmdir(dir.to_string(), recursive=true) catch {
    _ => ()
  }
}

///|
#cfg(not(platform="windows"))
fn restore_openseek_dir(previous : String?) -> Unit {
  if previous is Some(value) {
    @sys.set_env_var("OPENSEEK_DIR", value)
  } else {
    @sys.unset_env_var("OPENSEEK_DIR")
  }
}

///|
#cfg(not(platform="windows"))
fn has_finished_run(events : Array[EngineEvent], run_id : String) -> Bool {
  for event in events {
    if event is Finished(payload) && payload.run_id == run_id {
      return true
    }
  }
  false
}

///|
/// A workspace fixture for the run tests: `<root>/ws` attached as the only
/// registered workspace, with the registry itself under `<root>/global`.
/// Every run belongs to a workspace now, so a test that starts one registers
/// a real directory rather than relying on the removed scratch fallback.
/// Returns the path to send as the start payload's workspace hint.
async fn attach_run_workspace(root : @pathx.Path) -> String {
  let workspace = root.join("ws")
  @fsx.ensure_dir(workspace)
  let global = root.join("global")
  @fsx.ensure_dir(global)
  @fs.write_file(
    global.join("workspaces.json").to_string(),
    ({ "workspaces": [workspace.to_string()] } : Json).stringify(),
    create_mode=CreateOrTruncate,
  )
  workspace.to_string()
}

///|
async fn write_fake_file(path : @pathx.Path) -> Unit {
  @fsx.ensure_dir(path.dirname())
  @fs.write_file(path.to_string(), "", create_mode=CreateOrTruncate)
}

///|
/// The resolver only assembles a toolchain around a regular executable `moon`,
/// and initialization executes `moonc`, so both fakes must carry the bit.
async fn write_fake_executable(path : @pathx.Path) -> Unit {
  @fsx.ensure_dir(path.dirname())
  @fs.write_file(
    path.to_string(),
    "",
    create_mode=CreateOrTruncate,
    permission=0o755,
  )
}

///|
/// A ServeEngine handle for tests, with every bookkeeping field at its
/// spawn default. Adding a field to ServeEngine updates this one site
/// instead of every test literal.
fn test_serve_engine(
  session : String,
  writer : @process.WriteToProcess,
  process : @process.Process,
  sink : EventSink,
  phase~ : EnginePhase,
  session_root? : @pathx.Absolute,
  follower? : SessionFollower,
  condemned? : Bool = false,
) -> ServeEngine {
  {
    session_key: session,
    session_root,
    spec_key: "test",
    writer,
    commands: Queue(kind=Unbounded),
    process,
    sink,
    follower,
    consumer: None,
    phase,
    run_admitted_ms: 0,
    pending_failure: None,
    condemned,
    steer_runs: SteerRunTracker::new(),
  }
}
