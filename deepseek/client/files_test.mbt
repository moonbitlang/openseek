///|
/// A test server that captures the exact multipart request and lets each case
/// supply its own Files API response without contacting a real provider.
priv struct UploadServer {
  server : @http.Server
  requests : Array[(@http.Request, Bytes)]
}

///|
async fn UploadServer::start(
  group : @async.TaskGroup[Unit],
  status? : Int = 200,
  response~ : String,
  delay_ms? : Int = 0,
) -> UploadServer {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  group.add_defer(() => server.close())
  let requests = []
  group.spawn_bg(no_wait=true) <| () => {
    server.run_forever((_request, body, connection) => {
      requests.push((_request, body.read_all().binary()))
      if delay_ms > 0 {
        @async.sleep(delay_ms)
      }
      connection.send_response(status, "Test", extra_headers={
        "Content-Type": "application/json",
      })
      connection.write(response)
    })
  }
  { server, requests, }
}

///|
fn UploadServer::client(self : UploadServer) -> @client.Client {
  Client(
    api_key="upload-test-key",
    api_url="http://127.0.0.1:\{self.server.addr.port()}/v1/chat/completions",
    retry_attempts=3,
    retry_backoff_ms=1,
  )
}

///|
async test "image upload sends multipart bytes then file ID can enter chat" {
  @async.with_task_group() <| group => {
    // The mock tests the provider's fields and byte preservation. Generic
    // multipart delimiter and header encoding tests belong to form_data.
    let bytes = b"\x89PNG\r\n\x1a\n\x00\xffimage-content"
    let server = UploadServer::start(
      group,
      response=(
        {
          "id": "file-api-test",
          "object": "file",
          "bytes": bytes.length(),
          "created_at": 1000,
          "filename": "test.png",
          "purpose": "user_data",
          "expires_at": 4600,
        } : Json).stringify(),
    )
    let uploaded = server
      .client()
      .upload_image(bytes, filename="test.png", expires_after_seconds=3600)
    assert_eq(uploaded.id, "file-api-test")
    assert_eq(uploaded.bytes, bytes.length().to_int64())
    assert_eq(uploaded.expires_at, Some(4600L))
    assert_eq(server.requests.length(), 1)
    let (request, body) = server.requests[0]
    assert_true(request.meth is Post)
    assert_eq(request.path, "/v1/files")
    assert_eq(
      request.headers.get("Authorization"),
      Some("Bearer upload-test-key"),
    )
    guard request.headers.get("Content-Type") is Some(content_type) &&
      content_type.strip_prefix("multipart/form-data; boundary=")
      is Some(boundary) else {
      fail("expected multipart content type")
    }
    let prefix = "--\{boundary}\r\nContent-Disposition: form-data; name=\"purpose\"\r\n\r\nuser_data\r\n--\{boundary}\r\nContent-Disposition: form-data; name=\"expires_after[anchor]\"\r\n\r\ncreated_at\r\n--\{boundary}\r\nContent-Disposition: form-data; name=\"expires_after[seconds]\"\r\n\r\n3600\r\n--\{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"test.png\"\r\nContent-Type: image/png\r\n\r\n"
    assert_eq(
      body,
      @utf8.encode(prefix) + bytes + @utf8.encode("\r\n--\{boundary}--\r\n"),
    )
    guard @deepseek.encode_chat_request([
        ChatMessage(User, content=[Text("describe"), File(file_id=uploaded.id)]),
      ])
      is { "messages": [message], .. } else {
      fail("expected uploaded image in the chat request")
    }
    json_inspect(message, content={
      "role": "user",
      "content": [
        { "type": "text", "text": "describe" },
        { "type": "file", "file_id": "file-api-test" },
      ],
    })
  }
}

