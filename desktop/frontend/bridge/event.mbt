// Events emitted by a live engine-host connection. This package owns the
// transport lifecycle and wire-facing payload extraction; the parent
// frontend decides how each event changes application state.

///|
/// One event observed from a local Proton host or remote relay device. The
/// parent frontend pattern-matches this value to apply application policy.
pub enum Event {
  Notification(
    channel~ : @interop.ChannelId,
    websocket_epoch~ : Int,
    notification~ : @protocol.Notification
  )
  Unavailable(channel~ : @interop.ChannelId, message~ : String)
  ChannelDown(channel~ : @interop.ChannelId, websocket_epoch~ : Int)
  BrowserEvent(payload~ : Map[String, Json])
  MenuCommand(command_id~ : String)
  NotificationClicked(run_id~ : String)
}

///|
/// Decide whether a transport event needs a Rabbita command. High-frequency
/// events handled directly by a component return `None`, so the connection
/// does not enqueue an empty command and trigger an unrelated root render.
pub struct EventHandler((Event) -> @cmd.Cmd?)

///|
pub fn EventHandler::new(handle : (Event) -> @cmd.Cmd?) -> EventHandler {
  EventHandler(handle)
}

///|
fn EventHandler::enqueue(
  self : EventHandler,
  scheduler : &@cmd.Scheduler,
  event : Event,
) -> Unit {
  if self.0(event) is Some(command) {
    scheduler.add(command)
  }
}
