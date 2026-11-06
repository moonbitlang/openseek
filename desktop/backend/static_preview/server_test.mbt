///|
async fn write(root : String, path : String, body : String) -> Unit {
  @fs.write_file("\{root}/\{path}", body, create_mode=CreateOrTruncate)
}

///|
async test "previews preserve paths and MIME, reread files, and revoke only their own mapping" {
  @vfs.with_tmpdir(dir => {
    @fs.mkdir("\{dir}/pages")
    @fs.mkdir("\{dir}/assets")
    write(dir, "pages/index.HTML", "<h1>one</h1>")
    write(dir, "assets/main.mjs", "export const n = 1;")
    write(dir, "assets/style.css", "body { color: red }")
    write(dir, "assets/data.json", "{\"value\":1}")
    write(dir, "assets/你好 1.txt", "UTF-8 filename")
    let server = @static_preview.Server()
    let url = server.open(1, "\{dir}/pages/index.HTML", root=dir)
    let other = server.open(2, "\{dir}/pages/index.HTML", root=dir)
    assert_true(url != other)
    @async.with_task_group(group => {
      group.spawn_bg(() => server.run())
      let (response, body) = @http.get(url)
      assert_eq(response.code, 200)
      assert_eq(
        response.headers.get("content-type"),
        Some("text/html; charset=utf-8"),
      )
      assert_eq(response.headers.get("cache-control"), Some("no-store"))
      assert_eq(body.text(), "<h1>one</h1>")
      let base = url.strip_suffix("pages/index.HTML").unwrap().to_owned()
      for
        (name, kind) in [
          ("assets/main.mjs", "text/javascript; charset=utf-8"),
          ("assets/style.css", "text/css; charset=utf-8"),
          ("assets/data.json", "application/json"),
          (
            "assets/%E4%BD%A0%E5%A5%BD%201.txt?fresh=1", "text/plain; charset=utf-8",
          ),
        ] {
        let (response, _) = @http.get(base + name)
        assert_eq(response.code, 200)
        assert_eq(response.headers.get("content-type"), Some(kind))
      }
      write(dir, "pages/index.HTML", "<h1>updated</h1>")
      let (_, body) = @http.get(url)
      assert_eq(body.text(), "<h1>updated</h1>")
      server.close(1)
      let (response, _) = @http.get(url)
      assert_eq(response.code, 404)
      let (response, _) = @http.get(other)
      assert_eq(response.code, 200)
      server.clear()
      let (response, _) = @http.get(other)
      assert_eq(response.code, 404)
      group.return_immediately(())
    })
    // Ending the owning task group also closes the loopback listener.
    let refused = try {
      let _ = @http.get(url)
      false
    } catch {
      _ => true
    }
    assert_true(refused)
  })
}

///|
async test "previews reject foreign hosts, writes, traversal, and command routes" {
  @vfs.with_tmpdir(dir => {
    @fs.mkdir("\{dir}/root")
    write(dir, "secret.txt", "outside")
    write(dir, "root/index.htm", "safe")
    let server = @static_preview.Server()
    let url = server.open(1, "\{dir}/root/index.htm", root="\{dir}/root")
    let base = url.strip_suffix("index.htm").unwrap().to_owned()
    @async.with_task_group(group => {
      group.spawn_bg(() => server.run())
      let address = url
      .strip_prefix("http://")
      .unwrap()
      .split_once("/")
      .unwrap().0.to_owned()
      let socket = @socket.Tcp::connect(@socket.Addr::parse(address))
      socket.write(
        "GET / HTTP/1.1\r\nHost: attacker.example\r\nConnection: close\r\n\r\n",
      )
      let denied = socket.read_all().text()
      socket.close()
      assert_true(denied.contains("403 Forbidden"))
      let (response, _) = @http.request(url, Post, Map([]), "")
      assert_eq(response.code, 405)
      for
        name in [
          "%2e%2e/secret.txt", "..%2fsecret.txt", "%2fetc/passwd", "..%5csecret.txt",
          "index.htm%00", "C:%5csecret.txt",
        ] {
        let (response, _) = @http.get(base + name)
        assert_true(response.code is (403 | 404))
      }
      let (response, _) = @http.get(base + "api/commands")
      assert_eq(response.code, 404)
      let (response, _) = @http.get(base + "missing.json")
      assert_eq(response.code, 404)
      group.return_immediately(())
    })
  })
}

///|
#cfg(not(platform="windows"))
async test "previews reject escaping symlinks but allow links within the fixed root" {
  @vfs.with_tmpdir(dir => {
    @fs.mkdir("\{dir}/root")
    write(dir, "secret.txt", "outside")
    write(dir, "root/index.html", "safe")
    write(dir, "root/inside.txt", "inside")
    @fs.symlink(target="\{dir}/secret.txt", "\{dir}/root/escape.txt")
    @fs.symlink(target="\{dir}", "\{dir}/root/escape-dir")
    @fs.symlink(target="\{dir}/root/inside.txt", "\{dir}/root/link.txt")
    let server = @static_preview.Server()
    let url = server.open(1, "\{dir}/root/index.html", root="\{dir}/root")
    let base = url.strip_suffix("index.html").unwrap().to_owned()
    @async.with_task_group(group => {
      group.spawn_bg(() => server.run())
      for path in ["escape.txt", "escape-dir/secret.txt"] {
        let (response, _) = @http.get(base + path)
        assert_eq(response.code, 403)
      }
      let (response, body) = @http.get(base + "link.txt")
      assert_eq(response.code, 200)
      assert_eq(body.text(), "inside")
      group.return_immediately(())
    })
  })
}

///|
async test "standalone files use their parent and preview replacement revokes the old URL" {
  @vfs.with_tmpdir(dir => {
    write(dir, "index.html", "document")
    let server = @static_preview.Server()
    let old = server.open(1, "\{dir}/index.html")
    let current = server.open(1, "\{dir}/index.html")
    assert_true(old != current)
    @async.with_task_group(group => {
      group.spawn_bg(() => server.run())
      let (response, _) = @http.get(old)
      assert_eq(response.code, 404)
      let (response, body) = @http.get(current)
      assert_eq(response.code, 200)
      assert_eq(body.text(), "document")
      group.return_immediately(())
    })
  })
}

///|
async test "concurrent previews share one loopback listener" {
  @vfs.with_tmpdir(dir => {
    write(dir, "index.html", "document")
    let server = @static_preview.Server()
    @async.with_task_group(group => {
      group.spawn_bg(() => server.run())
      let first = group.spawn(() => server.open(1, "\{dir}/index.html"))
      let second = group.spawn(() => server.open(2, "\{dir}/index.html"))
      let first = first.wait()
      let second = second.wait()
      let origin = fn(url : String) {
        url.strip_prefix("http://").unwrap().split_once("/").unwrap().0.to_owned()
      }
      assert_eq(origin(first), origin(second))
      for url in [first, second] {
        let (response, _) = @http.get(url)
        assert_eq(response.code, 200)
      }
      group.return_immediately(())
    })
  })
}
