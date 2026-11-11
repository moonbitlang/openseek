///|
async fn upload(
  client : @client.Client,
  attachments : @attachments.AttachmentStore,
  reference : @protocol.ImageRef,
) -> String {
  guard client
    .upload_attachments(attachments, [reference])
    .get(reference.attachment_id)
    is Some(file_id) else {
    fail("missing file id")
  }
  file_id
}

///|
async test "persistent upload index survives clients, isolates credentials and forgets rejected files" {
  let home = @fs.tmpdir(prefix="openseek-upload-index-")
  let attachments = @attachments.AttachmentStore(home + "/image-data")
  defer @fs.rmdir(home, recursive=true)
  let reference = attachments.save(@protocol.Image::from_bytes(b"GIF87a"))
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    group.add_defer(() => server.close())
    let uploads : Array[String] = []
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever((request, body, connection) => {
        let data = body.read_all()
        assert_true(request.path.has_suffix("/files"))
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
      })
    }
    let api_url = "http://127.0.0.1:\{server.addr.port()}/chat/completions"
    let client = @client.Client(
      api_key="first-secret",
      api_url~,
      model=Deepseek(V4Flash),
    )
    assert_eq(upload(client, attachments, reference), "file-1")
    let resumed = @client.Client(
      api_key="first-secret",
      api_url~,
      model=Deepseek(V4Flash),
    )
    assert_eq(upload(resumed, attachments, reference), "file-1")
    assert_eq(uploads.length(), 1)
    let other = @client.Client(
      api_key="other-secret",
      api_url~,
      model=Deepseek(V4Flash),
    )
    assert_eq(upload(other, attachments, reference), "file-2")
    // A cached id is returned without touching the local object.
    @fs.remove(attachments.path(reference))
    assert_eq(upload(resumed, attachments, reference), "file-1")
    ignore(attachments.save(@protocol.Image::from_bytes(b"GIF87a")))
    resumed.forget_uploads(attachments, ["file-1"])
    assert_eq(upload(resumed, attachments, reference), "file-3")
    assert_eq(upload(other, attachments, reference), "file-2")
    // Index updates and their lock stay with the configured image objects.
    let index_text = @fs.read_file("\{home}/image-data/files-v1.json").text()
    assert_true(@fs.exists("\{home}/image-data/files-v1.lock"))
    assert_false(index_text.contains("first-secret"))
    assert_false(index_text.contains("other-secret"))
    assert_false(index_text.contains("GIF87a"))
    // Expired metadata is a cache miss even without restarting the process.
    let records = @json.parse(index_text)
    guard records is Array(records) else { fail("expected index records") }
    for record in records {
      if record is Object(fields) {
        fields["expires_at"] = Json("1")
      }
    }
    @fs.write_file(
      "\{home}/image-data/files-v1.json",
      Json(records).stringify(),
      create_mode=CreateOrTruncate,
    )
    assert_eq(upload(resumed, attachments, reference), "file-4")
    // An unreadable index is an empty cache, not an error.
    @fs.write_file(
      "\{home}/image-data/files-v1.json",
      "not json",
      create_mode=CreateOrTruncate,
    )
    assert_eq(upload(resumed, attachments, reference), "file-5")
    let endpoint = @client.Client(
      api_key="first-secret",
      api_url="http://127.0.0.1:\{server.addr.port()}/v2/chat/completions",
      model=Deepseek(V4Flash),
    )
    assert_eq(upload(endpoint, attachments, reference), "file-6")
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
    let a = @client.Client(api_key="key", api_url~, model=Deepseek(V4Flash))
    let b = @client.Client(api_key="key", api_url~, model=Deepseek(V4Flash))
    let ta = group.spawn(() => upload(a, attachments, first))
    let tb = group.spawn(() => upload(b, attachments, second))
    let ida = ta.wait()
    let idb = tb.wait()
    assert_true(ida != idb)
    assert_eq(peak, 2)
    assert_eq(upload(a, attachments, first), ida)
    assert_eq(upload(b, attachments, second), idb)
    assert_eq(count, 2)
    let index = @json.parse(
      @fs.read_file("\{home}/image-data/files-v1.json").text(),
    )
    assert_true(index is Array(records) && records.length() == 2)
    let same = attachments.save(@protocol.Image::from_bytes(b"GIF87ac"))
    let left = group.spawn(() => upload(a, attachments, same))
    let right = group.spawn(() => upload(b, attachments, same))
    assert_eq(left.wait(), right.wait())
    let merged = @json.parse(
      @fs.read_file("\{home}/image-data/files-v1.json").text(),
    )
    assert_true(merged is Array(records) && records.length() == 3)
  }
}

///|
async test "one batch uploads distinct misses concurrently" {
  let home = @fs.tmpdir(prefix="openseek-batch-upload-")
  let attachments = @attachments.AttachmentStore(home + "/image-data")
  defer @fs.rmdir(home, recursive=true)
  let first = attachments.save(@protocol.Image::from_bytes(b"GIF87aba"))
  let second = attachments.save(@protocol.Image::from_bytes(b"GIF87abb"))
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    group.add_defer(() => server.close())
    let mut count = 0
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever((_request, body, connection) => {
        ignore(body.read_all())
        count += 1
        let now = (@env.now() / 1000).to_double()
        connection.send_response(200, "OK")
        connection.write(
          (
            {
              "id": "batch-\{count}",
              "object": "file",
              "purpose": "user_data",
              "filename": "image.gif",
              "bytes": 8,
              "created_at": now,
              "expires_at": now + 86400,
            } : Json).stringify(),
        )
      })
    }
    let client = @client.Client(
      api_key="key",
      api_url="http://127.0.0.1:\{server.addr.port()}/chat/completions",
      model=Deepseek(V4Flash),
    )
    let ids = client.upload_attachments(attachments, [first, second])
    assert_eq(count, 2)
    assert_eq(ids.length(), 2)
    assert_true(ids.get(first.attachment_id) != ids.get(second.attachment_id))
    assert_eq(client.upload_attachments(attachments, [second, first]), ids)
    assert_eq(count, 2)
  }
}
