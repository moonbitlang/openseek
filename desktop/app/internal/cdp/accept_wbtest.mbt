///|
/// Accept the next connection that sends a request, with that request. A
/// client given `127.0.0.1` races another connection to it when the first has
/// not connected within 250 ms, and closes the loser before it sends
/// anything (`@socket.Tcp::connect_to_host`); such a connection is skipped.
async fn accept_request(
  server : @http.Server,
) -> (@http.ServerConnection, @http.RequestHeader) {
  for ;; {
    let (conn, _) = server.accept()
    let request = conn.read_request() catch {
      @io.UnexpectedEof => {
        conn.close()
        continue
      }
      error => {
        conn.close()
        raise error
      }
    }
    return (conn, request)
  }
}

///|
async test "accept_request skips connections closed before a request" {
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
      defer server.close()
      let accepted = group.spawn(() => {
        let (conn, request) = accept_request(server)
        defer conn.close()
        assert_eq(request.path, "/ready")
      })
      let abandoned = @socket.Tcp::connect(server.addr)
      abandoned.close()
      let client = @socket.Tcp::connect(server.addr)
      defer client.close()
      client.write(b"GET /ready HTTP/1.1\r\nHost: localhost\r\n\r\n")
      accepted.wait()
    })
  })
}
