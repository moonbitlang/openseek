///|
async fn serve_target_list(
  server : @http.Server,
  names : Array[String],
) -> Unit {
  let (conn, _) = server.accept()
  defer conn.close()
  assert_eq(conn.read_request().path, "/json/list")
  let targets : Json = names
    .map(name => {
      (
        {
          "type": "page",
          "webSocketDebuggerUrl": "ws://127.0.0.1:\{server.addr.port()}/devtools/page/\{name}".to_json(),
        } : Json)
    })
    .to_json()
  conn.send_response(200, "OK")
  conn.write_string(targets.stringify())
  conn.end_response()
}

///|
async test "a vanished candidate does not prevent finding the next target" {
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
      defer server.close()
      group.spawn_bg(() => {
        serve_target_list(server, ["closed", "valid"])
        for expected in ["/devtools/page/closed", "/devtools/page/valid"] {
          let (conn, _) = server.accept()
          defer conn.close()
          let request = conn.read_request()
          assert_eq(request.path, expected)
          if expected == "/devtools/page/closed" {
            conn..send_response(404, "Not Found").end_response()
          } else {
            let ws = @websocket.from_http_server(request, conn)
            defer ws.close()
            ignore(ws.recv().read_all())
            ws.send_text(
              (
                #|{"id":1,"result":{"result":{"type":"boolean","value":true}}}
              ),
            )
            assert_true(conn.read_some() is None)
          }
        }
      })
      let selected = with_cdp_targets(server.addr.port(), "\"marker\"", _ => {
        true
      })
      assert_true(selected)
    })
  })
}

///|
async test "candidate connections close on rejection and transfer on a match" {
  @async.with_timeout(5000, () => {
    for
      reply in [
        (
          #|{"id":1,"result":{"result":{"type":"boolean","value":false}}}
        ),
        (
          #|{"id":1,"result":{"result":{"type":"string","value":"bad"}}}
        ),
        (
          #|{"id":1,"error":{"code":-32000,"message":"Context is gone"}}
        ),
        (
          #|{"id":1,"result":{"result":{"type":"boolean","value":true}}}
        ),
      ] {
      @async.with_task_group(group => {
        let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
        defer server.close()
        let matched = reply.contains("true")
        let peer = group.spawn(() => {
          serve_target_list(server, ["valid"])
          let (conn, _) = server.accept()
          defer conn.close()
          let ws = @websocket.from_http_server(conn.read_request(), conn)
          defer ws.close()
          ignore(ws.recv().read_all())
          ws.send_text(reply)
          if matched {
            let request = @json.parse(ws.recv().read_all().text())
            assert_eq(
              request,
              ({ "id": 2, "method": "DOM.enable", "params": {} } : Json),
            )
            ws.send_text("{\"id\":2,\"result\":{}}")
          }
          assert_true(conn.read_some() is None)
        })
        let result = connect_target(
          @cdp.list_targets(server.addr.port())[0],
          "\"marker\"",
        )
        if matched {
          assert_true(result is Some(_))
          guard result is Some(connection) else {
            fail("matching connection was not transferred")
          }
          defer connection.close()
          connection.enable_dom()
        } else {
          assert_true(result is None)
        }
        peer.wait()
      })
    }
  })
}

///|
async test "cancelling candidate evaluation closes the untransferred connection" {
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
      defer server.close()
      let mut evaluating = false
      let peer = group.spawn(() => {
        serve_target_list(server, ["valid"])
        let (conn, _) = server.accept()
        defer conn.close()
        let ws = @websocket.from_http_server(conn.read_request(), conn)
        defer ws.close()
        ignore(ws.recv().read_all())
        evaluating = true
        assert_true(conn.read_some() is None)
      })
      let task = group.spawn(
        () => {
          connect_target(@cdp.list_targets(server.addr.port())[0], "\"marker\"")
        },
        allow_failure=true,
      )
      while !evaluating {
        @async.sleep(1)
      }
      task.cancel()
      let cancelled = try {
        ignore(task.wait())
        false
      } catch {
        @async.WaitedTaskAlreadyCancelled => true
        error => raise error
      }
      assert_true(cancelled)
      peer.wait()
    })
  })
}

///|
async test "CDP scope closes its connection after return, error, or cancellation" {
  @async.with_timeout(5000, () => {
    for outcome in ["return", "error", "cancel"] {
      @async.with_task_group(group => {
        let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
        defer server.close()
        let peer = group.spawn(() => {
          serve_target_list(server, ["valid"])
          let (conn, _) = server.accept()
          defer conn.close()
          let ws = @websocket.from_http_server(conn.read_request(), conn)
          defer ws.close()
          ignore(ws.recv().read_all())
          ws.send_text(
            "{\"id\":1,\"result\":{\"result\":{\"type\":\"boolean\",\"value\":true}}}",
          )
          let command = @json.parse(ws.recv().read_all().text())
          assert_eq(
            command,
            ({ "id": 2, "method": "DOM.enable", "params": {} } : Json),
          )
          ws.send_text("{\"id\":2,\"result\":{}}")
          assert_true(conn.read_some() is None)
        })
        let mut entered = false
        let task = group.spawn(
          () => {
            with_cdp_targets(server.addr.port(), "\"marker\"", connection => {
              connection.enable_dom()
              entered = true
              match outcome {
                "error" => raise BrowserCaptureError("callback failed")
                "cancel" => @async.sleep(60000)
                _ => ()
              }
              42
            })
          },
          allow_failure=true,
        )
        if outcome == "cancel" {
          while !entered {
            @async.sleep(1)
          }
          task.cancel()
        }
        match outcome {
          "return" => assert_eq(task.wait(), 42)
          "error" => {
            let failed = try {
              ignore(task.wait())
              false
            } catch {
              BrowserCaptureError("callback failed") => true
              error => raise error
            }
            assert_true(failed)
          }
          _ => {
            let cancelled = try {
              ignore(task.wait())
              false
            } catch {
              @async.WaitedTaskAlreadyCancelled => true
              error => raise error
            }
            assert_true(cancelled)
          }
        }
        peer.wait()
      })
    }
  })
}
