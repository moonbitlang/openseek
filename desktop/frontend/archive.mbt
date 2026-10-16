// The sidebar's archive flow: `archive_session` asks the host to move a
// conversation's durable record into its store's `archived` twin,
// `unarchive_session` moves it back, `delete_archived_session` permanently
// removes its archived record, and `archived_sessions` reads the remaining
// conversations back. Successful ops reply with archived groups in
// the same shape as `list_sessions`; archive can instead return a structured
// dirty-checkout confirmation state. Since the actions move records between
// the stores the sidebar lists, both commands refresh the live list too.
// `delete_session` permanently removes a live record without the stop in the
// archive; `check_delete_session` asks first what goes with it.

///|
/// The exact live or archived row awaiting permanent-deletion confirmation.
/// The visible title is captured with the identity so another render cannot
/// make the dialog appear to authorize a different conversation.
priv struct DeleteConfirm {
  channel : @interop.ChannelId
  key : ArchiveRecordKey
  title : String
  target : DeleteTarget
} derive(Eq)

///|
/// Which record a confirmation is about, with what only that kind carries.
priv enum DeleteTarget {
  // The parent plus every descendant visible in the same archived snapshot.
  // Host notifications still cover a child created after that snapshot.
  ArchivedChat(sessions~ : Array[String])
  // The worktree checkout the host reported goes with the chat, if any. An
  // archived chat has none: its checkout went when it was archived.
  LiveChat(checkout~ : @protocol.CheckoutRemoval?)
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
      let reply = @interop.bridge_request(
        channel,
        @commands.session_list_archived,
        @protocol.EmptyPayload::NoPayload,
      ) catch {
        error => {
          scheduler.add(
            dispatch(
              ArchivedFailed(
                message=@interop.bridge_error_text(error),
                connection_generation~,
                request_generation~,
              ),
            ),
          )
          return
        }
      }
      // Navigation can establish absence only from a complete inventory.
      // Keep store failures distinct from an empty archived list.
      for group in reply.groups {
        if !group.error.is_empty() {
          scheduler.add(
            dispatch(
              ArchivedFailed(
                message="\{group.workspace}: \{group.error}",
                connection_generation~,
                request_generation~,
              ),
            ),
          )
          return
        }
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
          ArchiveNeedsForce(session~, refusal~),
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
/// Ask the host what deleting one live conversation would remove besides its
/// record. The confirmation is staged from the answer, so it states what the
/// host will do instead of what this page's lists suggest.
fn check_delete_session(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  key : ArchiveRecordKey,
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
        @commands.session_delete_check,
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
        device_dispatch(DeleteChecked(key~, checkout=reply.checkout)),
      )
    })
    |> ignore
  })
}

///|
/// Permanently delete one live conversation, agreeing to exactly what the
/// confirmation showed: `checkout` is the host's account the dialog was
/// built from. A committed delete folds nothing from its reply: the host
/// announces every removed identity through `session.changed`, to this
/// client like any other. If more would go than the dialog said — a checkout
/// that appeared or turned dirty since — the host reports it instead, and
/// the same dialog asks again.
fn delete_session(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  key : ArchiveRecordKey,
  checkout : @protocol.CheckoutRemoval?,
) -> @cmd.Cmd {
  guard key.workspace_payload(channel) is Some(workspace) else {
    return @cmd.none
  }
  let payload : @protocol.SessionDeletePayload = match checkout {
    Some({ worktree, dirty_path_count, .. }) =>
      {
        session: key.session,
        workspace,
        worktree: Some(worktree),
        force: if dirty_path_count > 0 {
          Some(true)
        } else {
          None
        },
      }
    None => { session: key.session, workspace, worktree: None, force: None, }
  }
  let device_dispatch = dispatch.map((msg : DeviceMsg) => {
    FromDevice(channel, msg)
  })
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let reply = @interop.bridge_request(
        channel, @commands.session_delete, payload,
      ) catch {
        error => {
          scheduler.add(
            device_dispatch(DeleteFailed(@interop.bridge_error_text(error))),
          )
          return
        }
      }
      if reply is Unconfirmed(checkout) {
        scheduler.add(
          device_dispatch(DeleteChecked(key~, checkout=Some(checkout))),
        )
      }
    })
    |> ignore
  })
}

///|
/// The confirmation's body. It names what disappears and what survives so
/// the user does not have to infer filesystem or Git consequences from the
/// word "delete": for a live chat that is the host's own account of its
/// worktree checkout.
fn DeleteConfirm::message(
  locale~ : @i18n.Locale = English,
  self : DeleteConfirm,
) -> String {
  let title = self.title
  dynamic_text(
    locale,
    match self.target {
      LiveChat(checkout=Some({ worktree, dirty_paths, dirty_path_count, })) if dirty_path_count >
        0 =>
        DDeleteDirtyWorktreeConversation(
          title,
          worktree,
          @composer.dirty_paths_preview(dirty_paths, dirty_path_count),
        )
      LiveChat(checkout=Some({ worktree, .. })) =>
        DDeleteWorktreeConversation(title, worktree)
      LiveChat(checkout=None) | ArchivedChat(..) => DDeleteConversation(title)
    },
  )
}

///|
/// Permanent chat deletion requires a second, explicit click.
fn delete_modal(
  locale~ : @i18n.Locale = English,
  dispatch : @cmd.Emit[Msg],
  confirm : DeleteConfirm,
) -> @html.Html {
  @html.div(class="modal-backdrop", on_click=dispatch(CancelDeleteSession), [
    @html.div(class="modal", [
      @html.div(class="modal-title", shell_text(locale, DeleteChatQuestion)),
      @html.div(class="modal-body", confirm.message(locale~)),
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
