///|
async fn with_stdio(
  dispatcher : @mcp.Dispatcher,
  session : String,
  body : async (@io.MemoryPipeRead, @io.MemoryPipeWrite) -> Unit,
  groups~ : Array[String] = [],
) -> Unit {
  let (input, requests) = @io.memory_pipe()
  let (responses, output) = @io.memory_pipe()
  defer input.close()
  defer requests.close()
  defer responses.close()
  defer output.close()
  @async.with_timeout(10000, () => {
    @async.with_task_group(group => {
      group.spawn_bg(no_wait=true, () => {
        dispatcher.serve_stdio(input, output, session~, groups~)
      })
      body(responses, requests)
    })
  })
}

///|
async fn read_stdio_reply(reader : @io.Utf8Reader) -> Json {
  guard reader.read_until("\n") is Some(line) else {
    fail("the host closed the response pipe")
  }
  @json.parse(line)
}

///|
async fn send_stdio_request(
  writer : @io.MemoryPipeWrite,
  message : Json,
) -> Unit {
  writer.write(@utf8.encode(message.stringify() + "\n"))
}

///|
async test "stdio pipes initialize, discover and call the host's tools" {
  let dispatcher = @mcp.Dispatcher(test_tools(), version="stdio-test")
  with_stdio(dispatcher, "host-session", (responses, requests) => {
    let reader = @io.Utf8Reader(responses)
    send_stdio_request(
      requests,
      request(1, "initialize", {
        "protocolVersion": "2025-11-25",
        "capabilities": {},
        "clientInfo": { "name": "pipe-test", "version": "1" },
      }),
    )
    assert_true(
      read_stdio_reply(reader)
      is {
        "id": 1,
        "result": { "serverInfo": { "version": "stdio-test", .. }, .. },
        ..
      },
    )
    // Notifications occupy a line but do not create an output line.
    send_stdio_request(requests, {
      "jsonrpc": "2.0",
      "method": "notifications/initialized",
    })
    send_stdio_request(requests, { "jsonrpc": "2.0", "id": 99, "result": {} })
    send_stdio_request(requests, request(2, "tools/list", {}))
    assert_true(
      read_stdio_reply(reader)
      is {
        "id": 2,
        "result": {
          "tools": [
            { "name": "echo", .. },
            { "name": "broken", .. },
            { "name": "browser_get_text", .. },
          ],
          ..
        },
        ..
      },
    )
    let arguments : Json = {
      "session": "forged",
      "text": "你好\nsecond line",
    }
    send_stdio_request(
      requests,
      request(3, "tools/call", { "name": "echo", "arguments": arguments }),
    )
    assert_eq(read_stdio_reply(reader), {
      "jsonrpc": "2.0",
      "id": 3,
      "result": {
        "content": [
          { "type": "text", "text": "host-session " + arguments.stringify() },
        ],
        "isError": false,
      },
    })
    send_stdio_request(requests, request(4, "tools/call", { "name": "broken" }))
    assert_true(
      read_stdio_reply(reader)
      is {
        "id": 4,
        "result": {
          "content": [{ "text": "the page is gone; open it again", .. }],
          "isError": true,
          ..
        },
        ..
      },
    )
    send_stdio_request(requests, Json::empty_object())
    assert_true(
      read_stdio_reply(reader)
      is { "id": Null, "error": { "code": -32600, .. }, .. },
    )
    requests.write(b"{invalid json}\n")
    assert_true(
      read_stdio_reply(reader)
      is { "id": Null, "error": { "code": -32700, .. }, .. },
    )
    send_stdio_request(
      requests,
      request(5, "tools/call", { "name": "missing" }),
    )
    assert_true(
      read_stdio_reply(reader)
      is { "id": 5, "error": { "code": -32602, .. }, .. },
    )
    send_stdio_request(requests, request(6, "resources/list", {}))
    assert_true(
      read_stdio_reply(reader)
      is { "id": 6, "error": { "code": -32601, .. }, .. },
    )
    // A malformed line or tool failure does not end the stream.
    requests.write(b"{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"pi")
    requests.write(b"ng\"}\r")
    requests.write(b"\n")
    assert_true(read_stdio_reply(reader) is { "id": 7, "result": { }, .. })
  })
}

///|
async test "stdio binds each pipe to its trusted conversation and tool groups" {
  let dispatcher = @mcp.Dispatcher(test_tools(), version="test")
  for session in ["one", "two"] {
    with_stdio(
      dispatcher,
      session,
      (responses, requests) => {
        let reader = @io.Utf8Reader(responses)
        send_stdio_request(requests, request(1, "tools/list", {}))
        assert_true(
          read_stdio_reply(reader)
          is {
            "result": { "tools": [{ "name": "browser_get_text", .. }], .. },
            ..
          },
        )
        send_stdio_request(
          requests,
          request(2, "tools/call", { "name": "browser_get_text" }),
        )
        assert_true(
          read_stdio_reply(reader)
          is { "result": { "content": [{ "text": String(text), .. }], .. }, .. } &&
          text == session + " {}",
        )
        send_stdio_request(
          requests,
          request(3, "tools/call", { "name": "echo" }),
        )
        assert_true(
          read_stdio_reply(reader) is { "error": { "code": -32602, .. }, .. },
        )
      },
      groups=["browser"],
    )
  }
}

///|
async test "stdio drains pending calls at EOF without blocking other calls" {
  let release : @async.Queue[Unit] = Queue(kind=Unbounded)
  let calls = Ref(0)
  let dispatcher = @mcp.Dispatcher(
    [
      {
        name: "waiting",
        description: "A host-owned operation awaiting completion.",
        input_schema: { "type": "object" },
        call: call => {
          release.get() |> ignore
          calls.val += 1
          [Text(call.session)]
        },
      },
    ],
    version="test",
  )
  with_stdio(dispatcher, "host-session", (responses, requests) => {
    let reader = @io.Utf8Reader(responses)
    send_stdio_request(
      requests,
      request(1, "tools/call", { "name": "waiting" }),
    )
    send_stdio_request(requests, request(2, "ping", {}))
    // Closing the request direction does not cancel already accepted calls.
    requests.close()
    assert_true(read_stdio_reply(reader) is { "id": 2, "result": { }, .. })
    assert_eq(calls.val, 0)
    release.put(())
    assert_true(
      read_stdio_reply(reader)
      is {
        "id": 1,
        "result": { "content": [{ "text": "host-session", .. }], .. },
        ..
      },
    )
    assert_eq(calls.val, 1)
  })
}

///|
async test "HTTP and stdio call the same host-owned objects" {
  let calls = Ref(0)
  let server = @mcp.Server(
    [
      {
        name: "counter",
        description: "Count calls in the owning host.",
        input_schema: { "type": "object" },
        call: call => {
          calls.val += 1
          [Text("\{call.session}:\{calls.val}")]
        },
      },
    ],
    version="test",
  )
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => server.run())
    with_stdio(server.dispatcher(), "same-session", (responses, requests) => {
      let reader = @io.Utf8Reader(responses)
      send_stdio_request(
        requests,
        request(1, "tools/call", { "name": "counter" }),
      )
      assert_true(
        read_stdio_reply(reader)
        is {
          "result": { "content": [{ "text": "same-session:1", .. }], .. },
          ..
        },
      )
      let (status, result) = post(
        grant(server, "same-session"),
        request(2, "tools/call", { "name": "counter" }),
      )
      assert_eq(status, 200)
      assert_true(
        result
        is Some(
          {
            "result": { "content": [{ "text": "same-session:2", .. }], .. },
            ..
          },
        ),
      )
      assert_eq(calls.val, 2)
    })
  })
}

