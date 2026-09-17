// Events emitted by a live engine-host connection. This package owns the
// transport lifecycle and wire-facing payload extraction; the parent
// frontend decides how each event changes application state.

///|
/// One event observed from the local host or a remote relay device. The
/// parent frontend pattern-matches this value to apply application policy.
/// `MenuCommand` and `NotificationClicked` come from Proton's injected
/// runtime and only ever occur on the desktop window's local connection.
pub enum Event {
  Notification(
    channel~ : @interop.ChannelId,
    notification~ : @protocol.Notification
  )
  ChannelDown(channel~ : @interop.ChannelId, websocket_epoch~ : Int)
  MenuCommand(command_id~ : String)
  NotificationClicked(run_id~ : String)
}
