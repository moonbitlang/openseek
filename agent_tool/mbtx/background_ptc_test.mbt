///|
async test "default PTC survives background handoff and persists job-owned edit traces" {
  @vfs.with_tmpdir(ws => {
    @async.with_timeout(30000, () => {
      @async.with_task_group(group => {
        @fs.write_file("\{ws}/note.txt", "before\n")
        let state = @agent_tool.FileStateMap()
        let tools = @agent_tool.Tools([
          state.serialize(@edit.definition(workspace_root=ws, file_state=state)),
        ])
        let service = @ptc.Service::start(group, tools)
        let jobs = @bgjobs.BgJobRuntime(
          AgentTaskScope(group),
          spill_dir=ws,
          persistent_logs=true,
        )
        let foreground : Array[Json] = []
        let definition = @mbtx.definition(
          workspace_root=ws,
          file_state=state,
          bg_runtime=jobs,
          job_dir=ws,
          program_service=service,
          auto_background_after_ms=1,
          on_program_trace=data => foreground.push(data),
        )
        let output = dispatch(definition, {
          "source": (
            #|import { "bobzhang/openseek_tools@0.1.0" @tools, "moonbitlang/async" }
            #|async fn main {
            #|  @async.sleep(150)
            #|  let result = @tools.call("edit", { "path": "note.txt", "start_line": 1, "old_string": "before", "new_string": "after" })
            #|  if result.is_error { fail(result.content) }
            #|  println("background edit done")
            #|}
          ),
        })
        assert_false(output.is_error, msg=output.content)
        guard jobs.list() is [job] else {
          fail("default PTC did not background")
        }
        let foreground_count = foreground.length()
        jobs.wait_any([job.id])
        assert_eq(foreground.length(), foreground_count)
        assert_eq(@fs.read_file("\{ws}/note.txt").text(), "after\n")
        assert_true(jobs.snapshot(job.id) is Some({ status: Exited(0), .. }))
        assert_true(
          jobs.read_output(job.id) is Some(text) &&
          text.contains("background edit done"),
        )
        guard jobs.records() is [record] else { fail("missing job record") }
        assert_true(
          record.data
          is Some(
            { "ptc_calls": [{ "name": "edit", "status": "done", .. }], .. }
          ),
        )
        let saved = @json.parse(
          @fs.read_file(
            "\{ws}/\{@openseek_protocol.job_storage_name(job.id)}.json",
          ).text(),
        )
        let decoded : @openseek_protocol.JobRecord = @json.from_json(saved)
        assert_eq(decoded.data, record.data)
        assert_true(decoded.state is Exited(0))
        let result = dispatch(@job_output.definition(jobs), { "job_id": job.id })
        assert_eq(result.data, record.data)
      })
    })
  })
}

///|
async test "stopping a background PTC job joins its active tool before reporting stopped" {
  @vfs.with_tmpdir(ws => {
    @async.with_timeout(30000, () => {
      @async.with_task_group(group => {
        let entered : @async.Queue[Unit] = Queue(kind=Unbounded)
        let stopped = Ref(false)
        let tool = @agent_tool.AgentToolDefinition(
          name="block",
          description="block",
          schema=JsonSchema({}),
          program_callable=true,
          execute=Async(_ => {
            defer {
              stopped.val = true
            }
            entered.put(())
            @async.sleep(60000)
            @agent_tool.respond("unexpected")
          }),
        )
        let service = @ptc.Service::start(group, Tools([tool]))
        let jobs = @bgjobs.BgJobRuntime(AgentTaskScope(group), spill_dir=ws)
        let definition = @mbtx.definition(
          workspace_root=ws,
          bg_runtime=jobs,
          job_dir=ws,
          program_service=service,
          auto_background_after_ms=1,
        )
        let output = dispatch(definition, {
          "source": (
            #|import { "bobzhang/openseek_tools@0.1.0" @tools, "moonbitlang/async" }
            #|async fn main { println(@tools.call("block", {}).content) }
          ),
        })
        assert_false(output.is_error, msg=output.content)
        guard jobs.list() is [job] else { fail("missing background job") }
        entered.get()
        assert_true(jobs.stop(job.id))
        assert_true(stopped.val)
        assert_true(jobs.snapshot(job.id) is Some({ status: Stopped, .. }))
        guard jobs.records() is [record] else { fail("missing stopped job") }
        assert_true(
          record.data
          is Some({ "ptc_calls": [{ "status": "interrupted", .. }], .. }),
        )
      })
    })
  })
}

