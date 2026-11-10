///|
async test "image references resolve to file ids and rejected files upload once more" {
  let home = @fs.tmpdir(prefix="openseek-model-request-")
  let attachments = @attachments.AttachmentStore(home + "/image-data")
  defer @fs.rmdir(home, recursive=true)
  let reference = attachments.save(@protocol.Image::from_bytes(b"GIF87a"))
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    group.add_defer(() => server.close())
    let mut uploads = 0
    let chats : Array[Json] = []
    let mut reject_next = false
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever((request, body, connection) => {
        let data = body.read_all()
        if request.path.has_suffix("/files") {
          uploads += 1
          let now = (@env.now() / 1000).to_double()
          connection.send_response(200, "OK")
          connection.write(
            (
              {
                "id": "file-\{uploads}",
                "object": "file",
                "purpose": "user_data",
                "filename": "image.gif",
                "bytes": 6,
                "created_at": now,
                "expires_at": now + 86400,
              } : Json).stringify(),
          )
        } else {
          chats.push(@json.parse(data.text()))
          if reject_next {
            reject_next = false
            connection.send_response(400, "Bad Request")
            connection.write("{\"error\":{\"code\":\"file_expired\"}}")
          } else {
            connection.send_response(200, "OK")
            connection.write(
              "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"seen\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":1,\"completion_tokens\":1,\"total_tokens\":2}}",
            )
          }
        }
      })
    }
    let client = @client.Client(
      api_key="secret",
      api_url="http://127.0.0.1:\{server.addr.port()}/chat/completions",
      model=Deepseek(V4Flash),
    )
    let messages = [
      @agent_session.ModelMessage(User, content=[
        Text("before"),
        ImageRef(reference),
        Text("after"),
        ImageRef(reference),
      ]),
    ]
    ignore(@request.chat(client, messages, attachments~))
    assert_eq(uploads, 1)
    assert_true(
      chats[0]
      is {
        "messages": [
          {
            "content": [
              { "text": "before", .. },
              { "type": "file", "file_id": "file-1", .. },
              { "text": "after", .. },
              { "type": "file", "file_id": "file-1", .. },
            ],
            ..
          },
        ],
        ..
      },
    )
    reject_next = true
    ignore(@request.chat(client, messages, attachments~))
    assert_eq(uploads, 2)
    assert_eq(chats.length(), 3)
    assert_true(
      chats[2]
      is {
        "messages": [{ "content": [_, { "file_id": "file-2", .. }, ..], .. }],
        ..
      },
    )
    // Text-only requests never resolve a store.
    ignore(@request.chat(client, [ModelMessage(User, content=[Text("plain")])]))
    assert_eq(uploads, 2)
  }
}
