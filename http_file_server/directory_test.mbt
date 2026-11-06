///|
async fn with_server(
  root : String,
  body : async (String) -> Unit,
  index~ : Bool = false,
  active~ : () -> Bool = () => true,
) -> Unit {
  let directory = @http_file_server.Directory(root)
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      server.run_forever((request, _, conn) => {
        defer conn.close()
        directory.serve(request, conn, index~, active~)
      })
    })
    group.return_immediately(body("http://127.0.0.1:\{server.addr.port()}"))
  })
}

///|
async test "serve nested files, MIME, escaped names, HEAD and edits without scanning" {
  let root = @fs.tmpdir(prefix="static-files-")
  defer @fs.rmdir(root, recursive=true)
  @fs.mkdir(root + "/pages")
  @fs.write_file(root + "/pages/index.HTML", "<h1>Saved</h1>")
  @fs.write_file(root + "/data 你.json", "{\"value\":1}")
  let large = Bytes::make(131073, b'a')
  @fs.write_file(root + "/large.bin", large)
  with_server(root, origin => {
    let (response, body) = @http.get(origin + "/pages/index.HTML?cache=off")
    assert_eq(response.code, 200)
    assert_eq(
      response.headers.get("Content-Type"),
      Some("text/html; charset=utf-8"),
    )
    assert_eq(response.headers.get("Cache-Control"), Some("no-store"))
    assert_eq(body.text(), "<h1>Saved</h1>")
    let (head, data) = @http.request(origin + "/pages/index.HTML", Head, {}, "")
    assert_eq(head.code, 200)
    assert_eq(
      head.headers.get("Content-Length"),
      response.headers.get("Content-Length"),
    )
    assert_eq(data.binary().length(), 0)
    let (response, body) = @http.get(origin + "/data%20%E4%BD%A0.json")
    assert_eq(response.headers.get("Content-Type"), Some("application/json"))
    assert_eq(body.text(), "{\"value\":1}")
    @fs.write_file(
      root + "/pages/index.HTML",
      "<h1>Edited</h1>",
      create_mode=CreateOrTruncate,
    )
    let (_, body) = @http.get(origin + "/pages/index.HTML")
    assert_eq(body.text(), "<h1>Edited</h1>")
    let (response, body) = @http.get(origin + "/large.bin")
    assert_eq(
      response.headers.get("Content-Type"),
      Some("application/octet-stream"),
    )
    assert_eq(body.binary(), large)
    // A file created after the root was opened is immediately available.
    @fs.write_file(root + "/late.mjs", "export const value = 1;")
    let (response, body) = @http.get(origin + "/late.mjs")
    assert_eq(
      response.headers.get("Content-Type"),
      Some("text/javascript; charset=utf-8"),
    )
    assert_eq(body.text(), "export const value = 1;")
  })
}

///|
async test "reject traversal, encoded native paths, writes and directory listing" {
  let root = @fs.tmpdir(prefix="static-files-denied-")
  defer @fs.rmdir(root, recursive=true)
  @fs.write_file(root + "/index.html", "index")
  with_server(root, origin => {
    for
      path in [
        "/%2e%2e/secret", "/..%5csecret", "/%2fetc/passwd", "/C%3a/secret", "/%00bad",
      ] {
      let (response, _) = @http.get(origin + path)
      assert_eq(response.code, 403)
    }
    let (response, _) = @http.get(origin + "/missing")
    assert_eq(response.code, 404)
    let (response, _) = @http.get(origin + "/")
    assert_eq(response.code, 404)
    let (response, _) = @http.post(origin + "/index.html", "overwrite")
    assert_eq(response.code, 405)
    assert_eq(@fs.read_file(root + "/index.html").text(), "index")
  })
  with_server(root, index=true, origin => {
    let (response, body) = @http.get(origin + "/")
    assert_eq(response.code, 200)
    assert_eq(body.text(), "index")
  })
}

///|
#cfg(not(target_os="windows"))
async test "symlinks may resolve inside the root but not outside it" {
  let parent = @fs.tmpdir(prefix="static-files-links-")
  defer @fs.rmdir(parent, recursive=true)
  @fs.mkdir(parent + "/site")
  @fs.write_file(parent + "/secret", "outside")
  @fs.write_file(parent + "/site/allowed.txt", "inside")
  @fs.symlink(target=parent + "/secret", parent + "/site/escape.txt")
  @fs.symlink(target=parent + "/site/allowed.txt", parent + "/site/link.txt")
  with_server(parent + "/site", origin => {
    let (response, _) = @http.get(origin + "/escape.txt")
    assert_eq(response.code, 403)
    let (response, body) = @http.get(origin + "/link.txt")
    assert_eq(response.code, 200)
    assert_eq(body.text(), "inside")
  })
}

///|
async test "an owner's revocation suppresses the body" {
  let root = @fs.tmpdir(prefix="static-files-revoke-")
  defer @fs.rmdir(root, recursive=true)
  @fs.write_file(root + "/file.txt", "readable")
  let live = Ref(true)
  with_server(root, active=() => live.val, origin => {
    let (response, body) = @http.get(origin + "/file.txt")
    assert_eq(response.code, 200)
    assert_eq(body.text(), "readable")
    live.val = false
    let (response, body) = @http.get(origin + "/file.txt")
    assert_eq(response.code, 404)
    assert_eq(body.binary().length(), 0)
  })
}
