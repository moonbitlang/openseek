// The terminal panel's bridge calls, routed by the channel that owns each tab.
// `terminal.open` folds its
// reply back into the update loop; the steady-state ops are fire-and-forget
// — input failures surface as `InputFailed` (an error toast),
// resize/close failures are dropped (their loss only degrades, and a dead
// session reports itself through `terminal_exit`). Flow-control acks retry
// until the host accepts their idempotent output sequence.

///|
const AckRetryDelayMs = 100

///|
fn open_session(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  key : Int,
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
  @cmd.custom_cmd(_scheduler => {
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
/// One output acknowledgement. Within its owning connection, retrying the
/// same session/sequence pair is safe because the host removes each
/// outstanding sequence at most once.
priv struct TerminalAck {
  channel : @interop.ChannelId
  id : String
  sequence : Int
}

///|
fn TerminalAck::send(self : TerminalAck) -> @cmd.Cmd {
  @cmd.custom_cmd(_scheduler => {
    @js.async_run(() => {
      ignore(
        @interop.bridge_request(self.channel, @commands.terminal_ack, {
          id: self.id,
          sequence: self.sequence,
        }) catch {
          _ => {
            // UUIDs are never reassigned, so a retry cannot acknowledge a
            // replacement terminal. Keep the existing retry only for the
            // in-process bridge; a remote WebSocket failure tears down the
            // connection and all PTYs it owned.
            if self.channel is @interop.ChannelId::Local {
              _scheduler.add(@cmd.delay(self.send(), AckRetryDelayMs))
            }
            return
          }
        },
      )
    })
  })
}

///|
fn send_close(channel : @interop.ChannelId, id : String) -> @cmd.Cmd {
  @cmd.custom_cmd(_scheduler => {
    @js.async_run(() => {
      ignore(
        @interop.bridge_request(channel, @commands.terminal_close, { id, }) catch {
          _ => return
        },
      )
    })
  })
}
