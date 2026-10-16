///|
async fn console_request(
  socket : @websocket.Conn,
  id : Int32,
  method_ : String,
  params : Json,
  notices : Array[@protocol.Notification],
) -> Json {
  let request : Json = {
    "jsonrpc": "2.0",
    "id": id,
    "method": method_,
    "params": params,
  }
  socket.send_text(request.stringify())
  for ;; {
    let reply = @json.parse(socket.recv().read_all().text())
    guard reply is Object(fields) else { fail("expected an RPC object") }
    if fields.get("id") == Some(Json(id)) {
      guard fields.get("result") is Some(result) else {
        fail("RPC failed: \{reply.stringify()}")
      }
      return result
    }
    if fields.get("method") is Some(String(method_)) &&
      fields.get("params") is Some(params) &&
      @protocol.Notification::from_wire(method_, params) is Some(notification) {
      notices.push(notification)
    }
  }
}

///|
#cfg(not(platform="windows"))
async test "shared loopback server authenticates and round-trips PTY resize input output" {
  let root = @fs.tmpdir(prefix="seekmoon-console-pty-")
  defer @fs.rmdir(root, recursive=true)
  let console = LocalConsole::bind(port=0)
  let session = "console-pty-\{console.port()}"
  @work_dir.authorize_host_workspace(session, root)
  defer @work_dir.revoke_host_workspace(session)
  let state = @api.ApiState(engine="openseek")
  @async.with_timeout(10000, () => {
    @async.with_task_group(group => {
      group.spawn_bg(() => console.run(state))
      try @websocket.Conn::connect(console.socket_url()) catch {
        @websocket.HandshakeRejected(_, _) => ()
        error => raise error
      } noraise {
        socket => {
          socket.close()
          fail("a client without the launch capability was accepted")
        }
      }
      let socket = @websocket.Conn::connect(console.socket_url(), headers={
        "Cookie": "\{console.cookie_name}=\{console.token}",
      })
      defer socket.close()
      let notices : Array[@protocol.Notification] = []
      let opened = console_request(
        socket,
        1,
        "terminal.open",
        { "session": session, "workspace": root, "cols": 80, "rows": 24 },
        notices,
      )
      guard opened is Object(fields) && fields.get("id") is Some(String(id)) else {
        fail("terminal.open did not return its id")
      }
      ignore(
        console_request(
          socket,
          2,
          "terminal.resize",
          { "id": id, "cols": 91, "rows": 37 },
          notices,
        ),
      )
      ignore(
        console_request(
          socket,
          3,
          "terminal.input",
          {
            "id": id,
            "data": "stty size; printf '__seekmoon_pty__\\n'; exit\n",
          },
          notices,
        ),
      )
      let output = StringBuilder()
      let mut cursor = 0
      let mut exited = false
      let mut sequence = 0
      while !exited {
        if cursor < notices.length() {
          match notices[cursor] {
            TerminalOutput(payload) if payload.id == id => {
              output.write_string(@utf8.decode(@base64.decode(payload.data)))
              sequence = payload.sequence
            }
            TerminalExit(payload) if payload.id == id => {
              assert_eq(payload.code, 0)
              exited = true
            }
            _ => ()
          }
          cursor += 1
        } else {
          let frame = @json.parse(socket.recv().read_all().text())
          if frame is Object(fields) &&
            fields.get("method") is Some(String(method_)) &&
            fields.get("params") is Some(params) &&
            @protocol.Notification::from_wire(method_, params)
            is Some(notification) {
            notices.push(notification)
          }
        }
      }
      assert_true(sequence > 0)
      assert_true(output.to_string().contains("37 91"))
      assert_true(output.to_string().contains("__seekmoon_pty__"))
      ignore(
        console_request(
          socket,
          4,
          "terminal.ack",
          { "id": id, "sequence": sequence },
          notices,
        ),
      )
      ignore(
        console_request(socket, 5, "terminal.close", { "id": id }, notices),
      )
      group.return_immediately(())
    })
  })
}
