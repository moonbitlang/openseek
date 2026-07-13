// Integration tests: NDJSON framing end to end over an in-process pipe (the full
// jsonrpc + mcp stack) and over a real subprocess, plus connect's failure path.

///|
/// A minimal in-process MCP server speaking over a jsonrpc transport, for the
/// pipe test: answer initialize/tools-list/tools-call, ignore notifications.
async fn pipe_mcp_server(transport : &@jsonrpc.Transport) -> Unit {
  for ;; {
    guard transport.recv() is Some(request) else { return }
    guard request is { "method": String(method_), "id": id, .. } else {
      // A notification (e.g. notifications/initialized): nothing to answer.
      continue
    }
    let result : Json = match method_ {
      "initialize" =>
        {
          "protocolVersion": "2025-11-25",
          "serverInfo": { "name": "pipe", "version": "1.0" },
        }
      "tools/list" =>
        {
          "tools": [
            {
              "name": "echo",
              "description": "Echo",
              "inputSchema": { "type": "object" },
            },
          ],
        }
      "tools/call" => { "content": [{ "type": "text", "text": "called" }] }
      _ => Json::empty_object()
    }
    transport.send({ "jsonrpc": "2.0", "id": id, "result": result })
  }
}

///|
async test "the MCP stack runs a handshake, list, and call over an ndjson pipe" {
  @async.with_task_group(group => {
    // client -> server and server -> client byte pipes.
    let (server_reads, client_writes) = @io.pipe()
    let (client_reads, server_writes) = @io.pipe()
    let client_transport = NdjsonTransport::new(client_reads, client_writes, on_close=() => {
      client_reads.close()
      client_writes.close()
    })
    let server_transport : &@jsonrpc.Transport = NdjsonTransport::new(
      server_reads,
      server_writes,
      on_close=() => {
        server_reads.close()
        server_writes.close()
      },
    )
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      pipe_mcp_server(server_transport)
    })
    let rpc = @jsonrpc.Client::new(client_transport)
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      rpc.run_message_pump()
    })
    group.spawn_bg(no_wait=true, allow_failure=true, () => rpc.run_writer())
    let client = @mcp.McpClient::new(rpc)
    let init = client.initialize(client_name="openseek", client_version="0.1")
    assert_eq(init.server_name, "pipe")
    assert_eq(init.protocol_version, "2025-11-25")
    let tools = client.list_tools()
    assert_eq(tools.length(), 1)
    assert_eq(tools[0].name, "echo")
    let result = client.call_tool(name="echo", arguments=Json::empty_object())
    assert_eq(result.render_text(), "called")
  })
}

///|
async test "recv reads a JSON-RPC line from a real subprocess" {
  @async.with_task_group(group => {
    let (child_stdin, stdin_writer) = @process.write_to_process()
    let (stdout_reader, child_stdout) = @process.read_from_process()
    let line = "{\"jsonrpc\":\"2.0\",\"id\":7,\"result\":{\"ok\":true}}"
    // `sh -c "echo '<line>'"` prints the JSON-RPC line and exits.
    let process = @process.spawn(
      group,
      "sh",
      ["-c", "echo '\{line}'"],
      stdin=child_stdin,
      stdout=child_stdout,
      no_wait=true,
    ) catch {
      // Spawning is forbidden in this sandbox: skip (close our pipe ends; the
      // child ends are released by spawn's own cleanup).
      _ => {
        stdout_reader.close()
        stdin_writer.close()
        return
      }
    }
    let transport : &@jsonrpc.Transport = NdjsonTransport::new(
      stdout_reader,
      stdin_writer,
      on_close=() => {
        stdout_reader.close()
        stdin_writer.close()
        process.cancel()
      },
    )
    guard transport.recv() is Some(json) else {
      fail("expected a JSON-RPC line from the subprocess")
    }
    assert_true(
      json is { "id": Number(7, ..), "result": { "ok": True, .. }, .. },
    )
    transport.close()
  })
}

///|
async test "connect returns None when the command cannot start" {
  @async.with_task_group(group => {
    let conn = connect(
      group,
      command="openseek-no-such-mcp-server-xyz",
      args=[],
      client_name="openseek",
      client_version="0.1",
    )
    assert_true(conn is None)
  })
}

///|
/// A child that starts but never answers `initialize` must not hang connect: it
/// returns None at the deadline (and tears the process down).
async test "connect times out a server that never handshakes" {
  @async.with_task_group(group => {
    let conn = connect(
      group,
      command="sh",
      args=["-c", "sleep 30"],
      client_name="openseek",
      client_version="0.1",
      handshake_timeout_ms=500,
    ) catch {
      // Spawning is forbidden in this sandbox: skip.
      _ => return
    }
    assert_true(conn is None)
  })
}
