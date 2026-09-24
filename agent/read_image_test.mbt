///|
async test "direct and unprinted PTC image results reach the next request and replay after source deletion" {
  let root = @fs.tmpdir(prefix="openseek-image-turn-")
  defer @fs.rmdir(root, recursive=true)
  let bytes = @fs.read_file("deepseek/client/testdata/two-colors.png").binary()
  let image = @agent_session.Image::from_bytes(bytes)
  for ptc in [false, true] {
    @fs.write_file("\{root}/picture", bytes)
    @async.with_task_group(group => {
      let bodies : Array[String] = []
      let first = if ptc {
        ptc_payload(
          (
            #|import { "bobzhang/openseek_tools@0.1.0" @tools, "moonbitlang/async" }
            #|async fn main {
            #|  let result = @tools.call("read_image", { "path": "picture" })
            #|  if result.is_error { fail(result.content) }
            #|}
          ),
        )
      } else {
        wait_call_payload("read_image", { "path": "picture" })
      }
      guard goal_check_test_server(group, bodies, [
          first,
          final_answer_payload("seen"),
          final_answer_payload("replayed"),
        ])
        is Some(url) else {
        fail("missing server")
      }
      let session = @agent.run_turn_in_scope(
        runtime=AgentRuntime(workspace_root=root),
        scope=AgentTaskScope(group),
        api_key="offline",
        model=Deepseek(V4Flash),
        api_url=url,
        session=Session(SessionId("read-image"), system_prompt="system"),
        content=Content([Text("inspect picture")]),
        max_steps=3,
        append_item=(session, item) => session.append(item),
      )
      assert_eq(bodies.length(), 2)
      assert_true(bodies[1].contains(image.data_url()), msg=bodies[1])
      @fs.remove("\{root}/picture")
      let mut replay = @agent_session.Session(
        SessionId("read-image"),
        system_prompt="system",
      )
      for event in session.events() {
        let restored : @agent_session.SessionEvent = @json.from_json(
          Json(event),
        )
        replay = replay.append(restored.item())
      }
      ignore(
        @agent.run_turn_in_scope(
          runtime=AgentRuntime(workspace_root=root),
          scope=AgentTaskScope(group),
          api_key="offline",
          model=Deepseek(V4Flash),
          api_url=url,
          session=replay,
          content=Content([Text("inspect again")]),
          max_steps=1,
          append_item=(session, item) => session.append(item),
        ),
      )
      assert_eq(bodies.length(), 3)
      assert_true(bodies[2].contains(image.data_url()))
    })
  }
}