///|
async test "stdio rejects an oversized line before dispatching it" {
  let dispatcher = @mcp.Dispatcher([], version="test")
  let input = @io.MemoryReader(writer => {
    writer.write(Bytes::make(1048577, b'x'))
  })
  defer input.close()
  let (responses, output) = @io.memory_pipe()
  defer responses.close()
  defer output.close()
  try dispatcher.serve_stdio(input, output, session="host-session") catch {
    @mcp.ServerError(message) =>
      assert_eq(message, "MCP message exceeds 1048576 bytes")
    error => raise error
  } noraise {
    _ => fail("an oversized frame must end the adapter")
  }
}

///|
async test "concurrent stdio replies stay whole under pipe backpressure" {
  let text = String::make(131072, 'x')
  let started : @async.Queue[Unit] = Queue(kind=Unbounded)
  let dispatcher = @mcp.Dispatcher(
    [
      {
        name: "large",
        description: "A reply larger than the pipe buffer.",
        input_schema: { "type": "object" },
        call: _ => {
          started.put(())
          [Text(text)]
        },
      },
    ],
    version="test",
  )
  with_stdio(dispatcher, "host-session", (responses, requests) => {
    @async.with_task_group(group => {
      let reader = @io.Utf8Reader(responses)
      // The request pipe has no buffer: once every slot is busy the host
      // stops reading requests, so they are written while replies drain.
      group.spawn_bg(() => {
        for id in 1..<=20 {
          send_stdio_request(
            requests,
            request(id, "tools/call", { "name": "large" }),
          )
        }
        requests.close()
      })
      // Completed calls still occupy a slot while their replies await a reader.
      for _ in 0..<16 {
        started.get() |> ignore
      }
      assert_true(@async.with_timeout_opt(50, () => started.get()) is None)
      let replies : Map[Int32, Unit] = Map([])
      for _ in 0..<20 {
        guard read_stdio_reply(reader)
          is {
            "id": Number(id, ..),
            "result": { "content": [{ "text": String(received), .. }], .. },
            ..
          } else {
          fail("each response must occupy one complete JSON line")
        }
        assert_eq(received, text)
        replies[id.to_int()] = ()
      }
      assert_eq(replies.length(), 20)
      for id in 1..<=20 {
        assert_true(replies.contains(id))
      }
    })
  })
}

