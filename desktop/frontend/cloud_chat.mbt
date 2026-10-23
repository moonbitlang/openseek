///|
fn Model::host_selection(self : Model) -> ConversationSelection? {
  match self.selected_conversation {
    Some(HostSelection(selection)) => Some(selection)
    _ => None
  }
}

///|
fn Model::cloud_selected(self : Model) -> Bool {
  self.screen is Chat &&
  (
    self.cloud_identity() is Some(_) ||
    self.cloud_draft_identity() is Some(_) ||
    (
      self.selected_conversation is None &&
      self.navigation.location.map_or(false, location => {
        location.target.is_cloud()
      })
    )
  )
}

///|
fn Model::cloud_identity(self : Model) -> @interop.ConversationIdentity? {
  match self.selected_conversation {
    Some(CloudSelection(account~, session~)) =>
      Some(@interop.Cloud(account~, session~))
    _ => None
  }
}

///|
fn Model::cloud_draft_identity(self : Model) -> @interop.ConversationIdentity? {
  match self.selected_conversation {
    Some(CloudDraftSelection(account~, id~)) => {
      let owner = @interop.Cloud(account~, session=id)
      self.cloud.draft_identity().filter(current => current == owner)
    }
    _ => None
  }
}

///|
fn Model::cloud_conversation(self : Model) -> @cloud.Conversation? {
  guard self.cloud_draft_identity() is None else { return None }
  match self.selected_conversation {
    Some(CloudSelection(account~, session~)) if self.cloud.user_id ==
      Some(account) => self.cloud.conversations.get(session)
    _ => None
  }
}

///|
fn Model::cloud_archived(self : Model) -> Bool {
  self.cloud_draft_identity() is None &&
  self
  .cloud_identity()
  .map_or(false, owner => self.cloud.is_archived(owner.session()))
}

///|
fn Model::cloud_title(self : Model) -> String {
  if self.cloud_identity() is None && self.cloud_draft_identity() is None {
    return @sidebar_messages.text(self.locale, Cloud)
  }
  if self.selected_conversation is Some(CloudSelection(account~, session~)) &&
    self.cloud.user_id == Some(account) {
    for item in self.cloud.sessions {
      if item.id == session {
        return item.title.unwrap_or(shell_text(self.locale, NewChatLabel))
      }
    }
  }
  shell_text(self.locale, NewChatLabel)
}

///|
fn Model::accepts_composer_action(
  self : Model,
  identity : @composer.Identity,
) -> Bool {
  guard identity.archive_generation <= self.composer_entry_changes.length() else {
    return false
  }
  for
    index in identity.archive_generation..<self.composer_entry_changes.length() {
    if self.composer_entry_changes[index].retires(identity.owner) {
      return false
    }
  }
  true
}

