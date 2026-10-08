///|
async test "background PTC images survive source removal job completion repeat reads and runtime shutdown" {
  let bytes = @fs.read_file("deepseek/client/testdata/two-colors.png").binary()
  let image = @openseek_protocol.Image::from_bytes(bytes)
  @vfs.with_tmpdir(ws => {
    let retained = @async.with_timeout(30000, () => {
      @async.with_task_group(group => {
        @fs.write_file("\{ws}/picture", bytes)
        let tools = @agent_tool.Tools([
          @read_image.definition(workspace_root=ws),
        ])
        tools.set_image_input_supported(true)
        let service = @ptc.Service::start(group, tools, image_directory=() => {
          Some(ws)
        })
        let jobs = @bgjobs.BgJobRuntime(
          AgentTaskScope(group),
          spill_dir=ws,
          persistent_logs=true,
        )
        let definition = @mbtx.definition(
          workspace_root=ws,
          bg_runtime=jobs,
          job_dir=ws,
          program_service=service,
          auto_background_after_ms=1,
        )
        let output = dispatch(definition, {
          "source": (
            #|import { "moonbitlang/openseek_tools@0.2.0" @tools, "moonbitlang/async" }
            #|async fn main {
            #|  @async.sleep(150)
            #|  let result = @tools.call("read_image", { "path": "picture" })
            #|  if result.is_error { fail(result.content) }
            #|}
          ),
        })
        assert_false(output.is_error, msg=output.content)
        guard jobs.list() is [job] else { fail("missing background job") }
        jobs.wait_any([job.id])
        @fs.remove("\{ws}/picture")
        for _ in 0..<2 {
          let result = dispatch(@job_output.definition(jobs), {
            "job_id": job.id,
          })
          assert_false(result.is_error, msg=result.content)
          assert_true(result.images is [saved] && saved == image)
        }
        let saved : @openseek_protocol.JobRecord = @json.from_json(
          @json.parse(
            @fs.read_file(
              "\{ws}/\{@openseek_protocol.job_storage_name(job.id)}.json",
            ).text(),
          ),
        )
        guard saved.data
          is Some({ "ptc_images": [{ "path": String(path), .. }], .. }) else {
          fail("missing durable image path")
        }
        path
      })
    })
    let tool = @read_image.definition(workspace_root=ws)
    let restored = dispatch(tool, { "path": retained })
    assert_true(restored.images is [saved] && saved == image)
  })
}

///|
async test "foreground PTC retires image files and trace paths on success failure and cancellation" {
  let bytes = @fs.read_file("deepseek/client/testdata/two-colors.png").binary()
  let image = @openseek_protocol.Image::from_bytes(bytes)
  for outcome in ["success", "failure", "cancel"] {
    @vfs.with_tmpdir(ws => {
      @async.with_timeout(30000, () => {
        @async.with_task_group(group => {
          @fs.write_file("\{ws}/picture", bytes)
          let ready : @async.Queue[Unit] = Queue(kind=Unbounded)
          let tools = @agent_tool.Tools([
            @read_image.definition(workspace_root=ws),
            AgentToolDefinition(
              name="ready",
              description="signal completed image capture",
              schema=JsonSchema({}),
              program_callable=true,
              execute=Async(_ => {
                ready.put(())
                @agent_tool.respond("ready")
              }),
            ),
          ])
          tools.set_image_input_supported(true)
          let service = @ptc.Service::start(group, tools, image_directory=() => {
            Some(ws)
          })
          let jobs = @bgjobs.BgJobRuntime(
            AgentTaskScope(group),
            spill_dir=ws,
            persistent_logs=true,
          )
          let traces : Array[Json] = []
          let retained = Ref([])
          let definition = @mbtx.definition(
            workspace_root=ws,
            bg_runtime=jobs,
            job_dir=ws,
            program_service=service,
            auto_background_after_ms=60000,
            on_program_trace=trace => traces.push(trace),
            on_program_output=output => retained.val = output.images,
          )
          let ending = match outcome {
            "failure" => "fail(\"script failed after image capture\")"
            "cancel" => "@async.sleep(60000)"
            _ => "()"
          }
          let source =
            $|import { "moonbitlang/openseek_tools@0.2.0" @tools, "moonbitlang/async" }
            $|async fn main {
            $|  let result = @tools.call("read_image", { "path": "picture" })
            $|  if result.is_error { fail(result.content) }
            $|  ignore(@tools.call("ready", {}))
            $|  \{ending}
            $|}
          let operation = group.spawn(() => {
            dispatch(definition, { "source": source })
          })
          if outcome == "cancel" {
            ready.get()
            operation.cancel()
            try operation.wait() |> ignore catch {
              @async.WaitedTaskAlreadyCancelled => ()
              error => raise error
            } noraise {
              _ => fail("expected cancellation")
            }
          } else {
            let output = operation.wait()
            assert_eq(output.is_error, outcome == "failure", msg=output.content)
            assert_eq(output.images, [image])
            assert_true(output.data is Some({ "ptc_images"? : None, .. }))
          }
          // Capture happened before cleanup; all advertised files are now gone.
          let paths : Array[String] = []
          for trace in traces {
            if trace is { "ptc_images": Array(entries), .. } {
              for entry in entries {
                guard entry is { "path": String(path), .. } else {
                  fail("missing snapshot path")
                }
                paths.push(path)
              }
            }
          }
          assert_false(paths.is_empty())
          for path in paths {
            assert_false(@fs.exists(path), msg=path)
          }
          assert_true(traces.last() is Some({ "ptc_images"? : None, .. }))
          assert_eq(retained.val, [image])
          assert_eq(@fs.read_file("\{ws}/picture").binary(), bytes)
          assert_true(jobs.list().is_empty())
        })
      })
    })
  }
}
