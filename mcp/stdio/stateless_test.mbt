///|
async test "stdio modern server receives discovery and self-contained tool requests without handshake" {
  let script =
    #|read -r line
    #|case "$line" in *server/discover*io.modelcontextprotocol*) ;; *) exit 1;; esac
    #|printf '{"jsonrpc":"2.0","id":1,"result":{"resultType":"complete","supportedVersions":["2026-07-28"],"capabilities":{"tools":{}},"_meta":{"io.modelcontextprotocol/serverInfo":{"name":"stdio-modern","version":"1"}}}}\n'
    #|read -r line
    #|case "$line" in *tools/list*io.modelcontextprotocol*) ;; *) exit 2;; esac
    #|printf '{"jsonrpc":"2.0","id":2,"result":{"resultType":"complete","tools":[{"name":"echo"}]}}\n'
    #|read -r line
    #|case "$line" in *tools/call*io.modelcontextprotocol*) ;; *) exit 3;; esac
    #|printf '{"jsonrpc":"2.0","id":3,"result":{"resultType":"complete","content":[{"type":"text","text":"ok"}]}}\n'
    #|read -r line
  @async.with_task_group(group => {
    let connection = @stdio.connect(
      group,
      command="sh",
      args=["-c", script],
      client_name="test",
      client_version="1",
    )
    defer connection.shutdown()
    assert_eq(connection.init().protocol_version, "2026-07-28")
    assert_eq(connection.init().server_name, Some("stdio-modern"))
    assert_eq(connection.client().list_tools().length(), 1)
    assert_eq(
      connection.client().call_tool(name="echo", arguments={}).render_text(),
      "ok",
    )
  })
}

///|
async test "stdio falls back for varied legacy discovery errors and a silent probe" {
  for code in [Some(-32601), Some(-32602), Some(-32000), None] {
    let probe_reply = match code {
      Some(code) =>
        "printf '{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":\{code},\"message\":\"initialize first\"}}\\n'"
      None => ":"
    }
    let script =
      $|read -r line
      $|\{probe_reply}
      $|read -r line
      $|case "$line" in *initialize*2025-11-25*) ;; *) exit 1;; esac
      $|printf '{"jsonrpc":"2.0","id":2,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"legacy","version":"1"}}}\{"\\n"}'
      $|read -r line
      $|case "$line" in *notifications/initialized*) ;; *) exit 2;; esac
      $|read -r line
      $|case "$line" in *io.modelcontextprotocol*) exit 3;; esac
      $|printf '{"jsonrpc":"2.0","id":3,"result":{"tools":[]}}\{"\\n"}'
      $|read -r line
    @async.with_task_group(group => {
      let connection = @stdio.connect(
        group,
        command="sh",
        args=["-c", script],
        client_name="test",
        client_version="1",
        handshake_timeout_ms=2000,
      )
      defer connection.shutdown()
      assert_eq(connection.init().protocol_version, "2025-11-25")
      assert_eq(connection.client().list_tools().length(), 0)
    })
  }
}

///|
async test "stdio recognized modern error does not fall back to initialize" {
  let script =
    #|read -r line
    #|printf '{"jsonrpc":"2.0","id":1,"error":{"code":-32022,"message":"unsupported","data":{"supported":["2099-01-01"]}}}\n'
    #|read -r line
    #|printf '{"jsonrpc":"2.0","id":2,"result":{"protocolVersion":"2025-11-25"}}\n'
    #|read -r line
  @async.with_task_group(group => {
    try
      @stdio.connect(
        group,
        command="sh",
        args=["-c", script],
        client_name="test",
        client_version="1",
      )
    catch {
      @jsonrpc.Failed(code=-32022, ..) => ()
      error => raise error
    } noraise {
      _ => fail("modern error must surface without initialize")
    }
  })
}