///|
async test "explicit PTC opt-out preserves ordinary background execution" {
  @vfs.with_tmpdir(ws => {
    @async.with_timeout(30000, () => {
      @async.with_task_group(group => {
        let service = @ptc.Service::start(group, Tools([]))
        let jobs = @bgjobs.BgJobRuntime(AgentTaskScope(group), spill_dir=ws)
        let definition = @mbtx.definition(
          workspace_root=ws,
          bg_runtime=jobs,
          job_dir=ws,
          program_service=service,
          auto_background_after_ms=1,
        )
        let output = dispatch(definition, {
          "ptc": false,
          "source": (
            #|import { "moonbitlang/async", "moonbitlang/core/env", "moonbitlang/core/json" }
            #|async fn main {
            #|  guard @env.get_env_var("OPENSEEK_PTC") is Some(raw) else { fail("missing denial") }
            #|  guard @json.parse(raw) is { "available": false, .. } else { fail("PTC was enabled") }
            #|  @async.sleep(100)
            #|  println("ordinary background done")
            #|}
          ),
        })
        assert_false(output.is_error, msg=output.content)
        assert_true(output.data is None)
        guard jobs.list() is [job] else { fail("opt-out did not background") }
        jobs.wait_any([job.id])
        assert_true(
          jobs.snapshot(job.id) is Some({ status: Exited(0), data: None, .. }),
        )
      })
    })
  })
}

///|
async test "background edits after foreground edits validate stale input and keep separate traces" {
  @vfs.with_tmpdir(ws => {
    @async.with_timeout(30000, () => {
      @async.with_task_group(group => {
        @fs.write_file("\{ws}/note.txt", "before\n")
        let state = @agent_tool.FileStateMap()
        let entered : @async.Queue[Unit] = Queue(kind=Unbounded)
        let release : @async.Queue[Unit] = Queue(kind=Unbounded)
        let wait = @agent_tool.AgentToolDefinition(
          name="wait",
          description="test gate",
          schema=JsonSchema({}),
          program_callable=true,
          concurrent_safe=true,
          execute=Async(_ => {
            entered.put(())
            release.get()
            @agent_tool.respond("go")
          }),
        )
        let service = @ptc.Service::start(
          group,
          Tools([
            state.serialize(
              @edit.definition(workspace_root=ws, file_state=state),
            ),
            wait,
          ]),
        )
        let jobs = @bgjobs.BgJobRuntime(AgentTaskScope(group), spill_dir=ws)
        let current : Ref[Json?] = Ref(None)
        let background = @mbtx.definition(
          workspace_root=ws,
          bg_runtime=jobs,
          job_dir=ws,
          program_service=service,
          auto_background_after_ms=1,
          on_program_trace=data => current.val = Some(data),
        )
        let output = dispatch(background, {
          "source": (
            #|import { "bobzhang/openseek_tools@0.1.0" @tools, "moonbitlang/async" }
            #|async fn main {
            #|  ignore(@tools.call("wait", {}))
            #|  let result = @tools.call("edit", { "path": "note.txt", "start_line": 1, "old_string": "before", "new_string": "background" })
            #|  if result.is_error { println("stale edit rejected") } else { fail("stale edit accepted") }
            #|}
          ),
        })
        assert_false(output.is_error, msg=output.content)
        guard jobs.list() is [job] else { fail("missing job") }
        entered.get()
        defer release.put(())
        let foreground = @mbtx.definition(
          workspace_root=ws,
          bg_runtime=jobs,
          job_dir=ws,
          program_service=service,
          auto_background_after_ms=10000,
          on_program_trace=data => current.val = Some(data),
        )
        let output = dispatch(foreground, {
          "source": (
            #|import { "bobzhang/openseek_tools@0.1.0" @tools, "moonbitlang/async" }
            #|async fn main {
            #|  let result = @tools.call("edit", { "path": "note.txt", "start_line": 1, "old_string": "before", "new_string": "foreground" })
            #|  if result.is_error { fail(result.content) }
            #|}
          ),
        })
        assert_false(output.is_error, msg=output.content)
        let foreground_trace = current.val
        release.put(())
        jobs.wait_any([job.id])
        assert_eq(current.val, foreground_trace)
        assert_eq(@fs.read_file("\{ws}/note.txt").text(), "foreground\n")
        assert_true(
          jobs.read_output(job.id) is Some(text) &&
          text.contains("stale edit rejected"),
        )
        assert_true(
          output.data is Some({ "ptc_calls": [{ "name": "edit", .. }], .. }),
        )
        assert_true(
          jobs.snapshot(job.id)
          is Some(
            {
              data: Some(
                {
                  "ptc_calls": [
                    _,
                    { "name": "edit", "result": { "is_error": true, .. }, .. },
                  ],
                  ..
                }
              ),
              ..
            }
          ),
        )
      })
    })
  })
}

