///|
async test "SSH ready marker survives fragments and overlapping banner bytes" {
  let (reader, writer) = @io.pipe()
  defer reader.close()
  defer writer.close()
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      for
        part in ["welcome without newline___", "_seek", "moon_test", "__\nTAIL"] {
        writer.write(part)
        @async.pause()
      }
    })
    marker(reader, "__seekmoon_test__")
    assert_eq(reader.read_exactly(4), b"TAIL")
  })
}

///|
async test "SSH banner has a hard byte bound before handshake" {
  let (reader, writer) = @io.pipe()
  defer reader.close()
  defer writer.close()
  let rejected = try {
    @async.with_task_group(group => {
      group.spawn_bg(() => writer.write(Bytes::make(65536, b'x')))
      marker(reader, "never")
    })
    false
  } catch {
    HostClientError(_) => true
    e => raise e
  }
  assert_true(rejected)
}

///|
async test "cancelled callers leave queued bytes charged until the writer drains" {
  let (ws, server) = websocket_pair()
  defer server.close()
  defer ws.close()
  let payload : Json = { "text": "held payload" }
  let encoded : Json = {
    "jsonrpc": "2.0",
    "id": 1,
    "method": "test",
    "params": payload,
  }
  let bytes = @utf8.encode(encoded.stringify()).length()
  let client : Client = {
    identity: {
      server_id: "s",
      instance_id: "i",
      build_id: "b",
      protocol_version: 1,
      platform: "test",
      home: "/home",
      data_dir: "/data",
      status: "ready",
    },
    ws,
    pending: Map([]),
    outgoing: Queue(kind=Blocking(64)),
    notifications: Queue(kind=Blocking(64)),
    next_id: 0,
    closed: false,
    // Other in-flight responses own the rest of the real 64 MiB budget.
    retained: 64 * 1024 * 1024 - bytes * 2 - bytes / 2,
  }
  @async.with_timeout(1000, () => {
    @async.with_task_group(group => {
      let waiting = group.spawn(allow_failure=true, () => {
        ignore(client.request("test", payload))
      })
      while client.pending.is_empty() {
        @async.pause()
      }
      waiting.cancel()
      while !client.pending.is_empty() {
        @async.pause()
      }
      let rejected = try {
        ignore(client.request("test", payload))
        false
      } catch {
        Unsent(_) => true
        e => raise e
      }
      assert_true(rejected)
    })
  })
}

///|
async fn with_test_client(
  body : async (Client, @websocket.Conn) -> Unit,
) -> Unit {
  let (ws, server) = websocket_pair()
  defer ws.close()
  defer server.close()
  let client : Client = {
    identity: {
      server_id: "s",
      instance_id: "i",
      build_id: "b",
      protocol_version: 1,
      platform: "test",
      home: "/home",
      data_dir: "/data",
      status: "ready",
    },
    ws,
    pending: Map([]),
    outgoing: Queue(kind=Blocking(64)),
    notifications: Queue(kind=Blocking(64)),
    next_id: 0,
    closed: false,
    retained: 0,
  }
  @async.with_timeout(1000, () => body(client, server))
}

///|
async test "connection loss before writer handoff is unsent" {
  with_test_client((client, _) => {
    @async.with_task_group(group => {
      let request = group.spawn(() => {
        try {
          ignore(client.request("agent.start", {}))
          fail("request unexpectedly succeeded")
        } catch {
          Unsent(_) => ()
          e => raise e
        }
      })
      while client.pending.is_empty() {
        @async.pause()
      }
      client.close()
      request.wait()
    })
  })
}

///|
async test "connection loss after writer handoff is unknown" {
  with_test_client((client, server) => {
    @async.with_task_group(group => {
      group.spawn_bg(() => client.drive(() => client.read()))
      group.spawn_bg(() => client.drive(() => client.write()))
      let request = group.spawn(() => {
        try {
          ignore(client.request("agent.start", {}))
          fail("request unexpectedly succeeded")
        } catch {
          Unknown(_) => ()
          e => raise e
        }
      })
      let message = server.recv()
      let body = Buffer()
      while message.read_some() is Some(bytes) {
        body.write_bytes(bytes)
      }
      assert_true(
        @json.parse(@utf8.decode(body.to_bytes()))
        is { "method": "agent.start", .. },
      )
      server.close()
      request.wait()
    })
  })
}

