///|
test "terminal failures are normalized by the host" {
  assert_false(host_reports_terminal_error(AgentStep))
  assert_false(host_reports_terminal_error(AgentFinished("done")))
  assert_false(
    host_reports_terminal_error(ContextYield("[context ceiling] checkpointed")),
  )
  assert_true(host_reports_terminal_error(AgentAborted("interrupted")))
  assert_true(host_reports_terminal_error(MaxStepsExhausted))
  assert_true(host_reports_terminal_error(AgentError("boom")))
}

///|
test "context yield has a distinct non-success wire status" {
  let status : RunStatus = ContextYield
  assert_eq(status.wire(), "context_yield")
}

///|
async test "context yield reports a terminal finished event" {
  let emitted : Array[EngineEvent] = []
  let sink = EventSink(fn(event) { emitted.push(event) })
  let answer = "[context ceiling] checkpointed"
  assert_true(
    handle_decoded_event(sink, 17, ContextYield(answer)),
  )
  guard emitted is [Finished(payload)] else {
    fail("expected one finished event")
  }
  assert_eq(payload.run_id, 17)
  assert_eq(payload.status, "context_yield")
  guard payload.answer is Some(emitted_answer) else {
    fail("expected continuation guidance")
  }
  assert_eq(emitted_answer, answer)
}

///|
test "terminal closure preserves a queued compaction" {
  assert_true(
    Running(cancel_requested=false, compact_queued=false).after_run_close()
    is Idle,
  )
  assert_true(
    Running(cancel_requested=false, compact_queued=true).after_run_close()
    is Compacting,
  )
}

///|
test "trailing steer settle events keep the terminal run id" {
  let tracker = SteerRunTracker::new()
  tracker.begin_run()
  tracker.record_sent("old steer")
  tracker.record_terminal(41)
  tracker.begin_run()
  tracker.record_sent("fresh steer")
  let old_drop : @event.AgentEvent? = Some(SteerDropped("old steer"))
  let fresh_apply : @event.AgentEvent? = Some(SteerApplied("fresh steer"))
  assert_eq(tracker.run_id_for_event(old_drop, 42), 41)
  assert_eq(tracker.run_id_for_event(fresh_apply, 42), 42)
}

///|
test "new turn events clear stale settling state" {
  let tracker = SteerRunTracker::new()
  tracker.begin_run()
  tracker.record_sent("old steer")
  tracker.record_terminal(7)
  assert_eq(tracker.run_id_for_event(Some(AgentStep), 8), 8)
  let old_drop : @event.AgentEvent? = Some(SteerDropped("old steer"))
  assert_eq(tracker.run_id_for_event(old_drop, 8), 8)
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

///|
/// The slot claim is what closes the compact-preempts-starting-prompt race:
/// whichever op (start, compact, archive) validated first holds the slot
/// through its command hitting the wire, and every later claimant is refused
/// with the holder's message — releasing reopens the slot.
test "a claimed session slot refuses every other op until released" {
  let slot : SessionSlot = { pending: None, engine: None }
  slot.claim(StartPending)
  let refused = try slot.claim(CompactPending) catch {
    EngineError(message) => message
  } noraise {
    _ => ""
  }
  assert_true(refused.contains("already starting"))
  slot.pending = None
  slot.claim(CompactPending)
  let refused = try slot.claim(ArchivePending) catch {
    EngineError(message) => message
  } noraise {
    _ => ""
  }
  assert_true(refused.contains("compaction is already being requested"))
}
