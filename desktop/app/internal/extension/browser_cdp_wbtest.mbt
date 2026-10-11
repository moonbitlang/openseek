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
      let mut vanished = false
      group.spawn_bg(() => {
        serve_target_list(server, ["closed", "valid"])
        for _ in 0..<2 {
          let (conn, _) = server.accept()
          group.spawn_bg(() => {
            defer conn.close()
            let request = conn.read_request()
            if request.path == "/devtools/page/closed" {
              conn..send_response(404, "Not Found").end_response()
              vanished = true
            } else {
              assert_eq(request.path, "/devtools/page/valid")
              let ws = @websocket.from_http_server(request, conn)
              defer ws.close()
              ignore(ws.recv().read_all())
              while !vanished {
                @async.sleep(1)
              }
              ws.send_text(
                (
                  #|{"id":1,"result":{"result":{"type":"boolean","value":true}}}
                ),
              )
              assert_true(conn.read_some() is None)
            }
          })
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
async test "the first matching target wins past rejected and hung probes and closes every connection" {
  @async.with_timeout(5000, () => {
    let mut rejected = false
    let mut hung = 0
    let mut closed = 0
    @async.with_task_group(group => {
      let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
      defer server.close()
      group.spawn_bg(() => {
        serve_target_list(server, ["wrong", "hung-a", "hung-b", "valid"])
        for _ in 0..<4 {
          let (conn, _) = server.accept()
          group.spawn_bg(() => {
            defer conn.close()
            let request = conn.read_request()
            let ws = @websocket.from_http_server(request, conn)
            defer ws.close()
            ignore(ws.recv().read_all())
            match request.path {
              "/devtools/page/wrong" => {
                ws.send_text(
                  "{\"id\":1,\"result\":{\"result\":{\"type\":\"boolean\",\"value\":false}}}",
                )
                assert_true(conn.read_some() is None)
                rejected = true
              }
              "/devtools/page/hung-a" | "/devtools/page/hung-b" => {
                hung += 1
                assert_true(conn.read_some() is None)
              }
              "/devtools/page/valid" => {
                // Make rejection finish first, with both slow probes still
                // waiting. Serial discovery cannot reach this handshake.
                while !rejected || hung != 2 {
                  @async.sleep(1)
                }
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
              }
              _ => fail("unexpected candidate")
            }
            closed += 1
          })
        }
      })
      let result = with_cdp_targets(server.addr.port(), "\"marker\"", connection => {
        // The winner must remain usable after the racing group tears down.
        connection.enable_dom()
        42
      })
      assert_eq(result, 42)
    })
    assert_eq(closed, 4)
  })
}

///|
async test "empty discovery and unmatched probes retry until the marker appears" {
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
      defer server.close()
      group.spawn_bg(() => {
        serve_target_list(server, [])
        for matched in [false, true] {
          serve_target_list(server, ["page"])
          let (conn, _) = server.accept()
          defer conn.close()
          let ws = @websocket.from_http_server(conn.read_request(), conn)
          defer ws.close()
          ignore(ws.recv().read_all())
          ws.send_text(
            (
              {
                "id": 1,
                "result": {
                  "result": { "type": "boolean", "value": matched.to_json() },
                },
              } : Json).stringify(),
          )
          assert_true(conn.read_some() is None)
        }
      })
      assert_true(with_cdp_targets(server.addr.port(), "\"marker\"", _ => true))
    })
  })
}

///|
async test "cancelling discovery closes all concurrent candidate readers" {
  @async.with_timeout(5000, () => {
    let mut evaluating = 0
    let mut closed = 0
    @async.with_task_group(group => {
      let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
      defer server.close()
      group.spawn_bg(() => {
        serve_target_list(server, ["one", "two", "three"])
        for _ in 0..<3 {
          let (conn, _) = server.accept()
          group.spawn_bg(() => {
            defer conn.close()
            let ws = @websocket.from_http_server(conn.read_request(), conn)
            defer ws.close()
            ignore(ws.recv().read_all())
            evaluating += 1
            assert_true(conn.read_some() is None)
            closed += 1
          })
        }
      })
      let task = group.spawn(
        () => {
          with_cdp_targets(server.addr.port(), "\"marker\"", _ => {
            fail("a pending probe must not win")
          })
        },
        allow_failure=true,
      )
      while evaluating != 3 {
        @async.sleep(1)
      }
      task.cancel()
      let cancelled = try {
        task.wait()
        false
      } catch {
        @async.WaitedTaskAlreadyCancelled => true
        error => raise error
      }
      assert_true(cancelled)
    })
    assert_eq(closed, 3)
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
