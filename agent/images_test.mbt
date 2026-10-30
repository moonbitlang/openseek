///|
/// Image-aware provider fixture: uploads do not consume chat response slots.
async fn image_chat_test_server(
  group : @async.TaskGroup[Unit],
  bodies : Array[String],
  uploads : Array[String],
  responses : Array[String],
  image_bytes~ : Int32 = 8,
) -> String {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  group.add_defer(() => server.close())
  group.spawn_bg(no_wait=true) <| () => {
    server.run_forever((request, body, connection) => {
      let data = body.read_all()
      if request.path.has_suffix("/files") {
        uploads.push(request.path)
        connection.send_response(200, "OK")
        connection.write(
          (
            {
              "id": "file-test-\{uploads.length()}",
              "object": "file",
              "purpose": "user_data",
              "filename": "image.png",
              "bytes": image_bytes,
              "created_at": 1,
              "expires_at": 32503680000.0,
            } : Json).stringify(),
        )
      } else {
        assert_eq(request.path, "/chat/completions")
        bodies.push(data.text())
        connection.send_response(200, "OK", extra_headers={
          "Content-Type": "text/event-stream",
        })
        connection.write(
          "data: \{responses[bodies.length() - 1]}\n\ndata: [DONE]\n\n",
        )
      }
    })
  }
  "http://127.0.0.1:\{server.addr.port()}/chat/completions"
}

///|
async test "images are admitted before append without reordering queued or arriving user input" {
  let home = @fs.tmpdir(prefix="openseek-agent-admission-")
  let attachments = @attachments.AttachmentStore(home + "/attachments")
  defer @fs.rmdir(home, recursive=true)
  let image = @agent_session.Image::from_bytes(
    @fs.read_file("deepseek/client/testdata/two-colors.png").binary(),
  )
  @async.with_task_group() <| group => {
    let bodies : Array[String] = []
    let uploads : Array[String] = []
    let url = image_chat_test_server(
      group,
      bodies,
      uploads,
      [
        final_answer_payload("first"),
        final_answer_payload("second"),
        final_answer_payload("replay"),
      ],
      image_bytes=image.bytes.length(),
    )
    let runtime = @agent_runtime.AgentRuntime()
    runtime.queue_steer(
      Prompt(Content([Text("A"), Image(image)]), submission_id=Some("A")),
    )
    runtime.queue_steer(Notice("notice"))
    runtime.queue_steer(
      Prompt(Content([Text("B"), Image(image)]), submission_id=Some("B")),
    )
    let recorded : Array[@agent_session.SessionItem] = []
    let first = @agent.run_turn_in_scope(
      client=Client(
        api_key="test",
        model=Deepseek(V4Flash),
        api_url=url,
        attachments~,
        upload_index_dir=home + "/deepseek",
        thinking=Max,
      ),
      admit_content=content => attachments.admit(content),
      runtime~,
      scope=AgentTaskScope(group),
      session=Session(SessionId("images"), system_prompt="system"),
      content=Content([Image(image)]),
      submission_id="initial",
      append_item=(session, item) => {
        if item is User(user) {
          // The callback already receives references, before persistence runs.
          assert_false(user.content().0.any(part => part is Image(_)))
          if user.submission_id() == Some("A") {
            // Arrives while this drained batch is being appended: C must stay
            // behind B and must not replace A in the live request buffer.
            runtime.queue_steer(
              Prompt(
                Content([Text("C"), Image(image)]),
                submission_id=Some("C"),
              ),
            )
          }
        }
        recorded.push(item)
        session.append(item)
      },
      max_steps=3,
    )
    assert_eq(
      first.events().iter().map(event => event.item()).to_array(),
      recorded,
    )
    let users = [
      for item in recorded if item is User(user) => user.submission_id()
    ]
    assert_eq(users, [Some("initial"), Some("A"), Some("B"), Some("C")])
    assert_eq(bodies.length(), 2)
    assert_false(bodies[0].contains("\"text\":\"C\""))
    for index, body in bodies {
      guard @json.parse(body) is { "messages": Array(messages), .. } else {
        fail("missing messages")
      }
      let user_contents = [
        for message in messages if message
        is { "role": "user", "content": content, .. } => content
      ]
      let file : Json = { "type": "file", "file_id": "file-test-1" }
      let expected : Array[Json] = [
        [file],
        [{ "type": "text", "text": "A" }, file],
        "notice",
        [{ "type": "text", "text": "B" }, file],
      ]
      if index == 1 {
        expected.push([{ "type": "text", "text": "C" }, file])
      }
      assert_eq(user_contents, expected)
      assert_false(body.contains(image.data_url()))
    }
    let resumed : @agent_session.Session = @json.from_json(Json(first))
    ignore(
      @agent.run_turn_in_scope(
        client=Client(
          api_key="test",
          model=Deepseek(V4Flash),
          api_url=url,
          attachments~,
          upload_index_dir=home + "/deepseek",
          thinking=Max,
        ),
        admit_content=content => attachments.admit(content),
        runtime=AgentRuntime(),
        scope=AgentTaskScope(group),
        session=resumed,
        content=Content([Text("replay")]),
        append_item=(session, item) => session.append(item),
        max_steps=1,
      ),
    )
    assert_eq(uploads.length(), 1)
    assert_eq(bodies.length(), 3)
    assert_true(bodies[2].contains("file-test-1"))
  }
}

///|
async test "failed initial admission never reaches the session append hook" {
  let initial = @agent_session.Session(
    SessionId("admission-failure"),
    system_prompt="system",
  )
  let image = @agent_session.Image::from_bytes(b"GIF87a")
  let appended : Array[@agent_session.SessionItem] = []
  let admitted : Array[@agent_session.Content] = []
  @async.with_task_group() <| group => {
    try
      @agent.run_turn_in_scope(
        runtime=AgentRuntime(),
        scope=AgentTaskScope(group),
        client=Client(api_key="unused", model=Deepseek(V4Flash)),
        admit_content=content => {
          admitted.push(content)
          fail("attachment store unavailable")
        },
        session=initial,
        content=Content([Image(image)]),
        append_item=(session, item) => {
          appended.push(item)
          session.append(item)
        },
        max_steps=0,
      )
    catch {
      error => assert_true("\{error}".contains("attachment store unavailable"))
    } noraise {
      _ => fail("expected admission failure")
    }
  }
  assert_eq(admitted, [Content([Image(image)])])
  assert_eq(appended.length(), 0)
  assert_eq(initial.events().length(), 0)
}