///|
struct TestLogHandler(Array[@xlog.Entry])

///|
impl @xlog.Handler for TestLogHandler with fn handle(
  self : TestLogHandler,
  entry : @xlog.Entry,
) -> Unit {
  self.0.push(entry)
}

///|
async test "tool errors use the host logger separately from stdio replies" {
  let entries : Array[@xlog.Entry] = []
  @xlog.global().set_handler(TestLogHandler(entries))
  defer @xlog.global().set_handler(@xlog.Stdout())
  let dispatcher = @mcp.Dispatcher(test_tools(), version="test")
  with_stdio(dispatcher, "host-session", (responses, requests) => {
    let reader = @io.Utf8Reader(responses)
    send_stdio_request(requests, request(1, "tools/call", { "name": "broken" }))
    let response = @async.with_timeout_opt(1000, () => read_stdio_reply(reader))
    assert_true(
      response
      is Some(
        {
          "id": 1,
          "result": {
            "content": [{ "text": "the page is gone; open it again", .. }],
            "isError": true,
            ..
          },
          ..
        },
      ),
    )
    assert_eq(entries.length(), 1)
    assert_true(entries[0].level is Warn)
    assert_true(entries[0].category is Some("mcp"))
    assert_eq(entries[0].fields.get("event"), Some(Json("mcp_tool_failed")))
    assert_eq(entries[0].fields.get("tool"), Some(Json("broken")))
    assert_eq(entries[0].fields.get("session"), Some(Json("host-session")))
    assert_eq(
      entries[0].fields.get("error"),
      Some(Json("the page is gone; open it again")),
    )
    send_stdio_request(requests, request(2, "ping", {}))
    assert_eq(read_stdio_reply(reader), {
      "jsonrpc": "2.0",
      "id": 2,
      "result": {},
    })
  })
}

///|
async test "cancelling a stdio adapter settles its active handlers" {
  let started : @async.Queue[Unit] = Queue(kind=Unbounded)
  let waiting : @async.Queue[Unit] = Queue(kind=Unbounded)
  let active = Ref(false)
  let dispatcher = @mcp.Dispatcher(
    [
      {
        name: "waiting",
        description: "Wait until the owning adapter is cancelled.",
        input_schema: { "type": "object" },
        call: _ => {
          active.val = true
          defer {
            active.val = false
          }
          started.put(())
          waiting.get() |> ignore
          [Text("finished")]
        },
      },
    ],
    version="test",
  )
  // Returning from this body cancels the adapter task owned by the test host.
  with_stdio(dispatcher, "host-session", (_responses, requests) => {
    send_stdio_request(
      requests,
      request(1, "tools/call", { "name": "waiting" }),
    )
    started.get() |> ignore
    assert_true(active.val)
  })
  assert_false(active.val)
}

///|
async test "a broken stdio response pipe ends the adapter" {
  let dispatcher = @mcp.Dispatcher([], version="test")
  let input = @io.MemoryReader(writer => {
    writer.write(@utf8.encode(request(1, "ping", {}).stringify() + "\n"))
  })
  defer input.close()
  let (responses, output) = @io.memory_pipe()
  responses.close()
  defer output.close()
  let failed = try
    @async.with_timeout(1000, () => {
      dispatcher.serve_stdio(input, output, session="host-session")
    })
  catch {
    @async.TimeoutError => fail("a broken response pipe must not hang")
    _ => true
  } noraise {
    _ => false
  }
  assert_true(failed)
}
