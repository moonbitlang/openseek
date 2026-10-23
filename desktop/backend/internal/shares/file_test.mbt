///|
async test "file multipart preserves original binary bytes name and idempotency key" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let key = "a".repeat(64)
  let bytes = b"\x00\xff\xfe\r\nraw\x00"
  @async.with_task_group(group => {
    let receiver = group.spawn(() => {
      let (connection, _) = server.accept()
      defer connection.close()
      let request = connection.read_request()
      assert_eq(request.path, "/v2/shares")
      assert_eq(request.headers.get("Idempotency-Key"), Some(key))
      assert_eq(
        request.headers.get("Authorization"),
        Some("Bearer sug_fixture"),
      )
      let body = connection.read_all().binary()
      let footer = @utf8.encode("\r\n--\{key}--\r\n")
      let data_start = body.length() - footer.length() - bytes.length()
      assert_eq(body[data_start:data_start + bytes.length()].to_owned(), bytes)
      assert_eq(body[body.length() - footer.length():].to_owned(), footer)
      let metadata = @utf8.decode(body[:data_start].to_owned())
      assert_true(metadata.contains("filename=\"报告.bin\""))
      assert_true(metadata.contains("Content-Type: application/octet-stream"))
      assert_true(metadata.contains("name=\"title\"\r\n\r\n报告.bin"))
      connection.send_response(201, "Created")
      connection.write_string("{\"url\":\"https://shares.test/file\"}")
      connection.end_response()
    })
    let result = @shares.Snapshot::file(name="报告.bin", bytes~, key~).publish(
      server_url="http://127.0.0.1:\{server.addr.port()}",
      token="sug_fixture",
    )
    assert_true(result is Shared(url="https://shares.test/file"))
    receiver.wait()
  })
}

///|
async test "file uploads never resend after the server loses its response" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  @async.with_task_group(group => {
    let receiver = group.spawn(() => {
      let (connection, _) = server.accept()
      ignore(connection.read_request())
      connection.skip_request_body()
      connection.close()
      // A second attempt would fail the test rather than be answered as a retry.
      let duplicate = @async.with_timeout_opt(100, () => {
        let (connection, _) = server.accept()
        connection.close()
      })
      assert_true(duplicate is None)
    })
    let result = @shares.Snapshot::file(
      name="file.bin",
      bytes=b"\xff",
      key="b".repeat(64),
    ).publish(
      server_url="http://127.0.0.1:\{server.addr.port()}",
      token="ts_fixture",
      timeout_ms=1000,
    )
    assert_true(result is Failed(..))
    receiver.wait()
  })
}
