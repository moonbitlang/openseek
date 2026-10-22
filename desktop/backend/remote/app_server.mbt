///|
/// Loopback service reached only through the desktop-owned SSH -L forward.
/// The bootstrap channel reports the port; it never carries application RPC.
pub async fn serve_app_server(
  state : @api.ApiState,
  lifetime : &@io.Reader,
  announce : &@io.Writer,
) -> Unit {
  run_app_server(
    state,
    lifetime,
    announce,
    startup_timeout_ms=1_200_000,
    heartbeat_ms=30_000,
  )
}

///|
async fn run_app_server(
  state : @api.ApiState,
  lifetime : &@io.Reader,
  announce : &@io.Writer,
  startup_timeout_ms~ : Int32,
  heartbeat_ms~ : Int32,
) -> Unit {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let instance = @uuid.mint()
  let mut owned = false
  @async.with_task_group(group => {
    state.start_services(group)
    let announcement = AppServerAnnouncement::{
      port: server.addr.port(),
      instance,
    }
    announce.write(@json.to_json(announcement).stringify() + "\n")
    group.spawn_bg(() => {
      ignore(
        @async.with_timeout_opt(startup_timeout_ms, () => {
          while lifetime.read_some(max_len=4096) is Some(_) {
            ()
          }
        }),
      )
      if !owned {
        group.return_immediately(())
      }
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
        let request = @async.with_timeout(10_000, () => {
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
          let request : AppServerInitializeRequest = @json.from_json(
            @json.parse(@utf8.decode(body.to_bytes())),
          )
          guard request.instance == instance else {
            raise @host.HostError("App-server identity or protocol changed")
          }
          request
        })
        // Only one successfully initialized connection owns this process.
        // Claim before replying: the client may close bootstrap stdin as soon
        // as it receives the response. Rejected peers must not end the owner.
        guard !owned else { return }
        owned = true
        try {
          let response = AppServerInitializeResponse::{
            id: request.id,
            instance,
          }
          @async.with_timeout(heartbeat_ms, () => {
            ws.send_text(@json.to_json(response).stringify())
          })
          WsClientActor(state).serve(ws, heartbeat_ms~)
        } catch {
          _ => ()
        }
        group.return_immediately(())
      })
    }
  })
}
