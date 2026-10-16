// A browser page's connection to one named relay device. Reconnection policy
// remains in the parent model; changing the declared resource identity causes
// Rabbita to unload this socket and install the next generation.

///|
priv struct RemoteBridgeSub {
  device_id : String
  channel : @interop.ChannelId
  websocket_epoch : Int32
  account : @protocol.AccountSession?
  mut active : Bool
  mut dispatch : @cmd.Emit[Event]
}

///|
fn RemoteBridgeSub::RemoteBridgeSub(
  device_id : String,
  websocket_epoch : Int32,
  account : @protocol.AccountSession?,
  dispatch : @cmd.Emit[Event],
) -> RemoteBridgeSub {
  {
    device_id,
    channel: @interop.ChannelId::Remote(device_id),
    websocket_epoch,
    account,
    active: true,
    dispatch,
  }
}

///|
fn RemoteBridgeSub::subscription_key(
  device_id : String,
  websocket_epoch : Int32,
  reconnect_attempt : Int32,
) -> String {
  let channel : @interop.ChannelId = @interop.ChannelId::Remote(device_id)
  "host-bridge:\{channel.uri_authority()}:\{websocket_epoch}:\{reconnect_attempt}"
}

///|
fn RemoteBridgeSub::install(
  self : RemoteBridgeSub,
  scheduler : &@cmd.Scheduler,
) -> Unit {
  @js.Promise::from_async(() => {
    try {
      let ticket = if self.account is Some(account) {
        let endpoint = @dom.window().origin() +
          "/v2/devices/" +
          @uri.encode_component(self.device_id) +
          "/connect-ticket"
        let (response, body) = @http.post(endpoint, "", headers={
          "Authorization": "Bearer " + account.token,
        })
        guard self.active else { return }
        if response.code == 401 {
          scheduler.add(
            (self.dispatch)(
              AccountUnauthorized(
                channel=self.channel,
                websocket_epoch=self.websocket_epoch,
                token=account.token,
              ),
            ),
          )
          return
        }
        guard response.code == 200 &&
          body.json()
          is { "ticket": String(ticket), "expires_in": Number(expires, ..), .. } &&
          ticket.has_prefix("wst_") &&
          expires > 0 else {
          self.down(scheduler)
          return
        }
        Some(ticket)
      } else {
        None
      }
      guard self.active else { return }
      @interop.ws_connect(
        self.device_id,
        ticket?,
        on_notification=notification => {
          if self.active {
            scheduler.add(
              (self.dispatch)(Notification(channel=self.channel, notification~)),
            )
          }
        },
        on_down=() => self.down(scheduler),
      )
    } catch {
      _ => self.down(scheduler)
    }
  })
  |> ignore
}

///|
fn RemoteBridgeSub::down(
  self : RemoteBridgeSub,
  scheduler : &@cmd.Scheduler,
) -> Unit {
  if self.active {
    scheduler.add(
      (self.dispatch)(
        ChannelDown(channel=self.channel, websocket_epoch=self.websocket_epoch),
      ),
    )
  }
}

///|
fn RemoteBridgeSub::update_dispatch(
  self : RemoteBridgeSub,
  dispatch : @cmd.Emit[Event],
) -> Unit {
  self.dispatch = dispatch
}

///|
/// Close the current socket without emitting a down event. Removing the device
/// or replacing its declared generation therefore cannot start another retry.
fn RemoteBridgeSub::unload(self : RemoteBridgeSub) -> Unit {
  self.active = false
  @interop.ws_close(self.channel)
}
