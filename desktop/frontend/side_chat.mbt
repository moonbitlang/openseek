// Closing a side chat's tab deletes the side chat. The tab leaves the strip
// at once; the record follows when the host can take it, which is only once
// the side chat has no turn running.

///|
/// One side chat whose tab was closed. While it is here its record is not
/// shown as a tab, even though the listing still has it.
priv struct ClosingSideChat {
  chat : @interop.ConversationKey
  stage : ClosingStage
} derive(Eq)

///|
priv enum ClosingStage {
  // Asked to stop its turn; deleted once the run has ended.
  Stopping
  // The delete request is out. The listing dropping the record ends this.
  Deleting
} derive(Eq)

///|
/// The tab of side chat `chat` was closed: stop its turn if one is running,
/// and delete it once none is.
fn Model::close_side_chat(
  self : Model,
  dispatch : @cmd.Emit[Msg],
  chat : @interop.ConversationKey,
) -> (@cmd.Cmd, Model) {
  guard !self.closing_side_chats.any(closing => closing.chat == chat) else {
    return (@cmd.none, self)
  }
  let (model, commands) = {
    ..self,
    closing_side_chats: [..self.closing_side_chats, { chat, stage: Stopping, }],
  }.advance_side_chat_closing(dispatch)
  (commands, model)
}

///|
/// Move every closing side chat along: stop a turn that has a run to stop
/// — including one that was still starting when its tab closed, once its run
/// opens — delete one whose turn has ended, and forget one whose record the
/// listing no longer has.
fn Model::advance_side_chat_closing(
  self : Model,
  dispatch : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  guard !self.closing_side_chats.is_empty() else { return (self, @cmd.none) }
  let commands : Array[@cmd.Cmd] = []
  let closing : Array[ClosingSideChat] = []
  let mut model = self
  for entry in self.closing_side_chats {
    guard model.device_state(entry.chat.channel) is Some(dev) &&
      dev.sessions.iter().find_first(item => item.id == entry.chat.session)
      is Some(listed) else {
      continue
    }
    let conv = model.find_conversation(entry.chat.channel, entry.chat.session)
    match (entry.stage, conv) {
      (Deleting, _) => closing.push(entry)
      (Stopping, Some({ run: Open(run_id~, stage~), .. } as conv)) if !(stage
        is Cancelling) => {
        commands.push(
          cancel_openseek(
            locale=model.locale,
            dispatch,
            entry.chat.channel,
            run_id,
          ),
        )
        model = model.replace_conversation({
          ..conv,
          run: Open(run_id~, stage=Cancelling),
        })
        closing.push(entry)
      }
      (Stopping, Some(conv)) if conv.is_running() => closing.push(entry)
      (Stopping, _) => {
        commands.push(delete_side_chat(dispatch, entry.chat, listed.workspace))
        closing.push({ ..entry, stage: Deleting, })
      }
    }
  }
  if closing == model.closing_side_chats && commands.is_empty() {
    return (model, @cmd.none)
  }
  ({ ..model, closing_side_chats: closing, }, @cmd.batch(commands))
}

///|
/// Stopping a closing side chat failed, so its turn may still be running: its
/// tab comes back, where its turn can be stopped again or its question
/// answered.
fn Model::reopen_side_chat_after_cancel_failure(
  self : Model,
  chat : @interop.ConversationKey,
) -> Model {
  {
    ..self,
    closing_side_chats: self.closing_side_chats.filter(closing => {
      closing.chat != chat
    }),
  }
}

///|
/// Delete side chat `chat`'s record. Its checkout is its conversation's too,
/// so the request removes none; a host that would remove one anyway reports
/// that instead of deleting, and the tab comes back with the reason.
fn delete_side_chat(
  dispatch : @cmd.Emit[Msg],
  chat : @interop.ConversationKey,
  workspace : @common.Uri,
) -> @cmd.Cmd {
  let key : ArchiveRecordKey = { session: chat.session, workspace, }
  guard key.workspace_payload(chat.channel) is Some(workspace) else {
    return @cmd.none
  }
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let failure = try {
        let reply = @interop.bridge_request(
          chat.channel,
          @commands.session_delete,
          { session: chat.session, workspace, worktree: None, force: None, },
        )
        match reply {
          Deleted => None
          Unconfirmed({ worktree, .. }) =>
            Some(
              "Closing this side chat would remove worktree \{worktree}; it was kept.",
            )
        }
      } catch {
        error => Some(@interop.bridge_error_text(error))
      }
      if failure is Some(message) {
        scheduler.add(dispatch(SideChatCloseFailed(chat~, message~)))
      }
    })
    |> ignore
  })
}
