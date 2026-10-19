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
    self.selected_conversation is Some(CloudSelection(..)) ||
    self.cloud.creating_at(self.chat_navigation_generation)
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
fn Model::cloud_conversation(self : Model) -> @cloud.Conversation? {
  match self.selected_conversation {
    Some(CloudSelection(account~, session~)) if self.cloud.user_id ==
      Some(account) => self.cloud.conversations.get(session)
    _ => None
  }
}

///|
fn Model::cloud_archived(self : Model) -> Bool {
  self
  .cloud_identity()
  .map_or(false, owner => self.cloud.is_archived(owner.session()))
}

///|
fn Model::cloud_title(self : Model) -> String {
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
  guard identity.archive_generation <= self.composer_entry_retirements.length() else {
    return false
  }
  for
    index in identity.archive_generation..<self.composer_entry_retirements.length() {
    if self.composer_entry_retirements[index] == identity.owner {
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
  let switched = before.user_id is Some(_) && before.user_id != cloud.user_id
  let retirements = model.composer_entry_retirements.copy()
  if switched && before.user_id is Some(account) {
    let sessions = before.sessions.map(item => item.id)
    for session in before.conversations.keys() {
      if !sessions.contains(session) {
        sessions.push(session)
      }
    }
    for session in sessions {
      retirements.push(@interop.Cloud(account~, session~))
    }
  }
  let removed = if before.user_id == cloud.user_id {
    cloud.retired.filter(id => !before.retired.contains(id))
  } else {
    []
  }
  let mut navigation = model.navigation
  if before.user_id is Some(account) {
    for session in removed {
      retirements.push(@interop.Cloud(account~, session~))
      let location : @navigation.Location = {
        device: None,
        target: CloudSession(account~, session~),
      }
      let history = navigation.history.forget(location)
      navigation = {
        ..navigation,
        history,
        can_back: history.can_back(),
        can_forward: history.can_forward(),
        location: navigation.location.filter(current => current != location),
      }
    }
  }
  let removed_selection = model.cloud_identity()
    is Some(@interop.Cloud(session~, ..)) &&
    removed.contains(session)
  let archived_selection = match message {
    @cloud.Edited(epoch, id, request) =>
      model.screen is Chat &&
      !model.cloud.creating_at(model.chat_navigation_generation) &&
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
  let next = {
    ..model,
    cloud,
    navigation,
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
    composer_entry_retirements: retirements,
    selected_conversation: if removed_selection ||
      archived_selection ||
      (switched && model.cloud_identity() is Some(_)) {
      None
    } else {
      model.selected_conversation
    },
  }
  if (removed_selection || archived_selection) && model.screen is Chat {
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
  (command, next)
}

///|
fn Model::cloud_composer_input(self : Model) -> @composer.Input? {
  guard self.screen is Chat &&
    self.cloud_identity() is Some(owner) &&
    self.cloud_conversation() is Some(conversation) else {
    return None
  }
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
    run: if conversation.sending || conversation.generating {
      Some({ stage: @composer.Working, started_ms: None, tokens: 0, })
    } else {
      None
    },
    turn_id: conversation.task,
    history,
    installed_skills: [],
    submission_sequence: conversation.submission_sequence,
    file_index: @composer.FileIndexEmpty(epoch=self.composer_context_generation),
    presentation: {
      ..input.presentation,
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
      disabled: self.cloud_archived(),
      primary_action: @composer.Send(
        available=self.account is Some(_) &&
          self.cloud.can_send(owner.session()),
      ),
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
          unseen_outcome=None,
        ),
      },
    )
  })
}
