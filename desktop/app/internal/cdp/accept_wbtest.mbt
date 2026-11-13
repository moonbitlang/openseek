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
