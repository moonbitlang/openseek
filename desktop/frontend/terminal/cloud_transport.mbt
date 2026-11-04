///|
priv struct CloudSocket {
  rpc : @interop.RpcSession
  ready : @js.Value
  mut authenticated : Bool
  mut failure : String?
}

///|
let cloud_sockets : Map[Connection, CloudSocket] = Map([])

///|
let cloud_account : Ref[(String, String, Int32)?] = Ref(None)

///|
priv suberror CloudTerminalUnavailable {
  CloudTerminalUnavailable(String?)
}

///|
impl Show for CloudTerminalUnavailable with fn output(self, logger) {
  let CloudTerminalUnavailable(reason) = self
  logger.write_string(reason.unwrap_or(ui(English, ConnectionFailed(None))))
}

///|
/// Retiring the account closes only this client's sockets. No connection or
/// command is automatically restored after loss or account replacement.
fn sync_cloud_account(access : (String, String, Int32)?) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => {
    let replaced = cloud_account.val.map(value => (value.0, value.2)) !=
      access.map(value => (value.0, value.2))
    cloud_account.val = access
    if replaced {
      let sockets = cloud_sockets.values().to_array()
      cloud_sockets.clear()
      for socket in sockets {
        let _ : @js.Value = socket.ready.apply_with_string("resolve", [false])
        socket.rpc.close()
      }
    }
  })
}

///|
fn cloud_socket_is_current(
  connection : Connection,
  socket : CloudSocket,
) -> Bool {
  cloud_sockets
  .get(connection)
  .map_or(false, current => physical_equal(current, socket))
}

///|
fn close_cloud_socket(
  dispatch : @cmd.Emit[Msg],
  scheduler : &@cmd.Scheduler,
  connection : Connection,
  socket : CloudSocket,
) -> Unit {
  guard cloud_socket_is_current(connection, socket) else { return }
  cloud_sockets.remove(connection)
  let _ : @js.Value = socket.ready.apply_with_string("resolve", [false])
  socket.rpc.close()
  scheduler.add(
    dispatch(
      CloudDisconnected(
        connection~,
        authenticated=socket.authenticated,
        reason=socket.failure,
      ),
    ),
  )
}

///|
async fn connect_cloud(
  dispatch : @cmd.Emit[Msg],
  scheduler : &@cmd.Scheduler,
  connection : Connection,
) -> @interop.RpcSession {
  guard connection is Cloud(account~, session~, epoch~) &&
    cloud_account.val is Some((current, token, current_epoch)) &&
    current == account &&
    current_epoch == epoch else {
    raise CloudTerminalUnavailable(None)
  }
  let socket = cloud_sockets.get_or_init(connection, () => {
    let origin = @protocol.CloudOrigin
      .replace(old="https://", new="wss://")
      .replace(old="http://", new="ws://")
    let url = origin +
      "/v1/sessions/" +
      @uri.encode_component(session) +
      "/terminal"
    let ctor : @js.Value = @js.globalThis.get_with_string("WebSocket")
    let ws : @js.Value = ctor.new([url])
    let socket = {
      rpc: @interop.RpcSession(ws),
      ready: @interop.new_deferred(),
      authenticated: false,
      failure: None,
    }
    ws.set_with_string("onopen", (_ : @js.Value) => {
      if cloud_socket_is_current(connection, socket) {
        let frame : Json = { "type": "auth", "token": token }
        let _ : @js.Value = ws.apply_with_string("send", [
          @js.Value::cast_from(frame.stringify()),
        ])
      }
    })
    ws.set_with_string("onmessage", (event : @js.Value) => {
      guard cloud_socket_is_current(connection, socket) else { return }
      if !socket.authenticated {
        let text : String? = @js.Cast::into(
          (event.get_with_string("data") : @js.Value),
        )
        let frame : Json = text
          .bind(text => Some(@json.parse(text)) catch { _ => None })
          .unwrap_or(null)
        if frame is { "type": String("authenticated"), .. } {
          socket.authenticated = true
          socket.rpc.authenticated()
          let _ : @js.Value = socket.ready.apply_with_string("resolve", [true])
        } else {
          if frame
            is { "type": String("error"), "message": String(message), .. } &&
            !message.is_blank() {
            socket.failure = Some(message)
          }
          close_cloud_socket(dispatch, scheduler, connection, socket)
        }
      } else {
        socket.rpc.receive(event, notification => {
          let command = match notification {
            TerminalOutput(payload) =>
              output(connection, payload.id, payload.sequence, payload.data)
            TerminalExit(payload) =>
              dispatch(
                SessionExited(
                  channel=connection,
                  id=payload.id,
                  code=payload.code,
                ),
              )
            _ => @cmd.none
          }
          scheduler.add(command)
        })
      }
    })
    ws.set_with_string("onclose", (_ : @js.Value) => {
      close_cloud_socket(dispatch, scheduler, connection, socket)
    })
    socket
  })
  let ready : @js.Promise[Bool] = socket.ready.get_with_string("promise")
  guard ready.wait() && cloud_socket_is_current(connection, socket) else {
    raise CloudTerminalUnavailable(socket.failure)
  }
  socket.rpc
}

///|
async fn[Payload : ToJson, Reply : @json.FromJson] terminal_request(
  connection : Connection,
  command : @commands.Command[Payload, Reply],
  payload : Payload,
) -> Reply {
  match connection {
    Host(channel) => @interop.bridge_request(channel, command, payload)
    Cloud(..) => {
      guard cloud_sockets.get(connection) is Some(socket) &&
        socket.authenticated else {
        raise CloudTerminalUnavailable(None)
      }
      socket.rpc.request(command, payload)
    }
  }
}

///|
fn connection_lost(connection : Connection, error : Error) -> Bool {
  match connection {
    Host(channel) => @interop.bridge_connection_lost(channel, error)
    Cloud(..) =>
      !cloud_sockets.contains(connection) ||
      error is CloudTerminalUnavailable(_)
  }
}
