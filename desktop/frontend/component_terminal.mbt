///|
/// Project the active conversation and live device set into the terminal
/// package. The projection is read-only; the opaque terminal state itself is
/// stored once in the application Model.
fn Model::terminal_input(self : Model) -> @terminal.Input {
  @terminal.Input(
    ctx=terminal_ctx(self),
    live_channels=self.devices
      .iter()
      .filter_map(dev => {
        if dev.bridge is Connected && dev.reconnect_failures == 0 {
          Some(dev.channel)
        } else {
          None
        }
      })
      .to_array(),
    devices=self.devices.map(dev => dev.channel),
  )
}
