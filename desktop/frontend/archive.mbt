// The sidebar's archive flow: `archive_session` asks the host to move a
// conversation's durable record into its store's `archived` twin,
// `unarchive_session` moves it back, and `archived_sessions` reads the
// archived conversations back. All three ops reply with the archived groups
// in the same shape as `list_sessions`, so one decoder serves them all —
// and since archiving moves records between the stores the sidebar lists,
// the two action commands refresh the live list too.

///|
fn fetch_archived(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  connection_generation : Int,
  request_generation : Int,
) -> @cmd.Cmd {
  let dispatch = dispatch.map((msg : DeviceMsg) => FromDevice(channel, msg))
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      // A host without the op (or without a session store) just reads as an
      // empty Archived group.
      let reply = @interop.bridge_request(
        channel,
        "session.list_archived",
        @js.Object::new().to_value(),
      ) catch {
        _ => return
      }
      scheduler.add(
        dispatch(
          ArchivedLoaded(
            @transcript.decode_sessions_reply(@interop.reply_json_text(reply)).unwrap_or([],
            ),
            connection_generation~,
            request_generation~,
            fresh_session=generated_session_id(),
          ),
        ),
      )
    })
  })
}

///|
fn archive_session(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  session : String,
  connection_generation : Int,
  sessions_request_generation : Int,
  archived_request_generation : Int,
) -> @cmd.Cmd {
  archive_action(
    dispatch, channel, "session.archive", session, connection_generation, sessions_request_generation,
    archived_request_generation,
  )
}

///|
fn unarchive_session(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  session : String,
  connection_generation : Int,
  sessions_request_generation : Int,
  archived_request_generation : Int,
) -> @cmd.Cmd {
  archive_action(
    dispatch, channel, "session.unarchive", session, connection_generation, sessions_request_generation,
    archived_request_generation,
  )
}

///|
fn archive_action(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  op : String,
  session : String,
  connection_generation : Int,
  sessions_request_generation : Int,
  archived_request_generation : Int,
) -> @cmd.Cmd {
  let dispatch = dispatch.map((msg : DeviceMsg) => FromDevice(channel, msg))
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let payload = @js.Object::new()
      payload["session"] = session
      let reply = @interop.bridge_request(channel, op, payload.to_value()) catch {
        error => {
          scheduler.add(
            dispatch(ArchiveFailed(@interop.bridge_error_text(error))),
          )
          return
        }
      }
      scheduler.add(
        dispatch(
          ArchivedLoaded(
            @transcript.decode_sessions_reply(@interop.reply_json_text(reply)).unwrap_or([],
            ),
            connection_generation~,
            request_generation=archived_request_generation,
            fresh_session=generated_session_id(),
          ),
        ),
      )
      // The record moved between the live and archived stores; the sidebar's
      // live list is stale until re-fetched.
      let sessions = @interop.bridge_request(
        channel,
        "session.list",
        @js.Object::new().to_value(),
      ) catch {
        error => {
          scheduler.add(
            dispatch(SessionsFailed(@interop.bridge_error_text(error))),
          )
          return
        }
      }
      match
        @transcript.decode_sessions_reply(@interop.reply_json_text(sessions)) {
        Some(items) =>
          scheduler.add(
            dispatch(
              SessionsLoaded(
                items,
                connection_generation~,
                request_generation=sessions_request_generation,
              ),
            ),
          )
        None =>
          scheduler.add(dispatch(SessionsFailed("malformed session list")))
      }
    })
  })
}
