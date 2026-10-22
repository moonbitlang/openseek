///|
async test "a screenshot asks for no clip, and may be larger than other replies" {
  let data = "A".repeat(3 * 1024 * 1024)
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
      defer server.close()
      group.spawn_bg(() => {
        let (conn, _) = server.accept()
        defer conn.close()
        let ws = @websocket.from_http_server(conn.read_request(), conn)
        defer ws.close()
        assert_eq(@json.parse(ws.recv().read_all().text()), {
          "id": 1,
          "method": "Page.captureScreenshot",
          "params": { "format": "jpeg", "quality": 80 },
        })
        let reply : Json = { "id": 1, "result": { "data": Json(data) } }
        ws.send_text(reply.stringify())
      })
      let connection = connect("ws://127.0.0.1:\{server.addr.port()}")
      defer connection.close()
      assert_eq(
        connection.capture_screenshot(quality=80).length(),
        data.length(),
      )
    })
  })
}
