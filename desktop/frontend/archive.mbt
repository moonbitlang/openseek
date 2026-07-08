// The sidebar's archive flow: `archive_session` asks the host to move a
// conversation's durable record into its store's `archived` twin,
// `unarchive_session` moves it back, and `archived_sessions` reads the
// archived conversations back. All three ops reply with the archived groups
// in the same shape as `list_sessions`, so one decoder serves them all —
// and since archiving moves records between the stores the sidebar lists,
// the two action commands refresh the live list too.

///|
fn fetch_archived(dispatch : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      // A host without the op (or without a session store) just reads as an
      // empty Archived group.
      let reply = @interop.bridge_request(
        "archived_sessions",
        @js.Object::new().to_value(),
      ) catch {
        _ => return
      }
      scheduler.add(
        dispatch(
          ArchivedLoaded(
            @transcript.decode_sessions_reply(@interop.reply_json_text(reply)).unwrap_or([],
            ),
          ),
        ),
      )
    })
  })
}

///|
fn archive_session(dispatch : @cmd.Emit[Msg], session : String) -> @cmd.Cmd {
  archive_action(dispatch, "archive_session", session)
}

///|
fn unarchive_session(dispatch : @cmd.Emit[Msg], session : String) -> @cmd.Cmd {
  archive_action(dispatch, "unarchive_session", session)
}

///|
fn archive_action(
  dispatch : @cmd.Emit[Msg],
  op : String,
  session : String,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let payload = @js.Object::new()
      payload["session"] = session
      let reply = @interop.bridge_request(op, payload.to_value()) catch {
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
          ),
        ),
      )
      // The record moved between the live and archived stores; the sidebar's
      // live list is stale until re-fetched.
      let sessions = @interop.bridge_request(
        "list_sessions",
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
        Some(items) => scheduler.add(dispatch(SessionsLoaded(items)))
        None =>
          scheduler.add(dispatch(SessionsFailed("malformed session list")))
      }
    })
  })
}