///|
async test "successful process exit with an unfinished RPC is reported as a failed job" {
  @vfs.with_tmpdir(ws => {
    @async.with_timeout(30000, () => {
      @async.with_task_group(group => {
        let entered : @async.Queue[Unit] = Queue(kind=Unbounded)
        let stopped = Ref(false)
        let block = @agent_tool.AgentToolDefinition(
          name="block",
          description="unfinished call",
          schema=JsonSchema({}),
          program_callable=true,
          execute=Async(_ => {
            defer {
              stopped.val = true
            }
            entered.put(())
            @async.sleep(60000)
            @agent_tool.respond("unexpected")
          }),
        )
        let ready = @agent_tool.AgentToolDefinition(
          name="ready",
          description="wait for the other request to start",
          schema=JsonSchema({}),
          program_callable=true,
          concurrent_safe=true,
          execute=Async(_ => {
            entered.get()
            @agent_tool.respond("ready")
          }),
        )
        let service = @ptc.Service::start(group, Tools([block, ready]))
        let jobs = @bgjobs.BgJobRuntime(AgentTaskScope(group), spill_dir=ws)
        let definition = @mbtx.definition(
          workspace_root=ws,
          bg_runtime=jobs,
          job_dir=ws,
          program_service=service,
          auto_background_after_ms=1,
        )
        let output = dispatch(definition, {
          "source": (
            #|import { "bobzhang/openseek_tools@0.1.0" @tools, "moonbitlang/async" }
            #|async fn main {
            #|  @async.with_task_group(group => {
            #|    group.spawn_bg(() => ignore(@tools.call("block", {})), no_wait=true, allow_failure=true)
            #|    ignore(@tools.call("ready", {}))
            #|  })
            #|}
          ),
        })
        assert_false(output.is_error, msg=output.content)
        guard jobs.list() is [job] else { fail("missing job") }
        jobs.wait_any([job.id])
        assert_true(stopped.val)
        guard jobs.records() is [record] else {
          fail("missing terminal record")
        }
        assert_true(record.state is Exited(0))
        assert_true(record.cleanup_error is Some(_))
        let result = dispatch(@job_output.definition(jobs), { "job_id": job.id })
        assert_true(result.is_error)
        assert_true(result.content.contains("unfinished tool calls"))
      })
    })
  })
}

///|
async test "handoff failure retains completed mutations and interrupts pending calls" {
  @vfs.with_tmpdir(ws => {
    @async.with_timeout(30000, () => {
      @async.with_task_group(group => {
        @fs.mkdir("\{ws}/logs")
        @fs.write_file("\{ws}/note.txt", "before\n")
        let state = @agent_tool.FileStateMap()
        let blocked = Ref(false)
        let sabotage = @agent_tool.AgentToolDefinition(
          name="block",
          description="force output materialization failure",
          schema=JsonSchema({}),
          program_callable=true,
          execute=Async(_ => {
            // The foreground log remains in memory until adoption; making its
            // destination a directory forces adopt to fail after a successful edit.
            @fs.mkdir("\{ws}/logs/fg-1.out")
            blocked.val = true
            @async.sleep(60000)
            @agent_tool.respond("unexpected")
          }),
        )
        let service = @ptc.Service::start(
          group,
          Tools([
            state.serialize(
              @edit.definition(workspace_root=ws, file_state=state),
            ),
            sabotage,
          ]),
        )
        let jobs = @bgjobs.BgJobRuntime(
          AgentTaskScope(group),
          spill_dir="\{ws}/logs",
        )
        let output = dispatch(
          @mbtx.definition(
            workspace_root=ws,
            file_state=state,
            bg_runtime=jobs,
            job_dir=ws,
            program_service=service,
            auto_background_after_ms=2000,
          ),
          {
            "source": (
              #|import { "bobzhang/openseek_tools@0.1.0" @tools, "moonbitlang/async" }
              #|async fn main {
              #|  let result = @tools.call("edit", { "path": "note.txt", "start_line": 1, "old_string": "before", "new_string": "after" })
              #|  if result.is_error { fail(result.content) }
              #|  ignore(@tools.call("block", {}))
              #|}
            ),
          },
        )
        assert_true(blocked.val)
        assert_true(output.is_error, msg=output.content)
        assert_eq(@fs.read_file("\{ws}/note.txt").text(), "after\n")
        assert_true(jobs.list().is_empty())
        assert_true(
          output.data
          is Some(
            {
              "ptc_calls": [
                {
                  "name": "edit",
                  "status": "done",
                  "result": { "is_error": false, .. },
                  ..
                },
                { "name": "block", "status": "interrupted", .. },
              ],
              ..
            }
          ),
        )
      })
    })
  })
}
