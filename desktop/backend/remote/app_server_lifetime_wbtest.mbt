///|
async fn lifetime_request(
  ws : @websocket.Conn,
  method_ : String,
  params : Json,
) -> Json {
  ws.send_text(
    ({ "jsonrpc": "2.0", "id": 1, "method": method_, "params": params } : Json).stringify(),
  )
  for ;; {
    let message = ws.recv()
    let reply = @json.parse(message.read_all().text())
    if reply is { "id": 1, "result": result, .. } {
      return result
    }
  }
}

///|
async fn with_lifetime_server(
  body : async (@async.Task[Unit], @io.PipeWrite, String, String) -> Unit,
  startup_timeout_ms~ : Int32 = 5000,
  heartbeat_ms~ : Int32 = 5000,
) -> Unit {
  let root = @fs.tmpdir(prefix="app-server-lifetime-")
  defer @fs.rmdir(root, recursive=true)
  let state = @api.ApiState(
    engine="unused-lifetime-test-engine",
    runtime_dir=Path(root),
  )
  let (lifetime, writer) = @io.pipe()
  defer lifetime.close()
  defer writer.close()
  let (announcement, output) = @io.pipe()
  defer announcement.close()
  defer output.close()
  @async.with_timeout(10000, () => {
    @async.with_task_group(group => {
      let server = group.spawn(() => {
        run_app_server(
          state,
          lifetime,
          output,
          startup_timeout_ms~,
          heartbeat_ms~,
        )
      })
      guard announcement.read_until("\n") is Some(line) &&
        @json.parse(line)
        is { "port": Number(port, ..), "instance": String(instance), .. } else {
        fail("missing app-server endpoint")
      }
      body(server, writer, "ws://127.0.0.1:\{port.to_int()}/host", instance)
    })
  })
}

///|
async test "app-server startup ends on stdin EOF even after a rejected handshake" {
  with_lifetime_server((server, writer, url, _) => {
    let ws = @websocket.connect(url)
    defer ws.close()
    let rejected = try {
      ignore(
        lifetime_request(ws, "initialize", {
          "protocol": 1,
          "instance": "wrong",
        }),
      )
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
    assert_true(server.try_wait() is None)
    writer.close()
    server.wait()
  })
}

///|
async test "app-server startup expires when no WebSocket takes ownership" {
  // Keep stdin open: the server must enforce its own startup deadline.
  with_lifetime_server(
    (server, _, _, _) => server.wait(),
    startup_timeout_ms=100,
  )
}

///|
async test "initialized WebSocket owns the server across stdin EOF and rejects a second owner" {
  with_lifetime_server((server, writer, url, instance) => {
    let ws = @websocket.connect(url)
    defer ws.close()
    let initialize : Json = { "protocol": 1, "instance": instance }
    assert_eq(lifetime_request(ws, "initialize", initialize), initialize)
    writer.close()
    assert_true(
      lifetime_request(ws, "fs.browse", {}) is { "entries": Array(_), .. },
    )
    let other = @websocket.connect(url)
    defer other.close()
    let rejected = try {
      ignore(lifetime_request(other, "initialize", initialize))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
    assert_true(
      lifetime_request(ws, "fs.browse", {}) is { "entries": Array(_), .. },
    )
    ws.close()
    server.wait()
  })
}

///|
async test "app-server keeps an idle responsive WebSocket and reclaims a silent one" {
  with_lifetime_server(
    (server, writer, url, instance) => {
      let ws = @websocket.connect(url)
      defer ws.close()
      ignore(
        lifetime_request(ws, "initialize", {
          "protocol": 1,
          "instance": instance,
        }),
      )
      writer.close()
      @async.with_task_group(group => {
        // No business RPCs: recv alone answers native WebSocket Pings.
        let receiver : @async.Task[Unit] = group.spawn(() => {
          for ;; {
            ignore(ws.recv().read_all())
          }
        })
        // Stay responsive for longer than one ping period plus deadline.
        @async.sleep(2500)
        assert_true(server.try_wait() is None)
        receiver.cancel()
        // Keep TCP open but stop processing frames. Missing Pong must stop
        // the service, without an explicit WebSocket close or stdin change.
        server.wait()
      })
    },
    heartbeat_ms=1000,
  )
}
