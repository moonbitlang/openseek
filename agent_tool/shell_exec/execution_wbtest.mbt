///|
/// Poll an execution until it reaches a terminal status, failing after a bounded
/// deadline (200 ticks of 25ms) so a hung child can never hang the test.
#cfg(not(platform="windows"))
async fn poll_exec_terminal(exec : ShellExecution) -> Unit {
  for _ in 0..<200 {
    if exec.status().is_terminal() {
      return
    }
    @async.sleep(25)
  }
  fail("execution did not reach a terminal state in time")
}

///|
#cfg(not(platform="windows"))
async test "execution records a non-zero exit code" {
  @async.with_task_group(group => {
    let exec = ShellExecution::start(AgentTaskScope(group), program="sh", args=[
      "-c", "exit 3",
    ])
    poll_exec_terminal(exec)
    assert_true(exec.status() is Exited(3))
    assert_true(exec.exit_code() is Some(3))
  })
}

///|
#cfg(not(platform="windows"))
async test "execution runs to completion and captures output" {
  @async.with_task_group(group => {
    let exec = ShellExecution::start(AgentTaskScope(group), program="sh", args=[
      "-c", "printf hello",
    ])
    poll_exec_terminal(exec)
    assert_true(exec.status() is Exited(0))
    assert_true(exec.head().contains("hello"))
    assert_true(exec.exit_code() is Some(0))
  })
}

///|
#cfg(not(platform="windows"))
async test "kill_when_full stops a runaway once the sink fills" {
  @async.with_task_group(group => {
    let exec = ShellExecution::start(
      AgentTaskScope(group),
      program="sh",
      args=["-c", "yes"],
      inline_cap=100,
      hard_cap=100,
      kill_when_full=true,
    )
    poll_exec_terminal(exec)
    assert_true(exec.status() is Killed)
    assert_true(exec.output_truncated())
  })
}

///|
#cfg(not(platform="windows"))
async test "large output spills and read_all returns the full output" {
  let dir = @fs.tmpdir(prefix="openseek-exec-spill-")
  defer @fs.rmdir(dir, recursive=true)
  let path = "\{dir}/spill.out"
  @async.with_task_group(group => {
    let exec = ShellExecution::start(
      AgentTaskScope(group),
      program="sh",
      args=["-c", "seq 1 5000"],
      inline_cap=100,
      hard_cap=1000000,
      spill_path=path,
    )
    poll_exec_terminal(exec)
    assert_true(exec.status() is Exited(0))
    assert_true(exec.over_inline_cap())
    assert_true(exec.spill_path() is Some(_))
    // head is a bounded preview; read_all is the full output.
    assert_true(exec.head().has_prefix("1\n"))
    let full = exec.read_all()
    assert_true(full.has_prefix("1\n"))
    assert_true(full.contains("5000"))
  })
}

///|
#cfg(not(platform="windows"))
async test "request_stop synchronously terminates a running execution" {
  @async.with_task_group(group => {
    let exec = ShellExecution::start(AgentTaskScope(group), program="sleep", args=[
      "30",
    ])
    @async.sleep(50)
    assert_true(exec.status() is Running)
    exec.request_stop()
    poll_exec_terminal(exec)
    assert_true(exec.status() is Killed)
  })
}
