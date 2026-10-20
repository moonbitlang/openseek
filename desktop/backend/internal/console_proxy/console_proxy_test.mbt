///|
/// A stand-in relay on loopback: it records each request, answers the
/// roster with a cookie the proxy must not pass on, redirects to its own
/// origin, completes the account exchange, and echoes device socket text
/// until `bye`, which it answers with application close code 4001.
async fn fake_relay(
  server : @http.Server,
  seen : Array[@http.Request],
  verifiers : Array[String],
) -> Unit {
  let origin = "http://127.0.0.1:\{server.addr.port()}"
  @async.with_task_group(group => {
    for ;; {
      let (conn, _) = server.accept()
      group.spawn_bg(allow_failure=true, () => {
        defer conn.close()
        let request = conn.read_request()
        seen.push(request)
        async fn respond(code : Int32, body : String) -> Unit {
          conn.send_response(
            code,
            "OK",
            extra_headers={
              "Content-Type": "application/json",
              "Content-Length": body.length().to_string(),
              "Connection": "close",
            },
            cookies=[Cookie("relay_session", "secret")],
          )
          conn.write(body)
          conn.end_response()
        }
        match request.path {
          "/v2/devices" => respond(200, "{\"devices\":[]}")
          "/v2/echo?x=1" => respond(201, conn.read_all().text())
          "/v2/redirect" => {
            conn.send_response(302, "Found", extra_headers={
              "Location": "\{origin}/v2/devices",
              "Content-Length": "0",
              "Connection": "close",
            })
            conn.end_response()
          }
          "/v2/auth/account/exchange" => {
            guard conn.read_all().json()
              is { "code": String("c1"), "code_verifier": String(verifier), .. } else {
              respond(400, "{}")
              return
            }
            verifiers.push(verifier)
            respond(
              200, "{\"token\":\"t1\",\"user\":{\"user_id\":\"7\",\"login\":\"octocat\",\"avatar_url\":\"\"}}",
            )
          }
          "/v2/devices/d1/ws?ticket=wst_1" => {
            let ws = @websocket.from_http_server(request, conn)
            defer ws.close()
            for ;; {
              let text = ws.recv().read_all().text()
              if text == "bye" {
                ws.send_close(code=Other(4001), reason="done")
                return
              }
              ws.send_text("relay:" + text)
            }
          }
          _ => respond(404, "{}")
        }
      })
    }
  })
}

///|
async fn with_bundle(body : async (String) -> Unit) -> Unit {
  let root = @fs.tmpdir(prefix="openseek-console-proxy-")
  defer @fs.rmdir(root, recursive=true)
  @fs.write_file(
    "\{root}/index.html",
    "<!doctype html><html><head><title>t</title></head></html>",
  )
  @fs.write_file("\{root}/frontend.js", "void 0")
  body(root)
}

///|
async fn start_proxy(
  group : @async.TaskGroup[Unit],
  upstream : @console_proxy.Upstream,
  bundle : String,
) -> String {
  let ready : @aqueue.Queue[String] = Queue(kind=Unbounded)
  group.spawn_bg(no_wait=true, () => {
    @console_proxy.serve(upstream, bundle~, port=0, on_ready=origin => {
      ignore(ready.try_put(origin) catch { _ => false })
    })
  })
  ready.get()
}

///|
async test "the proxy serves the bundle and forwards relay traffic as a bearer client" {
  with_bundle(bundle => {
    let relay_server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let relay = "http://127.0.0.1:\{relay_server.addr.port()}"
    let seen : Array[@http.Request] = []
    let verifiers : Array[String] = []
    @async.with_task_group(group => {
      group.spawn_bg(no_wait=true, () => {
        fake_relay(relay_server, seen, verifiers)
      })
      let origin = start_proxy(group, Relay(relay), bundle)
      // Application paths get the document, pinned to the bundle root.
      let (document, html) = @http.get(origin + "/cloud/devices")
      assert_eq(document.code, 200)
      assert_true(html.text().contains("<head><base href=\"/\">"))
      let (asset, _) = @http.get(origin + "/frontend.js")
      assert_eq(asset.code, 200)
      let (missing, _) = @http.get(origin + "/missing.js")
      assert_eq(missing.code, 404)
      // Bodies, methods, queries and statuses pass through unchanged.
      let (echo, echoed) = @http.post(origin + "/v2/echo?x=1", "{\"a\":1}")
      assert_eq(echo.code, 201)
      assert_eq(echoed.text(), "{\"a\":1}")
      // API requests keep the page's bearer and lose its cookies and origin.
      let (roster, body) = @http.get(origin + "/v2/devices", headers={
        "Authorization": "Bearer t0",
        "Cookie": "local=1",
        "Origin": origin,
      })
      assert_eq(roster.code, 200)
      assert_eq(body.text(), "{\"devices\":[]}")
      assert_eq(roster.cookies.length(), 0)
      guard seen.last() is Some(forwarded) else { fail("relay saw nothing") }
      assert_eq(forwarded.headers.get("authorization"), Some("Bearer t0"))
      assert_eq(forwarded.headers.get("cookie"), None)
      assert_eq(forwarded.headers.get("origin"), None)
      // A redirect to the relay's origin stays on the proxy.
      let (redirect, _) = @http.get(origin + "/v2/redirect")
      assert_eq(redirect.code, 302)
      assert_eq(redirect.headers.get("location"), Some("/v2/devices"))
      // Device sockets are joined message for message, close code included.
      let ws = @websocket.connect(
        "ws://127.0.0.1:\{origin.split(":").last().unwrap()}/v2/devices/d1/ws?ticket=wst_1",
      )
      defer ws.close()
      ws.send_text("hi")
      assert_eq(ws.recv().read_all().text(), "relay:hi")
      ws.send_text("bye")
      let closed = try ws.recv() catch {
        @websocket.ConnectionClosed(code, _) => Some(code)
        _ => None
      } noraise {
        _ => None
      }
      assert_true(closed is Some(Other(4001)))
    })
  })
}

