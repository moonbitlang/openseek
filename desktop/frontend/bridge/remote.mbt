// A browser page's connection to one named relay device. Reconnection policy
// remains in the parent model; changing the declared resource identity causes
// Rabbita to unload this socket and install the next generation.

///|
priv struct RemoteBridgeSub {
  device_id : String
  channel : @interop.ChannelId
  websocket_epoch : Int
  mut events : EventHandler
}

///|
fn RemoteBridgeSub::RemoteBridgeSub(
  device_id : String,
  websocket_epoch : Int,
  events : EventHandler,
) -> RemoteBridgeSub {
  {
    device_id,
    channel: @interop.ChannelId::Remote(device_id),
    websocket_epoch,
    events,
  }
}

///|
fn RemoteBridgeSub::subscription_key(
  device_id : String,
  websocket_epoch : Int,
  reconnect_attempt : Int,
) -> String {
  let channel : @interop.ChannelId = @interop.ChannelId::Remote(device_id)
  "host-bridge:\{channel.uri_authority()}:\{websocket_epoch}:\{reconnect_attempt}"
}

///|
fn RemoteBridgeSub::install(
  self : RemoteBridgeSub,
  scheduler : &@cmd.Scheduler,
) -> Unit {
  @interop.ws_connect(
    self.device_id,
    on_notification=notification => {
      self.events.enqueue(
        scheduler,
        Notification(
          channel=self.channel,
          websocket_epoch=self.websocket_epoch,
          notification~,
        ),
      )
    },
    on_down=() => {
      self.events.enqueue(
        scheduler,
        ChannelDown(
          channel=self.channel,
          websocket_epoch=self.websocket_epoch,
        ),
      )
    },
  )
}

///|
fn RemoteBridgeSub::update_events(
  self : RemoteBridgeSub,
  events : EventHandler,
) -> Unit {
  self.events = events
}

///|
/// Close the current socket without emitting a down event. Removing the device
/// or replacing its declared generation therefore cannot start another retry.
fn RemoteBridgeSub::unload(self : RemoteBridgeSub) -> Unit {
  @interop.ws_close(self.channel)
}
