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
  channel : @interop.ChannelId,
  key : String,
  session : String,
  workspace : @common.Uri?,
  cols : Int32,
  rows : Int32,
  command? : String,
) -> @cmd.Cmd {
  match workspace {
    Some(resource) if !@resource.belongs_to(resource, channel) =>
      return @cmd.none
    _ => ()
  }
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let reply = @interop.bridge_request(channel, @commands.terminal_open, {
        session,
        workspace: workspace.map(value => value.path),
        cols,
        rows,
        command,
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
    |> ignore
  })
}

///|
fn send_input(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  key : String,
  id : String,
  batch : InputBatch,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let result : Result[Unit, InputWriteFailure] = try {
        ignore(
          @interop.bridge_request(channel, @commands.terminal_input, {
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
          if @interop.bridge_connection_lost(channel, error) {
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
  channel : @interop.ChannelId,
  id : String,
  cols : Int32,
  rows : Int32,
) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => {
    @js.Promise::from_async(() => {
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
    |> ignore
  })
}

///|
/// One output acknowledgement, sent after xterm has rendered the chunk. The
/// host treats `sequence` cumulatively, so a later successful acknowledgement
/// also covers this one if the request does not reach the host; no retry timer
/// is needed.
priv struct TerminalAck {
  channel : @interop.ChannelId
  id : String
  sequence : Int32
}

///|
fn TerminalAck::send(self : TerminalAck) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => {
    @js.Promise::from_async(() => {
      ignore(
        @interop.bridge_request(self.channel, @commands.terminal_ack, {
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
fn send_close(channel : @interop.ChannelId, id : String) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => {
    @js.Promise::from_async(() => {
      ignore(
        @interop.bridge_request(channel, @commands.terminal_close, { id, }) catch {
          _ => return
        },
      )
    })
    |> ignore
  })
}

///|
fn reattach_session(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  key : String,
  id : String,
  generation : Int32,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    guard term_host.entries.get(key) is Some(entry) else { return }
    let sequence = entry.received
    @js.Promise::from_async(() => {
      let result = try {
        let reply = @interop.bridge_request(
          channel,
          @commands.terminal_attach,
          { id, sequence, },
        )
        Ok(reply.attached)
      } catch {
        error =>
          if @interop.bridge_connection_lost(channel, error) {
            Err(ConnectionLost)
          } else {
            Err(WriteFailed(@interop.bridge_error_text(error)))
          }
      }
      scheduler.add(
        dispatch(Reattached(channel~, id~, key~, generation~, result~)),
      )
    })
    |> ignore
  })
}

///|
fn refit_tab(
  channel : @interop.ChannelId,
  key : String,
  id : String?,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    guard id is Some(id) && term_host.entries.get(key) is Some(entry) else {
      return
    }
    let cols : Int32 = entry.term.get_with_string("cols")
    let rows : Int32 = entry.term.get_with_string("rows")
    scheduler.add(send_resize(channel, id, cols, rows))
  })
}
