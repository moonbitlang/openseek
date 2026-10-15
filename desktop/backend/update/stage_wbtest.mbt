///|
async test "package download streams to disk and reports byte progress" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0")) catch {
      error if "\{error}".contains("Operation not permitted") => {
        println("local TCP bind unavailable; skipping test: \{error}")
        return
      }
      error => raise error
    }
    // Closing the listener lets the background run_forever task leave before
    // the task group waits for it during either success or assertion failure.
    defer server.close()
    group.spawn_bg(no_wait=true) <| () => {
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
    defer @fs.rmdir(dir, recursive=true)
    let destination = "\{dir}/package.zip"
    let progress : Array[(Int32, Int32?)] = []
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
  }
}

///|
async test "package download follows HTTP 302 redirects" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0")) catch {
      error if "\{error}".contains("Operation not permitted") => {
        println("local TCP bind unavailable; skipping test: \{error}")
        return
      }
      error => raise error
    }
    // Closing the listener lets the background run_forever task leave before
    // the task group waits for it during either success or assertion failure.
    defer server.close()
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (request, body, conn) => {
          let _ = body.read_all()
          assert_eq(request.headers.get("Accept-Encoding"), Some("identity"))
          let redirect = match request.path {
            "/package.zip" =>
              Some((302, "http://127.0.0.1:\{server.addr.port()}/301"))
            "/301" => Some((301, "//127.0.0.1:\{server.addr.port()}/303"))
            "/303" => Some((303, "/307"))
            "/307" => Some((307, "/308"))
            "/308" => Some((308, "/asset.zip"))
            _ => None
          }
          if redirect is Some((code, location)) {
            conn.send_response(code, "Redirect", extra_headers={
              "Location": location,
              "Content-Length": "5",
            })
            conn.write_string("moved")
            conn.end_response()
            return
          }
          assert_eq(request.path, "/asset.zip")
          conn.send_response(200, "OK", extra_headers={ "Content-Length": "6" })
          conn.write_string("abcdef")
          conn.end_response()
        },
        max_connections=1,
      )
    }
    let dir = @fs.tmpdir(prefix="openseek-update-download-")
    defer @fs.rmdir(dir, recursive=true)
    let destination = "\{dir}/package.zip"
    let progress : Array[(Int32, Int32?)] = []
    download(
      "http://127.0.0.1:\{server.addr.port()}/package.zip",
      destination,
      (downloaded_bytes, total_bytes) => {
        progress.push((downloaded_bytes, total_bytes))
      },
    )
    assert_eq(@fs.read_file(destination).text(), "abcdef")
    assert_eq(progress.length(), 2)
    assert_eq(progress[0].0, 0)
    assert_eq(progress[0].1, Some(6))
    let last = progress[progress.length() - 1]
    assert_eq(last.0, 6)
    assert_eq(last.1, Some(6))
  }
}

///|
async test "package download reports redirect and final response failures" {
  @async.with_timeout(5000) <| () => {
    @async.with_task_group() <| group => {
      let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
      defer server.close()
      let mut loop_requests = 0
      group.spawn_bg(no_wait=true) <| () => {
        server.run_forever(
          (request, body, conn) => {
            let _ = body.read_all()
            match request.path {
              "/loop" => {
                loop_requests += 1
                conn.send_response(302, "Found", extra_headers={
                  "Location": "/loop",
                  "Content-Length": "0",
                })
              }
              "/missing" => conn.send_response(302, "Found")
              "/forbidden" =>
                conn.send_response(302, "Found", extra_headers={
                  "Location": "/denied",
                  "Content-Length": "0",
                })
              "/denied" => conn.send_response(403, "Forbidden")
              _ => fail("unexpected request path")
            }
            conn.end_response()
          },
          max_connections=1,
        )
      }
      let dir = @fs.tmpdir(prefix="openseek-update-redirect-")
      defer @fs.rmdir(dir, recursive=true)
      let destination = "\{dir}/package.zip"
      for
        (path, expected) in [
          ("/loop", "update download redirected too many times"),
          ("/missing", "update download redirect has no Location header"),
          ("/forbidden", "update download returned HTTP 403"),
        ] {
        try
          download(
            "http://127.0.0.1:\{server.addr.port()}\{path}",
            destination,
            (_, _) => fail("a failed download must not report package progress"),
          )
        catch {
          UpdateError(message) => assert_eq(message, expected)
          error => raise error
        } noraise {
          _ => fail("expected the download to fail")
        }
        assert_false(@fs.exists(destination))
      }
      assert_eq(loop_requests, 6)
    }
  }
}

///|
test "package redirect locations preserve HTTPS and reject unsupported targets" {
  assert_eq(
    download_redirect_target("https://download.example", "/package.zip"),
    "https://download.example/package.zip",
  )
  assert_eq(
    download_redirect_target(
      "https://download.example/package.zip", "//cdn.example/asset.zip",
    ),
    "https://cdn.example/asset.zip",
  )
  for
    (location, expected) in [
      (
        "http://cdn.example/package.zip", "update download redirected to an insecure address",
      ),
      ("file:///package.zip", "update download sent an unsupported redirect"),
      ("", "update download sent an unsupported redirect"),
    ] {
    try
      download_redirect_target("https://download.example/package.zip", location)
    catch {
      UpdateError(message) => assert_eq(message, expected)
    } noraise {
      _ => fail("expected the redirect to be refused")
    }
  }
}
