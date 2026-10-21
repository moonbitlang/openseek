///|
fn download_account() -> @protocol.AccountSession {
  {
    token: "fixture-token",
    user: { user_id: "account-a", login: "fixture", avatar_url: "", },
  }
}

///|
async test "Cloud downloads validate cached bytes and fetch changed originals without text conversion" {
  @async.with_timeout(5000, () => {
    for unchanged in [true, false] {
      let directory = @fs.tmpdir(prefix="seekmoon-download-")
      defer @fs.rmdir(directory, recursive=true)
      let original = b"\xef\xbb\xbfline one\r\nline two\r\n"
      let updated = b"\xff\x00\x80new bytes\r\n"
      let current = download_account()
      @async.with_task_group(group => {
        let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
        defer server.close()
        let origin = "http://127.0.0.1:\{server.addr.port()}"
        group.spawn_bg(() => {
          let (conn, _) = server.accept()
          defer conn.close()
          let request = conn.read_request()
          assert_true(request.meth is Head)
          assert_eq(
            request.path,
            "/v1/sessions/session/files/content?path=dir%2Ffile%20%23.bin&allow_large=true",
          )
          assert_eq(
            request.headers.get("authorization"),
            Some("Bearer fixture-token"),
          )
          assert_eq(request.headers.get("if-none-match"), Some("W/\"version\""))
          conn
          ..send_response(if unchanged { 304 } else { 200 }, "OK")
          .end_response()
          if !unchanged {
            let (conn, _) = server.accept()
            defer conn.close()
            let request = conn.read_request()
            assert_true(request.meth is Get)
            assert_eq(
              request.path,
              "/v1/sessions/session/files/download?path=dir%2Ffile%20%23.bin",
            )
            assert_eq(
              request.headers.get("authorization"),
              Some("Bearer fixture-token"),
            )
            conn..send_response(200, "OK")..write(updated).end_response()
          }
        })
        let mut revealed : String? = None
        let reply = download_cloud_file(
          {
            account: current.user.user_id,
            session: "session",
            path: "dir/file #.bin",
            cached: Some({
              etag: "W/\"version\"",
              data_base64: @base64.encode(original),
            }),
          },
          () => Some(current),
          directory,
          origin~,
          reveal=path => {
            revealed = Some(path)
            0
          },
        )
        guard reply is Saved(path~, revealed=true) else {
          fail("download failed: \{Repr(reply)}")
        }
        assert_eq(revealed, Some(path))
        assert_eq(@pathx.Path(path).basename().to_owned(), "file #.bin")
        assert_eq(
          @fs.read_file(path).binary(),
          if unchanged {
            original
          } else {
            updated
          },
        )
      })
    }
  })
}

///|
async test "downloads without preview bytes use the raw endpoint and fence account changes" {
  @async.with_timeout(5000, () => {
    for retire in [false, true] {
      let directory = @fs.tmpdir(prefix="seekmoon-download-account-")
      defer @fs.rmdir(directory, recursive=true)
      let current = download_account()
      let account = Ref(Some(current))
      @async.with_task_group(group => {
        let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
        defer server.close()
        group.spawn_bg(() => {
          let (conn, _) = server.accept()
          defer conn.close()
          let request = conn.read_request()
          assert_eq(
            request.path,
            "/v1/sessions/session/files/download?path=unsupported.bin",
          )
          if retire {
            account.val = None
          }
          conn
          ..send_response(200, "OK")
          ..write(b"\xff\x00original")
          .end_response()
        })
        let reply = download_cloud_file(
          {
            account: "account-a",
            session: "session",
            path: "unsupported.bin",
            cached: None,
          },
          () => account.val,
          directory,
          origin="http://127.0.0.1:\{server.addr.port()}",
          reveal=_ => 0,
        )
        if retire {
          assert_true(reply is Failed(..))
          assert_eq(@fs.readdir(directory), [])
        } else {
          guard reply is Saved(path~, revealed=true) else {
            fail("download failed: \{Repr(reply)}")
          }
          assert_eq(@fs.read_file(path).binary(), b"\xff\x00original")
        }
      })
    }
  })
}

///|
async test "download failures create no saved file and never reveal a partial download" {
  @async.with_timeout(5000, () => {
    for status in [401, 403, 500] {
      let directory = @fs.tmpdir(prefix="seekmoon-download-failure-")
      defer @fs.rmdir(directory, recursive=true)
      @async.with_task_group(group => {
        let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
        defer server.close()
        group.spawn_bg(() => {
          let (conn, _) = server.accept()
          defer conn.close()
          ignore(conn.read_request())
          conn..send_response(status, "Failed").end_response()
        })
        let reply = download_cloud_file(
          {
            account: "account-a",
            session: "session",
            path: "file.bin",
            cached: None,
          },
          () => Some(download_account()),
          directory,
          origin="http://127.0.0.1:\{server.addr.port()}",
          reveal=_ => fail("failed downloads must not reveal a file"),
        )
        assert_true(reply is Failed(..))
        assert_eq(@fs.readdir(directory), [])
      })
    }
    let directory = @fs.tmpdir(prefix="seekmoon-download-partial-")
    defer @fs.rmdir(directory, recursive=true)
    let failed = try {
      ignore(
        save_download(directory, "file.bin", file => {
          file.write(b"partial")
          raise CloudDownloadError("connection interrupted")
        }),
      )
      false
    } catch {
      _ => true
    }
    assert_true(failed)
    assert_eq(@fs.readdir(directory), [])
  })
}

///|
async test "concurrent downloads number collisions without overwriting existing files" {
  let directory = @fs.tmpdir(prefix="seekmoon-download-collision-")
  defer @fs.rmdir(directory, recursive=true)
  let existing = @pathx.Path(directory).join(Relative("report.txt")).to_string()
  @fs.write_file(existing, b"keep me")
  let paths = @async.with_task_group(group => {
    let first = group.spawn(() => {
      save_download(directory, "report.txt", output => output.write(b"first"))
    })
    let second = group.spawn(() => {
      save_download(directory, "report.txt", output => output.write(b"second"))
    })
    (first.wait(), second.wait())
  })
  assert_true(paths.0 != paths.1)
  assert_eq(@fs.read_file(existing).binary(), b"keep me")
  assert_eq(@fs.read_file(paths.0).binary(), b"first")
  assert_eq(@fs.read_file(paths.1).binary(), b"second")
  let names = @fs.readdir(directory)
  assert_true(names.contains("report (1).txt"))
  assert_true(names.contains("report (2).txt"))
  let failed = download_cloud_file(
    {
      account: "other-account",
      session: "session",
      path: "report.txt",
      cached: None,
    },
    () => Some(download_account()),
    directory,
  )
  assert_true(failed is Failed(..))
}

///|
async test "cancelled downloads remove their incomplete destination" {
  let directory = @fs.tmpdir(prefix="seekmoon-download-cancel-")
  defer @fs.rmdir(directory, recursive=true)
  @async.with_task_group(group => {
    let started : @async.Queue[Unit] = Queue(kind=Blocking(1))
    let task = group.spawn(() => {
      save_download(directory, "partial.bin", file => {
        file.write(b"partial")
        started.put(())
        @async.sleep(10000)
      })
    })
    started.get()
    task.cancel()
    ignore(task.wait()) catch {
      @async.WaitedTaskAlreadyCancelled => ()
      error => raise error
    }
    assert_eq(@fs.readdir(directory), [])
  })
}
