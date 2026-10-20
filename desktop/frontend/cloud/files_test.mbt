///|
extern "js" fn mock_file_http(
  status : Int32,
  respond : (String, String, String) -> String,
) -> () -> Unit =
  #| (status, respond) => {
  #|   const previous = globalThis.fetch;
  #|   globalThis.fetch = async (url, options) => {
  #|     if (status < 0) throw new TypeError("offline");
  #|     const body = respond(String(url), options.method,
  #|       new Headers(options.headers).get("Authorization") || "");
  #|     const sig = (() => { try { return JSON.parse(body).sig; } catch { return undefined; } })();
  #|     return new Response(body, {status, headers: sig ? {ETag: JSON.stringify(sig)} : {}});
  #|   };
  #|   return () => { globalThis.fetch = previous; };
  #| }

///|
async fn check_directory_requests() -> Unit {
  let requests = []
  let restore = mock_file_http(200, (url, method_, authorization) => {
    requests.push((url, method_, authorization))
    "{\"entries\":[{\"name\":\"hello.txt\",\"is_dir\":false},{\"name\":\"src\",\"is_dir\":true}]}"
  })
  defer restore()
  let reply = @cloud.read_directory("test-token", "session/?", "")
  assert_true(
    reply is { entries: [file, directory], } &&
    file.name == "hello.txt" &&
    !file.is_dir &&
    directory.name == "src" &&
    directory.is_dir,
  )
  ignore(@cloud.read_directory("test-token", "session/?", "src/hello world#?"))
  assert_eq(requests, [
    (
      @cloud.CloudOrigin + "/v1/sessions/session%2F%3F/files?path=",
      "GET",
      "Bearer test-token",
    ),
    (
      @cloud.CloudOrigin +
      "/v1/sessions/session%2F%3F/files?path=src%2Fhello%20world%23%3F",
      "GET",
      "Bearer test-token",
    ),
  ])
}

///|
async fn check_file_index_requests() -> Unit {
  let requests = []
  let restore = mock_file_http(200, (url, method_, authorization) => {
    requests.push((url, method_, authorization))
    "{\"files\":[\"index.html\",\"src/hello world#?.mbt\"],\"future\":null}"
  })
  defer restore()
  assert_true(
    @cloud.read_file_index("test-token", "session/?")
    is ["index.html", "src/hello world#?.mbt"],
  )
  assert_eq(requests, [
    (
      @cloud.CloudOrigin + "/v1/sessions/session%2F%3F/files/index",
      "GET",
      "Bearer test-token",
    ),
  ])
  {
    let restore = mock_file_http(200, (_, _, _) => "{\"files\":[]}")
    defer restore()
    assert_true(@cloud.read_file_index("test-token", "session") is [])
  }
  for
    body in [
      "not JSON", "null", "{}", "{\"files\":null}", "{\"files\":\"index.html\"}",
      "{\"files\":{}}", "{\"files\":[\"index.html\",null]}", "{\"files\":[123]}",
    ] {
    let restore = mock_file_http(200, (_, _, _) => body)
    defer restore()
    assert_true(
      try {
        ignore(@cloud.read_file_index("test-token", "session"))
        false
      } catch {
        @cloud.RequestError::RequestError(Malformed) => true
        _ => false
      },
    )
  }
}

///|
async fn check_file_variants() -> Unit {
  let replies : Array[@protocol.ReadFileReply] = [
    Content(content="hello 🌙", absolute="/src/hello.txt", sig="text-sig"),
    BinaryContent(data_base64="AA==", media_type="image/png", sig="image-sig"),
    BinaryContent(
      data_base64="AA==",
      media_type="application/pdf",
      sig="pdf-sig",
    ),
    Binary,
    Oversized,
  ]
  for reply in replies {
    let requests = []
    let restore = mock_file_http(200, (url, method_, authorization) => {
      requests.push((url, method_, authorization))
      reply.to_json().stringify()
    })
    defer restore()
    let expected = match reply {
      Content(content~, absolute~, sig~) =>
        @protocol.Content(
          content~,
          absolute~,
          sig=Json::string(sig).stringify(),
        )
      BinaryContent(data_base64~, media_type~, sig~) =>
        @protocol.BinaryContent(
          data_base64~,
          media_type~,
          sig=Json::string(sig).stringify(),
        )
      Binary | Oversized => reply
    }
    assert_eq(
      @cloud.read_file("test-token", "session", "src/hello.txt"),
      expected,
    )
    assert_eq(requests, [
      (
        @cloud.CloudOrigin +
        "/v1/sessions/session/files/content?path=src%2Fhello.txt",
        "GET",
        "Bearer test-token",
      ),
    ])
  }
}

