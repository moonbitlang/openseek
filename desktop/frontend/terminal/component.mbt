///|
/// Application-owned values read by the terminal component. Tabs and emulator
/// lifecycle remain exclusively in the terminal Model.
struct Input {
  ctx : Ctx
  live_channels : Array[@interop.ChannelId]
  connections : Array[Connection]
} derive(Eq)

///|
/// One host transport generation the terminal must listen to. `attempt`
/// advances only when reconnect backoff expires, not when the socket drops.
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
/// Effects that belong to the application shell rather than the terminal.
pub(all) struct Actions {
  external_link : @cmd.Emit[String]
  error : @cmd.Emit[String]
  visibility : @cmd.Emit[Bool]
  connect : (@cmd.Emit[Msg], @interop.ChannelId, Int) -> @cmd.Cmd
}

///|
priv struct ComponentModel {
  terminal : State
  live_channels : Array[@interop.ChannelId]
  connections : Array[Connection]
} derive(Eq)

///|
priv enum ComponentMsg {
  Terminal(TerminalMsg)
  InputRendered
}

///|
/// Build the terminal state machine and return both independently updating
/// Html and Rabbita's real emitter. There is no late-installed nullable
/// reference between the host notification source and this component.
pub fn component(
  input : @rabbita.Val[Input],
  actions : Actions,
) -> (@rabbita.Val[@html.Html], @cmd.Emit[Msg]) {
  let (state, component_emit) = @rabbita.create_state_with_input(
    input~,
    init=(emit, _) => {
      (
        { terminal: State::empty(), live_channels: [], connections: [] },
        emit(InputRendered),
      )
    },
    update=(model, input, component_msg, component_emit) => {
      let emit = component_emit.map(msg => Terminal(msg))
      let external_emit = component_emit.map(msg => Terminal(External(msg)))
      let state = model.terminal
      if component_msg is InputRendered {
        let commands : Array[@cmd.Cmd] = []
        let mut state = state
        for channel in model.live_channels {
          if !input.live_channels.contains(channel) {
            let (command, next) = disconnect(state, channel)
            commands.push(command)
            state = next
          }
        }
        for connection in input.connections {
          if !model.connections.contains(connection) {
            commands.push(
              (actions.connect)(
                external_emit,
                connection.channel,
                connection.websocket_epoch,
              ),
            )
          }
        }
        let (state, sync_command) = sync(emit, state, input.ctx)
        commands.push(sync_command)
        return (
          {
            terminal: state,
            live_channels: input.live_channels,
            connections: input.connections,
          },
          @cmd.batch(commands),
        )
      }
      guard component_msg is Terminal(msg) else { return (model, @cmd.none) }
      // xterm recognizes links; the application chooses whether they open in
      // an embedded browser tab or the system browser.
      if msg is LinkActivated(url~) {
        return (model, (actions.external_link)(url))
      }
      // Replies queued by a retired connection cannot attach to a later PTY
      // that happens to reuse the same numeric id.
      let owner_live = match msg {
        Opened(channel~, key=_, id=_)
        | OutputRendered(channel~, id=_, sequence=_)
        | External(Output(channel~, id=_, sequence=_, data=_))
        | External(SessionExited(channel~, id=_, code=_)) =>
          input.live_channels.contains(channel)
        _ => true
      }
      guard owner_live else { return (model, @cmd.none) }
      let was_open = state.open
      let (command, state) = update(emit, msg, state, input.ctx)
      let (state, sync_command) = sync(emit, state, input.ctx)
      let error_command = match msg {
        InputFailed(message~) => (actions.error)(message)
        _ => @cmd.none
      }
      let visibility_command = if state.open != was_open {
        (actions.visibility)(state.open)
      } else {
        @cmd.none
      }
      (
        { ..model, terminal: state },
        @cmd.batch([command, sync_command, error_command, visibility_command]),
      )
    },
    subscriptions=(_, _, emit) => terminal_subscription(emit),
  )
  let emit = component_emit.map(msg => Terminal(msg))
  (
    state.view2(input, (model, input) => {
      panel_view(emit, model.terminal, input.ctx, input.sync_key())
    }),
    component_emit.map(msg => Terminal(External(msg))),
  )
}

///|
/// This explicit DOM attribute changes whenever terminal-relevant application
/// input changes. The component observes it and reconciles against the latest
/// `Input`; the root never calls into terminal state.
fn Input::sync_key(self : Input) -> String {
  let checkout = match self.ctx.checkout {
    None => "pending"
    Some(@interop.WorkspaceRoot) => "workspace"
    Some(@interop.Worktree(name~)) => "worktree:" + name
    Some(@interop.MissingWorktree(name~)) => "missing:" + name
  }
  let workspace = self.ctx.workspace
    .map(resource => resource.path)
    .unwrap_or("")
  let connections = self.connections
    .map(connection => {
      connection.channel.uri_authority() +
      ":" +
      connection.websocket_epoch.to_string() +
      ":" +
      connection.attempt.to_string()
    })
    .join(",")
  let live = self.live_channels
    .map(channel => channel.uri_authority())
    .join(",")
  [
    self.ctx.channel.uri_authority(),
    self.ctx.session,
    workspace,
    checkout,
    self.ctx.dark_mode.to_string(),
    self.ctx.connected.to_string(),
    live,
    connections,
  ].join("|")
}