///|
fn update_cloud(
  dispatch : @cmd.Emit[Msg],
  message : @cloud.Msg,
  model : Model,
) -> (@cmd.Cmd, Model) {
  if message is @cloud.Create && model.account is None {
    return begin_account_login(dispatch, model, create=true)
  }
  let before = model.cloud
  let (cloud, command, selected) = @cloud.update(
    before,
    message,
    dispatch.map(message => CloudAction(message)),
    token?=model.account.map(account => account.token),
    navigation=model.chat_navigation_generation,
  )
  let completion = if model.account.map(account => account.user.user_id) ==
    before.user_id {
    cloud_finished_notification(before, cloud, message)
  } else {
    None
  }
  let cloud = if completion is Some((id, _)) {
    let conversations = cloud.conversations.copy()
    conversations[id] = {
      ..conversations[id],
      unseen_finish: true,
      last_finished_task: conversations[id].task,
    }
    { ..cloud, conversations, }
  } else {
    cloud
  }
  let switched = before.user_id is Some(_) && before.user_id != cloud.user_id
  let retirements = model.composer_entry_changes.copy()
  let created = match message {
    @cloud.Created(epoch, request, session) if epoch == before.epoch &&
      before.creation is Some(creation) &&
      creation.request == request &&
      cloud.creation is None => Some(session)
    _ => None
  }
  if created is Some(session) &&
    before.draft_identity() is Some(owner) &&
    cloud.user_id is Some(account) {
    retirements.push(
      @composer.Move(from=owner, to=@interop.Cloud(account~, session~)),
    )
  }
  if switched && before.user_id is Some(account) {
    let sessions = before.sessions.map(item => item.id)
    for session in before.conversations.keys() {
      if !sessions.contains(session) {
        sessions.push(session)
      }
    }
    for session in sessions {
      retirements.push(@composer.Retire(@interop.Cloud(account~, session~)))
    }
  }
  let removed = if before.user_id == cloud.user_id {
    cloud.retired.filter(id => !before.retired.contains(id))
  } else {
    []
  }
  let deleted = message
    is (@cloud.Deleted(_, _, _)
    | @cloud.DeleteFailed(_, _, _, @cloud.Failure::Http(404)))
  let mut navigation = model.navigation
  if before.user_id is Some(account) {
    for session in removed {
      retirements.push(@composer.Retire(@interop.Cloud(account~, session~)))
      let location : @routes.Location = {
        device: None,
        target: CloudSession(account=Some(account), session~),
      }
      let history = navigation.history.forget(location)
      navigation = {
        ..navigation,
        history,
        can_back: if navigation.browser_ready {
          navigation.can_back
        } else {
          history.can_back()
        },
        can_forward: if navigation.browser_ready {
          navigation.can_forward
        } else {
          history.can_forward()
        },
        location: if deleted {
          navigation.location.filter(current => current != location)
        } else {
          navigation.location
        },
        phase: if !deleted && navigation.location == Some(location) {
          Missing
        } else {
          navigation.phase
        },
      }
    }
  }
  let removed_selection = model.cloud_identity()
    is Some(@interop.Cloud(session~, ..)) &&
    removed.contains(session)
  let archived_selection = match message {
    @cloud.Edited(epoch, id, request) =>
      model.screen is Chat &&
      model.cloud_draft_identity() is None &&
      epoch == before.epoch &&
      before.metadata_saves.get(id)
      is Some(
        {
          request: pending,
          edit: @cloud.Archive(true),
          navigation: generation,
        }
      ) &&
      pending == request &&
      generation == model.chat_navigation_generation &&
      !cloud.metadata_saves.contains(id) &&
      cloud.is_archived(id) &&
      model.cloud_identity() is Some(@interop.Cloud(account~, session~)) &&
      cloud.user_id == Some(account) &&
      session == id
    _ => false
  }
  let mut file_panel = model.file_panel
  let docks = model.docks.copy()
  let file_commands : Array[@cmd.Cmd] = []
  if before.epoch != cloud.epoch && before.user_id is Some(account) {
    let (panel, clear) = @fileeditor.forget_cloud_files(file_panel, account)
    file_panel = panel
    file_commands.push(clear)
    for owner in docks.keys().to_array() {
      if owner is @interop.Cloud(account=current, ..) && current == account {
        docks.remove(owner)
      }
    }
  }
  if before.user_id is Some(account) {
    for session in removed {
      let (panel, clear) = @fileeditor.forget_cloud_files(
        file_panel,
        account,
        session~,
      )
      file_panel = panel
      file_commands.push(clear)
      docks.remove(@interop.Cloud(account~, session~))
    }
  }
  let next = {
    ..model,
    docks,
    file_panel,
    screen: if message is @cloud.Create {
      Chat
    } else {
      model.screen
    },
    cloud,
    navigation,
    sidebar_mode: if message is @cloud.Create {
      @sidebar.ChatMode
    } else {
      model.sidebar_mode
    },
    delete_confirm: match model.delete_confirm {
      Some(CloudDelete(account~, session~, ..)) if cloud.user_id !=
        Some(account) ||
        cloud.retired.contains(session) => None
      other => other
    },
    api_setup_open: model.api_setup_open && !(message is @cloud.Create),
    conversation_rename: match model.conversation_rename {
      Some(rename) if rename.id.source() is @conversation.CloudLive &&
        (
          cloud.user_id != Some(rename.id.channel()) ||
          cloud.retired.contains(rename.id.conversation())
        ) => None
      other => other
    },
    composer_entry_changes: retirements,
    selected_conversation: if message is @cloud.Create &&
      cloud.draft_identity() is Some(@interop.Cloud(account~, session=id)) {
      Some(CloudDraftSelection(account~, id~))
    } else if removed_selection ||
      archived_selection ||
      (
        switched &&
        (
          model.cloud_identity() is Some(_) ||
          model.cloud_draft_identity() is Some(_)
        )
      ) {
      None
    } else if created is Some(session) &&
      model.cloud_draft_identity() is Some(@interop.Cloud(account~, ..)) {
      Some(CloudSelection(account~, session~))
    } else {
      model.selected_conversation
    },
  }
  // Streams may finish while another conversation is on screen. Retire that
  // session's file cache at the same transition as a foreground completion.
  let mut file_panel = next.file_panel
  if before.user_id == next.cloud.user_id && before.user_id is Some(account) {
    for session, conversation in before.conversations {
      if conversation.generating &&
        next.cloud.conversations
        .get(session)
        .map_or(false, conversation => !conversation.generating) {
        let (refresh, panel) = @fileeditor.update(
          dispatch.map(msg => FileEditor(msg)),
          @fileeditor.RunSettled(owner=@interop.Cloud(account~, session~)),
          file_panel,
          file_ctx(next),
        )
        file_commands.push(refresh)
        file_panel = panel
      }
    }
  }
  let next = { ..next, file_panel, }
  let command = @cmd.batch(
    [
      command,
      ..file_commands,
      completion.map_or(@cmd.none, value => value.1.command(locale=next.locale)),
    ],
  )
  if ((deleted && removed_selection) || archived_selection) &&
    model.screen is Chat {
    let next = {
      ..next,
      chat_navigation_generation: next.chat_navigation_generation + 1,
    }
    let (open, next) = update_cloud(dispatch, @cloud.Create, next)
    return (@cmd.batch([command, open]), next)
  }
  if selected is Some(session) && next.cloud.user_id is Some(account) {
    let (open, next) = update_msg(
      dispatch,
      OpenCloudConversation(account~, session~),
      next,
    )
    return (@cmd.batch([command, open]), next)
  }
  if cloud.needs_sign_in {
    let (expired, next) = expire_account(dispatch, next)
    return (@cmd.batch([command, expired]), next)
  }
  if next.conversation_rename is Some(rename) &&
    rename.id.source() is @conversation.CloudLive &&
    before.metadata_saves.get(rename.id.conversation())
    is Some({ edit: @cloud.Rename(_), .. }) &&
    !cloud.metadata_saves.contains(rename.id.conversation()) {
    let (finish, next) = match message {
      @cloud.EditFailed(_, _, _, error) =>
        update_msg(
          dispatch,
          ConversationRenameFailed(id=rename.id, message=error.label()),
          { ..next, cloud: { ..next.cloud, notice: None, }, },
        )
      _ => next.finish_conversation_rename(rename)
    }
    return (@cmd.batch([command, finish]), next)
  }
  if message is @cloud.WatchEvent(epoch, session, _, @cloud.NativeEvent(frame)) &&
    epoch == before.epoch &&
    before.conversations.get(session) is Some(previous) &&
    previous.last_seq.map_or(false, seq => frame.seq > seq) &&
    next.cloud.conversations.get(session) is Some(current) &&
    current.last_seq == Some(frame.seq) &&
    (frame.task_id is None || frame.task_id == previous.task) {
    let error = match @wire.parse(frame.data) {
      Some(
        @wire.CommandError(error~)
        | @wire.SessionError(error~)
        | @wire.CompactionFailed(error~)
        | @wire.AutoCompactionFailed(error~)
      ) => Some(error)
      _ => None
    }
    if error is Some(error) {
      // A command diagnostic is not a chatting task failure. Use the same
      // transient error reporting as Local instead of changing run status.
      let (report, next) = next.notify_error(dispatch, error)
      return (@cmd.batch([command, report]), next)
    }
  }
  (command, next)
}

