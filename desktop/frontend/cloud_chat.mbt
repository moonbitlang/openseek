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
    return @sidebar_messages.text(self.locale, Chats)
  }
  if self.selected_conversation is Some(CloudSelection(account~, session~)) &&
    self.cloud.user_id == Some(account) {
    for item in self.cloud.sidebar_sessions() {
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
  if message is @cloud.TerminalReady(epoch, session, shell) {
    guard epoch == model.cloud.epoch &&
      model.cloud.user_id is Some(account) &&
      model.account.map(credentials => credentials.user.user_id) ==
      Some(account) &&
      model.cloud.can_compose(session) else {
      return (@cmd.none, model)
    }
    let owner = @interop.Cloud(account~, session~)
    let target = {
      ..model,
      screen: Chat,
      selected_conversation: Some(CloudSelection(account~, session~)),
    }
    if shell is Some(shell) {
      return run_cloud_shell(dispatch, model, owner, shell)
    }
    let (command, terminal) = model.terminal.open_terminal(
      dispatch.map(msg => Terminal(msg)),
      target.terminal_input(),
      on_screen=model.screen is Chat && model.cloud_identity() == Some(owner),
    )
    return (command, { ..model, terminal, })
  }
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
    desktop_history=model.is_desktop,
  )
  let completion = if model.account.map(account => account.user.user_id) ==
    before.user_id {
    cloud_finished_notification(before, cloud, message)
  } else {
    None
  }
  let approval_notifications = if model.account.map(account => {
      account.user.user_id
    }) ==
    before.user_id {
    cloud_approval_notifications(before, cloud)
  } else {
    []
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
      navigation = {
        ..navigation,
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
    // A turn that starts in the Cloud conversation on screen, from this
    // client or another, locks its approval mode, so the menu closes with it.
    select_menu: if model.select_menu is Some(OpenSeekApprovalMenu) &&
      model.cloud_identity() is Some(owner) &&
      !cloud.can_choose_approval(owner.session()) {
      None
    } else {
      model.select_menu
    },
    sidebar_mode: if message is @cloud.Create {
      @sidebar.ChatMode
    } else {
      model.sidebar_mode
    },
    delete_confirm: match model.delete_confirm {
      Open(CloudDelete(account~, session~, ..)) if cloud.user_id !=
        Some(account) ||
        cloud.retired.contains(session) => model.delete_confirm.close()
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
  if message is @cloud.CreateFailed(epoch, request, failure) &&
    epoch == before.epoch &&
    before.creation is Some(creation) &&
    creation.request == request &&
    before.conversations.get(creation.id)
    is Some({ outgoing: Some({ input: @cloud.Terminal(shell), .. }), .. }) {
    if shell is Some(shell) {
      return cloud_shell_not_started(dispatch, next, shell.id, failure.label())
    }
    let (report, next) = next.notify_error(dispatch, failure.label())
    return (@cmd.batch([command, ..file_commands, report]), next)
  }
  // Earlier turns arrive from the network or from cached pages rejoining the
  // window; either way the visible turn must stay in place.
  let preserve_scroll = if model.transcript_slot()
    is Some(CloudTranscriptSlot(owner)) &&
    before.conversations.get(owner.session()) is Some(previous) &&
    next.cloud.conversations.get(owner.session()) is Some(current) &&
    current.extends_history_backward(previous) {
    @transcript_component.preserve_prepend_scroll()
  } else {
    @cmd.none
  }
  let command = @cmd.batch(
    [
      command,
      preserve_scroll,
      ..file_commands,
      cloud_command_results(dispatch, before, next.cloud, message),
      completion.map_or(@cmd.none, value => value.1.command(locale=next.locale)),
      ..approval_notifications.map(notification => {
        notification.command(locale=next.locale)
      }),
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
  let native_users = Map([])
  for event in conversation.document.events.unwrap_or([]) {
    if event.item is @protocol.User(user) {
      native_users[event.sequence] = user.content
    }
  }
  let history : Array[String] = []
  for record in conversation.records {
    if record.kind == "user" {
      let native = record.engine_sequence.bind(sequence => {
        native_users.get(sequence)
      })
      let text = match (native, record.data) {
        (Some(content), _) => content.text()
        (_, { "content": String(text), .. }) => text
        (_, { "content": Array(parts), .. }) =>
          parts
          .iter()
          .filter_map(part => {
            match part {
              { "type": "text", "text": String(text), .. } => Some(text)
              _ => None
            }
          })
          .join("")
        _ => continue
      }
      // Recall only the text without decoding the immutable image payloads.
      // Keep mention envelopes so the composer can restore their chips.
      if !text.is_blank() {
        history.push(text)
      }
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
    shell_available: conversation.queue_edit is None &&
    self.cloud.can_compose(owner.session()),
    prediction: if conversation.shell_commands.is_empty() {
      conversation.prediction
    } else {
      None
    },
    prediction_source: conversation.prediction_source(
      ready=self.cloud.can_send(owner.session()) &&
        file_ctx(self).root() is Some(_),
    ),
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
        if !conversation.shell_commands.is_empty() {
          context.push(
            @composer.ShellCommandsRunning(
              commands=conversation.shell_commands.map(p => p.command),
            ),
          )
        }
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
        @composer.ApprovalStatus({
          mode: self.cloud.approval(owner.session()),
          open: self.select_menu is Some(OpenSeekApprovalMenu),
          enabled: self.cloud.can_choose_approval(owner.session()),
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
  self.cloud
  .sidebar_sessions()
  .filter(item => item.archived == archived)
  .map(item => {
    let confirmed = !self.cloud.sessions.is_empty()
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
        loading: conversation.map_or(false, conversation => {
          conversation.loading || conversation.history_older_request is Some(_)
        }),
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
        rename: if confirmed {
          self.conversation_rename_input(id)
        } else {
          None
        },
        trailing: if confirmed {
          [
            if archived {
              @conversation.Restore(title=shell_text(self.locale, RestoreHint))
            } else {
              @conversation.Archive(title=shell_text(self.locale, ArchiveHint))
            },
            @conversation.Delete(
              title=shell_text(self.locale, DeletePermanently),
            ),
          ]
        } else {
          []
        },
        children: [],
        run_mark: @conversation.RunMark::for_task(
          running=item.generating ||
            conversation.map_or(false, conversation => {
              conversation.sending || conversation.generating
            }),
          needs_input=!archived &&
            conversation.map_or(false, conversation => {
              conversation.awaits_approval()
            }),
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

///|
fn integrated_cloud_model() -> Model {
  let state = {
    ..@cloud.State::empty(),
    user_id: Some("fixture-user"),
    epoch: 3,
    sessions: [
      {
        id: "cloud-a",
        title: Some("Cloud conversation"),
        updated_at: Some(100),
        generating: false,
        archived: false,
        approval: ApprovalAsk,
      },
    ],
  }
  let model = {
    ..test_model(),
    cloud: state,
    account: Some({
      token: "ts_fixture",
      user: { user_id: "fixture-user", login: "octocat", avatar_url: "", },
    }),
    is_desktop: true,
    deepseek_key_saved: false,
  }
  let (_, model) = update(
    test_dispatch(),
    OpenCloudConversation(account="fixture-user", session="cloud-a"),
    model,
  )
  let request = model.cloud.conversations.get("cloud-a").unwrap().request
  let (_, model) = update(
    test_dispatch(),
    CloudAction(
      @cloud.Loaded(3, "cloud-a", request, {
        prediction: None,
        session: {
          version: None,
          id: None,
          system_prompt: None,
          events: Some([
            {
              sequence: 1,
              ts: Some(100),
              item: @protocol.Assistant({
                content: "Cloud answer",
                reasoning_content: None,
                tool_calls: None,
                is_replay: None,
              }),
            },
          ]),
        },
        etag: None,
        offset: None,
        messages: [
          {
            task_id: "finished-task",
            kind: "assistant_message",
            data: { "content": "Cloud answer" },
            engine_sequence: None,
            created_at: 100,
          },
        ],
        generating: false,
      }),
    ),
    model,
  )
  model.with_cloud_baseline("cloud-a")
}

///|
fn Model::with_cloud_baseline(self : Model, session : String) -> Model {
  let conversations = self.cloud.conversations.copy()
  conversations[session] = { ..conversations[session], last_seq: Some(0), }
  { ..self, cloud: { ..self.cloud, conversations, }, }
}

///|
fn test_cloud_history(text : String) -> @cloud.History {
  {
    prediction: None,
    session: {
      version: None,
      id: None,
      system_prompt: None,
      events: Some([
        {
          sequence: 1,
          ts: Some(100),
          item: @protocol.Assistant({
            content: text,
            reasoning_content: None,
            tool_calls: None,
            is_replay: None,
          }),
        },
      ]),
    },
    etag: None,
    offset: None,
    messages: [
      {
        task_id: "finished-task",
        kind: "assistant_message",
        data: { "content": Json(text) },
        engine_sequence: None,
        created_at: 100,
      },
    ],
    generating: false,
  }
}

///|
test "Cloud direct links keep history readable while metadata controls editing" {
  let initial = integrated_cloud_model()
  let unknown = { ..initial, cloud: { ..initial.cloud, sessions: [], }, }
  let (_, waiting) = update(
    test_dispatch(),
    CloudAction(@cloud.Refresh),
    unknown,
  )
  let before = waiting.cloud_conversation().unwrap()
  assert_true(waiting.composer_input().presentation.disabled)
  assert_true(before.records == initial.cloud_conversation().unwrap().records)
  for archived in [false, true] {
    let (_, ready) = update(
      test_dispatch(),
      CloudAction(
        @cloud.Listed(
          waiting.cloud.epoch,
          waiting.cloud.list_request,
          initial.cloud.sessions.map(session => { ..session, archived, }),
        ),
      ),
      waiting,
    )
    assert_eq(ready.cloud_archived(), archived)
    assert_eq(ready.composer_input().presentation.disabled, archived)
    assert_true(ready.cloud_conversation().unwrap().records == before.records)
    assert_true(ready.cloud.creation is None)
    assert_true(ready.cloud_identity() == waiting.cloud_identity())
    assert_true(file_ctx(ready).placement is None)
    assert_true(file_ctx(ready).cloud_files is Some(_))
  }
  let (_, failed) = update(
    test_dispatch(),
    CloudAction(
      @cloud.ListFailed(
        waiting.cloud.epoch,
        waiting.cloud.list_request,
        Http(503),
      ),
    ),
    waiting,
  )
  assert_true(failed.cloud.list_status is Failed)
  assert_true(failed.composer_input().presentation.disabled)
  assert_true(failed.cloud_conversation().unwrap().records == before.records)
  assert_true(failed.cloud.creation is None)
  assert_true(failed.cloud_identity() == waiting.cloud_identity())
}

///|
test "Cloud deep-link missing and retryable failures preserve the requested address without creation" {
  let initial = { ..integrated_cloud_model(), is_desktop: false, }
  let (_, opening) = update(
    test_dispatch(),
    Navigation(Browser({ path: "/cloud/session/cloud-b", })),
    initial,
  )
  let request = opening.cloud.conversations["cloud-b"].request
  let location = opening.navigation.location
  for status in [404, 503] {
    let (_, failed) = update(
      test_dispatch(),
      CloudAction(
        @cloud.LoadFailed(opening.cloud.epoch, "cloud-b", request, Http(status)),
      ),
      opening,
    )
    assert_true(failed.navigation.location == location)
    assert_true(failed.cloud.creation is None)
    if status == 404 {
      assert_true(failed.navigation.phase is Missing)
      assert_true(failed.cloud.retired.contains("cloud-b"))
      assert_false(failed.cloud.conversations.contains("cloud-b"))
    } else {
      assert_true(
        failed.cloud.conversations["cloud-b"].notice ==
        Some("Cloud answered HTTP 503. Try again."),
      )
      let (_, retry) = update(
        test_dispatch(),
        OpenCloudConversation(account="fixture-user", session="cloud-b"),
        failed,
      )
      assert_true(retry.cloud.conversations["cloud-b"].request > request)
      let (_, ready) = update(
        test_dispatch(),
        CloudAction(
          @cloud.Loaded(
            retry.cloud.epoch,
            "cloud-b",
            retry.cloud.conversations["cloud-b"].request,
            test_cloud_history("Recovered history"),
          ),
        ),
        retry,
      )
      assert_true(
        ready.cloud.conversations["cloud-b"].records ==
        test_cloud_history("Recovered history").messages,
      )
      assert_true(ready.cloud.creation is None)
      assert_true(ready.navigation.location == location)
    }
  }
}

///|
test "late Cloud history cannot replace a newer URL selection and invalid routes cannot create a session" {
  let initial = { ..integrated_cloud_model(), is_desktop: false, }
  let (_, opening) = update(
    test_dispatch(),
    Navigation(Browser({ path: "/cloud/session/cloud-b", })),
    initial,
  )
  let request = opening.cloud.conversations["cloud-b"].request
  let (_, newer) = update(
    test_dispatch(),
    Navigation(Browser({ path: "/cloud/session/cloud-c", })),
    opening,
  )
  let (_, late) = update(
    test_dispatch(),
    CloudAction(
      @cloud.Loaded(
        opening.cloud.epoch,
        "cloud-b",
        request,
        test_cloud_history("Late history"),
      ),
    ),
    newer,
  )
  assert_true(late.navigation.location == newer.navigation.location)
  assert_true(
    late.cloud_identity() ==
    Some(@interop.Cloud(account="fixture-user", session="cloud-c")),
  )
  assert_true(
    late.cloud.conversations["cloud-c"] == newer.cloud.conversations["cloud-c"],
  )
  assert_true(late.cloud.creation is None)
  let (_, invalid) = update(
    test_dispatch(),
    Navigation(Browser({ path: "/cloud/session/extra/path", })),
    initial,
  )
  assert_true(invalid.navigation.phase is Invalid)
  assert_true(invalid.cloud.creation is None)
}

///|
test "failed terminal session creation retains the Cloud composer owner without opening a terminal or model task" {
  let (_, blank) = update(
    test_dispatch(),
    CloudAction(@cloud.Create),
    integrated_cloud_model(),
  )
  let identity = blank.composer_input().identity
  let (_, pending) = update(
    test_dispatch(),
    Terminal(@terminal.ToggleTerminal),
    blank,
  )
  assert_true(pending.cloud.creating_session())
  assert_false(pending.terminal.is_open())
  assert_true(terminal_ctx(pending).placement is None)
  let creation = pending.cloud.creation.unwrap()
  let (_, failed) = update(
    test_dispatch(),
    CloudAction(
      @cloud.CreateFailed(pending.cloud.epoch, creation.request, Http(500)),
    ),
    pending,
  )
  assert_true(failed.composer_input().identity == identity)
  assert_false(failed.composer_input().presentation.disabled)
  assert_false(failed.cloud.creating_session())
  assert_true(failed.terminal == blank.terminal)
  assert_true(failed.cloud.conversations[creation.id].outgoing is None)
  assert_false(failed.cloud.conversations[creation.id].sending)
  assert_false(failed.cloud.conversations[creation.id].generating)
  assert_true(
    failed.notifications.any(notification => {
      notification.message == "Cloud answered HTTP 500. Try again."
    }),
  )
  assert_true(failed.composer_entry_changes == blank.composer_entry_changes)
}

///|
test "blank Cloud drafts expose no file workspace while archived conversations retain read-only files" {
  let initial = integrated_cloud_model()
  let (_, blank) = update(test_dispatch(), CloudAction(@cloud.Create), initial)
  assert_false(blank.cloud.creating_session())
  assert_true(file_ctx(blank).root() is None)
  assert_true(file_ctx(blank).placement is None)
  assert_false(blank.file_panel_visible())
  let archived = {
    ..initial,
    cloud: {
      ..initial.cloud,
      sessions: initial.cloud.sessions.map(session => {
        ..session,
        archived: true,
      }),
    },
  }
  assert_true(archived.cloud_archived())
  let ctx = file_ctx(archived)
  assert_true(
    ctx.owner == @interop.Cloud(account="fixture-user", session="cloud-a"),
  )
  assert_true(ctx.placement is None)
  assert_true(ctx.cloud_files is Some(_))
  assert_true(ctx.root() is Some(_))
  assert_true(archived.composer_input().presentation.disabled)
}
