///|
async test "the agent publishes large files through PTC-only copy" {
  @vfs.with_tmpdir(ws => {
    @async.with_task_group(group => {
      let tools = @agent.build_tools(
        AgentRuntime(workspace_root=ws),
        AgentTaskScope(group),
      )
      assert_true(tools.find("copy") is None)
      guard tools.find("write") is Some(write) else { fail("expected write") }
      let JsonSchema(schema) = write.schema
      guard schema is { "properties": Object(properties), .. } else {
        fail("expected a write schema")
      }
      assert_false(properties.contains("from_file"))
      let arguments : Json = {
        "ptc": true,
        "description": "Publish a generated binary artifact",
        "source": (
          #|import { "moonbitlang/openseek_tools@0.4.2" @tools, "moonbitlang/core/async", "moonbitlang/core/async/fs" }
          #|async fn main {
          #|  let dir = @fs.tmpdir(prefix="generated-")
          #|  defer @fs.remove(dir, recursive=true)
          #|  let path = "\{dir}/artifact.bin"
          #|  let file = @fs.open(path, mode=WriteOnly, create_mode=CreateNew)
          #|  defer file.close()
          #|  let chunk = Bytes::make(65536, b'\xff')
          #|  for _ in 0..<272 { file.write(chunk) }
          #|  file.write(b"\x00\x80\xff")
          #|  file.close()
          #|  let result = @tools.call("copy", { "source": path, "destination": "output/artifact.bin" })
          #|  if result.is_error { fail(result.content) }
          #|  guard result.data is Some({ "bytes": 17825795, .. }) else { fail("wrong byte count") }
          #|  println("published binary artifact")
          #|}
        ),
      }
      guard @agent_tool.execute_tool_call(
          @agent_tool.AgentToolCall::from_arguments("mbtx", arguments),
          tools,
        )
        is Respond(output) else {
        fail("expected an mbtx response")
      }
      assert_false(output.is_error, msg=output.content)
      assert_true(output.content.contains("published binary artifact"))
      let path = "\{ws}/output/artifact.bin"
      assert_eq(@fs.file_size(path), 17825795L)
      guard output.data is Some(data) else { fail("expected PTC trace") }
      assert_true(data.stringify().length() < 10000)
      assert_true(
        data
        is {
          "ptc_calls": [
            {
              "name": "copy",
              "arguments": {
                "source": String(_),
                "destination": "output/artifact.bin",
                ..
              },
              "result": {
                "is_error": false,
                "data": {
                  "bytes": 17825795,
                  "sha256": "f8e7aa8b8f648546c833b38a8b4c5b6be713d58ddcf89cc328b1c5dd61415560",
                  ..
                },
                ..
              },
              ..
            },
          ],
          ..
        },
      )
    })
  })
}
