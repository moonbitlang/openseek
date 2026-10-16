///|
async test "persistent upload index survives clients, isolates credentials and refreshes rejected files" {
  let home = @fs.tmpdir(prefix="openseek-upload-index-")
  let attachments = @attachments.AttachmentStore(home + "/image-data")
  defer @fs.rmdir(home, recursive=true)
  let reference = attachments.save(@protocol.Image::from_bytes(b"GIF87a"))
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    group.add_defer(() => server.close())
    let uploads : Array[String] = []
    let chats : Array[Json] = []
    let mut reject_next = false
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever((request, body, connection) => {
        let data = body.read_all()
        if request.path.has_suffix("/files") {
          uploads.push(data.text())
          let now = (@env.now() / 1000).to_double()
          connection.send_response(200, "OK")
          connection.write(
            (
              {
                "id": "file-\{uploads.length()}",
                "object": "file",
                "purpose": "user_data",
                "filename": "image.gif",
                "bytes": 6,
                "created_at": now,
                "expires_at": now + 86400,
              } : Json).stringify(),
          )
        } else {
          assert_eq(request.path, "/chat/completions")
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
    let api_url = "http://127.0.0.1:\{server.addr.port()}/chat/completions"
    let client = @client.Client(
      api_key="first-secret",
      thinking=Max,
      api_url~,
      model=Deepseek(V4Flash),
      attachments~,
      upload_index_dir=home + "/deepseek",
    )
    assert_eq(client.upload_attachment(reference), "file-1")
    let resumed = @client.Client(
      api_key="first-secret",
      thinking=Max,
      api_url~,
      model=Deepseek(V4Flash),
      attachments~,
      upload_index_dir=home + "/deepseek",
    )
    assert_eq(resumed.upload_attachment(reference), "file-1")
    assert_eq(uploads.length(), 1)
    let other = @client.Client(
      api_key="other-secret",
      api_url~,
      model=Deepseek(V4Flash),
      attachments~,
      upload_index_dir=home + "/deepseek",
    )
    assert_eq(other.upload_attachment(reference), "file-2")
    let messages = [
      @deepseek.ChatMessage(User, content=[
        Text("before"),
        ImageUrl(url=reference.url()),
        Text("after"),
        ImageUrl(url=reference.url()),
      ]),
    ]
    let summary_client = resumed.with_thinking(No)
    assert_eq(summary_client.thinking, No)
    ignore(summary_client.chat(messages))
    assert_eq(uploads.length(), 2)
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
    ignore(resumed.chat(messages))
    assert_eq(uploads.length(), 3)
    assert_eq(chats.length(), 3)
    assert_eq(resumed.upload_attachment(reference), "file-3")
    assert_eq(other.upload_attachment(reference), "file-2")
    let index_text = @fs.read_file("\{home}/deepseek/files-v1.json").text()
    assert_false(index_text.contains("first-secret"))
    assert_false(index_text.contains("other-secret"))
    assert_false(index_text.contains("GIF87a"))
    // Expired metadata is a cache miss even without restarting the process.
    let index = @json.parse(index_text)
    guard index is { "records": Array(records), .. } else {
      fail("expected index records")
    }
    for record in records {
      if record is Object(fields) {
        fields["expires_at"] = Json("1")
      }
    }
    @fs.write_file(
      "\{home}/deepseek/files-v1.json",
      index.stringify(),
      create_mode=CreateOrTruncate,
    )
    assert_eq(resumed.upload_attachment(reference), "file-4")
    let endpoint = @client.Client(
      api_key="first-secret",
      api_url="http://127.0.0.1:\{server.addr.port()}/v2/chat/completions",
      model=Deepseek(V4Flash),
      attachments~,
      upload_index_dir=home + "/deepseek",
    )
    assert_eq(endpoint.upload_attachment(reference), "file-5")
  }
}

///|
async test "different uploads overlap and commits merge under the short index lock" {
  let home = @fs.tmpdir(prefix="openseek-parallel-upload-")
  let attachments = @attachments.AttachmentStore(home + "/image-data")
  defer @fs.rmdir(home, recursive=true)
  let first = attachments.save(@protocol.Image::from_bytes(b"GIF87aa"))
  let second = attachments.save(@protocol.Image::from_bytes(b"GIF87ab"))
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    group.add_defer(() => server.close())
    let mut count = 0
    let mut active = 0
    let mut peak = 0
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever((_request, body, connection) => {
        ignore(body.read_all())
        count += 1
        let id = count
        active += 1
        if active > peak {
          peak = active
        }
        @async.sleep(30)
        active -= 1
        let now = (@env.now() / 1000).to_double()
        connection.send_response(200, "OK")
        connection.write(
          (
            {
              "id": "parallel-\{id}",
              "object": "file",
              "purpose": "user_data",
              "filename": "image.gif",
              "bytes": 7,
              "created_at": now,
              "expires_at": now + 86400,
            } : Json).stringify(),
        )
      })
    }
    let api_url = "http://127.0.0.1:\{server.addr.port()}/chat/completions"
    let a = @client.Client(
      api_key="key",
      api_url~,
      model=Deepseek(V4Flash),
      attachments~,
      upload_index_dir=home + "/deepseek",
    )
    let b = @client.Client(
      api_key="key",
      api_url~,
      model=Deepseek(V4Flash),
      attachments~,
      upload_index_dir=home + "/deepseek",
    )
    let ta = group.spawn(() => a.upload_attachment(first))
    let tb = group.spawn(() => b.upload_attachment(second))
    let ida = ta.wait()
    let idb = tb.wait()
    assert_true(ida != idb)
    assert_eq(peak, 2)
    assert_eq(a.upload_attachment(first), ida)
    assert_eq(b.upload_attachment(second), idb)
    assert_eq(count, 2)
    let index = @json.parse(
      @fs.read_file("\{home}/deepseek/files-v1.json").text(),
    )
    assert_true(
      index is { "records": Array(records), .. } && records.length() == 2,
    )
    let same = attachments.save(@protocol.Image::from_bytes(b"GIF87ac"))
    let left = group.spawn(() => a.upload_attachment(same))
    let right = group.spawn(() => b.upload_attachment(same))
    assert_eq(left.wait(), right.wait())
    let merged = @json.parse(
      @fs.read_file("\{home}/deepseek/files-v1.json").text(),
    )
    assert_true(
      merged is { "records": Array(records), .. } && records.length() == 3,
    )
  }
}
