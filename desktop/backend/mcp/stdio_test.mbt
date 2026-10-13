///|
/// An MCP client's ends of the pipes `seekmoon mcp` serves.
priv struct StdioClient {
  to_server : @pipe.PipeWrite
  from_server : @pipe.PipeRead
}

///|
async fn StdioClient::send(self : StdioClient, message : Json) -> Unit {
  self.to_server.write("\{message.stringify()}\n")
}

///|
async fn StdioClient::receive(self : StdioClient) -> Json {
  guard self.from_server.read_until("\n") is Some(line) else {
    fail("the server closed its output")
  }
  @json.parse(line)
}

///|
/// Run `seekmoon mcp` with `args` in `env` for the duration of `body`, then
/// end its input the way a client stops a stdio server, and return how it
/// exited.
async fn with_stdio(
  args : Array[String],
  env : Map[String, String],
  body : async (StdioClient) -> Unit,
) -> @mcp.CliOutcome {
  let (server_in, client_out) = @pipe.pipe()
  defer server_in.close()
  defer client_out.close()
  let (client_in, server_out) = @pipe.pipe()
  defer client_in.close()
  defer server_out.close()
  @async.with_task_group(group => {
    let serving = group.spawn(() => {
      @mcp.serve_stdio(args, env, server_in, server_out)
    })
    body({ to_server: client_out, from_server: client_in, })
    client_out.close()
    serving.wait()
  })
}

///|
fn tool_names(reply : Json) -> Array[String] raise {
  guard reply is { "result": { "tools": Array(tools), .. }, .. } else {
    fail("tools/list was not answered: \{reply.stringify()}")
  }
  tools.filter_map(tool => {
    match tool {
      { "name": String(name), .. } => Some(name)
      _ => None
    }
  })
}

///|
async test "seekmoon mcp relays an MCP session to the host and stops when its input ends" {
  with_server(server => {
    let outcome = with_stdio([], server.grant("s-stdio"), client => {
      client.send(
        request(1, "initialize", {
          "protocolVersion": "2025-06-18",
          "capabilities": Json::empty_object(),
          "clientInfo": { "name": "test", "version": "0" },
        }),
      )
      guard client.receive()
        is {
          "id": Number(1, ..),
          "result": { "serverInfo": { "name": "seekmoon", .. }, .. },
          ..
        } else {
        fail("initialize was not relayed")
      }
      // A notification is relayed and answered with nothing: the next line
      // the client reads is the reply to its next request.
      client.send({
        "jsonrpc": "2.0",
        "method": "notifications/initialized",
        "params": Json::empty_object(),
      })
      client.send(request(2, "tools/list", Json::empty_object()))
      let listed = client.receive()
      assert_true(listed is { "id": Number(2, ..), .. })
      assert_eq(tool_names(listed), ["echo", "broken", "browser_get_text"])
      // The call is made for the conversation whose grant the process holds.
      client.send(request(3, "tools/call", { "name": "echo" }))
      guard client.receive()
        is {
          "id": Number(3, ..),
          "result": { "content": [{ "text": String(text), .. }], .. },
          ..
        } else {
        fail("tools/call was not relayed")
      }
      assert_eq(text, "s-stdio {}")
    })
    assert_eq((outcome.code, outcome.stderr), (0, ""))
  })
}

///|
async test "seekmoon mcp offers only the groups it is asked for" {
  with_server(server => {
    let outcome = with_stdio(["browser"], server.grant("s-stdio"), client => {
      client.send(request(1, "tools/list", Json::empty_object()))
      assert_eq(tool_names(client.receive()), ["browser_get_text"])
      // A tool outside those groups does not exist for this client, and the
      // host is never asked to run it.
      client.send(request(2, "tools/call", { "name": "echo" }))
      assert_true(
        client.receive()
        is {
          "id": Number(2, ..),
          "error": { "code": Number(-32602, ..), .. },
          ..
        },
      )
      client.send(
        request(3, "tools/call", {
          "name": "browser_get_text",
          "arguments": { "tab": 3 },
        }),
      )
      guard client.receive()
        is { "result": { "content": [{ "text": String(text), .. }], .. }, .. } else {
        fail("a tool of an offered group was not run")
      }
      assert_eq(text, "s-stdio {\"tab\":3}")
    })
    assert_eq(outcome.code, 0)
  })
}

///|
async test "seekmoon mcp answers for a host it cannot reach, and for a line that is not JSON" {
  with_server(server => {
    let gone = server.grant("s-stdio")
    gone[@mcp.UrlEnv] = "http://127.0.0.1:1/mcp"
    let outcome = with_stdio([], gone, client => {
      // The request is answered rather than left hanging, and the server
      // stays up for when the host is back.
      client.send(request(5, "tools/list", Json::empty_object()))
      guard client.receive()
        is {
          "id": Number(5, ..),
          "error": { "code": Number(-32000, ..), "message": String(reason), .. },
          ..
        } else {
        fail("an unreachable host left the request unanswered")
      }
      assert_true(reason.contains("could not reach"))
      client.to_server.write("{not json\n")
      assert_true(
        client.receive() is { "error": { "code": Number(-32700, ..), .. }, .. },
      )
    })
    assert_eq(outcome.code, 0)
  })
}

///|
async test "seekmoon mcp without a grant, or with a command line it does not take, does not serve" {
  let ungranted = with_stdio([], {}, _ => ())
  assert_eq(ungranted.code, 2)
  assert_true(ungranted.stderr.contains(@mcp.UrlEnv))
  with_server(server => {
    let refused = with_stdio(["--no-such-option"], server.grant("s-stdio"), _ => {
      ()
    })
    assert_eq(refused.code, 2)
    assert_false(refused.stderr.is_empty())
  })
}
