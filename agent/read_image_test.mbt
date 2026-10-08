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
            #|import { "moonbitlang/openseek_tools@0.2.0" @tools, "moonbitlang/async" }
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

///|
async test "tool text is bounded before durable and API content parts are assembled" {
  let image = @agent_session.Image::from_bytes(b"\x89PNG\r\n\x1a\n")
  // The emoji straddles the truncation boundary; neither durable nor wire text
  // may retain half of its surrogate pair. Both images must remain intact.
  let marker = "\n[truncated: result exceeded the 60000-char cap]"
  let text = String::make(60000 - marker.length() - 1, 'x') +
    "😀" +
    String::make(100, 'y')
  @async.with_task_group(group => {
    let bodies : Array[String] = []
    guard goal_check_test_server(group, bodies, [
        wait_call_payload("picture", {}),
        final_answer_payload("seen"),
      ])
      is Some(url) else {
      fail("missing server")
    }
    let runtime = @agent_runtime.AgentRuntime()
    let scope = @agent_runtime.AgentTaskScope(group)
    let tools = @agent.build_tools(runtime, scope, extra_tools=[
      AgentToolDefinition(
        name="picture",
        description="picture",
        schema=JsonSchema({}),
        execute=Sync(_ => @agent_tool.respond(text, images=[image, image])),
      ),
    ])
    let session = @agent.run_turn_in_scope(
      runtime~,
      scope~,
      tools~,
      api_key="offline",
      model=Deepseek(V4Flash),
      api_url=url,
      session=Session(SessionId("bounded-tool-images"), system_prompt="system"),
      content=Content([Text("inspect")]),
      max_steps=3,
      append_item=(session, item) => session.append(item),
    )
    let results = [
      for event in session.events() if event.item() is Tool(result) &&
      result.tool_name() == "picture" => result.content()
    ]
    guard results is [Content([Text(saved_text), Image(first), Image(second)])] else {
      fail("expected text followed by both images")
    }
    assert_eq(first, image)
    assert_eq(second, image)
    assert_true(saved_text.length() <= 60000)
    assert_true(saved_text.has_suffix(marker))
    assert_false(saved_text.contains("😀"))
    assert_eq(bodies.length(), 2)
    guard @json.parse(bodies[1]) is { "messages": Array(messages), .. } else {
      fail("missing API messages")
    }
    let results = messages.filter(message => message is { "role": "tool", .. })
    assert_true(
      results
      is [
        {
          "content": [
            { "type": "text", "text": String(wire_text), .. },
            {
              "type": "image_url",
              "image_url": { "url": String(first_url), .. },
              ..
            },
            {
              "type": "image_url",
              "image_url": { "url": String(second_url), .. },
              ..
            },
          ],
          ..
        },
      ] &&
      wire_text == saved_text &&
      first_url == image.data_url() &&
      second_url == image.data_url(),
    )
  })
}
