// The relay connector: the host's only outward face. It keeps one control
// WebSocket registered with the relay and dials one data WebSocket back per
// browser client the relay announces; each data connection is served by the
// same dispatcher the desktop bridge feeds (docs/remote-protocol.md).

///|
priv suberror ConnectorError {
  ConnectorError(String)
}

///|
impl Show for ConnectorError with fn output(self, logger) {
  match self {
    ConnectorError(message) => logger.write_string(message)
  }
}

///|
/// The relay understood the registration but rejected its credentials.
/// Retrying the same environment-provided token cannot repair that state.
priv suberror RegistrationRejected {
  RegistrationRejected(String)
}

///|
impl Show for RegistrationRejected with fn output(self, logger) {
  match self {
    RegistrationRejected(message) => logger.write_string(message)
  }
}

///|
const ReconnectDelayMs = 3_000

///|
/// The app-lifetime owner of the relay control connection and every data
/// WebSocket accepted through it. This branch deliberately gets its fixed
/// connector configuration from the environment; sign-in and Remote access
/// product state belong to a later change.
struct RelayActor {
  state : @api.ApiState
  relay_url : String
  device_token : String
  device_name : String
  announce : (String) -> Unit
}

///|
pub fn RelayActor::new(
  state : @api.ApiState,
  relay_url~ : String,
  device_token~ : String,
  device_name~ : String,
  announce~ : (String) -> Unit,
) -> RelayActor {
  { state, relay_url, device_token, device_name, announce }
}

///|
/// Run for the host's lifetime: keep one control connection registered,
/// reconnecting after any drop. `announce` receives the device id after
/// every successful registration.
pub async fn RelayActor::run(self : RelayActor) -> Unit {
  for ;; {
    self.connect_once() catch {
      error if @async.is_being_cancelled() => raise error
      RegistrationRejected(message) => {
        @xlog.warn(category="remote") <?
          { "message": "relay registration rejected", "error": message }
        return
      }
      error =>
        @xlog.warn(category="remote") <?
          { "message": "relay connection lost", "error": "\{error}" }
    }
    @async.sleep(ReconnectDelayMs)
  }
}

///|
/// One control session: register, then serve `open` announcements until the
/// connection drops, which raises out of here for `RelayActor::run` to
/// retry.
async fn RelayActor::connect_once(self : RelayActor) -> Unit {
  let control = @websocket.Conn::connect(self.relay_url)
  defer control.close()
  control.send_text(
    (Register(token=self.device_token, name=self.device_name) : @tunnel.Frame).encode(),
  )
  guard @tunnel.Frame::decode(control.recv().read_all().text()) is Some(frame) else {
    raise ConnectorError("relay sent an undecodable control frame")
  }
  let device = match frame {
    Registered(device~) => device
    Fail(message~) =>
      raise RegistrationRejected("relay refused registration: \{message}")
    Register(..) | Open(..) =>
      raise ConnectorError("relay broke the control protocol")
  }
  (self.announce)(device)
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      for ;; {
        @async.sleep(PingIntervalMs)
        control.ping()
      }
    })
    for ;; {
      guard @tunnel.Frame::decode(control.recv().read_all().text())
        is Some(frame) else {
        raise ConnectorError("relay sent an undecodable control frame")
      }
      match frame {
        // One task per client: a data connection that fails (or a client
        // that misbehaves) never touches the control channel or the other
        // clients.
        Open(stream~) =>
          group.spawn_bg(allow_failure=true, () => {
            WsClientActor::new(self.state, self.data_url(stream)).run()
          })
        Fail(message~) =>
          raise RegistrationRejected("relay reported failure: \{message}")
        Registered(..) | Register(..) =>
          raise ConnectorError("relay broke the control protocol")
      }
    }
  })
}

///|
/// The data WebSocket for one announced stream: the control URL with the
/// stream id appended (`…/tunnel` → `…/tunnel/<stream>`).
fn RelayActor::data_url(self : RelayActor, stream : String) -> String {
  match self.relay_url.strip_suffix("/") {
    Some(base) => "\{base}/\{stream}"
    None => "\{self.relay_url}/\{stream}"
  }
}
