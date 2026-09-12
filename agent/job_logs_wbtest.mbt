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

///|
async test "constructing session tools does not create a phantom durable session" {
  let root = @fs.tmpdir(prefix="openseek-lazy-jobs-")
  defer @fs.rmdir(root, recursive=true)
  let session_dir = "\{root}/sessions/new-session"
  @async.with_task_group(group => {
    ignore(
      build_tools(
        AgentRuntime(),
        AgentTaskScope(group),
        job_log_dir="\{session_dir}/jobs",
      ),
    )
    assert_false(@fs.exists(session_dir))
  })
  assert_false(@fs.exists(session_dir))
}

///|
#cfg(not(platform="windows"))
async test "concurrent first jobs prepare one canonical runtime directory" {
  let root = @fs.tmpdir(prefix="openseek-lazy-race-")
  defer @fs.rmdir(root, recursive=true)
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let tools = build_tools(
        AgentRuntime(),
        AgentTaskScope(group),
        job_log_dir="\{root}/jobs",
      )
      guard tools.background_job_runtime() is Some(jobs) else {
        fail("missing jobs")
      }
      let ids = @async.all([
        () => jobs.start(program="/bin/echo", args=["first"], command="first"),
        () => jobs.start(program="/bin/echo", args=["second"], command="second"),
      ])
      assert_eq(@fs.readdir("\{root}/jobs").length(), 1)
      for id in ids {
        jobs.wait_any([id])
        guard jobs.snapshot(id) is Some(snapshot) &&
          snapshot.output_file is Some(path) else {
          fail("missing file")
        }
        assert_eq(@fs.realpath(path), path)
        assert_true(@fs.read_file(path).text().has_suffix("\n"))
      }
    })
  })
}

///|
#cfg(not(platform="windows"))
async test "tiny foreground burst leaves no log files and concurrent noisy jobs retain every byte" {
  let root = @fs.tmpdir(prefix="openseek-job-load-")
  defer @fs.rmdir(root, recursive=true)
  @async.with_timeout(15000, () => {
    @async.with_task_group(group => {
      let tools = build_tools(
        AgentRuntime(),
        AgentTaskScope(group),
        job_log_dir=root,
      )
      guard tools.background_job_runtime() is Some(jobs) else {
        fail("missing jobs")
      }
      let tiny : Array[async () -> Unit] = []
      for _ in 0..<20 {
        tiny.push(() => {
          let exec = jobs.spawn_foreground_retained(
            "/bin/echo",
            ["small"],
            None,
            100,
          )
          exec.wait()
          assert_eq(exec.head(), "small\n")
          assert_true(exec.spill_path() is None)
          exec.discard()
        })
      }
      ignore(@async.all(tiny))
      let directory = "\{root}/\{jobs.generation()}"
      assert_eq(@fs.readdir(directory), ["owner.lock"])
      let noisy : Array[async () -> Unit] = []
      for _ in 0..<8 {
        noisy.push(() => {
          let id = jobs.start(
            program="/bin/sh",
            args=["-c", "head -c 262144 /dev/zero | tr '\\000' x"],
            command="noisy",
          )
          ignore(jobs.wait_any([id]))
          guard jobs.snapshot(id) is Some(snapshot) &&
            snapshot.output_file is Some(path) else {
            fail("missing log")
          }
          assert_eq(@fs.read_file(path).text(), "x".repeat(262144))
        })
      }
      ignore(@async.all(noisy))
    })
  })
}

///|
#cfg(not(platform="windows"))
async test "foreground-only runtime generations are removed after shutdown" {
  let root = @fs.tmpdir(prefix="openseek-empty-generations-")
  defer @fs.rmdir(root, recursive=true)
  for _ in 0..<3 {
    @async.with_task_group(group => {
      let tools = build_tools(
        AgentRuntime(),
        AgentTaskScope(group),
        job_log_dir=root,
      )
      guard tools.background_job_runtime() is Some(jobs) else {
        fail("missing runtime")
      }
      let exec = jobs.spawn_foreground_retained(
        "/bin/echo",
        ["short"],
        None,
        100,
      )
      exec.wait()
      exec.discard()
    })
    assert_eq(@fs.readdir(root), [])
  }
}

///|
#cfg(not(platform="windows"))
async test "failed metadata persistence never prunes an adopted job log" {
  let root = @fs.tmpdir(prefix="openseek-keep-failed-metadata-")
  defer @fs.rmdir(root, recursive=true)
  let path = @async.with_task_group(group => {
    let tools = build_tools(
      AgentRuntime(),
      AgentTaskScope(group),
      job_log_dir=root,
    )
    guard tools.background_job_runtime() is Some(jobs) else {
      fail("missing runtime")
    }
    let id = jobs.start(
      program="/bin/sh",
      args=["-c", "printf retained; sleep 30"],
      command="retained",
    )
    @async.with_timeout(10000, () => {
      while jobs.read_output(id) != Some("retained") {
        @async.sleep(5)
      }
    })
    guard jobs.snapshot(id) is Some(snapshot) &&
      snapshot.output_file is Some(path) else {
      fail("missing log")
    }
    let metadata = "\{root}/\{jobs.generation()}/\{id}.json"
    @fs.remove(metadata)
    @fs.mkdir(metadata)
    assert_true(jobs.stop(id))
    assert_true(
      jobs.records().any(record => record.persistence_error is Some(_)),
    )
    path
  })
  assert_eq(@fs.read_file(path).text(), "retained")
}
