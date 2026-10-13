// The sidebar's archive flow: `archive_session` asks the host to move a
// conversation's durable record into its store's `archived` twin,
// `unarchive_session` moves it back, `delete_archived_session` permanently
// removes its archived record, and `archived_sessions` reads the remaining
// conversations back. Successful ops reply with archived groups in
// the same shape as `list_sessions`; archive can instead return a structured
// dirty-checkout confirmation state. Since the actions move records between
// the stores the sidebar lists, both commands refresh the live list too.
// `delete_session` permanently removes a live record without the stop in the
// archive.

///|
/// The exact live or archived row awaiting permanent-deletion confirmation.
/// The visible title is captured with the identity so another render cannot
/// make the dialog appear to authorize a different conversation.
priv struct DeleteConfirm {
  channel : @interop.ChannelId
  key : ArchiveRecordKey
  record : ConversationRecord
  // The parent plus every descendant visible in the same listed snapshot.
  // Host notifications still cover a child created after that snapshot.
  sessions : Array[String]
  title : String
  // A live chat's checkout is removed with the chat, and a clean one —
  // ignored files included — goes without a second question, so this dialog
  // has to say so.
  checkout : DeleteCheckout
} derive(Eq)

///|
/// What deleting a chat does to a worktree checkout, as far as this page
/// knows. An archived chat has none: its checkout went when it was archived.
priv enum DeleteCheckout {
  NoCheckout
  Checkout(String)
  // The project's worktree registry has not been read. A pending or failed
  // list is not an empty one, so the dialog must not promise there is none.
  UnknownCheckout
} derive(Eq)

///|
fn fetch_archived(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  connection_generation : Int32,
  request_generation : Int32,
) -> @cmd.Cmd {
  let dispatch = dispatch.map((msg : DeviceMsg) => FromDevice(channel, msg))
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      // A host without the op (or without a session store) just reads as an
      // empty Archived group.
      let reply = @interop.bridge_request(
        channel,
        @commands.session_list_archived,
        @protocol.EmptyPayload::NoPayload,
      ) catch {
        _ => return
      }
      scheduler.add(
        dispatch(
          ArchivedLoaded(
            @transcript.sessions_from_reply(reply, channel),
            connection_generation~,
            request_generation~,
            fresh_session=generated_session_id(),
          ),
        ),
      )
    })
    |> ignore
  })
}

///|
fn archive_session(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  session : String,
  connection_generation : Int32,
  sessions_request_generation : Int32,
  archived_request_generation : Int32,
  force~ : Bool = false,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      archive_session_into(
        scheduler, dispatch, channel, session, connection_generation, sessions_request_generation,
        archived_request_generation, force,
      )
    })
    |> ignore
  })
}

///|
async fn archive_session_into(
  scheduler : &@cmd.Scheduler,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  session : String,
  connection_generation : Int32,
  sessions_request_generation : Int32,
  archived_request_generation : Int32,
  force : Bool,
) -> Unit noraise {
  let reply = @interop.bridge_request(
    channel,
    @commands.session_archive,
    // Archiving removes the conversation's checkout but retains its placement;
    // the retry after the discard-confirmation dialog carries force on the
    // wire.
    { session, force: if force { Some(true) } else { None }, },
  ) catch {
    error => {
      scheduler.add(
        dispatch.map((msg : DeviceMsg) => FromDevice(channel, msg))(
          ArchiveFailed(@interop.bridge_error_text(error)),
        ),
      )
      return
    }
  }
  match reply {
    NeedsForce(refusal) =>
      scheduler.add(
        dispatch.map((msg : DeviceMsg) => FromDevice(channel, msg))(
          ArchiveNeedsForce(session~, refusal~, retry=RetryArchive),
        ),
      )
    Archived(reply) =>
      apply_archive_list_reply(
        scheduler, dispatch, channel, reply, connection_generation, sessions_request_generation,
        archived_request_generation,
      )
  }
}

///|
fn unarchive_session(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  session : String,
  connection_generation : Int32,
  sessions_request_generation : Int32,
  archived_request_generation : Int32,
) -> @cmd.Cmd {
  archive_action(
    dispatch,
    channel,
    @commands.session_unarchive,
    { session, force: None, },
    connection_generation,
    sessions_request_generation,
    archived_request_generation,
  )
}

///|
/// Permanently delete one archived conversation. The response carries the
/// remaining archived list; the deleted identity is kept beside it because
/// list replies are unversioned and can race the host's notification.
fn delete_archived_session(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  key : ArchiveRecordKey,
  sessions : Array[String],
  connection_generation : Int32,
  archived_request_generation : Int32,
) -> @cmd.Cmd {
  guard key.workspace_payload(channel) is Some(workspace) else {
    return @cmd.none
  }
  let device_dispatch = dispatch.map((msg : DeviceMsg) => {
    FromDevice(channel, msg)
  })
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let reply = @interop.bridge_request(
        channel,
        @commands.session_delete_archived,
        { session: key.session, workspace, },
      ) catch {
        error => {
          scheduler.add(
            device_dispatch(DeleteFailed(@interop.bridge_error_text(error))),
          )
          return
        }
      }
      scheduler.add(
        device_dispatch(
          ArchivedDeleted(
            key~,
            sessions~,
            items=@transcript.sessions_from_reply(reply, channel),
            connection_generation~,
            request_generation=archived_request_generation,
            fresh_session=generated_session_id(),
          ),
        ),
      )
    })
    |> ignore
  })
}

