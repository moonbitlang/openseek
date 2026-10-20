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
  #|     return new Response(body, {status});
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
    reply is Ok({ entries: [file, directory], }) &&
    file.name == "hello.txt" &&
    !file.is_dir &&
    directory.name == "src" &&
    directory.is_dir,
  )
  match @cloud.read_directory("test-token", "session/?", "src/hello world#?") {
    Ok(_) => ()
    Err(failure) => fail(failure.label())
  }
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
    assert_true(
      @cloud.read_file("test-token", "session", "src/hello.txt") is Ok(actual) &&
      actual == reply,
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
      @cloud.read_file("test-token", "session", "file.txt") is Err(failure) &&
      expected(failure),
    )
  }
  let restore = mock_file_http(200, (_, _, _) => "{\"entries\":null}")
  defer restore()
  assert_true(
    @cloud.read_directory("test-token", "session", "") is Err(Malformed),
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
async test "Cloud workspace HTTP preserves request, content, and failure contracts" {
  // The async test runner schedules tests concurrently. Keep these fetch
  // substitutions in one test so each request observes its own transport.
  check_directory_requests()
  check_file_variants()
  check_file_failures()
  check_large_file_request()
}
