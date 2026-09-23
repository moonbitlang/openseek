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
            #|import { "bobzhang/openseek_tools@0.1.0" @tools, "moonbitlang/async" }
            #|async fn main {
            #|  @async.sleep(150)
            #|  let result = @tools.call("read_image", { "path": "picture" })
            #|  if result.is_error { fail(result.content) }
            #|}
          ),
        })
        assert_false(output.is_error, msg=output.content.text())
        guard jobs.list() is [job] else { fail("missing background job") }
        jobs.wait_any([job.id])
        @fs.remove("\{ws}/picture")
        for _ in 0..<2 {
          let result = dispatch(@job_output.definition(jobs), {
            "job_id": job.id,
          })
          assert_false(result.is_error, msg=result.content.text())
          assert_true(
            result.content.0 is [Text(_), Text(_), Image(saved)] &&
            saved == image,
          )
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
    assert_true(restored.content.0 is [Text(_), Image(saved)] && saved == image)
  })
}
