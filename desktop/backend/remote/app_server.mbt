///|
/// Loopback service reached only through the desktop-owned SSH -L forward.
/// The bootstrap channel reports the port; it never carries application RPC.
pub async fn serve_app_server(
  state : @api.ApiState,
  lifetime : &@io.Reader,
  announce : &@io.Writer,
) -> Unit {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let instance = @uuid.mint()
  @async.with_task_group(group => {
    state.start_services(group)
    announce.write(
      (
        { "port": server.addr.port(), "instance": instance, "protocol": 1 } :
        Json).stringify() +
      "\n",
    )
    group.spawn_bg(() => {
      while lifetime.read_some(max_len=4096) is Some(_) {
        ()
      }
      group.return_immediately(())
    })
    for ;; {
      let (conn, _) = server.accept()
      group.spawn_bg(allow_failure=true, () => {
        defer conn.close()
        let request = @async.with_timeout(10_000, () => conn.read_request())
        // A browser origin must never obtain the authenticated host catalog.
        guard request.meth is Get &&
          request.path == "/host" &&
          request.headers.get("origin") is None else {
          respond_status(conn, 403, "Forbidden")
          return
        }
        let ws = @websocket.from_http_server(request, conn)
        defer ws.close()
        @async.with_timeout(10_000, () => {
          let message = ws.recv()
          guard message.kind is Text else {
            raise @host.HostError("Expected initialize")
          }
          let body = Buffer()
          while message.read_some(max_len=4096) is Some(bytes) {
            guard body.length() + bytes.length() <= 65536 else {
              raise @host.HostError("Initialize too large")
            }
            body.write_bytes(bytes)
          }
          guard @json.parse(@utf8.decode(body.to_bytes()))
            is {
              "jsonrpc": "2.0",
              "id": id,
              "method": "initialize",
              "params": { "protocol": 1, "instance": String(expected), .. },
              ..
            } &&
            expected == instance else {
            raise @host.HostError("App-server identity or protocol changed")
          }
          ws.send_text(
            (
              {
                "jsonrpc": "2.0",
                "id": id,
                "result": { "protocol": 1, "instance": instance },
              } : Json).stringify(),
          )
        })
        WsClientActor(state).serve(ws)
      })
    }
  })
}