///|
async fn check_file_failures() -> Unit {
  let cases : Array[(Int32, String, (@cloud.Failure) -> Bool)] = [
    (401, "", failure => failure is Unauthorized),
    (403, "", failure => failure is Http(403)),
    (409, "", failure => failure is Busy),
    (404, "", failure => failure is Http(404)),
    (500, "", failure => failure is Http(500)),
    (-1, "", failure => failure is Unreachable),
    (200, "not JSON", failure => failure is Malformed),
    (
      200,
      "{\"kind\":\"content\",\"content\":\"missing signature\"}",
      failure => failure is Malformed,
    ),
    (200, "{\"kind\":\"unknown\"}", failure => failure is Malformed),
  ]
  for (status, body, expected) in cases {
    let restore = mock_file_http(status, (_, _, _) => body)
    defer restore()
    assert_true(
      try {
        ignore(@cloud.read_file("test-token", "session", "file.txt"))
        false
      } catch {
        @cloud.RequestError::RequestError(failure) => expected(failure)
        _ => false
      },
    )
    assert_true(
      try {
        ignore(@cloud.read_file_index("test-token", "session"))
        false
      } catch {
        @cloud.RequestError::RequestError(failure) => expected(failure)
        _ => false
      },
    )
  }
  let restore = mock_file_http(200, (_, _, _) => "{\"entries\":null}")
  defer restore()
  assert_true(
    try {
      ignore(@cloud.read_directory("test-token", "session", ""))
      false
    } catch {
      @cloud.RequestError::RequestError(Malformed) => true
      _ => false
    },
  )
}

///|
async fn check_large_file_request() -> Unit {
  let urls = []
  let restore = mock_file_http(200, (url, _, _) => {
    urls.push(url)
    "{\"kind\":\"oversized\"}"
  })
  defer restore()
  ignore(@cloud.read_file("test-token", "session", "large file.txt"))
  ignore(
    @cloud.read_file(
      "test-token",
      "session",
      "large file.txt",
      allow_large=true,
    ),
  )
  ignore(
    @cloud.read_file(
      "test-token",
      "session",
      "large file.txt",
      allow_large=false,
    ),
  )
  let path = @cloud.CloudOrigin +
    "/v1/sessions/session/files/content?path=large%20file.txt"
  assert_eq(urls, [path, path + "&allow_large=true", path])
}

///|
async fn check_attachment_requests() -> Unit {
  let requests = []
  let source = @protocol.AttachmentBytes(name="report.pdf", data_base64="AA==")
  {
    let restore = mock_file_http(200, (url, method_, authorization) => {
      requests.push((url, method_, authorization))
      if url.has_suffix("/prepare") {
        "{\"kind\":\"upload_required\",\"name\":\"report.pdf\"}"
      } else {
        "{\"path\":\".openseek/attachments/test/report.pdf\"}"
      }
    })
    defer restore()
    assert_true(
      @cloud_client.prepare_attachment("test-token", "session/?", source)
      is @protocol.AttachmentUploadRequired(name="report.pdf"),
    )
    assert_eq(
      @cloud_client.import_attachment("test-token", "session/?", source).path,
      ".openseek/attachments/test/report.pdf",
    )
  }
  assert_eq(requests, [
    (
      @cloud.CloudOrigin + "/v1/sessions/session%2F%3F/files/prepare",
      "POST",
      "Bearer test-token",
    ),
    (
      @cloud.CloudOrigin + "/v1/sessions/session%2F%3F/files/import",
      "POST",
      "Bearer test-token",
    ),
  ])
  let cases : Array[(Int32, String, (@cloud.Failure) -> Bool)] = [
    (401, "", failure => failure is Unauthorized),
    (409, "", failure => failure is Busy),
    (500, "", failure => failure is Http(500)),
    (-1, "", failure => failure is Unreachable),
    (200, "not JSON", failure => failure is Malformed),
    (200, "{}", failure => failure is Malformed),
  ]
  for (status, body, expected) in cases {
    let restore = mock_file_http(status, (_, _, _) => body)
    defer restore()
    assert_true(
      try {
        ignore(
          @cloud_client.prepare_attachment("test-token", "session", source),
        )
        false
      } catch {
        @cloud_client.RequestError(failure) => expected(failure)
        _ => false
      },
    )
    assert_true(
      try {
        ignore(@cloud_client.import_attachment("test-token", "session", source))
        false
      } catch {
        @cloud_client.RequestError(failure) => expected(failure)
        _ => false
      },
    )
  }
}

///|
async test "Cloud workspace HTTP preserves request, content, and failure contracts" {
  // The async test runner schedules tests concurrently. Keep these fetch
  // substitutions in one test so each request observes its own transport.
  check_directory_requests()
  check_file_index_requests()
  check_file_variants()
  check_file_failures()
  check_large_file_request()
  check_attachment_requests()
}
