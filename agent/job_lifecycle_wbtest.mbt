///|
#cfg(not(platform="windows"))
async test "job lifecycle publishes ordered durable start and failure with retained UTF8" {
  let root = @fs.tmpdir(prefix="openseek-job-events-")
  defer @fs.rmdir(root, recursive=true)
  let events : Array[(@protocol.JobEventKind, @protocol.JobRecord)] = []
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let jobs = @bgjobs.BgJobRuntime(
        AgentTaskScope(group),
        spill_dir=root,
        persistent_logs=true,
        on_job_event=(kind, job) => events.push((kind, job)),
      )
      let id = jobs.start(
        program="/bin/sh",
        args=["-c", "printf '你好'; exit 7"],
        command="failure",
      )
      ignore(jobs.wait_any([id]))
      assert_eq(events.length(), 2)
      assert_true(events[0].0 is Started)
      assert_true(events[1].0 is Failed)
      assert_eq(events[1].1.revision, 2)
      assert_true(events[1].1.state is Exited(7))
      assert_eq(events[1].1.output_bytes, 6L)
      assert_true(events[1].1.finished_at_ms is Some(_))
      let saved : @protocol.JobRecord = @json.from_json(
        @json.parse(@fs.read_file("\{root}/\{id}.json").text()),
      )
      assert_eq(saved, events[1].1)
      assert_eq(@fs.read_file("\{root}/\{id}.out").text(), "你好")
      jobs.finalize()
      assert_eq(events.length(), 2)
    })
  })
}

///|
#cfg(not(platform="windows"))
async test "stop emits stopping before one settled terminal event" {
  let events : Array[(@protocol.JobEventKind, @protocol.JobRecord)] = []
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let jobs = @bgjobs.BgJobRuntime(AgentTaskScope(group), on_job_event=(
        kind,
        job,
      ) => events.push((kind, job)))
      let id = jobs.start(program="/bin/sleep", args=["30"], command="sleep")
      assert_true(jobs.stop(id))
      assert_eq(events.length(), 3)
      assert_true(events[0].0 is Started)
      assert_true(events[1].0 is Updated)
      assert_true(events[2].0 is Finished)
      assert_true(events[2].1.state is Stopped("user"))
      assert_true(jobs.stop(id))
      assert_eq(events.length(), 3)
    })
  })
}

///|
#cfg(not(platform="windows"))
async test "session cleanup persists a terminal record after cancellation" {
  let root = @fs.tmpdir(prefix="openseek-job-finalize-")
  defer @fs.rmdir(root, recursive=true)
  let path = @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let tools = build_tools(
        AgentRuntime(),
        AgentTaskScope(group),
        job_log_dir=root,
      )
      guard tools.background_job_runtime() is Some(jobs) else {
        fail("missing jobs")
      }
      let id = jobs.start(program="/bin/sleep", args=["30"], command="sleep")
      "\{root}/\{jobs.generation()}/\{id}.json"
    })
  })
  let saved : @protocol.JobRecord = @json.from_json(
    @json.parse(@fs.read_file(path).text()),
  )
  assert_true(saved.state is Stopped("session_ended"))
  assert_eq(saved.revision, 2)
}
