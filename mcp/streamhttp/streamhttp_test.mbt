// End-to-end tests against a local mock MCP endpoint served by @http.Server:
// the full jsonrpc + mcp stack over real HTTP, exercising both response modes
// (single application/json body and an SSE event stream), session-id echoing,
// and the negotiated-protocol-version header.

///|
/// Bind a localhost mock server for one test, or report the skip and return
/// None where the sandbox forbids TCP binds.
async fn bind_test_server(skip_message : String) -> @http.Server? {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0")) catch {
    error => {
      let message = "\{error}"
      if message.contains("Operation not permitted") {
        println(skip_message)
        return None
      }
      raise error
    }
  }
  Some(server)
}

///|
/// Headers seen on the requests after initialization, for asserting that the
/// session id and protocol version are echoed.
struct SeenHeaders {
  mut session_id : String
  mut protocol_version : String
  mut accept : String
  mut deleted_session : String
}

///|
/// A mock MCP endpoint: `initialize` answered as a single JSON body carrying an
/// `Mcp-Session-Id` header; notifications answered 202; `tools/list` answered as
/// an SSE stream (one notification event, then the reply). Returns the endpoint
/// URL and the headers seen on the `tools/list` request.
async fn mock_mcp_endpoint(
  group : @async.TaskGroup[Unit],
) -> (String, SeenHeaders)? {
  guard bind_test_server("local TCP bind unavailable; skipping http mcp test")
    is Some(server) else {
    return None
  }
  let seen : SeenHeaders = {
    session_id: "",
    protocol_version: "",
    accept: "",
    deleted_session: "",
  }
  group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
    server.run_forever(
      (request, body, conn) => {
        let text = body.read_all().text()
        if request.meth is Delete {
          for key, value in request.headers {
            if key.to_lower() == "mcp-session-id" {
              seen.deleted_session = value
            }
          }
          conn.send_response(200, "OK")
          return
        }
        let message = @json.parse(text) catch { _ => Json::null() }
        match message {
          { "method": String("initialize"), "id": id, .. } => {
            let reply : Json = {
              "jsonrpc": "2.0",
              "id": id,
              "result": {
                "protocolVersion": "2025-11-25",
                "serverInfo": { "name": "http-mock", "version": "1.0" },
              },
            }
            conn.send_response(200, "OK", extra_headers={
              "Content-Type": "application/json",
              "Mcp-Session-Id": "session-123",
            })
            conn.write(reply.stringify())
          }
          { "method": String("tools/list"), "id": id, .. } => {
            for key, value in request.headers {
              match key.to_lower() {
                "mcp-session-id" => seen.session_id = value
                "mcp-protocol-version" => seen.protocol_version = value
                "accept" => seen.accept = value
                _ => ()
              }
            }
            let reply : Json = {
              "jsonrpc": "2.0",
              "id": id,
              "result": {
                "tools": [
                  {
                    "name": "fetch",
                    "description": "Fetch a URL",
                    "inputSchema": { "type": "object" },
                  },
                ],
              },
            }
            conn.send_response(200, "OK", extra_headers={
              "Content-Type": "text/event-stream",
            })
            // A notification event before the reply, framed with lone CRs (the
            // third terminator SSE permits), then the reply as a CRLF-framed
            // multi-line data event.
            conn.write(
              "event: message\rdata: {\"jsonrpc\":\"2.0\",\"method\":\"notifications/progress\",\"params\":{}}\r\r",
            )
            conn.flush()
            // Split at a token boundary: SSE joins the lines with a newline,
            // which JSON tolerates only between tokens.
            ignore(reply)
            conn.write(
              "data: {\"jsonrpc\":\"2.0\",\"id\":\{id.stringify()},\r\ndata: \"result\":{\"tools\":[{\"name\":\"fetch\",\"description\":\"Fetch a URL\",\"inputSchema\":{\"type\":\"object\"}}]}}\r\n\r\n",
            )
            conn.flush()
            // Hold the stream open past the reply: the client must release the
            // exchange (and answer promptly) instead of reading to EOF.
            @async.sleep(3000)
          }
          // A notification (e.g. notifications/initialized): accepted, no body.
          _ => conn.send_response(202, "Accepted")
        }
      },
      max_connections=8,
    )
  }
  Some(("http://127.0.0.1:\{server.addr.port()}/mcp", seen))
}