///|
async test "RPC rejection is a definite refusal on a live connection" {
  with_test_client((client, server) => {
    @async.with_task_group(group => {
      group.spawn_bg(() => client.drive(() => client.read()))
      group.spawn_bg(() => client.drive(() => client.write()))
      group.spawn_bg(() => {
        let message = server.recv()
        while message.read_some() is Some(_) {
          ()
        }
        server.send_text(
          "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32001,\"message\":\"draining\"}}",
        )
      })
      try {
        ignore(client.request("agent.start", {}))
        fail("request unexpectedly succeeded")
      } catch {
        Refused(message) => assert_true(message.contains("draining"))
        e => raise e
      }
      assert_false(client.closed)
      group.return_immediately(())
    })
  })
}

///|
async test "cancelled queued mutation is skipped without blocking next request" {
  with_test_client((client, server) => {
    @async.with_task_group(group => {
      let cancelled = group.spawn(allow_failure=true, () => {
        ignore(client.request("agent.start", {}))
      })
      while client.pending.is_empty() {
        @async.pause()
      }
      cancelled.cancel()
      while !client.pending.is_empty() {
        @async.pause()
      }
      group.spawn_bg(() => client.drive(() => client.read()))
      group.spawn_bg(() => client.drive(() => client.write()))
      group.spawn_bg(() => {
        let message = server.recv()
        let body = Buffer()
        while message.read_some() is Some(bytes) {
          body.write_bytes(bytes)
        }
        assert_true(
          @json.parse(@utf8.decode(body.to_bytes()))
          is { "id": 2, "method": "server.status", .. },
        )
        server.send_text("{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{}}")
      })
      assert_eq(client.request("server.status", {}), Json::empty_object())
      assert_eq(client.retained, 0)
      group.return_immediately(())
    })
  })
}

///|
fn test_host() -> Host raise {
  Host(id="ssh_test", {
    ssh: "/unused/ssh",
    destination: "alias",
    launcher: "/launcher",
    data_dir: "/data",
    build_id: "b",
    expected_server_id: None,
  })
}

///|
test "shared host pin accepts a new instance but rejects replacement server" {
  let host = test_host()
  let identity : @host_control.Identity = {
    server_id: "s",
    instance_id: "first",
    build_id: "b",
    protocol_version: 1,
    platform: "test",
    home: "/home",
    data_dir: "/data",
    status: "ready",
  }
  host.pin(identity)
  host.pin({ ..identity, instance_id: "second", })
  try {
    host.pin({ ..identity, server_id: "replacement", })
    fail("replacement server was accepted")
  } catch {
    IdentityChanged(_) => ()
    e => raise e
  }
  assert_eq(host.server_id(), Some("s"))
}

///|
async test "retired epoch refuses commands before touching the current writer" {
  with_test_client((client, _) => {
    let connection = Connection(test_host())
    connection.epoch = 2
    connection.client = Some(client)
    try {
      ignore(connection.request(epoch=1, "agent.start", {}))
      fail("retired request was accepted")
    } catch {
      Unsent(_) => ()
      e => raise e
    }
    connection.invalidate(epoch=1)
    assert_false(client.closed)
    assert_true(client.pending.is_empty())
    assert_true(client.outgoing.try_get() is None)
    @async.with_task_group(group => {
      let pending = group.spawn(() => {
        try connection.request(epoch=2, "agent.start", {}) catch {
          Unsent(_) => true
          error => raise error
        } noraise {
          _ => false
        }
      })
      while client.pending.is_empty() {
        @async.pause()
      }
      connection.invalidate(epoch=2)
      assert_true(pending.wait())
      assert_true(client.closed)
      assert_true(client.pending.is_empty())
    })
  })
}

///|
async test "late reply cannot escape after window connection replacement" {
  with_test_client((client, server) => {
    let connection = Connection(test_host())
    connection.epoch = 1
    connection.client = Some(client)
    @async.with_task_group(group => {
      group.spawn_bg(() => client.drive(() => client.read()))
      group.spawn_bg(() => client.drive(() => client.write()))
      group.spawn_bg(() => {
        let message = server.recv()
        while message.read_some() is Some(_) {
          ()
        }
        connection.epoch = 2
        connection.client = None
        server.send_text(
          "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"session\":\"same-name\"}}",
        )
      })
      try {
        ignore(connection.request(epoch=1, "session.load", {}))
        fail("retired reply escaped")
      } catch {
        Unknown(_) => ()
        e => raise e
      }
      group.return_immediately(())
    })
  })
}

///|
async test "transport failure reason survives request classification" {
  with_test_client((client, _) => {
    @async.with_task_group(group => {
      let request = group.spawn(() => {
        try {
          ignore(client.request("agent.start", {}))
          fail("request unexpectedly succeeded")
        } catch {
          Unsent(message) =>
            assert_eq(message, "notification overflow; resync required")
          e => raise e
        }
      })
      while client.pending.is_empty() {
        @async.pause()
      }
      client.drive(() => {
        raise HostClientError("notification overflow; resync required")
      })
      request.wait()
    })
  })
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
