// Events emitted by a live engine-host connection. This package owns the
// transport lifecycle and wire-facing payload extraction; the parent
// frontend decides how each event changes application state.

///|
/// One event observed from a local Proton host or remote relay device. The
/// parent frontend pattern-matches this value to apply application policy.
pub enum Event {
  Notification(
    channel~ : @interop.ChannelId,
    notification~ : @protocol.Notification
  )
  Unavailable(channel~ : @interop.ChannelId, message~ : String)
  ChannelDown(channel~ : @interop.ChannelId, websocket_epoch~ : Int)
  // The local Proton notification subscriber overflowed and was replaced;
  // request promises remain live, unlike a transport reconnect.
  NotificationGap(channel~ : @interop.ChannelId)
  BrowserEvent(payload~ : Map[String, Json])
  MenuCommand(command_id~ : String)
  NotificationClicked(run_id~ : String)
}