///|
async test "http connect handshakes, lists tools over SSE, and echoes session headers" {
  @async.with_task_group() <| group => {
    guard mock_mcp_endpoint(group) is Some((url, seen)) else { return }
    guard @streamhttp.connect(
        group,
        url~,
        client_name="openseek",
        client_version="0.1",
        handshake_timeout_ms=10000,
      )
      is Some(conn) else {
      fail("expected the http connect to succeed")
    }
    assert_eq(conn.init().server_name, "http-mock")
    assert_eq(conn.init().protocol_version, "2025-11-25")
    let tools = conn.client().list_tools()
    assert_eq(tools.length(), 1)
    assert_eq(tools[0].name, "fetch")
    // The post-initialize request carried the session and version headers.
    assert_eq(seen.session_id, "session-123")
    assert_eq(seen.protocol_version, "2025-11-25")
    assert_true(seen.accept.contains("text/event-stream"))
    conn.shutdown()
    // Shutdown releases the server session with a best-effort DELETE.
    for _ in 0..<100 {
      if seen.deleted_session != "" {
        break
      }
      @async.sleep(20)
    }
    assert_eq(seen.deleted_session, "session-123")
  }
}

///|
async test "http connect returns None for an unreachable endpoint" {
  @async.with_task_group() <| group => {
    let conn = @streamhttp.connect(
      group,
      // A localhost port from the dynamic range with nothing listening.
      url="http://127.0.0.1:1/mcp",
      client_name="openseek",
      client_version="0.1",
      handshake_timeout_ms=3000,
    )
    assert_true(conn is None)
  }
}

///|
/// Regression guard for the send-serialization deadlock: a server-initiated
/// `ping` arriving mid-SSE-stream must be answerable while that stream is still
/// open (each POST runs on its own task), and the original request completes
/// after the server sees the pong.
async test "a server ping mid-stream is answered while the stream is open" {
  @async.with_task_group() <| group => {
    guard bind_test_server("local TCP bind unavailable; skipping ping test")
      is Some(server) else {
      return
    }
    // The pong POST arrives on a separate connection; hand it to the stream
    // handler through a queue.
    let pongs : @async.Queue[Json] = Queue(kind=Unbounded)
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      server.run_forever(
        (_request, body, conn) => {
          let message = @json.parse(body.read_all().text()) catch {
            _ => Json::null()
          }
          match message {
            { "method": String("initialize"), "id": id, .. } => {
              let reply : Json = {
                "jsonrpc": "2.0",
                "id": id,
                "result": { "protocolVersion": "2025-11-25" },
              }
              conn.send_response(200, "OK", extra_headers={
                "Content-Type": "application/json",
              })
              conn.write(reply.stringify())
            }
            { "method": String("tools/list"), "id": id, .. } => {
              conn.send_response(200, "OK", extra_headers={
                "Content-Type": "text/event-stream",
              })
              // Ask the client for a ping mid-stream and WAIT for its pong
              // before answering the request — the old inline-SSE design
              // deadlocked exactly here.
              conn.write(
                "data: {\"jsonrpc\":\"2.0\",\"id\":\"srv-ping\",\"method\":\"ping\"}\n\n",
              )
              conn.flush()
              let pong = pongs.get()
              assert_true(pong is { "id": String("srv-ping"), "result": _, .. })
              let reply : Json = {
                "jsonrpc": "2.0",
                "id": id,
                "result": { "tools": [{ "name": "late" }] },
              }
              conn.write("data: \{reply.stringify()}\n\n")
            }
            // The pong (a response, no method) — route it to the stream handler.
            { "id": String("srv-ping"), .. } => {
              pongs.put(message)
              conn.send_response(202, "Accepted")
            }
            _ => conn.send_response(202, "Accepted")
          }
        },
        max_connections=8,
      )
    }
    guard @streamhttp.connect(
        group,
        url="http://127.0.0.1:\{server.addr.port()}/mcp",
        client_name="openseek",
        client_version="0.1",
        handshake_timeout_ms=10000,
      )
      is Some(conn) else {
      fail("expected the http connect to succeed")
    }
    let tools = @async.with_timeout_opt(10000, () => conn.client().list_tools())
    guard tools is Some(tools) else {
      fail("tools/list deadlocked behind the mid-stream ping")
    }
    assert_eq(tools[0].name, "late")
    conn.shutdown()
  }
}

