///|
async test "focus emulation sends both boolean settings" {
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
      defer server.close()
      let peer = group.spawn(() => {
        let (conn, _) = server.accept()
        defer conn.close()
        let ws = @websocket.from_http_server(conn.read_request(), conn)
        defer ws.close()
        for index, enabled in [true, false] {
          let id = index + 1
          assert_eq(
            @json.parse(ws.recv().text.read_all()),
            (
              {
                "id": Json(id),
                "method": "Emulation.setFocusEmulationEnabled",
                "params": { "enabled": Json(enabled) },
              } : Json),
          )
          ws.send_text(({ "id": Json(id), "result": {} } : Json).stringify())
        }
      })
      let connection = connect("ws://127.0.0.1:\{server.addr.port()}")
      defer connection.close()
      connection.set_focus_emulation_enabled(true)
      connection.set_focus_emulation_enabled(false)
      peer.wait()
    })
  })
}
