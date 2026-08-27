// The terminal panel's bridge calls, routed by the channel that owns each tab.
// `terminal.open` folds its
// reply back into the update loop; the steady-state ops are fire-and-forget
// — input failures surface as `InputFailed` (an error toast),
// resize/close failures are dropped (their loss only degrades, and a dead
// session reports itself through `terminal_exit`). Flow-control acks are sent
// once after xterm renders their output sequence.

///|
fn open_session(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  key : String,
  session : String,
  workspace : @common.Uri?,
  cols : Int,
  rows : Int,
) -> @cmd.Cmd {
  match workspace {
    Some(resource) if !@resource.belongs_to(resource, channel) =>
      return @cmd.none
    _ => ()
  }
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply = @interop.bridge_request(channel, @commands.terminal_open, {
        session,
        workspace: workspace.map(value => value.path),
        cols,
        rows,
      }) catch {
        error => {
          scheduler.add(
            dispatch(
              OpenFailed(key~, message=@interop.bridge_error_text(error)),
            ),
          )
          return
        }
      }
      scheduler.add(dispatch(Opened(channel~, key~, id=reply.id)))
    })
  })
}

///|
fn send_input(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  id : String,
  data : String,
  binary : Bool,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      ignore(
        @interop.bridge_request(channel, @commands.terminal_input, {
          id,
          data: if binary {
            None
          } else {
            Some(data)
          },
          data_base64: if binary {
            Some(data)
          } else {
            None
          },
        }) catch {
          error => {
            scheduler.add(
              dispatch(InputFailed(message=@interop.bridge_error_text(error))),
            )
            return
          }
        },
      )
    })
  })
}

///|
fn send_resize(
  channel : @interop.ChannelId,
  id : String,
  cols : Int,
  rows : Int,
) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => {
    @js.async_run(() => {
      ignore(
        @interop.bridge_request(channel, @commands.terminal_resize, {
          id,
          cols,
          rows,
        }) catch {
          _ => return
        },
      )
    })
  })
}

///|
/// One output acknowledgement, sent after xterm has rendered the chunk. A
/// failed bridge no longer owns a PTY or flow-control window to release, so
/// the acknowledgement is not retried.
priv struct TerminalAck {
  channel : @interop.ChannelId
  id : String
  sequence : Int
}

///|
fn TerminalAck::send(self : TerminalAck) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => {
    @js.async_run(() => {
      ignore(
        @interop.bridge_request(self.channel, @commands.terminal_ack, {
          id: self.id,
          sequence: self.sequence,
        }) catch {
          _ => return
        },
      )
    })
  })
}

///|
fn send_close(channel : @interop.ChannelId, id : String) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => {
    @js.async_run(() => {
      ignore(
        @interop.bridge_request(channel, @commands.terminal_close, { id, }) catch {
          _ => return
        },
      )
    })
  })
}