///|
/// A failed POST (HTTP 500) fails the pending request fast via a synthesized
/// JSON-RPC error instead of leaving it to an outer timeout.
async test "an http error fails the request fast" {
  @async.with_task_group() <| group => {
    guard bind_test_server("local TCP bind unavailable; skipping error test")
      is Some(server) else {
      return
    }
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      server.run_forever(
        (_request, body, conn) => {
          let message = @json.parse(body.read_all().text()) catch {
            _ => Json::null()
          }
          match message {
            { "method": String("initialize"), "id": id, .. } => {
              let reply : Json = {
                "jsonrpc": "2.0",
                "id": id,
                "result": { "protocolVersion": "2025-11-25" },
              }
              conn.send_response(200, "OK", extra_headers={
                "Content-Type": "application/json",
              })
              conn.write(reply.stringify())
            }
            { "method": String("tools/list"), .. } => {
              conn.send_response(500, "Internal Server Error", extra_headers={
                "Content-Type": "text/plain",
              })
              conn.write("boom")
            }
            _ => conn.send_response(202, "Accepted")
          }
        },
        max_connections=8,
      )
    }
    guard @streamhttp.connect(
        group,
        url="http://127.0.0.1:\{server.addr.port()}/mcp",
        client_name="openseek",
        client_version="0.1",
        handshake_timeout_ms=10000,
      )
      is Some(conn) else {
      fail("expected the http connect to succeed")
    }
    // Bounded well below any outer timeout: the failure must arrive promptly.
    let outcome = @async.with_timeout_opt(5000, () => {
      try {
        conn.client().list_tools() |> ignore
        "no error raised"
      } catch {
        @jsonrpc.Failed(code~, message~) => "failed \{code}: \{message}"
        error if @async.is_being_cancelled() => raise error
        _ => "other error"
      }
    })
    guard outcome is Some(outcome) else { fail("request did not fail fast") }
    assert_true(outcome.contains("failed -32000"))
    assert_true(outcome.contains("HTTP 500"))
    conn.shutdown()
  }
}

///|
/// Regression guard for the lifecycle ordering race: with detached per-POST
/// tasks, `tools/list` must still reach the server only after the
/// `notifications/initialized` POST has completed — even when the server is
/// slow to process that notification.
async test "tools/list waits for the initialized notification to complete" {
  @async.with_task_group() <| group => {
    guard bind_test_server("local TCP bind unavailable; skipping ordering test")
      is Some(server) else {
      return
    }
    let initialized_done : Ref[Bool] = { val: false }
    let list_saw_initialized : Ref[Bool] = { val: false }
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      server.run_forever(
        (_request, body, conn) => {
          let message = @json.parse(body.read_all().text()) catch {
            _ => Json::null()
          }
          match message {
            { "method": String("initialize"), "id": id, .. } => {
              let reply : Json = {
                "jsonrpc": "2.0",
                "id": id,
                "result": { "protocolVersion": "2025-11-25" },
              }
              conn.send_response(200, "OK", extra_headers={
                "Content-Type": "application/json",
              })
              conn.write(reply.stringify())
            }
            { "method": String("notifications/initialized"), .. } => {
              // A slow lifecycle handler: without the transport's gate, the
              // detached tools/list POST overtakes this notification.
              @async.sleep(150)
              initialized_done.val = true
              conn.send_response(202, "Accepted")
            }
            { "method": String("tools/list"), "id": id, .. } => {
              list_saw_initialized.val = initialized_done.val
              let reply : Json = {
                "jsonrpc": "2.0",
                "id": id,
                "result": { "tools": [{ "name": "ordered" }] },
              }
              conn.send_response(200, "OK", extra_headers={
                "Content-Type": "application/json",
              })
              conn.write(reply.stringify())
            }
            _ => conn.send_response(202, "Accepted")
          }
        },
        max_connections=8,
      )
    }
    guard @streamhttp.connect(
        group,
        url="http://127.0.0.1:\{server.addr.port()}/mcp",
        client_name="openseek",
        client_version="0.1",
        handshake_timeout_ms=10000,
      )
      is Some(conn) else {
      fail("expected the http connect to succeed")
    }
    let tools = conn.client().list_tools()
    assert_eq(tools[0].name, "ordered")
    assert_true(list_saw_initialized.val)
    conn.shutdown()
  }
}
