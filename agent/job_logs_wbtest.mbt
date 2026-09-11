///|
#cfg(not(platform="windows"))
async test "job files survive scope cleanup and a new runtime cannot overwrite them" {
  let root = @fs.tmpdir(prefix="openseek-retained-jobs-")
  defer @fs.rmdir(root, recursive=true)
  let run : async () -> String = () => {
    @async.with_timeout(5000, () => {
      @async.with_task_group(group => {
        let tools = build_tools(
          AgentRuntime(),
          AgentTaskScope(group),
          job_log_dir=root,
        )
        guard tools.background_job_runtime() is Some(jobs) else {
          fail("missing jobs")
        }
        let id = jobs.start(
          program="/bin/sh",
          args=["-c", "printf retained; sleep 30"],
          command="retained",
        )
        guard jobs.snapshot(id) is Some(snapshot) &&
          snapshot.output_file is Some(path) else {
          fail("job was announced without a file")
        }
        assert_true(@fs.exists(path))
        while jobs.read_output(id) != Some("retained") {
          @async.sleep(5)
        }
        path
      })
    })
  }
  let first = run()
  assert_eq(@fs.read_file(first).text(), "retained")
  let second = run()
  assert_true(first != second)
  assert_eq(@fs.read_file(first).text(), "retained")
  assert_eq(@fs.read_file(second).text(), "retained")
}

///|
#cfg(not(platform="windows"))
async test "small foreground execution materializes all prior output at adoption" {
  let root = @fs.tmpdir(prefix="openseek-adopt-jobs-")
  defer @fs.rmdir(root, recursive=true)
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let jobs = @bgjobs.BgJobRuntime(AgentTaskScope(group), spill_dir=root)
      let exec = jobs.spawn_foreground_retained(
        "/bin/sh",
        ["-c", "printf before; sleep 30"],
        None,
        100,
      )
      while exec.head() != "before" {
        @async.sleep(5)
      }
      assert_true(exec.spill_path() is None)
      let id = jobs.adopt(exec, command="adopted")
      guard jobs.snapshot(id) is Some(snapshot) &&
        snapshot.output_file is Some(path) else {
        fail("missing output file")
      }
      assert_eq(@fs.read_file(path).text(), "before")
      assert_true(jobs.stop(id))
      assert_eq(@fs.read_file(path).text(), "before")
    })
  })
}

///|
#cfg(not(platform="windows"))
async test "failed background adoption stops the execution and publishes no phantom job" {
  let root = @fs.tmpdir(prefix="openseek-adopt-failure-")
  defer @fs.rmdir(root, recursive=true)
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let jobs = @bgjobs.BgJobRuntime(
        AgentTaskScope(group),
        spill_dir="\{root}/missing",
      )
      let exec = jobs.spawn_foreground_retained("/bin/sleep", ["30"], None, 100)
      try jobs.adopt(exec, command="cannot retain") catch {
        _ => assert_true(exec.output_error() is Some(_))
      } noraise {
        _ => fail("adoption should fail")
      }
      exec.wait()
      assert_true(exec.status() is Killed)
      assert_true(jobs.list().is_empty())
    })
  })
}
