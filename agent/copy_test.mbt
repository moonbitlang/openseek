///|
async test "the agent publishes binary artifacts through PTC-only copy" {
  @vfs.with_tmpdir(ws => {
    @async.with_task_group(group => {
      let scratch = "\{ws}/.openseek/scratch"
      let tools = @agent.build_tools(
        AgentRuntime(workspace_root=ws),
        AgentTaskScope(group),
        session_scratch_dir=scratch,
      )
      assert_true(tools.find("copy") is None)
      let arguments : Json = {
        "ptc": true,
        "args": [scratch],
        "description": "Publish a generated binary artifact",
        "source": (
          #|import { "moonbitlang/openseek_tools@0.4.2" @tools, "moonbitlang/core/async", "moonbitlang/core/async/fs", "moonbitlang/core/env" }
          #|async fn main {
          #|  let path = "\{@env.args()[1]}/artifact.bin"
          #|  let file = @fs.open(path, mode=WriteOnly, create_mode=CreateNew)
          #|  defer file.close()
          #|  let chunk = Bytes::make(65536, b'\xff')
          #|  for _ in 0..<4 { file.write(chunk) }
          #|  file.write(b"\x00\x80\xff")
          #|  file.close()
          #|  let result = @tools.call("copy", { "source": path, "destination": "output/artifact.bin" })
          #|  if result.is_error { fail(result.content) }
          #|  guard result.data is Some({ "bytes": 262147, .. }) else { fail("wrong byte count") }
          #|  let blocked = @tools.call("copy", { "source": path, "destination": "output/API.MBTI" })
          #|  guard blocked.is_error else { fail("copy accepted a MoonBit destination") }
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
      assert_eq(@fs.file_size(path), 262147L)
      assert_false(@fs.exists("\{ws}/output/API.MBTI"))
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
                "data": { "bytes": 262147, "sha256": String(digest), .. },
                ..
              },
              ..
            },
            { "name": "copy", "result": { "is_error": true, .. }, .. },
          ],
          ..
        } &&
        digest.length() == 64,
      )
    })
  })
}