///|
fn Model::cloud_composer_input(self : Model) -> @composer.Input? {
  guard self.screen is Chat else { return None }
  let owner = match self.cloud_draft_identity() {
    Some(owner) => Some(owner)
    None => self.cloud_identity()
  }
  guard owner is Some(owner) else { return None }
  guard self.cloud.conversations.get(owner.session()) is Some(conversation) else {
    return None
  }
  let pending = self.cloud.draft_identity() == Some(owner) &&
    self.cloud.creating_session()
  let history : Array[String] = []
  for record in conversation.records {
    if record.kind == "user" &&
      record.data is { "content": String(content), .. } {
      history.push(content)
    }
  }
  let input = self.dormant_composer_input()
  Some({
    ..input,
    identity: { ..input.identity, owner, },
    draft: conversation.initial_submission
    .unwrap_or(input.draft)
    .with_semantic_selection(
      if self.file_panel.owner == Some(owner) {
        // Model references are workspace-relative; the panel's slash root is
        // only a virtual URI path, never a machine filesystem root.
        self.file_panel.search.selected_semantic_reference(".")
      } else {
        None
      },
    ),
    run: if conversation.sending || conversation.generating {
      Some(
        conversation
        .run_heartbeat()
        .unwrap_or({ stage: @composer.Working, started_ms: None, tokens: 0, }),
      )
    } else {
      None
    },
    turn_id: conversation.task,
    goal: conversation.controls.input(),
    slash_commands: if !self.cloud.can_compose(owner.session()) {
      []
    } else {
      self.openseek_commands()
    },
    history,
    root: file_ctx(self).root(),
    cloud_access: self.account.map(account => {
      token: account.token,
      epoch: self.cloud.epoch,
    }),
    staged_attachments: conversation.initial_attachments,
    file_candidates: self.file_search().candidates,
    open_files: self.live_editor_files(),
    active_file: self.active_workspace_file(),
    installed_skills: [],
    submission_sequence: conversation.submission_sequence,
    file_index: if self.file_panel.owner == Some(owner) {
      self.composer_file_index()
    } else {
      @composer.FileIndexEmpty(epoch=self.file_panel.request_epoch)
    },
    presentation: {
      images_enabled: true,
      context: {
        let context = conversation.control_context()
        if conversation.watch_status == Reconnecting {
          context.push(@composer.ConnectionBanner(device_name=Some("Cloud")))
        }
        if conversation.controls.is_compacting() ||
          conversation.controls.is_compact_queued() {
          context.push(
            @composer.CompactionNotice(
              queued=!conversation.controls.is_compacting(),
            ),
          )
        }
        context
      },
      status: [
        @composer.ModelStatus({
          id: "model",
          groups: [
            {
              label: "Cloud",
              options: [{ value: "deepseek-flash", label: "DeepSeek Flash", }],
            },
          ],
          selected: "deepseek-flash",
          disabled: true,
          open: false,
          title: "DeepSeek Flash",
        }),
      ],
      placeholder: shell_text(self.locale, AskPlaceholder),
      disabled: pending || !self.cloud.can_compose(owner.session()),
      primary_action: if conversation.generating ||
        conversation.sending ||
        conversation.queue_edit is Some(_) {
        conversation.control_primary_action(
          if self.followup_behavior is FollowupQueue {
            @composer.Queue
          } else {
            @composer.Steer
          },
        )
      } else {
        @composer.Send(
          available=self.account is Some(_) &&
            self.cloud.can_send(owner.session()),
        )
      },
    },
  })
}

