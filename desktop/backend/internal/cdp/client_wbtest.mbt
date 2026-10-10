///|
async test "typed commands preserve interleaved events and correlate replies" {
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
      defer server.close()
      group.spawn_bg(() => {
        let (conn, _) = server.accept()
        defer conn.close()
        let ws = @websocket.from_http_server(conn.read_request(), conn)
        defer ws.close()
        let request = @json.parse(ws.recv().read_all().text())
        assert_eq(
          request,
          (
            {
              "id": 1,
              "method": "Runtime.evaluate",
              "params": { "expression": "1 + 1", "returnByValue": true },
            } : Json),
        )
        ws.send_text(
          (
            #|{"method":"DOM.documentUpdated","params":{}}
          ),
        )
        ws.send_text(
          (
            #|{"method":"Overlay.inspectNodeRequested","params":{"backendNodeId":42}}
          ),
        )
        ws.send_text(
          (
            #|{"id":0,"result":{}}
          ),
        )
        ws.send_text(
          (
            #|{"id":1,"result":{"result":{"type":"number","value":2}}}
          ),
        )
        let request = @json.parse(ws.recv().read_all().text())
        assert_eq(
          request,
          (
            {
              "id": 2,
              "method": "DOM.resolveNode",
              "params": { "backendNodeId": 42 },
            } : Json),
        )
        ws.send_text(
          (
            #|{"id":2,"error":{"code":-32000,"message":"Node is gone","data":{"node":42}}}
          ),
        )
        ignore(ws.recv().read_all())
        ws.send_text("{\"id\":3,\"result\":{}}")
      })
      let connection = connect("ws://127.0.0.1:\{server.addr.port()}")
      defer connection.close()
      let result : Int = connection.evaluate("1 + 1").decode_value()
      assert_eq(result, 2)
      guard connection.next_event() is InspectNodeRequested(node) else {
        fail("event was lost")
      }
      let rejected = try {
        ignore(connection.resolve_node(node))
        false
      } catch {
        CommandFailed(code~, message~, data~) => {
          assert_eq(code, -32000)
          assert_eq(message, "Node is gone")
          assert_eq(data, Some(({ "node": 42 } : Json)))
          true
        }
        error => raise error
      }
      assert_true(rejected)
      connection.enable_dom()
    })
  })
}

///|
async test "interrupted CDP reads close the connection" {
  @async.with_timeout(5000, () => {
    for command in [false, true] {
      @async.with_task_group(group => {
        let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
        defer server.close()
        let mut partial_frame_sent = false
        let peer = group.spawn(() => {
          let (conn, _) = server.accept()
          defer conn.close()
          let ws = @websocket.from_http_server(conn.read_request(), conn)
          defer ws.close()
          if command {
            ignore(ws.recv().read_all())
          }
          // Text frame with an extended length, deliberately missing that length.
          conn.write(b"\x81\x7e")
          conn.flush()
          partial_frame_sent = true
          assert_true(conn.read_some() is None)
        })
        let connection = connect("ws://127.0.0.1:\{server.addr.port()}")
        defer connection.close()
        let reader = group.spawn(
          () => {
            if command {
              connection.enable_dom()
            } else {
              ignore(connection.next_event())
            }
          },
          allow_failure=true,
        )
        while !connection.reading || !partial_frame_sent {
          @async.sleep(1)
        }
        let rejected = try {
          connection.enable_dom()
          false
        } catch {
          ConcurrentRead => true
          error => raise error
        }
        assert_true(rejected)
        reader.cancel()
        let cancelled = try {
          reader.wait()
          false
        } catch {
          @async.WaitedTaskAlreadyCancelled => true
          error => raise error
        }
        assert_true(cancelled)
        assert_false(connection.reading)
        peer.wait()
        let closed = try {
          ignore(connection.next_event())
          false
        } catch {
          @websocket.ConnectionClosed(_, _) => true
          error => raise error
        }
        assert_true(closed)
      })
    }
  })
}
