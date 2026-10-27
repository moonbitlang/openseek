// The terminal panel's bridge calls, routed by the channel that owns each tab.
// `terminal.open` folds its
// reply back into the update loop; input writes settle one bounded per-tab
// queue through InputSettled. Transport loss waits for channel reconnection;
// other input failures pause that queue with a toast;
// resize/close failures are dropped (their loss only degrades, and a dead
// session reports itself through `terminal_exit`). Flow-control acks are sent
// once after xterm renders their output sequence.

///|
fn open_session(
  dispatch : @cmd.Emit[Msg],
  channel : Connection,
  key : String,
  session : String,
  workspace : @common.Uri?,
  cols : Int32,
  rows : Int32,
  command? : String,
) -> @cmd.Cmd {
  match workspace {
    Some(resource) if channel is Host(host) &&
      !@resource.belongs_to(resource, host) => return @cmd.none
    _ => ()
  }
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let reply = try {
        if channel is Cloud(..) {
          ignore(connect_cloud(dispatch, scheduler, channel))
        }
        terminal_request(channel, @commands.terminal_open, {
          session,
          workspace: workspace.map(value => value.path),
          cols,
          rows,
          command,
        })
      } catch {
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
    |> ignore
  })
}

///|
fn send_input(
  dispatch : @cmd.Emit[Msg],
  channel : Connection,
  key : String,
  id : String,
  batch : InputBatch,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let result : Result[Unit, InputWriteFailure] = try {
        ignore(
          terminal_request(channel, @commands.terminal_input, {
            id,
            data: if batch.chunk.binary {
              None
            } else {
              Some(batch.chunk.data)
            },
            data_base64: if batch.chunk.binary {
              Some(batch.chunk.data)
            } else {
              None
            },
          }),
        )
        Ok(())
      } catch {
        error =>
          if connection_lost(channel, error) {
            Err(ConnectionLost)
          } else {
            Err(WriteFailed(@interop.bridge_error_text(error)))
          }
      }
      scheduler.add(
        dispatch(InputSettled(key~, id~, token=batch.token, result~)),
      )
    })
    |> ignore
  })
}

///|
fn send_resize(
  channel : Connection,
  id : String,
  cols : Int32,
  rows : Int32,
) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => {
    @js.Promise::from_async(() => {
      ignore(
        terminal_request(channel, @commands.terminal_resize, { id, cols, rows, }) catch {
          _ => return
        },
      )
    })
    |> ignore
  })
}

///|
/// One output acknowledgement, sent after xterm has rendered the chunk. The
/// host treats `sequence` cumulatively, so a later successful acknowledgement
/// also covers this one if the request does not reach the host; no retry timer
/// is needed.
priv struct TerminalAck {
  channel : Connection
  id : String
  sequence : Int32
}

///|
fn TerminalAck::send(self : TerminalAck) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => {
    @js.Promise::from_async(() => {
      ignore(
        terminal_request(self.channel, @commands.terminal_ack, {
          id: self.id,
          sequence: self.sequence,
        }) catch {
          _ => return
        },
      )
    })
    |> ignore
  })
}

///|
fn send_close(channel : Connection, id : String) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => {
    @js.Promise::from_async(() => {
      ignore(
        terminal_request(channel, @commands.terminal_close, { id, }) catch {
          _ => return
        },
      )
    })
    |> ignore
  })
}