///|
async test "image upload preserves supported formats and omits permanent expiry" {
  for
    (bytes, media_type) in [
      (b"\xff\xd8\xff\x00", "image/jpeg"),
      (b"GIF89a\x00", "image/gif"),
      (b"RIFF\x00\x00\x00\x00WEBP", "image/webp"),
    ] {
    @async.with_task_group() <| group => {
      let server = UploadServer::start(
        group,
        response=(
          {
            "id": "file-api-test",
            "object": "file",
            "bytes": bytes.length(),
            "created_at": 1000,
            "filename": "image",
            "purpose": "user_data",
          } : Json).stringify(),
      )
      let uploaded = server.client().upload_image(bytes, filename="image")
      assert_eq(uploaded.expires_at, None)
      let body = server.requests[0].1
      assert_true(
        body.find(@utf8.encode("Content-Type: \{media_type}\r\n")) is Some(_),
      )
      assert_true(body.find(b"expires_after") is None)
      assert_true(body.find(bytes) is Some(_))
    }
  }
}

///|
async test "image upload retains HTTP errors without retrying POST" {
  for status in [400, 429, 503] {
    @async.with_task_group() <| group => {
      let server = UploadServer::start(
        group,
        status~,
        response="quota exceeded",
      )
      try server.client().upload_image(b"GIF87a", filename="image.gif") catch {
        @client.HttpStatus(code, body) => {
          assert_eq(code, status)
          assert_eq(body, "quota exceeded")
        }
        error => raise error
      } noraise {
        _ => fail("expected upload failure")
      }
      assert_eq(server.requests.length(), 1)
    }
  }
}

///|
async test "image upload rejects invalid input before connecting" {
  let client = @client.Client(
    api_key="unused",
    api_url="http://127.0.0.1:1/chat/completions",
  )
  for
    (bytes, filename, expiry, expected) in [
      (b"not an image", "image.png", 3600, @client.UnsupportedImageFormat),
      (b"GIF87a", "bad\r\nname", 3600, InvalidFilename),
      (b"GIF87a", "../image.gif", 3600, InvalidFilename),
      (b"GIF87a", "control\u0001.gif", 3600, InvalidFilename),
      (b"GIF87a", "quote\".gif", 3600, InvalidFilename),
      (b"GIF87a", "image.gif", 3599, InvalidExpirySeconds(3599)),
      (b"GIF87a", "image.gif", 2592001, InvalidExpirySeconds(2592001)),
      (
        Bytes::make(64 * 1024 * 1024 + 1, b'\x00'),
        "large.gif",
        3600,
        ImageTooLarge(bytes=64 * 1024 * 1024 + 1, limit=64 * 1024 * 1024),
      ),
    ] {
    let actual : @client.FileUploadError = try
      client.upload_image(bytes, filename~, expires_after_seconds=expiry)
    catch {
      @client.UnsupportedImageFormat => UnsupportedImageFormat
      @client.InvalidFilename => InvalidFilename
      @client.InvalidExpirySeconds(seconds) => InvalidExpirySeconds(seconds)
      @client.ImageTooLarge(bytes~, limit~) => ImageTooLarge(bytes~, limit~)
      error => raise error
    } noraise {
      _ => fail("expected input validation to reject upload")
    }
    assert_eq(actual, expected)
  }
}

///|
async test "image upload preserves typed JSON decoding errors" {
  for response in ["not JSON", "{}"] {
    @async.with_task_group() <| group => {
      let server = UploadServer::start(group, response~)
      try server.client().upload_image(b"GIF87a", filename="image.gif") catch {
        @client.MalformedResponseJson(error) => {
          assert_eq(response, "not JSON")
          assert_true(error is InvalidChar(_, _))
        }
        @client.InvalidResponseShape(error) => {
          assert_eq(response, "{}")
          assert_true(error is JsonDecodeError(_))
        }
        error => raise error
      } noraise {
        _ => fail("expected invalid success metadata to fail")
      }
      assert_eq(server.requests.length(), 1)
    }
  }
}

