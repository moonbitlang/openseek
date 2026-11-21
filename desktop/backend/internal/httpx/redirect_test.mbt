///|
async test "GET follows redirects on request and drops credentials across origins" {
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let origin = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
      defer origin.close()
      let asset = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
      defer asset.close()
      let base = "http://127.0.0.1:\{origin.addr.port}"
      let mut same_origin_headers = None
      let mut asset_headers = None
      group.spawn_bg(no_wait=true, () => {
        origin.run_forever((request, conn) => {
          let location = match request.path {
            "/start" => "next?ticket=123#fragment"
            "/next?ticket=123" => {
              same_origin_headers = Some(request.headers)
              "//127.0.0.1:\{asset.addr.port}/package.zip"
            }
            "/unsupported" => "file:///package.zip"
            "/empty" => ""
            _ => fail("unexpected redirect request")
          }
          conn.send_response(302, "Found", extra_headers={
            "Location": location,
            "Content-Length": "0",
          })
          conn.end_response()
        })
      })
      group.spawn_bg(no_wait=true, () => {
        asset.run_forever((request, conn) => {
          assert_eq(request.path, "/package.zip")
          asset_headers = Some(request.headers)
          conn.send_response(200, "OK", extra_headers={ "Content-Length": "3" })
          conn.write(b"zip")
          conn.end_response()
        })
      })
      let headers : @http.Headers = {
        "Authorization": "Bearer test-token",
        "Accept-Encoding": "identity",
      }
      let start = base + "/start"
      let (redirect, _) = @httpx.get(start, headers~)
      assert_eq(redirect.code, 302)
      assert_true(same_origin_headers is None && asset_headers is None)

      let (response, body) = @httpx.get(start, headers~, redirect=true)
      assert_eq(response.code, 200)
      assert_eq(body.binary(), b"zip")
      guard same_origin_headers is Some(same_origin_headers) &&
        asset_headers is Some(asset_headers) else {
        fail("expected the redirect requests to reach both origins")
      }
      assert_eq(
        same_origin_headers.get("Authorization"),
        Some("Bearer test-token"),
      )
      assert_eq(asset_headers.get("Authorization"), None)
      assert_eq(asset_headers.get("Accept-Encoding"), Some("identity"))

      for path in ["/unsupported", "/empty"] {
        try @httpx.get(base + path, redirect=true) catch {
          @httpx.InvalidLocation => ()
          error => raise error
        } noraise {
          _ => fail("expected the redirect to be refused")
        }
      }
    })
  })
}