///|
/// Permanently delete one live conversation. A committed delete folds
/// nothing from its reply: the host announces every removed identity through
/// `session.changed`, to this client like any other. A dirty worktree comes
/// back as the same confirmation state archiving uses.
fn delete_session(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  key : ArchiveRecordKey,
  force~ : Bool = false,
) -> @cmd.Cmd {
  guard key.workspace_payload(channel) is Some(workspace) else {
    return @cmd.none
  }
  let device_dispatch = dispatch.map((msg : DeviceMsg) => {
    FromDevice(channel, msg)
  })
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let reply = @interop.bridge_request(channel, @commands.session_delete, {
        session: key.session,
        workspace,
        force: if force {
          Some(true)
        } else {
          None
        },
      }) catch {
        error => {
          scheduler.add(
            device_dispatch(DeleteFailed(@interop.bridge_error_text(error))),
          )
          return
        }
      }
      if reply is NeedsForce(refusal) {
        scheduler.add(
          device_dispatch(
            ArchiveNeedsForce(
              session=key.session,
              refusal~,
              retry=RetryDelete(workspace=key.workspace),
            ),
          ),
        )
      }
    })
    |> ignore
  })
}

///|
/// Permanent chat deletion requires a second, explicit click. The
/// copy names what disappears and what survives so the user does not have to
/// infer filesystem or Git consequences from the word "delete".
fn delete_modal(
  locale~ : @i18n.Locale = English,
  dispatch : @cmd.Emit[Msg],
  confirm : DeleteConfirm,
) -> @html.Html {
  @html.div(class="modal-backdrop", on_click=dispatch(CancelDeleteSession), [
    @html.div(class="modal", [
      @html.div(class="modal-title", shell_text(locale, DeleteChatQuestion)),
      @html.div(
        class="modal-body",
        dynamic_text(
          locale,
          match confirm.checkout {
            NoCheckout => DDeleteConversation(confirm.title.to_string())
            Checkout(worktree) =>
              DDeleteWorktreeConversation(
                confirm.title.to_string(),
                worktree.to_string(),
              )
            UnknownCheckout =>
              DDeleteMaybeWorktreeConversation(confirm.title.to_string())
          },
        ),
      ),
      @html.div(class="modal-actions", [
        @html.button(
          class="button secondary",
          on_click=dispatch(CancelDeleteSession),
          shell_text(locale, CancelLabel),
        ),
        @html.button(
          class="button danger",
          on_click=dispatch(ConfirmDeleteSession),
          shell_text(locale, DeletePermanently),
        ),
      ]),
    ]),
  ])
}

///|
fn archive_action(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  command : @commands.Command[@protocol.SessionPayload, @protocol.SessionsReply],
  payload : @protocol.SessionPayload,
  connection_generation : Int32,
  sessions_request_generation : Int32,
  archived_request_generation : Int32,
) -> @cmd.Cmd {
  let device_dispatch = dispatch.map((msg : DeviceMsg) => {
    FromDevice(channel, msg)
  })
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let reply = @interop.bridge_request(channel, command, payload) catch {
        error => {
          scheduler.add(
            device_dispatch(ArchiveFailed(@interop.bridge_error_text(error))),
          )
          return
        }
      }
      apply_archive_list_reply(
        scheduler, dispatch, channel, reply, connection_generation, sessions_request_generation,
        archived_request_generation,
      )
    })
    |> ignore
  })
}

///|
/// Fold the archived-list reply from a successful archive/unarchive, then
/// refresh the live list that the record move made stale.
async fn apply_archive_list_reply(
  scheduler : &@cmd.Scheduler,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  reply : @protocol.SessionsReply,
  connection_generation : Int32,
  sessions_request_generation : Int32,
  archived_request_generation : Int32,
) -> Unit noraise {
  scheduler.add(
    dispatch.map((msg : DeviceMsg) => FromDevice(channel, msg))(
      ArchivedLoaded(
        @transcript.sessions_from_reply(reply, channel),
        connection_generation~,
        request_generation=archived_request_generation,
        fresh_session=generated_session_id(),
      ),
    ),
  )
  // The record moved between the live and archived stores; the sidebar's
  // live list is stale until re-fetched.
  refresh_sessions_into(
    scheduler, dispatch, channel, connection_generation, sessions_request_generation,
  )
}
