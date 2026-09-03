///|
// The localhost HTTP download hangs under the Windows test sandbox (client
// never observes the response). Re-enable once verified on a real runner.
#cfg(not(platform="windows"))
async test "package download streams to disk and reports byte progress" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0")) catch {
      error if "\{error}".contains("Operation not permitted") => {
        println("local TCP bind unavailable; skipping test: \{error}")
        return
      }
      error => raise error
    }
    // The listener is closed from the task that owns `run_forever`: the
    // background task keeps accepting until `run_forever` returns on
    // cancellation, and only then runs this deferred close. Closing from the
    // test body instead races the accept loop against the close (use-after-
    // free on the live handle) and hangs the test on Windows.
    group.spawn_bg(no_wait=true) <| () => {
      defer server.close()
      server.run_forever(
        (_request, body, conn) => {
          let _ = body.read_all()
          conn.send_response(200, "OK", extra_headers={ "Content-Length": "6" })
          conn.write_string("abcdef")
          conn.end_response()
        },
        max_connections=1,
      )
    }
    let dir = @fs.tmpdir(prefix="openseek-update-download-")
    let destination = "\{dir}/package.zip"
    let progress : Array[(Int, Int?)] = []
    download(
      "http://127.0.0.1:\{server.addr.port()}/package.zip",
      destination,
      (downloaded_bytes, total_bytes) => {
        progress.push((downloaded_bytes, total_bytes))
      },
    )
    assert_eq(@fs.read_file(destination).text(), "abcdef")
    assert_true(progress.length() >= 2)
    assert_eq(progress[0].0, 0)
    assert_eq(progress[0].1, Some(6))
    let last = progress[progress.length() - 1]
    assert_eq(last.0, 6)
    assert_eq(last.1, Some(6))
    @fs.rmdir(dir, recursive=true)
  }
}