///|
async test "image upload identifies invalid response fields with typed values" {
  let cases : Array[(String, Json?, @client.FileUploadError)] = [
    ("object", Some("other"), UnexpectedFileObject("other")),
    ("purpose", Some("other"), UnexpectedFilePurpose("other")),
    ("id", Some(" "), MissingFileId),
    ("filename", Some(" "), MissingFilename),
    ("bytes", Some(99), FileByteCountMismatch(expected=6, actual=99)),
    ("created_at", Some(-1), InvalidCreatedAt(-1)),
    ("created_at", Some(1000.5), InvalidCreatedAt(1000.5)),
    (
      "created_at",
      Some(9007199254740992.0),
      InvalidCreatedAt(9007199254740992.0),
    ),
    ("expires_at", Some(1000), InvalidExpiresAt(1000)),
    ("expires_at", Some(4600.5), InvalidExpiresAt(4600.5)),
    (
      "expires_at",
      Some(9007199254740992.0),
      InvalidExpiresAt(9007199254740992.0),
    ),
    ("expires_at", None, MissingExpiresAt),
  ]
  for (field, value, expected) in cases {
    @async.with_task_group() <| group => {
      let fields : Map[String, Json] = {
        "id": "file-api-test",
        "object": "file",
        "bytes": 6,
        "created_at": 1000,
        "filename": "image.gif",
        "purpose": "user_data",
        "expires_at": 4600,
      }
      if value is Some(value) {
        fields[field] = value
      } else {
        fields.remove(field)
      }
      let server = UploadServer::start(
        group,
        response=Json::object(fields).stringify(),
      )
      let actual : @client.FileUploadError = try
        server
        .client()
        .upload_image(
          b"GIF87a",
          filename="image.gif",
          expires_after_seconds=3600,
        )
      catch {
        @client.UnexpectedFileObject(value) => UnexpectedFileObject(value)
        @client.UnexpectedFilePurpose(value) => UnexpectedFilePurpose(value)
        @client.MissingFileId => MissingFileId
        @client.MissingFilename => MissingFilename
        @client.FileByteCountMismatch(expected~, actual~) =>
          FileByteCountMismatch(expected~, actual~)
        @client.InvalidCreatedAt(value) => InvalidCreatedAt(value)
        @client.InvalidExpiresAt(value) => InvalidExpiresAt(value)
        @client.MissingExpiresAt => MissingExpiresAt
        error => raise error
      } noraise {
        _ => fail("expected invalid success metadata to fail")
      }
      assert_eq(actual, expected)
      assert_eq(server.requests.length(), 1)
    }
  }
}

///|
async test "image upload rejects invalid timeout and endpoint before connecting" {
  let client = @client.Client(
    api_key="unused",
    api_url="http://127.0.0.1:1/chat/completions",
  )
  for timeout_ms in [0, -1] {
    try
      client.upload_image(b"GIF87a", filename="image.gif", timeout_ms~)
    catch {
      @client.InvalidTimeoutMs(actual) => assert_eq(actual, timeout_ms)
      error => raise error
    } noraise {
      _ => fail("expected invalid timeout")
    }
  }
  let client = @client.Client(
    api_key="unused",
    api_url="http://127.0.0.1:1/responses",
  )
  try client.upload_image(b"GIF87a", filename="image.gif") catch {
    @client.UnsupportedApiUrl => ()
    error => raise error
  } noraise {
    _ => fail("expected unsupported endpoint")
  }
}

///|
async test "image upload timeout closes a stalled request without retry" {
  @async.with_task_group() <| group => {
    let server = UploadServer::start(group, response="{}", delay_ms=1000)
    try
      server
      .client()
      .upload_image(b"GIF87a", filename="image.gif", timeout_ms=100)
    catch {
      @async.TimeoutError => ()
      error => raise error
    } noraise {
      _ => fail("expected upload timeout")
    }
    assert_eq(server.requests.length(), 1)
  }
}

///|
async test "chat rejects invalid content before contacting the endpoint" {
  let client = @client.Client(
    api_key="unused",
    api_url="http://127.0.0.1:1/chat/completions",
  )
  try
    client.chat([ChatMessage(System, content=[File(file_id="file-api-x")])])
  catch {
    @deepseek.FileContentNotAllowed(System) => ()
    error => raise error
  } noraise {
    _ => fail("expected invalid content role")
  }
  try client.chat([ChatMessage(User, content=[File(file_id=" ")])]) catch {
    @deepseek.EmptyFileId => ()
    error => raise error
  } noraise {
    _ => fail("expected blank file ID")
  }
}
