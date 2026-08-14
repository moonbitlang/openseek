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
/// The relay rejected this token — terminal for the config, unlike every
/// transient failure the retry loop absorbs.
priv suberror RegistrationRefused {
  RegistrationRefused(String)
}

///|
const ReconnectDelayMs = 3_000

///|
/// Keep one control connection registered, retrying transient failures
/// forever. Returns only on a terminal `fail` control frame — the relay
/// rejected this token — with the relay's message; `RelayActor::run` decides
/// what that means.
async fn RelayActor::run_connector(
  self : RelayActor,
  config : @auth.ConnectorConfig,
) -> String {
  for ;; {
    self.connect_once(config) catch {
      error if @async.is_being_cancelled() => raise error
      RegistrationRefused(message) => {
        self.dropped()
        return message
      }
      error =>
        @xlog.warn(category="remote") <?
          { "message": "relay connection lost", "error": "\{error}" }
    }
    self.dropped()
    @async.sleep(ReconnectDelayMs)
  }
}

///|
/// One control session: register, then serve `open` announcements until the
/// connection drops, which raises out of here for `run_connector` to retry.
async fn RelayActor::connect_once(
  self : RelayActor,
  config : @auth.ConnectorConfig,
) -> Unit {
  let control = @websocket.Conn::connect(config.relay_url)
  defer control.close()
  control.send_text(
    (
      Register(token=config.device_token, name=config.device_name) :
      @tunnel.Frame).encode(),
  )
  guard @tunnel.Frame::decode(control.recv().read_all().text()) is Some(frame) else {
    raise ConnectorError("relay sent an undecodable control frame")
  }
  let device = match frame {
    Registered(device~) => device
    Fail(message~) => raise RegistrationRefused(message)
    Register(..) | Open(..) =>
      raise ConnectorError("relay broke the control protocol")
  }
  self.registered(device)
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
            WsClientActor::WsClientActor(
              self.state,
              data_url(config.relay_url, stream),
            ).run()
          })
        // A mid-session fail is the relay revoking this registration —
        // terminal like a refused one.
        Fail(message~) => raise RegistrationRefused(message)
        Registered(..) | Register(..) =>
          raise ConnectorError("relay broke the control protocol")
      }
    }
  })
}

///|
/// The data WebSocket for one announced stream: the control URL with the
/// stream id appended (`…/tunnel` → `…/tunnel/<stream>`).
fn data_url(relay_url : String, stream : String) -> String {
  match relay_url.strip_suffix("/") {
    Some(base) => "\{base}/\{stream}"
    None => "\{relay_url}/\{stream}"
  }
}
