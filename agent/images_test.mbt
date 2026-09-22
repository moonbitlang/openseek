///|
async test "initial and image-only steering input survive replay and reach the provider" {
  let bytes = @fs.read_file("deepseek/client/testdata/two-colors.png").binary()
  let image = @agent_session.Image::from_data_url(
    @agent_session.Image::from_bytes(bytes).data_url(),
  )
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    group.add_defer(() => server.close())
    let requests : Array[Json] = []
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever((request, body, connection) => {
        let data = body.read_all()
        assert_eq(request.path, "/chat/completions")
        let request = @json.parse(data.text())
        requests.push(request)
        connection.send_response(200, "OK", extra_headers={
          "Content-Type": "text/event-stream",
        })
        connection.write(
          "data: {\"choices\":[{\"delta\":{\"content\":\"seen\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n",
        )
      })
    }
    let runtime = @agent_runtime.AgentRuntime()
    let scope = @agent_runtime.AgentTaskScope(group)
    runtime.queue_steer(
      Prompt(Content([Image(image)]), submission_id=Some("image-steer")),
    )
    let first = @agent.run_turn_in_scope(
      runtime~,
      scope~,
      api_key="test",
      model=Deepseek(V4Flash),
      session=Session(SessionId("desktop-images"), system_prompt="system"),
      content=Content([Image(image)]),
      submission_id="image-submit",
      append_item=(session, item) => session.append(item),
      max_steps=2,
      api_url="http://127.0.0.1:\{server.addr.port()}/chat/completions",
    )
    assert_eq(requests.length(), 1)
    let mut restored = @agent_session.Session(
      SessionId("desktop-images"),
      system_prompt="system",
    )
    for event in first.events() {
      let decoded : @agent_session.SessionEvent = @json.from_json(Json(event))
      restored = restored.append(decoded.item())
    }
    for event in restored.events().iter().take(2) {
      guard event.item() is User(user) else { fail("expected image user") }
      assert_true(user.content().0 is [Image(saved)] && saved == image)
    }
    let _ = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope~,
      api_key="test",
      model=Deepseek(V4Flash),
      session=restored,
      content=Content([Text("Describe again")]),
      append_item=(session, item) => session.append(item),
      max_steps=2,
      api_url="http://127.0.0.1:\{server.addr.port()}/chat/completions",
    )
    assert_eq(requests.length(), 2)
    for index, request in requests {
      guard request is { "messages": Array(messages), .. } else {
        fail("missing model messages")
      }
      let users = messages.filter(message => message is { "role": "user", .. })
      assert_eq(users.length(), index + 2)
      for message in users[:2] {
        assert_true(
          message is { "content": Array(parts), .. } &&
          parts
          is [
            { "type": "image_url", "image_url": { "url": String(url), .. }, .. },
          ] &&
          url == image.data_url(),
        )
      }
    }
  }
}
