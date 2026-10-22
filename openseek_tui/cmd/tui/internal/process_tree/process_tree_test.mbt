///|
/// Spawn a two-level tree shaped like the TUI's Windows `moonx` engine: `cmd.exe`
/// runs `ping` as a child and waits for it, and `ping` inherits the stdout
/// pipe. Kill only the root (as `TerminateProcess` does) once `ping` is known
/// to be running, and report whether stdout reached EOF within `grace_ms`,
/// i.e. whether every holder of the pipe died.
#cfg(all(target="native", platform="windows"))
async fn root_kill_closes_stdout(
  contain~ : Bool,
  contain_after_child_started~ : Bool,
  grace_ms~ : Int32,
) -> Bool {
  @async.with_task_group(group => {
    let (reader, child_stdout) = @process.read_from_process()
    defer reader.close()
    let proc = @process.spawn(
      group,
      "cmd.exe",
      ["/c", "ping", "-n", "30", "127.0.0.1"],
      stdout=child_stdout,
      cancel_handler=@process.hard_cancel(),
      no_wait=true,
    )
    if contain && !contain_after_child_started {
      @process_tree.contain(group, proc)
    }
    // Output means `ping` is running, so the kill below cannot win a race
    // against its creation.
    guard reader.read_until("\n") is Some(_) else {
      fail("ping produced no output")
    }
    if contain && contain_after_child_started {
      @process_tree.contain(group, proc)
    }
    proc.cancel()
    @async.with_timeout_opt(grace_ms, () => reader.read_all()) is Some(_)
  })
}

///|
#cfg(all(target="native", platform="windows"))
async test "windows: killing a bare root leaves its child holding stdout" {
  // The premise: without containment the grandchild survives the root's
  // TerminateProcess and keeps the pipe open (it exits on its own later).
  assert_false(
    root_kill_closes_stdout(
      contain=false,
      contain_after_child_started=false,
      grace_ms=2000,
    ),
  )
}

///|
#cfg(all(target="native", platform="windows"))
async test "windows: a contained tree dies with its root" {
  assert_true(
    root_kill_closes_stdout(
      contain=true,
      contain_after_child_started=false,
      grace_ms=10000,
    ),
  )
}

///|
#cfg(all(target="native", platform="windows"))
async test "windows: containment adopts a child started before it" {
  // The spawn-to-assignment window: a child that already exists when the root
  // joins the job must be swept in too.
  assert_true(
    root_kill_closes_stdout(
      contain=true,
      contain_after_child_started=true,
      grace_ms=10000,
    ),
  )
}
