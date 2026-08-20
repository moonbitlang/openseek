///|
/// Application-owned values read by the terminal component. Tabs and emulator
/// lifecycle remain exclusively in the terminal Model.
struct Input {
  ctx : Ctx
  live_channels : Array[@interop.ChannelId]
  connections : Array[Connection]
} derive(Eq)

///|
/// One device's current host transport generation. The entry remains while
/// its socket is temporarily down and disappears only when the device itself
/// is removed; `attempt` advances when reconnect backoff expires.
struct Connection {
  channel : @interop.ChannelId
  websocket_epoch : Int
  attempt : Int
} derive(Eq)

///|
pub fn Connection::Connection(
  channel~ : @interop.ChannelId,
  websocket_epoch~ : Int,
  attempt~ : Int,
) -> Connection {
  { channel, websocket_epoch, attempt }
}

///|
pub fn Input::Input(
  ctx~ : Ctx,
  live_channels~ : Array[@interop.ChannelId],
  connections~ : Array[Connection],
) -> Input {
  { ctx, live_channels, connections }
}

///|
/// A signed-out console has no devices. Close the panel at that ownership
/// boundary, but preserve the user's visibility choice while retained devices
/// reconnect; their old PTYs are still retired through `live_channels`
/// reconciliation.
fn State::close_without_devices(self : State, device_count : Int) -> State {
  if device_count == 0 {
    { ..self, open: false }
  } else {
    self
  }
}

///|
/// Reconcile parent-owned inputs after every root update. Channel retirement,
/// transport installation, conversation switches, and theme changes are all
/// ordinary state transitions; no rendered marker or DOM observer is needed.
pub fn State::reconcile(
  self : State,
  dispatch : @cmd.Emit[Msg],
  input : Input,
  connect : (@interop.ChannelId, Int) -> @cmd.Cmd,
) -> (State, @cmd.Cmd) {
  let commands : Array[@cmd.Cmd] = []
  let mut state = self
  for channel in self.live_channels {
    if !input.live_channels.contains(channel) {
      let (command, next) = disconnect(state, channel)
      commands.push(command)
      state = next
    }
  }
  for connection in input.connections {
    if !self.connections.contains(connection) {
      commands.push(connect(connection.channel, connection.websocket_epoch))
    }
  }
  state = state.close_without_devices(input.connections.length())
  let (state, sync_command) = sync(dispatch, state, input.ctx)
  commands.push(sync_command)
  // Output bypasses Rabbita, so refresh the terminal package's imperative
  // session-to-emulator routing after the low-frequency state transition that
  // can change it. This is a projection of `State`, not a second state owner.
  commands.push(state.sync_host_routes())
  (
    {
      ..state,
      live_channels: input.live_channels,
      connections: input.connections,
    },
    @cmd.batch(commands),
  )
}

///|
/// Render the root-owned terminal state directly.
pub fn component(
  input : @rabbita.Val[Input],
  state : @rabbita.Val[State],
  dispatch : @cmd.Emit[Msg],
) -> @rabbita.Val[@html.Html] {
  state.view2(input, (state, input) => panel_view(dispatch, state, input.ctx))
}

///|
test "terminal visibility distinguishes disconnect from device removal" {
  let open = { ..State::empty(), open: true }
  let disconnected = open.close_without_devices(1)
  assert_true(disconnected.open)
  let signed_out = open.close_without_devices(0)
  assert_false(signed_out.open)
}

///|
pub extend Connection with Eq::{equal, not_equal}

///|
pub extend Input with Eq::{equal, not_equal}
