///|
/// Project the active conversation and live device set into the terminal
/// package. The projection is read-only; the opaque terminal state itself is
/// stored once in the application Model. Native SSH terminal connections belong
/// to the window, so app-server disconnects do not retire their tab ids.
fn Model::terminal_input(self : Model) -> @terminal.Input {
  @terminal.Input(
    ctx=terminal_ctx(self),
    live_channels=self.devices
      .iter()
      .filter_map(dev => {
        if @interop.is_native_ssh(dev.channel) ||
          (dev.bridge is Connected && dev.reconnect_failures == 0) {
          Some(dev.channel)
        } else {
          None
        }
      })
      .to_array(),
    has_devices=!self.devices.is_empty(),
  )
}