///|
fn Model::cloud_chat_rows(
  self : Model,
  archived~ : Bool = false,
) -> Array[(RowStamp, @conversation.Input)] {
  guard self.cloud.user_id is Some(account) else { return [] }
  self.cloud.sessions
  .filter(item => item.archived == archived)
  .map(item => {
    let active = self.screen is Chat &&
      self.cloud_identity() == Some(@interop.Cloud(account~, session=item.id))
    let conversation = self.cloud.conversations.get(item.id)
    let id = @conversation.Id(
      source=if archived {
        @conversation.CloudArchived
      } else {
        @conversation.CloudLive
      },
      channel=account,
      conversation=item.id,
    )
    (
      item.updated_at.map_or(ComposingNow, ms => ActiveAt(ms)),
      {
        id,
        title: item.title.unwrap_or(shell_text(self.locale, NewChatLabel)),
        label: item.title.unwrap_or(shell_text(self.locale, NewChatLabel)),
        nested: false,
        subrun: false,
        active,
        loading: conversation.map_or(false, conversation => conversation.loading),
        load_failed: conversation.map_or(false, conversation => {
          conversation.history_required && conversation.notice is Some(_)
        }),
        running: conversation.map_or(item.generating, conversation => {
          conversation.sending || conversation.generating
        }) ||
        item.generating ||
        self.cloud.deletions.contains(item.id) ||
        self.cloud.metadata_saves.contains(item.id),
        openable: true,
        rename: self.conversation_rename_input(id),
        trailing: [
          if archived {
            @conversation.Restore(title=shell_text(self.locale, RestoreHint))
          } else {
            @conversation.Archive(title=shell_text(self.locale, ArchiveHint))
          },
          @conversation.Delete(title=shell_text(self.locale, DeletePermanently)),
        ],
        children: [],
        run_mark: @conversation.RunMark::for_task(
          running=item.generating ||
            conversation.map_or(false, conversation => {
              conversation.sending || conversation.generating
            }),
          needs_input=false,
          unseen_outcome=if !archived &&
            conversation is Some({ unseen_finish: true, .. } as conversation) {
            Some(
              match cloud_recorded_status(conversation) {
                Finished(Completed) => @conversation.Completed
                Failed | Errored => @conversation.Failed
                Finished(Aborted) => @conversation.Stopped
                _ => @conversation.Ended
              },
            )
          } else {
            None
          },
        ),
      },
    )
  })
}