///|
async test "sign-in runs the relay's loopback exchange once and hands the page its account" {
  with_bundle(bundle => {
    let relay_server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let relay = "http://127.0.0.1:\{relay_server.addr.port()}"
    let seen : Array[@http.Request] = []
    let verifiers : Array[String] = []
    @async.with_task_group(group => {
      group.spawn_bg(no_wait=true, () => {
        fake_relay(relay_server, seen, verifiers)
      })
      let origin = start_proxy(group, Relay(relay), bundle)
      let port = origin.split(":").last().unwrap().to_owned()
      let (start, _) = @http.get(
        origin +
        "/v2/auth/login?prompt=select_account&return_to=%2Fcloud%2Fdevices",
      )
      assert_eq(start.code, 302)
      guard start.headers.get("location") is Some(location) &&
        location.strip_prefix(relay + "/v2/auth/account/start?state=")
        is Some(rest) &&
        rest.split_once("&") is Some((state, query)) else {
        fail("sign-in did not start at the relay")
      }
      assert_true(query.contains("code_challenge_method=S256"))
      assert_true(query.has_suffix("&port=\{port}"))
      let (page, html) = @http.get(origin + "/cb?code=c1&state=\{state}")
      assert_eq(page.code, 200)
      let html = html.text()
      assert_true(html.contains("localStorage.setItem(\"seekmoon.account.v1\""))
      assert_true(html.contains("\\\"token\\\":\\\"t1\\\""))
      assert_true(html.contains("location.replace(\"/cloud/devices\")"))
      assert_eq(verifiers.length(), 1)
      // The state is spent: a replayed return exchanges nothing.
      let (replay, _) = @http.get(origin + "/cb?code=c1&state=\{state}")
      assert_eq(replay.code, 400)
      assert_eq(verifiers.length(), 1)
      // A denial is reported as text, never as markup.
      let (again, _) = @http.get(origin + "/v2/auth/login")
      guard again.headers.get("location") is Some(location) &&
        location.strip_prefix(relay + "/v2/auth/account/start?state=")
        is Some(rest) &&
        rest.split_once("&") is Some((state, _)) else {
        fail("second sign-in did not start")
      }
      let (denied, page) = @http.get(
        origin + "/cb?error=%3Cb%3Eno%3C%2Fb%3E&state=\{state}",
      )
      assert_eq(denied.code, 200)
      let page = page.text()
      assert_true(page.contains("&lt;b&gt;no&lt;/b&gt;"))
      assert_false(page.contains("<b>no</b>"))
      assert_eq(verifiers.length(), 1)
    })
  })
}

///|
async test "demo mode answers the roster for a signed-in page and nothing else" {
  with_bundle(bundle => {
    @async.with_task_group(group => {
      let origin = start_proxy(group, Demo, bundle)
      let (anonymous, _) = @http.get(origin + "/v2/devices")
      assert_eq(anonymous.code, 401)
      let (roster, body) = @http.get(origin + "/v2/devices", headers={
        "Authorization": "Bearer demo",
      })
      assert_eq(roster.code, 200)
      guard body.json() is { "devices": [_, _], .. } else {
        fail("expected two demo devices")
      }
      let (ticket, _) = @http.post(
        origin + "/v2/devices/demo-mac/connect-ticket",
        "",
      )
      assert_eq(ticket.code, 503)
      let (page, html) = @http.get(origin + "/v2/auth/login?return_to=%2Fcloud")
      assert_eq(page.code, 200)
      assert_true(html.text().contains("location.replace(\"/cloud\")"))
    })
  })
}
