///|
fn test_identity() -> @host_control.Identity {
  {
    server_id: "server",
    instance_id: "instance",
    build_id: "build",
    protocol_version: 1,
    platform: "test",
    home: "/home/test",
    data_dir: "/data/test",
    status: "ready",
  }
}

///|
async fn websocket_pair() -> (@websocket.Conn, @websocket.Conn) {
  let listener = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer listener.close()
  @async.with_timeout(1000, () => {
    @async.with_task_group(group => {
      let connecting = group.spawn(() => {
        @websocket.Conn::connect("ws://127.0.0.1:\{listener.addr.port()}/host")
      })
      let (http, _) = listener.accept()
      errdefer http.close()
      let server = @websocket.Conn::from_http_server(http.read_request(), http)
      errdefer server.close()
      (connecting.wait(), server)
    })
  })
}

///|
async fn initialize_client(client : @websocket.Conn) -> Unit {
  client.send_text(
    (
      {
        "jsonrpc": "2.0",
        "id": 0,
        "method": "server.initialize",
        "params": { "build_id": "build", "protocol_version": 1 },
      } : Json).stringify(),
  )
  let reply = @json.parse(client.recv().read_all().text())
  assert_true(
    reply
    is {
      "id": 0,
      "result": { "server_id": "server", "instance_id": "instance", .. },
      ..
    },
  )
  assert_true(
    @json.parse(client.recv().read_all().text())
    is {
      "method": "agent.connected",
      "params": { "stage": "accepted", .. },
      ..
    },
  )
}

///|
async test "direct connections gate both methods and subscription on initialize" {
  for method_ in ["fs.read_file", "server.initialize"] {
    let (client, server) = websocket_pair()
    defer client.close()
    defer server.close()
    @async.with_timeout(1000, () => {
      @async.with_task_group(group => {
        let mut subscribed = false
        let actor = Client(
          [],
          (_, _) => {
            subscribed = true
            () => ()
          },
          (_, _) => (),
        )
        let serving = group.spawn(allow_failure=true, () => {
          actor.serve_initialized(server, identity=test_identity())
        })
        client.send_text(
          (
            {
              "jsonrpc": "2.0",
              "id": 1,
              "method": method_,
              "params": { "build_id": "wrong", "protocol_version": 1 },
            } : Json).stringify(),
        )
        if method_ == "server.initialize" {
          assert_true(
            @json.parse(client.recv().read_all().text())
            is { "error": { "code": -32010, .. }, .. },
          )
        }
        let rejected = try {
          serving.wait()
          false
        } catch {
          SlowClient(_) => true
          error => raise error
        }
        assert_true(rejected)
        assert_false(subscribed)
      })
    })
  }
}

///|
async test "full request capacity rejects new work while matching pong remains live" {
  let (client, server) = websocket_pair()
  defer client.close()
  defer server.close()
  @async.with_timeout(2000, () => {
    @async.with_task_group(group => {
      let blocked : @async.Queue[Unit] = Queue(kind=Blocking(1))
      let quota : @async.Queue[Unit] = Queue(kind=Blocking(1))
      let mut invoked = 0
      let actor = Client(
        [
          {
            name: "blocked",
            invoke: _ => {
              invoked += 1
              blocked.get()
              Json::null()
            },
          },
        ],
        (_, _) => () => (),
        (_, _) => blocked.get(),
      )
      group.spawn_bg(() => {
        actor.serve_initialized(server, identity=test_identity())
      })
      initialize_client(client)
      group.spawn_bg(() => {
        for ;; {
          let reply = @json.parse(client.recv().read_all().text())
          assert_true(
            reply is { "id": 33, "error": { "code": -32011, .. }, .. },
          )
          quota.put(())
        }
      })
      for id in 1..<34 {
        client.send_text(
          (
            { "jsonrpc": "2.0", "id": id, "method": "blocked", "params": {} } :
            Json).stringify(),
        )
      }
      quota.get()
      assert_eq(invoked, 32)
      client.ping(msg=b"reader-still-live")
      group.return_immediately(())
    })
  })
}

///|
async test "ordered watch worker never parks the WebSocket control reader" {
  let (client, server) = websocket_pair()
  defer client.close()
  defer server.close()
  @async.with_timeout(2000, () => {
    @async.with_task_group(group => {
      let unblock : @async.Queue[Unit] = Queue(kind=Blocking(1))
      let notification : @async.Queue[Notification] = Queue(kind=Blocking(1))
      let watch_entered : @async.Queue[Unit] = Queue(kind=Blocking(1))
      let replies : @async.Queue[Json] = Queue(kind=Blocking(2))
      let order : Array[String] = []
      let actor = Client(
        [
          {
            name: "fs.watch",
            invoke: _ => {
              order.push("watch")
              watch_entered.put(())
              unblock.get()
              Json::null()
            },
          },
          {
            name: "fs.unwatch",
            invoke: _ => {
              order.push("unwatch")
              Json::null()
            },
          },
        ],
        (_, _) => () => (),
        (_, _) => notification.get() |> ignore,
      )
      group.spawn_bg(() => {
        actor.serve_initialized(server, identity=test_identity())
      })
      initialize_client(client)
      group.spawn_bg(() => {
        for ;; {
          replies.put(@json.parse(client.recv().read_all().text()))
        }
      })
      for id, method_ in ["fs.watch", "fs.unwatch"] {
        client.send_text(
          (
            { "jsonrpc": "2.0", "id": id, "method": method_, "params": {} } :
            Json).stringify(),
        )
      }
      watch_entered.get()
      client.ping(msg=b"ordered-watch")
      assert_eq(order, ["watch"])
      unblock.put(())
      assert_true(replies.get() is { "id": 0, "result": Null, .. })
      assert_true(replies.get() is { "id": 1, "result": Null, .. })
      assert_eq(order, ["watch", "unwatch"])
      group.return_immediately(())
    })
  })
}

///|
test "aggregate budget includes retained work and outbound messages" {
  let budget : ConnectionBudget = {
    bytes: 64 * 1024 * 1024,
    requests: 1,
    out: Queue(kind=Blocking(64)),
  }
  let rejected = try {
    budget.enqueue(Json::null())
    false
  } catch {
    SlowClient(_) => true
    error => raise error
  }
  assert_true(rejected)
  budget.bytes -= 4
  budget.enqueue(Json::null())
  assert_eq(budget.bytes, 64 * 1024 * 1024)
}

///|
async test "watchdog expires despite incoming business traffic and blocked ping writes" {
  let (client, server) = websocket_pair()
  defer client.close()
  defer server.close()
  @async.with_timeout(2000, () => {
    @async.with_task_group(group => {
      let mut received = 0
      group.spawn_bg(() => {
        for ;; {
          ignore(server.recv().read_all())
          received += 1
        }
      })
      group.spawn_bg(() => {
        for ;; {
          client.send_text("business")
          @async.sleep(1)
        }
      })
      // Fill the TCP send buffer, then leave the received message unread.
      // The pending write also holds the WebSocket write lock needed by ping.
      let mut write_finished = false
      group.spawn_bg(() => {
        server.send_binary(Bytes::make(16 * 1024 * 1024, b'x'))
        write_finished = true
      })
      let message = client.recv()
      assert_true(message.kind is Binary)
      assert_false(write_finished)
      let timed_out = try {
        heartbeat_with_budget(server, interval_ms=10, timeout_ms=100L)
        false
      } catch {
        SlowClient(message) => message == "pong deadline exceeded"
        error => raise error
      }
      assert_true(timed_out)
      assert_false(write_finished)
      assert_true(received > 0)
      group.return_immediately(())
    })
  })
}
