///|
const TranscriptReloadMaxAttempts : Int = 3

///|
/// Build the request for one transcript generation. Foreground loads may
/// activate a selected stored session; background refreshes only reconcile
/// the conversation already in the model.
fn session_snapshot_command(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  model : Model,
  session : String,
  generation : Int,
  activate_on_success : Bool,
) -> @cmd.Cmd {
  let (workspace, archived) = match model.find_conversation(channel, session) {
    Some(conv) => (Some(conv.project()), conv.is_archived_read_only())
    None => (model.session_project(channel, session), false)
  }
  if activate_on_success {
    open_session(dispatch, channel, session, workspace~, generation~, archived~)
  } else {
    refresh_session(
      dispatch,
      channel,
      session,
      workspace~,
      generation~,
      archived~,
    )
  }
}

///|
/// Move the UI's focus to `channel`: refetch the focused-scoped mirrors
/// that BridgeReady only loads for the then-focused device (host settings,
/// installed skills) and reset their local bookkeeping, so
/// nothing of the previous device's host bleeds through. The active
/// conversation is the caller's to place afterwards (an activation or a
/// rotation); until it does, nothing is selected. A no-op when focus is
/// already there — or when the page does not hold the channel. A browser
/// console may select its inert `Local` default while its required remote
/// device is unavailable; that transition only clears device-scoped state.
fn focus_channel(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  channel : @interop.ChannelId,
) -> (@cmd.Cmd, Model) {
  guard channel != model.focused else { return (@cmd.none, model) }
  let focus_cmd = if model.device_state(channel) is Some(dev) {
    @cmd.batch([
      fetch_host_settings(dispatch, channel, dev.connection_generation),
      fetch_installed_skills(dispatch, channel),
      // Let update advance the catalog generations after focus moves. Calling
      // the request method against the old state would reuse an old token.
      dispatch(Codex(channel~, @codex.Msg::refresh())),
    ])
  } else if channel == @interop.ChannelId::Local && model.console is Some(_) {
    @cmd.none
  } else {
    return (@cmd.none, model)
  }
  let (file_panel, unwatch_cmd) = model.file_panel.retire_watcher(
    dispatch.map(msg => FileEditor(msg)),
    file_ctx(model),
  )
  (
    @cmd.batch([focus_cmd, unwatch_cmd]),
    {
      ..model.clear_host_settings(),
      focused: channel,
      active_session: "",
      selected_conversation: None,
      conversation_load_failure: None,
      loading_conversation: None,
      installed_skills: [],
      // Codex is host-owned just like the other focused mirrors. Clear the
      // previous device's account and conversation list before its replies
      // can be mistaken for this device's sidebar section.
      codex: @codex.State(loading=true),
      // The old HostConnection is already parked. Preserve the remaining
      // owner/root state until the post-dispatch sync retires its file-index
      // cache and re-roots against the newly focused host.
      file_panel,
    },
  )
}

///|
/// The OpenSession body against an explicit channel — the caller has
/// already moved focus there, so `channel == model.focused` throughout.
fn open_session_on(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  model : Model,
  session_id : String,
) -> (@cmd.Cmd, Model) {
  let owner : @interop.ConversationKey = { channel, session: session_id, }
  if session_id == model.active_session {
    let base = { ..model, screen: Chat, }.mark_visible_conversation_read()
    // Re-selecting is an explicit catch-up point for writes made by an
    // idle CLI or another client. It also restarts an exhausted retry
    // round; an existing request stays single-flight. A fresh chat has no
    // durable record to read, including when returning here from Skills.
    match model.find_conversation(channel, session_id) {
      Some(conv) if !(conv.sync is Reloading(..)) &&
        model.can_reload_transcript(conv) => {
        let (next, generation) = base.begin_transcript_reload(conv)
        let next = { ..next, loading_conversation: Some(owner), }
        if generation is Some(generation) {
          (
            session_snapshot_command(
              dispatch, channel, next, session_id, generation, true,
            ),
            next,
          )
        } else {
          (@cmd.none, next)
        }
      }
      _ =>
        (
          @cmd.none,
          {
            ..base,
            loading_conversation: if base.loading_conversation == Some(owner) {
              Some(owner)
            } else {
              None
            },
          },
        )
    }
  } else if model.find_conversation(channel, session_id) is Some(conv) {
    // Switching focus; the transcript re-pins at the tail. The store is
    // also re-read behind the switch — the local copy may date from
    // before a reconnect, or another client may be driving this
    // conversation — and the current view stays on screen while the
    // reply is in flight. A failed/ongoing first load also needs to stay
    // attached even though it has no transcript yet.
    let reread = model.can_reload_transcript(conv) || !(conv.sync is Synced)
    let (model, generation) = if reread {
      model.begin_transcript_reload(conv)
    } else {
      (model.replace_conversation(conv), None)
    }
    let next = {
      ..model.activate(channel, session_id, conv.project()),
      screen: Chat,
      loading_conversation: if generation is Some(_) {
        Some(owner)
      } else {
        None
      },
    }.with_active_project(Some(conv.project()))
    let commands : Array[@cmd.Cmd] = []
    if generation is Some(generation) {
      commands.push(
        session_snapshot_command(
          dispatch, channel, next, session_id, generation, true,
        ),
      )
    }
    (@cmd.batch(commands), next)
  } else {
    // The sidebar item says which project store holds the session, while the
    // already-loaded worktree registry may place it in a specific checkout.
    // Join both snapshots before the conversation exists: no later registry
    // reply is guaranteed after a user opens an already-listed session.
    //
    // A session this page can place in no project is not openable: there is
    // no store to read it from. That is a row on its way out — its project
    // was detached — so the click is dropped rather than reported.
    guard model.session_project(channel, session_id) is Some(project) else {
      return (@cmd.none, model)
    }
    let conversation = empty_conversation(
      channel,
      session_id,
      project,
      // Reopening a stored conversation recovers the tier it was left on,
      // not whatever was picked last in some other chat.
      model=model
        .remembered_model(channel, session_id)
        .unwrap_or(model.default_model),
    )
    let conversation = if model.device_state(channel) is Some(dev) {
      {
        ..conversation,
        workspace: dev.conversation_workspace(
          project,
          session_id,
          conversation.workspace,
        ),
      }
    } else {
      conversation
    }
    let (model, generation) = model.begin_transcript_reload(conversation)
    let next = { ..model, screen: Chat, loading_conversation: Some(owner), }.with_active_project(
      Some(project),
    )
    if generation is Some(generation) {
      (
        session_snapshot_command(
          dispatch, channel, next, session_id, generation, true,
        ),
        next,
      )
    } else {
      (@cmd.none, next)
    }
  }
}

///|
fn Model::live_selection(
  self : Model,
  channel : @interop.ChannelId,
  session : String,
) -> ConversationSelection? {
  self
  .session_project(channel, session)
  .map(workspace => { channel, session, workspace, record: LiveRecord, })
}

///|
/// Open one archived row against its archived durable twin. Reusing an
/// already-open archived transcript preserves its rendered snapshot while a
/// fresh generation catches up. A live same-id entry or an archived twin from
/// another store is replaced, so neither writable state nor an in-flight
/// snapshot can cross the store-qualified archive boundary.
fn Model::open_archived_session_on(
  self : Model,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  session_id : String,
  workspace : @common.Uri,
) -> (@cmd.Cmd, Model) {
  let owner : @interop.ConversationKey = { channel, session: session_id, }
  let known = self.find_conversation(channel, session_id)
  let conversation = match known {
    Some(conv) if conv.is_archived_read_only() && conv.project() == workspace =>
      conv
    _ =>
      {
        ..empty_conversation(
          channel,
          session_id,
          workspace,
          model=self
            .remembered_model(channel, session_id)
            .unwrap_or(self.default_model),
        ),
        record: ArchivedRecord,
      }
  }
  let conversation = if self.device_state(channel) is Some(dev) {
    {
      ..conversation,
      record: ArchivedRecord,
      workspace: dev.conversation_workspace(
        workspace,
        session_id,
        conversation.workspace,
      ),
    }
  } else {
    { ..conversation, record: ArchivedRecord, }
  }
  let (model, generation) = self.begin_transcript_reload(conversation)
  let next = {
    ..model.activate(channel, session_id, workspace),
    screen: Chat,
    loading_conversation: Some(owner),
  }.with_active_project(Some(workspace))
  if generation is Some(generation) {
    (
      session_snapshot_command(
        dispatch, channel, next, session_id, generation, true,
      ),
      next,
    )
  } else {
    (@cmd.none, next)
  }
}

///|
/// Issue a live-session list request with a page-lifetime token. The token is
/// advanced before the command leaves update, so any older same-connection
/// reply is stale even if it returns last.
fn request_sessions_refresh(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  model : Model,
) -> (@cmd.Cmd, Model) {
  guard model.device_state(channel) is Some(dev) else {
    return (@cmd.none, model)
  }
  let request_generation = dev.sessions_request_generation + 1
  (
    fetch_sessions(
      dispatch,
      channel,
      dev.connection_generation,
      request_generation,
    ),
    model.replace_device({
      ..dev,
      sessions_request_generation: request_generation,
    }),
  )
}

///|
/// The archived list is fetched independently from the live list and keeps
/// its own token, so a newer live-only refresh does not invalidate a useful
/// archived reply.
fn request_archived_refresh(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  model : Model,
) -> (@cmd.Cmd, Model) {
  guard model.device_state(channel) is Some(dev) else {
    return (@cmd.none, model)
  }
  let request_generation = dev.archived_request_generation + 1
  (
    fetch_archived(
      dispatch,
      channel,
      dev.connection_generation,
      request_generation,
    ),
    model.replace_device({
      ..dev,
      archived_request_generation: request_generation,
    }),
  )
}

///|
/// Adopt one canonical workspace registry snapshot. Conversations from a
/// detached workspace leave this page with its sidebar section: their durable
/// records stay on disk and return when the directory is attached again. If
/// the active conversation leaves, select the newest remaining durable chat,
/// or rotate a fresh one into a project that stayed.
///
/// This is also the transition out of onboarding: a page with nothing on
/// screen — the app just started, or a project has been attached to a device
/// that had none — opens its first chat from here, because the registry is
/// the first thing that says a chat has anywhere to live.
fn adopt_projects(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  model : Model,
  paths : Array[@common.Uri],
) -> (@cmd.Cmd, Model) {
  guard model.device_state(channel) is Some(dev) else {
    return (@cmd.none, model)
  }
  // A pending add whose reply already resolved its registry row waits here
  // for that row to exist: the snapshot that contains it consumes the
  // pending and focuses. A snapshot without the row leaves it waiting —
  // a list read begun before our commit is still current-generation and
  // must not eat the focus the commit broadcast is about to deliver. An
  // unresolved pending stays untouched too: a snapshot alone cannot say
  // which row is ours (another client's commit broadcasts through this
  // same path), so it must never be guessed from one.
  let (focus_target, model) = match model.pending_project_adoption {
    Some(pending) if pending.channel == channel &&
      pending.resolved is Some(target) &&
      paths.contains(target) =>
      (Some(target), { ..model, pending_project_adoption: None, })
    _ => (None, model)
  }
  let selected_detached = channel == model.focused &&
    model.conversation_selection() is Some(selected) &&
    selected.channel == channel &&
    !paths.contains(selected.workspace)
  let active_project = if dev.active_project is None ||
    (dev.active_project is Some(active) && paths.contains(active)) {
    dev.active_project
  } else {
    None
  }
  // Each workspace's worktree list and settings mirror refresh with the
  // adopted registry; a detached workspace's cached rows drop with its
  // section. One request token per collection covers the whole fan-out
  // round.
  let worktrees_request_generation = dev.worktrees_request_generation + 1
  let workspace_settings_request_generation = dev.workspace_settings_request_generation +
    1
  let commands : Array[@cmd.Cmd] = []
  for path in paths {
    commands.push(
      fetch_worktrees(
        dispatch,
        channel,
        path,
        dev.connection_generation,
        worktrees_request_generation,
      ),
    )
    commands.push(
      fetch_workspace_settings(
        dispatch,
        channel,
        path,
        dev.connection_generation,
        workspace_settings_request_generation,
      ),
    )
  }
  let worktrees = dev.worktrees.filter(group => paths.contains(group.project))
  let workspace_settings = dev.workspace_settings.filter(row => {
    paths.contains(row.project)
  })
  // The old whole-session snapshot can outlive the workspace commit
  // broadcast. Prune it immediately so neither the sidebar nor fallback
  // selection can retain a conversation whose store is no longer attached.
  let sessions = dev.sessions.filter(item => paths.contains(item.workspace))
  let conversations = model.conversations.filter(conv => {
    conv.device != channel || paths.contains(conv.project())
  })
  let loading_conversation = if model.loading_conversation is Some(owner) &&
    owner.channel == channel &&
    !conversations
    .iter()
    .any(conv => {
      conv.device == owner.channel && conv.session_id == owner.session
    }) {
    None
  } else {
    model.loading_conversation
  }
  let (refresh_cmd, next) = request_sessions_refresh(dispatch, channel, {
    ..model.replace_device({
      ..dev,
      sessions,
      projects: paths,
      active_project,
      worktrees,
      worktrees_request_generation,
      workspace_settings,
      workspace_settings_request_generation,
    }),
    conversations,
    loading_conversation,
    // A detached workspace takes its settings page with it; the page
    // addresses a row that no longer exists.
    screen: match model.screen {
      WorkspaceSettings(channel=owner, workspace~) if owner == channel &&
        !paths.contains(workspace) => Chat
      screen => screen
    },
  })
  commands.push(refresh_cmd)
  if selected_detached {
    if focus_target is Some(project) {
      // This snapshot both removed the active conversation's project and
      // carries the row the user just added: the explicit add-and-focus
      // wins over fallback selection. NewChatIn rotates the fresh chat; the
      // dead session identity clears now so no render can address it while
      // the rotation is in flight (same rule as the fallback below).
      let (focus_cmd, focused) = update(
        dispatch,
        NewChatIn(channel, Some(project)),
        next,
      )
      commands.push(focus_cmd)
      commands.push(reveal_active_project())
      return (
        @cmd.batch(commands),
        {
          ..focused,
          active_session: "",
          selected_conversation: None,
          conversation_load_failure: None,
          loading_conversation: None,
          screen: Chat,
        },
      )
    }
    if sessions.get(0) is Some(fallback) {
      // The retained list is newest-first. Activate its first entry before
      // starting the reload so no render can address the detached session id
      // while the snapshot is in flight.
      let activated = next
        .activate(channel, fallback.id, fallback.workspace)
        .with_active_project(Some(fallback.workspace))
      // The session list names only the project store. Reconcile that broad
      // placement with the registry and any already-known conversation before
      // reloading: a retained Worktree must not be downgraded to Project, while
      // a session not yet materialized on this page still initializes from its
      // listed project.
      let activated = match activated.active_conversation() {
        Some(fallback_conv) =>
          activated.replace_conversation({
            ..fallback_conv,
            workspace: dev.conversation_workspace(
              fallback.workspace,
              fallback.id,
              fallback_conv.workspace,
            ),
          })
        // `activate` just placed this session, so it is on screen.
        None => activated
      }
      let (fallback_cmd, next) = open_session_on(
        dispatch,
        channel,
        activated,
        fallback.id,
      )
      commands.push(fallback_cmd)
      return (@cmd.batch(commands), next)
    }
    // Nothing is left to select on this device. Session ids are generated
    // inside a Cmd so update remains pure: clear the dead identity now, and
    // rotate a fresh chat into a project that survived (`target_project`
    // picks one). With no project left there is nowhere to rotate into, and
    // the view falls to onboarding until one is attached.
    if !paths.is_empty() {
      commands.push(rotate_session(dispatch, channel))
    }
    return (
      @cmd.batch(commands),
      {
        ..next,
        active_session: "",
        selected_conversation: None,
        conversation_load_failure: None,
        loading_conversation: None,
        screen: Chat,
      },
    )
  }
  if focus_target is Some(project) {
    // The confirmed add just committed: focus its project the way the
    // row's own ＋ does — activate it and start a fresh chat inside — and
    // scroll the newly active row into a long sidebar's view.
    let (focus_cmd, focused) = update(
      dispatch,
      NewChatIn(channel, Some(project)),
      next,
    )
    commands.push(focus_cmd)
    commands.push(reveal_active_project())
    return (@cmd.batch(commands), focused)
  }
  // Nothing is on screen and this device now has somewhere to put a chat:
  // the app's own startup rotation lands here, because it is issued before
  // the registry has answered and has no project to place until it does.
  if channel == next.focused &&
    next.active_conversation() is None &&
    !paths.is_empty() {
    commands.push(rotate_session(dispatch, channel))
  }
  (@cmd.batch(commands), next)
}

///|
/// Retry one failed generation without losing commits that arrived while its
/// snapshot was in flight. Three attempts form one bounded round. Exhaustion
/// keeps the buffer; a later commit/reconnect/open starts a fresh generation,
/// which is what an exhausted background round waits for.
fn retry_session_snapshot(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  model : Model,
  session : String,
  generation : Int,
  activate_on_success : Bool,
  message : String,
) -> (@cmd.Cmd, Model) {
  guard model.find_conversation(channel, session) is Some(conv) &&
    conv.sync
    is Reloading(generation=current, attempt~, buffered~, reload_after_current~) &&
    current == generation else {
    return (@cmd.none, model)
  }
  if attempt < TranscriptReloadMaxAttempts {
    let next_attempt = attempt + 1
    let next = model.replace_conversation({
      ..conv,
      sync: Reloading(
        generation~,
        attempt=next_attempt,
        buffered=buffered.copy(),
        reload_after_current~,
      ),
    })
    let delay_ms = match next_attempt {
      2 => 250
      _ => 500
    }
    (
      @cmd.delay(
        session_snapshot_command(
          dispatch, channel, next, session, generation, activate_on_success,
        ),
        delay_ms,
      ),
      next,
    )
  } else {
    let failed = {
      ..conv,
      sync: ReloadFailed(generation~, buffered=buffered.copy()),
    }
    let next = model.replace_conversation(failed)
    let scroll = @cmd.none
    let owner : @interop.ConversationKey = { channel, session, }
    if activate_on_success && model.loading_conversation == Some(owner) {
      let blocking_failure = !next.selected_conversation_loaded()
      let (toast, next) = next.notify_error(
        dispatch,
        TranscriptRefreshFailedNotice + " (" + message + ")",
      )
      let (sessions, next) = if conv.is_archived_read_only() {
        request_archived_refresh(dispatch, channel, next)
      } else {
        request_sessions_refresh(dispatch, channel, next)
      }
      (
        @cmd.batch([toast, sessions, scroll]),
        {
          ..next,
          loading_conversation: None,
          conversation_load_failure: match next.selected_conversation {
            Some(target) if blocking_failure &&
              target.channel == channel &&
              target.session == session => Some({ target, message, })
            _ => None
          },
        },
      )
    } else {
      (scroll, next)
    }
  }
}

///|
/// Fold one current-generation snapshot into its conversation. Lower
/// watermarks retry instead of rolling the transcript back; stale generations
/// are no-ops. Buffered gaps start one new background generation. A
/// foreground result activates only if it still owns `loading_conversation`.
fn apply_session_snapshot(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  model : Model,
  session : String,
  items : Array[@transcript.TranscriptItem],
  watermark : Int,
  goal : @transcript.GoalStanding?,
  goal_markers : Array[(Int, @transcript.GoalMarker)],
  generation : Int,
  activate_on_success : Bool,
) -> (@cmd.Cmd, Model) {
  guard model.find_conversation(channel, session) is Some(conv) &&
    conv.sync is Reloading(generation=current, reload_after_current~, ..) &&
    current == generation else {
    return (@cmd.none, model)
  }
  if watermark < conv.watermark {
    return retry_session_snapshot(
      dispatch,
      channel,
      model,
      session,
      generation,
      activate_on_success,
      "failed to load session \{session}: snapshot watermark moved backwards",
    )
  }
  let (conv, gapped) = conv.adopt_snapshot(
    items,
    watermark,
    goal~,
    goal_markers~,
  )
  let mut next = model.replace_conversation(conv)
  let commands : Array[@cmd.Cmd] = []
  let owner : @interop.ConversationKey = { channel, session, }
  if activate_on_success && model.loading_conversation == Some(owner) {
    next = {
      ..next.activate(channel, session, conv.project()),
      loading_conversation: None,
      conversation_load_failure: None,
    }
    // An archived transcript has no runnable checkout to inspect here. Its
    // retained workspace placement is still available to file links, but git
    // state is refreshed only after an unarchive turns the record live.
    if !conv.is_archived_read_only() {
      let (branch_cmd, probed) = probe_branch(
        dispatch,
        next,
        channel,
        session,
        next.conversation_root(conv),
      )
      next = probed
      commands.push(branch_cmd)
    }
  }
  if gapped || reload_after_current {
    guard next.find_conversation(channel, session) is Some(conv) else {
      return (@cmd.batch(commands), next)
    }
    let (reloading, next_generation) = next.begin_transcript_reload(conv)
    next = reloading
    if next_generation is Some(next_generation) {
      commands.push(
        session_snapshot_command(
          dispatch, channel, next, session, next_generation, false,
        ),
      )
    }
  }
  (@cmd.batch(commands), next)
}

///|
/// Whether an event the engine emits while idle (between turns) — the
/// compaction lifecycle, background-job notices, and the failure of an
/// idle-time durable append — so the routing must match by last run id: the
/// run that owned the id has already cleared `active_run_id` by the time
/// these arrive.
fn is_idle_event(event : @transcript.EngineEvent) -> Bool {
  match event {
    CompactionStarted
    | CompactionFinished(_)
    | CompactionFailed(_)
    | SessionAppendFailed(_)
    | BackgroundNotice(_) => true
    _ => false
  }
}

///|
fn is_steer_receipt(event : @transcript.EngineEvent) -> Bool {
  event is (SteerApplied(..) | SteerDropped(..))
}

///|
/// A chip's raw jump path as the root-relative form the panel and the host's
/// rooted ops speak. The steady state is the identity: chips
/// minted since the panel started recording relative names are already
/// relative. An older envelope can still carry an absolute path; those are
/// brought back inside against the conversation root, and `None` — an
/// absolute path outside anything this
/// conversation knows — means there is nothing the panel could open.
fn conversation_relative(
  model : Model,
  conv : Conversation,
  path : String,
) -> @pathx.Relative? {
  guard @resource.of_path(conv.device, path) is Some(absolute) else {
    // A string that is not a complete absolute path keeps its existing
    // workspace-relative interpretation.
    return Some(Relative(path))
  }
  if model.conversation_root(conv) is Some(root) &&
    @resource.relative_to(absolute, root) is Some(rest) &&
    !rest.is_root() {
    return Some(rest)
  }
  None
}

///|
/// Begin a non-transcript editor navigation. Transcript links capture this
/// page-lifetime token before their asynchronous host lookup; advancing it at
/// every competing navigation makes the user's latest action authoritative.
fn Model::begin_editor_navigation(self : Model) -> Model {
  {
    ..self,
    file_panel: {
      ..self.file_panel,
      file_link_generation: self.file_panel.file_link_generation + 1,
    },
  }
}

///|
/// Open the shared Explorer picker on one of its three inventories. Dock and
/// panel visibility belong to the shell; inventory selection, focus, and any
/// host-backed refresh belong to fileeditor.
fn open_explorer(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  mode : @fileeditor.ExplorerMode,
) -> (@cmd.Cmd, Model) {
  let model = model.begin_editor_navigation()
  let screen = if model.screen is Codex { Screen::Codex } else { Chat }
  let next = {
    ..model,
    screen,
    dock: @dock.open_picker(model.dock),
    right_panel_open: true,
    right_panel_menu_open: false,
    // Invoking any Explorer inventory is an explicit request to keep it next
    // to the selected file on wide layouts. Narrow file opens still perform
    // the normal drill-down and close this tree.
    file_panel: { ..model.file_panel, tree_open: true, },
  }
  let (cmd, file_panel) = @fileeditor.update(
    dispatch.map(msg => FileEditor(msg)),
    @fileeditor.ExplorerModeSelected(mode),
    next.file_panel,
    file_ctx(next),
  )
  // Opening the picker hides the focused launcher. Hand focus to the panel
  // first; inventory-specific commands can then focus their own input.
  (@cmd.batch([focus_dock_after_render(), cmd]), { ..next, file_panel, })
}

///|
/// Reveal a transcript-linked directory in the editor's Files tree. Keep an
/// active file visible beside the tree; otherwise activate the picker body so
/// the reveal has a visible home. `RevealDirectory` expands the ancestors;
/// transcript navigation additionally expands the target itself, without
/// toggling an already-open row closed.
fn reveal_local_directory(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  path : @pathx.Relative,
) -> (@cmd.Cmd, Model) {
  let dock = match model.dock.active {
    Some(File(_)) | Some(FilePicker) => model.dock
    None | Some(Browser(_)) | Some(GitDiff(_)) | Some(Workflows) =>
      @dock.open_picker(model.dock)
  }
  let model = {
    ..model,
    dock,
    right_panel_open: true,
    right_panel_menu_open: false,
  }
  let (cmd, panel) = @fileeditor.update(
    dispatch.map(msg => FileEditor(msg)),
    @fileeditor.RevealDirectory(path),
    model.file_panel,
    file_ctx(model),
  )
  let model = { ..model, file_panel: panel, }
  if path.is_root() || panel.expanded.contains(path) {
    return (cmd, model)
  }
  let (expand_cmd, panel) = @fileeditor.update(
    dispatch.map(msg => FileEditor(msg)),
    @fileeditor.DirToggle(path),
    panel,
    file_ctx(model),
  )
  (@cmd.batch([cmd, expand_cmd]), { ..model, file_panel: panel, })
}

///|
/// Bring a path into the workspace shown on screen. Codex file mentions come
/// from app-server's fuzzy search and are normally already relative; an
/// absolute value is accepted only inside the selected Codex thread's cwd.
fn Model::active_relative_path(self : Model, path : String) -> @pathx.Relative? {
  if self.screen is Codex {
    guard self.active_checkout() is Some(active) &&
      active.placement is Some(placement) &&
      placement.checkout_root() is Some(workspace) else {
      return None
    }
    if @resource.of_path(self.focused, path) is Some(absolute) {
      guard @resource.relative_to(absolute, workspace) is Some(rest) &&
        !rest.is_root() else {
        return None
      }
      return Some(rest)
    }
    return Some(Relative(path))
  }
  guard self.active_conversation() is Some(conv) else { return None }
  conversation_relative(self, conv, path)
}

///|
/// Open (or refocus) the editor side-panel on `path`, revealing `range` when
/// given — the shared tail of a composer chip's and a transcript chip's jump.
/// The raw path comes from a chip or envelope; a legacy absolute one that
/// cannot be brought inside the workspace surfaces as a panel error instead
/// of a bogus host read.
fn open_editor_at(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  path : String,
  range : @common.Range?,
  file_link_generation? : Int,
  annotation? : String,
) -> (@cmd.Cmd, Model) {
  // A transcript host reply already carries the token its click spent. Every
  // direct mention, Quick Open, or location jump is a newer competing action.
  let model = if file_link_generation is Some(_) {
    model
  } else {
    model.begin_editor_navigation()
  }
  let ctx = file_ctx(model)
  // Chip/transcript jumps call the file-editor package directly rather than
  // passing through its guarded message dispatcher. Keep them parked too: the
  // dock must not grow a loading tab, nor may a host read start, while checkout
  // placement is unresolved or missing.
  guard ctx.placement is Some(placement) && placement.is_ready() else {
    return (@cmd.none, model)
  }
  let owner = ctx.owner
  let femit = dispatch.map(msg => FileEditor(msg))
  // Park/restore the strip for a conversation switch up front, and re-root
  // the file subsystem when its cached tree belongs to another conversation;
  // otherwise `sync_file_panel`'s post-dispatch pass would see a session
  // mismatch and wipe the freshly opened tab below. A re-rooted document
  // table is seeded from the restored strip (identities only), exactly like
  // `@fileeditor.sync`'s own re-root.
  let dock = @dock.sync(model.dock, owner)
  let panel = model.file_panel.prepare_owner(owner, @dock.file_paths(dock))
  guard model.active_relative_path(path) is Some(relative) else {
    return (
      @fileeditor.mount_cmds(femit),
      {
        ..model,
        dock,
        right_panel_open: true,
        right_panel_menu_open: false,
        file_panel: {
          ..panel,
          error: Some("\{path} is outside the conversation workspace"),
        },
      },
    )
  }
  let had_active = @dock.active_file(dock) is Some(_)
  // An explicit open while the picker is the active tab fulfills it, the
  // same as a pick from its tree.
  let dock = if dock.active is Some(FilePicker) {
    @dock.resolve_pick(dock, relative)
  } else {
    @dock.open_file(dock, relative)
  }
  let model = {
    ..model,
    dock,
    file_panel: panel,
    right_panel_open: true,
    right_panel_menu_open: false,
  }
  let (cmd, panel) = @fileeditor.open_file(
    femit,
    panel,
    ctx,
    relative,
    file_link_generation?,
    range~,
    annotation?,
    had_active~,
  )
  (cmd, { ..model, file_panel: panel, })
}

///|
/// Run an accepted slash command against the active conversation and close the
/// completion menu. The command text is cleared from the composer; an unknown
/// id just dismisses the menu.
fn run_slash_command(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  command : String,
) -> (@cmd.Cmd, Model) {
  guard model.active_conversation() is Some(conv) &&
    !conv.is_archived_read_only() else {
    return (@cmd.none, model)
  }
  match command {
    "compact" =>
      // One compaction at a time: a repeat while one is queued or in flight
      // would stack another behind it in the engine's pending queue (the
      // host rejects it anyway) — swallow it like any settled command.
      if !(conv.compaction is NotCompacting) {
        (@cmd.none, { ..model.replace_conversation({ ..conv, task: "", }), })
      } else {
        (
          compact_openseek(
            dispatch,
            model.focused,
            session=conv.session_id,
            model=conv.engine_model,
            reasoning=model.reasoning_for(conv.engine_model),
            max_steps=model.max_steps,
            workspace=conv.project(),
          ),
          {
            ..model.replace_conversation({
              ..conv,
              task: "",
              // Hold the send gate before the host answers: mid-turn the
              // command queues behind the open run, and an idle request may
              // sit in the spawn/write window for seconds (a resumed
              // conversation gets its engine spawned on demand) — a prompt
              // sent into either gap would be consumed and rejected instead
              // of held. compaction_started confirms; CompactRejected clears.
              compaction: if conv.is_running() {
                Queued
              } else {
                Requested
              },
            }),
          },
        )
      }
    "goal" =>
      (
        @cmd.none,
        {
          ..model.replace_conversation({
            ..conv,
            task: "",
            goal_edit: Some({ draft: conv.goal_draft_seed(), }),
          }),
        },
      )
    _ => (@cmd.none, model)
  }
}

///|
/// Send one conversation's goal set (`Some`) or clear (`None`) to its engine.
/// Everything the command needs — session, workspace, launch mode — comes
/// from that conversation, so it cannot land on whichever one happens to be
/// active by the time the request goes out.
fn send_goal(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  conv : Conversation,
  command : String,
  text : String?,
) -> @cmd.Cmd {
  if conv.goal_creates_worktree() is Some(workspace) {
    return set_goal_in_new_worktree(
      dispatch,
      conv.device,
      conv.session_id,
      workspace,
      conv.engine_model,
      model.reasoning_for(conv.engine_model),
      model.max_steps,
      command,
      text,
    )
  }
  goal_openseek(
    dispatch,
    conv.device,
    session=conv.session_id,
    model=conv.engine_model,
    reasoning=model.reasoning_for(conv.engine_model),
    max_steps=model.max_steps,
    workspace=conv.project(),
    command,
    text,
  )
}

///|
/// Fold one engine event into its conversation. Returns the new conversation
/// and, when the event reported a failure the durable record will never carry,
/// the text to raise as a toast — the caller owns the dispatch a toast needs.
fn apply_engine_event(
  conv : Conversation,
  event : @transcript.EngineEvent,
  event_run_id : String?,
) -> (String?, Conversation) {
  match event {
    AgentStep(step) => {
      // The next model request starts after every durable commit this page
      // already knows, including commits buffered during a reload. Advancing
      // the frontier per step prevents an earlier step's identical reasoning
      // from being mistaken for this step's commit.
      let reasoning_frontier = conv.durable_frontier()
      let cleared = conv.clear_streams()
      let conv = { ..cleared, turn: { ..cleared.turn, reasoning_frontier, }, }
      (
        None,
        // A step can only advance an open, uncancelled turn: after a Stop the
        // stage stays Cancelling (steering a dying turn is refused, so the
        // display must not flip the gate back open), and a stray step for a
        // closed run changes nothing.
        if conv.run is Open(run_id~, stage~) && !(stage is Cancelling) {
          { ..conv, run: Open(run_id~, stage=AtStep(step)), }
        } else {
          conv
        },
      )
    }
    AssistantDelta(content) =>
      if content.is_empty() {
        (None, conv)
      } else {
        let conv = conv.complete_reasoning()
        let carried = conv.turn.streaming_response.unwrap_or("")
        (
          None,
          {
            ..conv,
            turn: { ..conv.turn, streaming_response: Some(carried + content), },
          },
        )
      }
    ReasoningDelta(content) =>
      if content.is_empty() ||
        conv.turn.live_reasoning is Some({ complete: true, .. }) {
        // A completed semantic event is the boundary. A delayed fragment must
        // not resurrect or mutate the finished preview.
        (None, conv)
      } else {
        let carried = match conv.turn.live_reasoning {
          Some(reasoning) => reasoning.content
          None => ""
        }
        (
          None,
          {
            ..conv,
            turn: {
              ..conv.turn,
              live_reasoning: Some({
                content: carried + content,
                complete: false,
              }),
            },
          },
        )
      }
    // Full semantic events never append transcript items: the store commit is
    // the sole durable source. The complete reasoning payload replaces any
    // accumulated fragments and seals their transient presentation.
    ReasoningMessage(content) => {
      let normalized = content.trim().to_owned()
      if normalized.is_empty() {
        // Remote delivery strips the complete payload because the durable
        // session event carries it. A remote client may have joined midway
        // through the stream, so its accumulated deltas can be only a suffix;
        // discard that provisional text at settlement and let the canonical
        // commit supply the complete Markdown card.
        (None, { ..conv, turn: { ..conv.turn, live_reasoning: None, }, })
      } else {
        (
          None,
          {
            ..conv,
            turn: {
              ..conv.turn,
              live_reasoning: Some({ content, complete: true, }),
            },
          },
        )
      }
    }
    AssistantMessage(_) => (None, conv.complete_reasoning().clear_response())
    // A background-job completion notice while idle. The durable record owns
    // the transcript card, and the completion is already surfaced to the
    // model as a steer — a toast would double it for an idle reader without
    // adding anything the card does not say.
    BackgroundNotice(_) => (None, conv)
    // A sub-run opened: the lane replaces the notice this used to be, so the
    // minutes it blocks for read as activity rather than silence. A repeated
    // id (a reconnect replaying the bracket) refreshes rather than doubles.
    // The lane docks above the composer, so opening one does not grow the
    // transcript and must not drag a pinned conversation down.
    // A workflow's brackets. The run is recorded for the Workflows tab; its
    // children arrive through the sub-run brackets the host synthesizes from
    // the run's sidecar (below), and resolve through `WorkflowEntryArrived`.
    // Nothing is dropped on close: a finished run is exactly what a reader
    // looks back over.
    WorkflowOpened(id~, first_child~, child_count~, ..) =>
      (
        None,
        {
          ..conv,
          workflows: @workflow.opened(
            conv.workflows,
            id~,
            session=conv.session_id,
            first_child~,
            child_count~,
          ),
        },
      )
    WorkflowClosed(id~) =>
      (None, { ..conv, workflows: @workflow.closed(conv.workflows, id~), })
    SubrunOpened(id~, kind~, label~) => {
      let subruns = conv.turn.subruns.filter(lane => lane.id != id)
      subruns.push({
        id,
        kind,
        label,
        steps: 0,
        activity: "",
        run: event_run_id,
      })
      (
        None,
        {
          ..conv,
          turn: { ..conv.turn, subruns, },
          // A child of a known workflow gets its row here, from the same
          // bracket that opened its lane.
          workflows: @workflow.child_opened(conv.workflows, id~, kind~, label~),
        },
      )
    }
    // Closed: always drop the lane. A captured sub-run already settles as the
    // durable tool brief, so repeating its status here would leave two
    // completion rows. Only an abnormal terminal status needs a local notice.
    //
    // The error goes in the retained OVERLAY, not in `messages`: the finish of
    // the enclosing run starts a snapshot whose `adopt_snapshot` replaces
    // `messages` wholesale, which would erase a non-durable error bubble.
    SubrunClosed(id~, status~, steps~, tokens~) => {
      let closed = conv.turn.subruns.filter(lane => lane.id == id)
      let conv = {
        ..conv,
        turn: {
          ..conv.turn,
          subruns: conv.turn.subruns.filter(lane => lane.id != id),
        },
        workflows: @workflow.child_closed(
          conv.workflows,
          id~,
          status~,
          steps~,
          tokens~,
        ),
      }
      if status == "captured" {
        (None, conv)
      } else {
        let kind = match closed {
          [lane, ..] => lane.kind
          [] => "subrun"
        }
        (
          Some(
            "\{kind} \{id}: \{status} · \{steps} step(s) · \{@labels.compact_count(tokens)} tok",
          ),
          conv,
        )
      }
    }
    Usage(prompt_tokens~, completion_tokens~) =>
      (
        None,
        {
          ..conv,
          turn: {
            ..conv.turn,
            usage_tokens: prompt_tokens + completion_tokens,
          },
        },
      )
    ToolResult(..) => (None, conv)
    // The turn loop records this as an error `tool_result`; its commit is the
    // one canonical transcript source, just like a successful tool result.
    ToolCallDecodeError(..) => (None, conv)
    // A turn cannot end while a tool inside it is still blocked, so a terminal
    // event means the question died with the turn — the engine settles it as
    // cancelled on its way out. Clearing here is what stops a card from
    // outliving the run it belongs to and offering to answer nothing.
    AgentFinished(_)
    | ContextYield(_)
    | AgentAborted(_)
    | AgentSetupFailed(_) =>
      (None, { ..conv.clear_streams(), pending_approval: None, })
    MaxStepsExhausted =>
      (None, { ..conv.clear_streams(), pending_approval: None, })
    // A tool is blocked until this is answered. It replaces whatever card was
    // showing: the engine asks one question at a time, so an unretired older
    // one is a card this client failed to clear, not a second live question.
    ApprovalRequested(id~, tool_name~, detail~, body~) =>
      (
        None,
        {
          ..conv,
          pending_approval: Some({
            id,
            run_id: event_run_id,
            tool_name,
            detail,
            body,
            answered: false,
          }),
        },
      )
    // Settled — by this client, by another one, or by the engine's deadline.
    // Matched by id so a late settlement for an older question cannot retire
    // the card for a newer one.
    ApprovalResolved(id~) =>
      if conv.pending_approval is Some(pending) && pending.id == id {
        (None, { ..conv, pending_approval: None, })
      } else {
        (None, conv)
      }
    // The steer took effect at a step boundary. Its durable user item arrives
    // through `session.event`; the live event only settles pending UI.
    SteerApplied(content~, submission_id~) => {
      ignore(content)
      if submission_id is Some(submission_id) {
        let (next, _) = conv.acknowledge_steer(submission_id, event_run_id)
        // A queued row can receive its steer receipt before the direct queue
        // RPC reply. The receipt is stronger: the text was consumed.
        let (next, _) = next.remove_queued_input(submission_id)
        (None, next)
      } else {
        // Legacy receipt: lifecycle information only. Text is not ownership
        // in a multi-client session, even when it happens to match.
        (None, conv)
      }
    }
    // The steer raced the turn's end through the pipes and was rejected; the
    // text must not vanish silently.
    SteerDropped(content=_, submission_id~) =>
      if submission_id is Some(submission_id) {
        let (next, removed) = conv.reject_steer(submission_id, event_run_id)
        (if removed { Some(SteerDroppedNotice) } else { None }, next)
      } else {
        (None, conv)
      }
    AutoCompactionFinished(_) => (None, conv)
    CompactionStarted => (None, { ..conv, compaction: Compacting, })
    CompactionFinished(_) => (None, { ..conv, compaction: NotCompacting, })
    // An idle-time append the engine could not persist. It names what failed
    // but not which command asked for it, so nothing is settled on it — a
    // pending goal keeps waiting, since this may have been some other item's
    // append and its own may still land. What it does buy is the word: the
    // failure stops being silent, and the row's own text and actions are
    // what the user recovers with.
    SessionAppendFailed(error) => {
      let content = if error.is_blank() {
        "the engine could not save an item to this session"
      } else {
        "the engine could not save an item to this session: \{error}"
      }
      (Some(content), conv)
    }
    CompactionFailed(reason) => {
      let content = if reason.is_blank() {
        "compaction failed"
      } else {
        "compaction failed: \{reason}"
      }
      (Some(content), { ..conv, compaction: NotCompacting, })
    }
  }
}

///|
/// The selected OpenSeek conversation or Codex task, with its single resolved
/// directory placement. Owner identity remains separate because it fences
/// asynchronous replies even while placement is unresolved or missing.
priv struct ActiveCheckout {
  owner : @interop.ConversationKey
  placement : @interop.CheckoutPlacement?
}

///|
/// Select the same owner and placement for transcript links, Files, Terminal,
/// and language services. This is the only screen-dependent directory choice;
/// downstream packages merely project roots from `placement`.
fn Model::active_checkout(self : Model) -> ActiveCheckout? {
  if self.screen is Codex {
    guard self.codex.active_id() is Some(session) else { return None }
    return Some({
      owner: { channel: self.focused, session, },
      placement: self.codex.active_placement(self.focused),
    })
  }
  guard self.active_conversation() is Some(conv) else { return None }
  Some({
    owner: { channel: conv.device, session: conv.session_id, },
    placement: self.conversation_placement(conv),
  })
}

///|
/// The file-editor package's read-only projection of the selected checkout.
fn file_ctx(model : Model) -> @fileeditor.Ctx {
  let active = model
    .active_checkout()
    .unwrap_or({
      owner: { channel: model.focused, session: "", },
      placement: None,
    })
  // A cwd-less Codex task has a valid scratch Terminal identity but app-server
  // exposes no path that Files or language services may address. Keep the one
  // typed placement in Codex state, then project this capability as absent at
  // the file-editor boundary rather than inventing a directory.
  let file_placement = match active.placement {
    Some(@interop.Scratch(root=None)) if model.screen is Codex => None
    placement => placement
  }
  let file_body_visible = match model.dock.active {
    Some(File(_)) | Some(GitDiff(_)) | Some(FilePicker) => true
    None | Some(Browser(_)) | Some(Workflows) => false
  }
  {
    // Keep the real identity even while placement is unresolved or missing.
    // Both panel packages use the typed checkout state to park host work; the
    // stable owner lets an interrupted changed-file review resume after Repair
    // without ever treating the project root as a fallback checkout.
    owner: active.owner,
    request_epoch: model.file_panel.request_epoch,
    // The native bridge and its watcher survive a page reload. Namespace the
    // panel's monotonic counter with this page's existing random identity so
    // a reloaded frontend cannot reuse the outgoing page's watcher token.
    watch_namespace: model.page_namespace + "-watch",
    placement: file_placement,
    dark_mode: model.theme.is_dark(model.system_dark),
    tree_layout: model.tree_layout,
    narrow: model.narrow,
    // The dock's projection: strip membership and the active tab are the
    // dock's truth, handed to the file subsystem read-only.
    // The dock preference survives Skills/Settings navigation, and an open
    // dock can instead show its browser or empty-strip launcher. CSS hides the
    // file body in all three cases. Report actual visibility so the file
    // subsystem parks its workspace watches and Changes refreshes off-screen.
    panel_open: model.right_panel_open &&
    (model.screen is Codex || (model.screen is Chat && file_body_visible)),
    open_files: @dock.file_paths(model.dock),
    active_file: @dock.active_file(model.dock),
    open_history_diffs: @dock.history_diffs(model.dock),
    active_history_diff: @dock.active_history_diff(model.dock),
  }
}

///|
/// The terminal package's view of the active conversation. On the Codex page,
/// the selected app-server thread supplies the PTY session id and cwd. The
/// focused device owns every PTY opened from either source; a remote connection
/// is considered unavailable from its first socket loss because its old PTYs
/// are torn down at that boundary, even before the page escalates to BridgeLost.
fn terminal_ctx(model : Model) -> @terminal.Ctx {
  let active = model
    .active_checkout()
    .unwrap_or({
      owner: { channel: model.focused, session: "", },
      placement: None,
    })
  let connected = match model.device_state(active.owner.channel) {
    Some(dev) => dev.bridge is Connected && dev.reconnect_failures == 0
    None => false
  }
  @terminal.Ctx(
    channel=active.owner.channel,
    session=active.owner.session,
    placement=active.placement,
    dark_mode=model.theme.is_dark(model.system_dark),
    connected~,
  )
}

///|
/// Reconcile the dock strip, then the file subsystem, with the active
/// conversation after every message (see `@dock.sync` /
/// `@fileeditor.sync`). Order matters: the dock parks/restores the strip
/// first, so the file sync sees the fresh projection and re-roots its
/// document table from it. Centralizing it here keeps every
/// conversation-switching handler from having to re-root the panel itself.
fn sync_file_panel(
  dispatch : @cmd.Emit[Msg],
  model : Model,
) -> (Model, @cmd.Cmd) {
  let ctx = file_ctx(model)
  // Placement health is carried separately from identity, so a missing
  // checkout keeps this conversation's strip while both content subsystems
  // refuse host-backed work until Repair settles.
  let dock = @dock.sync(model.dock, ctx.owner)
  let model = { ..model, dock, }
  let (panel, cmd) = @fileeditor.sync(
    dispatch.map(msg => FileEditor(msg)),
    model.file_panel,
    file_ctx(model),
  )
  ({ ..model, file_panel: panel, }, cmd)
}

///|
/// Whether a full-screen surface is drawn over the window. Every overlay
/// `view.mbt` appends after the shell (see its trailing `children.push`
/// block) belongs here: native views z-order above all HTML, so an overlay
/// this predicate forgets renders with the browser pane punched through it,
/// swallowing the clicks that land there.
fn covering_overlay(model : Model) -> Bool {
  (model.narrow && model.sidebar_open) ||
  model.project_picker is Some(_) ||
  model.archive_confirm is Some(_) ||
  model.archived_delete_confirm is Some(_) ||
  model.quick_open.is_open() ||
  model.api_setup_open ||
  model.update_ux is ConfirmingRestart(_) ||
  // Best effort: with the bridge gone the hide op may not deliver.
  model.bridge_state() is BridgeLost(_)
}

///|
/// Which browser page's native view belongs on screen: the active Browser
/// tab's, once it has a URL (a blank tab has no view yet) — and only while
/// the pane is actually visible and uncovered. Native views z-order above
/// all HTML, so anything the frontend draws over the pane area — the `+`
/// launcher popup, the narrow layout's sidebar drawer, a custom select, the
/// composer's Git popover, and every
/// `covering_overlay` — must hide the view rather than fight it.
fn desired_browser_view(model : Model) -> Int? {
  let conversation_screen = model.screen is Chat || model.screen is Codex
  let git_details_open = match model.screen {
    Chat => model.git_details_open
    Codex => model.codex.git_details_open()
    Skills | Settings | WorkspaceSettings(..) => false
  }
  guard model.is_desktop &&
    conversation_screen &&
    model.right_panel_open &&
    !model.right_panel_menu_open &&
    model.select_menu is None &&
    !git_details_open &&
    !covering_overlay(model) else {
    return None
  }
  guard @dock.active_browser(model.dock) is Some(id) &&
    @preview.page(model.preview, id) is Some(page) &&
    page.url is Some(_) else {
    return None
  }
  Some(id)
}

///|
fn browser_geometry(model : Model) -> BrowserGeometry {
  {
    desired: desired_browser_view(model),
    sidebar_open: model.sidebar_open,
    narrow: model.narrow,
    terminal_open: model.terminal.is_open(),
    right_panel_expanded: model.right_panel_expanded,
    tree_layout: model.tree_layout,
  }
}

///|
/// Reconcile the native view with the pane after every message. Hiding is
/// immediate; showing waits for a fresh pane measurement (the measured
/// rectangle comes back as `BrowserPaneMeasured`, which sends the bounds
/// and then the visibility flip). The geometry signature keeps this pass
/// from re-measuring when nothing placement-relevant changed — including
/// after the measurement message itself, which never alters the signature.
fn sync_browser_view(
  dispatch : @cmd.Emit[Msg],
  model : Model,
) -> (Model, @cmd.Cmd) {
  let pane = model.browser_pane
  match desired_browser_view(model) {
    None =>
      match pane.shown {
        Some(old) =>
          (
            { ..model, browser_pane: { shown: None, rect: None, geo: None, }, },
            browser_set_visible(dispatch, old, false),
          )
        None =>
          if pane.geo is Some(_) {
            // A measurement was requested but the view left the screen
            // before it landed; forget it so a later show re-measures.
            (
              {
                ..model,
                browser_pane: { shown: None, rect: None, geo: None, },
              },
              @cmd.none,
            )
          } else {
            (model, @cmd.none)
          }
      }
    Some(_) => {
      let geo = browser_geometry(model)
      if pane.geo == Some(geo) {
        (model, @cmd.none)
      } else {
        (
          { ..model, browser_pane: { ..pane, geo: Some(geo), }, },
          @cmd.batch([
            watch_browser_pane(dispatch),
            measure_browser_pane(dispatch),
          ]),
        )
      }
    }
  }
}

///|
/// Replace a selected record that disappeared while it was active or loading,
/// returning to an existing New chat draft or the supplied fresh id. The
/// removed record's composer state ends with it. List replies and identity
/// notifications share this transition because either can win their delivery
/// race.
fn replace_removed_selection(
  model : Model,
  channel : @interop.ChannelId,
  session : String,
  fresh_session : String,
  workspace : @common.Uri,
  record : ConversationRecord,
) -> Model {
  guard channel == model.focused &&
    model.conversation_selection() is Some(selected) &&
    selected.matches_record(channel, session, workspace, record) &&
    model.conversations
    .iter()
    .find_first(conv => {
      conv.device == channel &&
      conv.session_id == session &&
      conv.project() == workspace &&
      conv.is_archived_read_only() == (record is ArchivedRecord)
    })
    is Some(_) else {
    return model
  }
  let conversations = model.conversations.filter(conv => {
    conv.device != channel ||
    conv.session_id != session ||
    conv.project() != workspace ||
    conv.is_archived_read_only() != (record is ArchivedRecord)
  })
  let fallback = conversations
    .rev_iter()
    .find_first(conv => {
      conv.device == channel &&
      conv.project() == workspace &&
      model.conversation_is_new_chat(conv) &&
      conv.worth_keeping()
    })
  let fallback_session = match fallback {
    Some(draft) => draft.session_id
    None => fresh_session
  }
  let activated = { ..model, conversations, }
    .activate(channel, fallback_session, workspace)
    .with_active_project(Some(workspace))
  let activated = match fallback {
    Some(_) => activated
    None =>
      match activated.active_conversation() {
        Some(fresh) =>
          activated.replace_conversation({
            ..fresh,
            worktree_mode: model.default_worktree_mode(channel, workspace),
          })
        None => activated
      }
  }
  {
    ..activated,
    screen: Chat,
    loading_conversation: None,
    conversation_load_failure: None,
  }
}

///|
fn update(
  dispatch : @cmd.Emit[Msg],
  msg : Msg,
  model : Model,
) -> (@cmd.Cmd, Model) {
  let previous = model
  let (cmd, model) = update_msg(dispatch, msg, model)
  let notification_badge_cmd = notification_badge_command(
    previous,
    model,
    msg is Init,
  )
  let composer_context_changed = model.active_session != previous.active_session ||
    model.focused != previous.focused ||
    model.screen != previous.screen
  let model = if composer_context_changed {
    {
      ..model,
      composer_context_generation: previous.composer_context_generation + 1,
      select_menu: None,
    }
  } else {
    model
  }
  // Manual popovers sit above ordinary fixed backdrops in the browser's top
  // layer, so a newly covering surface must retire the root-owned select.
  let model = if !covering_overlay(previous) && covering_overlay(model) {
    { ..model, select_menu: None, }
  } else {
    model
  }
  // A registry refresh can retire the title control without changing the
  // active session. Do not leave its root menu flag hiding a native Browser
  // view after the control itself has disappeared.
  let model = if model.select_menu == Some(ProjectMenu) &&
    !model.can_choose_new_chat_project() {
    { ..model, select_menu: None, project_menu_query: "", }
  } else {
    model
  }
  // The query has meaning only while its exact menu is open. Context changes,
  // covering overlays, and selections close menus in several handlers; keep
  // all of those paths from reviving an old filter on the next fresh draft.
  let model = if model.select_menu == Some(ProjectMenu) ||
    model.project_menu_query.is_empty() {
    model
  } else {
    { ..model, project_menu_query: "", }
  }
  // On the narrow layout the sidebar is a full-screen drawer, so any
  // navigation that lands somewhere else — switching or creating a
  // conversation, opening Skills or Settings — closes it; centralizing the
  // rule here keeps every navigation handler drawer-agnostic.
  let model = if model.narrow &&
    model.sidebar_open &&
    (
      model.active_session != previous.active_session ||
      model.focused != previous.focused ||
      model.screen != previous.screen
    ) {
    { ..model, sidebar_open: false, }
  } else {
    model
  }
  // The quick pick belongs to the focused conversation captured when it
  // opened, and to that conversation's concrete root. Both can change through
  // many messages — device/session switches, background pushes, connection
  // metadata, restored session data, a worktree registry broadcast — so the
  // package fences the palette once here rather than in every branch.
  let (quick_open_cmd, quick_open) = match model.active_checkout() {
    Some(active) =>
      model.quick_open.reconcile(
        dispatch.map(msg => QuickOpen(msg)),
        model.quick_open_input(active),
      )
    // No checkout on screen is no owner to fence against — the palette has
    // nothing left to search, so it closes here for the same reason it does
    // when its conversation is replaced.
    None => model.quick_open.close()
  }
  let model = { ..model, quick_open, }
  // The composer's git popover belongs to the checkout that was on screen,
  // and is fenced the same way and for the same reason. It cannot rely on its
  // click-away listener here: a switch by keyboard — Cmd+N, Quick Open — makes
  // no click at all, and neither does a checkout losing its repository under
  // it. Left standing the flag would spring the popover open on the
  // conversation arriving, once its branch probe answered, and meanwhile keep
  // `desired_browser_view` hiding the native browser with no chip on screen to
  // click — a blank pane with nothing to explain it.
  //
  // The second clause is the invariant rather than a list of paths: no chip,
  // no popover, however the branch came to be gone.
  let model = if model.git_details_open &&
    (
      model.active_session != previous.active_session ||
      model.focused != previous.focused ||
      !(model.active_conversation() is Some(conv) && conv.shows_git_chip())
    ) {
    { ..model, git_details_open: false, }
  } else {
    model
  }
  // Panel visibility is root-owned because it controls both HTML layout and
  // host-backed editor/browser lifecycles. Reconcile every transition once
  // here, no matter which semantic action opened or closed the panel.
  let panel_visibility_changed = model.right_panel_open !=
    previous.right_panel_open
  // These messages call `open_editor_at` before this reconciliation. A valid
  // open already mounts the Viewer and either shows the cached document or
  // starts its generation-tagged read, including when the same TabLoading
  // document existed before the message. Activating it again here would start
  // a second untagged read. Failed/out-of-workspace opens retain an error and
  // still take the generic path so an older active document is restored.
  let file_opened_with_panel = !previous.right_panel_open &&
    model.right_panel_open &&
    msg.opens_file_before_panel_reconciliation() &&
    model.file_panel.error is None &&
    @dock.active_file(model.dock) is Some(_)
  let (panel_visibility_cmd, model) = if panel_visibility_changed &&
    !file_opened_with_panel {
    let (command, file_panel) = @fileeditor.panel_toggle_cmds(
      dispatch.map(msg => FileEditor(msg)),
      model.file_panel,
      file_ctx(model),
      opening=model.right_panel_open,
    )
    (command, { ..model, file_panel, })
  } else {
    (@cmd.none, model)
  }
  // Codex owns its Git popover flag, while the shell owns screen selection.
  // Leaving Codex closes the surface here so returning later cannot reopen a
  // popover for a task that is no longer the visible conversation.
  let model = if !(model.screen is Codex) && model.codex.git_details_open() {
    { ..model, codex: model.codex.with_git_details_closed(), }
  } else {
    model
  }
  let (model, panel_cmd) = sync_file_panel(dispatch, model)
  // The launcher menu belongs to one dock owner. Conversation changes are
  // already explicit root transitions, so close it here instead of observing a
  // rendered owner marker through the DOM.
  let model = if model.right_panel_menu_open &&
    model.dock.owner != previous.dock.owner {
    { ..model, right_panel_menu_open: false, }
  } else {
    model
  }
  // Terminal input changes are reconciled as part of the root transition.
  // Host transport installation is declared separately by the root
  // subscriptions, so terminal reconciliation owns only terminal state.
  let terminal_emit = dispatch.map(msg => Terminal(msg))
  let terminal_input = model.terminal_input()
  let (terminal, terminal_cmd) = model.terminal.reconcile(
    terminal_emit, terminal_input,
  )
  let model = { ..model, terminal, }
  let (model, browser_cmd) = sync_browser_view(dispatch, model)
  (
    @cmd.batch([
      cmd, notification_badge_cmd, quick_open_cmd, panel_visibility_cmd, panel_cmd,
      terminal_cmd, browser_cmd,
    ]),
    model,
  )
}

///|
/// Whether this root message calls `open_editor_at` synchronously. `OpenFile`
/// is deliberately absent: it only begins a host lookup. `OpenFileAt` opens
/// the panel later, after the host has classified the target as editable text.
fn Msg::opens_file_before_panel_reconciliation(self : Msg) -> Bool {
  self
  is (ComposerAction(@composer.MentionOpened(..))
  | CodexComposerAction(@composer.MentionOpened(..))
  | JumpToMention(_)
  | JumpToLocation(..)
  | QuickOpen(@quick_open.Pick(_))
  | OpenFileAt(..)
  | FileEditor(@fileeditor.SearchMatchSelected(..)))
}

///|
fn close_all_tabs(
  dispatch : @cmd.Emit[Msg],
  model : Model,
) -> (@cmd.Cmd, Model) {
  let tabs = model.dock.tabs.copy()
  guard !tabs.is_empty() else { return (@cmd.none, model) }
  let active = model.dock.active
  let commands : Array[@cmd.Cmd] = []
  let mut next = model
  // Close background tabs first so the active tab does not promote and mount
  // another tab that this same action is about to close. Routing every close
  // through the ordinary transition preserves document and browser teardown.
  for tab in tabs {
    if Some(tab) != active {
      let (command, updated) = update_msg(dispatch, Dock(TabClosed(tab)), next)
      commands.push(command)
      next = updated
    }
  }
  if active is Some(tab) {
    let (command, updated) = update_msg(dispatch, Dock(TabClosed(tab)), next)
    commands.push(command)
    next = updated
  }
  (
    @cmd.batch(commands),
    {
      ..next,
      right_panel_open: true,
      right_panel_menu_open: false,
      right_panel_expanded: false,
    },
  )
}

///|
fn update_msg(
  dispatch : @cmd.Emit[Msg],
  msg : Msg,
  model : Model,
) -> (@cmd.Cmd, Model) {
  match msg {
    Init =>
      // A browser console boots by asking the relay who is signed in; the
      // bridge and session rotation wait for the first roster (`apply_roster`)
      // because there is no channel to install before sign-in. Component
      // subscriptions own their transcript and terminal DOM lifetimes.
      match model.console {
        Some(_) =>
          (
            @cmd.batch([
              fetch_console_me(dispatch),
              load_saved_settings(dispatch),
              // Browser localStorage is relay-origin state, not device
              // state. Purge old client-held engine credentials even while
              // signed out or when no device is online to reach
              // `BridgeReady`.
              clear_legacy_engine_settings(),
              watch_color_scheme(dispatch),
              request_sidebar_resize_mount(),
              measure_scrollbar_lane(),
            ]),
            model,
          )
        None =>
          (
            @cmd.batch([
              load_saved_settings(dispatch),
              watch_color_scheme(dispatch),
              rotate_session(dispatch, model.focused),
              request_sidebar_resize_mount(),
              measure_scrollbar_lane(),
            ]),
            model,
          )
      }
    Console(msg) => update_console_msg(dispatch, msg, model)
    SettingsLoaded(
      notification_corner~,
      tree_layout~,
      theme~,
      font~,
      font_size~,
      fps_overlay_enabled~,
      model=stored,
      conversation_models=remembered,
      agent~,
      codex_model~,
      codex_effort~,
      openseek_effort~,
      glm_effort~
    ) => {
      let theme = Theme::parse(theme, model.theme)
      let app_font = AppFont::parse(font, model.app_font)
      let app_font_size = AppFontSize::parse(font_size, model.app_font_size)
      // Startup runs before any conversation exists, so adopting the stored
      // tiers here is enough — every conversation minted afterwards reads
      // them.
      let default_model = EngineModel::parse(stored).unwrap_or(
        model.default_model,
      )
      let default_agent = AgentChoice::parse(agent).unwrap_or(
        model.default_agent,
      )
      let openseek_reasoning = OpenSeekReasoning::parse(openseek_effort).unwrap_or(
        model.openseek_reasoning,
      )
      let glm_reasoning = OpenSeekReasoning::parse(glm_effort).unwrap_or(
        model.glm_reasoning,
      )
      // The stored Codex pick seeds Codex's own selection state. When the
      // catalog arrives, `with_models` keeps this id if it is still listed
      // and otherwise falls back to the catalog default — exactly the
      // semantics a stale stored preference should have.
      let (codex_cmd, codex) = if codex_model.is_blank() {
        (@cmd.none, model.codex)
      } else {
        @codex.update(
          dispatch.map(msg => Codex(channel=model.focused, msg)),
          @codex.Msg::model_changed(codex_model.trim().to_owned()),
          model.codex,
          model.focused,
          url => open_external_link(dispatch, url),
        )
      }
      let (codex_effort_cmd, codex) = if codex_effort.is_blank() {
        (@cmd.none, codex)
      } else {
        @codex.update(
          dispatch.map(msg => Codex(channel=model.focused, msg)),
          @codex.Msg::effort_changed(codex_effort.trim().to_owned()),
          codex,
          model.focused,
          url => open_external_link(dispatch, url),
        )
      }
      let next = {
        ..model,
        notification_corner: NotificationCorner::parse(notification_corner),
        tree_layout: @fileeditor.TreeLayout::parse(tree_layout),
        theme,
        app_font,
        app_font_size,
        fps_overlay_enabled,
        default_model,
        default_agent,
        conversation_models: parse_conversation_models(remembered),
        openseek_reasoning,
        glm_reasoning,
        codex,
      }
      // The localStorage read and the host settings request start together.
      // If the host won that race, reconcile the just-loaded model preference
      // now; otherwise `HostSettingsLoaded` performs the same fold later.
      let next = if next.host_settings_loaded() {
        next.align_fresh_conversation_with_provider()
      } else {
        next
      }
      (
        @cmd.batch([
          theme.apply(model.system_dark, model.is_desktop, dispatch),
          app_font.apply(),
          app_font_size.apply(),
          codex_cmd,
          codex_effort_cmd,
        ]),
        next,
      )
    }
    // The host's settings, from the bridge-time `settings.get` or a peer's
    // edit broadcast. Revisions order concurrent clients and RPC replies;
    // while this page has optimistic writes, keep only the newest status and
    // apply it once the last write settles.
    LegacySettingsRead(provider~, custom_url~, api_key~, custom_api_key~) =>
      // Only the desktop window migrates: it is the one client whose stored
      // values are unambiguously this host's. A browser page's copy may
      // belong to a different device behind the same origin — pushing it is
      // exactly the leak the host-side store removes — so it is purged.
      if model.is_desktop {
        let patch = legacy_settings_patch(
          provider~,
          custom_url~,
          api_key~,
          custom_api_key~,
        )
        // Mirror the pushed values optimistically so the Settings page and
        // the ready gate reflect the migration immediately.
        let next = {
          ..model,
          api_provider: ApiProvider::parse(provider),
          custom_api_url: custom_url.trim().to_owned(),
          deepseek_key_saved: model.deepseek_key_saved || !api_key.is_blank(),
          custom_key_saved: model.custom_key_saved || !custom_api_key.is_blank(),
          settings_saves: model.settings_saves + 1,
          legacy_cleanup_pending: true,
        }
        (
          push_host_settings(
            dispatch,
            model.focused,
            patch,
            model.focused_connection_generation(),
            cleans_legacy=true,
          ),
          next,
        )
      } else {
        (clear_legacy_engine_settings(), model)
      }
    CodexComposerAction(action) =>
      match action {
        @composer.ModelMenuToggled(identity~) => {
          guard model.screen is Codex &&
            model.codex.accepts_composer_identity(identity, model.focused) else {
            return (@cmd.none, model)
          }
          update_msg(dispatch, ToggleSelectMenu(CodexModelMenu), model)
        }
        @composer.ReasoningMenuToggled(identity~) => {
          guard model.screen is Codex &&
            model.codex.accepts_composer_identity(identity, model.focused) else {
            return (@cmd.none, model)
          }
          update_msg(dispatch, ToggleSelectMenu(CodexReasoningMenu), model)
        }
        @composer.SelectMenuDismissed(identity~) => {
          guard model.screen is Codex &&
            model.codex.accepts_composer_identity(identity, model.focused) else {
            return (@cmd.none, model)
          }
          update_msg(dispatch, CloseSelectMenu, model)
        }
        @composer.ModelSelected(identity~, value~) => {
          guard model.screen is Codex &&
            model.codex.accepts_composer_identity(identity, model.focused) else {
            return (@cmd.none, model)
          }
          update_msg(dispatch, ModelPicked(value), model)
        }
        @composer.ReasoningSelected(identity~, value~) => {
          guard model.screen is Codex &&
            model.codex.accepts_composer_identity(identity, model.focused) else {
            return (@cmd.none, model)
          }
          update_msg(dispatch, CodexEffortPicked(value), model)
        }
        @composer.MentionOpened(identity~, mention~) => {
          guard model.screen is Codex &&
            model.codex.accepts_composer_identity(identity, model.focused) else {
            return (@cmd.none, model)
          }
          guard @mention_context.target(mention.ref_) is Some(target) else {
            return (@cmd.none, model)
          }
          let range = if mention.range is Some(_) {
            mention.range
          } else {
            target.range
          }
          open_editor_at(
            dispatch,
            model,
            target.file,
            range,
            annotation?=target.annotation,
          )
        }
        @composer.FileIndexEnsured(identity~) => {
          guard model.screen is Codex &&
            model.codex.accepts_composer_identity(identity, model.focused) else {
            return (@cmd.none, model)
          }
          update_msg(dispatch, FileEditor(@fileeditor.EnsureFileIndex), model)
        }
        _ => {
          let channel = model.focused
          let (command, codex) = @codex.update(
            dispatch.map(next => Codex(channel~, next)),
            @codex.Msg::composer_action(action),
            model.codex,
            channel,
            url => open_external_link(dispatch, url),
          )
          (command, { ..model, codex, })
        }
      }
    ComposerAction(action) =>
      match action {
        @composer.ModelMenuToggled(..)
        | @composer.ReasoningMenuToggled(..)
        | @composer.SelectMenuDismissed(..)
        | @composer.ModelSelected(..)
        | @composer.ReasoningSelected(..)
        | @composer.ApprovalAnswered(..)
        | @composer.CodexRequestAnswerChanged(..)
        | @composer.CodexRequestResponded(..)
        | @composer.PermissionMenuToggled(..)
        | @composer.PermissionMenuDismissed(..)
        | @composer.PermissionSelected(..)
        | @composer.GitDetailsToggled(..)
        | @composer.WorktreeModeToggled(..)
        | @composer.ApiSetupRequested(..)
        | @composer.QueuedInputEditRequested(..)
        | @composer.QueuedInputSteerRequested(..)
        | @composer.QueuedInputDeleteRequested(..)
        | @composer.WorktreePlacementRetried(..)
        | @composer.MissingWorktreeRebuildRequested(..)
        | @composer.MissingWorktreeArchiveRequested(..) => {
          let identity = action.identity()
          guard model.screen is Chat &&
            model.conversation_for_composer_action(identity) is Some(conv) &&
            conv.device == model.focused &&
            conv.session_id == model.active_session else {
            return (@cmd.none, model)
          }
          match action {
            @composer.ModelMenuToggled(..) =>
              update_msg(dispatch, ToggleSelectMenu(OpenSeekModelMenu), model)
            @composer.ReasoningMenuToggled(..) =>
              update_msg(
                dispatch,
                ToggleSelectMenu(OpenSeekReasoningMenu),
                model,
              )
            @composer.SelectMenuDismissed(..) =>
              update_msg(dispatch, CloseSelectMenu, model)
            @composer.ModelSelected(value~, ..) =>
              update_msg(dispatch, ModelPicked(value), model)
            @composer.ReasoningSelected(value~, ..) =>
              update_msg(dispatch, OpenSeekEffortPicked(value), model)
            @composer.ApprovalAnswered(allow~, ..) =>
              update_msg(dispatch, ApprovalAnswered(allow~), model)
            @composer.GitDetailsToggled(..) =>
              update_msg(dispatch, ToggleGitDetails, model)
            @composer.WorktreeModeToggled(..) =>
              update_msg(dispatch, ToggleWorktreeMode, model)
            @composer.ApiSetupRequested(..) =>
              update_msg(dispatch, OpenApiSetup, model)
            @composer.QueuedInputEditRequested(id~, ..) => {
              guard conv.run is Open(stage~, ..) &&
                !(stage is Cancelling) &&
                conv.queued_inputs.search_by(item => item.id == id)
                is Some(index) else {
                return (@cmd.none, model)
              }
              let item = conv.queued_inputs[index]
              (
                @cmd.none,
                model.replace_conversation({
                  ..conv,
                  task: user_display_text(item.content),
                  mentions: [],
                  composer_draft_present: true,
                  queue_edit_id: Some(id),
                }),
              )
            }
            @composer.QueuedInputSteerRequested(id~, ..) => {
              guard conv.run is Open(run_id~, stage~) && !(stage is Cancelling) else {
                return (@cmd.none, model)
              }
              guard conv.queued_inputs.search_by(item => item.id == id)
                is Some(index) &&
                !conv.pending_steers
                .iter()
                .any(input => input.submission_id == id) else {
                return (@cmd.none, model)
              }
              let item = conv.queued_inputs[index]
              let conv = conv.enqueue_steer(
                id,
                Some(run_id),
                item.content,
                user_display_text(item.content),
                [],
                FollowupSteer,
              )
              (
                queue_openseek(
                  dispatch,
                  conv.device,
                  conv.session_id,
                  @protocol.QueueSteer(id~),
                  run_id,
                ),
                model.replace_conversation(conv),
              )
            }
            @composer.QueuedInputDeleteRequested(id~, ..) => {
              guard conv.run is Open(run_id~, stage~) && !(stage is Cancelling) else {
                return (@cmd.none, model)
              }
              let editing = conv.queue_edit_id == Some(id)
              (
                queue_openseek(
                  dispatch,
                  conv.device,
                  conv.session_id,
                  @protocol.QueueWithdraw(id~),
                  run_id,
                ),
                if editing {
                  model.replace_conversation({
                    ..conv,
                    task: "",
                    mentions: [],
                    composer_draft_present: false,
                    queue_edit_id: None,
                  })
                } else {
                  model
                },
              )
            }
            @composer.WorktreePlacementRetried(..) =>
              update_msg(dispatch, RetryWorktreePlacement, model)
            @composer.MissingWorktreeRebuildRequested(..) =>
              update_msg(dispatch, RepairWorktree, model)
            @composer.MissingWorktreeArchiveRequested(..) =>
              update_msg(
                dispatch,
                ArchiveSession(conv.device, conv.session_id),
                model,
              )
            @composer.PermissionMenuToggled(..)
            | @composer.PermissionMenuDismissed(..)
            | @composer.PermissionSelected(..)
            | @composer.CodexRequestAnswerChanged(..)
            | @composer.CodexRequestResponded(..) => (@cmd.none, model)
            _ => (@cmd.none, model)
          }
        }
        @composer.DraftSubmitted(identity~, draft~) => {
          guard model.conversation_for_composer_action(identity) is Some(conv) else {
            return (@cmd.none, model)
          }
          let original_focus = model.focused
          let original_session = model.active_session
          // `Send` reads the selected conversation synchronously. Select the
          // action owner only for that update, then restore visible navigation
          // while retaining the targeted conversation's submission state.
          let target = {
            ..model.replace_conversation({
              ..conv,
              task: draft.task,
              mentions: draft.mentions,
              composer_draft_present: true,
            }),
            focused: conv.device,
            active_session: conv.session_id,
          }
          let (command, submitted) = update_msg(dispatch, Send, target)
          (
            command,
            {
              ..submitted,
              focused: original_focus,
              active_session: original_session,
            },
          )
        }
        @composer.DraftPresenceChanged(identity~, present~, cleared_source~) =>
          if model.conversation_for_composer_action(identity) is Some(conv) {
            let task = if !present &&
              cleared_source is Some(source) &&
              conv.task == source.task {
              ""
            } else {
              conv.task
            }
            let mentions = if !present &&
              cleared_source is Some(source) &&
              conv.mentions == source.mentions {
              []
            } else {
              conv.mentions
            }
            (
              @cmd.none,
              model.replace_conversation({
                ..conv,
                task,
                mentions,
                composer_draft_present: present,
              }),
            )
          } else {
            (@cmd.none, model)
          }
        @composer.RootMentionRemoved(identity~, mention~) => {
          guard model.conversation_for_composer_action(identity) is Some(conv) else {
            return (@cmd.none, model)
          }
          (
            @cmd.none,
            model.replace_conversation({
              ..conv,
              mentions: conv.mentions.filter(existing => {
                existing.ref_ != mention.ref_
              }),
            }),
          )
        }
        @composer.SlashCommand(identity~, command~) => {
          guard model.conversation_for_composer_action(identity) is Some(conv) else {
            return (@cmd.none, model)
          }
          let (command, changed) = run_slash_command(
            dispatch,
            { ..model, focused: conv.device, active_session: conv.session_id, },
            command,
          )
          (
            command,
            {
              ..changed,
              focused: model.focused,
              active_session: model.active_session,
            },
          )
        }
        @composer.MentionOpened(identity~, mention~) => {
          guard model.conversation_for_composer_action(identity) is Some(conv) else {
            return (@cmd.none, model)
          }
          guard @mention_context.target(mention.ref_) is Some(target) else {
            return (@cmd.none, model)
          }
          let range = if mention.range is Some(_) {
            mention.range
          } else {
            target.range
          }
          let (command, opened) = open_editor_at(
            dispatch,
            { ..model, focused: conv.device, active_session: conv.session_id, },
            target.file,
            range,
            annotation?=target.annotation,
          )
          (
            command,
            {
              ..opened,
              focused: model.focused,
              active_session: model.active_session,
            },
          )
        }
        @composer.GoalCancelled(identity~) => {
          guard model.conversation_for_composer_action(identity) is Some(conv) else {
            return (@cmd.none, model)
          }
          (@cmd.none, model.replace_conversation({ ..conv, goal_edit: None, }))
        }
        @composer.GoalEditStarted(identity~) => {
          guard model.conversation_for_composer_action(identity) is Some(conv) else {
            return (@cmd.none, model)
          }
          let (command, changed) = update_msg(dispatch, OpenGoalEditor, {
            ..model,
            focused: conv.device,
            active_session: conv.session_id,
          })
          (
            command,
            {
              ..changed,
              focused: model.focused,
              active_session: model.active_session,
            },
          )
        }
        @composer.GoalCleared(identity~) => {
          guard model.conversation_for_composer_action(identity) is Some(conv) else {
            return (@cmd.none, model)
          }
          let (command, changed) = update_msg(dispatch, ClearGoal, {
            ..model,
            focused: conv.device,
            active_session: conv.session_id,
          })
          (
            command,
            {
              ..changed,
              focused: model.focused,
              active_session: model.active_session,
            },
          )
        }
        @composer.GoalSubmitted(identity~, draft~, prompt_present~) => {
          guard model.conversation_for_composer_action(identity) is Some(conv) else {
            return (@cmd.none, model)
          }
          guard conv.goal_edit is Some(_) else { return (@cmd.none, model) }
          let target = {
            ..model.replace_conversation({
              ..conv,
              goal_edit: Some({ draft, }),
              composer_draft_present: prompt_present,
            }),
            focused: conv.device,
            active_session: conv.session_id,
          }
          let (command, submitted) = update_msg(dispatch, SubmitGoal, target)
          (
            command,
            {
              ..submitted,
              focused: model.focused,
              active_session: model.active_session,
            },
          )
        }
        @composer.FileIndexEnsured(identity~) => {
          guard model.conversation_for_composer_action(identity) is Some(conv) else {
            return (@cmd.none, model)
          }
          let (command, indexed) = update_msg(
            dispatch,
            FileEditor(@fileeditor.EnsureFileIndex),
            { ..model, focused: conv.device, active_session: conv.session_id, },
          )
          (
            command,
            {
              ..indexed,
              focused: model.focused,
              active_session: model.active_session,
            },
          )
        }
        @composer.StopRequested(identity~) => {
          guard model.conversation_for_composer_action(identity) is Some(conv) else {
            return (@cmd.none, model)
          }
          let (command, stopped) = update_msg(dispatch, Stop, {
            ..model,
            focused: conv.device,
            active_session: conv.session_id,
          })
          (
            command,
            {
              ..stopped,
              focused: model.focused,
              active_session: model.active_session,
            },
          )
        }
      }
    JumpToMention(index) => {
      guard model.active_conversation() is Some(conv) else {
        return (@cmd.none, model)
      }
      guard conv.mentions.get(index) is Some(mention) else {
        return (@cmd.none, model)
      }
      guard @mention_context.target(mention.ref_) is Some(target) else {
        return (@cmd.none, model)
      }
      // A draft chip still holds the full resolved range (columns included);
      // the envelope-shaped target range is the fallback.
      let range = if mention.range is Some(_) {
        mention.range
      } else {
        target.range
      }
      open_editor_at(
        dispatch,
        model,
        target.file,
        range,
        annotation?=target.annotation,
      )
    }
    JumpToLocation(path~, range~, annotation~) =>
      open_editor_at(dispatch, model, path, range, annotation?)
    // Intercepted here rather than delegated to the fileeditor package: the
    // comment becomes an annotation chip on the composer draft, which only
    // this model knows about. `quote`/`range` come from the panel's viewer.
    FileEditor(
      EditorCommentAdded(
        resource~,
        file~,
        range~,
        quote~,
        comment~,
        feedback_id~
      )
    ) => {
      if model.screen is Codex {
        // Codex owns a separate wire model, but the visible editor annotation
        // is the same structured chip as OpenSeek's. Keep it in Codex's shared
        // composer tray; never leak it into the hidden OpenSeek conversation.
        return (
          @fileeditor.remove_editor_feedback(resource, feedback_id),
          {
            ..model,
            codex: model.codex.with_editor_comment(
              file.0,
              range,
              comment,
              quote,
            ),
          },
        )
      }
      guard model.active_conversation() is Some(conv) else {
        return (@cmd.none, model)
      }
      let mentions = @composer.Draft::{
          task: conv.task,
          mentions: conv.mentions,
        }.with_mention({
          ref_: Annotation(
            file=file.0,
            start_line=range.start_line_number,
            end_line=range.end_line_number,
            quote~,
            comment~,
            side=@mention_context.WorkingRevision,
          ),
          range: Some(range),
        }).mentions
      // The chip is the comment's carrier from here on; clearing the editor's
      // own bubble keeps the two from drifting apart (and from double-sending
      // if the user comments again).
      (
        @fileeditor.remove_editor_feedback(resource, feedback_id),
        model.replace_conversation({ ..conv, mentions, }),
      )
    }
    // The feedback service queues this after the comment-added message above,
    // so the new annotation is already in the visible composer batch. Reuse
    // each agent's normal submit path: an idle task starts, while a running
    // task receives the batch through its existing steer/message queue.
    FileEditor(@fileeditor.ApplyAllFeedback) =>
      match model.screen {
        Chat => update_msg(dispatch, Send, model)
        Codex => {
          let input = model.codex_composer_input()
          update_msg(
            dispatch,
            CodexComposerAction(
              @composer.DraftSubmitted(
                identity=input.identity,
                draft=input.draft,
              ),
            ),
            model,
          )
        }
        Skills | Settings | WorkspaceSettings(..) => (@cmd.none, model)
      }
    // Full-diff comments carry both line domains because a deletion has no
    // working-document position. Prefer the modified line for additions and
    // context; retain the original line for an original-only deletion. Only a
    // modified-side comment receives a concrete editor range, so reopening a
    // deleted-line chip cannot claim stale source columns.
    FileEditor(
      DiffCommentAdded(
        file~,
        original_line_number~,
        modified_line_number~,
        quote~,
        comment~,
        resource~,
        feedback_id~
      )
    ) => {
      let clear_feedback = match (resource, feedback_id) {
        (Some(resource), Some(feedback_id)) =>
          @fileeditor.remove_editor_feedback(resource, feedback_id)
        _ => @cmd.none
      }
      let (line_number, range, side) = match modified_line_number {
        Some(line_number) if line_number >= 1 => {
          let end_column = if quote.is_empty() { 1 } else { quote.length() + 1 }
          (
            line_number,
            Some(@common.Range(line_number, 1, line_number, end_column)),
            @mention_context.WorkingRevision,
          )
        }
        _ =>
          match original_line_number {
            Some(line_number) if line_number >= 1 =>
              (line_number, None, @mention_context.OriginalRevision)
            _ => return (clear_feedback, model)
          }
      }
      if model.screen is Codex {
        let end_column = if quote.is_empty() { 1 } else { quote.length() + 1 }
        let comment_range = range.unwrap_or(
          @common.Range(line_number, 1, line_number, end_column),
        )
        return (
          clear_feedback,
          {
            ..model,
            codex: model.codex.with_editor_comment(
              file.0,
              comment_range,
              comment,
              quote,
              side~,
            ),
          },
        )
      }
      guard model.active_conversation() is Some(conv) else {
        return (clear_feedback, model)
      }
      let mentions = @composer.Draft::{
          task: conv.task,
          mentions: conv.mentions,
        }.with_mention({
          ref_: Annotation(
            file=file.0,
            start_line=line_number,
            end_line=line_number,
            quote~,
            comment~,
            side~,
          ),
          range,
        }).mentions
      (clear_feedback, model.replace_conversation({ ..conv, mentions, }))
    }
    // Search rows use the same ordinary positioned-open path as definition,
    // mention, and Quick Open navigation. An active picker is fulfilled in
    // place; an already-open file is activated.
    FileEditor(@fileeditor.SearchMatchSelected(path~, range~)) =>
      open_editor_at(dispatch, model, path, Some(range))
    // Intercepted like the comment above: which dock tab a tree click opens
    // is the strip's business. The dock opens (or re-activates) the tab,
    // then the file subsystem loads and shows the document against the
    // fresh projection.
    FileEditor(FileSelected(path~, name~)) => {
      let placement = file_ctx(model).placement
      guard placement is Some(value) && value.is_ready() else {
        return (@cmd.none, model)
      }
      let model = model.begin_editor_navigation()
      let had_active = @dock.active_file(model.dock) is Some(_)
      // A pick made from the active FilePicker tab fulfills it: the picker
      // is replaced in place (or the already-open tab activates and the
      // picker closes). Any other tree click opens tabs as before.
      let dock = if model.dock.active is Some(FilePicker) {
        @dock.resolve_pick(model.dock, path)
      } else {
        @dock.open_file(model.dock, path)
      }
      let model = { ..model, dock, }
      let (cmd, panel) = @fileeditor.open_document(
        dispatch.map(msg => FileEditor(msg)),
        model.file_panel,
        file_ctx(model),
        path,
        name~,
        range=None,
        had_active~,
      )
      (cmd, { ..model, file_panel: panel, })
    }
    // A Changes row is the review action: open/activate the same ordinary file
    // tab, then let the file subsystem pair its working-tree document with the
    // row's HEAD path. Deleted rows have no working file but still use the
    // current path as their tab identity.
    FileEditor(ChangedFileSelected(change)) => {
      let placement = file_ctx(model).placement
      guard placement is Some(value) && value.is_ready() else {
        return (@cmd.none, model)
      }
      let model = model.begin_editor_navigation()
      let had_active = @dock.active_file(model.dock) is Some(_)
      let dock = if model.dock.active is Some(FilePicker) {
        @dock.resolve_pick(model.dock, change.path)
      } else {
        @dock.open_file(model.dock, change.path)
      }
      let model = { ..model, dock, }
      let (cmd, panel) = @fileeditor.open_changed_document(
        dispatch.map(msg => FileEditor(msg)),
        model.file_panel,
        file_ctx(model),
        change,
        had_active~,
      )
      (cmd, { ..model, file_panel: panel, })
    }
    // Historical rows open immutable commit/path identities rather than
    // joining the ordinary filesystem tab projection.
    FileEditor(HistoricalFileSelected(diff)) => {
      let placement = file_ctx(model).placement
      guard placement is Some(value) && value.is_ready() else {
        return (@cmd.none, model)
      }
      let model = model.begin_editor_navigation()
      let dock = @dock.open_history_diff(model.dock, diff)
      let model = { ..model, dock, }
      let (cmd, panel) = @fileeditor.open_history_diff(
        dispatch.map(msg => FileEditor(msg)),
        model.file_panel,
        file_ctx(model),
        diff,
      )
      (cmd, { ..model, file_panel: panel, })
    }
    // Intercepted for the same reason: a navigation jump (go-to-definition,
    // a reference pick) opens a dock tab before the document loads. The
    // owner stamp rejects a reply that outlived a conversation switch.
    FileEditor(OpenNavigationLocation(owner~, path~, range~)) => {
      guard model.file_panel.owner == Some(owner) &&
        file_ctx(model).owner == owner else {
        return (@cmd.none, model)
      }
      let placement = file_ctx(model).placement
      guard placement is Some(value) && value.is_ready() else {
        return (@cmd.none, model)
      }
      let model = model.begin_editor_navigation()
      let had_active = @dock.active_file(model.dock) is Some(_)
      let dock = @dock.open_file(model.dock, path)
      let model = { ..model, dock, }
      let (cmd, panel) = @fileeditor.open_file(
        dispatch.map(msg => FileEditor(msg)),
        model.file_panel,
        file_ctx(model),
        path,
        range=Some(range),
        had_active~,
      )
      (cmd, { ..model, file_panel: panel, })
    }
    // Definition/References providers live inside the imperative Viewer, but
    // their host failures belong on the app's ordinary toast rail. Fence the
    // callback by its original conversation and coalesce identical live
    // toasts: one user gesture can cause Viewer to ask more than once.
    FileEditor(@fileeditor.LanguageRequestFailed(owner~, message~)) => {
      guard model.file_panel.owner == Some(owner) &&
        file_ctx(model).owner == owner else {
        return (@cmd.none, model)
      }
      if model.notifications.iter().any(toast => toast.message == message) {
        (@cmd.none, model)
      } else {
        model.notify_error(dispatch, message)
      }
    }
    // Keep watcher lifecycle state in the file-editor package, but present an
    // accepted current-generation failure on the app-owned toast rail. The
    // before/after check uses that package's owner/root/generation fencing and
    // also prevents a repeated host notification from stacking duplicates.
    FileEditor(
      @fileeditor.FileWatchFailed(channel~, root~, generation~, message~)
    ) => {
      let file_message = @fileeditor.FileWatchFailed(
        channel~,
        root~,
        generation~,
        message~,
      )
      let (cmd, panel) = @fileeditor.update(
        dispatch.map(next => FileEditor(next)),
        file_message,
        model.file_panel,
        file_ctx(model),
      )
      let next = { ..model, file_panel: panel, }
      if panel.watch_error == Some(message) &&
        model.file_panel.watch_error != Some(message) &&
        !model.notifications.iter().any(toast => toast.message == message) {
        let (toast, next) = next.notify_error(dispatch, message)
        (@cmd.batch([cmd, toast]), next)
      } else {
        (cmd, next)
      }
    }
    QuickOpenOpen(provider) => open_quick_open(dispatch, model, provider)
    QuickOpen(msg) => update_quick_open(dispatch, model, msg)
    ToggleSelectMenu(menu) => {
      if menu is ProjectMenu && !model.can_choose_new_chat_project() {
        return (@cmd.none, model)
      }
      let select_menu = if model.select_menu == Some(menu) {
        None
      } else {
        Some(menu)
      }
      (
        @cmd.none,
        {
          ..model,
          select_menu,
          project_menu_query: "",
          git_details_open: false,
          codex: model.codex.with_git_details_closed(),
        },
      )
    }
    CloseSelectMenu =>
      (@cmd.none, { ..model, select_menu: None, project_menu_query: "", })
    ProjectMenuQueryChanged(query) =>
      if model.select_menu == Some(ProjectMenu) &&
        model.screen is Chat &&
        model.composing_new_chat() {
        (@cmd.none, { ..model, project_menu_query: query, })
      } else {
        (@cmd.none, model)
      }
    ProjectMenuProjectChosen(workspace) => {
      let menu_open = model.select_menu == Some(ProjectMenu)
      let closed = { ..model, select_menu: None, project_menu_query: "", }
      guard menu_open &&
        model.can_choose_new_chat_project() &&
        @resource.belongs_to(workspace, model.focused) &&
        model.focused_device() is Some(dev) &&
        dev.projects.contains(workspace) &&
        model.active_conversation() is Some(active) else {
        return (@cmd.none, closed)
      }
      // The selected row is still actionable so keyboard and pointer behavior
      // are uniform, but choosing it must not rotate a second empty session.
      if active.project() == workspace {
        (@cmd.none, closed)
      } else {
        update_msg(dispatch, NewChatIn(model.focused, Some(workspace)), closed)
      }
    }
    ModelPicked(value) => {
      guard ModelChoice::parse(value) is Some(choice) else {
        return (@cmd.none, model)
      }
      let model = { ..model, select_menu: None, }
      match choice {
        OpenSeekModel(engine_model) =>
          if model.screen is Codex {
            // Only a composing draft's chip offers the OpenSeek group; the
            // pick hands the fresh conversation back to OpenSeek. The draft
            // is abandoned and a fresh OpenSeek chat rotates into the
            // draft's project (or whatever project is active when the draft
            // never resolved one).
            guard model.codex.composing_draft() else {
              return (@cmd.none, model)
            }
            let root = model.codex.new_thread_cwd()
            let (abandon_cmd, codex) = @codex.update(
              dispatch.map(msg => Codex(channel=model.focused, msg)),
              @codex.Msg::abandon_draft(),
              model.codex,
              model.focused,
              url => open_external_link(dispatch, url),
            )
            let next = {
              ..model,
              codex,
              default_model: engine_model,
              default_agent: OpenSeekAgent,
              loading_conversation: None,
            }
            let next = if !root.is_empty() &&
              @resource.of_path(model.focused, root) is Some(workspace) {
              next.with_active_project(Some(workspace))
            } else {
              next
            }
            (
              @cmd.batch([
                abandon_cmd,
                save_default_model(engine_model),
                save_default_agent(OpenSeekAgent),
                rotate_session(dispatch, next.focused),
              ]),
              next,
            )
          } else {
            // The selector changes the conversation on screen. The tier is
            // pinned to that conversation right away — a chat can be given a
            // tier and left unsent for days — and becomes what the next new
            // chat starts from. (Starting a run pins it too; see `Started`.)
            // A turn already in flight keeps the model it was started with;
            // this takes effect on the next.
            guard model.active_conversation() is Some(conv) else {
              return (@cmd.none, model)
            }
            let next = model
              .replace_conversation({ ..conv, engine_model, })
              .remember_model(conv.device, conv.session_id, engine_model)
            (
              @cmd.batch([
                save_default_model(engine_model),
                save_default_agent(OpenSeekAgent),
                save_conversation_model(
                  conversation_model_key(conv.device, conv.session_id),
                  engine_model,
                ),
              ]),
              {
                ..next,
                default_model: engine_model,
                default_agent: OpenSeekAgent,
              },
            )
          }
        CodexModel(id) => {
          let (model_cmd, codex) = @codex.update(
            dispatch.map(msg => Codex(channel=model.focused, msg)),
            @codex.Msg::model_changed(id),
            model.codex,
            model.focused,
            url => open_external_link(dispatch, url),
          )
          let persist = @cmd.batch([
            model_cmd,
            save_codex_model(id),
            save_default_agent(CodexAgent),
          ])
          if model.screen is Codex {
            // A pick within the Codex group: the next thread start or turn
            // uses it, on the draft and stored-thread surfaces alike.
            (persist, { ..model, codex, default_agent: CodexAgent, })
          } else {
            // Only a composing OpenSeek chat's chip offers the Codex group;
            // the pick hands the fresh conversation to Codex. One composing
            // row at a time: an empty husk that was only ever the "New chat"
            // placeholder is deactivated so its row vanishes with the
            // switch; a husk holding typed writing keeps its row (and the
            // text survives a switch back).
            guard model.composing_new_chat() &&
              model.active_conversation() is Some(conv) else {
              return (@cmd.none, model)
            }
            let cwd = @resource.path_for(conv.project(), model.focused).unwrap_or(
              "",
            )
            let active_session = if conv.worth_keeping() {
              model.active_session
            } else {
              ""
            }
            (
              @cmd.batch([
                persist,
                CodexDraftRotation::{ cwd, }.rotate(dispatch),
              ]),
              {
                ..model,
                codex,
                default_agent: CodexAgent,
                screen: Codex,
                active_session,
                sidebar_open: model.sidebar_open && !model.narrow,
              },
            )
          }
        }
        CodexUnavailablePick =>
          // The Codex group's placeholder row: not a model, a doorway.
          // Sign-in and connection state live in the Settings page's Codex
          // group.
          update_msg(dispatch, OpenSetup, model)
      }
    }
    CodexEffortPicked(value) => {
      let model = { ..model, select_menu: None, }
      let (effort_cmd, codex) = @codex.update(
        dispatch.map(msg => Codex(channel=model.focused, msg)),
        @codex.Msg::effort_changed(value),
        model.codex,
        model.focused,
        url => open_external_link(dispatch, url),
      )
      (
        @cmd.batch([effort_cmd, save_codex_reasoning_effort(value)]),
        { ..model, codex, },
      )
    }
    OpenSeekEffortPicked(value) => {
      guard OpenSeekReasoning::parse(value) is Some(reasoning) else {
        return (@cmd.none, model)
      }
      guard model.active_conversation() is Some(conv) else {
        return (@cmd.none, model)
      }
      if conv.engine_model is (Glm53 | Glm53Flash) {
        (
          reasoning.save_for_glm(),
          { ..model, glm_reasoning: reasoning, select_menu: None, },
        )
      } else {
        (
          reasoning.save(),
          { ..model, openseek_reasoning: reasoning, select_menu: None, },
        )
      }
    }
    MaxStepsChanged(value) => (@cmd.none, { ..model, max_steps: value, })
    SetupApiKeyChanged(value) => {
      guard model.host_settings_loaded() else { return (@cmd.none, model) }
      (@cmd.none, { ..model, setup_api_key: value, })
    }
    ProviderChanged(value) => {
      guard model.host_settings_loaded() else { return (@cmd.none, model) }
      let provider = ApiProvider::parse(value)
      // The update channel no longer derives from the chat provider (only
      // the hosted chat proxy was retired; self-update and the relay stay
      // on the SeekMoon origin), so a provider switch leaves the update
      // answer alone.
      let push = push_host_settings(
        dispatch,
        model.focused,
        provider_settings_patch(provider),
        model.focused_connection_generation(),
      )
      let next = {
        ..model,
        api_provider: provider,
        setup_api_key: "",
        settings_saves: model.settings_saves + 1,
        select_menu: None,
      }.align_fresh_conversation_with_provider()
      // The switch can move the endpoint between usable and not. Inside the
      // setup modal the form simply re-renders for the new provider; a
      // switch that breaks a usable endpoint away from the Settings page
      // opens the modal — it is the announcement now, not a toast.
      (push, next.settle_api_setup())
    }
    FollowupBehaviorChanged(value) => {
      guard model.host_settings_loaded() else { return (@cmd.none, model) }
      let behavior = FollowupBehavior::parse(value)
      (
        push_host_settings(
          dispatch,
          model.focused,
          followup_behavior_patch(behavior),
          model.focused_connection_generation(),
        ),
        {
          ..model,
          followup_behavior: behavior,
          settings_saves: model.settings_saves + 1,
          select_menu: None,
        },
      )
    }
    CustomApiUrlChanged(value) => {
      guard model.host_settings_loaded() else { return (@cmd.none, model) }
      (
        push_host_settings(
          dispatch,
          model.focused,
          custom_url_settings_patch(value),
          model.focused_connection_generation(),
        ),
        {
          ..model,
          custom_api_url: value,
          settings_saves: model.settings_saves + 1,
        },
      )
    }
    NotificationCornerChanged(value) => {
      let corner = NotificationCorner::parse(value)
      (
        save_notification_corner(corner),
        { ..model, notification_corner: corner, select_menu: None, },
      )
    }
    TreeLayoutChanged(value) => {
      let layout = @fileeditor.TreeLayout::parse(value)
      // The dock flips purely in CSS, but the viewer cannot see its host
      // change size on its own — remeasure it (mount_cmds is idempotent and
      // carries the remeasure).
      (
        @cmd.batch([
          save_tree_layout(layout),
          @fileeditor.mount_cmds(dispatch.map(msg => FileEditor(msg))),
        ]),
        { ..model, tree_layout: layout, select_menu: None, },
      )
    }
    NotificationExpired(id) | DismissNotification(id) =>
      (
        @cmd.none,
        { ..model, notifications: model.notifications.filter(t => t.id != id), },
      )
    RemoteStatusLoaded(status) =>
      (@cmd.none, { ..model, remote_access: Some(status), })
    RemoteConnectClicked =>
      // The flow blocks on a browser round-trip; a second click while one
      // is pending would start a second loopback flow just to be refused.
      if model.remote_connecting {
        (@cmd.none, model)
      } else {
        (
          connect_remote(dispatch),
          { ..model, remote_connecting: true, remote_error: None, },
        )
      }
    RemoteConnectFinished(status) =>
      (
        @cmd.none,
        {
          ..model,
          remote_access: Some(status),
          remote_connecting: false,
          remote_error: None,
        },
      )
    RemoteConnectFailed(message) =>
      (
        @cmd.none,
        { ..model, remote_connecting: false, remote_error: Some(message), },
      )
    RemoteCancelClicked =>
      // Fire-and-forget: the connect that is being cancelled reports back
      // through its own reply, which is what clears the pending state.
      (cancel_remote(dispatch), model)
    RemoteDisconnectClicked =>
      (disconnect_remote(dispatch), { ..model, remote_error: None, })
    RemoteDisconnectFailed(message) =>
      (@cmd.none, { ..model, remote_error: Some(message), })
    AppInfoLoaded(version) => (@cmd.none, { ..model, app_version: version, })
    CheckForUpdates =>
      // A user-initiated check; never stacks on an in-flight one, and never
      // interrupts a download already underway.
      if model.update_ux
        is (CheckingForUpdate
        | ConfirmingRestart(..)
        | DownloadingUpdate(..)
        | RestartingForUpdate(..)) {
        (@cmd.none, model)
      } else {
        (
          check_for_updates(dispatch, explicit=true),
          { ..model, update_ux: CheckingForUpdate, },
        )
      }
    UpdateCheckFinished(result~, explicit~) => {
      // A stale reply must not clobber a flow the user has since started
      // (confirming, downloading); only the waiting states accept results.
      guard model.update_ux
        is (UpdateUnknown
        | CheckingForUpdate
        | UpToDate
        | UpdateCheckFailed(..)) else {
        return (@cmd.none, model)
      }
      match result {
        CheckFound(version~, installable~, unavailable_reason~) => {
          let (cmd, next) = if !installable &&
            unavailable_reason is Some(reason) {
            model.notify_error(dispatch, reason)
          } else {
            (@cmd.none, model)
          }
          (cmd, { ..next, update_ux: UpdateAvailable(version~, installable~), })
        }
        CheckUpToDate =>
          (
            @cmd.none,
            {
              ..model
              // Only worth stating when the user asked; a quiet startup
              // check leaves nothing behind.
              ,
              update_ux: if explicit {
                UpToDate
              } else {
                UpdateUnknown
              },
            },
          )
        CheckUnreachable(reason~) =>
          // Offline is routine for the app, an answer for the user.
          if explicit {
            (
              @cmd.none,
              {
                ..model,
                update_ux: UpdateCheckFailed(
                  message="Could not reach the update server: \{reason}",
                ),
              },
            )
          } else {
            (@cmd.none, { ..model, update_ux: UpdateUnknown, })
          }
        CheckMalformed(reason~) =>
          // A garbage manifest also happens under captive portals, so the
          // app asking stays quiet (the host logged it); the user asking
          // gets the truth.
          if explicit {
            (
              @cmd.none,
              {
                ..model,
                update_ux: UpdateCheckFailed(
                  message="The update server answered unusably: \{reason}",
                ),
              },
            )
          } else {
            (@cmd.none, { ..model, update_ux: UpdateUnknown, })
          }
        CheckBroken(version~, reason~) => {
          // A broken package entry can only be the publisher's fault:
          // loud both ways.
          let message = "SeekMoon \{version} is published but its package is unusable: \{reason}"
          let (cmd, next) = if explicit {
            (@cmd.none, model)
          } else {
            model.notify_error(dispatch, message)
          }
          (cmd, { ..next, update_ux: UpdateCheckFailed(message~), })
        }
      }
    }
    UpdateClicked =>
      // Only meaningful while an installable release is on offer; the
      // button does not render otherwise, but a stale click must not
      // restart a download.
      if model.update_ux is UpdateAvailable(version~, installable=true) {
        if model.any_conversation_busy() {
          (@cmd.none, { ..model, update_ux: ConfirmingRestart(version~), })
        } else {
          (
            download_update(dispatch),
            {
              ..model,
              update_ux: DownloadingUpdate(version~, progress={
                downloaded_bytes: 0,
                total_bytes: None,
              }),
            },
          )
        }
      } else {
        (@cmd.none, model)
      }
    ConfirmUpdateRestart =>
      if model.update_ux is ConfirmingRestart(version~) {
        (
          download_update(dispatch),
          {
            ..model,
            update_ux: DownloadingUpdate(version~, progress={
              downloaded_bytes: 0,
              total_bytes: None,
            }),
          },
        )
      } else {
        (@cmd.none, model)
      }
    CancelUpdateRestart =>
      if model.update_ux is ConfirmingRestart(version~) {
        (
          @cmd.none,
          { ..model, update_ux: UpdateAvailable(version~, installable=true), },
        )
      } else {
        (@cmd.none, model)
      }
    UpdateDownloadProgress(downloaded_bytes~, total_bytes~) =>
      if model.update_ux is DownloadingUpdate(version~, ..) {
        (
          @cmd.none,
          {
            ..model,
            update_ux: DownloadingUpdate(version~, progress={
              downloaded_bytes,
              total_bytes,
            }),
          },
        )
      } else {
        // A late event must not revive a completed, failed, or never-started
        // download after the UI has moved to another state.
        (@cmd.none, model)
      }
    UpdateDownloaded =>
      if model.update_ux is DownloadingUpdate(version~, ..) {
        (
          apply_update(dispatch),
          { ..model, update_ux: RestartingForUpdate(version~), },
        )
      } else {
        (@cmd.none, model)
      }
    UpdateFailed(message~) => {
      // A failed download can be retried. A failed swap means the preflight
      // no longer considers this location replaceable, so withdraw the
      // button until a fresh check says otherwise. Both failures say why.
      let (cmd, next) = model.notify_error(dispatch, message)
      let update_ux = match next.update_ux {
        DownloadingUpdate(version~, ..) =>
          UpdateAvailable(version~, installable=true)
        RestartingForUpdate(version~) =>
          UpdateAvailable(version~, installable=false)
        other => other
      }
      (cmd, { ..next, update_ux, })
    }
    UpdateApplied => (close_window(), model)
    OpenSetup =>
      (
        @cmd.none,
        { ..model, screen: Settings, setup_api_key: "", api_setup_open: false, },
      )
    DismissApiSetup =>
      (
        @cmd.none,
        { ..model, api_setup_open: false, api_setup_dismissed: true, },
      )
    OpenApiSetup =>
      // Reopening cancels the dismissal — otherwise the next settled
      // snapshot would close the modal the user just asked for.
      (
        @cmd.none,
        { ..model, api_setup_open: true, api_setup_dismissed: false, },
      )
    OpenCodexConfig => (open_codex_config(dispatch, model.focused), model)
    CodexConfigOpenFailed(message) => model.notify_error(dispatch, message)
    OpenCodex => {
      let (cmd, codex) = @codex.update(
        dispatch.map(msg => Codex(channel=model.focused, msg)),
        @codex.Msg::refresh(),
        model.codex,
        model.focused,
        url => open_external_link(dispatch, url),
      )
      (
        cmd,
        {
          ..model,
          screen: Codex,
          sidebar_open: model.sidebar_open && !model.narrow,
          codex,
        },
      )
    }
    CodexDraftRotated(cwd~, id~) => {
      let (cmd, codex) = @codex.update(
        dispatch.map(msg => Codex(channel=model.focused, msg)),
        @codex.Msg::start_draft(id, cwd),
        model.codex,
        model.focused,
        url => open_external_link(dispatch, url),
      )
      (
        cmd,
        {
          ..model,
          screen: Codex,
          sidebar_open: model.sidebar_open && !model.narrow,
          codex,
        },
      )
    }
    CodexOpenThread(thread_id) => {
      let (cmd, codex) = @codex.update(
        dispatch.map(msg => Codex(channel=model.focused, msg)),
        @codex.Msg::open_thread(thread_id),
        model.codex,
        model.focused,
        url => open_external_link(dispatch, url),
      )
      (
        cmd,
        {
          ..model,
          screen: Codex,
          sidebar_open: model.sidebar_open && !model.narrow,
          codex,
        },
      )
    }
    CodexArchiveThread(thread_id) => {
      let (cmd, codex) = @codex.update(
        dispatch.map(msg => Codex(channel=model.focused, msg)),
        @codex.Msg::archive_thread(thread_id),
        model.codex,
        model.focused,
        url => open_external_link(dispatch, url),
      )
      (cmd, { ..model, codex, })
    }
    CodexUnarchiveThread(thread_id) => {
      let (cmd, codex) = @codex.update(
        dispatch.map(msg => Codex(channel=model.focused, msg)),
        @codex.Msg::unarchive_thread(thread_id),
        model.codex,
        model.focused,
        url => open_external_link(dispatch, url),
      )
      (cmd, { ..model, codex, })
    }
    Codex(channel~, msg) => {
      // A reply, approval request, or status event belongs to the host that
      // produced it. Device focus is the root authority boundary.
      if channel != model.focused {
        return (@cmd.none, model)
      }
      let (cmd, codex) = @codex.update(
        dispatch.map(next => Codex(channel~, next)),
        msg,
        model.codex,
        channel,
        url => open_external_link(dispatch, url),
      )
      (cmd, { ..model, codex, })
    }
    ToggleSidebar =>
      (@cmd.none, { ..model, sidebar_open: !model.sidebar_open, })
    WindowFocusChanged(focused) => {
      // Returning to a visible transcript marks its completed turn read.
      // Permission questions remain actionable until answered and therefore
      // continue to contribute to the independently derived badge count.
      let model = { ..model, window_focused: focused, }
      (@cmd.none, model.mark_visible_conversation_read())
    }
    ViewportResized(width~) => {
      let narrow = width <= NarrowBreakpoint
      // The embedded viewer only learns its host's size through layout(),
      // so any resize while a document is up remeasures it — same-side
      // resizes included (a rotation changes the host without crossing the
      // breakpoint).
      let cmds = if model.right_panel_open &&
        @dock.active_file(model.dock) is Some(_) {
        [@fileeditor.request_viewer_remeasure()]
      } else {
        []
      }
      // A horizontal resize can move the right-anchored browser pane
      // without resizing it (`--editor-width` is fixed pixels after a
      // drag): its ResizeObserver stays silent and the geometry signature
      // never changes, so the resize itself must trigger the re-measure.
      if desired_browser_view(model) is Some(_) {
        cmds.push(measure_browser_pane(dispatch))
      }
      let cmd = @cmd.batch(cmds)
      if narrow == model.narrow {
        (cmd, model)
      } else {
        // Crossing the breakpoint resets the sidebar to the new layout's
        // default: an open column on wide, a closed drawer on narrow.
        (cmd, { ..model, narrow, sidebar_open: !narrow, })
      }
    }
    SaveApiKey => {
      guard model.host_settings_loaded() else { return (@cmd.none, model) }
      let api_key = model.setup_api_key.trim().to_owned()
      if api_key.is_empty() {
        (@cmd.none, model)
      } else {
        match model.api_provider {
          // The key goes straight to the host's store; the mirror keeps
          // only its presence. The save never navigates — it lands on
          // whatever page the form (Settings or the modal over any screen)
          // was open over. A save that completes the setup retires the
          // modal optimistically; one that leaves it incomplete (Custom
          // with no URL yet) keeps the modal up mid-setup. A failed save
          // comes back as a toast.
          Deepseek | Glm | Custom as provider => {
            let next = {
              ..model,
              deepseek_key_saved: model.deepseek_key_saved ||
              provider is Deepseek,
              glm_key_saved: model.glm_key_saved || provider is Glm,
              custom_key_saved: model.custom_key_saved || provider is Custom,
              setup_api_key: "",
              settings_saves: model.settings_saves + 1,
            }
            (
              push_host_settings(
                dispatch,
                model.focused,
                api_key_settings_patch(provider, api_key),
                model.focused_connection_generation(),
              ),
              next.settle_api_setup(),
            )
          }
        }
      }
    }
    OpenSkills => {
      // The page decides whether its catalog still needs fetching; the
      // installed list is the root's mirror, cheap, and refreshed on every
      // open.
      let (page_cmd, skills) = model.skills.opening(
        dispatch.map(msg => Skills(msg)),
        model.skills_input(),
      )
      (
        @cmd.batch([page_cmd, fetch_installed_skills(dispatch, model.focused)]),
        { ..model, screen: Skills, skills, },
      )
    }
    Skills(msg) => {
      let (page_cmd, skills, outcome) = model.skills.handle(
        dispatch.map(next => Skills(next)),
        msg,
        model.skills_input(),
      )
      let model = { ..model, skills, }
      // A settled install or uninstall changed the library the root owns;
      // what the page shows must come from disk, not from a client-side
      // guess.
      guard outcome is Some(@skills.LibraryChanged(channel~)) else {
        return (page_cmd, model)
      }
      (@cmd.batch([page_cmd, fetch_installed_skills(dispatch, channel)]), model)
    }
    Send => {
      guard model.active_conversation() is Some(conv) else {
        return (@cmd.none, model)
      }
      if conv.is_archived_read_only() {
        return (@cmd.none, model)
      }
      let checkout = model.conversation_placement(conv)
      // The outgoing prompt is the typed text with the chips folded in as the
      // `<user_mentions>` envelope. The envelope is itself valid prompt
      // content, so an explicitly attached chip can be sent without text.
      let task = @composer.Draft::{ task: conv.task, mentions: conv.mentions, }
        .prompt()
        .trim()
        .to_owned()
      if !conv.draft_sendable() ||
        !(model.bridge_state() is Connected) ||
        !model.api_ready() ||
        checkout is None ||
        checkout is Some(@interop.MissingWorktree(..)) {
        (@cmd.none, model)
      } else if conv.is_running() {
        // Submitting while this conversation's turn runs steers it: the text
        // is folded into the running turn at its next step boundary and
        // echoed back as a `steer_applied` event. A turn being cancelled
        // cannot be steered — the steer could outlive the dying turn in the
        // engine's queue and contaminate a later prompt — so the text stays
        // in the composer.
        if conv.run is Open(run_id~, stage~) && !(stage is Cancelling) {
          if conv.queue_edit_id is Some(id) {
            return (
              queue_openseek(
                dispatch,
                model.focused,
                conv.session_id,
                @protocol.QueueEdit(id~, text=task),
                run_id,
              ),
              // Keep the edit in the composer until the in-memory mutation is
              // accepted. A refusal then loses no user-authored text.
              model,
            )
          }
          let (model, submission_id) = model.allocate_submission_id()
          let conv = conv.enqueue_steer(
            submission_id,
            Some(run_id),
            task,
            conv.task,
            conv.mentions,
            model.followup_behavior,
          )
          let command = if model.followup_behavior is FollowupQueue {
            queue_openseek(
              dispatch,
              model.focused,
              conv.session_id,
              @protocol.QueueAdd(id=submission_id, text=task),
              run_id,
            )
          } else {
            steer_openseek(
              dispatch,
              model.focused,
              conv.session_id,
              submission_id,
              task,
              run_id,
            )
          }
          (
            command,
            {
              ..model.replace_conversation({
                ..conv,
                task: "",
                mentions: [],
                composer_draft_present: false,
              }),
            },
          )
        } else {
          (@cmd.none, model)
        }
      } else if !(conv.compaction is NotCompacting) {
        // A prompt submitted mid-compaction would sit in the serve engine's
        // queue behind it, where Stop (which cancels only the compaction)
        // cannot reach it — the user's cancel would not stop the submitted
        // work. A queued or just-requested compaction is the same gap one
        // step earlier: the command is on its way and compaction_started has
        // not yet arrived. The draft stays in the composer until the
        // compaction settles.
        (@cmd.none, model)
      } else {
        let (model, submission_id) = model.allocate_submission_id()
        // The worktree launch mode acts until a create has bound the
        // conversation; the eligibility must survive a rejected setup
        // attempt (see `wants_fresh_worktree`). Read before the pending
        // prompt below mutates the conversation.
        let fresh_worktree = conv.wants_fresh_worktree()
        let conv = {
          ..conv,
          pending_prompt: Some({
            submission_id,
            draft: conv.task,
            mentions: conv.mentions.copy(),
          }),
        }
        let next = {
          ..conv,
          task: "",
          mentions: [],
          composer_draft_present: false,
          run: Starting(submission_id~),
          // A turn starts from nothing observed. That includes the terminal
          // floor: the store may have advanced through an external CLI while
          // this page was idle, so only the real Started seam's causal
          // snapshot may establish this run's predecessor terminal.
          turn: RunState::for_run(conv.durable_frontier()),
          // The submit is the moment this run began as far as the user is
          // concerned: the wait they are watching starts here, not at the
          // host's `started`.
          run_started_ms: Some(@interop.now_ms()),
        }
        // The worktree launch mode's first submit creates the environment
        // (the host names it, binds this conversation) and starts inside
        // it, as one command; every other submit is a plain start — a
        // bound session's cwd comes from the host's registry.
        let start_cmd = if fresh_worktree &&
          conv.workspace is Project(root=workspace) {
          start_in_new_worktree(
            dispatch,
            model.focused,
            task,
            submission_id,
            conv.engine_model,
            model.reasoning_for(conv.engine_model),
            model.max_steps,
            conv.session_id,
            workspace,
          )
        } else {
          start_openseek(
            dispatch,
            model.focused,
            task,
            submission_id,
            conv.engine_model,
            model.reasoning_for(conv.engine_model),
            model.max_steps,
            conv.session_id,
            workspace=conv.project(),
          )
        }
        (start_cmd, model.replace_conversation(next))
      }
    }
    Stop => {
      guard model.active_conversation() is Some(conv) else {
        return (@cmd.none, model)
      }
      if conv.run is Open(run_id~, ..) {
        (
          cancel_openseek(dispatch, model.focused, run_id),
          model.replace_conversation({
            ..conv,
            run: Open(run_id~, stage=Cancelling),
          }),
        )
      } else {
        (@cmd.none, model)
      }
    }
    // Answering is refused once already answered, so a double click cannot
    // send two decisions for one question. The card is marked rather than
    // removed: it comes off screen when the engine says the question settled,
    // which is the only evidence the answer arrived.
    ApprovalAnswered(allow~) => {
      guard model.active_conversation() is Some(conv) &&
        conv.pending_approval is Some(pending) &&
        !pending.answered else {
        return (@cmd.none, model)
      }
      (
        approve_openseek(
          dispatch,
          model.focused,
          conv.session_id,
          pending.id,
          pending.run_id,
          allow~,
        ),
        model.replace_conversation({
          ..conv,
          pending_approval: Some({ ..pending, answered: true, }),
        }),
      )
    }
    ApprovalAnswerFailed(channel~, session~, id~) => {
      guard model.find_conversation(channel, session) is Some(conv) &&
        conv.pending_approval is Some(pending) &&
        pending.id == id else {
        return (@cmd.none, model)
      }
      (
        @cmd.none,
        model.replace_conversation({
          ..conv,
          pending_approval: Some({ ..pending, answered: false, }),
        }),
      )
    }
    NewChat =>
      // A fresh conversation can start at any time: the current one keeps
      // running in the background and stays one sidebar click away. It lands
      // in the active workspace — the one the on-screen conversation uses —
      // and starts with whichever agent the model chip was last picked from.
      if model.default_agent is CodexAgent {
        new_codex_chat(
          dispatch,
          model,
          model.focused_device().bind(dev => dev.active_project),
        )
      } else {
        (
          rotate_session(dispatch, model.focused),
          { ..model, loading_conversation: None, },
        )
      }
    NewChatIn(channel, workspace) => {
      // A workspace section's own "new chat": the fresh conversation lands in
      // that project, and the workspace stays active for the next one. The
      // sidebar components reveal the active row themselves, so no disclosure
      // state needs unfolding here. The explicit channel lets this handler
      // move device selection before creating the chat.
      guard model.device_state(channel) is Some(_) else {
        return (@cmd.none, model)
      }
      let (focus_cmd, model) = focus_channel(dispatch, model, channel)
      let model = {
        ..model.with_active_project(workspace),
        loading_conversation: None,
      }
      let (start_cmd, model) = if model.default_agent is CodexAgent {
        new_codex_chat(dispatch, model, workspace)
      } else {
        (rotate_session(dispatch, channel), model)
      }
      (@cmd.batch([focus_cmd, start_cmd]), model)
    }
    ToggleWorktreeMode => {
      // One predicate with the chip that offers this — see
      // `can_choose_launch_mode`. Two spellings of "may still choose" is how
      // the toggle stayed live through a placement chain the chip had
      // already committed to.
      //
      // The chip decides only THIS conversation. The workspace's default for
      // future chats is its own durable setting, edited on the workspace
      // settings page — a per-chat exception must not silently rewrite it.
      guard model.active_conversation() is Some(conv) else {
        return (@cmd.none, model)
      }
      if model.can_choose_launch_mode(conv) && conv.workspace is Project(..) {
        (
          @cmd.none,
          model.replace_conversation({
            ..conv,
            worktree_mode: !conv.worktree_mode,
          }),
        )
      } else {
        (@cmd.none, model)
      }
    }
    RetryWorktreePlacement => {
      guard model.active_conversation() is Some(conv) &&
        model.conversation_placement(conv) is None &&
        model.device_state(conv.device) is Some(dev) else {
        return (@cmd.none, model)
      }
      let workspace = conv.project()
      let request_generation = dev.worktrees_request_generation + 1
      (
        fetch_worktrees(
          dispatch,
          conv.device,
          workspace,
          dev.connection_generation,
          request_generation,
        ),
        model.replace_device({
          ..dev,
          worktrees_request_generation: request_generation,
        }),
      )
    }
    RepairWorktree => {
      guard model.active_conversation() is Some(conv) else {
        return (@cmd.none, model)
      }
      guard model.conversation_placement(conv)
        is Some(@interop.MissingWorktree(..)) &&
        conv.workspace is Worktree(project=workspace, ..) else {
        return (@cmd.none, model)
      }
      (
        repair_worktree_cmd(
          dispatch,
          conv.device,
          workspace.path,
          conv.session_id,
        ),
        model,
      )
    }
    ConfirmArchiveDiscard =>
      match model.archive_confirm {
        Some(confirm) => {
          // The dialog's confirm IS the force: retry the archive discarding
          // the worktree's uncommitted changes. Same generation dance as
          // the plain archive click.
          guard model.device_state(confirm.channel) is Some(dev) else {
            return (@cmd.none, { ..model, archive_confirm: None, })
          }
          let sessions_request_generation = dev.sessions_request_generation + 1
          let archived_request_generation = dev.archived_request_generation + 1
          (
            archive_session(
              dispatch,
              confirm.channel,
              confirm.session,
              dev.connection_generation,
              sessions_request_generation,
              archived_request_generation,
              force=true,
            ),
            {
              ..model.replace_device({
                ..dev,
                sessions_request_generation,
                archived_request_generation,
              }),
              archive_confirm: None,
            },
          )
        }
        None => (@cmd.none, model)
      }
    CancelArchiveDiscard => (@cmd.none, { ..model, archive_confirm: None, })
    ConfirmDeleteArchivedSession =>
      match model.archived_delete_confirm {
        Some(confirm) => {
          guard model.device_state(confirm.channel) is Some(dev) else {
            return (@cmd.none, { ..model, archived_delete_confirm: None, })
          }
          let archived_request_generation = dev.archived_request_generation + 1
          (
            delete_archived_session(
              dispatch,
              confirm.channel,
              confirm.key,
              confirm.sessions,
              dev.connection_generation,
              archived_request_generation,
            ),
            {
              ..model.replace_device({ ..dev, archived_request_generation, }),
              archived_delete_confirm: None,
            },
          )
        }
        None => (@cmd.none, model)
      }
    CancelDeleteArchivedSession =>
      (@cmd.none, { ..model, archived_delete_confirm: None, })
    SessionRotated(owner) => {
      // A delayed rotation is owned by the channel that requested it. A focus
      // switch overtakes it; activating the old owner's id here would yank the
      // user back to the host they already left.
      // A chat happens in a project. A rotation that arrives with none to
      // land in — every project was detached while it was in flight — has
      // nowhere to put the fresh session, and the view stays on onboarding.
      guard owner.channel == model.focused &&
        model.device_state(owner.channel) is Some(dev) &&
        dev.target_project() is Some(project) else {
        return (@cmd.none, model)
      }
      let existing = model.find_conversation(owner.channel, owner.session)
      let activated = model.activate(owner.channel, owner.session, project)
      // A rotation creates the conversation, so stamp it with the workspace
      // it was asked into and that workspace's saved default. An existing
      // conversation keeps its own choice if the reply is replayed.
      let conversations = activated.conversations.map(conv => {
        if conv.device == owner.channel &&
          conv.session_id == owner.session &&
          conv.messages.length() == 0 &&
          !conv.is_running() {
          {
            ..conv,
            workspace: Project(root=project),
            worktree_mode: if existing is Some(existing) {
              existing.worktree_mode
            } else {
              dev.default_worktree_mode(project)
            },
          }
        } else {
          conv
        }
      })
      (
        @cmd.none,
        {
          ..activated,
          conversations,
          screen: Chat,
          loading_conversation: None,
        },
      )
    }
    PickProject(channel) => {
      // Focus moves for the surrounding UI, while the picker itself keeps
      // `channel` as its owner through every later navigation and confirm.
      guard model.device_state(channel) is Some(_) else {
        return (@cmd.none, model)
      }
      let (focus_cmd, model) = focus_channel(dispatch, model, channel)
      // Retire Quick Open first. The picker's capture-phase keys claim Enter
      // and Escape for the browse session, so a palette left standing would
      // paint over the picker while every keystroke went to the picker behind
      // it. The palette holds nothing worth preserving — unlike the picker's
      // own browse position, which is why it refuses to reopen over itself.
      let (quick_open_cmd, quick_open) = model.quick_open.close()
      let (browse_cmd, picker) = @project_picker.State::open(
        channel,
        dispatch.map(msg => ProjectPicker(msg)),
      )
      (
        @cmd.batch([focus_cmd, quick_open_cmd, browse_cmd]),
        { ..model, quick_open, project_picker: Some(picker), },
      )
    }
    AddProjectRequested =>
      // The chord acts on the focused device, like the sidebar section's ＋.
      // While the picker is already open it does nothing: restarting the
      // browse would yank the listing back to home mid-navigation.
      if model.project_picker is Some(_) {
        (@cmd.none, model)
      } else {
        update(dispatch, PickProject(model.focused), model)
      }
    ProjectPicker(msg) =>
      match model.project_picker {
        Some(picker) => {
          let (cmd, next, outcome) = @project_picker.State::handle(
            picker,
            dispatch.map(msg => ProjectPicker(msg)),
            msg,
          )
          let model = { ..model, project_picker: next, }
          match outcome {
            None => (cmd, model)
            // A failed browse or create leaves the previous listing usable.
            Some(@project_picker.Outcome::Failed(message)) => {
              let (toast, model) = model.notify_error(dispatch, message)
              (@cmd.batch([cmd, toast]), model)
            }
            // Confirm registers the directory the host last listed — always
            // something it confirmed exists — never raw pasted text; a paste
            // navigates (and validates) first. The pending adoption later
            // focuses the project the add committed.
            Some(@project_picker.Outcome::Picked(channel, path)) => {
              guard @resource.of_path(channel, path) is Some(picked) else {
                let (toast, model) = model.notify_error(
                  dispatch, "The selected folder returned an invalid path.",
                )
                return (@cmd.batch([cmd, toast]), model)
              }
              let known = match model.device_state(channel) {
                Some(dev) => dev.projects.copy()
                None => []
              }
              (
                @cmd.batch([cmd, add_project(dispatch, channel, path)]),
                {
                  ..model,
                  pending_project_adoption: Some({
                    channel,
                    requested: path,
                    picked,
                    known,
                    resolved: None,
                  }),
                },
              )
            }
          }
        }
        None => (@cmd.none, model)
      }
    RemoveProject(channel, path) =>
      // The row itself leaves with the registry commit broadcast; its open
      // "…" menu is component state and leaves with the keyed row.
      if @resource.belongs_to(path, channel) {
        (remove_project(dispatch, channel, path.path), model)
      } else {
        (@cmd.none, model)
      }
    OpenWorkspaceSettings(channel, workspace) =>
      (@cmd.none, { ..model, screen: WorkspaceSettings(channel~, workspace~), })
    WorkspaceDefaultModeChosen(channel, workspace, value) => {
      guard model.device_state(channel) is Some(dev) else {
        return (@cmd.none, model)
      }
      let worktree_mode = value == "worktree"
      // Apply optimistically under a fresh token, so a slower list reply
      // cannot roll the page's select back; the commit broadcast lands on a
      // newer token still. The failure path re-reads the disk state.
      let request_generation = dev.workspace_settings_request_generation + 1
      (
        save_workspace_settings(dispatch, channel, workspace, worktree_mode~),
        model.replace_device({
          ..dev.with_workspace_settings(
            workspace,
            worktree_mode,
            generation=request_generation,
          ),
          workspace_settings_request_generation: request_generation,
        }),
      )
    }
    WorkspaceSubmodulesChosen(channel, workspace, value) => {
      guard model.device_state(channel) is Some(dev) &&
        dev.workspace_settings_row(workspace) is Some(row) else {
        return (@cmd.none, model)
      }
      let checkout_submodules = match value {
        "checkout" => true
        "skip" => false
        _ => return (@cmd.none, model)
      }
      // Preserve the workspace's launch mode locally and patch only the
      // submodule field on disk. The generation fence has the same job as
      // the launch-mode edit above: an older read cannot undo this choice.
      let request_generation = dev.workspace_settings_request_generation + 1
      (
        save_workspace_settings(
          dispatch,
          channel,
          workspace,
          checkout_submodules~,
        ),
        model.replace_device({
          ..dev.with_workspace_settings(
            workspace,
            row.worktree_mode,
            generation=request_generation,
            checkout_submodules~,
          ),
          workspace_settings_request_generation: request_generation,
        }),
      )
    }
    WorkspaceSubmoduleTimeoutChosen(channel, workspace, value) => {
      guard model.device_state(channel) is Some(dev) &&
        dev.workspace_settings_row(workspace) is Some(row) else {
        return (@cmd.none, model)
      }
      let submodule_checkout_timeout_seconds = match value {
        "5" => 5
        "10" => 10
        "30" => 30
        "60" => 60
        _ => return (@cmd.none, model)
      }
      // Patch only the timeout and keep both neighboring workspace choices.
      // A fresh generation prevents an older read from undoing this select.
      let request_generation = dev.workspace_settings_request_generation + 1
      (
        save_workspace_settings(
          dispatch,
          channel,
          workspace,
          submodule_checkout_timeout_seconds~,
        ),
        model.replace_device({
          ..dev.with_workspace_settings(
            workspace,
            row.worktree_mode,
            generation=request_generation,
            checkout_submodules=row.checkout_submodules,
            submodule_checkout_timeout_seconds~,
          ),
          workspace_settings_request_generation: request_generation,
        }),
      )
    }
    ArchiveSession(channel, session_id) => {
      // Archiving acts on the row's own device and never moves focus.
      guard model.device_state(channel) is Some(dev) else {
        return (@cmd.none, model)
      }
      let sessions_request_generation = dev.sessions_request_generation + 1
      let archived_request_generation = dev.archived_request_generation + 1
      (
        archive_session(
          dispatch,
          channel,
          session_id,
          dev.connection_generation,
          sessions_request_generation,
          archived_request_generation,
        ),
        model.replace_device({
          ..dev,
          sessions_request_generation,
          archived_request_generation,
        }),
      )
    }
    UnarchiveSession(channel, session_id) => {
      guard model.device_state(channel) is Some(dev) else {
        return (@cmd.none, model)
      }
      let sessions_request_generation = dev.sessions_request_generation + 1
      let archived_request_generation = dev.archived_request_generation + 1
      (
        unarchive_session(
          dispatch,
          channel,
          session_id,
          dev.connection_generation,
          sessions_request_generation,
          archived_request_generation,
        ),
        model.replace_device({
          ..dev,
          sessions_request_generation,
          archived_request_generation,
        }),
      )
    }
    DeleteArchivedSession(channel, key) => {
      // Only a currently visible archived row may open the destructive dialog;
      // stale clicks cannot authorize deletion of an identity no longer shown.
      guard model.device_state(channel) is Some(dev) &&
        key.workspace_payload(channel) is Some(_) &&
        dev.archived.iter().find_first(item => key.matches(item))
        is Some(record) else {
        return (@cmd.none, model)
      }
      let sessions : Array[String] = [key.session]
      for row in @transcript.session_tree(dev.archived) {
        if key.matches(row.item) {
          for child in row.children {
            sessions.push(child.id)
          }
        }
      }
      (
        @cmd.none,
        {
          ..model,
          archived_delete_confirm: Some({
            channel,
            key,
            sessions,
            title: session_item_label(record),
          }),
        },
      )
    }
    ConversationRenameRequested(id~, label~) =>
      if id.source() is (@conversation.OpenSeekLive | @conversation.CodexLive) {
        (
          focus_conversation_rename(),
          {
            ..model,
            conversation_rename: Some({
              id,
              draft: label,
              saving: false,
              error: None,
            }),
          },
        )
      } else {
        (@cmd.none, model)
      }
    ConversationRenameChanged(id~, value~) =>
      match model.conversation_rename {
        Some(rename) if rename.id == id && !rename.saving =>
          (
            @cmd.none,
            {
              ..model,
              conversation_rename: Some({ ..rename, draft: value, error: None, }),
            },
          )
        _ => (@cmd.none, model)
      }
    ConversationRenameSubmitted(id) =>
      match model.conversation_rename {
        Some(rename) if rename.id == id &&
          !rename.saving &&
          !rename.draft.trim().is_empty() => {
          let saving = { ..rename, saving: true, error: None, }
          (
            rename_conversation(dispatch, saving),
            { ..model, conversation_rename: Some(saving), },
          )
        }
        _ => (@cmd.none, model)
      }
    ConversationRenameCancelled(id) =>
      match model.conversation_rename {
        Some(rename) if rename.id == id && !rename.saving =>
          (@cmd.none, { ..model, conversation_rename: None, })
        _ => (@cmd.none, model)
      }
    ConversationRenameSucceeded(id) =>
      match model.conversation_rename {
        Some(rename) if rename.id == id =>
          (@cmd.none, { ..model, conversation_rename: None, })
        _ => (@cmd.none, model)
      }
    ConversationRenameFailed(id~, message~) =>
      match model.conversation_rename {
        Some(rename) if rename.id == id =>
          (
            @cmd.none,
            {
              ..model,
              conversation_rename: Some({
                ..rename,
                saving: false,
                error: Some("Rename failed: " + message),
              }),
            },
          )
        _ => (@cmd.none, model)
      }
    NotificationClicked(run_id~) => {
      // Proton notifications are emitted only for the embedded local host. A
      // finished run usually matches by last run id; a permission request
      // still owns the active run while its tool waits for the answer.
      let conv = if model.conversation_by_last_run(Local, run_id) is Some(conv) {
        Some(conv)
      } else {
        model.conversation_by_run(Local, run_id)
      }
      if conv is Some(conv) {
        update_msg(dispatch, OpenSession(conv.device, conv.session_id), model)
      } else {
        (@cmd.none, model)
      }
    }
    // A transcript link naming a session on the device already focused. It
    // delegates rather than duplicating: the sub-run child this opens is an
    // ordinary durable session, and `OpenSession` is how one is opened.
    OpenSessionHere(session_id) =>
      update_msg(dispatch, OpenSession(model.focused, session_id), model)
    OpenSession(channel, session_id) =>
      // Selecting a conversation always returns to the chat — including
      // re-selecting the active one from the Skills page. The explicit channel
      // may also move device selection before the focused-scoped mirrors
      // refetch and the conversation opens there; current sidebar rows pass
      // the selected channel.
      if session_id.is_empty() {
        (@cmd.none, model)
      } else {
        // A row click that raced its device's removal has nowhere to go.
        guard model.device_state(channel) is Some(_) else {
          return (@cmd.none, model)
        }
        let (focus_cmd, model) = focus_channel(dispatch, model, channel)
        guard model.live_selection(channel, session_id) is Some(target) else {
          return (@cmd.none, model)
        }
        let model = {
          ..model.cancel_unsubmitted_conversation_rename(),
          selected_conversation: Some(target),
          conversation_load_failure: None,
          screen: Chat,
        }
        let (cmd, model) = open_session_on(dispatch, channel, model, session_id)
        (@cmd.batch([focus_cmd, cmd]), model)
      }
    RetrySelectedConversation =>
      match model.selected_conversation {
        Some(selection) if selection.record is LiveRecord =>
          update_msg(
            dispatch,
            OpenSession(selection.channel, selection.session),
            { ..model, conversation_load_failure: None, },
          )
        Some(selection) if selection.record is ArchivedRecord =>
          update_msg(
            dispatch,
            OpenArchivedSession(
              selection.channel,
              session=selection.session,
              workspace=selection.workspace,
            ),
            { ..model, conversation_load_failure: None, },
          )
        _ => (@cmd.none, model)
      }
    OpenArchivedSession(channel, session~, workspace~) => {
      guard !session.is_empty() && model.device_state(channel) is Some(dev) else {
        return (@cmd.none, model)
      }
      // The row may have been restored while its click was queued. Re-read
      // the current archived index and use its placement rather than opening
      // a stale archived target or trusting an obsolete workspace hint.
      let key : ArchiveRecordKey = { session, workspace, }
      guard dev.archived.iter().any(item => key.matches(item)) &&
        !(dev.archive_override(key) is Some(ArchiveLive)) else {
        return (@cmd.none, model)
      }
      let (focus_cmd, model) = focus_channel(dispatch, model, channel)
      let model = {
        ..model.cancel_unsubmitted_conversation_rename(),
        selected_conversation: Some({
          channel,
          session,
          workspace,
          record: ArchivedRecord,
        }),
        conversation_load_failure: None,
        screen: Chat,
      }
      let (cmd, model) = model.open_archived_session_on(
        dispatch, channel, session, workspace,
      )
      (@cmd.batch([focus_cmd, cmd]), model)
    }
    ColorSchemeChanged(dark) => {
      let model = { ..model, system_dark: dark, }
      match model.theme {
        System =>
          (
            @cmd.batch([
              System.apply(dark, model.is_desktop, dispatch),
              browser_set_theme_for_pages(dispatch, model, dark),
            ]),
            model,
          )
        Light | Dark => (@cmd.none, model)
      }
    }
    FpsOverlayChanged(enabled) =>
      (save_fps_overlay(enabled), { ..model, fps_overlay_enabled: enabled, })
    ThemeChanged(value) => {
      let theme = Theme::parse(value, model.theme)
      let model = { ..model, select_menu: None, }
      if theme == model.theme {
        (@cmd.none, model)
      } else {
        (
          @cmd.batch([
            theme.apply(model.system_dark, model.is_desktop, dispatch),
            browser_set_theme_for_pages(
              dispatch,
              model,
              theme.is_dark(model.system_dark),
            ),
            theme.save(),
          ]),
          { ..model, theme, },
        )
      }
    }
    FontChanged(value) => {
      let app_font = AppFont::parse(value, model.app_font)
      let model = { ..model, select_menu: None, }
      if app_font == model.app_font {
        (@cmd.none, model)
      } else {
        (
          @cmd.batch([app_font.apply(), app_font.save()]),
          { ..model, app_font, },
        )
      }
    }
    FontSizeChanged(value) => {
      let app_font_size = AppFontSize::parse(value, model.app_font_size)
      let model = { ..model, select_menu: None, }
      if app_font_size == model.app_font_size {
        (@cmd.none, model)
      } else {
        (
          @cmd.batch([app_font_size.apply(), app_font_size.save()]),
          { ..model, app_font_size, },
        )
      }
    }
    OpenFile(path) => {
      // A relative path is taken against the active conversation's projected
      // checkout root. The host keeps text editor targets inside that root;
      // non-text paths may still use the system opener.
      guard model.active_checkout() is Some(active) &&
        active.placement is Some(placement) &&
        placement.checkout_root() is Some(cwd) else {
        return (@cmd.none, model)
      }
      // Spend the token before starting host work. This synchronously makes
      // every older host reply and positioned read stale, even if this click
      // ultimately opens a non-text path through the system instead.
      let generation = model.file_panel.file_link_generation + 1
      let model = {
        ..model,
        file_panel: { ..model.file_panel, file_link_generation: generation, },
      }
      (
        open_file(
          dispatch,
          active.owner.channel,
          active.owner.session,
          generation,
          cwd=Some(cwd),
          path,
        ),
        model,
      )
    }
    RevealFile(path) => {
      guard model.is_desktop &&
        model.active_checkout() is Some(active) &&
        active.owner.channel is Local &&
        active.placement is Some(placement) &&
        placement.checkout_root() is Some(cwd) else {
        return (@cmd.none, model)
      }
      (
        reveal_file(
          dispatch,
          active.owner.channel,
          active.owner.session,
          cwd,
          path,
        ),
        model,
      )
    }
    OpenFileAt(owner~, generation~, path~, line~, column~) => {
      guard model.active_checkout() is Some(active) &&
        owner == active.owner &&
        generation == model.file_panel.file_link_generation else {
        return (@cmd.none, model)
      }
      let range = match line {
        Some(line) => {
          let column = column.unwrap_or(1)
          Some(@common.Range(line, column, line, column))
        }
        None => None
      }
      open_editor_at(
        dispatch,
        model,
        path,
        range,
        file_link_generation=generation,
      )
    }
    OpenDirectoryAt(owner~, generation~, path~) => {
      guard model.active_checkout() is Some(active) &&
        owner == active.owner &&
        generation == model.file_panel.file_link_generation else {
        return (@cmd.none, model)
      }
      reveal_local_directory(dispatch, model, Relative(path))
    }
    ToggleGitDetails => {
      let opening = !model.git_details_open
      let model = { ..model, git_details_open: opening, }
      guard opening else { return (@cmd.none, model) }
      // Opening it is a request for current information, and everything it
      // shows goes stale on its own: CI finishes minutes after the run that
      // started it, and the working tree keeps moving. Nothing else looks
      // again until the next run, so without this the chip's tint can sit on
      // "running" long after the checks settled.
      //
      // The branch probe is the refresh — it re-counts the lines and, through
      // its reply, re-runs the pull-request lookup, which is the same path
      // every run boundary takes, in-flight fencing and all.
      guard model.active_conversation() is Some(conv) else {
        return (@cmd.none, model)
      }
      probe_branch(
        dispatch,
        model,
        conv.device,
        conv.session_id,
        model.conversation_root(conv),
      )
    }
    CloseGitDetails => (@cmd.none, { ..model, git_details_open: false, })
    ToggleRightPanel => {
      let opening = !model.right_panel_open
      // A direct visibility toggle has no later semantic action to fence old
      // editor replies. Actions such as OpenFile and JumpToLocation spend
      // their own navigation generation before opening the panel.
      let model = if !opening || model.dock.active is Some(_) {
        model.begin_editor_navigation()
      } else {
        model
      }
      let model = {
        ..model,
        right_panel_open: opening,
        right_panel_menu_open: false,
        right_panel_expanded: if opening {
          model.right_panel_expanded
        } else {
          false
        },
      }
      (@cmd.none, model)
    }
    ToggleRightPanelMenu =>
      (
        @cmd.none,
        { ..model, right_panel_menu_open: !model.right_panel_menu_open, },
      )
    ToggleRightPanelExpanded => {
      guard model.right_panel_open else { return (@cmd.none, model) }
      let model = {
        ..model,
        right_panel_menu_open: false,
        right_panel_expanded: !model.right_panel_expanded,
      }
      let cmd = if @dock.active_file(model.dock) is Some(_) {
        @fileeditor.request_viewer_remeasure()
      } else {
        @cmd.none
      }
      (cmd, model)
    }
    CloseRightPanelMenu =>
      (@cmd.none, { ..model, right_panel_menu_open: false, })
    CloseAllTabs => close_all_tabs(dispatch, model)
    OpenGoalEditor => {
      guard model.active_conversation() is Some(conv) else {
        return (@cmd.none, model)
      }
      if conv.is_archived_read_only() {
        return (@cmd.none, model)
      }
      // Opening goal mode touches only this conversation, so an unsaved edit
      // waiting on another one is untouched — the reason the draft lives here
      // rather than in a single model-wide slot.
      //
      // A menu left open over the prompt does not survive the switch: it was
      // computed from the prompt draft, and a goal draft has no slash
      // commands to offer. Accepting one of its stale rows would replace the
      // goal being written, or run something else entirely.
      (
        @cmd.none,
        {
          ..model.replace_conversation({
            ..conv,
            goal_edit: Some({ draft: conv.goal_draft_seed(), }),
          }),
        },
      )
    }
    GoalDraftEdited(draft) => {
      guard model.active_conversation() is Some(conv) else {
        return (@cmd.none, model)
      }
      if conv.is_archived_read_only() {
        return (@cmd.none, model)
      }
      if conv.goal_edit is Some(_) {
        (
          @cmd.none,
          model.replace_conversation({ ..conv, goal_edit: Some({ draft, }), }),
        )
      } else {
        (@cmd.none, model)
      }
    }
    SubmitGoal => {
      guard model.active_conversation() is Some(conv) else {
        return (@cmd.none, model)
      }
      if conv.is_archived_read_only() {
        return (@cmd.none, model)
      }
      guard conv.goal_edit is Some(edit) else { return (@cmd.none, model) }
      let text = edit.draft.trim().to_owned()
      // A blank draft has nothing to set (the button is disabled; this also
      // catches Enter); goal mode stays open for the user to finish.
      guard !text.is_empty() else { return (@cmd.none, model) }
      // Goal mode closes, but the text stays as `goal_pending` until the
      // durable marker lands. `agent.goal` returning only means the command
      // reached the engine's stdin — the append behind it can still fail, and
      // then nothing would carry the user's writing.
      let (model, command) = model.allocate_submission_id()
      (
        send_goal(dispatch, model, conv, command, Some(text)),
        model.replace_conversation({
          ..conv,
          goal_edit: None,
          goal_pending: Some({
            id: command,
            request: Setting(text),
            since: conv.durable_frontier(),
          }),
        }),
      )
    }
    ClearGoal => {
      // Always send it, mirrored or not: the row lags the engine by one
      // durable commit, so a clear racing an in-flight set must not be
      // dropped on the mirror's say-so. A tombstone on a goalless session is
      // a harmless no-op the engine still confirms.
      //
      // The ✕ belongs to the conversation on screen, and so does the edit it
      // closes — neither can reach a neighbour's.
      guard model.active_conversation() is Some(conv) else {
        return (@cmd.none, model)
      }
      if conv.is_archived_read_only() {
        return (@cmd.none, model)
      }
      let (model, command) = model.allocate_submission_id()
      (
        send_goal(dispatch, model, conv, command, None),
        model.replace_conversation({
          ..conv,
          goal_edit: None,
          // Supersedes a set still awaiting its marker.
          goal_pending: Some({
            id: command,
            request: Clearing,
            since: conv.durable_frontier(),
          }),
        }),
      )
    }
    CloseGoalEditor => {
      guard model.active_conversation() is Some(conv) else {
        return (@cmd.none, model)
      }
      (@cmd.none, model.replace_conversation({ ..conv, goal_edit: None, }))
    }
    FileEditor(msg) => {
      let (cmd, panel) = @fileeditor.update(
        dispatch.map(msg => FileEditor(msg)),
        msg,
        model.file_panel,
        file_ctx(model),
      )
      let next = { ..model, file_panel: panel, }
      (cmd, next)
    }
    Dock(msg) => {
      // The strip machine is pure; the cross-package effects of the
      // transition — showing or dropping documents, mounting hosts — are
      // commanded here off the before/after difference.
      let before = model.dock
      let dock = @dock.update(msg, before)
      // Only a real non-empty -> empty strip transition closes the panel.
      // An already-empty panel is the launcher surface, so a stale close must
      // leave it open. Reset the other visibility bits just like the explicit
      // panel toggle does, keeping the root-owned panel state consistent.
      let model = if !before.tabs.is_empty() && dock.tabs.is_empty() {
        {
          ..model,
          dock,
          right_panel_open: false,
          right_panel_menu_open: false,
          right_panel_expanded: false,
        }
      } else {
        { ..model, dock, }
      }
      let femit = dispatch.map(msg => FileEditor(msg))
      match msg {
        TabActivated(_) =>
          if dock.active != before.active {
            // A tab selection is newer than any transcript link still waiting
            // on its host lookup, even when the selected tab is not a file.
            let model = model.begin_editor_navigation()
            if @dock.active_file(dock) is Some(path) {
              let cmds : Array[@cmd.Cmd] = []
              if @dock.active_file(before) is None {
                // The file body was CSS-hidden behind the browser pane or
                // the picker overlay; the viewer must re-measure its host on
                // return.
                cmds.push(@fileeditor.request_viewer_remeasure())
              }
              let (cmd, panel) = @fileeditor.activate(
                femit,
                model.file_panel,
                file_ctx(model),
                path,
              )
              cmds.push(cmd)
              (@cmd.batch(cmds), { ..model, file_panel: panel, })
            } else if @dock.active_history_diff(dock) is Some(diff) {
              let cmds : Array[@cmd.Cmd] = []
              if @dock.active_history_diff(before) is None {
                cmds.push(@fileeditor.request_viewer_remeasure())
              }
              let (cmd, panel) = @fileeditor.activate_history_diff(
                femit,
                model.file_panel,
                file_ctx(model),
                diff,
              )
              cmds.push(cmd)
              (@cmd.batch(cmds), { ..model, file_panel: panel, })
            } else {
              (@cmd.none, model)
            }
          } else {
            (@cmd.none, model)
          }
        TabClosed(tab) =>
          // A stale close (racing another close) leaves the strip — and so
          // the document table — untouched.
          if before.tabs.search_by(entry => entry == tab) is Some(_) {
            // When the closed tab was on screen and a file tab inherits it,
            // its document must be shown; a file close routes through
            // close_document (which also drops the document), the other
            // kinds activate directly.
            let next_file = @dock.active_file(dock)
            let next_history = @dock.active_history_diff(dock)
            let was_active = before.active == Some(tab)
            // Closing any file tab is newer than a pending transcript link:
            // even an inactive tab must stay closed when that link's delayed
            // host lookup returns. Other tab kinds compete only when closing
            // them changes the active destination.
            let closes_file = match tab {
              File(_) | GitDiff(_) => true
              _ => false
            }
            let model = if closes_file ||
              (was_active && dock.active != before.active) {
              model.begin_editor_navigation()
            } else {
              model
            }
            match tab {
              File(path~) => {
                let (cmd, panel) = @fileeditor.close_document(
                  femit,
                  model.file_panel,
                  file_ctx(model),
                  path,
                  next=next_file,
                  was_active~,
                )
                if was_active && next_history is Some(diff) {
                  let (history_cmd, panel) = @fileeditor.activate_history_diff(
                    femit,
                    panel,
                    file_ctx(model),
                    diff,
                  )
                  (
                    @cmd.batch([cmd, history_cmd]),
                    { ..model, file_panel: panel, },
                  )
                } else {
                  (cmd, { ..model, file_panel: panel, })
                }
              }
              GitDiff(diff~) => {
                let panel = @fileeditor.close_history_diff(
                  model.file_panel,
                  diff,
                )
                if was_active && next_file is Some(path) {
                  let (cmd, panel) = @fileeditor.activate(
                    femit,
                    panel,
                    file_ctx(model),
                    path,
                  )
                  (cmd, { ..model, file_panel: panel, })
                } else if was_active && next_history is Some(next) {
                  let (cmd, panel) = @fileeditor.activate_history_diff(
                    femit,
                    panel,
                    file_ctx(model),
                    next,
                  )
                  (cmd, { ..model, file_panel: panel, })
                } else {
                  (@cmd.none, { ..model, file_panel: panel, })
                }
              }
              Browser(id~) => {
                let cmds : Array[@cmd.Cmd] = [browser_close_view(dispatch, id)]
                // Closing owns the native view's teardown. Retire its cached
                // placement at the same transition so the outer browser sync
                // does not enqueue a hide behind the close; the ordered bridge
                // lane would then try to hide a view the host already removed.
                // Clearing `geo` also makes a successor Browser tab re-measure.
                let browser_pane = if model.browser_pane.shown == Some(id) {
                  { shown: None, rect: None, geo: None, }
                } else {
                  model.browser_pane
                }
                let model = {
                  ..model,
                  preview: @preview.close_page(model.preview, id),
                  browser_pane,
                }
                if was_active && next_file is Some(path) {
                  cmds.push(@fileeditor.request_viewer_remeasure())
                  let (cmd, panel) = @fileeditor.activate(
                    femit,
                    model.file_panel,
                    file_ctx(model),
                    path,
                  )
                  cmds.push(cmd)
                  (@cmd.batch(cmds), { ..model, file_panel: panel, })
                } else if was_active && next_history is Some(diff) {
                  cmds.push(@fileeditor.request_viewer_remeasure())
                  let (cmd, panel) = @fileeditor.activate_history_diff(
                    femit,
                    model.file_panel,
                    file_ctx(model),
                    diff,
                  )
                  cmds.push(cmd)
                  (@cmd.batch(cmds), { ..model, file_panel: panel, })
                } else {
                  (@cmd.batch(cmds), model)
                }
              }
              // Neither tab owns a document: closing one while active hands
              // focus to a neighbouring file or diff, and otherwise nothing.
              FilePicker | Workflows =>
                if was_active && next_file is Some(path) {
                  let (cmd, panel) = @fileeditor.activate(
                    femit,
                    model.file_panel,
                    file_ctx(model),
                    path,
                  )
                  (cmd, { ..model, file_panel: panel, })
                } else if was_active && next_history is Some(diff) {
                  let (cmd, panel) = @fileeditor.activate_history_diff(
                    femit,
                    model.file_panel,
                    file_ctx(model),
                    diff,
                  )
                  (cmd, { ..model, file_panel: panel, })
                } else {
                  (@cmd.none, model)
                }
            }
          } else {
            (@cmd.none, model)
          }
      }
    }
    Preview(msg) => {
      // A navigation replaces the page realm, so reapply the app theme both
      // at commit time and after loading settles. The first call minimizes a
      // mismatched flash; the second covers engines whose document element
      // did not exist at the earlier event.
      let theme_cmd = match msg {
        @preview.Msg::Navigated(id~, ..) =>
          browser_set_theme(
            dispatch,
            id,
            model.theme.is_dark(model.system_dark),
          )
        @preview.Msg::LoadingChanged(id~, loading~) =>
          if loading {
            @cmd.none
          } else {
            browser_set_theme(
              dispatch,
              id,
              model.theme.is_dark(model.system_dark),
            )
          }
        _ => @cmd.none
      }
      (theme_cmd, { ..model, preview: @preview.update(msg, model.preview), })
    }
    BrowserTabRequested => {
      let model = model.begin_editor_navigation()
      let (preview, id) = @preview.open_page(model.preview)
      let dock = @dock.open_browser(model.dock, id)
      (
        focus_browser_address(),
        { ..model, preview, dock, right_panel_menu_open: false, },
      )
    }
    ExplorerRequested(mode) => open_explorer(dispatch, model, mode)
    // The Workflows tab: opened like the explorer inventories, keeping the
    // right panel on screen with its launcher menu closed.
    WorkflowsRequested =>
      (
        @cmd.none,
        {
          ..model,
          dock: @dock.open_workflows(model.dock),
          right_panel_open: true,
          right_panel_menu_open: false,
        },
      )
    BrowserAddressEdited(value) =>
      match @dock.active_browser(model.dock) {
        Some(id) =>
          (
            @cmd.none,
            {
              ..model,
              preview: @preview.update(
                @preview.Msg::InputChanged(id~, value~),
                model.preview,
              ),
            },
          )
        None => (@cmd.none, model)
      }
    BrowserNavigateSubmitted => {
      guard @dock.active_browser(model.dock) is Some(id) &&
        @preview.page(model.preview, id) is Some(page) &&
        @preview.normalize_url(page.input) is Some(url) else {
        return (@cmd.none, model)
      }
      // A committed browser navigation is newer than any pending transcript
      // file link. Spend the token only after validation so an invalid address
      // draft remains a pure no-op.
      let model = model.begin_editor_navigation()
      // A blank tab's first navigation creates the native view; later ones
      // navigate the existing view.
      let (cmd, pane) = if page.url is Some(_) {
        // `browser.navigate` builds the view back when it is gone — a create
        // the host refused, or one a reload's `close_all` swept — and a
        // rebuilt view arrives hidden at a placeholder size. No view op is
        // acknowledged, so the cached placement may describe a view that
        // never existed; forgetting it has the next sync measure and place
        // whatever the host actually has now.
        (
          browser_navigate(
            dispatch,
            id,
            url,
            model.theme.is_dark(model.system_dark),
          ),
          { shown: None, rect: None, geo: None, },
        )
      } else {
        // The blank tab's own placement is already absent (a page without a
        // URL is never the desired view), so the create needs no reset.
        (
          browser_open(
            dispatch,
            id,
            url,
            model.theme.is_dark(model.system_dark),
          ),
          model.browser_pane,
        )
      }
      (
        cmd,
        {
          ..model,
          preview: @preview.navigate(model.preview, id, url),
          browser_pane: pane,
        },
      )
    }
    BrowserBack =>
      (
        browser_history_for_active(dispatch, model, @commands.browser_back),
        model,
      )
    BrowserForward =>
      (
        browser_history_for_active(dispatch, model, @commands.browser_forward),
        model,
      )
    BrowserReload =>
      (
        browser_history_for_active(dispatch, model, @commands.browser_reload),
        model,
      )
    BrowserOpenExternal => {
      guard @dock.active_browser(model.dock) is Some(id) &&
        @preview.page(model.preview, id) is Some(page) &&
        page.url is Some(url) else {
        return (@cmd.none, model)
      }
      (open_external_link(dispatch, url), model)
    }
    AppToggleMaximizedRequested =>
      if model.is_desktop {
        (
          browser_op(
            dispatch,
            @commands.app_toggle_maximized,
            @protocol.NoPayload,
            quiet=false,
          ),
          model,
        )
      } else {
        (@cmd.none, model)
      }
    AppDeveloperToolsRequested =>
      (
        browser_op(
          dispatch,
          @commands.app_open_devtools,
          @protocol.NoPayload,
          quiet=false,
        ),
        model,
      )
    AppCloseWindowRequested => {
      guard model.is_desktop else { return (@cmd.none, model) }
      (
        browser_op(
          dispatch,
          @commands.app_close_window,
          @protocol.NoPayload,
          quiet=false,
        ),
        model,
      )
    }
    CloseActiveDockTab => {
      guard model.is_desktop else { return (@cmd.none, model) }
      match model.dock.active {
        Some(tab) => {
          let (cmd, model) = update_msg(dispatch, Dock(TabClosed(tab)), model)
          (@cmd.batch([cmd, focus_dock_after_render()]), model)
        }
        None => (@cmd.none, model)
      }
    }
    BrowserPaneMeasured(rect~) => {
      // A rectangle for a view that already left the screen (or a zero
      // rectangle from the observer watching a hidden pane) is stale.
      guard desired_browser_view(model) is Some(id) &&
        rect.width > 0 &&
        rect.height > 0 else {
        return (@cmd.none, model)
      }
      let pane = model.browser_pane
      let cmds : Array[@cmd.Cmd] = []
      if pane.rect != Some(rect) || pane.shown != Some(id) {
        cmds.push(browser_set_bounds(dispatch, id, rect))
      }
      if pane.shown != Some(id) {
        // Bounds land before visibility so the view never flashes at its
        // previous place.
        if pane.shown is Some(old) {
          cmds.push(browser_set_visible(dispatch, old, false))
        }
        cmds.push(browser_set_visible(dispatch, id, true))
      }
      (
        @cmd.batch(cmds),
        {
          ..model,
          browser_pane: { ..pane, shown: Some(id), rect: Some(rect), },
        },
      )
    }
    Terminal(@terminal.LinkActivated(url~)) =>
      update_msg(dispatch, ExternalLinkClicked(url), model)
    Terminal(@terminal.InputFailed(message~)) =>
      model.notify_error(dispatch, message)
    Terminal(msg) => {
      let (cmd, terminal) = model.terminal.handle(
        dispatch.map(next => Terminal(next)),
        msg,
        model.terminal_input(),
      )
      (cmd, { ..model, terminal, })
    }
    HostActionFailed(message) => model.notify_error(dispatch, message)
    SessionExportOpenFailed(path~) =>
      model.notify_error(
        dispatch,
        "Saved to \{path}, but couldn't open it automatically.",
      )
    OpenFileFailed(owner~, generation~, message~) =>
      if model.active_checkout() is Some(active) &&
        owner == active.owner &&
        generation == model.file_panel.file_link_generation {
        model.notify_error(dispatch, message)
      } else {
        (@cmd.none, model)
      }
    ExternalLinkClicked(url) =>
      // Web links open in the dock's Browser tabs by default — the
      // toolbar's open-external button hands the page to the system
      // browser when its chrome or logins are needed. Non-web schemes
      // (mailto:, vscode:, …) and remote consoles (no native views) keep
      // the external path. A same-URL tab already in this strip
      // re-activates instead of duplicating.
      //
      // Only from conversation screens: the capture listener behind this
      // message is document-wide, so it also reports anchors on screens where
      // the dock is not rendered and a tab would be invisible. Chat and Codex
      // deliberately share this route — their PR links must open in the same
      // built-in Browser instead of changing behavior with the conversation
      // provider. Settings' device-page link is the clearest external case:
      // it wants the browser where the user is already signed in.
      if !model.is_desktop {
        (open_browser_link(url), model)
      } else if (model.screen is Chat || model.screen is Codex) &&
        @preview.is_web_url(url) {
        // Opening or reusing a Browser tab is a newer dock navigation than a
        // transcript text-file link still waiting on `host.open_path`. Spend the
        // shared token before either branch so its delayed reply cannot put a
        // file back over the URL the user chose later.
        let model = model.begin_editor_navigation()
        // The scan is over this strip's tabs, not the global page map: a
        // parked conversation may hold the same URL, and matching its page
        // first would shadow this strip's own tab forever.
        let reuse = for tab in model.dock.tabs {
          if tab is Browser(id~) &&
            @preview.page(model.preview, id) is Some(page) &&
            page.url == Some(url) {
            break Some(id)
          }
        } nobreak {
          None
        }
        match reuse {
          Some(id) => {
            let dock = @dock.open_browser(model.dock, id)
            // The reuse matched this page's optimistic URL mirror, which can
            // drift from what the native view actually shows — a host op that
            // failed, or a reload's `close_all` that swept the view. Focusing
            // alone would present the stale page under the clicked URL, so a
            // reuse re-navigates: `browser.navigate` rebuilds the view when
            // it is gone, and dropping the pane placement makes the next sync
            // measure and show whatever the host has now.
            (
              browser_navigate(
                dispatch,
                id,
                url,
                model.theme.is_dark(model.system_dark),
              ),
              {
                ..model,
                preview: @preview.navigate(model.preview, id, url),
                dock,
                browser_pane: { shown: None, rect: None, geo: None, },
                right_panel_open: true,
                right_panel_menu_open: false,
              },
            )
          }
          None => {
            let (preview, id) = @preview.open_page(model.preview, url~)
            let dock = @dock.open_browser(model.dock, id)
            (
              browser_open(
                dispatch,
                id,
                url,
                model.theme.is_dark(model.system_dark),
              ),
              {
                ..model,
                preview,
                dock,
                right_panel_open: true,
                right_panel_menu_open: false,
              },
            )
          }
        }
      } else {
        (open_external_link(dispatch, url), model)
      }
    FromDevice(channel, msg) => update_device_msg(dispatch, channel, msg, model)
  }
}

///|
/// Settle one definitively refused initial prompt: restore its draft and
/// placement state, and report the refusal. Nothing durable will ever carry
/// it — the prompt was refused before anything was written — so it is a toast
/// rather than a transcript row.
fn Model::reject_start(
  self : Model,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  session : String,
  submission_id : String,
  message : String,
) -> (@cmd.Cmd, Model) {
  guard self.find_conversation(channel, session) is Some(conv) else {
    return (@cmd.none, self)
  }
  let (rejected, removed) = conv.reject_pending_prompt(submission_id)
  guard removed else { return (@cmd.none, self) }
  let next = if conv.run is Starting(submission_id=current) &&
    current == submission_id {
    { ..rejected.clear_streams(), run: NoRun(ended=Some(RunFailed)), }
  } else {
    rejected
  }
  let (notice, updated) = self
    .replace_conversation(next)
    .notify_error(dispatch, message)
  if updated.device_state(channel) is Some(dev) {
    // A checkout deleted outside the app cannot publish a registry
    // notification. Refresh placement after every rejected workspace start;
    // a newly missing row then exposes Repair/Archive immediately.
    let request_generation = dev.worktrees_request_generation + 1
    (
      @cmd.batch([
        notice,
        fetch_worktrees(
          dispatch,
          channel,
          conv.project(),
          dev.connection_generation,
          request_generation,
        ),
      ]),
      updated.replace_device({
        ..dev,
        worktrees_request_generation: request_generation,
      }),
    )
  } else {
    (notice, updated)
  }
}

///|
/// Reconcile the selected Codex task from one authoritative worktree registry
/// snapshot. List replies and live broadcasts have different freshness rules,
/// but once their caller accepts them they must project the same host-owned row
/// into Files, Terminal, language services, Git and skills.
fn Model::apply_codex_worktree_snapshot(
  self : Model,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  workspace : @common.Uri,
  rows : Array[WorktreeRow],
) -> (@cmd.Cmd, Model) {
  guard channel == self.focused && self.codex.active_id() is Some(thread_id) else {
    return (@cmd.none, self)
  }
  for row in rows {
    if row.codex_thread == Some(thread_id) && row.path is Some(path) {
      let (command, codex) = @codex.update(
        dispatch.map(msg => Codex(channel~, msg)),
        @codex.Msg::worktree_changed(
          thread_id,
          workspace.path,
          row.name,
          path.path,
          row.present,
        ),
        self.codex,
        channel,
        url => open_external_link(dispatch, url),
      )
      return (command, { ..self, codex, })
    }
  }
  (@cmd.none, self)
}

///|
/// Catch up the transcript of a sub-run child the reader is looking at.
///
/// A child's record is written by a process the host manages no writer for, so
/// no follower broadcasts its commits (`internal/engine/follower` runs one per
/// host-managed writer) and `session.load` answered it with a one-shot read.
/// Every signal that the child moved therefore has to drive its own catch-up,
/// and there are exactly two: the probe's progress push while it runs, and the
/// finish. Both matter — the host cancels the probe at `subrun_finished`
/// without a final poll (`internal/engine/engine.mbt`), and the probe sleeps
/// before it reads, so the child's last writes — its report among them — reach
/// a reader through the finish or not at all.
///
/// `active_session` alone does not mean visible: a reader on Skills or
/// Settings has one, and reloading behind those screens would be work nobody
/// can see.
fn refresh_visible_subrun_child(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  session : String,
  model : Model,
) -> (@cmd.Cmd, Model) {
  guard model.screen is Chat &&
    channel == model.focused &&
    session == model.active_session &&
    model.find_conversation(channel, session) is Some(child) &&
    model.can_reload_transcript(child) else {
    return (@cmd.none, model)
  }
  // Coalesce rather than drop. `begin_transcript_reload` is single-flight and
  // answers a signal arriving mid-read with `None`, which is right for a user
  // re-selecting a row and wrong here: the probe publishes only when the child
  // ADVANCED, so a dropped signal can be the last one ever sent — a child that
  // then finishes would strand this transcript one step short with nothing
  // left to correct it.
  let (next, generation) = model.ensure_transcript_reload_after_current(child)
  match generation {
    // A background refresh, never `activate_on_success`: the foreground path
    // pulls the UI to Chat, calls `Model::activate` (pruning other
    // conversations and clearing their unseen-finish marks), and remounts the
    // transcript component — and the remount is what would discard a reader's
    // scroll position and open disclosures. None of that belongs here.
    Some(generation) =>
      (
        session_snapshot_command(
          dispatch, channel, next, session, generation, false,
        ),
        next,
      )
    // Already reloading; the follow-up generation is now armed.
    None => (@cmd.none, next)
  }
}

///|
/// One device channel's messages — its connection lifecycle, its
/// notification stream, and every generation-fenced reply. The arms are
/// the same handlers `update_msg` held before the channel split; `channel`
/// names the device the message came from.
fn update_device_msg(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  msg : DeviceMsg,
  model : Model,
) -> (@cmd.Cmd, Model) {
  guard model.device_state(channel) is Some(dev) else {
    return (@cmd.none, model)
  }
  match msg {
    InstalledSkillsLoaded(items) =>
      if channel == model.focused {
        (@cmd.none, { ..model, installed_skills: items, })
      } else {
        (@cmd.none, model)
      }
    InstalledSkillsFailed(message) =>
      if channel == model.focused {
        (@cmd.none, { ..model, skills: model.skills.with_notice(message), })
      } else {
        (@cmd.none, model)
      }
    // A running sub-run advanced. Two independent readers care: the PARENT's
    // dock lane, and — when the reader is looking at the child itself — the
    // CHILD's transcript. Neither is a precondition for the other. A lane
    // whose parent conversation is gone must not suppress the refresh of a
    // child on screen, and a child nobody is viewing must not suppress the
    // lane.
    // A resolved call of a workflow: refines the row its brackets created, or
    // creates one when they were missed. Routed like sub-run progress, by the
    // parent session the entry names; a conversation that is gone drops it.
    WorkflowEntryArrived(channel, entry) => {
      let model = match model.find_conversation(channel, entry.session) {
        Some(conv) =>
          model.replace_conversation({
            ..conv,
            workflows: @workflow.entry(conv.workflows, entry),
          })
        None => model
      }
      (@cmd.none, model)
    }
    SubrunProgressed(id~, session~, steps~, activity~) => {
      // Route by the CHILD session id, not by the sub-run id: `sr-N` is only
      // unique within its parent engine, so two conversations can both have
      // an `sr-1` in flight. The conversation on screen is not necessarily
      // the one that launched this child either — a background turn keeps
      // running while the user reads something else.
      //
      // An id with no lane is a push that outraced (or outlived) its
      // brackets — dropped, not resurrected, since only a bracket knows a
      // sub-run exists.
      let model = if @transcript.subrun_parent(session) is Some(parent) &&
        model.find_conversation(channel, parent) is Some(conv) {
        let subruns = conv.turn.subruns.map(lane => {
          if lane.id == id {
            { ..lane, steps, activity, }
          } else {
            lane
          }
        })
        if subruns == conv.turn.subruns {
          model
        } else {
          model.replace_conversation({
            ..conv,
            turn: { ..conv.turn, subruns, },
          })
        }
      } else {
        model
      }
      refresh_visible_subrun_child(dispatch, channel, session, model)
    }
    SkillsChanged =>
      if channel == model.focused {
        (fetch_installed_skills(dispatch, channel), model)
      } else {
        // `installed_skills` is the focused host's mirror. A background
        // device is refreshed when focus moves to it.
        (@cmd.none, model)
      }
    BridgeReady => {
      let connection_generation = dev.connection_generation + 1
      let sessions_request_generation = dev.sessions_request_generation + 1
      let archived_request_generation = dev.archived_request_generation + 1
      let projects_request_generation = dev.projects_request_generation + 1
      // Capture the exact per-session lifecycle frontier before issuing the
      // unversioned runs snapshot. A live Started or Finished received before
      // its reply then wins over both stale positive rows and stale absence.
      let run_frontier = model.run_snapshot_frontier(channel)
      let commands = [
        fetch_sessions(
          dispatch, channel, connection_generation, sessions_request_generation,
        ),
        // In-flight runs, so a page that joined (or reconnected) mid-run
        // learns each live run's identity — the resync half of the
        // protocol's reconnect story (docs/remote-protocol.md).
        fetch_runs(dispatch, channel, run_frontier, connection_generation),
        fetch_archived(
          dispatch, channel, connection_generation, archived_request_generation,
        ),
        fetch_projects(
          dispatch, channel, connection_generation, projects_request_generation,
        ),
      ]
      // The focused-scoped half: the host-settings mirror and installed
      // skills (they feed the composer's `$` completion, so
      // they load on connect rather than when the Skills page opens) follow
      // the device the UI acts on — always this one while the app runs a
      // single channel.
      if channel == model.focused {
        commands.push(
          fetch_host_settings(dispatch, channel, connection_generation),
        )
        // Legacy client-stored engine settings: the desktop migrates them
        // up to the host, a browser purges them (see `LegacySettingsRead`).
        commands.push(read_legacy_engine_settings(dispatch))
        commands.push(fetch_installed_skills(dispatch, channel))
        // Codex conversations are always visible in the global sidebar, so
        // populate that focused-host catalog on bridge readiness rather than
        // waiting for a separate Codex page to be opened.
        commands.push(dispatch(Codex(channel~, @codex.Msg::refresh())))
        // Self-update and the relay sign-in are the desktop window's alone
        // (see `is_desktop`); a browser never checks, so neither UI
        // materializes there. The startup update check rides here so it
        // only runs once the bridge can carry it.
        if model.is_desktop {
          commands.push(model.fetch_app_info(dispatch))
          commands.push(check_for_updates(dispatch, explicit=false))
          commands.push(fetch_remote_status(dispatch))
        }
      }
      // Delta streams are not replayable across a connection boundary; keep
      // none of the pre-gap fragment, or the first post-gap delta would splice
      // onto stale text. Compaction has no wire resync in this protocol: an
      // local queued/requested/in-flight marker is released here so a missed
      // terminal event cannot disable Send forever. Any receipt still pending
      // at this boundary can no longer arrive, so its entry ends here. If the
      // host still compacts, its next prompt rejection is a transient,
      // visible local failure.
      let conversations = model.conversations.map(conv => {
        if conv.device == channel {
          {
            ..conv.clear_streams().forget_awaiting_inputs(),
            compaction: NotCompacting,
          }
        } else {
          conv
        }
      })
      let model = model.replace_device({
        ..dev,
        bridge: Connected,
        reconnect_failures: 0,
        connection_generation,
        sessions_request_generation,
        archived_request_generation,
        projects_request_generation,
        archive_overrides: [],
        // Worktree notifications are not replayed across a connection gap.
        // Keep every workspace blocked until this connection returns a fresh
        // list (or a newer `worktree.changed` broadcast) instead of trusting
        // placement cached before the disconnect.
        worktrees: [],
        // Same rule for the settings mirror: a default changed by another
        // client during the gap must not be copied into a chat created
        // before this connection's re-read lands. Absent rows read as the
        // safe Local default.
        workspace_settings: [],
      })
      // Replies from writes issued on the dead bridge carry their captured
      // generation and are ignored below. The new host may have restarted
      // its in-memory settings revision, so its first authoritative status
      // starts a fresh monotonic round. Focused-scoped, like the fetches
      // that repopulate the mirror.
      let model = if channel == model.focused {
        { ..model.clear_host_settings(), conversations, }
      } else {
        { ..model, conversations, }
      }
      // The resync's other half: whatever landed while this client was away
      // (another client's prompts, items a still-running turn completed, a
      // finished run's verdict) exists only in the store. Reads happen
      // exactly where this client was absent: the conversation on screen
      // re-reads now, every other one re-reads when opened (`OpenSession`
      // always reloads). An in-flight user load keeps right of way.
      let model = if channel == model.focused {
        match model.find_conversation(channel, model.active_session) {
          Some(conv) if (
              model.can_reload_transcript(conv) || conv.sync is Reloading(..)
            ) &&
            model.loading_conversation is None => {
            // A real engine pump can restart while the transport remains
            // open. If an older read is already in flight, it may carry a
            // pre-ready cut, so require one follow-up generation rather than
            // treating the old single-flight request as sufficient.
            let (model, generation) = model.ensure_transcript_reload_after_current(
              conv,
            )
            if generation is Some(generation) {
              commands.push(
                session_snapshot_command(
                  dispatch,
                  channel,
                  model,
                  conv.session_id,
                  generation,
                  false,
                ),
              )
            }
            model
          }
          _ => model
        }
      } else {
        model
      }
      guard channel == model.focused else {
        return (@cmd.batch(commands), model)
      }
      (
        @cmd.batch(commands),
        {
          // The host this bridge just (re)connected to may be a fresh
          // process with no filesystem watcher; forgetting what was watched
          // makes the post-dispatch panel sync re-issue `fs.watch` instead
          // of reading the stale record as "already placed". An unusable
          // endpoint does not route anywhere from here: the settings
          // snapshot this connection fetches decides whether the API-setup
          // modal opens.
          ..model,
          file_panel: { ..model.file_panel, watching: None, },
        },
      )
    }
    BridgeUnavailable(message) =>
      (@cmd.none, model.replace_device({ ..dev, bridge: BridgeLost(message), }))
    ChannelDown(websocket_epoch~) => {
      // A close callback may already be queued when sign-out retires a
      // device. If the same relay id is later re-added, it owns a new epoch
      // and must not inherit the retired connection's failure or timer.
      guard websocket_epoch == dev.websocket_epoch else {
        return (@cmd.none, model)
      }
      // Count the loss and schedule the next attempt. Because the attempt
      // comes back through this function, a removed or re-added device fails
      // the state/epoch guards and its old loop simply ends.
      let failures = dev.reconnect_failures + 1
      let bridge = if failures == WsLostAfter {
        BridgeLost(
          "Can't reach SeekMoon. Make sure SeekMoon is running, then reopen this page.",
        )
      } else {
        dev.bridge
      }
      (
        @cmd.delay(
          dispatch(FromDevice(channel, ReconnectDue(websocket_epoch~))),
          reconnect_delay(failures),
        ),
        model.replace_device({ ..dev, bridge, reconnect_failures: failures, }),
      )
    }
    ReconnectDue(websocket_epoch~) => {
      guard websocket_epoch == dev.websocket_epoch else {
        return (@cmd.none, model)
      }
      (
        @cmd.none,
        model.replace_device({
          ..dev,
          reconnect_attempt: dev.reconnect_attempt + 1,
        }),
      )
    }
    FilePanel(msg) => {
      // The file panel serves the focused conversation; a background
      // device's fs/diagnostics noise must not re-stat or redraw it.
      guard channel == model.focused else { return (@cmd.none, model) }
      update_msg(dispatch, FileEditor(msg), model)
    }
    HostSettingsLoaded(settings, connection_generation~) => {
      guard connection_generation is None ||
        connection_generation == Some(dev.connection_generation) else {
        return (@cmd.none, model)
      }
      // The settings mirror is the focused host's. A generation-carrying
      // reply is only ever requested for the focused channel, but the
      // `settings.changed` broadcast (generation None) arrives from every
      // connected device — a background device's edit must not clobber the
      // form. A focus switch refetches, so nothing is lost.
      guard channel == model.focused else { return (@cmd.none, model) }
      if settings.revision < model.host_settings_revision {
        (@cmd.none, model)
      } else if model.settings_saves > 0 {
        (@cmd.none, model.defer_host_settings(settings))
      } else {
        // The settled mirror decides the modal (`settle_api_setup`); the
        // dismissal flag — not the mirror, which a reconnect clears — is
        // what keeps a "Not now" quiet across snapshots.
        (@cmd.none, model.apply_host_settings(settings).settle_api_setup())
      }
    }
    HostSettingsApplied(settings, connection_generation~, cleans_legacy~) => {
      guard connection_generation == dev.connection_generation else {
        return (@cmd.none, model)
      }
      // A save issued on the old focus may settle after the user switches
      // devices. Its revision and localStorage cleanup belong to that old
      // host and must not alter the newly focused host's mirror.
      guard channel == model.focused else { return (@cmd.none, model) }
      let next = {
        ..model,
        settings_saves: if model.settings_saves > 0 {
          model.settings_saves - 1
        } else {
          0
        },
      }.defer_host_settings(settings)
      // The migration's secrets leave localStorage only once the host
      // confirmed it holds them.
      let cleanup = if cleans_legacy && next.legacy_cleanup_pending {
        clear_legacy_engine_settings()
      } else {
        @cmd.none
      }
      let next = if cleans_legacy {
        { ..next, legacy_cleanup_pending: false, }
      } else {
        next
      }
      (
        cleanup,
        if next.settings_saves > 0 {
          next
        } else {
          next.flush_host_settings()
        },
      )
    }
    HostSettingsSaveFailed(message, connection_generation~, cleans_legacy~) => {
      guard connection_generation == dev.connection_generation else {
        return (@cmd.none, model)
      }
      guard channel == model.focused else { return (@cmd.none, model) }
      let next = {
        ..model,
        settings_saves: if model.settings_saves > 0 {
          model.settings_saves - 1
        } else {
          0
        },
        // The push never landed; the legacy values stay in localStorage for
        // the next launch's retry.
        legacy_cleanup_pending: if cleans_legacy {
          false
        } else {
          model.legacy_cleanup_pending
        },
      }
      let next = if next.settings_saves == 0 {
        next.flush_host_settings()
      } else {
        next
      }
      let (notice, notified) = next.notify_error(
        dispatch,
        "Saving settings failed: \{message}",
      )
      let commands = [notice]
      if next.settings_saves == 0 {
        // No successful reply may follow to correct the optimistic form.
        // An authoritative get (same-revision statuses are accepted) restores
        // host truth after a definite or ambiguous write failure.
        commands.push(
          fetch_host_settings(dispatch, channel, dev.connection_generation),
        )
      }
      (@cmd.batch(commands), notified)
    }
    SteerUndelivered(session~, submission_id~, text~, run_id~) => {
      // The response path failed and the host may or may not have taken the
      // steer. Neither answer is knowable here and neither is worth guessing
      // at: the entry ends, and the transcript says what actually happened.
      ignore(text)
      if model.find_conversation(channel, session) is Some(conv) {
        let (next, changed) = conv.acknowledge_steer(
          submission_id,
          Some(run_id),
        )
        if changed {
          (@cmd.none, model.replace_conversation(next))
        } else {
          (@cmd.none, model)
        }
      } else {
        (@cmd.none, model)
      }
    }
    SteerRejected(session~, submission_id~, run_id~) =>
      // A concrete `steered:false` cannot later commit. Retire the queue entry
      // and restore its exact draft; a later same-text submission is unrelated.
      if model.find_conversation(channel, session) is Some(conv) {
        let (next, removed) = conv.reject_steer(submission_id, Some(run_id))
        if removed {
          model
          .replace_conversation(next)
          .notify_error(dispatch, SteerDroppedNotice)
        } else {
          (@cmd.none, model)
        }
      } else {
        (@cmd.none, model)
      }
    QueueAccepted(session~, action~, run_id~) => {
      guard model.find_conversation(channel, session) is Some(conv) else {
        return (@cmd.none, model)
      }
      let next = match action {
        @protocol.QueueAdd(id~, ..) => {
          let (next, _) = conv.acknowledge_steer(id, Some(run_id))
          next
        }
        @protocol.QueueEdit(id~, text=content) => {
          guard conv.queued_inputs.search_by(item => item.id == id)
            is Some(index) else {
            return (@cmd.none, model)
          }
          let queued_inputs = conv.queued_inputs.copy()
          queued_inputs[index] = { id, content, }
          if conv.queue_edit_id == Some(id) {
            {
              ..conv,
              queued_inputs,
              task: "",
              mentions: [],
              composer_draft_present: false,
              queue_edit_id: None,
            }
          } else {
            { ..conv, queued_inputs, }
          }
        }
        @protocol.QueueWithdraw(id~) | @protocol.QueueSteer(id~) => {
          let (next, _) = conv.remove_queued_input(id)
          next
        }
      }
      (@cmd.none, model.replace_conversation(next))
    }
    QueueAddRejected(session~, submission_id~, run_id~) =>
      if model.find_conversation(channel, session) is Some(conv) {
        let (next, removed) = conv.reject_steer(submission_id, Some(run_id))
        if removed {
          let (next, _) = next.remove_queued_input(submission_id)
          model
          .replace_conversation(next)
          .notify_error(
            dispatch, "Message was not queued (the task ended as you sent it) — it is back in the composer.",
          )
        } else {
          (@cmd.none, model)
        }
      } else {
        (@cmd.none, model)
      }
    QueueSteerRejected(session~, submission_id~, run_id~, message~) =>
      if model.find_conversation(channel, session) is Some(conv) {
        let (next, removed) = conv.acknowledge_steer(
          submission_id,
          Some(run_id),
        )
        if removed {
          model.replace_conversation(next).notify_error(dispatch, message)
        } else {
          (@cmd.none, model)
        }
      } else {
        (@cmd.none, model)
      }
    CancelNotOpen(run_id~) => {
      guard model.conversation_by_run(channel, run_id) is Some(conv) else {
        return (@cmd.none, model)
      }
      // The id-addressed reply is authoritative: this exact run is no longer
      // open at the host. Close the optimistic Cancelling phase immediately,
      // then ask for the saved settlement so the ordinary Finished path can
      // recover its outcome and refresh the transcript. A successor that won
      // the race has another id and is left untouched by the guard above.
      let closed = conv.clear_streams().forget_steers_for_run(run_id)
      let closed = if closed.pending_approval
        is Some({ run_id: Some(owner), .. }) &&
        owner == run_id {
        { ..closed, pending_approval: None, }
      } else {
        closed
      }
      let updated = model.replace_conversation({
        ..closed,
        run: NoRun(ended=None),
        last_run_id: Some(run_id),
      })
      (
        fetch_runs(
          dispatch,
          channel,
          updated.run_snapshot_frontier(channel),
          dev.connection_generation,
        ),
        updated,
      )
    }
    CancelFailed(run_id~, message~) => {
      guard model.conversation_by_run(channel, run_id) is Some(conv) &&
        conv.run is Open(run_id=current, stage=Cancelling) &&
        current == run_id else {
        return (@cmd.none, model)
      }
      // Stop was optimistic. If delivery failed, hand the control back while
      // a runs snapshot determines whether the engine is in fact still live.
      let retryable = model.replace_conversation({
        ..conv,
        run: Open(run_id~, stage=AtStep(None)),
      })
      let (notice, notified) = retryable.notify_error(dispatch, message)
      (
        @cmd.batch([
          notice,
          fetch_runs(
            dispatch,
            channel,
            notified.run_snapshot_frontier(channel),
            dev.connection_generation,
          ),
        ]),
        notified,
      )
    }
    SessionsLoaded(items, connection_generation~, request_generation~) => {
      guard connection_generation == dev.connection_generation &&
        request_generation == dev.sessions_request_generation else {
        return (@cmd.none, model)
      }
      // Whole-list replies have no store revision. An identity notification
      // delivered after this request was issued wins for its session: remove
      // newly archived rows and retain newly unarchived rows from the current
      // model when the stale reply omitted them.
      let items = items.filter(item => {
        let disposition = dev.archive_override({
          session: item.id,
          workspace: item.workspace,
        })
        disposition != Some(ArchiveStored) &&
        disposition != Some(ArchiveDeleted)
      })
      for fact in dev.archive_overrides {
        if fact.disposition is ArchiveLive &&
          !items.iter().any(item => fact.key.matches(item)) {
          for current in dev.sessions {
            if fact.key.matches(current) {
              items.push(current)
            }
          }
        }
      }
      // A commit or Started broadcast can materialize a conversation before
      // session.list tells this page which durable store owns it. Reconcile
      // that provisional placement from the list before any later send: an
      // empty workspace hint here would otherwise fork the same session into
      // the default store.
      let conversations = model.conversations.map(conv => {
        if conv.device == channel {
          let mut project = conv.project()
          for item in items {
            if item.id == conv.session_id {
              project = item.workspace
            }
          }
          {
            ..conv,
            workspace: dev.conversation_workspace(
              project,
              conv.session_id,
              conv.workspace,
            ),
          }
        } else {
          conv
        }
      })
      let mut active_project = dev.active_project
      if channel == model.focused {
        for item in items {
          if item.id == model.active_session {
            active_project = Some(item.workspace)
          }
        }
      }
      let mut next = {
        ..model.replace_device({ ..dev, sessions: items, active_project, }),
        conversations,
      }
      let commands : Array[@cmd.Cmd] = []
      // A client can miss session.changed while disconnected. A live row from
      // this connection is then the first proof that a cached read-only record
      // was restored elsewhere. Reclassify it before the archived-list reply:
      // the override admits new commits immediately, and the new transcript
      // generation fences the archived request started by BridgeReady.
      for conv in next.conversations {
        let key : ArchiveRecordKey = {
          session: conv.session_id,
          workspace: conv.project(),
        }
        if conv.device == channel &&
          conv.is_archived_read_only() &&
          items.iter().any(item => key.matches(item)) {
          let foreground = channel == next.focused &&
            next.active_session == conv.session_id
          next = next.with_archive_override(channel, key, ArchiveLive)
          let (updated, generation) = next.begin_transcript_reload({
            ..conv,
            record: LiveRecord,
            sync: Synced,
          })
          next = if foreground {
            {
              ..updated,
              loading_conversation: Some({ channel, session: conv.session_id, }),
            }
          } else {
            updated
          }
          if generation is Some(generation) {
            commands.push(
              session_snapshot_command(
                dispatch,
                channel,
                next,
                conv.session_id,
                generation,
                foreground,
              ),
            )
          }
        }
      }
      // A start or a goal may have been accepted just before the connection
      // vanished, while the first BridgeReady load raced persistence and
      // returned empty. The session list is later durable proof that a record
      // now exists: use that edge to retry exactly the unresolved recoveries.
      for conv in next.conversations {
        if conv.device == channel &&
          conv.awaits_durable_proof() &&
          !(conv.sync is Reloading(..)) &&
          items.iter().any(item => item.id == conv.session_id) {
          let (updated, generation) = next.begin_transcript_reload(conv)
          next = updated
          if generation is Some(generation) {
            commands.push(
              session_snapshot_command(
                dispatch,
                channel,
                next,
                conv.session_id,
                generation,
                false,
              ),
            )
          }
        }
      }
      (@cmd.batch(commands), next)
    }
    ProjectsLoaded(paths, connection_generation~, request_generation~) => {
      guard connection_generation == dev.connection_generation &&
        request_generation == dev.projects_request_generation else {
        return (@cmd.none, model)
      }
      // The registry snapshot is also the authority for what this page may
      // keep open. `adopt_projects` drops conversations from detached
      // stores; their durable records remain on disk and return through the
      // next session list after the workspace is attached again.
      adopt_projects(dispatch, channel, model, paths)
    }
    ProjectsChanged(paths) => {
      // The post-commit broadcast is newer than every list request issued so
      // far. Advance the token before applying it, so an older list reply can
      // never roll any client back after this canonical mutation order.
      let next = model.replace_device({
        ..dev,
        projects_request_generation: dev.projects_request_generation + 1,
      })
      adopt_projects(dispatch, channel, next, paths)
    }
    ProjectAddCommitted(added~, paths~) => {
      // Identity resolution for a pending add-and-focus. This reply is the
      // canonical list right after our own commit, so the picked directory
      // is in it — as picked, or under its realpath spelling, in which case
      // it is the reply's one row we did not already know. Anything else
      // (concurrent commits landed between our known snapshot and ours) is
      // not provably ours: stand down rather than guess. `added` pairs the
      // reply with its confirm: a reply for a directory the pending is not
      // about answers a superseded confirm and is ignored outright — the
      // current confirm's own reply is still on its way.
      guard model.pending_project_adoption is Some(pending) &&
        pending.channel == channel &&
        pending.requested == added else {
        return (@cmd.none, model)
      }
      let target = if paths.contains(pending.picked) {
        Some(pending.picked)
      } else {
        match paths.filter(path => !pending.known.contains(path)) {
          [added] => Some(added)
          _ => None
        }
      }
      guard target is Some(target) else {
        return (@cmd.none, { ..model, pending_project_adoption: None, })
      }
      if dev.projects.contains(target) {
        // The commit broadcast beat this reply and the row already exists:
        // focus it now, the way the row's own ＋ does.
        let cleared = { ..model, pending_project_adoption: None, }
        let (focus_cmd, focused) = update(
          dispatch,
          NewChatIn(channel, Some(target)),
          cleared,
        )
        (@cmd.batch([focus_cmd, reveal_active_project()]), focused)
      } else {
        // The row is not on this page yet; the snapshot that brings it
        // finishes the focus.
        (
          @cmd.none,
          {
            ..model,
            pending_project_adoption: Some({
              ..pending,
              resolved: Some(target),
            }),
          },
        )
      }
    }
    ProjectFailed(message) => {
      // A failed mutation also settles any confirmed add still waiting to
      // focus its project: nothing was committed on its behalf.
      let model = if model.pending_project_adoption is Some(pending) &&
        pending.channel == channel {
        { ..model, pending_project_adoption: None, }
      } else {
        model
      }
      model.notify_error(dispatch, "Workspace error: \{message}")
    }
    WorkspaceSettingsLoaded(
      workspace~,
      worktree_mode~,
      checkout_submodules~,
      submodule_checkout_timeout_seconds~,
      connection_generation~,
      request_generation~
    ) => {
      // The same per-workspace staleness fence as `WorktreesLoaded` — plus a
      // registry-membership check, because pruning a detached workspace's
      // row also discards the generation it was applied under. Without the
      // membership check, a straggler reply issued before the detach would
      // pass the reset (-1) fence and resurrect a row that could outlive a
      // reattach until the fresh fan-out answers.
      guard dev.projects.contains(workspace) &&
        connection_generation == dev.connection_generation &&
        request_generation > dev.workspace_settings_generation(workspace) else {
        return (@cmd.none, model)
      }
      (
        @cmd.none,
        model.replace_device(
          dev.with_workspace_settings(
            workspace,
            worktree_mode,
            generation=request_generation,
            checkout_submodules~,
            submodule_checkout_timeout_seconds~,
          ),
        ),
      )
    }
    WorkspaceSettingsChanged(
      workspace~,
      worktree_mode~,
      checkout_submodules~,
      submodule_checkout_timeout_seconds~
    ) => {
      // A broadcast can race the detach commit the same way a reply can
      // (the hub orders them per client, so an attach is always processed
      // before settings broadcasts that follow it).
      guard dev.projects.contains(workspace) else { return (@cmd.none, model) }
      // The post-commit broadcast is newer than every list request issued so
      // far; advance the mint and stamp this workspace's row with the new
      // token so an older reply for it can never roll the broadcast back.
      let workspace_settings_request_generation = dev.workspace_settings_request_generation +
        1
      (
        @cmd.none,
        model.replace_device({
          ..dev.with_workspace_settings(
            workspace,
            worktree_mode,
            generation=workspace_settings_request_generation,
            checkout_submodules~,
            submodule_checkout_timeout_seconds~,
          ),
          workspace_settings_request_generation,
        }),
      )
    }
    WorkspaceSettingsSaveFailed(workspace~, message~) => {
      // The page's optimistic value may be wrong now: alongside the toast,
      // re-read the disk state under a fresh token.
      let request_generation = dev.workspace_settings_request_generation + 1
      let (toast, next) = model.notify_error(
        dispatch,
        "Workspace settings not saved for \{workspace.path}: \{message}",
      )
      (
        @cmd.batch([
          toast,
          fetch_workspace_settings(
            dispatch,
            channel,
            workspace,
            dev.connection_generation,
            request_generation,
          ),
        ]),
        next.replace_device({
          ..dev,
          workspace_settings_request_generation: request_generation,
        }),
      )
    }
    WorktreesLoaded(
      rows,
      workspace~,
      connection_generation~,
      request_generation~
    ) => {
      // The staleness fence is per workspace: this reply is stale only when
      // THIS workspace's rows were already applied under a newer token — a
      // broadcast for a sibling workspace must not discard it.
      guard connection_generation == dev.connection_generation &&
        request_generation > dev.worktree_generation(workspace) else {
        return (@cmd.none, model)
      }
      let next_dev = dev.with_worktrees(
        workspace,
        rows,
        generation=request_generation,
      )
      let next = model.replace_device(next_dev)
      // A fresh list can be the first proof that a binding disappeared while
      // this client was disconnected. Spend one Git request number just like
      // the live broadcast path: every conversation unbound by this snapshot
      // must reject branch and pull-request answers still in flight for the
      // checkout that no longer owns it.
      let (fence, next) = next.mint_git_request()
      let conversations = next.conversations.map(conv => {
        if conv.device == channel && conv.project() == workspace {
          let placement = next_dev.conversation_workspace(
            workspace,
            conv.session_id,
            conv.workspace,
          )
          if conv.workspace is Worktree(..) && placement is Project(..) {
            { ..conv.forget_git(fence~), workspace: placement, }
          } else {
            { ..conv, workspace: placement, }
          }
        } else {
          conv
        }
      })
      // The list reply is the reconnect catch-up path: live
      // `worktree.changed` notifications are not replayed after a gap, so the
      // accepted snapshot must also repair the selected Codex task's placement.
      { ..next, conversations, }.apply_codex_worktree_snapshot(
        dispatch, channel, workspace, rows,
      )
    }
    WorktreesFailed(
      workspace~,
      connection_generation~,
      request_generation~,
      message~
    ) => {
      // A later snapshot or broadcast for this workspace makes an older
      // failure irrelevant, just as a dead connection's rejection must not
      // pop over the newly connected UI.
      guard connection_generation == dev.connection_generation &&
        request_generation > dev.worktree_generation(workspace) else {
        return (@cmd.none, model)
      }
      model.notify_error(
        dispatch,
        "Worktree list unavailable for \{workspace.path}: \{message}",
      )
    }
    WorktreesChanged(rows, workspace~) => {
      // The post-commit broadcast is newer than every list request issued so
      // far; advance the mint and stamp this workspace's rows with the new
      // token so an older reply for it can never roll the broadcast back.
      let worktrees_request_generation = dev.worktrees_request_generation + 1
      let next_dev = {
        ..dev.with_worktrees(
          workspace,
          rows,
          generation=worktrees_request_generation,
        ),
        worktrees_request_generation,
      }
      let next = model.replace_device(next_dev)
      // Every conversation this broadcast unbinds is unbound at the same
      // instant, so one spent request number fences all of their probes.
      let (fence, next) = next.mint_git_request()
      // Only an actual registry-row removal unbinds its conversations. Archive
      // keeps the row with `present: false`, so it passes through unchanged and
      // later Unarchive still surfaces Repair. Stand down any staged confirm
      // only when the placement itself disappeared.
      let conversations = next.conversations.map(conv => {
        if conv.device == channel && conv.project() == workspace {
          let placement = next_dev.conversation_workspace(
            workspace,
            conv.session_id,
            conv.workspace,
          )
          if conv.workspace is Worktree(..) && placement is Project(..) {
            // The checkout is gone, so every placement derived from it goes
            // too. `forget_git` retires probes already in flight for the removed
            // checkout; the enum transition simultaneously makes every file,
            // LSP, terminal and launcher root re-project to the project.
            { ..conv.forget_git(fence~), workspace: placement, }
          } else {
            { ..conv, workspace: placement, }
          }
        } else {
          conv
        }
      })
      // An open discard dialog whose mapping just disappeared (a protocol
      // client explicitly removed the worktree) must close too:
      // confirming it later would fire a stale forced archive.
      let archive_confirm = match next.archive_confirm {
        Some(confirm) if confirm.channel == channel &&
          next.find_conversation(channel, confirm.session) is Some(conv) &&
          conv.project() == workspace &&
          !rows.iter().any(row => row.session == Some(confirm.session)) => None
        other => other
      }
      let next = { ..next, conversations, archive_confirm, }
      // `worktree.create` commits and broadcasts the owner row before the
      // initiating frontend receives its turn reply. Apply the same accepted
      // snapshot transition as reconnect, so every frontend displaying this
      // Codex task moves its native roots together.
      next.apply_codex_worktree_snapshot(dispatch, channel, workspace, rows)
    }
    WorktreeCreated(workspace~, name~, session~) => {
      // The chain's checkout exists: bind the composing conversation, so
      // the chip shows and a retried submit reuses the same environment.
      guard model.find_conversation(channel, session) is Some(conv) &&
        conv.workspace is Project(root=current) &&
        current == workspace else {
        return (@cmd.none, model)
      }
      (
        @cmd.none,
        model.replace_conversation({
          ..conv,
          workspace: Worktree(project=workspace, name~),
          worktree_mode: false,
        }),
      )
    }
    ArchiveNeedsForce(session~, refusal~) =>
      // The host refused to archive over the worktree's uncommitted
      // changes; stage the discard-confirmation dialog, whose confirm
      // retries with force.
      (
        @cmd.none,
        { ..model, archive_confirm: Some({ channel, session, refusal, }), },
      )
    ArchivedLoaded(
      items,
      connection_generation~,
      request_generation~,
      fresh_session~
    ) => {
      guard connection_generation == dev.connection_generation &&
        request_generation == dev.archived_request_generation else {
        return (@cmd.none, model)
      }
      // A newer unarchive notification wins over an older whole-list reply;
      // a newer archive notification is supplemented from the current list
      // when that reply predates the move.
      let items = items.filter(item => {
        let disposition = dev.archive_override({
          session: item.id,
          workspace: item.workspace,
        })
        disposition != Some(ArchiveLive) && disposition != Some(ArchiveDeleted)
      })
      for fact in dev.archive_overrides {
        if fact.disposition is ArchiveStored &&
          !items.iter().any(item => fact.key.matches(item)) {
          for current in dev.archived {
            if fact.key.matches(current) {
              items.push(current)
            }
          }
        }
      }
      // An archive mutation response can beat its session.changed callback.
      // Treat a newly observed archived row as a local tombstone immediately,
      // so a stale live-list reply cannot reopen it in that delivery gap.
      let mut next = model
      for item in items {
        let key : ArchiveRecordKey = {
          session: item.id,
          workspace: item.workspace,
        }
        if next.archive_override(channel, key) is None {
          next = next.with_archive_override(channel, key, ArchiveStored)
        }
      }
      let archived_now = (id : String, workspace : @common.Uri) => {
        items.iter().any(item => item.id == id && item.workspace == workspace)
      }
      // The selected row may still be loading while another conversation is
      // active. Its exact store-qualified identity, not `active_session`, owns
      // the fallback when an archive reply removes it.
      if next.conversation_selection() is Some(selected) &&
        selected.record is LiveRecord &&
        archived_now(selected.session, selected.workspace) {
        next = replace_removed_selection(
          next,
          channel,
          selected.session,
          fresh_session,
          selected.workspace,
          LiveRecord,
        )
      }
      let conversations = next.conversations.filter(conv => {
        conv.device != channel ||
        !archived_now(conv.session_id, conv.project()) ||
        conv.is_archived_read_only()
      })
      guard next.device_state(channel) is Some(ndev) else {
        return (@cmd.none, { ..next, conversations, })
      }
      let sessions = ndev.sessions.filter(item => {
        !archived_now(item.id, item.workspace)
      })
      (
        @cmd.none,
        {
          ..next.replace_device({ ..ndev, archived: items, sessions, }),
          conversations,
        },
      )
    }
    ArchivedDeleted(
      key~,
      sessions~,
      items~,
      connection_generation~,
      request_generation~,
      fresh_session~
    ) => {
      guard connection_generation == dev.connection_generation &&
        request_generation == dev.archived_request_generation else {
        return (@cmd.none, model)
      }
      // Install the permanent tombstone before folding the unversioned list
      // reply. The ordinary ArchivedLoaded reconciliation then rejects both
      // this stale row and any later live-list copy of it.
      let mut tombstoned = model
      for session in sessions {
        tombstoned = tombstoned.with_archive_override(
          channel,
          { session, workspace: key.workspace, },
          ArchiveDeleted,
        )
      }
      // The selected archived row may still be loading. Replace that exact
      // selection before removing its backing conversation.
      if tombstoned.conversation_selection() is Some(selected) &&
        selected.record is ArchivedRecord &&
        selected.channel == channel &&
        selected.workspace == key.workspace &&
        sessions.contains(selected.session) {
        tombstoned = replace_removed_selection(
          tombstoned,
          channel,
          selected.session,
          fresh_session,
          key.workspace,
          ArchivedRecord,
        )
      }
      if tombstoned.device_state(channel) is Some(ndev) {
        tombstoned = tombstoned.replace_device({
          ..ndev,
          sessions: ndev.sessions.filter(item => {
            item.workspace != key.workspace || !sessions.contains(item.id)
          }),
          archived: ndev.archived.filter(item => {
            item.workspace != key.workspace || !sessions.contains(item.id)
          }),
        })
      }
      let conversations = tombstoned.conversations.filter(conv => {
        conv.device != channel ||
        conv.project() != key.workspace ||
        !sessions.contains(conv.session_id)
      })
      update_device_msg(
        dispatch,
        channel,
        ArchivedLoaded(
          items,
          connection_generation~,
          request_generation~,
          fresh_session~,
        ),
        { ..tombstoned, conversations, archived_delete_confirm: None, },
      )
    }
    ArchiveFailed(message) => {
      // A definitive refusal usually means this page no longer matches the
      // host's stores — the record moved, or its workspace detached while
      // this sidebar still showed it. Re-adopt the registry snapshot (which
      // prunes detached conversations and refreshes the live list) and the
      // archived list, so the state that made the click possible heals
      // instead of failing identically forever.
      let projects_request_generation = dev.projects_request_generation + 1
      let refresh = fetch_projects(
        dispatch,
        channel,
        dev.connection_generation,
        projects_request_generation,
      )
      let model = model.replace_device({ ..dev, projects_request_generation, })
      let (archived, model) = request_archived_refresh(dispatch, channel, model)
      let (toast, model) = model.notify_error(
        dispatch,
        "Archive failed: \{message}",
      )
      (@cmd.batch([refresh, archived, toast]), model)
    }
    DeleteArchivedFailed(message) => {
      let (refresh, model) = request_archived_refresh(dispatch, channel, model)
      let (toast, model) = model.notify_error(
        dispatch,
        "Delete failed: \{message}",
      )
      (@cmd.batch([refresh, toast]), model)
    }
    WorktreeFailed(message) => model.notify_error(dispatch, message)
    SessionsFailed(message) =>
      model.notify_error(dispatch, "Session list unavailable: \{message}")
    // Another client archived, restored, or deleted a conversation. Both
    // sidebar lists are stale, but this identity-bearing fact takes effect
    // immediately and remains authoritative over in-flight replies.
    SessionsChanged(change~, key~, fresh_session~) => {
      let (sessions, model) = request_sessions_refresh(dispatch, channel, model)
      let (archived, model) = request_archived_refresh(dispatch, channel, model)
      let commands = @cmd.batch([sessions, archived])
      guard model.device_state(channel) is Some(dev) else {
        return (commands, model)
      }
      if change == "deleted" {
        let changed = if fresh_session is Some(fresh) {
          replace_removed_selection(
            model,
            channel,
            key.session,
            fresh,
            key.workspace,
            ArchivedRecord,
          )
        } else {
          model
        }
        let sessions = dev.sessions.filter(item => !key.matches(item))
        let archived = dev.archived.filter(item => !key.matches(item))
        let conversations = changed.conversations.filter(conv => {
          conv.device != channel ||
          conv.session_id != key.session ||
          conv.project() != key.workspace
        })
        let confirm = match changed.archived_delete_confirm {
          Some(confirm) if confirm.channel == channel && confirm.key == key =>
            None
          other => other
        }
        let next = changed
          .replace_device({ ..dev, sessions, archived, })
          .with_archive_override(channel, key, ArchiveDeleted)
        return (
          commands,
          { ..next, conversations, archived_delete_confirm: confirm, },
        )
      }
      if change == "unarchived" {
        let mut restored : @transcript.SessionListItem? = None
        for item in dev.archived {
          if key.matches(item) {
            restored = Some(item)
          }
        }
        let archived = dev.archived.filter(item => !key.matches(item))
        let sessions = dev.sessions.copy()
        if restored is Some(item) &&
          !sessions.iter().any(current => key.matches(current)) {
          sessions.push(item)
        }
        let next = model
          .replace_device({ ..dev, sessions, archived, })
          .with_archive_override(channel, key, ArchiveLive)
        let next = match next.selected_conversation {
          Some(selected) if selected.matches_record(
              channel,
              key.session,
              key.workspace,
              ArchivedRecord,
            ) =>
            {
              ..next,
              selected_conversation: Some({ ..selected, record: LiveRecord, }),
            }
          _ => next
        }
        // Fence an archived read that was already in flight, then re-read the
        // now-live record. The transcript stays visible while this new
        // generation settles; only the record source and composer capability
        // change immediately.
        if next.find_conversation(channel, key.session) is Some(conv) &&
          conv.project() == key.workspace &&
          conv.is_archived_read_only() {
          let (next, generation) = next.begin_transcript_reload({
            ..conv,
            record: LiveRecord,
            sync: Synced,
          })
          if generation is Some(generation) {
            let foreground = channel == next.focused &&
              next.active_session == key.session &&
              next.session_project(channel, key.session) == Some(key.workspace)
            let next = if foreground {
              {
                ..next,
                loading_conversation: Some({ channel, session: key.session, }),
              }
            } else {
              next
            }
            return (
              @cmd.batch([
                commands,
                session_snapshot_command(
                  dispatch,
                  channel,
                  next,
                  key.session,
                  generation,
                  foreground,
                ),
              ]),
              next,
            )
          }
          return (commands, next)
        }
        return (commands, next)
      }
      if change != "archived" {
        return (commands, model)
      }
      // Invalidate the live target before either async list reply. Keeping a
      // placeholder archived entry also blocks a late session.event from
      // rematerializing it during this window.
      let sessions = dev.sessions.filter(item => !key.matches(item))
      let conversations = model.conversations.filter(conv => {
        conv.device != channel ||
        conv.session_id != key.session ||
        conv.project() != key.workspace ||
        conv.is_archived_read_only()
      })
      let archived = dev.archived.copy()
      if !archived.iter().any(item => key.matches(item)) {
        let mut item : @transcript.SessionListItem = {
          id: key.session,
          title: None,
          workspace: key.workspace,
          workspace_name: "",
          updated_at_ms: None,
        }
        for live in dev.sessions {
          if key.matches(live) {
            item = live
          }
        }
        archived.push(item)
      }
      let overridden = model.with_archive_override(channel, key, ArchiveStored)
      let overridden = match overridden.device_state(channel) {
        Some(ndev) => overridden.replace_device({ ..ndev, sessions, archived, })
        None => overridden
      }
      let selected_archived = model.conversation_selection() is Some(selected) &&
        selected.matches_record(channel, key.session, key.workspace, LiveRecord)
      let next = {
        ..overridden,
        conversations: if selected_archived {
          model.conversations
        } else {
          conversations
        },
      }
      if selected_archived && fresh_session is Some(fresh) {
        (
          commands,
          replace_removed_selection(
            next,
            channel,
            key.session,
            fresh,
            key.workspace,
            LiveRecord,
          ),
        )
      } else {
        (commands, { ..next, conversations, })
      }
    }
    SessionLoaded(
      session~,
      items~,
      watermark~,
      goal~,
      goal_markers~,
      generation~
    ) =>
      apply_session_snapshot(
        dispatch, channel, model, session, items, watermark, goal, goal_markers,
        generation, true,
      )
    SessionRefreshed(
      session~,
      items~,
      watermark~,
      goal~,
      goal_markers~,
      generation~
    ) =>
      apply_session_snapshot(
        dispatch, channel, model, session, items, watermark, goal, goal_markers,
        generation, false,
      )
    SessionLoadFailed(session~, message~, generation~) =>
      retry_session_snapshot(
        dispatch, channel, model, session, generation, true, message,
      )
    SessionRefreshFailed(session~, generation~) =>
      retry_session_snapshot(
        dispatch,
        channel,
        model,
        session,
        generation,
        false,
        "failed to refresh session \{session}",
      )
    SessionCommitted(session~, sequence~, ts~, item~, session_root~) => {
      // The commit names its own store — the exact durable identity rather
      // than a guess. Commits do not precede `agent.connected` (readiness
      // precedes every forwarded notification), but if one ever did, the
      // listing/live guess is what places it.
      //
      // A store this page cannot resolve to a project places nothing: the
      // record could not be told apart from a same-id one in another store,
      // so the commit is dropped rather than attached to a guess.
      guard (match dev.bridge {
          Connected => dev.placement_for_store_root(session_root)
          _ => model.session_project(channel, session)
        })
        is Some(commit_project) else {
        return (@cmd.none, model)
      }
      // Archiving removes live client state after the hub's ordered final
      // commit. A stale/replayed commit seen after that local fact must not
      // resurrect the archived record as a live hidden conversation.
      let key : ArchiveRecordKey = { session, workspace: commit_project, }
      let archived = match dev.archive_override(key) {
        Some(ArchiveStored | ArchiveDeleted) => true
        Some(ArchiveLive) => false
        None => dev.archived.iter().any(item => key.matches(item))
      }
      if archived {
        return (@cmd.none, model)
      }
      // The page holds at most one conversation per (channel, id), so the
      // one this id finds may stand for another store's record — and that
      // record's watermark says nothing about this store's commits. Only a
      // conversation placed in the committed store can have seen them.
      let first_commit_unseen = match
        model.find_conversation(channel, session) {
        Some(conv) if conv.project() == commit_project =>
          !conv.has_seen_durable_sequence(sequence)
        _ => true
      }
      // The listing is store-qualified, so ask whether THIS record is listed:
      // a same-id row from another store is a different durable record and
      // must not suppress the reload that gives this one its sidebar row.
      let listed = dev.sessions
        .iter()
        .any(item => item.id == session && item.workspace == commit_project)
      let refresh_sessions = sequence == 1 && !listed && first_commit_unseen
      // A short foreign run can commit and finish before either the session
      // list or run resync reaches this page. Materialize hidden client state
      // from the commit itself: sequence 1 projects immediately; a later
      // sequence exposes a gap and follows the normal snapshot recovery path.
      let model = if model.find_conversation(channel, session) is None {
        model.replace_conversation(
          empty_conversation(
            channel,
            session,
            commit_project,
            model=model
              .remembered_model(channel, session)
              .unwrap_or(model.default_model),
          ),
        )
      } else {
        model
      }
      let (commit_cmd, next) = if model.find_conversation(channel, session)
        is Some(conv) {
        let commit : BufferedCommit = { sequence, ts, item, }
        match conv.sync {
          // A read is in flight: buffer — its snapshot's watermark decides
          // whether this commit is already contained once it lands.
          Reloading(..) =>
            (@cmd.none, model.replace_conversation(conv.buffer_commit(commit)))
          // A new commit is also a retry signal after a bounded round stopped.
          ReloadFailed(..) => {
            let (model, generation) = model.begin_transcript_reload(
              conv.buffer_commit(commit),
            )
            if generation is Some(generation) {
              (
                session_snapshot_command(
                  dispatch, channel, model, session, generation, false,
                ),
                model,
              )
            } else {
              (@cmd.none, model)
            }
          }
          Synced =>
            if sequence <= conv.watermark {
              // Old news: the snapshot (or an earlier commit) already
              // carried it. Re-broadcasts are safe by construction.
              (@cmd.none, model)
            } else if sequence == conv.watermark + 1 {
              let (changed, next) = conv.apply_commit(sequence, item, ts?)
              (
                if changed {
                  @cmd.none
                } else {
                  @cmd.none
                },
                model.replace_conversation({ ..next, watermark: sequence, }),
              )
            } else {
              // A gap: this client missed a broadcast (kicked as a slow
              // subscriber, a host restart, an external writer). The record
              // is the source of truth — re-read it, buffering from here.
              let (model, generation) = model.begin_transcript_reload(conv)
              guard model.find_conversation(channel, session) is Some(reloading) else {
                return (@cmd.none, model)
              }
              let model = model.replace_conversation(
                reloading.buffer_commit(commit),
              )
              if generation is Some(generation) {
                (
                  session_snapshot_command(
                    dispatch, channel, model, session, generation, false,
                  ),
                  model,
                )
              } else {
                (@cmd.none, model)
              }
            }
        }
      } else {
        (@cmd.none, model)
      }
      // A live Started can overtake the store write and the BridgeReady list
      // request can therefore miss a newly-created session. Sequence one is
      // the first durable proof that the record exists; refresh the list so
      // clients that learned the commit first still converge on the store's
      // project grouping.
      if refresh_sessions {
        let (sessions, next) = request_sessions_refresh(dispatch, channel, next)
        (@cmd.batch([commit_cmd, sessions]), next)
      } else {
        (commit_cmd, next)
      }
    }
    BranchLoaded(session~, branch~, diffstat~, generation~, base_hint~) => {
      guard model.find_conversation(channel, session) is Some(conv) else {
        return (@cmd.none, model)
      }
      // A probe that is still counting untracked files while a later one has
      // already answered would otherwise put its older branch and totals back
      // on screen, where nothing would correct them until the next refresh.
      guard generation == conv.branch_generation else {
        return (@cmd.none, model)
      }
      let conv = { ..conv, branch, diffstat, diffstat_hint: base_hint, }
      // The pull-request lookup rides on the branch answer rather than on the
      // four places that ask for it: whatever refreshes the branch — a run
      // starting, a session opening, a run finishing — is exactly when the
      // branch's pull request can have changed too.
      guard branch is Some(branch) && !branch.is_empty() else {
        // Not a repository any more: an answer about the branch it used to
        // have would only mislead, including one still on its way.
        let (fence, model) = model.mint_git_request()
        return (
          @cmd.none,
          model.replace_conversation(conv.forget_pull_request(fence~)),
        )
      }
      // A lookup already in flight for this same branch is not stacked on —
      // but it is marked stale, because its answer was gathered before this
      // refresh asked for one. Dropping the refresh outright would leave the
      // chip describing the repository as it was when a run started, with
      // nothing scheduled to correct it.
      if conv.pull_request is Some(probe) &&
        probe.probing &&
        probe.branch == branch {
        let pull_request = Some({ ..probe, stale: true, })
        return (
          @cmd.none,
          model.replace_conversation({ ..conv, pull_request, }),
        )
      }
      probe_pull_request(dispatch, model, channel, conv, branch)
    }
    PullRequestLoaded(
      session~,
      branch~,
      generation~,
      queried~,
      pull_request~,
      compare_url~
    ) => {
      guard model.find_conversation(channel, session) is Some(conv) else {
        return (@cmd.none, model)
      }
      // Matched by which request this answers, not by branch: a checkout that
      // moves X → Y → X leaves two lookups for X in flight, and if the newer
      // settles first, matching by name would let the older overwrite it.
      guard generation == conv.pull_request_generation else {
        return (@cmd.none, model)
      }
      // Read before the answer overwrites it: whether a refresh landed while
      // this lookup was in flight.
      let stale = conv.pull_request is Some(probe) && probe.stale
      // Labelled with the branch the host actually read from `HEAD`. When the
      // checkout moved mid-flight the two differ, and the answer is filed
      // under what it describes — where `settled_probe` hides it until the
      // branch chip catches up, instead of showing it against this one.
      let settled : PullRequestProbe = {
        branch: queried.unwrap_or(branch),
        probing: false,
        stale: false,
        pull_request,
        compare_url,
      }
      let conv = { ..conv, pull_request: Some(settled), }
      // A refresh arrived while this lookup was in flight: its answer predates
      // that refresh, so run one more against the branch now checked out.
      if stale && conv.branch is Some(current) && !current.is_empty() {
        return probe_pull_request(dispatch, model, channel, conv, current)
      }
      let model = model.replace_conversation(conv)
      // This answer may have named a base nobody knew when the diffstat beside
      // it was measured — the first pull request a session sees, or one that
      // has been retargeted since. Until it is measured again the popover
      // reports a span from the wrong place, which on a stacked pull request
      // is not a rounding error but the whole branch below this one. Measuring
      // again settles the hint, so this asks at most once per base.
      guard conv.settled_probe() is Some(probe) &&
        probe.pull_request is Some(answer) &&
        conv.diffstat_hint != Some(answer.base) else {
        return (@cmd.none, model)
      }
      probe_branch(
        dispatch,
        model,
        channel,
        session,
        model.conversation_root(conv),
      )
    }
    Started(
      run_id~,
      session~,
      model=selected_model,
      max_steps~,
      session_root~,
      submission_id~
    ) => {
      // This run's durable store, classified exactly the way a commit's root
      // is: Started precedes the first commit, so on a fresh connection this
      // is the placement the conversation is born with — and the projects
      // registry it would otherwise be resolved against may still be in
      // flight. A rootless legacy event has no store to classify.
      let started_project = if dev.bridge is Connected &&
        session_root is Some(root) {
        dev.placement_for_store_root(root)
      } else {
        dev.project_for_session_root(session_root)
      }
      // A delete tombstone outranks unversioned list replies and replayed
      // commits, but it must not hide a later same-id incarnation forever.
      // Started precedes every commit of an accepted run and carries the
      // host-selected durable store, so it is the first exact creation fact
      // that can safely retire the tombstone. Rootless legacy events cannot
      // distinguish same-id records in different stores and leave it intact.
      let model = match (session_root, started_project) {
        (Some(_), Some(workspace)) => {
          let key : ArchiveRecordKey = { session, workspace, }
          if dev.archive_override(key) is Some(ArchiveDeleted) {
            model.with_archive_override(channel, key, ArchiveLive)
          } else {
            model
          }
        }
        _ => model
      }
      // A run another client started may reach us with no local conversation
      // for its session (an `agent.runs` resync on a fresh page, or a live
      // start for a session this client never opened): materialize one, so
      // the run is trackable — streamable, cancellable, steerable — from
      // every client, not just the one that sent the prompt. A run this
      // client sent is already `Starting` when its `started` arrives (the
      // send handler flips the phase before the request leaves). Repeating
      // the same open id is idempotent; a distinct id replacing a stale open
      // run is foreign and first settles that old run's transient state.
      let existing = match model.find_conversation(channel, session) {
        Some(conv) => conv
        None => {
          // A conversation is created inside a project. With neither the
          // run's own store nor a listing to place this session, there is no
          // directory to track it in and no store to read it from, so the
          // run is left alone rather than materialized nowhere.
          guard (match started_project {
              Some(project) => Some(project)
              None => model.session_project(channel, session)
            })
            is Some(project) else {
            return (@cmd.none, model)
          }
          empty_conversation(
            channel,
            session,
            project,
            // A conversation this page is meeting for the first time takes
            // the tier its run is on — better evidence than the default,
            // and no choice exists yet to contradict it. A remembered choice
            // still outranks it: that is what the user meant to send next,
            // while the run may have been started elsewhere. A conversation
            // the page already holds keeps its own tier — see below.
            model=model
              .remembered_model(channel, session)
              .unwrap_or(selected_model),
          )
        }
      }
      let existing = match started_project {
        Some(project) =>
          {
            ..existing,
            workspace: dev.conversation_workspace(
              project,
              session,
              existing.workspace,
            ),
          }
        // A rootless legacy event asserts nothing: the run's own store is
        // authoritative for where the record lives, but an event that names
        // none must not move a placement the user chose. That reconcile
        // belongs to the session list.
        None => existing
      }
      // An automatically promoted follow-up is still transient until this
      // ordinary Started boundary. Retire its in-memory queue row here; the
      // corresponding User commit is the first durable representation of it.
      let existing = if submission_id is Some(id) &&
        existing.queued_inputs.iter().any(item => item.id == id) {
        let (without_queue, _) = existing.remove_queued_input(id)
        {
          ..without_queue,
          pending_steers: without_queue.pending_steers.filter(input => {
            input.submission_id != id
          }),
        }
      } else {
        existing
      }
      let owned = submission_id is Some(id) &&
        existing.has_initial_submission(id)
      let current_start = submission_id is Some(id) &&
        existing.run is Starting(submission_id=current) &&
        current == id
      let same_open = existing.run is Open(run_id=current, ..) &&
        current == run_id
      let conv = existing
      let (conv, foreign, stale_terminal) = match conv.run {
        Starting(..) if owned && current_start => (conv, false, false)
        // A foreign run starting says nothing about this client's own start,
        // which is still in flight and still owns its receipt path — a late
        // rejection must remain able to restore that draft.
        Starting(..) => (conv, true, false)
        Open(run_id=current, ..) if current == run_id => (conv, false, false)
        Open(run_id=previous_run, ..) =>
          (
            conv.clear_streams().forget_steers_for_run(previous_run),
            true,
            false,
          )
        NoRun(..) if existing.last_run_id is Some(last) && last == run_id =>
          (conv, false, true)
        NoRun(..) => (conv, true, false)
      }
      // The prompt bubble is not appended at this lifecycle boundary. Durable
      // transcript snapshots and `session.event` commits are its only sources.
      // A foreign run means the store holds a lifecycle boundary this client
      // cannot infer from item kinds: a delayed User may still belong to the
      // prior run as a steer. Re-read active and background conversations
      // alike; commits buffer until that snapshot establishes the new run's
      // terminal floor. If an older read is already in flight, mark one
      // follow-up generation: its pre-Started cut may drain commits, but may
      // not establish this run's floor.
      // Every newly observed Started boundary gets a post-Started snapshot,
      // including an owned local start. External/CLI turns may have advanced
      // the store while this page was idle without a follower broadcasting
      // them; reusing Send's stale terminal floor would let that older
      // terminal be mistaken for this run's. The host admits this Started
      // only after its predecessor's final drain, so this read is the first
      // safe place to establish the new floor.
      let refresh = foreign || current_start
      let run = if stale_terminal {
        conv.run
      } else {
        match conv.run {
          Open(run_id=current, stage~) if current == run_id =>
            Open(run_id=current, stage~)
          _ => Open(run_id~, stage=Opened)
        }
      }
      let sync = if refresh &&
        conv.sync
        is Reloading(generation~, attempt~, buffered~, reload_after_current=_) {
        Reloading(generation~, attempt~, buffered~, reload_after_current=true)
      } else {
        conv.sync
      }
      // A Started that opens a different run starts its turn from nothing:
      // the fragment, sub-run lanes and token count the previous turn
      // accumulated belong to that turn, not this one. A repeat of the open
      // run's Started, or a late one for a run already settled, keeps what it
      // has.
      let turn : RunState = if stale_terminal || same_open {
        conv.turn
      } else {
        RunState::for_run(conv.durable_frontier())
      }
      // `foreign` is exactly the question the elapsed span needs answered: a
      // run this page did not submit and wait for has an age that started
      // before we were watching. Keeping the previous run's start would date
      // the new one from a moment it never had; the span is simply omitted
      // until a submit of ours establishes one.
      let run_started_ms = if foreign { None } else { conv.run_started_ms }
      let conv = {
        ..conv,
        run,
        turn,
        run_started_ms,
        sync,
        // The tier is deliberately NOT re-established from the run. A start
        // is always older than the composer: the user may have flipped the
        // chip for the next turn while this one was still being spawned, and
        // a turn another client started says nothing about what this user
        // intends to send. The chip means "what your next turn runs on", so
        // only the chip changes it.
        last_run_id: Some(run_id),
      }
      let (updated, generation) = if refresh {
        model.begin_transcript_reload(conv)
      } else {
        (model.replace_conversation(conv), None)
      }
      // Probe the root projected from the reconciled conversation.
      let (branch_cmd, updated) = probe_branch(
        dispatch,
        updated,
        channel,
        session,
        updated.conversation_root(conv),
      )
      let commands = [branch_cmd]
      if generation is Some(generation) {
        commands.push(
          session_snapshot_command(
            dispatch, channel, updated, session, generation, false,
          ),
        )
      }
      // A run is what makes a conversation durable, so this is where its tier
      // gets pinned — the chip is not the only way to acquire one. A tier
      // merely inherited from the page default and then used would otherwise
      // stay unremembered, and the conversation would come back on whatever
      // default an unrelated chat has moved to since. Re-pinning the same
      // tier only reorders the list, so consecutive turns write once.
      let pinned = updated.remember_model(channel, session, conv.engine_model)
      if pinned.conversation_models != model.conversation_models {
        commands.push(
          save_conversation_model(
            conversation_model_key(channel, session),
            conv.engine_model,
          ),
        )
      }
      let updated = pinned
      // The model rode in on the conversation above; max steps is still one
      // global setting, so sync it only when this start belongs to the
      // conversation on screen. A slow background start (the user switched
      // chats mid-spawn) must not overwrite a value the user has since
      // changed for the now-active conversation.
      if channel == updated.focused && session == updated.active_session {
        (@cmd.batch(commands), { ..updated, max_steps: max_steps.to_string(), })
      } else {
        (@cmd.batch(commands), updated)
      }
    }
    RunsLoaded(
      runs~,
      settled~,
      approvals~,
      live~,
      frontier~,
      connection_generation~
    ) => {
      guard connection_generation == dev.connection_generation else {
        return (@cmd.none, model)
      }
      // Accept the snapshot as one state transition. No intermediate replayed
      // Started row is rendered, and a later BridgeReady invalidates both its
      // positive rows and its negative frontier together.
      let commands : Array[@cmd.Cmd] = []
      let mut next = model
      let accepted_settlements : Array[RecoveredSettlement] = []
      let settled_sessions : Array[String] = []
      for settlement in settled {
        if !accepted_settlements
          .iter()
          .any(item => item.run_id == settlement.run_id) &&
          model.matched_settlement_frontier(channel, frontier, settlement)
          is Some(_) {
          accepted_settlements.push(settlement)
          if !settled_sessions.contains(settlement.session) {
            settled_sessions.push(settlement.session)
          }
        }
      }
      // Validate positive rows against the same immutable request-time model,
      // before a predecessor settlement mutates it. One atomic host snapshot
      // may legitimately contain completed r1 and active successor r2 for the
      // same session; both pieces must survive that hand-off.
      let accepted_runs : Array[RecoveredRun] = []
      let admitted_run_sessions : Array[String] = []
      for run in runs {
        let duplicates_settlement = accepted_settlements
          .iter()
          .any(item => item.session == run.session && item.run_id == run.run_id)
        if !duplicates_settlement &&
          !admitted_run_sessions.contains(run.session) &&
          model.matches_run_snapshot_frontier(channel, frontier, run.session) {
          accepted_runs.push(run)
          admitted_run_sessions.push(run.session)
        }
      }
      // A completion selected by this request is stronger than mere absence.
      // Replay it before active rows and negative settlement, but only while
      // the page still has the exact owner captured at request time. A
      // Starting owner first gains the host run id so the ordinary Finished
      // transition can retire or restore its exact initial submission.
      // A session can carry an older run selector and a newer unbound prompt
      // selector at the same cut. Apply run-owned evidence first, then the
      // submission-owned completion that controls the current composer gate.
      let ordered_settlements : Array[RecoveredSettlement] = []
      for settlement in accepted_settlements {
        if model.matched_settlement_frontier(channel, frontier, settlement)
          is Some(SettlementByRun) {
          ordered_settlements.push(settlement)
        }
      }
      for settlement in accepted_settlements {
        if model.matched_settlement_frontier(channel, frontier, settlement)
          is Some(SettlementBySubmission(_)) {
          ordered_settlements.push(settlement)
        }
      }
      for settlement in ordered_settlements {
        guard model.matched_settlement_frontier(channel, frontier, settlement)
          is Some(owner) else {
          continue
        }
        if owner is SettlementBySubmission(submission_id) &&
          next.find_conversation(channel, settlement.session) is Some(conv) {
          // The settlement names the run this submission opened, so the
          // prompt in flight finally has its answer.
          let (settled, _) = conv.settle_pending_prompt(submission_id)
          next = next.replace_conversation({
            ..settled,
            run: Open(run_id=settlement.run_id, stage=Opened),
            turn: RunState::empty(),
            last_run_id: Some(settlement.run_id),
          })
        }
        let (cmd, updated) = update_device_msg(
          dispatch,
          channel,
          Finished(
            run_id=settlement.run_id,
            status=settlement.status,
            answer=None,
          ),
          next,
        )
        commands.push(cmd)
        next = updated
      }
      for run in accepted_runs {
        let (cmd, updated) = update_device_msg(
          dispatch,
          channel,
          Started(
            run_id=run.run_id,
            session=run.session,
            model=run.model,
            max_steps=run.max_steps,
            session_root=run.session_root,
            submission_id=run.submission_id,
          ),
          next,
        )
        commands.push(cmd)
        next = updated
      }
      // Do not let the older negative-set logic re-anchor a completion that
      // just supplied an exact durable frontier (notably sequence zero).
      let unsettled_frontier = frontier.filter(captured => {
        !settled_sessions.contains(captured.session)
      })
      let (settled_cmd, settled) = update_device_msg(
        dispatch,
        channel,
        RunsSettled(live~, frontier=unsettled_frontier),
        next,
      )
      commands.push(settled_cmd)
      // Standing questions land last, once every conversation in this snapshot
      // has the run phase the snapshot gives it.
      //
      // Two passes, because they answer two different questions of two
      // different sets. Seeding asks what the reply says exists, so it iterates
      // the REPLY — a fresh page captures an empty frontier (`BridgeReady`
      // issues this alongside `session.list`, before any conversation exists),
      // and iterating the frontier would drop every question on the one path
      // the replay was built for. Retiring asks what this page was showing that
      // the reply lacks, which only the frontier knows.
      let captured_by_session : Map[String, RunSnapshotFrontier] = Map([])
      for row in frontier {
        captured_by_session[row.session] = row
      }
      let mut seeded = settled
      for recovered in approvals {
        guard seeded.find_conversation(channel, recovered.session) is Some(conv) else {
          continue
        }
        let showing = conv.pending_approval.map(pending => pending.id)
        // Unchanged since the request went out — a session absent from the
        // frontier captured nothing, so it must be showing nothing now.
        // Anything else is newer truth than the reply, live events having
        // landed meanwhile.
        let captured = match captured_by_session.get(recovered.session) {
          Some(row) => row.pending_approval_id
          None => None
        }
        guard showing == captured else { continue }
        // And the question must belong to the run this conversation has open.
        // The check above compares two endpoints, so it cannot see a value
        // that changed and changed back: with nothing captured, one question
        // asked and resolved in flight, and its run replaced by a successor,
        // both endpoints read `None` and this dead question would be seeded
        // onto the new run — where answering it is rejected and the failure
        // handler puts the buttons back, leaving a prompt that can never be
        // dismissed. A question only exists inside a turn, so a conversation
        // with no open run has none to restore.
        guard conv.run is Open(run_id~, ..) &&
          recovered.approval.run_id == Some(run_id) else {
          continue
        }
        // Already on screen unchanged: leave it, answered flag and all. This
        // resync runs on every reconnect, not only after a reload, so handing
        // the buttons back to a card the user has already answered would be
        // one question with two decisions.
        if showing is Some(id) && id == recovered.approval.id {
          continue
        }
        seeded = seeded.replace_conversation({
          ..conv,
          pending_approval: Some(recovered.approval),
        })
      }
      // Retire: a question this page was showing that the reply lacks was
      // answered while the page was away — by another client, or by the run
      // ending. Its `approval_resolved` is gone for good (reconnect is resync;
      // transients are not replayed), so nothing else will ever take that card
      // down, and pressing it sends a decision the engine's desk discards.
      //
      for captured in frontier {
        guard captured.pending_approval_id is Some(captured_id) else {
          continue
        }
        if approvals.iter().any(item => item.approval.id == captured_id) {
          continue
        }
        guard seeded.find_conversation(channel, captured.session) is Some(conv) else {
          continue
        }
        if conv.pending_approval is Some(current) && current.id == captured_id {
          seeded = seeded.replace_conversation({
            ..conv,
            pending_approval: None,
          })
        }
      }
      (@cmd.batch(commands), seeded)
    }
    RunsSettled(live~, frontier~) => {
      // A conversation still showing an open run the host no longer has: the
      // run ended while this client was away, and its terminal event will
      // never be replayed, so the phase settles here. How it ended is
      // unknowable (`ended=None`); the verdict text lives in the store and
      // arrives through the usual reads — the active conversation reloads at
      // `BridgeReady`, the rest when opened. Only a lifecycle state that still
      // exactly matches this request's per-session frontier may settle; live
      // Started/Finished transitions received meanwhile are newer truth.
      let settled = model.conversations.map(conv => {
        if conv.device != channel {
          return conv
        }
        for captured in frontier {
          if captured.session == conv.session_id {
            return match captured.state {
              SnapshotOpen(run_id~) if conv.run is Open(run_id=current, ..) &&
                current == run_id &&
                !live.contains(run_id) =>
                // The runs reply proves this run is over. Its submissions can
                // no longer acquire a receipt, so they end with it; the
                // transcript, not a local notice, says what the run recorded.
                {
                  ..conv.clear_streams().forget_steers_for_run(run_id),
                  run: NoRun(ended=None),
                  last_run_id: Some(run_id),
                }
              SnapshotIdle(last_run_id=Some(run_id)) if conv.run is NoRun(..) &&
                conv.last_run_id is Some(current) &&
                current == run_id =>
                // The run this conversation last owned is idle at the host,
                // so nothing it carried is still in flight.
                conv.forget_steers_for_run(run_id)
              SnapshotStarting(submission_id~) if conv.run
                is Starting(submission_id=current) &&
                current == submission_id => {
                // The host has no record of this start, so the prompt never
                // opened a run. Close the local lifecycle and let the entry
                // go with it.
                let (settled, _) = conv.settle_pending_prompt(submission_id)
                { ..settled.clear_streams(), run: NoRun(ended=None), }
              }
              _ => conv
            }
          }
        }
        conv
      })
      (@cmd.none, { ..model, conversations: settled, })
    }
    Engine(run_id, event, session~) => {
      // Compaction and background notices happen between turns, so their
      // events arrive after the run that owned `run_id` cleared
      // `active_run_id` — or with no run id at all (an engine spawned just
      // to compact). The host stamps them with their session, which covers
      // that case too; the conversation that last held the id remains the
      // fallback for unstamped events.
      let conv = if run_id is Some(id) &&
        model.conversation_by_run(channel, id) is Some(conv) {
        Some(conv)
      } else if is_steer_receipt(event) && run_id is Some(id) {
        // Host settling receipts may intentionally trail the terminal event;
        // an even newer Started can already have replaced last_run_id. Prefer
        // the exact pending-steer match before the legacy run fallback.
        let exact = match event {
          SteerApplied(submission_id=Some(submission_id), ..) =>
            model.conversation_by_pending_steer(channel, submission_id, id)
          SteerDropped(submission_id=Some(submission_id), ..) =>
            model.conversation_by_pending_steer(channel, submission_id, id)
          _ => None
        }
        if exact is Some(conv) {
          Some(conv)
        } else {
          model.conversation_by_last_run(channel, id)
        }
      } else if is_idle_event(event) {
        if session is Some(session) &&
          model.find_conversation(channel, session) is Some(conv) {
          Some(conv)
        } else if run_id is Some(id) {
          model.conversation_by_last_run(channel, id)
        } else {
          None
        }
      } else {
        None
      }
      if conv is Some(conv) {
        let approval_notification = approval_system_notification(
          channel, run_id, event,
        )
        let (report, next) = apply_engine_event(conv, event, run_id)
        let updated = model.replace_conversation(next)
        // The finish is a sub-run child's terminal refresh boundary, and the
        // only one it has. The host cancels the progress probe here without a
        // final poll, and the probe sleeps before it reads — so everything the
        // child wrote since the last tick, which is where its report lands,
        // reaches a reader watching that transcript through this event or not
        // at all.
        let (finished_cmd, updated) = if event is SubrunClosed(id~, ..) {
          refresh_visible_subrun_child(
            dispatch,
            channel,
            "\{conv.session_id}-\{id}",
            updated,
          )
        } else {
          (@cmd.none, updated)
        }
        let (report_cmd, updated) = if report is Some(text) {
          updated.notify_error(dispatch, text)
        } else {
          let command = match approval_notification {
            Some(notification) => notification.command()
            None => @cmd.none
          }
          (command, updated)
        }
        (@cmd.batch([finished_cmd, report_cmd]), updated)
      } else {
        (@cmd.none, model)
      }
    }
    // Everything else the panel owns (tree, viewer, diagnostics) is the
    // fileeditor package's business; route it there and adopt its state.
    StartResponded(session~, submission_id~, run_id~, status~, exit_code~) => {
      guard model.find_conversation(channel, session) is Some(conv) &&
        conv.has_initial_submission(submission_id) else {
        return (@cmd.none, model)
      }
      // The id-bearing reply always settles its exact submission, even when
      // Finished A and Started B overtook A's RPC response. Only lifecycle
      // mutation remains conditional on A still owning the conversation.
      let owns_lifecycle = match conv.run {
        Starting(submission_id=current) => current == submission_id
        Open(run_id=current, ..) => current == run_id
        NoRun(..) => conv.last_run_id is Some(last) && last == run_id
      }
      // A prompt is sent once. Whatever the host answered, this submission's
      // entry has served its purpose — it existed to recognize this reply —
      // and nothing downstream reconciles it against the record.
      let (conv, _) = conv.settle_pending_prompt(submission_id)
      if status == "accepted" {
        let missed_started = owns_lifecycle &&
          conv.run is Starting(submission_id=current) &&
          current == submission_id
        let late_abnormal = conv.run is NoRun(..) &&
          conv.last_run_id is Some(owner) &&
          owner == run_id &&
          !(conv.run is NoRun(ended=Some(RunFinished(outcome))) &&
          outcome is (Completed | ContextYield | MaxStepsExhausted))
        let settled = conv
        // The reply still opens the lifecycle when its Started notification
        // was delayed. A very short run may already be finished; never
        // resurrect that settled phase.
        let next = if owns_lifecycle {
          match settled.run {
            NoRun(..) => settled
            Open(run_id=current, stage~) if current == run_id =>
              {
                ..settled,
                run: Open(run_id=current, stage~),
                last_run_id: Some(run_id),
              }
            // This page submitted and is now being told the run it was
            // waiting for opened: the submit is still where the user's wait
            // began, so the span carries over.
            Starting(..) =>
              {
                ..settled,
                run: Open(run_id~, stage=Opened),
                last_run_id: Some(run_id),
              }
            // Some other run opened — reconnect adopting one already in
            // flight, or a turn started elsewhere. Its age is not this page's
            // to know, and the previous run's start would be a lie.
            _ =>
              {
                ..settled,
                run: Open(run_id~, stage=Opened),
                last_run_id: Some(run_id),
                run_started_ms: None,
              }
          }
        } else {
          settled
        }
        let (updated, generation) = if missed_started || late_abnormal {
          model.ensure_transcript_reload_after_current(next)
        } else {
          (model.replace_conversation(next), None)
        }
        let (branch_cmd, updated) = probe_branch(
          dispatch,
          updated,
          channel,
          session,
          updated.conversation_root(settled),
        )
        let commands = [branch_cmd]
        if generation is Some(generation) {
          commands.push(
            session_snapshot_command(
              dispatch, channel, updated, session, generation, false,
            ),
          )
        }
        (@cmd.batch(commands), updated)
      } else {
        // The process result closes a still-live run. Whether its User append
        // reached the store is the record's question, not this reply's, and
        // the reload below is what answers it.
        ignore(status)
        ignore(exit_code)
        let closed = if owns_lifecycle {
          conv.forget_steers_for_run(run_id)
        } else {
          conv
        }
        let next = if owns_lifecycle {
          match closed.run {
            Starting(..) | Open(..) =>
              {
                ..closed.clear_streams(),
                run: NoRun(ended=Some(RunFailed)),
                last_run_id: Some(run_id),
              }
            NoRun(..) => closed
          }
        } else {
          closed
        }
        let (model, generation) = model.ensure_transcript_reload_after_current(
          next,
        )
        let (sessions, model) = request_sessions_refresh(
          dispatch, channel, model,
        )
        let commands = [
          sessions,
          fetch_runs(
            dispatch,
            channel,
            model.run_snapshot_frontier(channel),
            dev.connection_generation,
          ),
        ]
        if generation is Some(generation) {
          commands.push(
            session_snapshot_command(
              dispatch, channel, model, session, generation, false,
            ),
          )
        }
        (@cmd.batch(commands), model)
      }
    }
    StartUndelivered(session~, submission_id~, message~) =>
      if model.find_conversation(channel, session) is Some(conv) {
        // The response path failed, so whether the host took this prompt is
        // unknowable here. Nothing guesses on the client's behalf: the entry
        // ends and the reload below shows what the record actually holds.
        ignore(message)
        let owns_submission = conv.has_initial_submission(submission_id)
        let (settled, changed) = conv.settle_pending_prompt(submission_id)
        if !owns_submission {
          (@cmd.none, model)
        } else {
          let next = if conv.run is Starting(submission_id=current) &&
            current == submission_id {
            { ..settled.clear_streams(), run: NoRun(ended=Some(RunFailed)), }
          } else {
            // A Started push/response for another run won the race. An
            // uncorrelated transport failure must never close that open run.
            settled
          }
          let updated = model.replace_conversation(next)
          let (sessions, updated) = request_sessions_refresh(
            dispatch, channel, updated,
          )
          let commands = [
            sessions,
            fetch_runs(
              dispatch,
              channel,
              updated.run_snapshot_frontier(channel),
              dev.connection_generation,
            ),
          ]
          if changed {
            commands.push(@cmd.none)
          }
          (@cmd.batch(commands), updated)
        }
      } else {
        (@cmd.none, model)
      }
    StartRejected(session~, submission_id~, message~) =>
      model.reject_start(dispatch, channel, session, submission_id, message)
    WorktreeSetupFailed(session~, submission_id~, message~) =>
      model.reject_start(dispatch, channel, session, submission_id, message)
    Error(run_id~, message~, diagnostics~, exit_code~) => {
      // Agent-side semantic errors are lifecycle-only here; their durable
      // status is classified by the subsequent Finished event. Process
      // diagnostics carry `exit_code` and have no durable twin.
      let conv = if run_id is Some(run_id) {
        if model.conversation_by_run(channel, run_id) is Some(conv) {
          Some(conv)
        } else {
          model.conversation_by_last_run(channel, run_id)
        }
      } else if channel == model.focused {
        model.active_conversation()
      } else {
        None
      }
      if conv is Some(conv) {
        if run_id is Some(_) && exit_code is None {
          return (@cmd.none, model)
        }
        let content = if diagnostics is Some(diagnostics) &&
          !diagnostics.is_blank() {
          "\{message}\n\n\{diagnostics}"
        } else {
          message
        }
        // Neither kind belongs to a durable event: the record will never
        // carry either, and the transcript is where durable events go. Both
        // are reported as toasts, and the top bar's `Errored` status is what
        // stands once the toast dismisses itself.
        let settled = model.replace_conversation(
          if conv.run is NoRun(..) {
            { ..conv, run: NoRun(ended=Some(RunErrored)), }
          } else {
            conv
          },
        )
        settled.notify_error(dispatch, content)
      } else {
        (@cmd.none, model)
      }
    }
    CompactRejected(session~, message~) =>
      if model.find_conversation(channel, session) is Some(conv) {
        model
        .replace_conversation({ ..conv, compaction: NotCompacting, })
        .notify_error(dispatch, message)
      } else {
        (@cmd.none, model)
      }
    GoalRejected(session~, command~, draft~, message~) =>
      if model.find_conversation(channel, session) is Some(conv) {
        // A rejection acts only on the send it answers, and only while that
        // send is still the one in flight. The row keeps its actions while a
        // command is out, so the user can send a second over the first — and
        // the second may be the same text, or Clear again, so only the id
        // separates them.
        //
        // Anything else is a reply that arrived too late to mean what it
        // says. Either a newer send replaced this one, or the record already
        // settled whatever was outstanding — including by carrying this very
        // text, set from somewhere else. In every such case the durable goal
        // has already been decided, so retiring the slot would drop a live
        // successor and reopening the editor would claim a failure that is
        // not what this conversation now stands at. The toast still reports
        // it; nothing here is silent.
        let restored = if !(conv.goal_pending is Some(pending) &&
          pending.id == command) {
          conv
        } else if draft is Some(draft) && conv.goal_edit is None {
          // Hand the goal text back, the way a rejected prompt restores its
          // draft: nothing durable will ever carry it, so losing it here
          // loses it for good. Only when this conversation has not claimed
          // goal mode since — a newer edit is the user's, not this dead
          // request's.
          { ..conv, goal_edit: Some({ draft, }), goal_pending: None, }
        } else {
          { ..conv, goal_pending: None, }
        }
        model.replace_conversation(restored).notify_error(dispatch, message)
      } else {
        (@cmd.none, model)
      }
    GoalUndelivered(session~, command~, draft~, message~) =>
      if model.find_conversation(channel, session) is Some(conv) &&
        conv.goal_pending is Some(pending) &&
        pending.id == command {
        // Only while this send is still the one in flight. It retires
        // nothing, but "the fate of this text is unknown" is still a claim
        // about the world, and it stops being true the moment the record
        // settles the send — the socket can die after the commit arrives and
        // before the reply does — or a newer send replaces it.
        //
        // While it is true, the request stays in flight: a marker, or the
        // reload that follows the reconnect, is what settles it. So the text
        // cannot come back to the editor — it would claim the goal is unset,
        // and a resend over a command the host may already hold only earns a
        // refusal. Nothing is lost by leaving it there: the request in flight
        // still carries it, and that is what the goal row shows and what
        // reopening the editor seeds from.
        ignore(draft)
        let detail = if conv.goal_pending is Some({ request: Clearing, .. }) {
          " — check the goal row before clearing it again"
        } else {
          " — check the goal row before setting it again"
        }
        model
        .replace_conversation(conv)
        .notify_error(
          dispatch,
          "Goal delivery could not be confirmed (" + message + ")" + detail,
        )
      } else {
        (@cmd.none, model)
      }
    Finished(run_id~, status~, answer~) =>
      if (if model.conversation_by_run(channel, run_id) is Some(conv) {
          Some(conv)
        } else {
          // RunsSettled may have closed the phase first; Finished is still the
          // authoritative outcome for the conversation that last owned it.
          model.conversation_by_last_run(channel, run_id)
        })
        is Some(conv) {
        let first_finish = !(conv.run is NoRun(ended=Some(RunFinished(_))) &&
          conv.last_run_id is Some(last) &&
          last == run_id)
        // Missing receipts are not guessed dropped. Keep exact-id ownership
        // briefly and show a truthful unconfirmed notice behind the durable
        // terminal boundary; a trailing receipt may still settle it.
        //
        // The run is over, so nothing it carried can still acquire a receipt.
        // Whether each submission reached the store is the record's question;
        // the transcript answers it without a local placeholder.
        let outcome = RunOutcome::parse(status)
        let settled_inputs = conv.clear_streams().forget_steers_for_run(run_id)
        // A dead/aborted serve process loses its controller-owned queue. A
        // normal terminal keeps it for the Started boundary that immediately
        // promotes the next ordinary prompt.
        let settled_inputs = match outcome {
          Aborted | RunFailed | Unknown(_) =>
            {
              ..settled_inputs,
              queued_inputs: [],
              queue_edit_id: None,
              pending_steers: settled_inputs.pending_steers.filter(input => {
                input.behavior is FollowupSteer
              }),
            }
          Completed | ContextYield | MaxStepsExhausted => settled_inputs
        }
        // A question belonging to this run goes with it. The engine settles
        // its own on the way out, so what reaches here is the engine that
        // could not — a killed process emits no `approval_resolved` — and
        // nothing else would ever retire the card, there being no deadline
        // behind the question. The host drops its copy on the same evidence.
        let settled_inputs = if settled_inputs.pending_approval
          is Some({ run_id: Some(owner), .. }) &&
          owner == run_id {
          { ..settled_inputs, pending_approval: None, }
        } else {
          settled_inputs
        }
        let base = {
          ..settled_inputs,
          run: NoRun(ended=Some(RunFinished(outcome))),
          last_run_id: Some(run_id),
          // A finish the user watched happen needs no reminder. Every other
          // completion is unread until its transcript is actually visible.
          unseen_finish: !model.conversation_is_visible(
            conv.device,
            conv.session_id,
          ),
        }
        // The finished run just appended to the durable store, so the
        // sidebar list (and this conversation's title) may have changed —
        // and the turn may have created the repository or switched branches.
        let mut next = model.replace_conversation(base)
        let (sessions, requested) = request_sessions_refresh(
          dispatch, channel, next,
        )
        next = requested
        let (branch_cmd, probed) = probe_branch(
          dispatch,
          next,
          channel,
          conv.session_id,
          next.conversation_root(conv),
        )
        next = probed
        let commands = [sessions, branch_cmd]
        // Only the embedded desktop page owns system notifications. Remote
        // browser pages never have the notification extension, and replaying
        // the same Finished boundary must not post a second notification.
        if first_finish && channel is Local {
          commands.push(
            FinishedSystemNotification::{ run_id, status, answer, }.command(),
          )
        }
        // The turn's edits routinely land in files the editor panel never
        // shows — paths its pruned watcher does not cover — so the settled
        // boundary re-checks the active MoonBit file's module. The panel's
        // owner fence drops a finish from a conversation it is not showing.
        if first_finish {
          let (panel_cmd, panel_next) = update_msg(
            dispatch,
            FileEditor(RunSettled(owner={ channel, session: conv.session_id, })),
            next,
          )
          commands.push(panel_cmd)
          next = panel_next
        }
        // A run that recorded nothing needs this pass as much as any other:
        // the read answers "this conversation is empty" rather than failing,
        // so the reconciliation ends in Synced either way.
        if first_finish && !base.session_id.is_empty() {
          match base.sync {
            Reloading(generation~, attempt~, buffered~, reload_after_current~) =>
              // The current snapshot may have been captured before this
              // Finished boundary. Do not start a concurrent read; remember
              // to run exactly one fresh generation after it settles.
              if !reload_after_current {
                next = next.replace_conversation({
                  ..base,
                  sync: Reloading(
                    generation~,
                    attempt~,
                    buffered~,
                    reload_after_current=true,
                  ),
                })
              }
            Synced | ReloadFailed(..) => {
              let (reloading, generation) = next.begin_transcript_reload(base)
              next = reloading
              if generation is Some(generation) {
                commands.push(
                  session_snapshot_command(
                    dispatch,
                    channel,
                    next,
                    base.session_id,
                    generation,
                    false,
                  ),
                )
              }
            }
          }
        }
        (@cmd.batch(commands), next)
      } else {
        // Even when this page missed both Started and every commit, the list
        // can reveal the finished durable session for a later open.
        request_sessions_refresh(dispatch, channel, model)
      }
  }
}

// Purity and state-transition tests for the update handlers that back the
// streaming, session, and multi-conversation integration. Commands are
// opaque, so the tests assert on the returned model only.

///|
fn test_dispatch() -> @cmd.Emit[Msg] {
  Emit(_ => @cmd.none)
}

///|
/// Test-only: a device-scoped message as the page's one channel delivers it.
fn on_home(msg : DeviceMsg) -> Msg {
  FromDevice(@interop.ChannelId::Local, msg)
}

///|
/// Test-only: `update` with a device message on the page's one channel.
fn update_dev(
  dispatch : @cmd.Emit[Msg],
  msg : DeviceMsg,
  model : Model,
) -> (@cmd.Cmd, Model) {
  update(dispatch, on_home(msg), model)
}

///|
/// A frontend resource fixture with the same validation as protocol input.
/// Keeping it as a channel method makes the owning device explicit in tests.
fn @interop.ChannelId::test_resource(
  self : @interop.ChannelId,
  path : String,
) -> @common.Uri raise {
  guard @resource.of_path(self, path) is Some(resource) else {
    fail("test resource path was invalid: \{path}")
  }
  resource
}

///|
/// The project every conversation fixture on this device belongs to. A
/// conversation is workspace-owned now, so the shared test model attaches
/// one project and puts its conversation in it.
fn @interop.ChannelId::test_project(self : @interop.ChannelId) -> @common.Uri {
  // Valid by construction; a total fixture keeps every test using
  // `test_model` free of a synthetic error effect.
  match @resource.of_path(self, "/work") {
    Some(root) => root
    None => @common.Uri::file("/work")
  }
}

///|
/// The durable store the fixture conversation's records live in — the store
/// root a commit or start for a conversation in `test_project` carries.
/// Derived from that project so the two cannot drift apart.
fn @interop.ChannelId::test_store_root(
  self : @interop.ChannelId,
) -> @common.Uri {
  let path = self.test_project().path + "/.openseek"
  match @resource.of_path(self, path) {
    Some(root) => root
    None => @common.Uri::file(path)
  }
}

///|
/// The worktree registry mirror a placement needs before it resolves. Rows
/// stay empty: the fixture conversation works in the project root.
fn @interop.ChannelId::test_worktrees(
  self : @interop.ChannelId,
) -> ProjectWorktrees {
  { project: self.test_project(), rows: [], generation: 0, }
}

///|
fn test_conversation() -> Conversation {
  empty_conversation(
    @interop.ChannelId::Local,
    "desktop-test",
    @interop.ChannelId::Local.test_project(),
  )
}

///|
fn test_reloading(buffered : Array[BufferedCommit]) -> TranscriptSync {
  Reloading(generation=1, attempt=1, buffered~, reload_after_current=false)
}

///|
fn running_conversation() -> Conversation {
  { ..test_conversation(), run: Open(run_id="r7", stage=Opened), }
}

///|
fn test_model() -> Model {
  {
    ..initial_model()
    // The headless test runtime has no page location, so `initial_model()`
    // seeds no devices (and, looking like a browser, a console); every test
    // here runs desktop-shaped, on an explicit Local channel.
    ,
    devices: [
      {
        ..empty_device_state(@interop.ChannelId::Local),
        bridge: Connected,
        projects: [@interop.ChannelId::Local.test_project()],
        worktrees: [@interop.ChannelId::Local.test_worktrees()],
      },
    ],
    focused: @interop.ChannelId::Local,
    console: None,
    // The shared fixture represents a connected desktop after its initial
    // settings snapshot. Loading-state tests opt back into revision -1.
    host_settings_revision: 0,
    // BYOK means a ready app has a key saved: without one, the composer's
    // send gate stays shut and every submission test would first need to
    // configure an endpoint. Setup-flow tests load their own keyless
    // settings payloads instead.
    deepseek_key_saved: true,
    active_session: "desktop-test",
    conversations: [test_conversation()],
  }
}

///|
/// Test-only: the focused device's state; raising keeps a broken model a
/// test failure rather than a silent mismatch.
fn Model::dev(self : Model) -> DeviceState raise {
  guard self.focused_device() is Some(dev) else {
    fail("the model holds no focused device")
  }
  dev
}

///|
/// Test-only: the conversation on screen. A test that reads it has already
/// put one there, so its absence is a broken fixture; raising says so where
/// production code must instead take `active_conversation`'s `None` branch
/// and render onboarding.
fn Model::active(self : Model) -> Conversation raise {
  guard self.active_conversation() is Some(conv) else {
    fail("the model holds no active conversation")
  }
  conv
}

///|
/// Test-only: transform the focused device's state, e.g. seeding a session
/// list on `test_model()`.
fn Model::with_dev(
  self : Model,
  transform : (DeviceState) -> DeviceState,
) -> Model raise {
  self.replace_device(transform(self.dev()))
}

///|
/// Test-only: the durable rows the sidebar would show for `ids`, all in the
/// fixture project's store. Opening a conversation reads its store from its
/// row, so a test that opens one has to list it first.
fn Model::with_listed(self : Model, ids : Array[String]) -> Model raise {
  self.with_dev(dev => {
    ..dev,
    sessions: ids.map(id => {
      (
        {
          id,
          title: Some(""),
          workspace: @interop.ChannelId::Local.test_project(),
          workspace_name: "work",
          updated_at_ms: None,
        } : @transcript.SessionListItem)
    }),
  })
}

///|
fn sessions_loaded(
  items : Array[@transcript.SessionListItem],
  request_generation? : Int = 0,
) -> Msg {
  on_home(SessionsLoaded(items, connection_generation=0, request_generation~))
}

///|
/// A lane belongs to its turn. The finish bracket that retires it is not
/// replayed, so a dropped connection or an engine that dies mid-sub-run must
/// not leave a pulsing lane behind.
test "a lane outlives neither its run nor a missing finish bracket" {
  let conv = { ..test_conversation(), run: Open(run_id="r1", stage=Opened), }
  let (_, opened) = apply_engine_event(
    conv,
    SubrunOpened(id="sr-1", kind="explore", label="where is X"),
    Some("r1"),
  )
  inspect(opened.visible_subruns().length(), content="1")
  // The run settles without a finish bracket ever arriving.
  let settled = { ..opened, run: NoRun(ended=Some(RunFailed)), }
  inspect(settled.visible_subruns().length(), content="0")
  // And the stranded lane does not reappear inside the NEXT turn.
  let next_turn = { ..settled, run: Open(run_id="r2", stage=Opened), }
  inspect(next_turn.visible_subruns().length(), content="0")
}

///|
/// A captured sub-run already has a durable tool brief, so closing its live
/// lane must not report a second completion. An abnormal close has no
/// successful tool brief to explain it, and no durable event of its own, so it
/// is reported to the user directly.
test "sub-run completion reports only abnormal terminal status" {
  let conv = { ..test_conversation(), run: Open(run_id="r1", stage=Opened), }
  let (_, opened) = apply_engine_event(
    conv,
    SubrunOpened(id="sr-1", kind="explore", label="where is X"),
    Some("r1"),
  )
  let (captured_report, closed) = apply_engine_event(
    opened,
    SubrunClosed(id="sr-1", status="captured", steps=37, tokens=12_449),
    Some("r1"),
  )
  assert_true(captured_report is None)
  inspect(closed.visible_subruns().length(), content="0")
  // The successful tool brief is the only completion row.
  inspect(closed.messages.length(), content="0")
  let (_, reopened) = apply_engine_event(
    closed,
    SubrunOpened(id="sr-2", kind="review", label="check the change"),
    Some("r1"),
  )
  let (failure_report, failed) = apply_engine_event(
    reopened,
    SubrunClosed(id="sr-2", status="failed", steps=4, tokens=901),
    Some("r1"),
  )
  inspect(failed.visible_subruns().length(), content="0")
  // The failed tool has no successful brief and no durable event of its own,
  // so the failure is reported as a toast rather than as a transcript row.
  assert_true(
    failure_report is Some("review sr-2: failed · 4 step(s) · 901 tok"),
  )
}

///|
test "viewport resize flips the narrow flag and resets the sidebar" {
  let dispatch = test_dispatch()
  let (_, narrow) = update(dispatch, ViewportResized(width=390), test_model())
  assert_true(narrow.narrow)
  assert_false(narrow.sidebar_open)
  // Same side of the breakpoint: nothing moves (idempotent).
  let (_, same) = update(dispatch, ViewportResized(width=390), narrow)
  assert_true(same.narrow)
  assert_false(same.sidebar_open)
  let (_, wide) = update(dispatch, ViewportResized(width=1280), same)
  assert_false(wide.narrow)
  assert_true(wide.sidebar_open)
}

///|
test "the narrow drawer closes when navigation lands elsewhere" {
  let dispatch = test_dispatch()
  let (_, narrow) = update(dispatch, ViewportResized(width=390), test_model())
  let (_, opened) = update(dispatch, ToggleSidebar, narrow)
  assert_true(opened.sidebar_open)
  // Navigating to the Skills page from the drawer closes it; on the wide
  // layout the same navigation leaves the sidebar column alone.
  let (_, settled) = update(dispatch, OpenSkills, opened)
  assert_false(settled.sidebar_open)
  let (_, wide) = update(dispatch, ViewportResized(width=1280), settled)
  let (_, back) = update(dispatch, OpenSetup, wide)
  assert_true(back.sidebar_open)
}

///|
fn archived_loaded(
  items : Array[@transcript.SessionListItem],
  request_generation? : Int = 0,
) -> Msg {
  on_home(
    ArchivedLoaded(
      items,
      connection_generation=0,
      request_generation~,
      fresh_session="desktop-archive-replacement",
    ),
  )
}

///|
fn running_model() -> Model {
  test_model().replace_conversation(running_conversation())
}

///|
test "an approval notification click opens its local conversation" {
  let dispatch = test_dispatch()
  let remote : @interop.ChannelId = Remote("d-remote")
  let home = running_model()
  let model = {
    ..home,
    devices: [
      home.devices[0],
      { ..empty_device_state(remote), bridge: Connected, },
    ],
    focused: remote,
    active_session: "",
  }
  let (_, opened) = update(dispatch, NotificationClicked(run_id="r7"), model)
  assert_true(opened.focused is Local)
  assert_eq(opened.active_session, "desktop-test")
}

///|
fn encoded_start_workspace(conv : Conversation) -> String? {
  let payload = start_payload(
    "continue",
    DsPro,
    ReasoningMax,
    "1000",
    conv.session_id,
    "test-submission",
    workspace=conv.project(),
  )
  let json = payload.to_json()
  guard json is Object(fields) else { return None }
  @jsonx.json_text(fields, "workspace")
}

///|
test "runs resync names exact Starting Open and Idle owners" {
  let starting = {
    ..empty_conversation(
      @interop.ChannelId::Local,
      "starting-session",
      @interop.ChannelId::Local.test_project(),
    ),
    run: Starting(submission_id="submission-starting"),
  }
  let open = {
    ..empty_conversation(
      @interop.ChannelId::Local,
      "open-session",
      @interop.ChannelId::Local.test_project(),
    ),
    run: Open(run_id="run-open", stage=Opened),
  }
  let idle = {
    ..empty_conversation(
      @interop.ChannelId::Local,
      "idle-session",
      @interop.ChannelId::Local.test_project(),
    ),
    last_run_id: Some("run-idle"),
  }
  let empty = empty_conversation(
    @interop.ChannelId::Local,
    "never-started",
    @interop.ChannelId::Local.test_project(),
  )
  let model = test_model()
    .replace_conversation(starting)
    .replace_conversation(open)
    .replace_conversation(idle)
    .replace_conversation(empty)
  let json = runs_payload(
    model.run_snapshot_frontier(@interop.ChannelId::Local),
  ).to_json()
  guard json is { "known": Array(known), .. } else {
    fail("runs payload omitted known selectors")
  }
  inspect(known.length(), content="3")
  assert_true(
    known.contains({
      "session": "starting-session",
      "submission_id": "submission-starting",
    }),
  )
  assert_true(
    known.contains({ "session": "open-session", "run_id": "run-open" }),
  )
  assert_true(
    known.contains({ "session": "idle-session", "run_id": "run-idle" }),
  )
}

///|
fn with_pending_steers(
  conv : Conversation,
  texts : Array[String],
  run_id? : String = "r7",
) -> Conversation {
  let mut next = conv
  for index, text in texts {
    next = next.enqueue_steer(
      "test-steer-" + index.to_string(),
      Some(run_id),
      text,
      text,
      [],
      FollowupSteer,
    )
  }
  next
}

///|
fn with_pending_prompt(
  conv : Conversation,
  id : String,
  text : String,
) -> Conversation {
  {
    ..conv,
    pending_prompt: Some({ submission_id: id, draft: text, mentions: [], }),
  }
}

///|
/// Run A has finished but its exact start response is still in flight; run B
/// has already been sent and announced on the same conversation.
fn second_run_started_before_first_response() -> (Model, String)? {
  let dispatch = test_dispatch()
  let first = with_pending_prompt(
    { ..test_conversation(), run: Starting(submission_id="first-start"), },
    "first-start",
    "first prompt",
  )
  let (_, first_started) = update_dev(
    dispatch,
    Started(
      run_id="r-first",
      session="desktop-test",
      model=DsPro,
      max_steps=1000,
      session_root=None,
      submission_id=Some("first-start"),
    ),
    test_model().replace_conversation(first),
  )
  let (_, first_finished) = update_dev(
    dispatch,
    Finished(run_id="r-first", status="finished", answer=None),
    first_started,
  )
  let (_, reconciled) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[],
      watermark=1,
      generation=1,
    ),
    first_finished,
  )
  let (_, post_finish) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[],
      watermark=1,
      generation=2,
    ),
    reconciled,
  )
  guard post_finish.active_conversation() is Some(idle) else { return None }
  let drafted = post_finish.replace_conversation({
    ..idle,
    task: "second prompt",
  })
  let (_, sending) = update(dispatch, Send, drafted)
  guard sending.active_conversation() is Some(sent) &&
    sent.run is Starting(submission_id=second_submission) else {
    return None
  }
  let (_, second_started) = update_dev(
    dispatch,
    Started(
      run_id="r-second",
      session="desktop-test",
      model=DsPro,
      max_steps=1000,
      session_root=None,
      submission_id=Some(second_submission),
    ),
    sending,
  )
  Some((second_started, second_submission))
}

///|
/// Run A ended with one steer receipt still in flight, then run B started.
fn second_run_started_before_first_steer_receipt() -> Model? {
  let dispatch = test_dispatch()
  let first = with_pending_steers(running_conversation(), ["late steer"])
  let (_, first_finished) = update_dev(
    dispatch,
    Finished(run_id="r7", status="finished", answer=None),
    running_model().replace_conversation(first),
  )
  // A second local run is admitted only after the prior durable terminal has
  // reconciled. The old steer receipt may still trail that boundary.
  let (_, reconciled) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[],
      watermark=1,
      generation=1,
    ),
    first_finished,
  )
  guard reconciled.active_conversation() is Some(idle) else { return None }
  let drafted = reconciled.replace_conversation({
    ..idle,
    task: "second prompt",
  })
  let (_, sending) = update(dispatch, Send, drafted)
  guard sending.active_conversation() is Some(sent) &&
    sent.run is Starting(submission_id=second_submission) else {
    return None
  }
  let (_, second_started) = update_dev(
    dispatch,
    Started(
      run_id="r8",
      session="desktop-test",
      model=DsPro,
      max_steps=1000,
      session_root=None,
      submission_id=Some(second_submission),
    ),
    sending,
  )
  Some(second_started)
}

///|
test "assistant deltas accumulate into the streaming response" {
  let dispatch = test_dispatch()
  let (_, first) = update_dev(
    dispatch,
    Engine(Some("r7"), AssistantDelta("Hello"), session=None),
    running_model(),
  )
  let (_, second) = update_dev(
    dispatch,
    Engine(Some("r7"), AssistantDelta(", world"), session=None),
    first,
  )
  assert_eq(second.active().turn.streaming_response, Some("Hello, world"))
  inspect(second.active().messages.length(), content="0")
}

///|
test "update is pure: replaying a delta on the same model is idempotent" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    turn: {
      ..running_conversation().turn,
      streaming_response: Some("partial"),
    },
  })
  let (_, once) = update_dev(
    dispatch,
    Engine(Some("r7"), AssistantDelta("!"), session=None),
    model,
  )
  let (_, twice) = update_dev(
    dispatch,
    Engine(Some("r7"), AssistantDelta("!"), session=None),
    model,
  )
  assert_eq(once.active().turn.streaming_response, Some("partial!"))
  assert_eq(twice.active().turn.streaming_response, Some("partial!"))
}

///|
test "deltas from an unknown run are dropped" {
  let dispatch = test_dispatch()
  let (_, next) = update_dev(
    dispatch,
    Engine(Some("r99"), AssistantDelta("stale"), session=None),
    running_model(),
  )
  assert_eq(next.active().turn.streaming_response, None)
}

///|
test "reasoning message waits for its durable commit" {
  let dispatch = test_dispatch()
  let model = running_model()
  let (_, next) = update_dev(
    dispatch,
    Engine(Some("r7"), ReasoningMessage("full thought"), session=None),
    model,
  )
  inspect(next.active().messages.length(), content="0")
  assert_eq(
    next.active().turn.live_reasoning,
    Some({ content: "full thought", complete: true, }),
  )
}

///|
test "reasoning deltas accumulate and answer output closes the live stream" {
  let dispatch = test_dispatch()
  let (_, first) = update_dev(
    dispatch,
    Engine(Some("r7"), ReasoningDelta("first"), session=None),
    running_model(),
  )
  let (_, second) = update_dev(
    dispatch,
    Engine(Some("r7"), ReasoningDelta(" line"), session=None),
    first,
  )
  assert_eq(
    second.active().turn.live_reasoning,
    Some({ content: "first line", complete: false, }),
  )
  let (_, answered) = update_dev(
    dispatch,
    Engine(Some("r7"), AssistantDelta("answer"), session=None),
    second,
  )
  assert_eq(
    answered.active().turn.live_reasoning,
    Some({ content: "first line", complete: true, }),
  )
  // Once the stream is semantically complete, a delayed delta cannot revive
  // or extend it.
  let (_, late) = update_dev(
    dispatch,
    Engine(Some("r7"), ReasoningDelta(" late"), session=None),
    answered,
  )
  assert_eq(
    late.active().turn.live_reasoning,
    answered.active().turn.live_reasoning,
  )
}

///|
test "an empty remote reasoning settlement clears the partial preview" {
  let dispatch = test_dispatch()
  let (_, partial) = update_dev(
    dispatch,
    Engine(Some("r7"), ReasoningDelta("first line"), session=None),
    running_model(),
  )
  let (_, settled) = update_dev(
    dispatch,
    Engine(Some("r7"), ReasoningMessage(""), session=None),
    partial,
  )
  assert_eq(settled.active().turn.live_reasoning, None)
  assert_eq(settled.active().reasoning_for_render(), (None, false))
}

///|
test "a matching durable commit de-duplicates without mutating the preview" {
  let dispatch = test_dispatch()
  let live = running_model().replace_conversation({
    ..running_conversation(),
    turn: {
      ..running_conversation().turn,
      live_reasoning: Some({ content: "think", complete: true, }),
    },
  })
  let (_, committed) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=1,
      ts=None,
      item=@protocol.Assistant({
        content: "answer",
        tool_calls: None,
        reasoning_content: Some("think"),
        is_replay: None,
      }),
      session_root=@interop.ChannelId::Local.test_store_root(),
    ),
    live,
  )
  assert_eq(
    committed.active().turn.live_reasoning,
    Some({ content: "think", complete: true, }),
  )
  assert_eq(committed.active().reasoning_for_render(), (None, true))
  assert_eq(committed.active().messages.length(), 1)
  assert_true(
    committed.active().messages[0].kind
    is Assistant(reasoning=Some("think"), ..),
  )
}

///|
test "commit-first reasoning keeps late prefixes and de-duplicates when sealed" {
  let dispatch = test_dispatch()
  let commit = SessionCommitted(
    session="desktop-test",
    sequence=1,
    ts=None,
    item=@protocol.Assistant({
      content: "answer",
      tool_calls: None,
      reasoning_content: Some("complete thought"),
      is_replay: None,
    }),
    session_root=@interop.ChannelId::Local.test_store_root(),
  )
  let (_, committed) = update_dev(dispatch, commit, running_model())
  let (_, partial) = update_dev(
    dispatch,
    Engine(Some("r7"), ReasoningDelta("complete"), session=None),
    committed,
  )
  assert_eq(partial.active().reasoning_for_render(), (Some("complete"), false))
  let (_, completed) = update_dev(
    dispatch,
    Engine(Some("r7"), ReasoningMessage("complete thought"), session=None),
    partial,
  )
  assert_eq(
    completed.active().turn.live_reasoning,
    Some({ content: "complete thought", complete: true, }),
  )
  assert_eq(completed.active().reasoning_for_render(), (None, true))
}

///|
test "a delayed untagged commit cannot truncate a newer reasoning stream" {
  let dispatch = test_dispatch()
  let (_, partial) = update_dev(
    dispatch,
    Engine(Some("r7"), ReasoningDelta("shared"), session=None),
    running_model(),
  )
  let (_, committed) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=1,
      ts=None,
      item=@protocol.Assistant({
        content: "older answer",
        tool_calls: None,
        reasoning_content: Some("shared"),
        is_replay: None,
      }),
      session_root=@interop.ChannelId::Local.test_store_root(),
    ),
    partial,
  )
  assert_eq(
    committed.active().turn.live_reasoning,
    Some({ content: "shared", complete: false, }),
  )
  assert_eq(committed.active().reasoning_for_render(), (Some("shared"), false))
  let (_, continued) = update_dev(
    dispatch,
    Engine(Some("r7"), ReasoningDelta(" future"), session=None),
    committed,
  )
  assert_eq(
    continued.active().turn.live_reasoning,
    Some({ content: "shared future", complete: false, }),
  )
}

///|
test "a later run does not confuse identical historical reasoning for its commit" {
  let dispatch = test_dispatch()
  let historical = {
    ..running_conversation(),
    messages: [
      {
        kind: Assistant(
          reasoning=Some("shared opening"),
          prose=Some("older answer"),
          calls=[],
          replay=false,
          finished=false,
        ),
        ts: None,
        sequence: Some(2),
      },
    ],
    watermark: 3,
    turn: RunState::for_run(3),
  }
  let model = running_model().replace_conversation(historical)
  let (_, partial) = update_dev(
    dispatch,
    Engine(Some("r7"), ReasoningDelta("shared opening"), session=None),
    model,
  )
  assert_eq(
    partial.active().reasoning_for_render(),
    (Some("shared opening"), false),
  )
  let (_, complete) = update_dev(
    dispatch,
    Engine(Some("r7"), ReasoningMessage("shared opening"), session=None),
    partial,
  )
  assert_eq(
    complete.active().turn.live_reasoning,
    Some({ content: "shared opening", complete: true, }),
  )
}

///|
test "a new model step advances past identical reasoning from the prior step" {
  let previous_step = {
    ..running_conversation(),
    messages: [
      {
        kind: Assistant(
          reasoning=Some("shared opening"),
          prose=None,
          calls=[],
          replay=false,
          finished=false,
        ),
        ts: None,
        sequence: Some(2),
      },
    ],
    watermark: 2,
    turn: {
      ..RunState::for_run(0),
      live_reasoning: Some({ content: "old live", complete: true, }),
    },
  }
  let (_, next_step) = apply_engine_event(
    previous_step,
    AgentStep(Some(2)),
    Some("r7"),
  )
  assert_eq(next_step.turn.live_reasoning, None)
  assert_eq(next_step.turn.reasoning_frontier, 2)
  let (_, live) = apply_engine_event(
    next_step,
    ReasoningDelta("shared opening"),
    Some("r7"),
  )
  assert_eq(live.reasoning_for_render(), (Some("shared opening"), false))
}

///|
test "a new run frontier includes commits already buffered by reload" {
  let dispatch = test_dispatch()
  let buffered : BufferedCommit = {
    sequence: 3,
    ts: None,
    item: @protocol.Assistant({
      content: "older answer",
      tool_calls: None,
      reasoning_content: Some("shared opening"),
      is_replay: None,
    }),
  }
  let conv = {
    ..test_conversation(),
    watermark: 1,
    sync: test_reloading([buffered]),
  }
  let (_, started) = update_dev(
    dispatch,
    Started(
      run_id="r7",
      session="desktop-test",
      model=DsPro,
      max_steps=1000,
      session_root=None,
      submission_id=None,
    ),
    test_model().replace_conversation(conv),
  )
  assert_eq(started.active().turn.reasoning_frontier, 3)
}

///|
test "the run heartbeat projects the phase it is derived from" {
  assert_eq(test_conversation().run_heartbeat(), None)
  let stage_of = (conv : Conversation) => {
    conv.run_heartbeat().map(run => run.stage)
  }
  // A silent model call is the whole point of the row: nothing else on screen
  // moves between the step event and the first answer delta.
  assert_eq(stage_of(running_conversation()), Some(Thinking))
  assert_eq(
    stage_of({
      ..running_conversation(),
      run: Open(run_id="r7", stage=AtStep(Some(3))),
    }),
    Some(AtStep(3)),
  )
  assert_eq(
    stage_of({
      ..running_conversation(),
      run: Open(run_id="r7", stage=AtStep(None)),
    }),
    Some(Working),
  )
  assert_eq(
    stage_of({
      ..running_conversation(),
      run: Open(run_id="r7", stage=Cancelling),
    }),
    Some(Stopping),
  )
  // The send is accepted but no run id exists yet: still worth a row, or the
  // gap between submitting and `started` reads as a dropped prompt.
  assert_eq(
    stage_of({ ..test_conversation(), run: Starting(submission_id="sub-1"), }),
    Some(Starting),
  )
  // A finished run leaves nothing behind — the answer is the status.
  assert_eq(
    stage_of({
      ..running_conversation(),
      run: NoRun(ended=Some(RunFinished(Completed))),
    }),
    None,
  )
}

///|
test "the run heartbeat carries only the facts the page actually has" {
  let full = {
    ..running_conversation(),
    run_started_ms: Some(1_000.0),
    turn: { ..running_conversation().turn, usage_tokens: 12_345, },
  }
  assert_eq(
    full.run_heartbeat(),
    Some({ stage: Thinking, started_ms: Some(1_000.0), tokens: 12_345, }),
  )
  // A run adopted from a reconnect has no start this page witnessed. The
  // composer omits the span rather than dating it from when we noticed.
  assert_eq(
    { ..full, run_started_ms: None, }.run_heartbeat().map(run => run.started_ms),
    Some(None),
  )
}

///|
test "a step event is what moves the heartbeat's stage" {
  let running = running_model()
  assert_eq(
    running.active().run_heartbeat().map(run => run.stage),
    Some(Thinking),
  )
  let (_, stepped) = update_dev(
    test_dispatch(),
    Engine(Some("r7"), AgentStep(Some(2)), session=None),
    running,
  )
  assert_eq(
    stepped.active().run_heartbeat().map(run => run.stage),
    Some(AtStep(2)),
  )
}

///|
test "assistant message only settles the transient response" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    turn: { ..running_conversation().turn, streaming_response: Some("answ"), },
  })
  let (_, next) = update_dev(
    dispatch,
    Engine(Some("r7"), AssistantMessage("answer"), session=None),
    model,
  )
  assert_eq(next.active().turn.streaming_response, None)
  inspect(next.active().messages.length(), content="0")
}

///|
test "agent setup failure is lifecycle-only until its durable terminal" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    turn: {
      ..running_conversation().turn,
      streaming_response: Some("partial answer"),
    },
  })
  let (_, next) = update_dev(
    dispatch,
    Engine(Some("r7"), AgentSetupFailed("could not initialize"), session=None),
    model,
  )
  assert_eq(next.active().turn.streaming_response, None)
  inspect(next.active().messages.length(), content="0")
}

///|
test "a new agent step clears the live stream" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    turn: { ..running_conversation().turn, streaming_response: Some("left"), },
  })
  let (_, next) = update_dev(
    dispatch,
    Engine(Some("r7"), AgentStep(Some(2)), session=None),
    model,
  )
  assert_eq(next.active().turn.streaming_response, None)
}

///|
test "finished run clears any leftover stream" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    turn: {
      ..running_conversation().turn,
      streaming_response: Some("leftover"),
    },
  })
  let (_, next) = update_dev(
    dispatch,
    Finished(run_id="r7", status="finished", answer=Some("done")),
    model,
  )
  assert_eq(next.active().turn.streaming_response, None)
  inspect(next.active().is_running(), content="false")
}

///|
test "finished run reloads the named durable session for an old host" {
  let dispatch = test_dispatch()
  let (_, finished) = update_dev(
    dispatch,
    Finished(run_id="r7", status="finished", answer=Some("done")),
    running_model(),
  )
  guard finished.active().sync
    is Reloading(generation=1, reload_after_current=false, ..) else {
    fail("Finished did not start the compatibility snapshot")
  }
  // Old hosts send no session.event; their post-Finished full snapshot is
  // therefore the only canonical source the commit-aware frontend consumes.
  let (_, loaded) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[
        { kind: User("question"), ts: None, sequence: None, },
        {
          kind: Assistant(
            reasoning=None,
            prose=Some("done"),
            calls=[],
            replay=false,
            finished=false,
          ),
          ts: None,
          sequence: None,
        },
      ],
      watermark=3,
      generation=1,
    ),
    finished,
  )
  inspect(loaded.active().messages.length(), content="2")
  assert_eq(loaded.active().messages[1].text(), Some("done"))
  inspect(loaded.active().watermark, content="3")
  assert_true(loaded.active().sync is Synced)
}

///|
test "Finished queues one follow-up behind an older in-flight snapshot" {
  let dispatch = test_dispatch()
  let model = {
    ..running_model().replace_conversation({
      ..running_conversation(),
      sync: test_reloading([]),
    }),
    transcript_request_generation: 1,
  }
  let finish : DeviceMsg = Finished(run_id="r7", status="finished", answer=None)
  let (_, finished) = update_dev(dispatch, finish, model)
  guard finished.active().sync
    is Reloading(generation=1, reload_after_current=true, ..) else {
    fail("Finished did not remember the post-boundary reload")
  }
  // A duplicate lifecycle notification is idempotent: it is not a second
  // durable boundary and must not queue another generation.
  let (_, duplicate) = update_dev(dispatch, finish, finished)
  guard duplicate.active().sync
    is Reloading(generation=1, reload_after_current=true, ..) else {
    fail("duplicate Finished changed the queued follow-up")
  }
  let (_, followed) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[],
      watermark=0,
      generation=1,
    ),
    duplicate,
  )
  guard followed.active().sync
    is Reloading(generation=2, reload_after_current=false, ..) else {
    fail("the older snapshot did not hand off to one fresh generation")
  }
}

///|
test "a finish the user watched leaves no unseen dot" {
  let dispatch = test_dispatch()
  let (_, next) = update_dev(
    dispatch,
    Finished(run_id="r7", status="finished", answer=Some("done")),
    running_model(),
  )
  inspect(next.active().unseen_finish, content="false")
}

///|
test "a finish in an unfocused window still needs attention" {
  let dispatch = test_dispatch()
  let model = { ..running_model(), window_focused: false, }
  let (_, next) = update_dev(
    dispatch,
    Finished(run_id="r7", status="finished", answer=Some("done")),
    model,
  )
  inspect(next.active().unseen_finish, content="true")
  inspect(next.notification_badge_count(), content="1")
  let (_, focused) = update(dispatch, WindowFocusChanged(true), next)
  inspect(focused.active().unseen_finish, content="false")
  inspect(focused.notification_badge_count(), content="0")
}

///|
test "a finish behind settings stays unread until the chat is reopened" {
  let dispatch = test_dispatch()
  let model = { ..running_model(), screen: Settings, }
  let (_, next) = update_dev(
    dispatch,
    Finished(run_id="r7", status="finished", answer=Some("done")),
    model,
  )
  inspect(next.active().unseen_finish, content="true")
  inspect(next.notification_badge_count(), content="1")
  let (_, opened) = open_session_on(
    dispatch,
    @interop.ChannelId::Local,
    next,
    "desktop-test",
  )
  assert_true(opened.screen is Chat)
  inspect(opened.active().unseen_finish, content="false")
  inspect(opened.notification_badge_count(), content="0")
}

///|
test "a background finish marks its conversation until it is opened" {
  let dispatch = test_dispatch()
  // The run belongs to "desktop-test"; the user is looking at another chat.
  let model = { ..running_model(), active_session: "desktop-elsewhere", }
  let (_, next) = update_dev(
    dispatch,
    Finished(run_id="r7", status="finished", answer=Some("done")),
    model,
  )
  guard next.find_conversation(@interop.ChannelId::Local, "desktop-test")
    is Some(conv) else {
    fail("conversation missing")
  }
  inspect(conv.unseen_finish, content="true")
  let opened = next.activate(
    @interop.ChannelId::Local,
    "desktop-test",
    @interop.ChannelId::Local.test_project(),
  )
  guard opened.find_conversation(@interop.ChannelId::Local, "desktop-test")
    is Some(seen) else {
    fail("conversation missing after activate")
  }
  inspect(seen.unseen_finish, content="false")
}

///|
test "an idle background notice is absorbed without a toast" {
  let dispatch = test_dispatch()
  // The run already finished: `active_run_id` is cleared, only the last-run
  // memory ties the id back to its conversation — so the event still reaches
  // `apply_engine_event`, which must raise nothing.
  let model = test_model().replace_conversation({
    ..test_conversation(),
    last_run_id: Some("r7"),
  })
  let (_, next) = update_dev(
    dispatch,
    Engine(
      Some("r7"),
      BackgroundNotice("background job bg-1 finished (exit=0)"),
      session=None,
    ),
    model,
  )
  assert_true(next.notifications.is_empty())
}

///|
test "new chat keeps the model intact until the rotation lands" {
  let dispatch = test_dispatch()
  let model = {
    ..running_model(),
    loading_conversation: Some({ channel: Local, session: "desktop-stale", }),
  }
  let (_, next) = update(dispatch, NewChat, model)
  inspect(next.active().is_running(), content="true")
  assert_true(next.loading_conversation is None)
}

///|
test "generated session ids include a random suffix" {
  let id = generated_session_id()
  let parts = [..id.split("-")]
  inspect(parts.length(), content="5")
  inspect(parts[0], content="desktop")
  inspect(parts[1].length(), content="8")
  inspect(parts[2].length(), content="6")
  inspect(parts[3].length(), content="3")
  inspect(parts[4].length(), content="9")
  let _ = @string.parse_int(parts[1]) catch {
    _ => fail("expected numeric date")
  }
  let _ = @string.parse_int(parts[2]) catch {
    _ => fail("expected numeric time")
  }
  let _ = @string.parse_int(parts[3]) catch {
    _ => fail("expected numeric millis")
  }
  let _ = @string.parse_int(parts[4]) catch {
    _ => fail("expected numeric salt")
  }
}

///|
test "session rotation activates a fresh conversation, keeping the old one" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..running_conversation(),
    messages: [{ kind: User("hi"), ts: None, sequence: None, }],
  })
  let (_, next) = update(
    dispatch,
    SessionRotated({ channel: Local, session: "desktop-fresh", }),
    model,
  )
  inspect(next.active_session, content="desktop-fresh")
  inspect(next.active().messages.length(), content="0")
  inspect(next.active().turn.usage_tokens, content="0")
  assert_true(next.display_status() is Ready)
  // The previous conversation keeps running in the background.
  guard next.find_conversation(@interop.ChannelId::Local, "desktop-test")
    is Some(old) else {
    fail("expected the old conversation to survive")
  }
  inspect(old.is_running(), content="true")
  inspect(old.messages.length(), content="1")
}

///|
test "session rotation prunes abandoned empty conversations" {
  let dispatch = test_dispatch()
  let (_, first) = update(
    dispatch,
    SessionRotated({ channel: Local, session: "desktop-a", }),
    test_model(),
  )
  let (_, second) = update(
    dispatch,
    SessionRotated({ channel: Local, session: "desktop-b", }),
    first,
  )
  // "desktop-test" and "desktop-a" had no transcript, no draft, no run.
  inspect(second.conversations.length(), content="1")
  inspect(second.active_session, content="desktop-b")
}

///|
test "a delayed rotation cannot steal focus from another channel" {
  let dispatch = test_dispatch()
  let remote : @interop.ChannelId = Remote("d-remote")
  let model = {
    ..test_model(),
    devices: [
      { ..empty_device_state(@interop.ChannelId::Local), bridge: Connected, },
      { ..empty_device_state(remote), bridge: Connected, },
    ],
  }
  let (_, next) = update(
    dispatch,
    SessionRotated({ channel: remote, session: "remote-late", }),
    model,
  )
  assert_true(next.focused is Local)
  inspect(next.active_session, content="desktop-test")
  assert_true(next.find_conversation(remote, "remote-late") is None)
}

///|
test "sessions loaded replaces the sidebar list" {
  let dispatch = test_dispatch()
  let items : Array[@transcript.SessionListItem] = [
    {
      id: "desktop-a",
      title: Some("first question"),
      workspace: @interop.ChannelId::Local.test_project(),
      workspace_name: "",
      updated_at_ms: None,
    },
  ]
  let (_, once) = update(dispatch, sessions_loaded(items), test_model())
  let (_, twice) = update(dispatch, sessions_loaded(items), test_model())
  inspect(once.dev().sessions.length(), content="1")
  inspect(once.dev().sessions[0].id, content="desktop-a")
  inspect(twice.dev().sessions.length(), content="1")
}

///|
test "session list assigns a commit-first conversation to its durable workspace" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/work/foreign")
  let (_, committed) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-foreign",
      sequence=1,
      ts=None,
      item=@protocol.User({
        content: "arrived before the list",
        submission_id: None,
      }),
      session_root=@interop.ChannelId::Local.test_store_root(),
    ),
    test_model(),
  )
  guard committed.find_conversation(
      @interop.ChannelId::Local,
      "desktop-foreign",
    )
    is Some(provisional) else {
    fail("commit did not materialize its conversation")
  }
  // The commit's own store places it immediately; the listing that follows
  // is what moves it to the project the host groups it under.
  assert_eq(
    provisional.workspace,
    Project(root=@interop.ChannelId::Local.test_project()),
  )
  let (_, listed) = update(
    dispatch,
    sessions_loaded(
      [
        {
          id: "desktop-foreign",
          title: Some("arrived before the list"),
          workspace,
          workspace_name: "foreign",
          updated_at_ms: None,
        },
      ],
      request_generation=committed.dev().sessions_request_generation,
    ),
    committed.activate(
      @interop.ChannelId::Local,
      "desktop-foreign",
      @interop.ChannelId::Local.test_project(),
    ),
  )
  guard listed.find_conversation(@interop.ChannelId::Local, "desktop-foreign")
    is Some(reconciled) else {
    fail("listed conversation disappeared")
  }
  assert_eq(reconciled.workspace, Project(root=workspace))
  assert_eq(listed.dev().active_project, Some(workspace))
  assert_true(encoded_start_workspace(reconciled) is Some("/work/foreign"))
}

///|
test "a rooted commit places its conversation without waiting for the list" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/work/foreign")
  let store = @interop.ChannelId::Local.test_resource("/work/foreign/.openseek")
  let model = test_model().with_dev(dev => { ..dev, projects: [workspace], })
  let (_, committed) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-foreign",
      sequence=1,
      ts=None,
      item=@protocol.User({
        content: "arrived before the list",
        submission_id: None,
      }),
      session_root=store,
    ),
    model,
  )
  guard committed.find_conversation(
      @interop.ChannelId::Local,
      "desktop-foreign",
    )
    is Some(placed) else {
    fail("rooted commit did not materialize its conversation")
  }
  assert_eq(placed.workspace, Project(root=workspace))
  // A registered project's own store is matched exactly rather than guessed
  // from a missing listing.
  let (_, registered) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-registered",
      sequence=1,
      ts=None,
      item=@protocol.User({ content: "hi", submission_id: None, }),
      session_root=@interop.ChannelId::Local.test_store_root(),
    ),
    committed,
  )
  guard registered.find_conversation(
      @interop.ChannelId::Local,
      "desktop-registered",
    )
    is Some(known) else {
    fail("rooted commit for a registered store did not materialize")
  }
  assert_eq(
    known.workspace,
    Project(root=@interop.ChannelId::Local.test_project()),
  )
  // The projects registry reply may still be in flight on a fresh
  // connection: a store outside the mirrored registry is still a project
  // store, and its layout (`<project>/.openseek`) names the project.
  let (_, unseen) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-unseen",
      sequence=1,
      ts=None,
      item=@protocol.User({ content: "hi", submission_id: None, }),
      session_root=@interop.ChannelId::Local.test_resource(
        "/work/unseen/.openseek",
      ),
    ),
    registered,
  )
  guard unseen.find_conversation(@interop.ChannelId::Local, "desktop-unseen")
    is Some(pending) else {
    fail("unregistered-store commit did not materialize its conversation")
  }
  assert_eq(
    pending.workspace,
    Project(root=@interop.ChannelId::Local.test_resource("/work/unseen")),
  )
}

///|
/// A same-id row from another store is a different durable record: it must
/// not suppress the list reload that gives the committed record its own row.
test "a commit for an unlisted store refreshes past a same-id row" {
  let dispatch = test_dispatch()
  let listed = @interop.ChannelId::Local.test_project()
  let other = @interop.ChannelId::Local.test_resource("/other")
  let store = @interop.ChannelId::Local.test_resource("/other/.openseek")
  let model = test_model().with_dev(dev => {
    ..dev,
    projects: [listed, other],
    sessions: [
      {
        id: "desktop-shared",
        title: Some("listed copy"),
        workspace: listed,
        workspace_name: "work",
        updated_at_ms: None,
      },
      {
        id: "desktop-listed-only",
        title: Some("listed chat"),
        workspace: listed,
        workspace_name: "work",
        updated_at_ms: None,
      },
    ],
  })
  let (_, committed) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-shared",
      sequence=1,
      ts=None,
      item=@protocol.User({ content: "hi", submission_id: None, }),
      session_root=store,
    ),
    model,
  )
  assert_eq(committed.dev().sessions_request_generation, 1)
  // The store that is already listed asks for nothing: this exact record has
  // its row, and the conversation is new to the page either way.
  let (_, same_store) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-listed-only",
      sequence=1,
      ts=None,
      item=@protocol.User({ content: "hi", submission_id: None, }),
      session_root=@interop.ChannelId::Local.test_store_root(),
    ),
    committed,
  )
  assert_eq(same_store.dev().sessions_request_generation, 1)
}

///|
/// The unseen-commit gate has the same hazard as the listing check: the page
/// holds one conversation per (channel, id), so a record in one project that
/// already consumed sequence one must not make another project store's first
/// commit look like old news.
test "a commit for an unlisted store refreshes past a same-id watermark" {
  let dispatch = test_dispatch()
  let listed = @interop.ChannelId::Local.test_project()
  let other = @interop.ChannelId::Local.test_resource("/other")
  let store = @interop.ChannelId::Local.test_resource("/other/.openseek")
  let model = test_model().with_dev(dev => {
    ..dev,
    projects: [listed, other],
    sessions: [
      {
        id: "desktop-shared",
        title: Some("listed copy"),
        workspace: listed,
        workspace_name: "work",
        updated_at_ms: None,
      },
    ],
  })
  // The listed record consumes its own first commit, so the page now holds
  // that project's conversation at watermark one.
  let (_, first) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-shared",
      sequence=1,
      ts=None,
      item=@protocol.User({ content: "listed", submission_id: None, }),
      session_root=@interop.ChannelId::Local.test_store_root(),
    ),
    model,
  )
  assert_eq(first.dev().sessions_request_generation, 0)
  guard first.find_conversation(@interop.ChannelId::Local, "desktop-shared")
    is Some(consumed) else {
    fail("listed commit did not materialize its conversation")
  }
  assert_eq(consumed.watermark, 1)
  // The other store's own first commit is a different durable record: it is
  // unlisted, and the listed watermark must not suppress its reload.
  let (_, committed) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-shared",
      sequence=1,
      ts=None,
      item=@protocol.User({ content: "other project", submission_id: None, }),
      session_root=store,
    ),
    first,
  )
  assert_eq(committed.dev().sessions_request_generation, 1)
}

///|
test "a background session list updates only its channel's same-id workspace" {
  let dispatch = test_dispatch()
  let remote : @interop.ChannelId = Remote("d-remote")
  let local_conv = {
    ..empty_conversation(
      @interop.ChannelId::Local,
      "shared",
      @interop.ChannelId::Local.test_project(),
    ),
    workspace: Project(root=@interop.ChannelId::Local.test_resource("/local")),
  }
  let remote_conv = {
    ..empty_conversation(remote, "shared", remote.test_project()),
    workspace: Project(root=remote.test_resource("/remote-old")),
  }
  let model = {
    ..test_model(),
    devices: [
      { ..empty_device_state(@interop.ChannelId::Local), bridge: Connected, },
      { ..empty_device_state(remote), bridge: Connected, },
    ],
    active_session: "shared",
    conversations: [local_conv, remote_conv],
  }
  let (_, next) = update(
    dispatch,
    FromDevice(
      remote,
      SessionsLoaded(
        [
          {
            id: "shared",
            title: Some("remote"),
            workspace: remote.test_resource("/remote-new"),
            workspace_name: "remote-new",
            updated_at_ms: None,
          },
        ],
        connection_generation=0,
        request_generation=0,
      ),
    ),
    model,
  )
  guard next.find_conversation(@interop.ChannelId::Local, "shared")
    is Some(local_conv) &&
    next.find_conversation(remote, "shared") is Some(remote_conv) else {
    fail("same-id conversations disappeared")
  }
  assert_true(
    local_conv.workspace is Project(root=workspace) &&
    workspace.path == "/local",
  )
  assert_true(
    remote_conv.workspace is Project(root=workspace) &&
    workspace.path == "/remote-new",
  )
}

///|
test "session list assigns a Started-first conversation to its durable workspace" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/work/started-first")
  let (_, started) = update_dev(
    dispatch,
    Started(
      run_id="foreign-run",
      session="desktop-started-first",
      model=DsPro,
      max_steps=1000,
      session_root=Some(@interop.ChannelId::Local.test_store_root()),
      submission_id=None,
    ),
    test_model(),
  )
  guard started.find_conversation(
      @interop.ChannelId::Local,
      "desktop-started-first",
    )
    is Some(provisional) else {
    fail("Started did not materialize its conversation")
  }
  // The run's own store places it immediately; the listing that follows is
  // what moves it to the project the host groups it under.
  assert_eq(
    provisional.workspace,
    Project(root=@interop.ChannelId::Local.test_project()),
  )
  let (_, listed) = update(
    dispatch,
    sessions_loaded([
      {
        id: "desktop-started-first",
        title: Some("arrived before the list"),
        workspace,
        workspace_name: "started-first",
        updated_at_ms: None,
      },
    ]),
    started,
  )
  guard listed.find_conversation(
      @interop.ChannelId::Local,
      "desktop-started-first",
    )
    is Some(reconciled) else {
    fail("listed conversation disappeared")
  }
  assert_eq(reconciled.workspace, Project(root=workspace))
  assert_true(
    encoded_start_workspace(reconciled) is Some("/work/started-first"),
  )
}

///|
test "Started places a foreign conversation from its host session root" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/C:/work/core")
  let model = test_model().with_dev(dev => { ..dev, projects: [workspace], })
  let (_, started) = update_dev(
    dispatch,
    Started(
      run_id="foreign-run",
      session="desktop-workspace-run",
      model=DsPro,
      max_steps=1000,
      session_root=Some(
        @interop.ChannelId::Local.test_resource("/C:/work/core/.openseek"),
      ),
      submission_id=None,
    ),
    model,
  )
  guard started.find_conversation(
      @interop.ChannelId::Local,
      "desktop-workspace-run",
    )
    is Some(foreign) else {
    fail("Started did not materialize its conversation")
  }
  assert_eq(foreign.workspace, Project(root=workspace))
  inspect(started.active_session, content="desktop-test")
}

///|
test "sessions failure pops a toast without touching the transcript" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    messages: [{ kind: User("hi"), ts: None, sequence: None, }],
  })
  let (_, next) = update_dev(dispatch, SessionsFailed("engine exploded"), model)
  inspect(next.notifications.length(), content="1")
  inspect(
    next.notifications[0].message,
    content="Session list unavailable: engine exploded",
  )
  inspect(next.active().messages.length(), content="1")
}

///|
test "open session is a no-op for the current session" {
  let dispatch = test_dispatch()
  let (_, next) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-test"),
    test_model(),
  )
  inspect(next.active_session, content="desktop-test")
  inspect(next.conversations.length(), content="1")
}

///|
test "a sub-run child opens through its parent before the store lists it" {
  // The Workflows tab offers a click into a child the sidebar has not listed
  // yet (the inventory refreshes at connect, archive and unarchive, not when
  // a child appears mid-run). The child's session lives in its parent's
  // store, so the parent's placement is its own.
  let dispatch = test_dispatch()
  let model = test_model()
  assert_true(
    model.session_project(@interop.ChannelId::Local, "desktop-test-sr-2")
    is Some(_),
  )
  let (_, next) = update(dispatch, OpenSessionHere("desktop-test-sr-2"), model)
  // The click selects the child and starts its first load; the view switches
  // when the snapshot lands, as for any session opened from the sidebar.
  guard next.selected_conversation is Some(selection) else {
    fail("expected the child to be selected")
  }
  inspect(selection.session, content="desktop-test-sr-2")
  assert_eq(selection.workspace, @interop.ChannelId::Local.test_project())
  assert_true(
    next.loading_conversation
    is Some({ channel: Local, session: "desktop-test-sr-2", }),
  )
  guard next.find_conversation(@interop.ChannelId::Local, "desktop-test-sr-2")
    is Some(child) else {
    fail("expected the child conversation to exist, loading")
  }
  assert_true(child.sync is Reloading(..))
  inspect(
    next.transcript_request_generation,
    content="\{model.transcript_request_generation + 1}",
  )
  // A child of a parent this page knows nothing about is still unplaceable.
  let (_, same) = update(dispatch, OpenSessionHere("elsewhere-sr-2"), model)
  inspect(same.active_session, content="desktop-test")
}

///|
test "open session keeps live state on screen while re-reading the store" {
  let dispatch = test_dispatch()
  let background = {
    ..empty_conversation(
      @interop.ChannelId::Local,
      "desktop-bg",
      @interop.ChannelId::Local.test_project(),
    ),
    run: Open(run_id="r9", stage=Opened),
    messages: [{ kind: User("background task"), ts: None, sequence: None, }],
    turn: {
      ..empty_conversation(
        @interop.ChannelId::Local,
        "desktop-bg",
        @interop.ChannelId::Local.test_project(),
      ).turn,
      streaming_response: Some("mid-stream"),
    },
  }
  let model = running_model().replace_conversation(background)
  let (_, once) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-bg"),
    model,
  )
  let (_, twice) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-bg"),
    model,
  )
  inspect(once.active_session, content="desktop-bg")
  // The live state stays on screen; the store re-read happens behind it
  // (this client may have been absent for part of this conversation).
  assert_eq(once.active().turn.streaming_response, Some("mid-stream"))
  inspect(once.active().is_running(), content="true")
  assert_true(
    once.loading_conversation
    is Some({ channel: Local, session: "desktop-bg", }),
  )
  // The previous conversation is still running in the background.
  guard once.find_conversation(@interop.ChannelId::Local, "desktop-test")
    is Some(old) else {
    fail("expected the old conversation to survive")
  }
  inspect(old.is_running(), content="true")
  inspect(twice.active_session, content="desktop-bg")
}

///|
test "reconnect refresh is single-flight and preserves its commit buffer" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    messages: [{ kind: User("kept"), ts: None, sequence: None, }],
    watermark: 1,
  })
  let (_, refreshing) = update_dev(dispatch, BridgeReady, model)
  guard refreshing.active().sync is Reloading(generation=1, attempt=1, ..) else {
    fail("expected the first reconnect refresh")
  }
  let (_, buffered) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=3,
      ts=None,
      item=@protocol.User({ content: "future", submission_id: None, }),
      session_root=@interop.ChannelId::Local.test_store_root(),
    ),
    refreshing,
  )
  let (_, reconnected_again) = update_dev(dispatch, BridgeReady, buffered)
  guard reconnected_again.active().sync
    is Reloading(generation=1, attempt=1, buffered=commits, ..) else {
    fail("a second reconnect started another generation")
  }
  inspect(commits.length(), content="1")
  inspect(commits[0].sequence, content="3")
}

///|
test "BridgeReady clears every non-replayable stream and compaction phase" {
  let dispatch = test_dispatch()
  let active = {
    ..test_conversation(),
    compaction: Queued,
    turn: {
      ..test_conversation().turn,
      streaming_response: Some("old answer"),
    },
  }
  let background = {
    ..empty_conversation(
      @interop.ChannelId::Local,
      "desktop-bg",
      @interop.ChannelId::Local.test_project(),
    ),
    compaction: Compacting,
    turn: {
      ..empty_conversation(
        @interop.ChannelId::Local,
        "desktop-bg",
        @interop.ChannelId::Local.test_project(),
      ).turn,
      streaming_response: Some("background answer"),
    },
  }
  let model = test_model()
    .replace_conversation(active)
    .replace_conversation(background)
  let (_, next) = update_dev(dispatch, BridgeReady, model)
  for conv in next.conversations {
    assert_eq(conv.turn.streaming_response, None)
    assert_true(conv.compaction is NotCompacting)
  }
}

///|
test "BridgeReady clears focused host settings until the refetch lands" {
  let dispatch = test_dispatch()
  let model = {
    ..test_model(),
    api_provider: Custom,
    custom_api_url: "https://old.example/chat",
    custom_key_saved: true,
    setup_api_key: "old-key",
    host_settings_revision: 7,
  }
  let (_, next) = update_dev(dispatch, BridgeReady, model)
  assert_false(next.host_settings_loaded())
  assert_true(next.api_provider is Deepseek)
  inspect(next.custom_api_url, content="")
  assert_false(next.custom_key_saved)
  inspect(next.setup_api_key, content="")
}

///|
/// A reconnect invalidates every path-based fact: the worktree mirror is
/// dropped, so this conversation's placement is unknown again and nothing may
/// keep addressing the root the dead connection confirmed. Both the watcher
/// and the file index must retire and stay retired until a fresh index is
/// built against a re-confirmed root.
test "a reconnect retires the file index watcher until placement returns" {
  let dispatch = test_dispatch()
  let model = test_model()
  let owner : @interop.ConversationKey = {
    channel: @interop.ChannelId::Local,
    session: "desktop-test",
  }
  let root = @interop.ChannelId::Local.test_project()
  let watched : @fileeditor.WatchedPaths = {
    owner,
    root,
    files: [],
    directories: [],
    recursive: true,
  }
  let panel = {
    ..model.file_panel,
    owner: Some(owner),
    placement: @fileeditor.PlacementLive(@interop.WorkspaceRoot(root~)),
    watching: Some(watched),
    watch_generation: 7,
  }
  let model = { ..model, file_panel: panel, }
  let file_emit = dispatch.map(msg => FileEditor(msg))
  let (_, loading) = @fileeditor.update(
    file_emit,
    @fileeditor.EnsureFileIndex,
    panel,
    file_ctx(model),
  )
  let (_, ready) = @fileeditor.update(
    file_emit,
    @fileeditor.FilesIndexed(
      owner~,
      epoch=loading.request_epoch,
      files=[],
      truncated=false,
    ),
    loading,
    file_ctx(model),
  )
  let model = { ..model, file_panel: ready, }
  let (_, reconnected) = update_dev(dispatch, BridgeReady, model)
  // A reconnect drops the worktree mirror, so this conversation's placement
  // is unknown again. Both the watcher and the index retire rather than keep
  // addressing a root the new connection has not confirmed.
  assert_true(reconnected.file_panel.watching is None)
  assert_false(reconnected.file_panel.index is @fileeditor.IndexReady(..))
  // The registry answering does not by itself resurrect them: nothing is
  // watched again until a fresh index is built against the confirmed root.
  let (_, placed) = update_dev(
    dispatch,
    WorktreesLoaded(
      [],
      workspace=@interop.ChannelId::Local.test_project(),
      connection_generation=reconnected.dev().connection_generation,
      request_generation=reconnected.dev().worktrees_request_generation,
    ),
    reconnected,
  )
  assert_true(placed.file_panel.watching is None)
  assert_eq(placed.dev().worktrees.length(), 1)
}

///|
test "device focus retires the outgoing watcher and file index" {
  let dispatch = test_dispatch()
  let remote : @interop.ChannelId = Remote("remote-device")
  let model = test_model()
  let owner : @interop.ConversationKey = {
    channel: @interop.ChannelId::Local,
    session: "desktop-test",
  }
  let root = @interop.ChannelId::Local.test_project()
  let devices = model.devices.copy()
  devices.push({ ..empty_device_state(remote), bridge: Connected, })
  let conversations = model.conversations.copy()
  conversations.push(
    empty_conversation(remote, "remote-session", remote.test_project()),
  )
  let panel = {
    ..model.file_panel,
    owner: Some(owner),
    placement: @fileeditor.PlacementLive(@interop.WorkspaceRoot(root~)),
    watching: Some({ owner, root, files: [], directories: [], recursive: true, }),
    watch_generation: 7,
  }
  let model = { ..model, devices, conversations, file_panel: panel, }
  let (_, loading) = @fileeditor.update(
    dispatch.map(msg => FileEditor(msg)),
    @fileeditor.EnsureFileIndex,
    panel,
    file_ctx(model),
  )
  assert_true(loading.index is @fileeditor.IndexLoading(_))
  let (_, next) = update(dispatch, OpenSession(remote, "remote-session"), {
    ..model,
    file_panel: loading,
  })
  // The old Local HostConnection receives `fs.unwatch` before the common sync
  // replaces its owner. That sync also retires the in-flight Local index key;
  // the new remote conversation starts without either resource.
  assert_eq(next.focused, remote)
  assert_true(
    next.file_panel.owner is Some({ channel: Remote("remote-device"), .. }),
  )
  assert_true(next.file_panel.watching is None)
  assert_eq(next.file_panel.watch_generation, 8)
  assert_true(next.file_panel.index is @fileeditor.IndexEmpty)
}

///|
test "BridgeReady resets only conversations owned by its channel" {
  let dispatch = test_dispatch()
  let background : @interop.ChannelId = Remote("d-bg")
  let local_conv = {
    ..empty_conversation(
      @interop.ChannelId::Local,
      "shared",
      @interop.ChannelId::Local.test_project(),
    ),
    compaction: Queued,
    turn: {
      ..empty_conversation(
        @interop.ChannelId::Local,
        "shared",
        @interop.ChannelId::Local.test_project(),
      ).turn,
      streaming_response: Some("local answer"),
    },
  }
  let remote = {
    ..empty_conversation(background, "shared", background.test_project()),
    compaction: Compacting,
    turn: {
      ..empty_conversation(background, "shared", background.test_project()).turn,
      streaming_response: Some("remote answer"),
    },
  }
  let model = {
    ..test_model(),
    devices: [
      { ..empty_device_state(@interop.ChannelId::Local), bridge: Connected, },
      { ..empty_device_state(background), bridge: Connected, },
    ],
    active_session: "shared",
    conversations: [local_conv, remote],
  }
  let (_, next) = update(dispatch, FromDevice(background, BridgeReady), model)
  guard next.find_conversation(@interop.ChannelId::Local, "shared")
    is Some(kept) &&
    next.find_conversation(background, "shared") is Some(reset) else {
    fail("same-id conversations were not preserved")
  }
  assert_eq(kept.turn.streaming_response, Some("local answer"))
  assert_true(kept.compaction is Queued)
  assert_eq(reset.turn.streaming_response, None)
  assert_true(reset.compaction is NotCompacting)
}

///|
test "socket losses mark the bridge lost at the third consecutive drop" {
  let dispatch = test_dispatch()
  let channel : @interop.ChannelId = Remote("d1")
  let model = {
    ..initial_model(),
    devices: [{ ..empty_device_state(channel), bridge: Connected, }],
    focused: channel,
  }
  let (_, one) = update(
    dispatch,
    FromDevice(channel, ChannelDown(websocket_epoch=0)),
    model,
  )
  let (_, due) = update(
    dispatch,
    FromDevice(channel, ReconnectDue(websocket_epoch=0)),
    one,
  )
  inspect(due.dev().reconnect_attempt, content="1")
  // Terminal retirement is covered by the terminal component's disconnect
  // test; the application state owns only the reconnect policy now.
  let (_, two) = update(
    dispatch,
    FromDevice(channel, ChannelDown(websocket_epoch=0)),
    due,
  )
  inspect(two.dev().reconnect_failures, content="2")
  assert_true(two.bridge_state() is Connected)
  let (_, three) = update(
    dispatch,
    FromDevice(channel, ChannelDown(websocket_epoch=0)),
    two,
  )
  assert_true(three.bridge_state() is BridgeLost(_))
}

///|
test "BridgeReady resets the reconnect failure count" {
  let dispatch = test_dispatch()
  let channel : @interop.ChannelId = Remote("d1")
  let model = {
    ..initial_model(),
    devices: [
      {
        ..empty_device_state(channel),
        reconnect_failures: 2,
        bridge: BridgeLost("gone"),
      },
    ],
    focused: channel,
  }
  let (_, next) = update(dispatch, FromDevice(channel, BridgeReady), model)
  inspect(next.dev().reconnect_failures, content="0")
  assert_true(next.bridge_state() is Connected)
}

///|
test "late reconnect ticks cannot act on removed or re-added devices" {
  let dispatch = test_dispatch()
  let channel : @interop.ChannelId = Remote("gone")
  let model = test_model()
  let (_, next) = update(
    dispatch,
    FromDevice(channel, ReconnectDue(websocket_epoch=1)),
    model,
  )
  inspect(next.devices.length(), content="1")
  assert_true(next.device_state(channel) is None)
  // Reusing the relay id after sign-out is not reusing the connection. The
  // page-wide epoch survives account teardown and advances when the roster
  // adopts the same id again.
  let roster : Array[DeviceMeta] = [
    { id: "same", name: "Mac", hostname: None, online: true, },
  ]
  let console_model = {
    ..console_test_model(),
    console: Some(empty_console_state(Some("same"), None)),
  }
  let (_, signed) = update(
    dispatch,
    Console(MeLoaded(login="o", avatar="")),
    console_model,
  )
  let (_, first) = update(
    dispatch,
    Console(RosterLoaded(roster, generation=1)),
    signed,
  )
  let same : @interop.ChannelId = Remote("same")
  guard first.device_state(same) is Some(first_dev) else {
    fail("first device connection missing")
  }
  inspect(first_dev.websocket_epoch, content="1")
  let (_, out) = update(dispatch, Console(MeUnauthorized), first)
  let (_, signed_again) = update(
    dispatch,
    Console(MeLoaded(login="o", avatar="")),
    out,
  )
  let (_, current) = update(
    dispatch,
    Console(RosterLoaded(roster, generation=2)),
    signed_again,
  )
  guard current.device_state(same) is Some(current_dev) else {
    fail("re-added device connection missing")
  }
  inspect(current_dev.websocket_epoch, content="2")
  let (_, stale) = update(
    dispatch,
    FromDevice(same, ReconnectDue(websocket_epoch=1)),
    current,
  )
  assert_true(stale.devices == current.devices)
  inspect(stale.websocket_epoch, content="2")
}

///|
test "an explicit rejected fresh start does not force reconnect reloads" {
  let dispatch = test_dispatch()
  let conv = with_pending_prompt(
    { ..test_conversation(), run: Starting(submission_id="rejected-id"), },
    "rejected-id",
    "try this",
  )
  let (_, rejected) = update_dev(
    dispatch,
    StartRejected(
      session="desktop-test",
      submission_id="rejected-id",
      message="host refused",
    ),
    test_model().replace_conversation(conv),
  )
  inspect(rejected.active().pending_steers.length(), content="0")
  let (_, reconnected) = update_dev(dispatch, BridgeReady, rejected)
  assert_true(reconnected.active().sync is Synced)
  inspect(reconnected.transcript_request_generation, content="0")
}

///|
test "open session tracks the latest load and ignores stale replies" {
  let dispatch = test_dispatch()
  let (_, loading_a) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-a"),
    test_model().with_listed(["desktop-a", "desktop-b"]),
  )
  inspect(loading_a.active_session, content="desktop-test")
  assert_true(
    loading_a.loading_conversation
    is Some({ channel: Local, session: "desktop-a", }),
  )
  let (_, loading_b) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-b"),
    loading_a,
  )
  assert_true(
    loading_b.loading_conversation
    is Some({ channel: Local, session: "desktop-b", }),
  )
  let a_items : Array[@transcript.TranscriptItem] = [
    { kind: User("old selection"), ts: None, sequence: None, },
  ]
  let (_, after_a) = update_dev(
    dispatch,
    SessionLoaded(
      goal=None,
      goal_markers=[],
      session="desktop-a",
      items=a_items,
      watermark=0,
      generation=1,
    ),
    loading_b,
  )
  inspect(after_a.active_session, content="desktop-test")
  assert_true(
    after_a.loading_conversation
    is Some({ channel: Local, session: "desktop-b", }),
  )
  let b_items : Array[@transcript.TranscriptItem] = [
    { kind: User("latest selection"), ts: None, sequence: None, },
  ]
  let (_, after_b) = update_dev(
    dispatch,
    SessionLoaded(
      goal=None,
      goal_markers=[],
      session="desktop-b",
      items=b_items,
      watermark=0,
      generation=2,
    ),
    after_a,
  )
  inspect(after_b.active_session, content="desktop-b")
  assert_true(after_b.loading_conversation is None)
  assert_eq(after_b.active().messages[0].text(), Some("latest selection"))
}

///|
test "a restored session keeps the placement its listing named" {
  let dispatch = test_dispatch()
  let session = "desktop-restored"
  let (_, listed) = update(
    dispatch,
    sessions_loaded([
      {
        id: session,
        title: Some("restored"),
        workspace: @interop.ChannelId::Local.test_project(),
        workspace_name: "work",
        updated_at_ms: None,
      },
    ]),
    test_model(),
  )
  let (_, loading) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, session),
    listed,
  )
  guard loading.find_conversation(@interop.ChannelId::Local, session)
    is Some(before) else {
    fail("conversation was not materialized for loading")
  }
  assert_true(
    loading.conversation_root(before) is Some(root) && root.path == "/work",
  )
  let (_, restored) = update_dev(
    dispatch,
    SessionLoaded(
      session~,
      items=[],
      watermark=0,
      goal=None,
      goal_markers=[],
      generation=1,
    ),
    loading,
  )
  assert_eq(restored.active_session, session)
  // Placement stays stable across transcript restoration: it follows the
  // project the listing named, not anything the transcript carries.
  assert_true(restored.active().workspace is Project(..))
  assert_true(
    restored.conversation_root(restored.active()) is Some(root) &&
    root.path == "/work",
  )
  assert_true(
    file_ctx(restored).placement is Some(placement) &&
    placement.checkout_root() is Some(root) &&
    root.path == "/work",
  )
}

///|
test "same-id session loads are fenced by channel owner" {
  let dispatch = test_dispatch()
  let remote : @interop.ChannelId = Remote("d-remote")
  let local_conv = {
    ..empty_conversation(
      @interop.ChannelId::Local,
      "shared",
      @interop.ChannelId::Local.test_project(),
    ),
    messages: [{ kind: User("local"), ts: None, sequence: None, }],
  }
  let remote_conv = {
    ..empty_conversation(remote, "shared", remote.test_project()),
    messages: [{ kind: User("remote"), ts: None, sequence: None, }],
  }
  let model = {
    ..test_model(),
    devices: [
      { ..empty_device_state(@interop.ChannelId::Local), bridge: Connected, },
      { ..empty_device_state(remote), bridge: Connected, },
    ],
    active_session: "shared",
    conversations: [local_conv, remote_conv],
  }
  let (_, loading_remote) = update(
    dispatch,
    OpenSession(remote, "shared"),
    model,
  )
  let (_, loading_local) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "shared"),
    loading_remote,
  )
  assert_true(
    loading_local.loading_conversation
    is Some({ channel: Local, session: "shared", }),
  )
  let (_, remote_reply) = update(
    dispatch,
    FromDevice(
      remote,
      SessionLoaded(
        goal=None,
        goal_markers=[],
        session="shared",
        items=[
          {
            kind: Assistant(
              reasoning=None,
              prose=Some("remote loaded"),
              calls=[],
              replay=false,
              finished=false,
            ),
            ts: None,
            sequence: None,
          },
        ],
        watermark=1,
        generation=1,
      ),
    ),
    loading_local,
  )
  assert_true(remote_reply.focused is Local)
  assert_eq(remote_reply.active().messages[0].text(), Some("local"))
  assert_true(
    remote_reply.loading_conversation
    is Some({ channel: Local, session: "shared", }),
  )
  guard remote_reply.find_conversation(remote, "shared") is Some(loaded) else {
    fail("remote conversation disappeared")
  }
  assert_eq(loaded.messages[0].text(), Some("remote loaded"))
}

///|
test "reselecting a synced active session reloads idle external writes" {
  let dispatch = test_dispatch()
  let model = test_model().with_dev(dev => {
    ..dev,
    sessions: [
      {
        id: "desktop-test",
        title: Some(""),
        workspace: @interop.ChannelId::Local.test_project(),
        workspace_name: "",
        updated_at_ms: None,
      },
    ],
  })
  let (_, reloading) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-test"),
    model,
  )
  assert_true(
    reloading.loading_conversation
    is Some({ channel: Local, session: "desktop-test", }),
  )
  guard reloading.active().sync is Reloading(generation=1, attempt=1, ..) else {
    fail("expected active reselect to catch up")
  }
  let (_, still_single_flight) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-test"),
    reloading,
  )
  inspect(still_single_flight.transcript_request_generation, content="1")
  guard still_single_flight.active().sync
    is Reloading(generation=1, attempt=1, ..) else {
    fail("active reselect duplicated an in-flight request")
  }
  let (_, loaded) = update_dev(
    dispatch,
    SessionLoaded(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[
        {
          kind: Assistant(
            reasoning=None,
            prose=Some("written elsewhere"),
            calls=[],
            replay=false,
            finished=false,
          ),
          ts: None,
          sequence: None,
        },
      ],
      watermark=1,
      generation=1,
    ),
    still_single_flight,
  )
  inspect(loaded.active().messages.length(), content="1")
  assert_eq(loaded.active().messages[0].text(), Some("written elsewhere"))
  inspect(loaded.active().watermark, content="1")
  assert_true(loaded.active().sync is Synced)
}

///|
test "returning to a fresh active chat does not load a missing session" {
  let dispatch = test_dispatch()
  let model = {
    ..test_model().replace_conversation({
      ..test_conversation(),
      task: "unsent draft",
    }),
    screen: Skills,
  }
  let (_, next) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-test"),
    model,
  )
  assert_true(next.screen is Chat)
  assert_true(next.loading_conversation is None)
  inspect(next.transcript_request_generation, content="0")
  assert_true(next.active().sync is Synced)
  inspect(next.active().task, content="unsent draft")
}

///|
test "pruning and reopening cannot reuse a transcript request token" {
  let dispatch = test_dispatch()
  let (_, opening) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-pruned"),
    test_model().with_listed(["desktop-pruned"]),
  )
  guard opening.find_conversation(@interop.ChannelId::Local, "desktop-pruned")
    is Some(first) &&
    first.sync is Reloading(generation=1, ..) else {
    fail("expected the original request")
  }
  let pruned = opening.activate(
    @interop.ChannelId::Local,
    "desktop-other",
    @interop.ChannelId::Local.test_project(),
  )
  assert_true(
    pruned.find_conversation(@interop.ChannelId::Local, "desktop-pruned")
    is None,
  )
  let (_, reopened) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-pruned"),
    pruned,
  )
  guard reopened.find_conversation(@interop.ChannelId::Local, "desktop-pruned")
    is Some(second) &&
    second.sync is Reloading(generation=2, ..) else {
    fail("reopened conversation reused its old request token")
  }
  let (_, stale) = update_dev(
    dispatch,
    SessionLoaded(
      goal=None,
      goal_markers=[],
      session="desktop-pruned",
      items=[{ kind: User("late old snapshot"), ts: None, sequence: None, }],
      watermark=9,
      generation=1,
    ),
    reopened,
  )
  assert_true(
    stale.loading_conversation
    is Some({ channel: Local, session: "desktop-pruned", }),
  )
  guard stale.find_conversation(@interop.ChannelId::Local, "desktop-pruned")
    is Some(current) &&
    current.sync is Reloading(generation=2, ..) else {
    fail("late reply changed the reopened conversation")
  }
  inspect(current.messages.length(), content="0")
  inspect(current.watermark, content="0")
  let (_, fresh) = update_dev(
    dispatch,
    SessionLoaded(
      goal=None,
      goal_markers=[],
      session="desktop-pruned",
      items=[{ kind: User("fresh snapshot"), ts: None, sequence: None, }],
      watermark=1,
      generation=2,
    ),
    stale,
  )
  inspect(fresh.active_session, content="desktop-pruned")
  assert_eq(fresh.active().messages[0].text(), Some("fresh snapshot"))
}

///|
test "archive removal and reopening cannot reuse a transcript request token" {
  let dispatch = test_dispatch()
  let (_, opening) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-archived"),
    test_model().with_listed(["desktop-archived"]),
  )
  let (_, archived) = update(
    dispatch,
    archived_loaded([archived_item("desktop-archived")]),
    opening,
  )
  assert_true(
    archived.find_conversation(@interop.ChannelId::Local, "desktop-archived")
    is None,
  )
  let (_, restored) = update(dispatch, archived_loaded([]), archived)
  // Archiving pruned the live row; the list refresh that follows an
  // unarchive is what puts it back, and the row is what names its store.
  let (_, reopened) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-archived"),
    restored.with_listed(["desktop-archived"]),
  )
  guard reopened.find_conversation(
      @interop.ChannelId::Local,
      "desktop-archived",
    )
    is Some(current) &&
    current.sync is Reloading(generation=2, ..) else {
    fail("archive removal allowed a request token to be reused")
  }
  let (_, stale) = update_dev(
    dispatch,
    SessionLoaded(
      goal=None,
      goal_markers=[],
      session="desktop-archived",
      items=[
        { kind: User("late archived snapshot"), ts: None, sequence: None, },
      ],
      watermark=4,
      generation=1,
    ),
    reopened,
  )
  guard stale.find_conversation(@interop.ChannelId::Local, "desktop-archived")
    is Some(unchanged) &&
    unchanged.sync is Reloading(generation=2, ..) else {
    fail("late pre-archive reply changed the reopened conversation")
  }
  inspect(unchanged.messages.length(), content="0")
  inspect(unchanged.watermark, content="0")
}

///|
test "an abandoned session load retries silently" {
  let dispatch = test_dispatch()
  let (_, loading) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-a"),
    test_model().with_listed(["desktop-a"]),
  )
  let (_, abandoned) = update(dispatch, NewChat, loading)
  let (_, next) = update_dev(
    dispatch,
    SessionLoadFailed(
      session="desktop-a",
      message="failed to load session desktop-a",
      generation=1,
    ),
    abandoned,
  )
  assert_true(next.loading_conversation is None)
  inspect(next.active().messages.length(), content="0")
  inspect(next.notifications.length(), content="0")
}

///|
test "a foreground load preserves state through retries and reports exhaustion" {
  let dispatch = test_dispatch()
  let (_, loading) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-a"),
    test_model().with_listed(["desktop-a"]),
  )
  let failure = SessionLoadFailed(
    session="desktop-a",
    message="failed to load session desktop-a: no such file",
    generation=1,
  )
  let (_, retrying2) = update_dev(dispatch, failure, loading)
  assert_true(
    retrying2.loading_conversation
    is Some({ channel: Local, session: "desktop-a", }),
  )
  inspect(retrying2.notifications.length(), content="0")
  guard retrying2.find_conversation(@interop.ChannelId::Local, "desktop-a")
    is Some(conv2) &&
    conv2.sync is Reloading(attempt=2, ..) else {
    fail("expected the second foreground attempt")
  }
  let (_, retrying3) = update_dev(dispatch, failure, retrying2)
  guard retrying3.find_conversation(@interop.ChannelId::Local, "desktop-a")
    is Some(conv3) &&
    conv3.sync is Reloading(attempt=3, ..) else {
    fail("expected the third foreground attempt")
  }
  let (_, next) = update_dev(dispatch, failure, retrying3)
  assert_true(next.loading_conversation is None)
  inspect(next.notifications.length(), content="1")
  inspect(
    next.notifications[0].message,
    content="Transcript refresh failed repeatedly. New commits are buffered; reopen the conversation or wait for the next update to retry. (failed to load session desktop-a: no such file)",
  )
  guard next.find_conversation(@interop.ChannelId::Local, "desktop-a")
    is Some(failed) else {
    fail("expected the failed conversation")
  }
  assert_true(failed.sync is ReloadFailed(..))
  assert_true(
    next.notifications[0].message.has_prefix(TranscriptRefreshFailedNotice),
  )
  // The conversation on screen keeps its transcript and status untouched.
  inspect(next.active().messages.length(), content="0")
  assert_true(next.display_status() is Ready)
}

///|
test "a host action failure pops a toast" {
  let dispatch = test_dispatch()
  let (_, next) = update(
    dispatch,
    HostActionFailed("open path failed: no opener"),
    test_model(),
  )
  inspect(next.notifications.length(), content="1")
  inspect(next.notifications[0].message, content="open path failed: no opener")
}

///|
test "a saved export that could not open pops a toast" {
  let dispatch = test_dispatch()
  let model = test_model()
  let (_, first) = update(
    dispatch,
    SessionExportOpenFailed(path="/exports/conversation.html"),
    model,
  )
  let (_, second) = update(
    dispatch,
    SessionExportOpenFailed(path="/exports/conversation.html"),
    model,
  )
  inspect(first.notifications.length(), content="1")
  inspect(
    first.notifications[0].message,
    content="Saved to /exports/conversation.html, but couldn't open it automatically.",
  )
  assert_eq(first.notification_seq, second.notification_seq)
  assert_eq(first.notifications.length(), second.notifications.length())
  assert_eq(first.notifications[0].message, second.notifications[0].message)
}

///|
test "a file-link host failure is visible only for the latest navigation" {
  let dispatch = test_dispatch()
  let model = test_model()
  let owner : @interop.ConversationKey = {
    channel: model.focused,
    session: model.active().session_id,
  }
  let newer = model.begin_editor_navigation()
  let (_, stale) = update(
    dispatch,
    OpenFileFailed(owner~, generation=0, message="old path failed"),
    newer,
  )
  inspect(stale.notifications.length(), content="0")
  let (_, current) = update(
    dispatch,
    OpenFileFailed(owner~, generation=1, message="current path failed"),
    newer,
  )
  inspect(current.notifications.length(), content="1")
  inspect(current.notifications[0].message, content="current path failed")
}

///|
test "a Codex file-link failure is fenced by the selected Codex task" {
  let dispatch = test_dispatch()
  let codex = @codex.State::from_thread_snapshot({
    "thread": {
      "id": "codex-thread-1",
      "preview": "Open a file",
      "cwd": "/work/codex-project",
      "turns": [],
    },
  })
  let model = { ..test_model(), codex, screen: Codex, }.begin_editor_navigation()
  let hidden_openseek : @interop.ConversationKey = {
    channel: model.focused,
    session: model.active().session_id,
  }
  let codex_owner : @interop.ConversationKey = {
    channel: model.focused,
    session: "codex-thread-1",
  }
  let (_, hidden) = update(
    dispatch,
    OpenFileFailed(
      owner=hidden_openseek,
      generation=1,
      message="hidden OpenSeek failure",
    ),
    model,
  )
  inspect(hidden.notifications.length(), content="0")
  let message = OpenFileFailed(
    owner=codex_owner,
    generation=1,
    message="Codex path failed",
  )
  let (_, first) = update(dispatch, message, model)
  let (_, second) = update(dispatch, message, model)
  inspect(first.notifications.length(), content="1")
  inspect(first.notifications[0].message, content="Codex path failed")
  assert_true(first.notifications == second.notifications)
  assert_eq(first.notification_seq, second.notification_seq)
}

///|
test "opening an external link is a pure model transition" {
  let dispatch = test_dispatch()
  let base = test_model()
  let (_, first) = update(
    dispatch,
    ExternalLinkClicked("https://example.com/docs"),
    base,
  )
  let (_, second) = update(
    dispatch,
    ExternalLinkClicked("https://example.com/docs"),
    base,
  )
  inspect(first.active_session, content="desktop-test")
  inspect(second.active_session, content="desktop-test")
  inspect(first.notifications.length(), content="0")
  inspect(second.notifications.length(), content="0")
}

///|
test "run semantic errors never duplicate their terminal commit" {
  let dispatch = test_dispatch()
  let semantic = Error(
    run_id=Some("r7"),
    message="engine error",
    diagnostics=None,
    exit_code=None,
  )
  let terminal = SessionCommitted(
    session="desktop-test",
    sequence=1,
    ts=None,
    item=@protocol.Terminal(@protocol.Failed("engine error")),
    session_root=@interop.ChannelId::Local.test_store_root(),
  )
  let (_, semantic_first) = update_dev(dispatch, semantic, running_model())
  let (_, committed_after) = update_dev(dispatch, terminal, semantic_first)
  inspect(committed_after.active().messages.length(), content="1")
  let (_, committed_first) = update_dev(dispatch, terminal, running_model())
  let (_, semantic_after) = update_dev(dispatch, semantic, committed_first)
  inspect(semantic_after.active().messages.length(), content="1")
}

///|
test "a process-exit error reports its host diagnostics as a toast" {
  let dispatch = test_dispatch()
  let (_, next) = update_dev(
    dispatch,
    Error(
      run_id=Some("r7"),
      message="engine process exited",
      diagnostics=Some("fatal stderr"),
      exit_code=Some(9),
    ),
    running_model(),
  )
  // The record will never carry this text, so the transcript is the wrong
  // place for it: no durable event can ever say where it belongs.
  inspect(next.notifications.length(), content="1")
  assert_true(next.notifications[0].message.contains("fatal stderr"))
}

///|
test "agent error decoder preserves exit codes and normalizes missing messages" {
  guard error_msg({
      run_id: Some("r7"),
      message: Some("exited"),
      exit_code: Some(9),
      diagnostics: None,
    })
    is Some(Error(exit_code=Some(9), ..)) else {
    fail("expected the exit code")
  }
  guard error_msg({
      run_id: None,
      message: None,
      exit_code: None,
      diagnostics: None,
    })
    is Some(Error(message="error", ..)) else {
    fail("expected the generic error label")
  }
}

///|
test "session loaded swaps the active conversation onto the stored session" {
  let dispatch = test_dispatch()
  let model = test_model()
    .replace_conversation({
      ..test_conversation(),
      messages: [{ kind: User("old chat"), ts: None, sequence: None, }],
      turn: {
        ..test_conversation().turn,
        usage_tokens: 42,
        streaming_response: Some("leftover"),
      },
    })
    // The stored session is opened from its sidebar row, which is what
    // names the store it is read from.
    .with_dev(dev => {
      ..dev,
      sessions: [
        {
          id: "desktop-stored",
          title: Some("stored"),
          workspace: @interop.ChannelId::Local.test_project(),
          workspace_name: "work",
          updated_at_ms: None,
        },
      ],
    })
  let (_, loading) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-stored"),
    model,
  )
  let items : Array[@transcript.TranscriptItem] = [
    { kind: User("stored question"), ts: None, sequence: None, },
    {
      kind: Assistant(
        reasoning=None,
        prose=Some("stored answer"),
        calls=[],
        replay=false,
        finished=false,
      ),
      ts: None,
      sequence: None,
    },
  ]
  let (_, once) = update_dev(
    dispatch,
    SessionLoaded(
      goal=None,
      goal_markers=[],
      session="desktop-stored",
      items~,
      watermark=0,
      generation=1,
    ),
    loading,
  )
  let (_, twice) = update_dev(
    dispatch,
    SessionLoaded(
      goal=None,
      goal_markers=[],
      session="desktop-stored",
      items~,
      watermark=0,
      generation=1,
    ),
    loading,
  )
  inspect(once.active_session, content="desktop-stored")
  inspect(once.active().messages.length(), content="2")
  assert_eq(once.active().messages[0].text(), Some("stored question"))
  assert_eq(once.active().turn.streaming_response, None)
  inspect(once.active().turn.usage_tokens, content="0")
  assert_eq(
    once.active().workspace,
    Project(root=@interop.ChannelId::Local.test_project()),
  )
  assert_true(once.display_status() is Ready)
  inspect(twice.active().messages.length(), content="2")
}

///|
test "session loaded adopts the store transcript and keeps live run state" {
  let dispatch = test_dispatch()
  let model = running_model().with_listed(["desktop-stored"])
  let items : Array[@transcript.TranscriptItem] = [
    { kind: User("stored"), ts: None, sequence: None, },
  ]
  // The active conversation runs; loading some other stored session is fine.
  let (_, loading_other) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-stored"),
    model,
  )
  let (_, other) = update_dev(
    dispatch,
    SessionLoaded(
      goal=None,
      goal_markers=[],
      session="desktop-stored",
      items~,
      watermark=0,
      generation=1,
    ),
    loading_other,
  )
  inspect(other.active_session, content="desktop-stored")
  guard other.find_conversation(@interop.ChannelId::Local, "desktop-test")
    is Some(live) else {
    fail("expected the running conversation to survive")
  }
  inspect(live.is_running(), content="true")
  // A load reply for the running conversation itself adopts the store's
  // transcript — the source of truth for completed items — while the live
  // run state (phase, streaming buffers) rides across untouched.
  let streaming = running_model().replace_conversation({
    ..running_conversation(),
    turn: {
      ..running_conversation().turn,
      streaming_response: Some("mid-step"),
    },
  })
  let loading_same = {
    ..streaming.replace_conversation({
      ..streaming.active(),
      sync: test_reloading([]),
    }),
    loading_conversation: Some({ channel: Local, session: "desktop-test", }),
  }
  let (_, same) = update_dev(
    dispatch,
    SessionLoaded(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items~,
      watermark=0,
      generation=1,
    ),
    loading_same,
  )
  inspect(same.active().messages.length(), content="1")
  assert_eq(same.active().messages[0].text(), Some("stored"))
  inspect(same.active().is_running(), content="true")
  assert_eq(same.active().turn.streaming_response, Some("mid-step"))
}

///|
test "started routes by session without restating its placement" {
  let dispatch = test_dispatch()
  let (_, next) = update_dev(
    dispatch,
    Started(
      run_id="r7",
      session="desktop-test",
      model=DsPro,
      max_steps=1000,
      session_root=None,
      submission_id=None,
    ),
    test_model(),
  )
  // A rootless Started names no store, so it must not restate placement: the
  // conversation keeps the project it already had.
  assert_true(next.active().workspace is Project(..))
  assert_true(
    next.conversation_root(next.active()) is Some(root) && root.path == "/work",
  )
  inspect(next.active().is_running(), content="true")
  guard next.active().run is Open(run_id="r7", ..) else {
    fail("expected the run id to be recorded")
  }
  // A run this client did not send: the store gained its prompt, so the
  // on-screen conversation re-reads it in the background, buffering commits
  // until the snapshot lands. The user-load marker stays free.
  assert_true(next.active().sync is Reloading(..))
  assert_true(next.loading_conversation is None)
}

///|
test "started decoder preserves optional placement and submission id" {
  guard started_msg(@interop.ChannelId::Local, {
      run_id: "r7",
      submission_id: Some("submission-7"),
      engine: None,
      model: Some("deepseek-v4-pro"),
      max_steps: Some(1000),
      session: "desktop-test",
      session_root: Some("/work/core/.openseek"),
    })
    is Some(Started(session_root~, submission_id~, ..)) else {
    fail("placement or submission id was lost while decoding Started")
  }
  assert_true(
    session_root is Some(resource) && resource.path == "/work/core/.openseek",
  )
  assert_eq(submission_id, Some("submission-7"))
}

///|
test "host path decoders reject relative placement and diagnostic paths" {
  let payload : @protocol.StartedPayload = {
    run_id: "r7",
    submission_id: None,
    engine: None,
    model: Some("deepseek-v4-pro"),
    max_steps: Some(1000),
    session: "desktop-test",
    session_root: Some("relative/session-root"),
  }
  assert_true(started_msg(@interop.ChannelId::Local, payload) is None)
  assert_true(
    RecoveredRun::from_started(@interop.ChannelId::Local, payload) is None,
  )
  assert_true(
    diagnostics_msg(@interop.ChannelId::Local, {
      root: "relative/workspace",
      path: "relative/file.mbt",
      diagnostics: [],
    })
    is None,
  )
}

///|
test "started for an unknown session materializes its conversation" {
  let dispatch = test_dispatch()
  let (_, next) = update_dev(
    dispatch,
    Started(
      run_id="r7",
      session="desktop-ghost",
      model=DsPro,
      max_steps=1000,
      session_root=Some(@interop.ChannelId::Local.test_store_root()),
      submission_id=None,
    ),
    test_model(),
  )
  // Another client's run is now trackable here: cancellable, steerable,
  // and its events route to a real conversation.
  guard next.find_conversation(@interop.ChannelId::Local, "desktop-ghost")
    is Some(ghost) else {
    fail("expected the foreign run's conversation to materialize")
  }
  inspect(ghost.is_running(), content="true")
  guard ghost.run is Open(run_id="r7", ..) else {
    fail("expected the run id to be recorded")
  }
  // No bubble is synthesized from the pushed task — the durable transcript's
  // only sources are snapshots and commits, and the prompt's own commit (or
  // the read when this conversation is opened) brings it.
  inspect(ghost.messages.length(), content="0")
  // Focus stays where the user is.
  inspect(next.active_session, content="desktop-test")
  inspect(next.active().is_running(), content="false")
  // A run whose store this page cannot place has no directory to work in
  // and no store to read from, so there is nothing to materialize.
  let (_, rootless) = update_dev(
    dispatch,
    Started(
      run_id="r8",
      session="desktop-rootless",
      model=DsPro,
      max_steps=1000,
      session_root=None,
      submission_id=None,
    ),
    test_model(),
  )
  assert_true(
    rootless.find_conversation(@interop.ChannelId::Local, "desktop-rootless")
    is None,
  )
}

///|
/// Started is where a foreign conversation gets its placement, and it
/// precedes the first commit — so on a fresh connection, whose projects
/// registry is still in flight, the run's own store root has to name the
/// project. Otherwise terminal and file operations would have nowhere to
/// point until the session list lands.
test "started places a conversation before the registry arrives" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/work/foreign")
  let store = @interop.ChannelId::Local.test_resource("/work/foreign/.openseek")
  fn start(model, session, session_root) {
    let (_, next) = update_dev(
      dispatch,
      Started(
        run_id="r9",
        session~,
        model=DsPro,
        max_steps=1000,
        session_root~,
        submission_id=None,
      ),
      model,
    )
    next
  }

  // The registry is empty: the store layout is the only evidence, and it
  // names the project.
  let unregistered = start(test_model(), "desktop-foreign", Some(store))
  guard unregistered.find_conversation(
      @interop.ChannelId::Local,
      "desktop-foreign",
    )
    is Some(placed) else {
    fail("expected the foreign run's conversation to materialize")
  }
  assert_eq(placed.workspace, Project(root=workspace))
  // A registered project resolves the same way it always did.
  let registered = start(
    test_model().with_dev(dev => { ..dev, projects: [workspace], }),
    "desktop-registered",
    Some(store),
  )
  guard registered.find_conversation(
      @interop.ChannelId::Local,
      "desktop-registered",
    )
    is Some(known) else {
    fail("expected the registered run's conversation to materialize")
  }
  assert_eq(known.workspace, Project(root=workspace))
}

///|
test "a run boundary discards the previous turn's live state whole" {
  let dispatch = test_dispatch()
  let lane : @subrun.Lane = {
    id: "sub-1",
    kind: "task",
    label: "sub-run",
    steps: 2,
    activity: "running",
    run: Some("r-old"),
  }
  let conv = {
    ..running_conversation(),
    run: Open(run_id="r-old", stage=AtStep(Some(3))),
    turn: {
      streaming_response: Some("old answer fragment"),
      live_reasoning: None,
      reasoning_frontier: 0,
      subruns: [lane],
      usage_tokens: 4200,
    },
  }
  let (_, next) = update_dev(
    dispatch,
    Started(
      run_id="r-new",
      session="desktop-test",
      model=DsPro,
      max_steps=1000,
      session_root=None,
      submission_id=None,
    ),
    running_model().replace_conversation(conv),
  )
  // Nothing the previous turn accumulated belongs to this one, and none of it
  // has to be cleared field by field to stay out.
  guard next.active().run is Open(run_id="r-new", ..) else {
    fail("expected the new run to replace the old id")
  }
  assert_eq(next.active().turn.streaming_response, None)
  inspect(next.active().turn.subruns.length(), content="0")
  inspect(next.active().turn.usage_tokens, content="0")
}

///|
test "a distinct started id replaces a stale open run as foreign" {
  let dispatch = test_dispatch()
  let conv = with_pending_steers(
    {
      ..running_conversation(),
      run: Open(run_id="r-old", stage=AtStep(Some(3))),
      turn: {
        ..running_conversation().turn,
        streaming_response: Some("old answer fragment"),
      },
      run_started_ms: Some(1_000.0),
    },
    ["old steer"],
    run_id="r-old",
  )
  let model = running_model().replace_conversation(conv)
  let (_, next) = update_dev(
    dispatch,
    Started(
      run_id="r-new",
      session="desktop-test",
      model=DsPro,
      max_steps=1000,
      session_root=None,
      submission_id=None,
    ),
    model,
  )
  guard next.active().run is Open(run_id="r-new", stage=Opened) else {
    fail("expected the new run to replace the stale id")
  }
  assert_eq(next.active().turn.streaming_response, None)
  inspect(next.active().pending_steers.length(), content="0")
  // The replaced run took its pending input with it and left no placeholder:
  // what the turn actually recorded is in the transcript.
  guard next.active().sync is Reloading(generation=1, attempt=1, ..) else {
    fail("a foreign replacement did not refresh the transcript")
  }
  // The replaced run's start belonged to the run that just lost the seat.
  // Carrying it over would age the new run from a moment it never had.
  assert_eq(next.active().run_started_ms, None)
}

///|
test "a repeated started id is idempotent" {
  let dispatch = test_dispatch()
  let conv = with_pending_steers(
    {
      ..running_conversation(),
      run: Open(run_id="r7", stage=AtStep(Some(4))),
      turn: {
        ..running_conversation().turn,
        streaming_response: Some("current fragment"),
      },
    },
    ["current steer"],
  )
  let model = running_model().replace_conversation(conv)
  let (_, next) = update_dev(
    dispatch,
    Started(
      run_id="r7",
      session="desktop-test",
      model=DsPro,
      max_steps=1000,
      session_root=None,
      submission_id=None,
    ),
    model,
  )
  guard next.active().run is Open(run_id="r7", stage=AtStep(Some(4))) else {
    fail("a repeated start reset the live run stage")
  }
  assert_eq(next.active().turn.streaming_response, Some("current fragment"))
  inspect(next.active().pending_steers.length(), content="1")
  assert_eq(next.active().pending_steers[0].content, "current steer")
  inspect(next.transcript_request_generation, content="0")
  assert_true(next.active().sync is Synced)
}

///|
test "a start failure cannot close a run opened by a winning push" {
  let dispatch = test_dispatch()
  let starting_conv = with_pending_prompt(
    { ..test_conversation(), run: Starting(submission_id="mine"), },
    "mine",
    "my competing prompt",
  )
  let starting = test_model().replace_conversation(starting_conv)
  let (_, opened) = update_dev(
    dispatch,
    Started(
      run_id="r-foreign",
      session="desktop-test",
      model=DsPro,
      max_steps=1000,
      session_root=None,
      submission_id=Some("theirs"),
    ),
    starting,
  )
  let opened = opened.replace_conversation(
    with_pending_steers(
      {
        ..opened.active(),
        turn: {
          ..opened.active().turn,
          streaming_response: Some("foreign fragment"),
        },
      },
      ["steer for foreign run"],
      run_id="r-foreign",
    ),
  )
  let (_, failed) = update_dev(
    dispatch,
    StartRejected(
      session="desktop-test",
      submission_id="mine",
      message="start was rejected",
    ),
    opened,
  )
  guard failed.active().run is Open(run_id="r-foreign", stage=Opened) else {
    fail("the local failure closed the already-open run")
  }
  assert_eq(failed.active().turn.streaming_response, Some("foreign fragment"))
  inspect(failed.active().pending_steers.length(), content="1")
  inspect(
    failed.active().pending_steers[0].content,
    content="steer for foreign run",
  )
  inspect(failed.active().task, content="my competing prompt")
  inspect(failed.notifications.length(), content="1")
  inspect(failed.notifications[0].message, content="start was rejected")
  guard failed.active().sync is Reloading(generation=1, ..) else {
    fail("the raced start failure did not catch up the transcript")
  }
}

///|
test "a start failure closes only a still-starting run" {
  let dispatch = test_dispatch()
  let conv = with_pending_prompt(
    {
      ..test_conversation(),
      run: Starting(submission_id="prompt-id"),
      turn: { ..test_conversation().turn, streaming_response: Some("partial"), },
    },
    "prompt-id",
    "prompt",
  )
  let model = test_model().replace_conversation(conv)
  let (_, failed) = update_dev(
    dispatch,
    StartRejected(
      session="desktop-test",
      submission_id="prompt-id",
      message="start failed",
    ),
    model,
  )
  assert_true(failed.active().run is NoRun(ended=Some(RunFailed)))
  assert_eq(failed.active().turn.streaming_response, None)
  inspect(failed.notifications.length(), content="1")
  inspect(failed.active().task, content="prompt")
  inspect(failed.transcript_request_generation, content="0")
}

///|
test "a matching Started establishes the run after an undelivered response" {
  let dispatch = test_dispatch()
  let conv = with_pending_prompt(
    { ..test_conversation(), run: Starting(submission_id="prompt-id"), },
    "prompt-id",
    "accepted prompt",
  )
  let (_, failed) = update_dev(
    dispatch,
    StartUndelivered(
      session="desktop-test",
      submission_id="prompt-id",
      message="connection lost",
    ),
    test_model().replace_conversation(conv),
  )
  let (_, started) = update_dev(
    dispatch,
    Started(
      run_id="r-recovered",
      session="desktop-test",
      model=DsPro,
      max_steps=1000,
      session_root=None,
      submission_id=Some("prompt-id"),
    ),
    failed,
  )
  // The lost response ended the entry and left no notice behind; a Started
  // that arrives anyway is still the run's exact identity.
  assert_true(started.active().run is Open(run_id="r-recovered", ..))
  inspect(started.active().pending_steers.length(), content="0")
}

///|
test "an accepted start response opens the run without Started" {
  let dispatch = test_dispatch()
  let conv = with_pending_prompt(
    { ..test_conversation(), run: Starting(submission_id="prompt-id"), },
    "prompt-id",
    "prompt",
  )
  let (_, responded) = update_dev(
    dispatch,
    StartResponded(
      session="desktop-test",
      submission_id="prompt-id",
      run_id="r-response",
      status="accepted",
      exit_code=0,
    ),
    test_model().replace_conversation(conv),
  )
  assert_true(responded.active().run is Open(run_id="r-response", ..))
  assert_true(responded.active().last_run_id is Some("r-response"))
  // The reply is the entry's last consumer: a prompt is sent once.
  inspect(responded.active().pending_steers.length(), content="0")
  assert_true(responded.active().sync is Reloading(generation=1, ..))
  let (_, started) = update_dev(
    dispatch,
    Started(
      run_id="r-response",
      session="desktop-test",
      model=DsPro,
      max_steps=1000,
      session_root=None,
      submission_id=Some("prompt-id"),
    ),
    responded,
  )
  // The delayed Started is idempotent with the response-first recovery: it
  // neither drops nor queues a second generation.
  assert_true(started.active().sync is Reloading(generation=1, ..))
  let (_, loaded) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[
        { kind: User("external prompt"), ts: None, sequence: None, },
        {
          kind: Assistant(
            reasoning=None,
            prose=Some("external answer"),
            calls=[],
            replay=false,
            finished=false,
          ),
          ts: None,
          sequence: None,
        },
        { kind: User("prompt"), ts: None, sequence: None, },
      ],
      watermark=4,
      generation=1,
    ),
    started,
  )
  assert_true(loaded.active().sync is Synced)
  inspect(loaded.active().pending_steers.length(), content="0")
}

///|
test "an old-host Started without an id is settled by the exact start response" {
  let dispatch = test_dispatch()
  let conv = with_pending_prompt(
    { ..test_conversation(), run: Starting(submission_id="prompt-id"), },
    "prompt-id",
    "prompt",
  )
  let (_, started) = update_dev(
    dispatch,
    Started(
      run_id="r-old-host",
      session="desktop-test",
      model=DsPro,
      max_steps=1000,
      session_root=None,
      submission_id=None,
    ),
    test_model().replace_conversation(conv),
  )
  assert_true(started.active().run is Open(run_id="r-old-host", ..))
  assert_true(started.active().pending_prompt is Some(_))
  let (_, responded) = update_dev(
    dispatch,
    StartResponded(
      session="desktop-test",
      submission_id="prompt-id",
      run_id="r-old-host",
      status="accepted",
      exit_code=0,
    ),
    started,
  )
  // The id-less Started could not settle the entry; the exact response can.
  assert_true(responded.active().run is Open(run_id="r-old-host", ..))
  inspect(responded.active().pending_steers.length(), content="0")
}

///|
test "a late accepted response settles run A without replacing open run B" {
  let dispatch = test_dispatch()
  guard second_run_started_before_first_response() is Some(result) else {
    fail("expected the second prompt to be starting")
  }
  let (second_started, second_submission) = result
  let (_, responded) = update_dev(
    dispatch,
    StartResponded(
      session="desktop-test",
      submission_id="first-start",
      run_id="r-first",
      status="accepted",
      exit_code=0,
    ),
    second_started,
  )
  assert_true(responded.active().run is Open(run_id="r-second", ..))
  assert_true(responded.active().last_run_id is Some("r-second"))
  guard responded.active().pending_prompt is Some(still_pending) else {
    fail("the late reply consumed the newer submission")
  }
  inspect(still_pending.submission_id, content=second_submission)
}

///|
test "a late failed response for durable run A cannot disturb open run B" {
  let dispatch = test_dispatch()
  guard second_run_started_before_first_response() is Some(result) else {
    fail("expected the second prompt to be starting")
  }
  let (second_started, second_submission) = result
  let (_, responded) = update_dev(
    dispatch,
    StartResponded(
      session="desktop-test",
      submission_id="first-start",
      run_id="r-first",
      status="failed",
      exit_code=1,
    ),
    second_started,
  )
  assert_true(responded.active().run is Open(run_id="r-second", ..))
  assert_true(responded.active().last_run_id is Some("r-second"))
  guard responded.active().pending_prompt is Some(still_pending) else {
    fail("the late reply consumed the newer submission")
  }
  inspect(still_pending.submission_id, content=second_submission)
}

///|
test "runs settled closes runs the host no longer has, sparing live and starting ones" {
  let dispatch = test_dispatch()
  // A run that ended while this client was away: its terminal event is
  // gone for good, so only the `agent.runs` reply can close it.
  let stale = {
    ..empty_conversation(
      @interop.ChannelId::Local,
      "desktop-stale",
      @interop.ChannelId::Local.test_project(),
    ),
    run: Open(run_id="r9", stage=AtStep(Some(4))),
    turn: {
      ..empty_conversation(
        @interop.ChannelId::Local,
        "desktop-stale",
        @interop.ChannelId::Local.test_project(),
      ).turn,
      streaming_response: Some("mid-step"),
    },
  }
  // A send still in flight has no run id yet; its own `started` (or
  // failure) is coming and must be the one to settle it.
  let starting = {
    ..empty_conversation(
      @interop.ChannelId::Local,
      "desktop-starting",
      @interop.ChannelId::Local.test_project(),
    ),
    run: Starting(submission_id="pending-start"),
  }
  let model = running_model()
    .replace_conversation(stale)
    .replace_conversation(starting)
  let (_, next) = update_dev(
    dispatch,
    RunsSettled(live=["r7"], frontier=[
      {
        session: "desktop-test",
        state: SnapshotOpen(run_id="r7"),
        initial_ids: [],
        pending_approval_id: None,
      },
      {
        session: "desktop-stale",
        state: SnapshotOpen(run_id="r9"),
        initial_ids: [],
        pending_approval_id: None,
      },
    ]),
    model,
  )
  // Run 7 is still in flight on the host: untouched.
  inspect(next.active().is_running(), content="true")
  guard next.find_conversation(@interop.ChannelId::Local, "desktop-stale")
    is Some(settled) else {
    fail("expected the stale conversation")
  }
  inspect(settled.is_running(), content="false")
  assert_eq(settled.turn.streaming_response, None)
  guard settled.run is NoRun(ended=None) else {
    fail("expected the stale run to settle without a verdict")
  }
  guard next.find_conversation(@interop.ChannelId::Local, "desktop-starting")
    is Some(sending) else {
    fail("expected the starting conversation")
  }
  assert_true(sending.run is Starting(..))
}

///|
test "reconnect runs snapshot settles only its captured Starting submission" {
  let dispatch = test_dispatch()
  let conv = with_pending_prompt(
    { ..test_conversation(), run: Starting(submission_id="pre-gap-start"), },
    "pre-gap-start",
    "maybe accepted",
  )
  let (_, bridged) = update_dev(
    dispatch,
    BridgeReady,
    test_model().replace_conversation(conv),
  )
  // The gap ended the entry: no receipt can cross it.
  inspect(bridged.active().pending_steers.length(), content="0")
  let (_, settled) = update_dev(
    dispatch,
    RunsSettled(
      live=[],
      frontier=bridged.run_snapshot_frontier(@interop.ChannelId::Local),
    ),
    bridged,
  )
  assert_true(settled.active().run is NoRun(ended=None))
}

///|
test "reconnect recovers a Finished notification dropped behind a slow page" {
  let dispatch = test_dispatch()
  // The host has already finished r7, but this page missed that one live
  // notification and still presents the run as open.
  let (_, bridged) = update_dev(dispatch, BridgeReady, running_model())
  let frontier = bridged.run_snapshot_frontier(@interop.ChannelId::Local)
  let (_, recovered) = update_dev(
    dispatch,
    RunsLoaded(
      runs=[],
      settled=[
        {
          run_id: "r7",
          session: "desktop-test",
          submission_id: None,
          status: "finished",
        },
      ],
      approvals=[],
      live=[],
      frontier~,
      connection_generation=bridged.dev().connection_generation,
    ),
    bridged,
  )
  assert_true(
    recovered.active().run is NoRun(ended=Some(RunFinished(Completed))),
  )
  assert_true(recovered.active().last_run_id is Some("r7"))
}

///|
test "an old empty runs snapshot cannot close a start sent after reconnect" {
  let dispatch = test_dispatch()
  let (_, bridged) = update_dev(dispatch, BridgeReady, test_model())
  // A reconnect clears the host-settings mirror; the refetch that follows
  // restores the saved key (the BYOK fixture is a ready app).
  let (_, ready) = update_dev(
    dispatch,
    HostSettingsLoaded(
      host_settings(provider="deepseek", has_deepseek_key=true),
      connection_generation=None,
    ),
    bridged,
  )
  // A reconnect drops the worktree mirror and re-requests it; path-based work
  // stays parked until it answers, so restore it before sending.
  let ready = ready.with_dev(dev => {
    ..dev,
    worktrees: [@interop.ChannelId::Local.test_worktrees()],
  })
  let drafted = ready.replace_conversation({
    ..ready.active(),
    task: "new prompt",
  })
  let (_, sent) = update(dispatch, Send, drafted)
  assert_true(sent.active().run is Starting(..))
  // The submit is where the user's wait begins, so the elapsed span the tail
  // lane reports has to be established here — before any host round trip.
  assert_true(sent.active().run_started_ms is Some(_))
  let (_, stale_snapshot) = update_dev(
    dispatch,
    RunsSettled(live=[], frontier=[]),
    sent,
  )
  assert_true(stale_snapshot.active().run is Starting(..))
}

///|
test "an older start rejection cannot close the current start" {
  let dispatch = test_dispatch()
  let old = with_pending_prompt(
    test_conversation(),
    "older-start",
    "older prompt",
  )
  let current = with_pending_prompt(
    { ..old, run: Starting(submission_id="current-start"), },
    "current-start",
    "current prompt",
  )
  let (_, next) = update_dev(
    dispatch,
    StartRejected(
      session="desktop-test",
      submission_id="older-start",
      message="older start rejected",
    ),
    test_model().replace_conversation(current),
  )
  assert_true(next.active().run is Starting(submission_id="current-start"))
  guard next.active().pending_prompt is Some(pending) else {
    fail("the older rejection consumed the current submission")
  }
  inspect(pending.submission_id, content="current-start")
}

///|
test "a Started racing ahead of an older runs response stays open" {
  let dispatch = test_dispatch()
  let frontier = test_model().run_snapshot_frontier(@interop.ChannelId::Local)
  let (_, started) = update_dev(
    dispatch,
    Started(
      run_id="r-after-snapshot",
      session="desktop-test",
      model=DsPro,
      max_steps=1000,
      session_root=None,
      submission_id=Some("foreign-new"),
    ),
    test_model(),
  )
  let (_, stale_snapshot) = update_dev(
    dispatch,
    RunsSettled(live=[], frontier~),
    started,
  )
  assert_true(
    stale_snapshot.active().run is Open(run_id="r-after-snapshot", ..),
  )
}

///|
test "a stale runs snapshot cannot replay a foreign run after BridgeReady" {
  let dispatch = test_dispatch()
  let (_, generation_one) = update_dev(dispatch, BridgeReady, test_model())
  let stale = RunsLoaded(
    runs=[
      {
        run_id: "old-run",
        session: "old-session",
        model: DsPro,
        max_steps: 1000,
        session_root: None,
        submission_id: None,
      },
    ],
    settled=[],
    approvals=[],
    live=["old-run"],
    frontier=generation_one.run_snapshot_frontier(@interop.ChannelId::Local),
    connection_generation=generation_one.dev().connection_generation,
  )
  let (_, generation_two) = update_dev(dispatch, BridgeReady, generation_one)
  // The current generation's empty answer wins first. The delayed older
  // answer must then be rejected whole, before replaying its Started row.
  let (_, current) = update_dev(
    dispatch,
    RunsLoaded(
      runs=[],
      settled=[],
      approvals=[],
      live=[],
      frontier=generation_two.run_snapshot_frontier(@interop.ChannelId::Local),
      connection_generation=generation_two.dev().connection_generation,
    ),
    generation_two,
  )
  let (_, once) = update_dev(dispatch, stale, current)
  let (_, twice) = update_dev(dispatch, stale, current)
  assert_true(
    once.find_conversation(@interop.ChannelId::Local, "old-session") is None,
  )
  assert_true(
    twice.find_conversation(@interop.ChannelId::Local, "old-session") is None,
  )
  inspect(once.dev().connection_generation, content="2")
  inspect(twice.dev().connection_generation, content="2")
}

///|
test "a settlement captured for an older Starting owner cannot close its successor" {
  let dispatch = test_dispatch()
  let old = with_pending_prompt(
    { ..test_conversation(), run: Starting(submission_id="old-owner"), },
    "old-owner",
    "old prompt",
  )
  let frontier = test_model()
    .replace_conversation(old)
    .run_snapshot_frontier(@interop.ChannelId::Local)
  let current = with_pending_prompt(
    { ..old, run: Starting(submission_id="new-owner"), },
    "new-owner",
    "new prompt",
  )
  let model = test_model().replace_conversation(current)
  let (_, unchanged) = update_dev(
    dispatch,
    RunsLoaded(
      runs=[],
      settled=[
        {
          run_id: "old-run",
          session: "desktop-test",
          submission_id: Some("old-owner"),
          status: "failed",
        },
      ],
      approvals=[],
      live=[],
      frontier~,
      connection_generation=model.dev().connection_generation,
    ),
    model,
  )
  assert_true(unchanged.active().run is Starting(submission_id="new-owner"))
  assert_true(unchanged.active().pending_prompt is Some(_))
}

///|
test "an older positive runs row cannot replace a newer Started" {
  let dispatch = test_dispatch()
  let model = running_model()
  let frontier = model.run_snapshot_frontier(@interop.ChannelId::Local)
  let (_, finished) = update_dev(
    dispatch,
    Finished(run_id="r7", status="finished", answer=None),
    model,
  )
  let (_, newer) = update_dev(
    dispatch,
    Started(
      run_id="r8",
      session="desktop-test",
      model=DsPro,
      max_steps=1000,
      session_root=None,
      submission_id=None,
    ),
    finished,
  )
  let (_, stale) = update_dev(
    dispatch,
    RunsLoaded(
      runs=[
        {
          run_id: "r7",
          session: "desktop-test",
          model: DsPro,
          max_steps: 1000,
          session_root: None,
          submission_id: None,
        },
      ],
      settled=[],
      approvals=[],
      live=["r7"],
      frontier~,
      connection_generation=0,
    ),
    newer,
  )
  assert_true(stale.active().run is Open(run_id="r8", ..))
  assert_true(stale.active().last_run_id is Some("r8"))
}

///|
test "an older positive runs row cannot resurrect a finished run" {
  let dispatch = test_dispatch()
  let model = running_model()
  let frontier = model.run_snapshot_frontier(@interop.ChannelId::Local)
  let (_, finished) = update_dev(
    dispatch,
    Finished(run_id="r7", status="finished", answer=None),
    model,
  )
  let (_, stale) = update_dev(
    dispatch,
    RunsLoaded(
      runs=[
        {
          run_id: "r7",
          session: "desktop-test",
          model: DsPro,
          max_steps: 1000,
          session_root: None,
          submission_id: None,
        },
      ],
      settled=[],
      approvals=[],
      live=["r7"],
      frontier~,
      connection_generation=0,
    ),
    finished,
  )
  assert_true(stale.active().run is NoRun(ended=Some(RunFinished(Completed))))
  assert_true(stale.active().last_run_id is Some("r7"))
}

///|
test "Finished after RunsSettled fills the last run outcome idempotently" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    last_run_id: Some("r7"),
  })
  let (_, settled) = update_dev(
    dispatch,
    RunsSettled(
      live=[],
      frontier=model.run_snapshot_frontier(@interop.ChannelId::Local),
    ),
    model,
  )
  assert_true(settled.active().run is NoRun(ended=None))
  let finish : DeviceMsg = Finished(run_id="r7", status="finished", answer=None)
  let (_, once) = update_dev(dispatch, finish, settled)
  let (_, twice) = update_dev(dispatch, finish, once)
  assert_true(once.active().run is NoRun(ended=Some(RunFinished(Completed))))
  assert_true(twice.active().run is NoRun(ended=Some(RunFinished(Completed))))
}

///|
test "a failed response after durable Finished cannot resurrect its prompt" {
  let dispatch = test_dispatch()
  let conv = with_pending_prompt(
    { ..test_conversation(), run: Starting(submission_id="fast-start"), },
    "fast-start",
    "fast prompt",
  )
  let (_, started) = update_dev(
    dispatch,
    Started(
      run_id="r-fast",
      session="desktop-test",
      model=DsPro,
      max_steps=1000,
      session_root=None,
      submission_id=Some("fast-start"),
    ),
    test_model().replace_conversation(conv),
  )
  assert_true(started.active().pending_prompt is Some(_))
  let (_, finished) = update_dev(
    dispatch,
    Finished(run_id="r-fast", status="finished", answer=None),
    started,
  )
  assert_true(
    finished.active().run is NoRun(ended=Some(RunFinished(Completed))),
  )
  let (_, failed) = update_dev(
    dispatch,
    StartResponded(
      session="desktop-test",
      submission_id="fast-start",
      run_id="r-fast",
      status="failed",
      exit_code=1,
    ),
    finished,
  )
  assert_true(failed.active().run is NoRun(ended=Some(RunFinished(Completed))))
  inspect(failed.active().pending_steers.length(), content="0")
  let (_, empty) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[],
      watermark=0,
      generation=1,
    ),
    failed,
  )
  assert_true(empty.active().run is NoRun(ended=Some(RunFinished(Completed))))
  inspect(empty.active().pending_steers.length(), content="0")
}

///|
test "an accepted response consumes a fast-finished prompt without reopening" {
  let dispatch = test_dispatch()
  let conv = with_pending_prompt(
    {
      ..test_conversation(),
      run: NoRun(ended=Some(RunFinished(Completed))),
      last_run_id: Some("r-fast"),
    },
    "fast-start",
    "fast prompt",
  )
  let (_, accepted) = update_dev(
    dispatch,
    StartResponded(
      session="desktop-test",
      submission_id="fast-start",
      run_id="r-fast",
      status="accepted",
      exit_code=0,
    ),
    test_model().replace_conversation(conv),
  )
  assert_true(
    accepted.active().run is NoRun(ended=Some(RunFinished(Completed))),
  )
  inspect(accepted.active().pending_steers.length(), content="0")
}

///|
test "concurrent conversations keep their streams apart" {
  let dispatch = test_dispatch()
  let second = {
    ..empty_conversation(
      @interop.ChannelId::Local,
      "desktop-second",
      @interop.ChannelId::Local.test_project(),
    ),
    run: Open(run_id="r8", stage=Opened),
  }
  let model = running_model().replace_conversation(second)
  let (_, next) = update_dev(
    dispatch,
    Engine(Some("r8"), AssistantDelta("for B"), session=None),
    model,
  )
  // Run 8 belongs to the background conversation; the active one is untouched.
  assert_eq(next.active().turn.streaming_response, None)
  guard next.find_conversation(@interop.ChannelId::Local, "desktop-second")
    is Some(bg) else {
    fail("expected the background conversation")
  }
  assert_eq(bg.turn.streaming_response, Some("for B"))
}

///|
test "a background run finishes without disturbing the conversation on screen" {
  let dispatch = test_dispatch()
  let second = {
    ..empty_conversation(
      @interop.ChannelId::Local,
      "desktop-second",
      @interop.ChannelId::Local.test_project(),
    ),
    run: Open(run_id="r8", stage=Opened),
    messages: [{ kind: User("background ask"), ts: None, sequence: None, }],
  }
  let model = running_model().replace_conversation(second)
  let (_, next) = update_dev(
    dispatch,
    Finished(run_id="r8", status="finished", answer=Some("done")),
    model,
  )
  guard next.find_conversation(@interop.ChannelId::Local, "desktop-second")
    is Some(bg) else {
    fail("expected the background conversation")
  }
  inspect(bg.is_running(), content="false")
  assert_true(bg.run is NoRun(ended=Some(RunFinished(_))))
  // The conversation on screen is still running its own turn.
  inspect(next.active().is_running(), content="true")
  assert_true(next.display_status() is Running)
}

///|
test "send while running queues a steer instead of a prompt" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    task: "focus on the tests",
  })
  let (_, once) = update(dispatch, Send, model)
  let (_, twice) = update(dispatch, Send, model)
  inspect(once.active().task, content="")
  inspect(once.active().pending_steers.length(), content="1")
  assert_eq(once.active().pending_steers[0].content, "focus on the tests")
  // The steer is pending, not part of the transcript yet.
  inspect(once.active().messages.length(), content="0")
  inspect(once.active().is_running(), content="true")
  inspect(twice.active().pending_steers.length(), content="1")
  inspect(
    twice.active().pending_steers[0].content,
    content="focus on the tests",
  )
}

///|
test "a cancelling turn cannot be steered; the text stays in the composer" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    run: Open(run_id="r7", stage=Cancelling),
    task: "too late",
  })
  let (_, next) = update(dispatch, Send, model)
  inspect(next.active().task, content="too late")
  inspect(next.active().pending_steers.length(), content="0")
}

///|
test "a Stop reply for an already-ended run retires Stopping" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    run: Open(run_id="r7", stage=Cancelling),
  })
  let (_, next) = update_dev(dispatch, CancelNotOpen(run_id="r7"), model)
  assert_true(next.active().run is NoRun(ended=None))
  assert_eq(next.active().last_run_id, Some("r7"))
}

///|
test "a failed Stop becomes retryable instead of staying Stopping" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    run: Open(run_id="r7", stage=Cancelling),
  })
  let (_, next) = update_dev(
    dispatch,
    CancelFailed(run_id="r7", message="cancel transport failed"),
    model,
  )
  assert_true(next.active().run is Open(run_id="r7", stage=AtStep(None)))
  assert_true(
    next.notifications
    .iter()
    .any(item => item.message.contains("cancel transport failed")),
  )
}

///|
test "an old empty cancel reply cannot close a successor" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    run: Open(run_id="r8", stage=Opened),
  })
  let (_, next) = update_dev(dispatch, CancelNotOpen(run_id="r7"), model)
  assert_true(next.active().run is Open(run_id="r8", stage=Opened))
}

///|
test "steer_applied only settles pending UI until its commit" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation(
    with_pending_steers(running_conversation(), ["go left"]),
  )
  let (_, next) = update_dev(
    dispatch,
    Engine(
      Some("r7"),
      SteerApplied(content="go left", submission_id=Some("test-steer-0")),
      session=None,
    ),
    model,
  )
  inspect(next.active().pending_steers.length(), content="0")
  inspect(next.active().messages.length(), content="0")
}

///|
test "a legacy text-only steer receipt cannot claim local ownership" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation(
    with_pending_steers(running_conversation(), ["go left"]),
  )
  let (_, next) = update_dev(
    dispatch,
    Engine(
      Some("r7"),
      SteerApplied(content="go left", submission_id=None),
      session=None,
    ),
    model,
  )
  inspect(next.active().pending_steers.length(), content="1")
}

///|
test "a live commit dates its row on arrival, buffered or applied straight" {
  let dispatch = test_dispatch()
  let stamped = (session, sequence, ts) => {
    SessionCommitted(
      session~,
      sequence~,
      ts=Some(ts),
      item=@protocol.User({ content: "question", submission_id: None, }),
      session_root=@interop.ChannelId::Local.test_store_root(),
    )
  }
  // The contiguous-commit path a running conversation takes: the row must
  // carry its stamp now, not only after the next snapshot reload.
  let (_, direct) = update_dev(
    dispatch,
    stamped("desktop-test", 1, 1781144351123),
    running_model(),
  )
  assert_true(direct.active().messages[0].ts is Some(1781144351123))
  // The same stamp survives the buffer a reconnect drains commits through.
  let (_, reconnecting) = update_dev(dispatch, BridgeReady, running_model())
  let (_, buffered) = update_dev(
    dispatch,
    stamped("desktop-test", 1, 1781144352000),
    reconnecting,
  )
  let (_, drained) = update_dev(
    dispatch,
    SessionRefreshed(
      session="desktop-test",
      items=[],
      watermark=0,
      generation=1,
      goal=None,
      goal_markers=[],
    ),
    buffered,
  )
  assert_true(drained.active().messages[0].ts is Some(1781144352000))
}

///|
test "a canonical user commit never settles a local steer" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation(
    with_pending_steers(running_conversation(), ["go left"]),
  )
  let (_, committed) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=1,
      ts=None,
      item=@protocol.User({ content: "go left", submission_id: None, }),
      session_root=@interop.ChannelId::Local.test_store_root(),
    ),
    model,
  )
  inspect(committed.active().messages.length(), content="1")
  inspect(committed.active().pending_steers.length(), content="1")
}

///|
test "a snapshot never settles a local steer by text" {
  let dispatch = test_dispatch()
  let conv = with_pending_steers(
    {
      ..running_conversation(),
      messages: [{ kind: User("same"), ts: None, sequence: None, }],
      watermark: 1,
      sync: test_reloading([]),
    },
    ["same"],
  )
  let model = running_model().replace_conversation(conv)
  let (_, loaded) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[{ kind: User("same"), ts: None, sequence: None, }],
      watermark=1,
      generation=1,
    ),
    model,
  )
  inspect(loaded.active().pending_steers.length(), content="1")
}

///|
test "steer_dropped settles the pending steer with a visible notice" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation(
    with_pending_steers(running_conversation(), ["go left"]),
  )
  let (_, next) = update_dev(
    dispatch,
    Engine(
      Some("r7"),
      SteerDropped(content="go left", submission_id=Some("test-steer-0")),
      session=None,
    ),
    model,
  )
  inspect(next.active().pending_steers.length(), content="0")
  inspect(next.active().task, content="go left")
  inspect(next.notifications.length(), content="1")
  assert_true(next.notifications[0].message.contains("back in the composer"))
}

///|
test "an identical-text settle removes exactly one pending entry" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation(
    with_pending_steers(running_conversation(), ["again", "again"]),
  )
  let (_, next) = update_dev(
    dispatch,
    Engine(
      Some("r7"),
      SteerApplied(content="again", submission_id=Some("test-steer-0")),
      session=None,
    ),
    model,
  )
  inspect(next.active().pending_steers.length(), content="1")
  assert_eq(next.active().pending_steers[0].content, "again")
  inspect(next.active().pending_steers[0].submission_id, content="test-steer-1")
}

///|
test "a late exact applied receipt retracts a run-end unconfirmed notice" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation(
    with_pending_steers(running_conversation(), ["lost"]),
  )
  let (_, finished) = update_dev(
    dispatch,
    Finished(run_id="r7", status="finished", answer=Some("")),
    model,
  )
  let (_, next) = update_dev(
    dispatch,
    Engine(
      Some("r7"),
      SteerApplied(content="lost", submission_id=Some("test-steer-0")),
      session=None,
    ),
    finished,
  )
  inspect(next.active().pending_steers.length(), content="0")
}

///|
test "a trailing applied receipt for run A settles after run B Started" {
  let dispatch = test_dispatch()
  guard second_run_started_before_first_steer_receipt() is Some(started) else {
    fail("expected the second prompt to be starting")
  }
  let (_, next) = update_dev(
    dispatch,
    Engine(
      Some("r7"),
      SteerApplied(content="late steer", submission_id=Some("test-steer-0")),
      session=None,
    ),
    started,
  )
  assert_true(next.active().run is Open(run_id="r8", ..))
  assert_true(next.active().last_run_id is Some("r8"))
  inspect(next.active().pending_steers.length(), content="0")
  assert_true(next.active().pending_prompt is Some(_))
}

///|
test "a trailing dropped receipt for run A cannot close run B" {
  let dispatch = test_dispatch()
  guard second_run_started_before_first_steer_receipt() is Some(started) else {
    fail("expected the second prompt to be starting")
  }
  let (_, next) = update_dev(
    dispatch,
    Engine(
      Some("r7"),
      SteerDropped(content="late steer", submission_id=Some("test-steer-0")),
      session=None,
    ),
    started,
  )
  // Run A ended when B replaced it, taking A's pending steer with it, so the
  // trailing receipt has nothing left to settle. What it must not do is
  // disturb B.
  assert_true(next.active().run is Open(run_id="r8", ..))
  assert_true(next.active().last_run_id is Some("r8"))
  inspect(next.active().pending_steers.length(), content="0")
  assert_true(next.active().pending_prompt is Some(_))
  inspect(next.active().task, content="")
}

///|
test "a foreign background run schedules one causal read after Started" {
  let dispatch = test_dispatch()
  let session = "desktop-background"
  let conv = {
    ..empty_conversation(
      @interop.ChannelId::Local,
      session,
      @interop.ChannelId::Local.test_project(),
    ),
    watermark: 1,
    sync: test_reloading([]),
  }
  let model = {
    ..test_model().replace_conversation(conv),
    transcript_request_generation: 1,
  }
  // This previous-run answer arrived behind a snapshot whose read cut was
  // already taken, but before the next run's lifecycle announcement.
  let (_, buffered_answer) = update_dev(
    dispatch,
    SessionCommitted(
      session~,
      sequence=2,
      ts=None,
      item=@protocol.Assistant({
        content: "previous answer",
        tool_calls: None,
        reasoning_content: None,
        is_replay: None,
      }),
      session_root=@interop.ChannelId::Local.test_store_root(),
    ),
    model,
  )
  let (_, started) = update_dev(
    dispatch,
    Started(
      run_id="foreign-next",
      session~,
      model=DsPro,
      max_steps=1000,
      session_root=None,
      submission_id=None,
    ),
    buffered_answer,
  )
  guard started.find_conversation(@interop.ChannelId::Local, session)
    is Some(started_conv) else {
    fail("missing background conversation")
  }
  assert_true(
    started_conv.sync is Reloading(generation=1, reload_after_current=true, ..),
  )
  let (_, buffered_terminal) = update_dev(
    dispatch,
    SessionCommitted(
      session~,
      sequence=3,
      ts=None,
      item=@protocol.Terminal(@protocol.Finished("previous answer")),
      session_root=@interop.ChannelId::Local.test_store_root(),
    ),
    started,
  )
  let (_, buffered_user) = update_dev(
    dispatch,
    SessionCommitted(
      session~,
      sequence=4,
      ts=None,
      item=@protocol.User({ content: "current question", submission_id: None, }),
      session_root=@interop.ChannelId::Local.test_store_root(),
    ),
    buffered_terminal,
  )
  // Generation 1 predates Started. It may drain the ordered buffer, and the
  // causal read it scheduled still runs after it.
  let (_, after_old_cut) = update_dev(
    dispatch,
    SessionRefreshed(
      session~,
      items=[],
      watermark=1,
      goal=None,
      goal_markers=[],
      generation=1,
    ),
    buffered_user,
  )
  guard after_old_cut.find_conversation(@interop.ChannelId::Local, session)
    is Some(after_old) else {
    fail("missing conversation after old snapshot")
  }
  assert_true(after_old.sync is Reloading(generation=2, ..))
  let (_, causal) = update_dev(
    dispatch,
    SessionRefreshed(
      session~,
      items=[
        {
          kind: Assistant(
            reasoning=None,
            prose=Some("previous answer"),
            calls=[],
            replay=false,
            finished=false,
          ),
          ts: None,
          sequence: None,
        },
        { kind: User("current question"), ts: None, sequence: None, },
      ],
      watermark=4,
      goal=None,
      goal_markers=[],
      generation=2,
    ),
    after_old_cut,
  )
  guard causal.find_conversation(@interop.ChannelId::Local, session)
    is Some(current) else {
    fail("missing conversation after causal snapshot")
  }
  assert_true(current.sync is Synced)
  inspect(current.messages.length(), content="2")
}

///|
test "buffered commits are delivery, not applied chronology" {
  let dispatch = test_dispatch()
  let conv = {
    ..running_conversation(),
    watermark: 1,
    sync: test_reloading([]),
  }
  let model = test_model().replace_conversation(conv)
  let (_, user) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=2,
      ts=None,
      item=@protocol.User({ content: "current question", submission_id: None, }),
      session_root=@interop.ChannelId::Local.test_store_root(),
    ),
    model,
  )
  let (_, answer) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=3,
      ts=None,
      item=@protocol.Assistant({
        content: "current answer",
        tool_calls: None,
        reasoning_content: None,
        is_replay: None,
      }),
      session_root=@interop.ChannelId::Local.test_store_root(),
    ),
    user,
  )
  let (_, terminal) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=4,
      ts=None,
      item=@protocol.Terminal(@protocol.Finished("current answer")),
      session_root=@interop.ChannelId::Local.test_store_root(),
    ),
    answer,
  )
  // Buffered state is delivery, not applied chronology: three commits have
  // arrived and none of them has moved the transcript.
  inspect(terminal.active().watermark, content="1")
  inspect(terminal.active().messages.length(), content="0")
  let (_, loaded) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[],
      watermark=1,
      generation=1,
    ),
    terminal,
  )
  // The snapshot lands and the ordered buffer drains on top of it. The
  // terminal projects no row of its own.
  inspect(loaded.active().watermark, content="4")
  inspect(loaded.active().messages.length(), content="2")
}

///|
test "a reloading transcript does not hold up a steer" {
  let dispatch = test_dispatch()
  // The record is what a turn writes, not a precondition for submitting to
  // one. Reading it is the transcript's problem; the engine takes the text
  // either way, and the record is where it shows up.
  let conv = {
    ..running_conversation(),
    task: "steer while reloading",
    sync: test_reloading([]),
  }
  let model = running_model().replace_conversation(conv)
  let (_, next) = update(dispatch, Send, model)
  inspect(next.active().task, content="")
  inspect(next.active().pending_steers.length(), content="1")
}

///|
test "a trailing applied receipt settles after an empty runs snapshot" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation(
    with_pending_steers(running_conversation(), ["late applied"]),
  )
  let frontier = model.run_snapshot_frontier(@interop.ChannelId::Local)
  let (_, settled) = update_dev(
    dispatch,
    RunsSettled(live=[], frontier~),
    model,
  )
  let (_, applied) = update_dev(
    dispatch,
    Engine(
      Some("r7"),
      SteerApplied(content="late applied", submission_id=Some("test-steer-0")),
      session=None,
    ),
    settled,
  )
  inspect(applied.active().pending_steers.length(), content="0")
}

///|
test "a trailing dropped receipt after an empty runs snapshot changes nothing" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation(
    with_pending_steers(running_conversation(), ["late dropped"]),
  )
  let frontier = model.run_snapshot_frontier(@interop.ChannelId::Local)
  let (_, settled) = update_dev(
    dispatch,
    RunsSettled(live=[], frontier~),
    model,
  )
  let (_, dropped) = update_dev(
    dispatch,
    Engine(
      Some("r7"),
      SteerDropped(content="late dropped", submission_id=Some("test-steer-0")),
      session=None,
    ),
    settled,
  )
  // The snapshot already ended the run and its pending steer; a receipt that
  // trails it owns nothing.
  inspect(dropped.active().pending_steers.length(), content="0")
  inspect(dropped.active().task, content="")
}

///|
test "the official endpoint requires a key, a custom endpoint a URL" {
  let official = {
    ..test_model(),
    api_provider: Deepseek,
    deepseek_key_saved: false,
  }
  assert_false(official.api_ready())
  assert_true(official.display_status() is ApiKeyRequired)
  assert_true({ ..official, deepseek_key_saved: true, }.api_ready())
  // The GLM provider is gated on its own key, never DeepSeek's.
  let glm = {
    ..test_model(),
    api_provider: Glm,
    deepseek_key_saved: true,
    glm_key_saved: false,
  }
  assert_false(glm.api_ready())
  assert_true(glm.display_status() is ApiKeyRequired)
  assert_true({ ..glm, glm_key_saved: true, }.api_ready())
  let custom = { ..test_model(), api_provider: Custom, custom_api_url: "", }
  assert_false(custom.api_ready())
  assert_true(custom.display_status() is SetupRequired)
  let configured = {
    ..custom,
    custom_api_url: "https://proxy.example/chat/completions",
  }
  assert_true(configured.api_ready())
}

///|
test "loaded UI preferences parse their wire names" {
  let dispatch = test_dispatch()
  let (_, restored) = update(
    dispatch,
    SettingsLoaded(
      notification_corner="top-left",
      tree_layout="",
      theme="dark",
      font="menlo",
      font_size="15",
      fps_overlay_enabled=true,
      model="deepseek-v4-flash",
      conversation_models="[{\"key\":\"local/desktop-test\",\"model\":\"deepseek-v4-pro\"}]",
      agent="codex",
      codex_model="gpt-5.4-codex",
      codex_effort="xhigh",
      openseek_effort="high",
      glm_effort="max",
    ),
    test_model(),
  )
  assert_true(restored.notification_corner is TopLeft)
  assert_true(restored.theme is Dark)
  assert_true(restored.app_font is Menlo)
  assert_eq(restored.app_font_size, AppFontSize(15))
  assert_true(restored.default_model is DsFlash)
  assert_true(restored.default_agent is CodexAgent)
  assert_true(restored.openseek_reasoning is ReasoningHigh)
  assert_true(restored.glm_reasoning is ReasoningMax)
  // The stored conversation outranks the stored default for its own chat.
  assert_true(restored.active().engine_model is DsPro)
  // Unknown stored values fall back to the defaults.
  let (_, unknown) = update(
    dispatch,
    SettingsLoaded(
      notification_corner="",
      tree_layout="",
      theme="broken",
      font="broken",
      font_size="broken",
      fps_overlay_enabled=false,
      model="",
      conversation_models="not json",
      agent="broken",
      codex_model="",
      codex_effort="",
      openseek_effort="broken",
      glm_effort="broken",
    ),
    test_model(),
  )
  assert_true(unknown.notification_corner is BottomRight)
  assert_true(unknown.theme is System)
  assert_true(unknown.app_font is SystemMono)
  assert_eq(unknown.app_font_size, AppFontSize(14))
  assert_true(unknown.default_model is DsFlash)
  assert_true(unknown.openseek_reasoning is ReasoningHigh)
  assert_true(unknown.glm_reasoning is ReasoningOff)
  assert_true(unknown.default_agent is OpenSeekAgent)
  // A store that will not parse remembers nothing rather than wedging.
  assert_eq(unknown.conversation_models.length(), 0)
}

///|
test "the model selector switches one conversation, not the app" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation(
    empty_conversation(
      @interop.ChannelId::Local,
      "other-chat",
      @interop.ChannelId::Local.test_project(),
    ),
  )
  let (_, flash) = update(
    dispatch,
    ModelPicked("openseek:deepseek-v4-flash"),
    model,
  )
  assert_true(flash.active().engine_model is DsFlash)
  // The handler is pure: applying the same message to the same model produces
  // the same selected/default/stored model state.
  let (_, flash_again) = update(
    dispatch,
    ModelPicked("openseek:deepseek-v4-flash"),
    model,
  )
  @debug.assert_eq(
    flash.active().engine_model,
    flash_again.active().engine_model,
  )
  @debug.assert_eq(flash.default_model, flash_again.default_model)
  @debug.assert_eq(flash.conversation_models, flash_again.conversation_models)
  // The conversation next door keeps the tier it was already on.
  guard flash.find_conversation(@interop.ChannelId::Local, "other-chat")
    is Some(other) else {
    fail("the second conversation vanished")
  }
  assert_true(other.engine_model is DsPro)
  // The tier just picked is what conversations opened afterwards start from.
  assert_true(flash.default_model is DsFlash)
  assert_true(
    flash
    .activate(
      @interop.ChannelId::Local,
      "fresh-chat",
      @interop.ChannelId::Local.test_project(),
    )
    .active().engine_model
    is DsFlash,
  )
  let (_, pro) = update(
    dispatch,
    ModelPicked("openseek:deepseek-v4-pro"),
    flash,
  )
  assert_true(pro.active().engine_model is DsPro)
}

///|
test "a start never overrides the tier picked for the next turn" {
  let dispatch = test_dispatch()
  // The selector stays live while a turn spawns, so the user can change it for the
  // next turn before this one's `Started` arrives. The start is older than
  // that choice and must not undo it — the same holds for a turn another
  // client began, which says nothing about what this user means to send.
  let (_, queued) = update(
    dispatch,
    ModelPicked("openseek:deepseek-v4-flash"),
    test_model(),
  )
  assert_true(queued.active().engine_model is DsFlash)
  let (_, ran) = update_dev(
    dispatch,
    Started(
      run_id="r1",
      session="desktop-test",
      model=DsPro,
      max_steps=1000,
      session_root=None,
      submission_id=None,
    ),
    queued,
  )
  assert_true(ran.active().engine_model is DsFlash)
}

///|
test "reopening a conversation recovers its own tier, not the last pick" {
  let dispatch = test_dispatch()
  // Set the chat on screen to DsFlash, then open a different one and put it
  // back on DsPro. The second pick moves the default new chats inherit — it
  // must not follow the first conversation home.
  let (_, flash) = update(
    dispatch,
    ModelPicked("openseek:deepseek-v4-flash"),
    test_model(),
  )
  let other = flash.activate(
    @interop.ChannelId::Local,
    "other-chat",
    @interop.ChannelId::Local.test_project(),
  )
  assert_true(other.active().engine_model is DsFlash)
  let (_, pro) = update(
    dispatch,
    ModelPicked("openseek:deepseek-v4-pro"),
    other,
  )
  assert_true(pro.default_model is DsPro)
  // Reopening drops the conversation and mints it again (nothing was sent,
  // so `activate` does not retain it) — exactly the path that used to hand
  // back the unrelated default.
  let reopened = pro.activate(
    @interop.ChannelId::Local,
    "desktop-test",
    @interop.ChannelId::Local.test_project(),
  )
  assert_true(reopened.active().engine_model is DsFlash)
}

///|
test "a run pins an inherited tier the user never clicked for" {
  let dispatch = test_dispatch()
  // This chat never touched the chip — it just inherited DsPro and ran. That
  // still has to pin, or a later toggle elsewhere silently retiers it.
  let (_, ran) = update_dev(
    dispatch,
    Started(
      run_id="r1",
      session="desktop-test",
      model=DsPro,
      max_steps=1000,
      session_root=None,
      submission_id=None,
    ),
    test_model(),
  )
  assert_true(
    ran.remembered_model(@interop.ChannelId::Local, "desktop-test")
    is Some(DsPro),
  )
  // Another chat moves the page default to DsFlash...
  let elsewhere = ran.activate(
    @interop.ChannelId::Local,
    "other-chat",
    @interop.ChannelId::Local.test_project(),
  )
  let (_, moved) = update(
    dispatch,
    ModelPicked("openseek:deepseek-v4-flash"),
    elsewhere,
  )
  assert_true(moved.default_model is DsFlash)
  // ...and the first one still comes back on the tier it ran with.
  let reopened = moved.activate(
    @interop.ChannelId::Local,
    "desktop-test",
    @interop.ChannelId::Local.test_project(),
  )
  assert_true(reopened.active().engine_model is DsPro)
}

///|
test "a Codex pick hands a fresh chat to Codex" {
  let dispatch = test_dispatch()
  // The fixture chat has sent nothing, so its chip still offers both agent
  // groups. Picking a Codex model switches the surface and the defaults; the
  // real draft arrives via the rotation command's `CodexDraftRotated`.
  let (_, switched) = update(
    dispatch,
    ModelPicked("codex:gpt-5.4-codex"),
    test_model(),
  )
  assert_true(switched.screen is Codex)
  assert_true(switched.default_agent is CodexAgent)
  // One composing row at a time: the empty husk was only ever the "New
  // chat" placeholder, so it deactivates and its sidebar row goes with it.
  assert_true(switched.active_conversation() is None)
  // A husk holding typed writing keeps its row instead — switching back
  // finds the text.
  let typed = test_model().replace_conversation({
    ..test_conversation(),
    composer_draft_present: true,
  })
  let (_, kept) = update(dispatch, ModelPicked("codex:gpt-5.4-codex"), typed)
  assert_true(kept.screen is Codex)
  assert_true(kept.active_conversation() is Some(_))
}

///|
test "a begun conversation never changes agents" {
  let dispatch = test_dispatch()
  let (_, ran) = update_dev(
    dispatch,
    Started(
      run_id="r1",
      session="desktop-test",
      model=DsPro,
      max_steps=1000,
      session_root=None,
      submission_id=None,
    ),
    test_model(),
  )
  let (_, unchanged) = update(dispatch, ModelPicked("codex:gpt-5.4-codex"), ran)
  assert_true(unchanged.screen is Chat)
  assert_true(unchanged.default_agent is OpenSeekAgent)
}

///|
test "an OpenSeek pick on a composing Codex draft hands the chat back" {
  let dispatch = test_dispatch()
  let (_, drafting) = update(
    dispatch,
    CodexDraftRotated(cwd="/work", id="desktop-draft-1"),
    test_model(),
  )
  assert_true(drafting.screen is Codex)
  assert_true(drafting.codex.composing_draft())
  let (_, back) = update(
    dispatch,
    ModelPicked("openseek:deepseek-v4-flash"),
    drafting,
  )
  assert_false(back.codex.composing_draft())
  assert_true(back.default_agent is OpenSeekAgent)
  assert_true(back.default_model is DsFlash)
}

///|
test "the Codex group's placeholder row opens Settings" {
  let dispatch = test_dispatch()
  let (_, opened) = update(
    dispatch,
    ModelPicked("codex.unavailable"),
    test_model(),
  )
  // Sign-in and connection state live in the Settings page's Codex group.
  assert_true(opened.screen is Settings)
  // A placeholder pick is a doorway, not a model: nothing was selected.
  assert_true(opened.default_agent is OpenSeekAgent)
}

///|
test "Codex threads share the Projects section's project rows" {
  let codex = @codex.State::from_thread_snapshot({
    "thread": {
      "id": "codex-thread-1",
      "cwd": "/work",
      "projectRoot": "/work",
      "preview": "Codex task",
      "updatedAt": 2000,
      "turns": [],
    },
  })
  let model = { ..test_model(), codex, screen: Codex, }.with_dev(dev => {
    ..dev,
    sessions: [
      {
        id: "desktop-newer",
        title: Some("after the Codex task"),
        workspace: @interop.ChannelId::Local.test_project(),
        workspace_name: "work",
        updated_at_ms: Some(3_000_000.0),
      },
      {
        id: "desktop-older",
        title: Some("before the Codex task"),
        workspace: @interop.ChannelId::Local.test_project(),
        workspace_name: "work",
        updated_at_ms: Some(1_000_000.0),
      },
    ],
  })
  let sections = model.sidebar_component_sections(model.dev())
  // The Projects section and the Archived section — no Codex section.
  assert_eq(sections.length(), 2)
  inspect(sections[0].label, content="Projects")
  guard sections[0].entries[0] is @section.Project(project) else {
    fail("expected the fixture project's row")
  }
  // The fixture's unsent OpenSeek chat is represented by its project rather
  // than a child row. Durable history still interleaves newest-first across
  // both agents.
  let order = project.conversations.map(row => row.id.conversation())
  assert_eq(order, ["desktop-newer", "codex-thread-1", "desktop-older"])
  assert_true(project.conversations[1].id.source() is @conversation.CodexLive)
  assert_true(project.conversations[1].nested)
  // With the Codex page on screen, its active task claims the activation.
  assert_eq(sections[0].activation, Some("codex-thread-1"))
}

///|
test "remembered tiers survive a round trip through storage" {
  let dispatch = test_dispatch()
  let (_, chosen) = update(
    dispatch,
    ModelPicked("openseek:deepseek-v4-flash"),
    test_model(),
  )
  let restored = parse_conversation_models(
    encoded_conversation_models(chosen.conversation_models),
  )
  assert_eq(restored, chosen.conversation_models)
  assert_true(restored is [{ key: "local/desktop-test", model: DsFlash, }])
}

///|
test "a write merges into the stored rows instead of replacing them" {
  // A sibling console tab on the same origin wrote these while this page held
  // a copy loaded at its own startup. Pinning here must not drop the other
  // tab's row — that conversation would silently revert to the default.
  let stored = parse_conversation_models(
    encoded_conversation_models([
      { key: "remote.b/sibling-chat", model: DsFlash, },
      { key: "remote.a/desktop-test", model: DsPro, },
    ]),
  )
  let merged = remembered_with(stored, "remote.a/desktop-test", DsFlash)
  assert_true(
    merged
    is [
      { key: "remote.a/desktop-test", model: DsFlash, },
      { key: "remote.b/sibling-chat", model: DsFlash, },
    ],
  )
}

///|
/// Test-only: the stored spelling of a remembered list, as
/// `save_conversation_model` writes it.
fn encoded_conversation_models(
  entries : Array[StoredConversationModel],
) -> String {
  let rows : Array[Json] = entries.map(entry => {
    "key": entry.key.to_json(),
    "model": entry.model.wire().to_json(),
  })
  rows.to_json().stringify()
}

///|
test "the remembered list stays capped, newest first" {
  let mut model = test_model()
  // One past the cap, so the first conversation chosen for is the one that
  // falls off and reverts to the page default.
  for index in 0..<=ConversationModelsLimit {
    model = model.remember_model(
      @interop.ChannelId::Local,
      "session-\{index}",
      if index % 2 == 0 {
        DsFlash
      } else {
        DsPro
      },
    )
  }
  assert_eq(model.conversation_models.length(), ConversationModelsLimit)
  assert_true(
    model.remembered_model(@interop.ChannelId::Local, "session-0") is None,
  )
  assert_true(
    model.remembered_model(
      @interop.ChannelId::Local,
      "session-\{ConversationModelsLimit}",
    )
    is Some(DsFlash),
  )
  // Re-choosing an existing conversation moves it, never duplicates it.
  let again = model.remember_model(
    @interop.ChannelId::Local,
    "session-1",
    DsFlash,
  )
  assert_eq(again.conversation_models.length(), ConversationModelsLimit)
  assert_true(
    again.remembered_model(@interop.ChannelId::Local, "session-1")
    is Some(DsFlash),
  )
}

///|
test "a conversation first met through a live run adopts its tier" {
  let dispatch = test_dispatch()
  // No local choice exists to contradict the run, so its tier is the best
  // evidence available — and it lands on that conversation alone, moving
  // neither the chat on screen nor the default new chats start from.
  let (_, background) = update_dev(
    dispatch,
    Started(
      run_id="r2",
      session="background-chat",
      model=DsPro,
      max_steps=1000,
      session_root=Some(@interop.ChannelId::Local.test_store_root()),
      submission_id=None,
    ),
    // The chat on screen sits on the page default, so the run's other tier
    // contrasts with both of the things it must not move.
    test_model().replace_conversation({
      ..test_conversation(),
      engine_model: DsFlash,
    }),
  )
  guard background.find_conversation(
      @interop.ChannelId::Local,
      "background-chat",
    )
    is Some(conv) else {
    fail("the background run materialized no conversation")
  }
  assert_true(conv.engine_model is DsPro)
  assert_true(background.active().engine_model is DsFlash)
  assert_true(background.default_model is DsFlash)
}

///|
fn host_settings(
  provider~ : String,
  revision? : Int = 0,
  has_deepseek_key? : Bool = false,
  has_glm_key? : Bool = false,
  custom_api_url? : String = "",
) -> HostSettings {
  {
    revision,
    provider,
    custom_api_url,
    has_deepseek_key,
    has_glm_key,
    has_custom_key: false,
    followup_behavior: "steer",
  }
}

///|
test "host settings edits wait for the focused host snapshot" {
  let dispatch = test_dispatch()
  // Model a queued DOM message from the old Settings page after focus already
  // moved. The negative revision is authoritative: none of these stale values
  // or events may be applied to the replacement host.
  let loading = {
    ..test_model(),
    api_provider: Deepseek,
    custom_api_url: "https://old.example/chat",
    deepseek_key_saved: true,
    setup_api_key: "old-device-key",
    host_settings_revision: -1,
  }
  let messages : Array[Msg] = [
    SetupApiKeyChanged("queued-key"),
    ProviderChanged("custom"),
    CustomApiUrlChanged("https://new.example/chat"),
    SaveApiKey,
  ]
  for message in messages {
    let (_, once) = update(dispatch, message, loading)
    let (_, twice) = update(dispatch, message, loading)
    assert_true(once.api_provider == loading.api_provider)
    assert_eq(once.custom_api_url, loading.custom_api_url)
    assert_eq(once.setup_api_key, loading.setup_api_key)
    assert_eq(once.settings_saves, 0)
    assert_true(twice.api_provider == loading.api_provider)
    assert_eq(twice.custom_api_url, loading.custom_api_url)
    assert_eq(twice.setup_api_key, loading.setup_api_key)
    assert_eq(twice.settings_saves, 0)
  }
}

///|
test "an unusable first settings snapshot opens the setup modal" {
  let dispatch = test_dispatch()
  // A hosted-provider value left by an older build parses as the BYOK
  // default: keyless DeepSeek, which needs setup.
  let (_, zero_config) = update_dev(
    dispatch,
    HostSettingsLoaded(
      host_settings(provider="openseek"),
      connection_generation=None,
    ),
    test_model(),
  )
  assert_true(zero_config.screen is Chat)
  assert_true(zero_config.api_setup_open)
  assert_true(zero_config.api_provider is Deepseek)
  assert_true(zero_config.display_status() is ApiKeyRequired)
  let (_, keyless) = update_dev(
    dispatch,
    HostSettingsLoaded(
      host_settings(provider="deepseek"),
      connection_generation=None,
    ),
    test_model(),
  )
  assert_true(keyless.screen is Chat)
  assert_true(keyless.api_setup_open)
  assert_true(keyless.display_status() is ApiKeyRequired)
  let (_, restored) = update_dev(
    dispatch,
    HostSettingsLoaded(
      host_settings(provider="deepseek", has_deepseek_key=true),
      connection_generation=None,
    ),
    test_model(),
  )
  assert_true(restored.screen is Chat)
  assert_true(!restored.api_setup_open)
  assert_true(restored.deepseek_key_saved)
}

///|
test "the setup modal tracks endpoint usability without toasts" {
  let dispatch = test_dispatch()
  let (_, keyless) = update_dev(
    dispatch,
    HostSettingsLoaded(
      host_settings(provider="deepseek"),
      connection_generation=None,
    ),
    test_model(),
  )
  assert_true(keyless.api_setup_open)
  // The modal is the announcement; a toast under it would double-signal.
  assert_eq(keyless.notifications.length(), 0)
  // A snapshot that is usable closes the modal.
  let (_, ready) = update_dev(
    dispatch,
    HostSettingsLoaded(
      host_settings(provider="deepseek", has_deepseek_key=true),
      connection_generation=None,
    ),
    { ..test_model(), api_setup_open: true, },
  )
  assert_true(!ready.api_setup_open)
  assert_eq(ready.notifications.length(), 0)
  // A later change that breaks a usable endpoint reopens the modal.
  let (_, broken) = update_dev(
    dispatch,
    HostSettingsLoaded(
      host_settings(provider="custom", custom_api_url=""),
      connection_generation=None,
    ),
    {
      ..test_model(),
      host_settings_revision: 0,
      api_provider: Custom,
      custom_api_url: "https://ok.example/chat",
    },
  )
  assert_true(broken.api_setup_open)
  // "Not now" dismisses; an unrelated payload that leaves the endpoint
  // unusable does not re-announce it.
  let (_, dismissed) = update(dispatch, DismissApiSetup, {
    ..broken,
    api_setup_open: true,
  })
  assert_true(!dismissed.api_setup_open)
  let (_, still) = update_dev(
    dispatch,
    HostSettingsLoaded(
      host_settings(provider="deepseek"),
      connection_generation=None,
    ),
    dismissed,
  )
  assert_true(!still.api_setup_open)
  // Opening Settings from the gear closes the modal.
  let (_, on_settings) = update(dispatch, OpenSetup, {
    ..broken,
    api_setup_open: true,
  })
  assert_true(on_settings.screen is Settings)
  assert_true(!on_settings.api_setup_open)
  // Breaking while the Settings page is open does not pop the modal over
  // the form; the guide there already explains it.
  let (_, mid_edit) = update_dev(
    dispatch,
    HostSettingsLoaded(
      host_settings(provider="custom", custom_api_url=""),
      connection_generation=None,
    ),
    {
      ..test_model(),
      screen: Settings,
      host_settings_revision: 0,
      api_provider: Custom,
      custom_api_url: "https://ok.example/chat",
    },
  )
  assert_true(!mid_edit.api_setup_open)
}

///|
test "switching to a provider missing its key or URL opens the setup modal" {
  let dispatch = test_dispatch()
  // The BYOK fixture is ready (a key is saved); switching to Custom with
  // no URL takes the endpoint from usable to not. Off the Settings page
  // the setup modal is the announcement — no toast underneath it.
  let (_, switched) = update(dispatch, ProviderChanged("custom"), test_model())
  assert_true(switched.api_provider is Custom)
  assert_true(switched.api_setup_open)
  assert_eq(switched.notifications.length(), 0)
  // A switch that stays usable stays quiet.
  let (_, kept) = update(dispatch, ProviderChanged("deepseek"), {
    ..test_model(),
    api_provider: Custom,
    custom_api_url: "https://ok.example/chat",
  })
  assert_true(!kept.api_setup_open)
  // Switching back to a provider the stored key makes usable retires the
  // modal that the break opened.
  let (_, back) = update(dispatch, ProviderChanged("deepseek"), switched)
  assert_true(back.api_provider is Deepseek)
  assert_true(!back.api_setup_open)
}

///|
test "the GLM provider aligns only a fresh chat to its model family" {
  let dispatch = test_dispatch()
  let (_, glm) = update(dispatch, ProviderChanged("glm"), {
    ..test_model(),
    glm_key_saved: true,
  })
  assert_true(glm.api_provider is Glm)
  assert_true(glm.default_model is Glm53)
  assert_true(glm.active().engine_model is Glm53)
  // GLM's forced-thinking default is the shared low wire value, independent
  // from the High preference DeepSeek keeps.
  assert_true(glm.reasoning_for(glm.active().engine_model) is ReasoningOff)
  assert_true(glm.openseek_reasoning is ReasoningHigh)
  // A host snapshot on a later launch performs the same alignment even
  // though the page-local model preference loads before host settings do.
  let (_, restored) = update_dev(
    dispatch,
    HostSettingsLoaded(
      host_settings(provider="glm", has_glm_key=true),
      connection_generation=None,
    ),
    test_model(),
  )
  assert_true(restored.default_model is Glm53)
  assert_true(restored.active().engine_model is Glm53)
  // Startup is order-independent: if the host's GLM snapshot arrives before
  // localStorage, the later DeepSeek model preference cannot reintroduce a
  // mismatched fresh chat.
  let (_, preferences_after_host) = update(
    dispatch,
    SettingsLoaded(
      notification_corner="",
      tree_layout="",
      theme="",
      font="",
      font_size="",
      fps_overlay_enabled=false,
      model="deepseek-v4-pro",
      conversation_models="",
      agent="",
      codex_model="",
      codex_effort="",
      openseek_effort="",
      glm_effort="",
    ),
    restored,
  )
  assert_true(preferences_after_host.default_model is Glm53)
  assert_true(preferences_after_host.active().engine_model is Glm53)
  // Once a conversation has begun, its pinned model remains explicit and
  // visible for the user to change rather than being rewritten by Settings.
  let (_, running) = update(dispatch, ProviderChanged("glm"), running_model())
  assert_true(running.api_provider is Glm)
  assert_true(running.default_model is Glm53)
  assert_true(running.active().engine_model is DsPro)
  assert_true(running.display_status() is Running)
}

///|
test "a dismissal survives the mirror reset a reconnect performs" {
  let dispatch = test_dispatch()
  let (_, keyless) = update_dev(
    dispatch,
    HostSettingsLoaded(
      host_settings(provider="deepseek"),
      connection_generation=None,
    ),
    test_model(),
  )
  let (_, dismissed) = update(dispatch, DismissApiSetup, keyless)
  // A reconnect (or focus switch) resets the mirror to the loading
  // sentinel; the refetched snapshot must not re-pop the modal on every
  // WS flap — dismissal is the user's answer for the session.
  let cleared = dismissed.clear_host_settings()
  assert_true(!cleared.api_setup_open)
  let (_, reconnected) = update_dev(
    dispatch,
    HostSettingsLoaded(
      host_settings(provider="deepseek"),
      connection_generation=None,
    ),
    cleared,
  )
  assert_true(!reconnected.api_setup_open)
  // A usable endpoint re-arms the announcement: the next break prompts
  // again even after an earlier "Not now".
  let (_, ready) = update_dev(
    dispatch,
    HostSettingsLoaded(
      host_settings(provider="deepseek", has_deepseek_key=true),
      connection_generation=None,
    ),
    reconnected,
  )
  assert_true(!ready.api_setup_open)
  let (_, broken) = update_dev(
    dispatch,
    HostSettingsLoaded(
      host_settings(provider="deepseek"),
      connection_generation=None,
    ),
    ready,
  )
  assert_true(broken.api_setup_open)
}

///|
test "the composer's BYOK notice outlives a dismissal and reopens the modal" {
  let dispatch = test_dispatch()
  let (_, keyless) = update_dev(
    dispatch,
    HostSettingsLoaded(
      host_settings(provider="deepseek"),
      connection_generation=None,
    ),
    test_model(),
  )
  let (_, dismissed) = update(dispatch, DismissApiSetup, keyless)
  // Quiet must not mean lost: the notice stays while the endpoint is
  // unusable, dismissal or not.
  assert_true(dismissed.api_setup_banner_visible())
  // The loading sentinel is not a verdict; a reconnect must not flash it.
  assert_true(!dismissed.clear_host_settings().api_setup_banner_visible())
  // A usable endpoint retires the notice with the modal.
  assert_true(!test_model().api_setup_banner_visible())
  // Its "Set up" reopens the modal, and reopening cancels the dismissal so
  // the next settled snapshot leaves the modal the user asked for alone.
  let (_, reopened) = update(dispatch, OpenApiSetup, dismissed)
  assert_true(reopened.api_setup_open)
  let (_, still_open) = update_dev(
    dispatch,
    HostSettingsLoaded(
      host_settings(provider="deepseek"),
      connection_generation=None,
    ),
    reopened,
  )
  assert_true(still_open.api_setup_open)
}

///|
test "a custom endpoint reads as usable only from a plausible URL" {
  let custom = {
    ..test_model(),
    api_provider: Custom,
    deepseek_key_saved: false,
  }
  // A prefix mid-typing must not arm Send or retire the setup modal.
  assert_true(!{ ..custom, custom_api_url: "", }.api_ready())
  assert_true(!{ ..custom, custom_api_url: "h", }.api_ready())
  assert_true(!{ ..custom, custom_api_url: "https://", }.api_ready())
  assert_true(!{ ..custom, custom_api_url: "ftp://host", }.api_ready())
  assert_true({ ..custom, custom_api_url: "https://host", }.api_ready())
  assert_true(
    { ..custom, custom_api_url: " https://host/chat/completions ", }.api_ready(),
  )
  assert_true(
    { ..custom, custom_api_url: "http://127.0.0.1:8080", }.api_ready(),
  )
}

///|
test "clearing the mirror never leaves an orphaned setup modal" {
  // A modal left up over the loading sentinel would render default data
  // with every control disabled; close it with the mirror it was showing.
  let open = {
    ..test_model(),
    api_setup_open: true,
    deepseek_key_saved: false,
  }
  assert_true(!open.clear_host_settings().api_setup_open)
}

///|
test "saving from the setup modal stays on the page it opened over" {
  let dispatch = test_dispatch()
  // The modal renders over any screen; completing setup from it must not
  // yank the user to Chat.
  let over_skills = {
    ..test_model(),
    screen: Skills,
    api_setup_open: true,
    deepseek_key_saved: false,
  }
  let (_, typed) = update(dispatch, SetupApiKeyChanged("sk-test"), over_skills)
  let (_, saved) = update(dispatch, SaveApiKey, typed)
  assert_true(saved.screen is Skills)
  assert_true(!saved.api_setup_open)
  // A save that leaves the setup incomplete (Custom, no URL yet) keeps the
  // modal up mid-setup instead of dumping the user on Settings.
  let custom_half = {
    ..test_model(),
    api_provider: Custom,
    custom_api_url: "",
    api_setup_open: true,
  }
  let (_, keyed) = update(
    dispatch,
    SetupApiKeyChanged("sk-custom"),
    custom_half,
  )
  let (_, still_open) = update(dispatch, SaveApiKey, keyed)
  assert_true(still_open.screen is Chat)
  assert_true(still_open.api_setup_open)
}

///|
test "saving the key from the setup modal retires it" {
  let dispatch = test_dispatch()
  let open = {
    ..test_model(),
    api_setup_open: true,
    deepseek_key_saved: false,
  }
  let (_, typed) = update(dispatch, SetupApiKeyChanged("sk-test"), open)
  let (_, saved) = update(dispatch, SaveApiKey, typed)
  assert_true(saved.deepseek_key_saved)
  assert_true(saved.screen is Chat)
  assert_true(!saved.api_setup_open)
  assert_eq(saved.setup_api_key, "")
}

///|
test "a settled host save that completes the setup closes the modal" {
  // A custom URL typed into the modal is saved optimistically; the host's
  // applied confirmation is what retires the modal, not mid-typing.
  let typing = {
    ..test_model(),
    api_setup_open: true,
    api_provider: Custom,
    custom_api_url: "https://ok.example/chat",
    settings_saves: 1,
    select_menu: Some(ApiProviderMenu),
  }
  let closed = typing.flush_host_settings()
  assert_true(!closed.api_setup_open)
  assert_true(closed.select_menu is None)
  // The same host reconciliation must not close the API selector when it is
  // owned by the Settings page rather than an open setup modal.
  let page = {
    ..typing,
    screen: Settings,
    api_setup_open: false,
    select_menu: Some(ApiProviderMenu),
  }.flush_host_settings()
  assert_true(page.select_menu == Some(ApiProviderMenu))
  // A flush that leaves the endpoint unusable keeps the modal up.
  let still = {
    ..test_model(),
    api_setup_open: true,
    api_provider: Deepseek,
    deepseek_key_saved: false,
    deferred_host_settings: Some(host_settings(provider="deepseek")),
    host_settings_revision: -1,
  }
  assert_true(still.flush_host_settings().api_setup_open)
}

///|
test "a background device's pushes leave the focused mirrors alone" {
  let dispatch = test_dispatch()
  let background : @interop.ChannelId = Remote("d_bg")
  let model = {
    ..test_model(),
    devices: [
      { ..empty_device_state(@interop.ChannelId::Local), bridge: Connected, },
      { ..empty_device_state(background), bridge: Connected, },
    ],
  }
  // A settings.changed broadcast from the background device: the form (and
  // the incomplete-settings redirect) keeps the focused host's state.
  let (_, settled) = update(
    dispatch,
    FromDevice(
      background,
      HostSettingsLoaded(
        host_settings(provider="deepseek"),
        connection_generation=None,
      ),
    ),
    model,
  )
  assert_true(settled.api_provider is Deepseek)
  assert_true(settled.screen is Chat)
}

///|
test "host settings are deferred while this client's writes are in flight" {
  let dispatch = test_dispatch()
  let model = { ..test_model(), settings_saves: 1, }
  // A broadcast (or a stale get reply) arriving mid-write must not clobber
  // the optimistic mirror.
  let (_, ignored) = update_dev(
    dispatch,
    HostSettingsLoaded(
      host_settings(provider="deepseek", revision=1),
      connection_generation=None,
    ),
    model,
  )
  assert_true(ignored.api_provider is Deepseek)
  inspect(ignored.settings_saves, content="1")
  // The write's own reply reconciles once it is the last one out.
  let (_, settled) = update_dev(
    dispatch,
    HostSettingsApplied(
      host_settings(provider="deepseek", revision=2, has_deepseek_key=true),
      connection_generation=0,
      cleans_legacy=false,
    ),
    model,
  )
  inspect(settled.settings_saves, content="0")
  assert_true(settled.api_provider is Deepseek)
  assert_true(settled.deepseek_key_saved)
  inspect(settled.host_settings_revision, content="2")
  // With more writes still out, even a reply only decrements.
  let stacked = { ..model, settings_saves: 2, }
  let (_, still_pending) = update_dev(
    dispatch,
    HostSettingsApplied(
      host_settings(provider="deepseek", revision=1),
      connection_generation=0,
      cleans_legacy=false,
    ),
    stacked,
  )
  inspect(still_pending.settings_saves, content="1")
  assert_true(still_pending.api_provider is Deepseek)
}

///|
test "a newer peer broadcast beats a delayed local settings reply" {
  let dispatch = test_dispatch()
  let model = {
    ..test_model(),
    api_provider: Custom,
    settings_saves: 1,
    host_settings_revision: 5,
  }
  let (_, broadcast) = update_dev(
    dispatch,
    HostSettingsLoaded(
      host_settings(provider="deepseek", revision=7),
      connection_generation=None,
    ),
    model,
  )
  // Preserve the optimistic form until the local RPC settles.
  assert_true(broadcast.api_provider is Custom)
  let (_, settled) = update_dev(
    dispatch,
    HostSettingsApplied(
      host_settings(provider="openseek", revision=6),
      connection_generation=0,
      cleans_legacy=false,
    ),
    broadcast,
  )
  assert_true(settled.api_provider is Deepseek)
  inspect(settled.host_settings_revision, content="7")
  inspect(settled.settings_saves, content="0")
}

///|
test "legacy client settings migrate up only from the desktop window" {
  let dispatch = test_dispatch()
  let legacy = LegacySettingsRead(
    provider="deepseek",
    custom_url="",
    api_key="sk-legacy",
    custom_api_key="",
  )
  let (_, desktop) = update(dispatch, legacy, {
    ..test_model(),
    is_desktop: true,
  })
  assert_true(desktop.api_provider is Deepseek)
  assert_true(desktop.deepseek_key_saved)
  inspect(desktop.settings_saves, content="1")
  assert_true(desktop.legacy_cleanup_pending)
  // A browser page only purges — its copy may belong to another device.
  // The keyless mirror is explicit: the fixture's saved key belongs to the
  // desktop window's migration above, not to this page.
  let (_, browser) = update(dispatch, legacy, {
    ..test_model(),
    is_desktop: false,
    deepseek_key_saved: false,
  })
  assert_false(browser.deepseek_key_saved)
  inspect(browser.settings_saves, content="0")
  assert_false(browser.legacy_cleanup_pending)
}

///|
test "only the migration settings response owns legacy cleanup" {
  let dispatch = test_dispatch()
  let pending = {
    ..test_model(),
    settings_saves: 2,
    legacy_cleanup_pending: true,
  }
  // An unrelated save may finish first; it must not consume the migration's
  // right to clear localStorage when that exact write is acknowledged.
  let (_, unrelated) = update_dev(
    dispatch,
    HostSettingsApplied(
      host_settings(provider="custom", revision=1),
      connection_generation=0,
      cleans_legacy=false,
    ),
    pending,
  )
  inspect(unrelated.settings_saves, content="1")
  assert_true(unrelated.legacy_cleanup_pending)
  let (_, migrated) = update_dev(
    dispatch,
    HostSettingsApplied(
      host_settings(provider="deepseek", revision=2, has_deepseek_key=true),
      connection_generation=0,
      cleans_legacy=true,
    ),
    unrelated,
  )
  inspect(migrated.settings_saves, content="0")
  assert_false(migrated.legacy_cleanup_pending)
  assert_true(migrated.api_provider is Deepseek)
  assert_true(migrated.deepseek_key_saved)
}

///|
test "a failed migration keeps legacy storage for a later launch" {
  let dispatch = test_dispatch()
  let pending = {
    ..test_model(),
    settings_saves: 1,
    legacy_cleanup_pending: true,
  }
  let (_, failed) = update_dev(
    dispatch,
    HostSettingsSaveFailed(
      "host write failed",
      connection_generation=0,
      cleans_legacy=true,
    ),
    pending,
  )
  inspect(failed.settings_saves, content="0")
  // False means this launch must not clear localStorage; LegacySettingsRead
  // on the next launch will discover and retry the still-present values.
  assert_false(failed.legacy_cleanup_pending)
}

///|
test "background settings replies cannot alter the focused host mirror" {
  let dispatch = test_dispatch()
  let home = test_model()
  let focused = {
    ..home,
    devices: [
      home.devices[0],
      { ..empty_device_state(Remote("d_b")), bridge: Connected, },
    ],
    focused: Remote("d_b"),
    api_provider: Custom,
    settings_saves: 1,
  }
  let (_, applied) = update(
    dispatch,
    FromDevice(
      Local,
      HostSettingsApplied(
        host_settings(provider="deepseek", revision=7),
        connection_generation=0,
        cleans_legacy=false,
      ),
    ),
    focused,
  )
  assert_true(applied.api_provider is Custom)
  assert_eq(applied.settings_saves, 1)
  let (_, failed) = update(
    dispatch,
    FromDevice(
      Local,
      HostSettingsSaveFailed(
        "old host failed",
        connection_generation=0,
        cleans_legacy=false,
      ),
    ),
    applied,
  )
  assert_eq(failed.settings_saves, 1)
  assert_eq(failed.notifications.length(), 0)
}

///|
test "the notification-corner setting parses its wire names" {
  let dispatch = test_dispatch()
  let (_, moved) = update(
    dispatch,
    NotificationCornerChanged("top-right"),
    test_model(),
  )
  assert_true(moved.notification_corner is TopRight)
  let (_, unknown) = update(
    dispatch,
    NotificationCornerChanged("nowhere"),
    moved,
  )
  assert_true(unknown.notification_corner is BottomRight)
}

///|
test "the tree-layout setting parses its wire names" {
  let dispatch = test_dispatch()
  let (_, docked) = update(
    dispatch,
    TreeLayoutChanged("bottom-panel"),
    test_model(),
  )
  assert_true(docked.tree_layout is BottomPanel)
  // An unknown stored value falls back to the default right sidebar.
  let (_, unknown) = update(dispatch, TreeLayoutChanged("floating"), docked)
  assert_true(unknown.tree_layout is RightSidebar)
}

///|
test "update is pure: a provider change is idempotent" {
  let dispatch = test_dispatch()
  let model = {
    ..test_model(),
    setup_api_key: "typed",
    deepseek_key_saved: false,
  }
  let (_, once) = update(dispatch, ProviderChanged("deepseek"), model)
  let (_, twice) = update(dispatch, ProviderChanged("deepseek"), model)
  assert_true(once.api_provider is Deepseek)
  assert_true(twice.api_provider is Deepseek)
  inspect(once.setup_api_key, content="")
  inspect(twice.setup_api_key, content="")
  inspect(once.settings_saves, content="1")
  inspect(twice.settings_saves, content="1")
  assert_true(once.display_status() is ApiKeyRequired)
  assert_true(twice.display_status() is ApiKeyRequired)
}

///|
test "saving a key marks the active provider credential only" {
  let dispatch = test_dispatch()
  let deepseek = {
    ..test_model(),
    api_provider: Deepseek,
    deepseek_key_saved: false,
    setup_api_key: "  sk-new  ",
    screen: Settings,
  }
  let (_, saved_deepseek) = update(dispatch, SaveApiKey, deepseek)
  assert_true(saved_deepseek.deepseek_key_saved)
  assert_false(saved_deepseek.custom_key_saved)
  inspect(saved_deepseek.setup_api_key, content="")
  inspect(saved_deepseek.settings_saves, content="1")
  // The save never navigates: a key saved on the Settings page leaves the
  // user on the form they were filling in.
  assert_true(saved_deepseek.screen is Settings)
  // Each provider's flag is independent: switching to Custom and saving
  // marks only the custom credential.
  let custom = {
    ..test_model(),
    api_provider: Custom,
    deepseek_key_saved: false,
    custom_api_url: "https://proxy.example/chat/completions",
    setup_api_key: "  sk-custom-new  ",
    screen: Settings,
  }
  let (_, saved_custom) = update(dispatch, SaveApiKey, custom)
  assert_false(saved_custom.deepseek_key_saved)
  assert_true(saved_custom.custom_key_saved)
  assert_true(saved_custom.screen is Settings)
  // A GLM key lands in the GLM slot alone.
  let glm = {
    ..test_model(),
    api_provider: Glm,
    deepseek_key_saved: false,
    glm_key_saved: false,
    setup_api_key: "  glm-new  ",
    screen: Settings,
  }
  let (_, saved_glm) = update(dispatch, SaveApiKey, glm)
  assert_true(saved_glm.glm_key_saved)
  assert_false(saved_glm.deepseek_key_saved)
  assert_false(saved_glm.custom_key_saved)
  assert_true(saved_glm.screen is Settings)
}

///|
/// The Settings page has no Done button — the sidebar is the only way out,
/// even while the endpoint is unusable (the composer blocks sending then).
test "sidebar navigation leaves the settings page" {
  let dispatch = test_dispatch()
  let model = { ..test_model(), api_provider: Deepseek, screen: Settings, }
  let (_, next) = update(
    dispatch,
    SessionRotated({ channel: Local, session: "s-fresh", }),
    model,
  )
  assert_true(next.screen is Chat)
}

///|
/// A `git.branch` reply for the test conversation.
fn branch_reply(
  branch : String,
  generation? : Int = 0,
  session? : String = "desktop-test",
  diffstat? : DiffStat,
  base_hint? : String,
) -> DeviceMsg {
  BranchLoaded(
    session~,
    branch=Some(branch),
    diffstat~,
    generation~,
    base_hint~,
  )
}

///|
/// A `git.pull_request` reply for the test conversation. `queried` defaults to
/// the branch asked about, which is the ordinary case: only a checkout that
/// moved mid-request makes them differ.
fn pull_request_reply(
  branch : String,
  generation~ : Int,
  queried? : String,
  pull_request? : PullRequest,
  compare_url? : String,
) -> DeviceMsg {
  PullRequestLoaded(
    session="desktop-test",
    branch~,
    generation~,
    queried=Some(queried.unwrap_or(branch)),
    pull_request~,
    compare_url~,
  )
}

///|
/// The probe a lookup for `branch` leaves behind while it runs.
fn probing_for(
  branch : String,
  pull_request? : PullRequest,
  compare_url? : String,
) -> PullRequestProbe {
  { branch, probing: true, stale: false, pull_request, compare_url, }
}

///|
/// One pull request, varied per test by field update.
fn test_pull_request() -> PullRequest {
  {
    number: 710,
    title: "Add a changed-files explorer",
    state: PullRequestOpen,
    draft: true,
    url: "https://github.test/acme/app/pull/710",
    base: "main",
    additions: 2972,
    deletions: 287,
    changed_files: 18,
    checks: Some({ passed: 1, failed: 0, pending: 3, }),
  }
}

///|
test "a branch reply lands on its conversation and an empty one hides it" {
  let dispatch = test_dispatch()
  let stat : DiffStat = {
    added: 12,
    removed: 3,
    files: 2,
    base: Some("origin/main"),
    partial: false,
  }
  let (_, named) = update_dev(
    dispatch,
    branch_reply("feature/x", diffstat=stat),
    test_model(),
  )
  assert_true(named.active().branch is Some("feature/x"))
  assert_eq(named.active().diffstat, Some(stat))
  // A named branch is also what the pull-request lookup keys on, and the
  // lookup it issued is on record so a second reply cannot stack another.
  assert_eq(named.active().pull_request, Some(probing_for("feature/x")))
  assert_eq(named.active().pull_request_generation, 1)
  let (_, cleared) = update_dev(dispatch, branch_reply(""), named)
  assert_true(cleared.active().branch is Some(""))
  // A workspace that stopped being a repository keeps no pull request from
  // the branch it used to have — and the lookup still running for it is
  // retired rather than left holding a number the next one would reuse.
  assert_eq(cleared.active().pull_request, None)
  assert_eq(cleared.active().pull_request_generation, 2)
  let (_, overtaken) = update_dev(
    dispatch,
    pull_request_reply(
      "feature/x",
      generation=1,
      pull_request=test_pull_request(),
    ),
    cleared,
  )
  assert_eq(overtaken.active().pull_request, None)
  // A reply for an unknown session is dropped.
  let (_, ignored) = update_dev(
    dispatch,
    branch_reply("main", session="desktop-gone"),
    test_model(),
  )
  assert_true(ignored.active().branch is None)
}

///|
test "a superseded branch probe cannot put its older answer back" {
  let dispatch = test_dispatch()
  // Two probes in flight: a run's start and its finish, or either of those and
  // the popover being opened. The first is still counting untracked files.
  let (_, first) = probe_branch(
    dispatch,
    test_model(),
    @interop.ChannelId::Local,
    "desktop-test",
    None,
  )
  let (_, second) = probe_branch(
    dispatch,
    first,
    @interop.ChannelId::Local,
    "desktop-test",
    None,
  )
  assert_eq(second.active().branch_generation, 2)
  let newer : DiffStat = {
    added: 9,
    removed: 0,
    files: 1,
    base: Some("origin/main"),
    partial: false,
  }
  let (_, settled) = update_dev(
    dispatch,
    branch_reply("feature/new", generation=2, diffstat=newer),
    second,
  )
  assert_eq(settled.active().diffstat, Some(newer))
  // The slower first probe answers last, and is discarded: nothing would have
  // corrected its stale totals until the next refresh.
  let (_, overtaken) = update_dev(
    dispatch,
    branch_reply("feature/old", generation=1),
    settled,
  )
  assert_true(overtaken.active().branch is Some("feature/new"))
  assert_eq(overtaken.active().diffstat, Some(newer))
}

///|
test "a pull-request reply only lands on the branch it was asked about" {
  let dispatch = test_dispatch()
  // Measured from the base the answers below report, so settling one asks for
  // nothing further and this stays about which reply lands where.
  let (_, probing) = update_dev(
    dispatch,
    branch_reply("feature/x", base_hint="main"),
    test_model(),
  )
  let answer = test_pull_request()
  // A reply from a lookup that has since been superseded is dropped. The
  // branch name cannot decide this: a checkout that moves X → Y → X leaves two
  // lookups for X in flight at once, so which request answered is the question.
  let (_, stale) = update_dev(
    dispatch,
    pull_request_reply("feature/x", generation=0, pull_request=answer),
    probing,
  )
  assert_eq(stale.active().pull_request.unwrap().pull_request, None)
  assert_true(stale.active().pull_request.unwrap().probing)
  // The host answers about whatever `HEAD` said when it ran. An answer that
  // came back describing a different branch is filed under that branch, not
  // under the one the lookup was issued for — so the chip, which only shows a
  // probe matching the checked-out branch, does not show it against this one.
  let (_, moved) = update_dev(
    dispatch,
    pull_request_reply(
      "feature/x",
      generation=1,
      queried="feature/y",
      pull_request=answer,
    ),
    probing,
  )
  assert_eq(moved.active().pull_request.unwrap().branch, "feature/y")
  assert_eq(moved.active().settled_probe(), None)
  let (_, settled) = update_dev(
    dispatch,
    PullRequestLoaded(
      session="desktop-test",
      branch="feature/x",
      generation=1,
      queried=Some("feature/x"),
      pull_request=Some(answer),
      compare_url=None,
    ),
    probing,
  )
  assert_eq(
    settled.active().pull_request,
    Some({ ..probing_for("feature/x", pull_request=answer), probing: false, }),
  )
  // Refreshing the same branch keeps that answer on screen while it re-probes,
  // so the chip does not blink on every run boundary. A new request means a new
  // number; the answer it carries is the old one's, kept only until this lookup
  // replaces it.
  let (_, refreshing) = update_dev(
    dispatch,
    branch_reply("feature/x", base_hint="main"),
    settled,
  )
  assert_eq(
    refreshing.active().pull_request,
    Some(probing_for("feature/x", pull_request=answer)),
  )
  assert_eq(refreshing.active().pull_request_generation, 2)
}

///|
test "a pull request's base is measured from as soon as it is known" {
  let dispatch = test_dispatch()
  // The first probe of a session has no pull request to ask about, so the host
  // measured from its own guess and said so.
  let guessed : DiffStat = {
    added: 2467,
    removed: 51,
    files: 24,
    base: Some("origin/main"),
    partial: false,
  }
  let (_, probing) = update_dev(
    dispatch,
    branch_reply("feature/y", diffstat=guessed),
    test_model(),
  )
  assert_eq(probing.active().diffstat_hint, None)
  let branch_generation = probing.active().branch_generation
  // The lookup comes back naming a base no local rule would have guessed: this
  // branch sits on another one, so the totals on screen are the stack's, not
  // this branch's. Settling therefore asks for another measurement.
  let stacked = { ..test_pull_request(), base: "feature/x", }
  let (_, settled) = update_dev(
    dispatch,
    pull_request_reply("feature/y", generation=1, pull_request=stacked),
    probing,
  )
  assert_true(settled.active().branch_generation > branch_generation)
  // That measurement answers with the base it was given, which is what stops
  // the next settled answer from asking again.
  let measured : DiffStat = {
    ..guessed,
    added: 41,
    base: Some("origin/feature/x"),
  }
  let (_, remeasured) = update_dev(
    dispatch,
    branch_reply(
      "feature/y",
      generation=settled.active().branch_generation,
      diffstat=measured,
      base_hint="feature/x",
    ),
    settled,
  )
  assert_eq(remeasured.active().diffstat, Some(measured))
  assert_eq(remeasured.active().diffstat_hint, Some("feature/x"))
  let (_, quiet) = update_dev(
    dispatch,
    pull_request_reply(
      "feature/y",
      generation=remeasured.active().pull_request_generation,
      pull_request=stacked,
    ),
    remeasured,
  )
  assert_eq(
    quiet.active().branch_generation,
    remeasured.active().branch_generation,
  )
}

///|
test "a checkout that returns to a branch does not accept the older lookup" {
  let dispatch = test_dispatch()
  // X, then away to Y, then back to X: the first X lookup is still running,
  // and a second one for the same branch is now in flight beside it.
  let (_, first) = update_dev(dispatch, branch_reply("feature/x"), test_model())
  assert_eq(first.active().pull_request_generation, 1)
  let (_, away) = update_dev(dispatch, branch_reply("feature/y"), first)
  let (_, back) = update_dev(dispatch, branch_reply("feature/x"), away)
  assert_eq(back.active().pull_request_generation, 3)
  fn answered(generation : Int, number : Int) {
    pull_request_reply("feature/x", generation~, pull_request={
      ..test_pull_request(),
      number,
    })
  }

  fn picked(model : Model) raise {
    model.active().pull_request.unwrap().pull_request.unwrap().number
  }

  // The newer one settles first.
  let (_, settled) = update_dev(dispatch, answered(3, 710), back)
  assert_eq(picked(settled), 710)
  // The older one for the same branch arrives afterwards. Matching by name
  // would take it; matching by request does not.
  let (_, overtaken) = update_dev(dispatch, answered(1, 404), settled)
  assert_eq(picked(overtaken), 710)
}

///|
test "a reopened conversation does not accept the old record's replies" {
  let dispatch = test_dispatch()
  let (_, probing) = update_dev(
    dispatch,
    branch_reply("feature/x"),
    test_model(),
  )
  let generation = probing.active().pull_request_generation
  // Archiving and reopening the same session does not clear the record, it
  // builds a new one — counters included, which is why they cannot live there.
  let reopened = probing.replace_conversation(test_conversation())
  assert_eq(reopened.active().pull_request_generation, 0)
  let (_, again) = update_dev(dispatch, branch_reply("feature/x"), reopened)
  assert_true(again.active().pull_request_generation > generation)
  // The lookup the first record left running answers now, for a checkout the
  // reopened conversation has not confirmed anything about yet.
  let (_, late) = update_dev(
    dispatch,
    pull_request_reply(
      "feature/x",
      generation~,
      pull_request=test_pull_request(),
    ),
    again,
  )
  assert_eq(late.active().pull_request.unwrap().pull_request, None)
}

///|
test "a refresh during a lookup is run afterwards, not dropped" {
  let dispatch = test_dispatch()
  let refresh = branch_reply("feature/x")
  let (_, probing) = update_dev(dispatch, refresh, test_model())
  assert_true(probing.active().pull_request.unwrap().probing)
  // A run finishing while the run-start lookup is still in flight does not
  // stack a second request — but the answer it is waiting on was gathered
  // before that run's work, so it must not be the last word either.
  let (_, queued) = update_dev(dispatch, refresh, probing)
  assert_eq(
    queued.active().pull_request,
    Some({ ..probing_for("feature/x"), stale: true, }),
  )
  // Settling that lookup therefore issues another rather than leaving the
  // composer describing the repository as it was when the run started.
  let compare = "https://github.test/acme/app/compare/feature/x"
  let (_, followed) = update_dev(
    dispatch,
    pull_request_reply("feature/x", generation=1, compare_url=compare),
    queued,
  )
  guard followed.active().pull_request is Some(probe) else {
    fail("the queued refresh dropped the probe")
  }
  assert_true(probe.probing)
  assert_false(probe.stale)
  // Its answer stays on screen while the follow-up runs.
  assert_true(probe.compare_url is Some(_))
  // With nothing queued, settling is the end of it.
  let (_, quiet) = update_dev(
    dispatch,
    pull_request_reply("feature/x", generation=1),
    probing,
  )
  assert_false(quiet.active().pull_request.unwrap().probing)
  // A queued retry after an answer about a branch the checkout has left drops
  // that answer instead of relabelling it: carrying it over would reintroduce
  // exactly the mismatch the reply's own branch is there to prevent. The retry
  // is a new request, so it carries the next number.
  let (_, elsewhere) = update_dev(
    dispatch,
    pull_request_reply(
      "feature/x",
      generation=1,
      queried="feature/y",
      pull_request=test_pull_request(),
    ),
    queued,
  )
  assert_eq(elsewhere.active().pull_request, Some(probing_for("feature/x")))
  assert_eq(elsewhere.active().pull_request_generation, 2)
}

///|
test "custom select menus switch and dismiss deterministically" {
  let dispatch = test_dispatch()
  let base = test_model()
  let (_, opened) = update(dispatch, ToggleSelectMenu(OpenSeekModelMenu), base)
  assert_true(opened.select_menu == Some(OpenSeekModelMenu))
  // The transition is pure: replaying the same message against the same
  // model produces the same open menu rather than consulting DOM state.
  let (_, replayed) = update(
    dispatch,
    ToggleSelectMenu(OpenSeekModelMenu),
    base,
  )
  assert_true(replayed.select_menu == opened.select_menu)
  let (_, switched) = update(
    dispatch,
    ToggleSelectMenu(OpenSeekReasoningMenu),
    opened,
  )
  assert_true(switched.select_menu == Some(OpenSeekReasoningMenu))
  let (_, closed) = update(dispatch, CloseSelectMenu, switched)
  assert_true(closed.select_menu is None)
  let (_, closed_again) = update(dispatch, CloseSelectMenu, closed)
  assert_true(closed_again.select_menu is None)
  // Selecting a valid row closes the popup in the same state transition that
  // applies the value; no native menu is left to close itself afterwards.
  let (_, reopened) = update(
    dispatch,
    ToggleSelectMenu(OpenSeekModelMenu),
    closed_again,
  )
  let (_, picked) = update(
    dispatch,
    ModelPicked("openseek:deepseek-v4-flash"),
    reopened,
  )
  assert_true(picked.select_menu is None)
  let (_, reasoning_open) = update(
    dispatch,
    ToggleSelectMenu(OpenSeekReasoningMenu),
    picked,
  )
  let (_, effort_picked) = update(
    dispatch,
    OpenSeekEffortPicked("high"),
    reasoning_open,
  )
  assert_true(effort_picked.select_menu is None)
  let (_, settings_open) = update(
    dispatch,
    ToggleSelectMenu(ThemeMenu),
    effort_picked,
  )
  assert_true(settings_open.select_menu == Some(ThemeMenu))
  let (_, theme_picked) = update(dispatch, ThemeChanged("dark"), settings_open)
  assert_true(theme_picked.theme is Dark)
  assert_true(theme_picked.select_menu is None)
  let (_, open_before_switch) = update(
    dispatch,
    ToggleSelectMenu(OpenSeekModelMenu),
    theme_picked,
  )
  let (_, context_switched) = update(
    dispatch,
    SessionRotated({ channel: Local, session: "desktop-other", }),
    open_before_switch,
  )
  assert_true(context_switched.select_menu is None)
}

///|
test "a covering overlay dismisses an open custom select" {
  let dispatch = test_dispatch()
  let base = { ..test_model(), select_menu: Some(OpenSeekModelMenu), }
  let (_, lost) = update(
    dispatch,
    FromDevice(Local, BridgeUnavailable("bridge stopped")),
    base,
  )
  assert_true(lost.bridge_state() is BridgeLost(_))
  assert_true(lost.select_menu is None)
}

///|
test "GLM and DeepSeek remember independent reasoning choices" {
  let dispatch = test_dispatch()
  let glm = test_model().replace_conversation({
    ..test_conversation(),
    engine_model: Glm53,
  })
  guard glm.openseek_reasoning_chip(glm.active()) is Some(control) else {
    fail("GLM reasoning control was hidden")
  }
  assert_eq(control.selected, "no")
  assert_eq(control.options[0].label, "Low")
  assert_eq(control.title, "Reasoning effort: Low")
  // Max is not DeepSeek's default, so the two sides stay distinguishable.
  let (_, glm_max) = update(dispatch, OpenSeekEffortPicked("max"), glm)
  assert_true(glm_max.glm_reasoning is ReasoningMax)
  assert_true(glm_max.openseek_reasoning is ReasoningHigh)
  let deepseek = glm_max.replace_conversation({
    ..glm_max.active(),
    engine_model: DsPro,
  })
  let (_, deepseek_off) = update(dispatch, OpenSeekEffortPicked("no"), deepseek)
  assert_true(deepseek_off.openseek_reasoning is ReasoningOff)
  assert_true(deepseek_off.glm_reasoning is ReasoningMax)
}

///|
test "the composer's git details popover toggles shut again" {
  let dispatch = test_dispatch()
  // The popover has no trigger without a branch, so a conversation that has
  // one is where this starts — the flag cannot be raised otherwise.
  let (_, on_branch) = update_dev(
    dispatch,
    branch_reply("feature/x"),
    test_model(),
  )
  assert_false(on_branch.git_details_open)
  let (_, opened) = update(dispatch, ToggleGitDetails, on_branch)
  assert_true(opened.git_details_open)
  // Opening re-probes (the command is not inspectable here), which must not
  // disturb what is already on screen: the answer stays until its reply lands.
  assert_eq(opened.active().pull_request, on_branch.active().pull_request)
  assert_eq(opened.active().diffstat, on_branch.active().diffstat)
  let (_, closed) = update(dispatch, ToggleGitDetails, opened)
  assert_false(closed.git_details_open)
  // Switching conversations closes it, and so does the branch going away under
  // the conversation on screen. Neither produces a click for the dismissal
  // listener to see, and with no chip rendered nothing is left to click the
  // popover shut — the flag would go on hiding the native browser with no
  // visible cause.
  let (_, switched) = update(
    dispatch,
    SessionRotated({ channel: Local, session: "desktop-other", }),
    opened,
  )
  assert_eq(switched.active_session, "desktop-other")
  assert_false(switched.git_details_open)
  let (_, lost) = update_dev(
    dispatch,
    branch_reply("", generation=opened.active().branch_generation),
    opened,
  )
  assert_false(lost.active().shows_git_chip())
  assert_false(lost.git_details_open)
  // Dismissal is idempotent where the toggle is not: the click that closes the
  // popover also reaches whatever it landed on, and a second dismissal — from
  // a page that dispatched one on its own — must not bring it back.
  let (_, dismissed) = update(dispatch, CloseGitDetails, opened)
  assert_false(dismissed.git_details_open)
  let (_, still_closed) = update(dispatch, CloseGitDetails, dismissed)
  assert_false(still_closed.git_details_open)
}

///|
test "right-panel menu closes without reopening on a second dismissal" {
  let dispatch = test_dispatch()
  // Right-panel actions update the root's single visibility state directly.
  let (_, docked) = update(dispatch, ToggleRightPanel, desktop_model())
  // The empty strip is the launcher's deliberate open state. A delayed close
  // for a tab that is already gone must not collapse that surface.
  let (_, empty) = update(
    dispatch,
    Dock(TabClosed(@dock.DockTab::FilePicker)),
    docked,
  )
  assert_true(empty.right_panel_open)
  let (_, menued) = update(dispatch, ToggleRightPanelMenu, empty)
  assert_true(menued.right_panel_menu_open)
  let (_, unmenued) = update(dispatch, CloseRightPanelMenu, menued)
  assert_false(unmenued.right_panel_menu_open)
  let (_, unmenued_twice) = update(dispatch, CloseRightPanelMenu, unmenued)
  assert_false(unmenued_twice.right_panel_menu_open)
  let (_, expanded) = update(dispatch, ToggleRightPanelExpanded, unmenued_twice)
  assert_true(expanded.right_panel_expanded)
  assert_false(expanded.right_panel_menu_open)
  let (_, restored) = update(dispatch, ToggleRightPanelExpanded, expanded)
  assert_false(restored.right_panel_expanded)
  let (_, expanded_again) = update(dispatch, ToggleRightPanelExpanded, restored)
  let (_, hidden) = update(dispatch, ToggleRightPanel, expanded_again)
  assert_false(hidden.right_panel_open)
  assert_false(hidden.right_panel_expanded)
  let (_, still_hidden) = update(dispatch, ToggleRightPanelExpanded, hidden)
  assert_true(still_hidden == hidden)
}

///|
test "right-panel menu closes when the dock owner changes" {
  let dispatch = test_dispatch()
  let model = desktop_model()
  let stale_owner : @interop.ConversationKey = {
    channel: @interop.Local,
    session: "stale-panel-owner",
  }
  let stale = {
    ..model,
    right_panel_open: true,
    right_panel_menu_open: true,
    dock: { ..model.dock, owner: Some(stale_owner), },
  }
  // Any root message runs the centralized dock synchronization. The owner
  // transition closes the menu directly, with no rendered marker or observer.
  let (_, synced) = update(dispatch, CloseGitDetails, stale)
  assert_false(synced.right_panel_menu_open)
  assert_true(synced.dock.owner != Some(stale_owner))
}

///|
/// An archived row in `channel`'s fixture project store — where the fixture
/// conversation's record lives, so an archive fact about it addresses that
/// same durable identity.
fn archived_item(
  id : String,
  channel? : @interop.ChannelId = Local,
) -> @transcript.SessionListItem {
  {
    id,
    title: Some(""),
    workspace: channel.test_project(),
    workspace_name: "work",
    updated_at_ms: None,
  }
}

///|
/// An archived row in `test_project` — the store the fixture conversation
/// lives in, so an archive fact about it addresses the same durable identity.
fn placed_archived_item(id : String) -> @transcript.SessionListItem {
  {
    id,
    title: Some(""),
    workspace: @interop.ChannelId::Local.test_project(),
    workspace_name: "work",
    updated_at_ms: None,
  }
}

///|
test "opening an archived row creates a read-only transcript owner" {
  let dispatch = test_dispatch()
  let item = archived_item("desktop-archived")
  let model = test_model().with_dev(dev => { ..dev, archived: [item], })
  let open = OpenArchivedSession(
    @interop.ChannelId::Local,
    session=item.id,
    workspace=item.workspace,
  )
  let (_, loading) = update(dispatch, open, model)
  inspect(loading.active_session, content="desktop-archived")
  assert_true(loading.active().record is ArchivedRecord)
  guard loading.active().sync is Reloading(generation=1, attempt=1, ..) else {
    fail("the archived transcript did not begin its first read")
  }
  assert_true(
    loading.loading_conversation
    is Some({ channel: Local, session: "desktop-archived", }),
  )
  // Re-selecting the same row stays single-flight; it does not mint a second
  // generation that could overtake the first archived snapshot.
  let (_, selected_again) = update(dispatch, open, loading)
  guard selected_again.active().sync is Reloading(generation=1, ..) else {
    fail("re-selecting an archived row replaced the in-flight generation")
  }
}

///|
test "switching same-id archived stores fences the first transcript load" {
  let dispatch = test_dispatch()
  let first = @interop.ChannelId::Local.test_resource("/first")
  let second = @interop.ChannelId::Local.test_resource("/second")
  let first_item : @transcript.SessionListItem = {
    ..archived_item("desktop-shared"),
    workspace: first,
    workspace_name: "first",
    updated_at_ms: None,
  }
  let second_item : @transcript.SessionListItem = {
    ..first_item,
    workspace: second,
    workspace_name: "second",
    updated_at_ms: None,
  }
  let model = test_model().with_dev(dev => {
    ..dev,
    archived: [first_item, second_item],
    projects: [first, second],
  })
  let (_, loading_first) = update(
    dispatch,
    OpenArchivedSession(
      @interop.ChannelId::Local,
      session=first_item.id,
      workspace=first_item.workspace,
    ),
    model,
  )
  guard loading_first.active().sync is Reloading(generation=1, ..) else {
    fail("the first archived store did not begin loading")
  }
  assert_eq(loading_first.active().workspace, Project(root=first))
  let (_, loading_second) = update(
    dispatch,
    OpenArchivedSession(
      @interop.ChannelId::Local,
      session=second_item.id,
      workspace=second_item.workspace,
    ),
    loading_first,
  )
  guard loading_second.active().sync is Reloading(generation=2, ..) else {
    fail("the second archived store reused the first request generation")
  }
  assert_eq(loading_second.active().workspace, Project(root=second))
  let (_, stale_first) = update_dev(
    dispatch,
    SessionLoaded(
      session=first_item.id,
      items=[
        {
          kind: Assistant(
            reasoning=None,
            prose=Some("first store answer"),
            calls=[],
            replay=false,
            finished=false,
          ),
          ts: None,
          sequence: Some(1),
        },
      ],
      watermark=1,
      goal=None,
      goal_markers=[],
      generation=1,
    ),
    loading_second,
  )
  inspect(stale_first.active().messages.length(), content="0")
  assert_eq(stale_first.active().workspace, Project(root=second))
  let (_, loaded_second) = update_dev(
    dispatch,
    SessionLoaded(
      session=second_item.id,
      items=[
        {
          kind: Assistant(
            reasoning=None,
            prose=Some("second store answer"),
            calls=[],
            replay=false,
            finished=false,
          ),
          ts: None,
          sequence: Some(1),
        },
      ],
      watermark=1,
      goal=None,
      goal_markers=[],
      generation=2,
    ),
    stale_first,
  )
  inspect(loaded_second.active().messages.length(), content="1")
  assert_eq(
    loaded_second.active().messages[0].text(),
    Some("second store answer"),
  )
}

///|
test "archived transcripts reject record-changing actions in update" {
  let dispatch = test_dispatch()
  let archived = {
    ..test_conversation(),
    record: ArchivedRecord,
    task: "must stay unsent",
    goal_edit: Some({ draft: "must stay unset", }),
  }
  let model = test_model().replace_conversation(archived)
  let (_, sent) = update(dispatch, Send, model)
  assert_true(sent.active().run is NoRun(ended=None))
  inspect(sent.active().task, content="must stay unsent")
  let (_, goal) = update(dispatch, SubmitGoal, model)
  assert_true(goal.active().goal_pending is None)
  assert_true(goal.active().goal_edit is Some(_))
  let (_, compacted) = run_slash_command(dispatch, model, "compact")
  assert_true(compacted.active().compaction is NotCompacting)
  inspect(compacted.active().task, content="must stay unsent")
}

///|
test "an archived snapshot stays open across archived-list reconciliation" {
  let dispatch = test_dispatch()
  let item = archived_item("desktop-archived")
  let model = test_model().with_dev(dev => { ..dev, archived: [item], })
  let (_, loading) = update(
    dispatch,
    OpenArchivedSession(
      @interop.ChannelId::Local,
      session=item.id,
      workspace=item.workspace,
    ),
    model,
  )
  let (_, loaded) = update_dev(
    dispatch,
    SessionLoaded(
      goal=None,
      goal_markers=[],
      session=item.id,
      items=[
        {
          kind: Assistant(
            reasoning=None,
            prose=Some("archived answer"),
            calls=[],
            replay=false,
            finished=false,
          ),
          ts: None,
          sequence: Some(1),
        },
      ],
      watermark=1,
      generation=1,
    ),
    loading,
  )
  assert_true(loaded.active().record is ArchivedRecord)
  assert_eq(loaded.active().messages[0].text(), Some("archived answer"))
  let (_, reconciled) = update(dispatch, archived_loaded([item]), loaded)
  inspect(reconciled.active_session, content="desktop-archived")
  assert_true(reconciled.active().record is ArchivedRecord)
  assert_eq(reconciled.active().messages[0].text(), Some("archived answer"))
}

///|
test "unarchiving an open transcript fences its archived snapshot" {
  let dispatch = test_dispatch()
  let item = archived_item("desktop-archived")
  let archived = {
    ..empty_conversation(
      @interop.ChannelId::Local,
      item.id,
      @interop.ChannelId::Local.test_project(),
    ),
    record: ArchivedRecord,
    messages: [
      {
        kind: Assistant(
          reasoning=None,
          prose=Some("visible archived answer"),
          calls=[],
          replay=false,
          finished=false,
        ),
        ts: None,
        sequence: Some(1),
      },
    ],
    watermark: 1,
  }
  let model = {
    ..test_model()
    .replace_conversation(archived)
    .with_dev(dev => { ..dev, archived: [item], }),
    active_session: item.id,
    transcript_request_generation: 1,
  }
  let (_, restoring) = update_dev(
    dispatch,
    SessionsChanged(
      change="unarchived",
      key={ session: item.id, workspace: item.workspace, },
      fresh_session=None,
    ),
    model,
  )
  assert_true(restoring.active().record is LiveRecord)
  guard restoring.active().sync is Reloading(generation=2, ..) else {
    fail("unarchive did not fence the archived read with a live generation")
  }
  let (_, stale) = update_dev(
    dispatch,
    SessionLoaded(
      goal=None,
      goal_markers=[],
      session=item.id,
      items=[
        {
          kind: Assistant(
            reasoning=None,
            prose=Some("late archived answer"),
            calls=[],
            replay=false,
            finished=false,
          ),
          ts: None,
          sequence: Some(1),
        },
      ],
      watermark=1,
      generation=1,
    ),
    restoring,
  )
  assert_true(stale.active().record is LiveRecord)
  assert_eq(stale.active().messages[0].text(), Some("visible archived answer"))
}

///|
test "session.changed decoder preserves archive invalidation identity" {
  let store = @interop.ChannelId::Local.test_project()
  guard session_changed_msg(@interop.ChannelId::Local, {
      change: "archived",
      session: "desktop-old",
      workspace: store.path,
    })
    is Some(
      SessionsChanged(change="archived", key=archived, fresh_session=Some(_))
    ) else {
    fail("archive invalidation was not decoded")
  }
  assert_true(archived == { session: "desktop-old", workspace: store, })
  guard session_changed_msg(@interop.ChannelId::Local, {
      change: "deleted",
      session: "desktop-old",
      workspace: store.path,
    })
    is Some(
      SessionsChanged(change="deleted", key=deleted, fresh_session=Some(_))
    ) else {
    fail("delete invalidation was not decoded")
  }
  assert_true(deleted == { session: "desktop-old", workspace: store, })
  // Every durable record lives in a workspace store, so a notification that
  // names none identifies no record and is refused outright.
  assert_true(
    session_changed_msg(@interop.ChannelId::Local, {
      change: "archived",
      session: "desktop-old",
      workspace: "",
    })
    is None,
  )
}

///|
test "archived deletion confirmation owns one visible conversation family" {
  let dispatch = test_dispatch()
  let parent = archived_item("desktop-parent")
  let child = archived_item("desktop-parent-sr-1")
  let model = test_model().with_dev(dev => {
    ..dev,
    archived: [parent, child, archived_item("desktop-other")],
  })
  let (_, staged) = update(
    dispatch,
    DeleteArchivedSession(@interop.ChannelId::Local, {
      session: "desktop-parent",
      workspace: @interop.ChannelId::Local.test_project(),
    }),
    model,
  )
  guard staged.archived_delete_confirm is Some(confirm) else {
    fail("delete confirmation was not staged")
  }
  assert_true(
    confirm.key ==
    {
      session: "desktop-parent",
      workspace: @interop.ChannelId::Local.test_project(),
    },
  )
  // The record's blank title falls back to its id: the dialog names what the
  // archived list showed, not whatever label the click happened to carry.
  assert_eq(confirm.title, "desktop-parent")
  assert_true(confirm.sessions.contains("desktop-parent"))
  assert_true(confirm.sessions.contains("desktop-parent-sr-1"))
  let (_, cancelled) = update(dispatch, CancelDeleteArchivedSession, staged)
  assert_true(cancelled.archived_delete_confirm is None)
  let (_, cancelled_twice) = update(
    dispatch,
    CancelDeleteArchivedSession,
    cancelled,
  )
  assert_true(cancelled_twice.archived_delete_confirm is None)
  let (_, confirmed) = update(dispatch, ConfirmDeleteArchivedSession, staged)
  assert_true(confirmed.archived_delete_confirm is None)
  assert_eq(confirmed.dev().archived_request_generation, 1)
  let (_, confirmed_twice) = update(
    dispatch,
    ConfirmDeleteArchivedSession,
    confirmed,
  )
  assert_eq(confirmed_twice.dev().archived_request_generation, 1)
}

///|
test "archived deletion keeps same-id rows in other stores" {
  let dispatch = test_dispatch()
  let project = @interop.ChannelId::Local.test_resource("/project")
  let unplaced = archived_item("shared")
  let project_parent : @transcript.SessionListItem = {
    ..archived_item("shared"),
    workspace: project,
    workspace_name: "project",
    updated_at_ms: None,
  }
  let project_child : @transcript.SessionListItem = {
    ..project_parent,
    id: "shared-sr-1",
  }
  // The other store's live row deliberately comes first. Store-qualified
  // active deletion must use the open conversation, not this same-id row.
  let model = {
    ..test_model()
    .replace_conversation({
      ..empty_conversation(
        @interop.ChannelId::Local,
        "shared",
        @interop.ChannelId::Local.test_project(),
      ),
      workspace: Project(root=project),
      record: ArchivedRecord,
      task: "project draft",
    })
    .with_dev(dev => {
      ..dev,
      sessions: [unplaced],
      archived: [unplaced, project_parent, project_child],
    }),
    active_session: "shared",
  }
  let key : ArchiveRecordKey = { session: "shared", workspace: project, }
  let (_, staged) = update(
    dispatch,
    DeleteArchivedSession(@interop.ChannelId::Local, key),
    model,
  )
  guard staged.archived_delete_confirm is Some(confirm) else {
    fail("delete confirmation was not staged")
  }
  assert_true(confirm.key == key)
  assert_eq(confirm.sessions, ["shared", "shared-sr-1"])
  let response_model = staged.with_dev(dev => {
    ..dev,
    archived_request_generation: 1,
  })
  let (_, deleted) = update_dev(
    dispatch,
    ArchivedDeleted(
      key~,
      sessions=confirm.sessions,
      items=[unplaced, project_parent, project_child],
      connection_generation=0,
      request_generation=1,
      fresh_session="desktop-fresh",
    ),
    response_model,
  )
  assert_true(deleted.dev().archived == [unplaced])
  inspect(deleted.active_session, content="desktop-fresh")
  inspect(deleted.active().task, content="")
}

///|
test "delete response tombstones a family before stale list replies" {
  let dispatch = test_dispatch()
  let parent = archived_item("desktop-parent")
  let child = archived_item("desktop-parent-sr-1")
  let other = archived_item("desktop-other")
  let model = {
    ..test_model().with_dev(dev => {
      ..dev,
      archived_request_generation: 1,
      archived: [parent, child, other],
      sessions: [parent, child],
    }),
    conversations: [
      {
        ..empty_conversation(
          @interop.ChannelId::Local,
          "desktop-parent",
          @interop.ChannelId::Local.test_project(),
        ),
        record: ArchivedRecord,
        task: "keep local draft",
      },
      empty_conversation(
        @interop.ChannelId::Local,
        "desktop-parent-sr-1",
        @interop.ChannelId::Local.test_project(),
      ),
    ],
    active_session: "desktop-parent",
  }
  let deleted_msg = ArchivedDeleted(
    key={
      session: "desktop-parent",
      workspace: @interop.ChannelId::Local.test_project(),
    },
    sessions=["desktop-parent", "desktop-parent-sr-1"],
    items=[parent, child, other],
    connection_generation=0,
    request_generation=1,
    fresh_session="desktop-fresh",
  )
  let (_, deleted) = update_dev(dispatch, deleted_msg, model)
  let (_, same_input) = update_dev(dispatch, deleted_msg, model)
  inspect(deleted.active_session, content="desktop-fresh")
  assert_eq(same_input.active_session, deleted.active_session)
  assert_eq(same_input.active().task, deleted.active().task)
  inspect(deleted.active().task, content="")
  assert_eq(deleted.dev().archived.length(), 1)
  assert_eq(deleted.dev().archived[0].id, "desktop-other")
  assert_false(deleted.dev().sessions.contains(parent))
  assert_false(deleted.dev().sessions.contains(child))
  assert_true(
    deleted.find_conversation(@interop.ChannelId::Local, "desktop-parent")
    is None,
  )
  assert_true(
    deleted.find_conversation(@interop.ChannelId::Local, "desktop-parent-sr-1")
    is None,
  )
  let (_, stale_live) = update_dev(
    dispatch,
    SessionsLoaded(
      [parent, child],
      connection_generation=0,
      request_generation=0,
    ),
    deleted,
  )
  assert_false(stale_live.dev().sessions.contains(parent))
  assert_false(stale_live.dev().sessions.contains(child))
}

///|
test "a new Started incarnation retires its exact deleted tombstone" {
  let dispatch = test_dispatch()
  let deleted_item = archived_item("desktop-recreated")
  let project = @interop.ChannelId::Local.test_resource("/project")
  let model = test_model().with_dev(dev => {
    ..dev,
    archived_request_generation: 1,
    archived: [deleted_item],
    projects: [project],
  })
  let (_, deleted) = update_dev(
    dispatch,
    ArchivedDeleted(
      key={
        session: deleted_item.id,
        workspace: @interop.ChannelId::Local.test_project(),
      },
      sessions=[deleted_item.id],
      items=[deleted_item],
      connection_generation=0,
      request_generation=1,
      fresh_session="desktop-fresh",
    ),
    model,
  )
  assert_true(
    deleted
    .dev()
    .archive_override({
      session: deleted_item.id,
      workspace: @interop.ChannelId::Local.test_project(),
    })
    is Some(ArchiveDeleted),
  )
  // A same-id creation in another store is unrelated and cannot lift the
  // tombstone selected here.
  let (_, unrelated) = update_dev(
    dispatch,
    Started(
      run_id="unrelated-run",
      session=deleted_item.id,
      model=DsPro,
      max_steps=1000,
      session_root=Some(
        @interop.ChannelId::Local.test_resource("/project/.openseek"),
      ),
      submission_id=None,
    ),
    deleted,
  )
  assert_true(
    unrelated
    .dev()
    .archive_override({
      session: deleted_item.id,
      workspace: @interop.ChannelId::Local.test_project(),
    })
    is Some(ArchiveDeleted),
  )
  let (_, started) = update_dev(
    dispatch,
    Started(
      run_id="recreated-run",
      session=deleted_item.id,
      model=DsPro,
      max_steps=1000,
      session_root=Some(@interop.ChannelId::Local.test_store_root()),
      submission_id=None,
    ),
    deleted,
  )
  assert_true(
    started
    .dev()
    .archive_override({
      session: deleted_item.id,
      workspace: @interop.ChannelId::Local.test_project(),
    })
    is Some(ArchiveLive),
  )
  let (_, committed) = update_dev(
    dispatch,
    SessionCommitted(
      session=deleted_item.id,
      sequence=1,
      ts=None,
      item=@protocol.User({ content: "new incarnation", submission_id: None, }),
      session_root=@interop.ChannelId::Local.test_store_root(),
    ),
    started,
  )
  guard committed.find_conversation(@interop.ChannelId::Local, deleted_item.id)
    is Some(recreated) else {
    fail("the recreated conversation stayed hidden")
  }
  guard recreated.sync is Reloading(generation~, buffered~, ..) else {
    fail("the recreated conversation did not retain its first commit")
  }
  inspect(buffered.length(), content="1")
  inspect(buffered[0].sequence, content="1")
  let (_, reconciled) = update_dev(
    dispatch,
    SessionRefreshed(
      session=deleted_item.id,
      items=[],
      watermark=0,
      goal=None,
      goal_markers=[],
      generation~,
    ),
    committed,
  )
  guard reconciled.find_conversation(@interop.ChannelId::Local, deleted_item.id)
    is Some(recreated) else {
    fail("the recreated conversation disappeared after its snapshot")
  }
  assert_true(
    recreated.messages
    .iter()
    .any(message => message.text() == Some("new incarnation")),
  )
}

///|
test "deleted broadcast is immediate and idempotent" {
  let dispatch = test_dispatch()
  let item = archived_item("desktop-gone")
  let project = @interop.ChannelId::Local.test_resource("/project")
  let same_id_project : @transcript.SessionListItem = {
    ..item,
    workspace: project,
    workspace_name: "project",
    updated_at_ms: None,
  }
  let model = {
    ..test_model()
    .replace_conversation({
      ..empty_conversation(
        @interop.ChannelId::Local,
        "desktop-gone",
        @interop.ChannelId::Local.test_project(),
      ),
      record: ArchivedRecord,
      task: "carry this draft",
    })
    .with_dev(dev => {
      ..dev,
      sessions: [item, same_id_project],
      archived: [item, same_id_project],
    }),
    active_session: "desktop-gone",
  }
  let deleted_msg = SessionsChanged(
    change="deleted",
    key={
      session: "desktop-gone",
      workspace: @interop.ChannelId::Local.test_project(),
    },
    fresh_session=Some("desktop-fresh"),
  )
  let (_, deleted) = update_dev(dispatch, deleted_msg, model)
  let (_, same_input) = update_dev(dispatch, deleted_msg, model)
  inspect(deleted.active_session, content="desktop-fresh")
  assert_eq(same_input.active_session, deleted.active_session)
  assert_eq(same_input.active().task, deleted.active().task)
  inspect(deleted.active().task, content="")
  assert_true(
    deleted.find_conversation(@interop.ChannelId::Local, "desktop-gone") is None,
  )
  assert_false(deleted.dev().sessions.contains(item))
  assert_false(deleted.dev().archived.contains(item))
  assert_true(deleted.dev().sessions.contains(same_id_project))
  assert_true(deleted.dev().archived.contains(same_id_project))
  let (_, deleted_twice) = update_dev(dispatch, deleted_msg, deleted)
  assert_false(deleted_twice.dev().sessions.contains(item))
  assert_false(deleted_twice.dev().archived.contains(item))
}

///|
test "deleted broadcast rotates the active conversation's exact store" {
  let dispatch = test_dispatch()
  let unplaced = archived_item("shared")
  let project = @interop.ChannelId::Local.test_resource("/project")
  let project_item : @transcript.SessionListItem = {
    ..unplaced,
    workspace: project,
    workspace_name: "project",
    updated_at_ms: None,
  }
  let model = {
    ..test_model()
    .replace_conversation({
      ..empty_conversation(
        @interop.ChannelId::Local,
        "shared",
        @interop.ChannelId::Local.test_project(),
      ),
      workspace: Project(root=project),
      record: ArchivedRecord,
      task: "project draft",
    })
    .with_dev(dev => { ..dev, sessions: [unplaced], archived: [project_item], }),
    active_session: "shared",
  }
  let (_, deleted) = update_dev(
    dispatch,
    SessionsChanged(
      change="deleted",
      key={ session: "shared", workspace: project, },
      fresh_session=Some("desktop-fresh"),
    ),
    model,
  )
  inspect(deleted.active_session, content="desktop-fresh")
  inspect(deleted.active().task, content="")
  assert_true(deleted.dev().sessions == [unplaced])
  assert_true(deleted.dev().archived.is_empty())
}

///|
test "archive facts rotate the open conversation's exact store" {
  let dispatch = test_dispatch()
  let unplaced = archived_item("shared")
  let project = @interop.ChannelId::Local.test_resource("/project")
  let project_item : @transcript.SessionListItem = {
    ..unplaced,
    workspace: project,
    workspace_name: "project",
    updated_at_ms: None,
  }
  // The other store's row deliberately comes first: session_project("shared")
  // resolves to it, while the conversation actually open on screen belongs to
  // the project store being archived.
  let model = {
    ..test_model()
    .replace_conversation({
      ..empty_conversation(
        @interop.ChannelId::Local,
        "shared",
        @interop.ChannelId::Local.test_project(),
      ),
      workspace: Project(root=project),
      task: "project draft",
    })
    .with_dev(dev => { ..dev, sessions: [unplaced, project_item], }),
    active_session: "shared",
  }
  let (_, notified) = update_dev(
    dispatch,
    SessionsChanged(
      change="archived",
      key={ session: "shared", workspace: project, },
      fresh_session=Some("notification-fresh"),
    ),
    model,
  )
  inspect(notified.active_session, content="notification-fresh")
  inspect(notified.active().task, content="")
  assert_true(
    notified.find_conversation(@interop.ChannelId::Local, "shared") is None,
  )
  assert_true(notified.dev().sessions == [unplaced])
  let (_, listed) = update(dispatch, archived_loaded([project_item]), model)
  inspect(listed.active_session, content="desktop-archive-replacement")
  inspect(listed.active().task, content="")
  assert_true(
    listed.find_conversation(@interop.ChannelId::Local, "shared") is None,
  )
  assert_true(listed.dev().sessions == [unplaced])
}

///|
test "archive broadcast invalidates the active send target before list replies" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/work/archived")
  let mention : Mention = { ref_: Skill(name="draft-skill"), range: None, }
  // The open conversation, not the sidebar row below, is the store owner
  // that the archive notification must retire.
  let model = test_model()
    .replace_conversation({
      ..test_conversation(),
      workspace: Project(root=workspace),
      task: "must not target archived session",
      mentions: [mention],
    })
    .with_dev(dev => {
      ..dev.with_workspace_settings(workspace, true, generation=1),
      sessions: [
        {
          ..placed_archived_item("desktop-test"),
          workspace,
          workspace_name: "archived",
          updated_at_ms: None,
        },
      ],
      worktrees: [{ project: workspace, rows: [], generation: 1, }],
    })
  let (_, invalidated) = update_dev(
    dispatch,
    SessionsChanged(
      change="archived",
      key={ session: "desktop-test", workspace, },
      fresh_session=Some("desktop-fresh"),
    ),
    model,
  )
  inspect(invalidated.active_session, content="desktop-fresh")
  assert_true(
    invalidated.find_conversation(@interop.ChannelId::Local, "desktop-test")
    is None,
  )
  inspect(invalidated.active().session_id, content="desktop-fresh")
  assert_eq(invalidated.dev().active_project, Some(workspace))
  assert_eq(invalidated.active().workspace, Project(root=workspace))
  assert_true(invalidated.active().worktree_mode)
  inspect(invalidated.active().task, content="")
  assert_true(invalidated.active().mentions.is_empty())
  assert_true(
    invalidated.dev().archived.iter().any(item => item.id == "desktop-test"),
  )
  assert_false(
    invalidated.dev().sessions.iter().any(item => item.id == "desktop-test"),
  )
  // Even before either sidebar refresh returns, the next submit belongs to
  // the replacement conversation; no live state can target the archived id.
  let drafted = invalidated.replace_conversation({
    ..invalidated.active(),
    task: "safe replacement",
  })
  let (_, sent) = update(dispatch, Send, drafted)
  inspect(sent.active_session, content="desktop-fresh")
  inspect(sent.active().session_id, content="desktop-fresh")
  assert_true(sent.active().run is Starting(..))
  assert_true(
    sent.find_conversation(@interop.ChannelId::Local, "desktop-test") is None,
  )
}

///|
test "an archive response arriving before its notification discards the draft once" {
  let dispatch = test_dispatch()
  let model = test_model()
    .replace_conversation({ ..test_conversation(), task: "keep this draft", })
    .with_dev(dev => {
      ..dev,
      sessions: [placed_archived_item("desktop-test")],
    })
  let (_, responded) = update(
    dispatch,
    archived_loaded([placed_archived_item("desktop-test")]),
    model,
  )
  inspect(responded.active_session, content="desktop-archive-replacement")
  inspect(responded.active().task, content="")
  let (_, notified) = update_dev(
    dispatch,
    SessionsChanged(
      change="archived",
      key={
        session: "desktop-test",
        workspace: @interop.ChannelId::Local.test_project(),
      },
      fresh_session=Some("desktop-notification-replacement"),
    ),
    responded,
  )
  // The late duplicate only refreshes the tombstone; it cannot rotate the
  // fallback composer a second time.
  inspect(notified.active_session, content="desktop-archive-replacement")
  inspect(notified.active().task, content="")
}

///|
test "archiving a pending start discards its composer without ownership" {
  let dispatch = test_dispatch()
  let sent_mention : Mention = { ref_: Skill(name="sent-skill"), range: None, }
  let newer_mention : Mention = {
    ref_: Skill(name="newer-skill"),
    range: None,
  }
  let pending = {
    ..test_conversation(),
    pending_prompt: Some({
      submission_id: "pending-start",
      draft: "original draft",
      mentions: [sent_mention],
    }),
  }
  let model = test_model()
    .replace_conversation({
      ..pending,
      run: Starting(submission_id="pending-start"),
      task: "typed afterward",
      mentions: [newer_mention],
    })
    .with_dev(dev => {
      ..dev,
      sessions: [placed_archived_item("desktop-test")],
    })
  let (_, next) = update_dev(
    dispatch,
    SessionsChanged(
      change="archived",
      key={
        session: "desktop-test",
        workspace: @interop.ChannelId::Local.test_project(),
      },
      fresh_session=Some("desktop-restored"),
    ),
    model,
  )
  inspect(next.active_session, content="desktop-restored")
  inspect(next.active().task, content="")
  assert_true(next.active().mentions.is_empty())
  assert_true(next.active().run is NoRun(ended=None))
  inspect(next.active().pending_steers.length(), content="0")
}

///|
test "an archive notification wins over a stale live-list reply" {
  let dispatch = test_dispatch()
  let item = placed_archived_item("desktop-test")
  let model = test_model().with_dev(dev => { ..dev, sessions: [item], })
  let (_, invalidated) = update_dev(
    dispatch,
    SessionsChanged(
      change="archived",
      key={
        session: "desktop-test",
        workspace: @interop.ChannelId::Local.test_project(),
      },
      fresh_session=Some("desktop-safe"),
    ),
    model,
  )
  let (_, stale) = update(
    dispatch,
    sessions_loaded([item], request_generation=1),
    invalidated,
  )
  assert_false(
    stale.dev().sessions.iter().any(current => current.id == item.id),
  )
  assert_true(stale.dev().archived.iter().any(current => current.id == item.id))
  inspect(stale.active_session, content="desktop-safe")
}

///|
test "a background archive removes only its channel's same-id conversation" {
  let dispatch = test_dispatch()
  let remote : @interop.ChannelId = Remote("d-remote")
  let local_conv = {
    ..empty_conversation(
      @interop.ChannelId::Local,
      "shared",
      @interop.ChannelId::Local.test_project(),
    ),
    messages: [{ kind: User("local"), ts: None, sequence: None, }],
  }
  let remote_conv = {
    ..empty_conversation(remote, "shared", remote.test_project()),
    messages: [{ kind: User("remote"), ts: None, sequence: None, }],
  }
  let model = {
    ..test_model(),
    devices: [
      { ..empty_device_state(@interop.ChannelId::Local), bridge: Connected, },
      { ..empty_device_state(remote), bridge: Connected, },
    ],
    active_session: "shared",
    conversations: [local_conv, remote_conv],
  }
  let (_, next) = update(
    dispatch,
    FromDevice(
      remote,
      ArchivedLoaded(
        [archived_item("shared", channel=remote)],
        connection_generation=0,
        request_generation=0,
        fresh_session="remote-fresh",
      ),
    ),
    model,
  )
  assert_true(next.focused is Local)
  inspect(next.active_session, content="shared")
  guard next.find_conversation(@interop.ChannelId::Local, "shared")
    is Some(kept) else {
    fail("the focused same-id conversation was removed")
  }
  assert_eq(kept.messages[0].text(), Some("local"))
  assert_true(next.find_conversation(remote, "shared") is None)
}

///|
test "an unarchive notification wins over a stale archived-list reply" {
  let dispatch = test_dispatch()
  let item = archived_item("desktop-old")
  let model = test_model().with_dev(dev => { ..dev, archived: [item], })
  let (_, restored) = update_dev(
    dispatch,
    SessionsChanged(
      change="unarchived",
      key={
        session: "desktop-old",
        workspace: @interop.ChannelId::Local.test_project(),
      },
      fresh_session=None,
    ),
    model,
  )
  let (_, stale) = update(
    dispatch,
    archived_loaded([item], request_generation=1),
    restored,
  )
  assert_false(
    stale.dev().archived.iter().any(current => current.id == item.id),
  )
  assert_true(stale.dev().sessions.iter().any(current => current.id == item.id))
}

///|
test "BridgeReady replaces archive overrides with fresh-list truth" {
  let dispatch = test_dispatch()
  let item = archived_item("desktop-old")
  let archived = {
    ..empty_conversation(
      @interop.ChannelId::Local,
      item.id,
      @interop.ChannelId::Local.test_project(),
    ),
    record: ArchivedRecord,
    messages: [
      {
        kind: Assistant(
          reasoning=None,
          prose=Some("cached archived answer"),
          calls=[],
          replay=false,
          finished=false,
        ),
        ts: None,
        sequence: Some(1),
      },
    ],
    watermark: 1,
  }
  let model = {
    ..test_model()
    .with_archive_override(
      @interop.ChannelId::Local,
      {
        session: "desktop-old",
        workspace: @interop.ChannelId::Local.test_project(),
      },
      ArchiveStored,
    )
    .with_dev(dev => { ..dev, archived: [item], })
    .replace_conversation(archived),
    active_session: item.id,
  }
  let (_, ready) = update_dev(dispatch, BridgeReady, model)
  inspect(ready.dev().connection_generation, content="1")
  inspect(ready.dev().archive_overrides.length(), content="0")
  let (_, live) = update_dev(
    dispatch,
    SessionsLoaded([item], connection_generation=1, request_generation=1),
    ready,
  )
  guard live.find_conversation(@interop.ChannelId::Local, item.id)
    is Some(restored) else {
    fail("the freshly live record disappeared during reconnect")
  }
  assert_true(restored.record is LiveRecord)
  assert_true(
    live
    .dev()
    .archive_override({ session: item.id, workspace: item.workspace, })
    is Some(ArchiveLive),
  )
  guard restored.sync is Reloading(generation=2, ..) else {
    fail("fresh live-list truth did not fence the archived reload")
  }
  let (_, stale_archived) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session=item.id,
      items=[
        {
          kind: Assistant(
            reasoning=None,
            prose=Some("late archived answer"),
            calls=[],
            replay=false,
            finished=false,
          ),
          ts: None,
          sequence: Some(1),
        },
      ],
      watermark=1,
      generation=1,
    ),
    live,
  )
  assert_true(stale_archived.active().record is LiveRecord)
  assert_eq(
    stale_archived.active().messages[0].text(),
    Some("cached archived answer"),
  )
  let (_, live_again) = update_dev(
    dispatch,
    SessionsLoaded([item], connection_generation=1, request_generation=1),
    ready,
  )
  guard live_again.find_conversation(@interop.ChannelId::Local, item.id)
    is Some(restored_again) else {
    fail("the repeated live-list update dropped the restored record")
  }
  assert_true(restored_again.record is LiveRecord)
  guard restored_again.sync is Reloading(generation=2, ..) else {
    fail("the reconnect transition was not idempotent")
  }
  let (_, reconciled) = update_dev(
    dispatch,
    ArchivedLoaded(
      [],
      connection_generation=1,
      request_generation=1,
      fresh_session="desktop-unused",
    ),
    stale_archived,
  )
  assert_true(
    reconciled.dev().sessions.iter().any(current => current.id == item.id),
  )
  inspect(reconciled.dev().archived.length(), content="0")
  let (_, stale) = update_dev(
    dispatch,
    ArchivedLoaded(
      [item],
      connection_generation=0,
      request_generation=1,
      fresh_session="desktop-stale",
    ),
    reconciled,
  )
  inspect(stale.dev().archived.length(), content="0")
}

///|
test "an older same-connection live list cannot replace a newer reply" {
  let dispatch = test_dispatch()
  let old : @transcript.SessionListItem = {
    id: "desktop-listed",
    title: Some("old title"),
    workspace: @interop.ChannelId::Local.test_project(),
    workspace_name: "",
    updated_at_ms: None,
  }
  let current = { ..old, title: Some("current title"), }
  let model = test_model().with_dev(dev => {
    ..dev,
    sessions_request_generation: 2,
  })
  let (_, newest) = update_dev(
    dispatch,
    SessionsLoaded([current], connection_generation=0, request_generation=2),
    model,
  )
  let (_, stale) = update_dev(
    dispatch,
    SessionsLoaded([old], connection_generation=0, request_generation=1),
    newest,
  )
  inspect(stale.dev().sessions.length(), content="1")
  assert_true(stale.dev().sessions[0].title is Some("current title"))
}

///|
test "an older same-connection archived list cannot replace a newer reply" {
  let dispatch = test_dispatch()
  let old : @transcript.SessionListItem = {
    id: "desktop-archived",
    title: Some("old title"),
    workspace: @interop.ChannelId::Local.test_project(),
    workspace_name: "",
    updated_at_ms: None,
  }
  let current = { ..old, title: Some("current title"), }
  let model = test_model().with_dev(dev => {
    ..dev,
    archived_request_generation: 2,
  })
  let (_, newest) = update_dev(
    dispatch,
    ArchivedLoaded(
      [current],
      connection_generation=0,
      request_generation=2,
      fresh_session="desktop-unused",
    ),
    model,
  )
  let (_, stale) = update_dev(
    dispatch,
    ArchivedLoaded(
      [old],
      connection_generation=0,
      request_generation=1,
      fresh_session="desktop-unused",
    ),
    newest,
  )
  inspect(stale.dev().archived.length(), content="1")
  assert_true(stale.dev().archived[0].title is Some("current title"))
}

///|
test "an archived background session drops its live state, active stays" {
  let dispatch = test_dispatch()
  let model = {
    ..test_model(),
    conversations: [
      test_conversation(),
      empty_conversation(
        @interop.ChannelId::Local,
        "desktop-old",
        @interop.ChannelId::Local.test_project(),
      ),
    ],
  }
  let (_, next) = update(
    dispatch,
    archived_loaded([archived_item("desktop-old")]),
    model,
  )
  inspect(next.dev().archived.length(), content="1")
  inspect(next.dev().archived[0].id, content="desktop-old")
  assert_true(
    next.find_conversation(@interop.ChannelId::Local, "desktop-old") is None,
  )
  inspect(next.active_session, content="desktop-test")
}

///|
test "an archived-list reply immediately replaces the active conversation" {
  let dispatch = test_dispatch()
  let (_, next) = update(
    dispatch,
    archived_loaded([placed_archived_item("desktop-test")]),
    test_model(),
  )
  assert_true(
    next.find_conversation(@interop.ChannelId::Local, "desktop-test") is None,
  )
  inspect(next.active_session, content="desktop-archive-replacement")
  inspect(next.dev().archived[0].id, content="desktop-test")
}

///|
test "an archive failure pops a toast that a click or its timer dismisses" {
  let dispatch = test_dispatch()
  let (_, failed) = update_dev(
    dispatch,
    ArchiveFailed("zip missing"),
    test_model(),
  )
  inspect(failed.notifications.length(), content="1")
  inspect(
    failed.notifications[0].message,
    content="Archive failed: zip missing",
  )
  let id = failed.notifications[0].id
  // A stale timer (the toast is already gone) must not touch a later toast.
  let (_, dismissed) = update(dispatch, DismissNotification(id), failed)
  inspect(dismissed.notifications.length(), content="0")
  let (_, again) = update_dev(
    dispatch,
    ArchiveFailed("still missing"),
    dismissed,
  )
  let (_, expired) = update(dispatch, NotificationExpired(id), again)
  inspect(expired.notifications.length(), content="1")
  inspect(
    expired.notifications[0].message,
    content="Archive failed: still missing",
  )
}

///|
test "toast ids only ever grow, so timers and toasts stay paired" {
  let dispatch = test_dispatch()
  let (_, first) = update_dev(dispatch, ArchiveFailed("one"), test_model())
  let (_, second) = update_dev(dispatch, SessionsFailed("two"), first)
  inspect(second.notifications.length(), content="2")
  assert_true(second.notifications[0].id != second.notifications[1].id)
  inspect(second.notification_seq, content="2")
}

///|
test "the color-scheme watcher only changes a system-following theme" {
  let dispatch = test_dispatch()
  let system = { ..test_model(), theme: System, system_dark: false, }
  let (_, dark) = update(dispatch, ColorSchemeChanged(true), system)
  assert_true(dark.theme is System)
  assert_true(dark.system_dark)
  let fixed = { ..dark, theme: Light, }
  let (_, changed_host) = update(dispatch, ColorSchemeChanged(false), fixed)
  assert_true(changed_host.theme is Light)
  assert_false(changed_host.system_dark)
}

///|
test "theme settings switch fixed palettes and are idempotent" {
  let dispatch = test_dispatch()
  let system = { ..test_model(), theme: System, system_dark: true, }
  let (_, first) = update(dispatch, ThemeChanged("dark"), system)
  let (_, repeated) = update(dispatch, ThemeChanged("dark"), first)
  assert_true(first.theme is Dark)
  assert_true(repeated.theme is Dark)
  assert_true(first.system_dark && repeated.system_dark)
  let (_, following) = update(dispatch, ThemeChanged("system"), first)
  assert_true(following.theme is System)
  assert_true(following.system_dark)
  let (_, light) = update(dispatch, ThemeChanged("light"), first)
  assert_true(light.theme is Light)
  let (_, unchanged) = update(dispatch, ThemeChanged("unknown"), system)
  assert_true(unchanged.theme is System)
}

///|
test "monospace settings switch code surfaces and are idempotent" {
  let dispatch = test_dispatch()
  let model = test_model()
  let (_, first) = update(dispatch, FontChanged("geist-mono"), model)
  let (_, second) = update(dispatch, FontChanged("geist-mono"), first)
  assert_true(first.app_font is GeistMono)
  assert_true(second.app_font is GeistMono)
  let (_, system) = update(dispatch, FontChanged("system-mono"), first)
  assert_true(system.app_font is SystemMono)
  let (_, menlo) = update(dispatch, FontChanged("menlo"), system)
  assert_true(menlo.app_font is Menlo)
  let (_, bundled) = update(dispatch, FontChanged("geist-mono"), menlo)
  assert_true(bundled.app_font is GeistMono)
  let (_, unchanged) = update(dispatch, FontChanged("unknown"), model)
  assert_true(unchanged.app_font is SystemMono)
}

///|
test "font-size settings switch every text surface and are idempotent" {
  assert_eq(AppFontSize(12).pixels(), 11.0)
  assert_eq(AppFontSize(14).pixels(), 13.0)
  assert_eq(AppFontSize(18).pixels(), 17.0)
  let dispatch = test_dispatch()
  let model = test_model()
  let (_, first) = update(dispatch, FontSizeChanged("15"), model)
  let (_, second) = update(dispatch, FontSizeChanged("15"), first)
  assert_eq(first.app_font_size, AppFontSize(15))
  assert_eq(second.app_font_size, AppFontSize(15))
  assert_eq(first.app_font_size.pixels(), 14.0)
  let (_, largest) = update(dispatch, FontSizeChanged("18"), first)
  assert_eq(largest.app_font_size, AppFontSize(18))
  assert_eq(largest.app_font_size.pixels(), 17.0)
  let (_, unchanged) = update(dispatch, FontSizeChanged("unknown"), model)
  assert_eq(unchanged.app_font_size, AppFontSize(14))
}

///|
test "selecting a conversation returns from the skills page to the chat" {
  let dispatch = test_dispatch()
  let (_, opened) = update(dispatch, OpenSkills, test_model())
  assert_true(opened.screen is Skills)

  // Re-selecting the active conversation is enough to switch back…
  let (_, back) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-test"),
    opened,
  )
  assert_true(back.screen is Chat)

  // …and so is rotating to a fresh one.
  let (_, rotated) = update(
    dispatch,
    SessionRotated({ channel: Local, session: "desktop-fresh", }),
    opened,
  )
  assert_true(rotated.screen is Chat)
}

///|
test "Codex sidebar selection uses the main conversation screen" {
  let dispatch = test_dispatch()
  let codex = @codex.State::from_thread_snapshot({
    "thread": {
      "id": "codex-thread-1",
      "preview": "Shared sidebar",
      "cwd": "/work/codex-project",
      "turns": [],
    },
  })
  let wide = { ..test_model(), codex, sidebar_open: true, }
  let (_, opened) = update(dispatch, CodexOpenThread("codex-thread-1"), wide)
  assert_true(opened.screen is Codex)
  assert_true(opened.sidebar_open)
  assert_true(opened.codex.active_id() is Some("codex-thread-1"))
  assert_true(
    opened.file_panel.owner
    is Some({ channel: Local, session: "codex-thread-1", }),
  )
  let workspace = @interop.ChannelId::Local.test_resource("/work/codex-project")
  guard opened.active_checkout() is Some(active) else {
    fail("selected Codex task did not project an active checkout")
  }
  assert_eq(active.owner, {
    channel: @interop.ChannelId::Local,
    session: "codex-thread-1",
  })
  assert_eq(
    active.placement.bind(value => value.checkout_root()),
    Some(workspace),
  )
  assert_true(opened.conversation_root(opened.active()) != Some(workspace))
  assert_true(file_ctx(opened).placement is Some(@interop.WorkspaceRoot(..)))
  assert_eq(
    file_ctx(opened).placement.bind(value => value.checkout_root()),
    Some(workspace),
  )
  let opened_terminal = terminal_ctx(opened)
  inspect(opened_terminal.session, content="codex-thread-1")
  assert_true(opened_terminal.placement is Some(@interop.WorkspaceRoot(..)))
  assert_eq(
    opened_terminal.placement.bind(value => value.checkout_root()),
    Some(workspace),
  )
  assert_true(opened_terminal.connected)

  // The same input and model produce the same state; the bridge call remains
  // an opaque Cmd and is not executed inside the reducer.
  let (_, opened_again) = update(
    dispatch,
    CodexOpenThread("codex-thread-1"),
    wide,
  )
  assert_true(opened_again.screen is Codex)
  assert_true(opened_again.sidebar_open)
  assert_true(opened_again.codex.active_id() is Some("codex-thread-1"))
  assert_true(
    opened_again.file_panel.owner
    is Some({ channel: Local, session: "codex-thread-1", }),
  )
}

///|
test "Codex events from a background device cannot mutate the focused host" {
  let dispatch = test_dispatch()
  let model = test_model()
  let (_, next) = update(
    dispatch,
    Codex(
      channel=@interop.ChannelId::Remote("background"),
      @codex.Msg::status_changed({ "status": "ready" }),
    ),
    model,
  )
  assert_true(next.codex == model.codex)
  assert_eq(next.focused, model.focused)
}

///|
test "cwd-less Codex tasks keep Files unavailable and use scratch Terminal" {
  let codex = @codex.State::from_thread_snapshot({
    "thread": { "id": "codex-scratch-1", "preview": "No cwd yet", "turns": [] },
  })
  let model = { ..test_model(), codex, screen: Codex, }
  let files = file_ctx(model)
  inspect(files.owner.session, content="codex-scratch-1")
  assert_true(files.placement is None)

  // The owner remains stable for async fencing. Terminal identifies the
  // host-lazy scratch group by task id without inventing a Files directory.
  let terminal = terminal_ctx(model)
  inspect(terminal.session, content="codex-scratch-1")
  assert_true(terminal.placement is Some(@interop.Scratch(root=None)))
  assert_true(terminal.connected)
}

///|
test "Codex sidebar actions close only the narrow drawer" {
  let dispatch = test_dispatch()
  let narrow = {
    ..test_model(),
    narrow: true,
    sidebar_open: true,
    screen: Chat,
  }
  let (_, opened) = update(dispatch, OpenCodex, narrow)
  assert_true(opened.screen is Codex)
  assert_false(opened.sidebar_open)

  // A "New chat" while Codex is the default agent routes there too — and
  // still closes only the narrow drawer.
  let (_, ready) = update(
    dispatch,
    Codex(
      channel=narrow.focused,
      @codex.Msg::status_changed({ "status": "ready" }),
    ),
    { ..narrow, default_agent: CodexAgent, },
  )
  let (_, creating) = update(dispatch, NewChat, ready)
  assert_true(creating.screen is Codex)
  assert_false(creating.sidebar_open)

  // Archiving from the shared sidebar acts on that row without changing the
  // OpenSeek conversation currently occupying the main pane.
  let (_, archiving) = update(
    dispatch,
    CodexArchiveThread("codex-thread-1"),
    narrow,
  )
  assert_true(archiving.screen is Chat)
}

///|
test "an unreadable library becomes the focused page's notice" {
  let dispatch = test_dispatch()
  let home = test_model()
  // Both devices are known, so a background reply reaches the handler proper
  // instead of being dropped for want of a device state.
  let paired = {
    ..home,
    devices: [
      home.devices[0],
      { ..empty_device_state(Remote("d_b")), bridge: Connected, },
    ],
  }
  let (_, noticed) = update(
    dispatch,
    FromDevice(Local, InstalledSkillsFailed("library unreadable")),
    paired,
  )
  assert_true(noticed.skills == paired.skills.with_notice("library unreadable"))

  // The page is the focused host's; a background device says nothing on it.
  let (_, quiet) = update(
    dispatch,
    FromDevice(Remote("d_b"), InstalledSkillsFailed("other host")),
    noticed,
  )
  assert_true(quiet.skills == noticed.skills)
}

///|
test "installed skills replies are scoped to their source device" {
  let dispatch = test_dispatch()
  let home = test_model()
  let focused = {
    ..home,
    devices: [
      home.devices[0],
      { ..empty_device_state(Remote("d_b")), bridge: Connected, },
    ],
    focused: Remote("d_b"),
    installed_skills: [],
  }
  let old_host : Array[@skills.InstalledItem] = [
    { id: "old", name: "old", description: "", source: "old/source@1.0.0", },
  ]
  let (_, ignored) = update(
    dispatch,
    FromDevice(Local, InstalledSkillsLoaded(old_host)),
    focused,
  )
  assert_eq(ignored.installed_skills.length(), 0)
  let new_host : Array[@skills.InstalledItem] = [
    { id: "new", name: "new", description: "", source: "new/source@1.0.0", },
  ]
  let (_, applied) = update(
    dispatch,
    FromDevice(Remote("d_b"), InstalledSkillsLoaded(new_host)),
    ignored,
  )
  assert_eq(applied.installed_skills.length(), 1)
  assert_eq(applied.installed_skills[0].id, "new")
}

///|
test "file editor context reports the file body actual visibility" {
  let model = test_model()
  let path = @pathx.Relative("src/main.mbt")
  let file_model = {
    ..model,
    right_panel_open: true,
    dock: { ..model.dock, tabs: [File(path~)], active: Some(File(path~)), },
  }
  assert_true(file_ctx(file_model).panel_open)
  assert_false(file_ctx({ ..file_model, right_panel_open: false, }).panel_open)
  let picker_model = {
    ..file_model,
    dock: { ..file_model.dock, tabs: [FilePicker], active: Some(FilePicker), },
  }
  assert_true(file_ctx(picker_model).panel_open)
  let browser_model = {
    ..file_model,
    dock: {
      ..file_model.dock,
      tabs: [Browser(id=1)],
      active: Some(Browser(id=1)),
    },
  }
  assert_false(file_ctx(browser_model).panel_open)
  let launcher_model = {
    ..file_model,
    dock: { ..file_model.dock, tabs: [], active: None, },
  }
  assert_false(file_ctx(launcher_model).panel_open)
  assert_false(file_ctx({ ..file_model, screen: Skills, }).panel_open)
  assert_false(file_ctx({ ..file_model, screen: Settings, }).panel_open)
}

///|
test "only synchronous file-open messages suppress panel reactivation" {
  let owner : @interop.ConversationKey = {
    channel: Local,
    session: "desktop-test",
  }
  let identity : ComposerActionIdentity = { owner, archive_generation: 0, }
  assert_true(JumpToMention(0).opens_file_before_panel_reconciliation())
  assert_true(
    ComposerAction(
      @composer.MentionOpened(identity~, mention={
        ref_: File(path="a.mbt"),
        range: None,
      }),
    ).opens_file_before_panel_reconciliation(),
  )
  assert_true(
    CodexComposerAction(
      @composer.MentionOpened(identity~, mention={
        ref_: File(path="a.mbt"),
        range: None,
      }),
    ).opens_file_before_panel_reconciliation(),
  )
  assert_true(
    JumpToLocation(path="a.mbt", range=None, annotation=None).opens_file_before_panel_reconciliation(),
  )
  assert_true(
    QuickOpen(@quick_open.Pick(0)).opens_file_before_panel_reconciliation(),
  )
  assert_true(
    OpenFileAt(owner~, generation=1, path="a.mbt", line=Some(1), column=None).opens_file_before_panel_reconciliation(),
  )
  // This only starts the asynchronous host lookup. The later OpenFileAt is
  // the message that actually opens the document.
  assert_false(OpenFile("a.mbt").opens_file_before_panel_reconciliation())
  assert_false(ToggleRightPanel.opens_file_before_panel_reconciliation())
}

///|
test "JumpToMention opens the editor panel and selects the mention's file" {
  let dispatch = test_dispatch()
  let mention : Mention = {
    ref_: Symbol(name="parse_hover", file="src/main.mbt", line=5),
    range: Some(@common.Range(5, 1, 5, 12)),
  }
  let model = test_model().replace_conversation({
    ..test_conversation(),
    mentions: [mention],
  })
  let (_, next) = update(dispatch, JumpToMention(0), model)
  assert_true(next.right_panel_open)
  assert_true(@dock.active_file(next.dock) is Some(Relative("src/main.mbt")))
  assert_eq(next.file_panel.file_link_generation, 1)
  // The document table follows the strip: the jumped-to file has an entry.
  assert_true(next.file_panel.docs.contains(Relative("src/main.mbt")))
}

///|
test "resolved transcript files and directories stay in the right panel" {
  let dispatch = test_dispatch()
  let model = test_model()
  let owner : @interop.ConversationKey = {
    channel: Local,
    session: "desktop-test",
  }
  let (_, file_pending) = update(dispatch, OpenFile("src/main.mbt"), model)
  let (_, file) = update(
    dispatch,
    OpenFileAt(
      owner~,
      generation=1,
      path="src/main.mbt",
      line=None,
      column=None,
    ),
    file_pending,
  )
  assert_true(file.right_panel_open)
  assert_true(@dock.active_file(file.dock) is Some(Relative("src/main.mbt")))

  let (_, directory_pending) = update(dispatch, OpenFile("src"), model)
  let directory_msg = OpenDirectoryAt(owner~, generation=1, path="src")
  let (_, directory) = update(dispatch, directory_msg, directory_pending)
  assert_true(directory.right_panel_open)
  assert_true(directory.dock.active is Some(FilePicker))
  assert_true(directory.file_panel.tree_open)
  assert_true(directory.file_panel.highlighted is Some(Relative("src")))
  assert_true(directory.file_panel.expanded.contains(Relative("src")))
  // Repeating the same link is a reveal, not the row's collapse toggle.
  let (_, repeated) = update(dispatch, directory_msg, directory)
  assert_true(repeated.file_panel.expanded.contains(Relative("src")))
}

///|
test "update is pure: a resolved transcript position opens its owning file" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/work/project")
  let worktree = @interop.ChannelId::Local.test_resource(
    "/work/project/.worktrees/wt-4",
  )
  let model = test_model()
    .replace_conversation({
      ..test_conversation(),
      workspace: Worktree(project=workspace, name="wt-4"),
    })
    .with_dev(dev => {
      ..dev,
      projects: [workspace],
      worktrees: [
        {
          project: workspace,
          rows: [
            {
              name: "wt-4",
              session: Some("desktop-test"),
              codex_thread: None,
              path: Some(worktree),
              present: true,
            },
          ],
          generation: 1,
        },
      ],
    })
  let owner : @interop.ConversationKey = {
    channel: @interop.ChannelId::Local,
    session: "desktop-test",
  }
  // Spending the generation is part of the pure click transition, before the
  // host command runs. Replaying the same input therefore produces the same
  // token rather than consulting hidden state.
  let (_, first_pending) = update(dispatch, OpenFile("src/main.mbt:1"), model)
  let (_, replayed_pending) = update(
    dispatch,
    OpenFile("src/main.mbt:1"),
    model,
  )
  assert_eq(first_pending.file_panel.file_link_generation, 1)
  assert_eq(replayed_pending.file_panel.file_link_generation, 1)
  let (_, latest_pending) = update(
    dispatch,
    OpenFile("src/main.mbt:2738:17"),
    first_pending,
  )
  assert_eq(latest_pending.file_panel.file_link_generation, 2)
  // Routing is asynchronous: a path that later goes to the system must not
  // open an empty panel while the host is still classifying it.
  assert_false(latest_pending.right_panel_open)
  // The panel may already be showing another document while this host lookup
  // is pending. Closing that open panel is a newer user decision; its delayed
  // reply cannot reopen the panel.
  let panel_open_pending = { ..latest_pending, right_panel_open: true, }
  let (_, panel_closed) = update(dispatch, ToggleRightPanel, panel_open_pending)
  assert_false(panel_closed.right_panel_open)
  assert_eq(panel_closed.file_panel.file_link_generation, 3)
  let (_, after_closed_reply) = update(
    dispatch,
    OpenFileAt(
      owner~,
      generation=2,
      path="src/main.mbt",
      line=Some(2738),
      column=Some(17),
    ),
    panel_closed,
  )
  assert_false(after_closed_reply.right_panel_open)
  assert_true(after_closed_reply.dock.active is None)
  // Revealing an existing tab is also a newer dock navigation. The pending
  // reply cannot replace the file the user chose to bring back on screen.
  let hidden_pending = {
    ..latest_pending,
    dock: @dock.open_file(latest_pending.dock, Relative("README.md")),
    right_panel_open: false,
  }
  let (_, panel_opened) = update(dispatch, ToggleRightPanel, hidden_pending)
  assert_true(panel_opened.right_panel_open)
  assert_eq(panel_opened.file_panel.file_link_generation, 3)
  assert_true(
    @dock.active_file(panel_opened.dock) is Some(Relative("README.md")),
  )
  let (_, after_opened_reply) = update(
    dispatch,
    OpenFileAt(
      owner~,
      generation=2,
      path="src/main.mbt",
      line=Some(2738),
      column=Some(17),
    ),
    panel_opened,
  )
  assert_true(
    @dock.active_file(after_opened_reply.dock) is Some(Relative("README.md")),
  )
  assert_false(
    after_opened_reply.dock.tabs.contains(
      @dock.DockTab::File(path=Relative("src/main.mbt")),
    ),
  )
  // The first host reply is stale as soon as the second click happens.
  let (_, old_host_reply) = update(
    dispatch,
    OpenFileAt(
      owner~,
      generation=1,
      path="src/main.mbt",
      line=Some(1),
      column=None,
    ),
    latest_pending,
  )
  assert_true(old_host_reply.dock.active is None)
  let msg = OpenFileAt(
    owner~,
    generation=2,
    path="src/main.mbt",
    line=Some(2738),
    column=Some(17),
  )
  let (_, first) = update(dispatch, msg, latest_pending)
  let (_, second) = update(dispatch, msg, latest_pending)
  assert_true(@dock.active_file(first.dock) is Some(Relative("src/main.mbt")))
  assert_true(first.right_panel_open)
  assert_true(@dock.active_file(second.dock) is Some(Relative("src/main.mbt")))
  assert_true(first.file_panel.docs.contains(Relative("src/main.mbt")))
  assert_true(second.file_panel.docs.contains(Relative("src/main.mbt")))
  let target = @resource.join_relative(worktree, Relative("src/main.mbt"))
  // A later ordinary navigation of the same loading file owns its read with
  // the same generation token. If that newer read fails first, the older
  // positioned success cannot fill the failed tab afterward.
  let (_, ordinary_pending) = update(
    dispatch,
    FileEditor(
      @fileeditor.OpenNavigationLocation(
        owner~,
        path=Relative("src/main.mbt"),
        range=@common.Range(9, 1, 9, 4),
      ),
    ),
    first,
  )
  assert_eq(ordinary_pending.file_panel.file_link_generation, 3)
  let (_, ordinary_failed) = update(
    dispatch,
    FileEditor(
      @fileeditor.FileFailed(
        owner~,
        epoch=ordinary_pending.file_panel.request_epoch,
        path=Relative("src/main.mbt"),
        file_link_generation=Some(3),
        review_generation=None,
        message="newer ordinary read failed",
      ),
    ),
    ordinary_pending,
  )
  assert_true(
    ordinary_failed.file_panel.docs.get(Relative("src/main.mbt"))
    is Some(
      { state: @fileeditor.TabReadFailed("newer ordinary read failed"), .. }
    ),
  )
  let (_, old_after_failure) = update(
    dispatch,
    FileEditor(
      @fileeditor.FileLoaded(
        owner~,
        epoch=ordinary_failed.file_panel.request_epoch,
        path=Relative("src/main.mbt"),
        name="main.mbt",
        file=@fileeditor.Content(content="old", absolute=target, sig="1:3"),
        file_link_generation=Some(2),
        review_generation=None,
        range=Some(@common.Range(2738, 17, 2738, 17)),
        annotation=None,
      ),
    ),
    ordinary_failed,
  )
  assert_true(old_after_failure == ordinary_failed)
  // Both host replies can arrive in click order while the corresponding file
  // reads settle in reverse. The older read may finish the loading document,
  // but it cannot move the Viewer back to its stale position.
  let (_, old_file_reply) = update(
    dispatch,
    FileEditor(
      @fileeditor.FileLoaded(
        owner~,
        epoch=first.file_panel.request_epoch,
        path=Relative("src/main.mbt"),
        name="main.mbt",
        file=@fileeditor.Content(content="old", absolute=target, sig="1:3"),
        file_link_generation=Some(1),
        review_generation=None,
        range=Some(@common.Range(1, 1, 1, 1)),
        annotation=None,
      ),
    ),
    first,
  )
  assert_true(
    old_file_reply.file_panel.docs.get(Relative("src/main.mbt"))
    is Some({ state: @fileeditor.TabLoaded(content="old", ..), .. }),
  )
  // A stale failure likewise makes its loading tab retryable without raising
  // a panel-wide error or applying the old position.
  let (_, old_file_failure) = update(
    dispatch,
    FileEditor(
      @fileeditor.FileFailed(
        owner~,
        epoch=first.file_panel.request_epoch,
        path=Relative("src/main.mbt"),
        file_link_generation=Some(1),
        review_generation=None,
        message="old read failed",
      ),
    ),
    first,
  )
  assert_true(old_file_failure.file_panel.error is None)
  assert_true(
    old_file_failure.file_panel.docs.get(Relative("src/main.mbt"))
    is Some({ state: @fileeditor.TabReadFailed("old read failed"), .. }),
  )
  // The current failure is authoritative even if the stale success filled the
  // cache first, so the superseded snapshot cannot survive the failed read.
  let (_, current_file_failure) = update(
    dispatch,
    FileEditor(
      @fileeditor.FileFailed(
        owner~,
        epoch=first.file_panel.request_epoch,
        path=Relative("src/main.mbt"),
        file_link_generation=Some(2),
        review_generation=None,
        message="current read failed",
      ),
    ),
    old_file_reply,
  )
  assert_true(current_file_failure.file_panel.error is None)
  assert_true(
    current_file_failure.file_panel.docs.get(Relative("src/main.mbt"))
    is Some({ state: @fileeditor.TabReadFailed("current read failed"), .. }),
  )
  let (_, current_file_reply) = update(
    dispatch,
    FileEditor(
      @fileeditor.FileLoaded(
        owner~,
        epoch=first.file_panel.request_epoch,
        path=Relative("src/main.mbt"),
        name="main.mbt",
        file=@fileeditor.Content(content="new", absolute=target, sig="2:3"),
        file_link_generation=Some(2),
        review_generation=None,
        range=Some(@common.Range(2738, 17, 2738, 17)),
        annotation=None,
      ),
    ),
    old_file_reply,
  )
  assert_true(
    current_file_reply.file_panel.docs.get(Relative("src/main.mbt"))
    is Some({ state: @fileeditor.TabLoaded(content="new", ..), .. }),
  )
  // Closing an inactive file tab is also newer than a pending positioned
  // link to that file. Its delayed host reply must not recreate the tab.
  let (_, other_file) = update(
    dispatch,
    FileEditor(FileSelected(path=Relative("README.md"), name="README.md")),
    current_file_reply,
  )
  assert_true(@dock.active_file(other_file.dock) is Some(Relative("README.md")))
  let (_, inactive_pending) = update(
    dispatch,
    OpenFile("src/main.mbt:40"),
    other_file,
  )
  let pending_generation = inactive_pending.file_panel.file_link_generation
  let (_, inactive_closed) = update(
    dispatch,
    Dock(TabClosed(@dock.DockTab::File(path=Relative("src/main.mbt")))),
    inactive_pending,
  )
  assert_eq(
    inactive_closed.file_panel.file_link_generation,
    pending_generation + 1,
  )
  assert_false(
    inactive_closed.dock.tabs.contains(
      @dock.DockTab::File(path=Relative("src/main.mbt")),
    ),
  )
  let (_, after_inactive_reply) = update(
    dispatch,
    OpenFileAt(
      owner~,
      generation=pending_generation,
      path="src/main.mbt",
      line=Some(40),
      column=None,
    ),
    inactive_closed,
  )
  assert_false(
    after_inactive_reply.dock.tabs.contains(
      @dock.DockTab::File(path=Relative("src/main.mbt")),
    ),
  )
  // A later tree pick competes with the transcript request just like a newer
  // transcript click: it advances the same token before opening its document.
  let (_, tree_opened) = update(
    dispatch,
    FileEditor(FileSelected(path=Relative("README.md"), name="README.md")),
    latest_pending,
  )
  assert_eq(tree_opened.file_panel.file_link_generation, 3)
  let (_, delayed_transcript_reply) = update(
    dispatch,
    OpenFileAt(
      owner~,
      generation=2,
      path="src/main.mbt",
      line=Some(2738),
      column=Some(17),
    ),
    tree_opened,
  )
  assert_true(
    @dock.active_file(delayed_transcript_reply.dock)
    is Some(Relative("README.md")),
  )
  assert_false(
    delayed_transcript_reply.file_panel.docs.contains(Relative("src/main.mbt")),
  )
  // A delayed reply from another conversation cannot open a tab here.
  let (_, stale) = update(
    dispatch,
    OpenFileAt(
      owner={ ..owner, session: "another-session", },
      generation=2,
      path="/work/project/src/main.mbt",
      line=Some(1),
      column=None,
    ),
    latest_pending,
  )
  assert_true(stale.dock.active is None)
  assert_false(stale.file_panel.docs.contains(Relative("src/main.mbt")))
}

///|
test "JumpToMention is a no-op for a chip without a resolved location" {
  let dispatch = test_dispatch()
  let mention : Mention = { ref_: Skill(name="review-pr"), range: None, }
  let model = test_model().replace_conversation({
    ..test_conversation(),
    mentions: [mention],
  })
  let (_, next) = update(dispatch, JumpToMention(0), model)
  assert_false(next.right_panel_open)
  assert_true(next.dock.active is None)
}

///|
test "EditorCommentAdded attaches a deduplicated annotation chip" {
  let dispatch = test_dispatch()
  let model = test_model()
  let absolute = @interop.ChannelId::Local.test_resource(
    "/work/project/src/main.mbt",
  )
  // The chip path arrives workspace-relative from the panel (recorded when
  // the file was shown); the resource URI only routes the bubble removal.
  let msg : Msg = FileEditor(
    EditorCommentAdded(
      resource=@fileeditor.ModelUri::of(absolute),
      file=Relative("src/main.mbt"),
      range=@common.Range(5, 1, 6, 3),
      quote="fn parse_hover() {",
      comment="rename this",
      feedback_id="viewer-feedback-0",
    ),
  )
  let (_, next) = update(dispatch, msg, model)
  let mentions = next.active().mentions
  assert_eq(mentions.length(), 1)
  assert_true(
    mentions[0].ref_
    is Annotation(file="src/main.mbt", start_line=5, end_line=6, ..),
  )
  // Submitting the identical comment again is a no-op, not a second chip.
  let (_, again) = update(dispatch, msg, next)
  assert_eq(again.active().mentions.length(), 1)
}

///|
test "ApplyAllFeedback queues the attached annotation on a running task" {
  let dispatch = test_dispatch()
  let model = running_model()
  let (_, batched) = update(
    dispatch,
    FileEditor(
      EditorCommentAdded(
        resource=@fileeditor.ModelUri::of(
          @interop.ChannelId::Local.test_resource("/work/project/src/main.mbt"),
        ),
        file=Relative("src/main.mbt"),
        range=@common.Range(5, 1, 6, 3),
        quote="fn parse_hover() {",
        comment="rename this",
        feedback_id="viewer-feedback-immediate",
      ),
    ),
    model,
  )
  assert_eq(batched.active().mentions.length(), 1)
  let (_, applied) = update(
    dispatch,
    FileEditor(@fileeditor.ApplyAllFeedback),
    batched,
  )
  assert_true(applied.active().mentions.is_empty())
  assert_eq(applied.active().pending_steers.length(), 1)
  let steer = applied.active().pending_steers[0]
  assert_eq(steer.mentions.length(), 1)
  assert_true(steer.content.contains("<user_mentions>"))
  assert_true(steer.content.contains("rename this"))
}

///|
test "DiffCommentAdded preserves modified and original-only line identity" {
  let dispatch = test_dispatch()
  let file = @pathx.Relative("src/main.mbt")
  let added : Msg = FileEditor(
    DiffCommentAdded(
      file~,
      original_line_number=None,
      modified_line_number=Some(7),
      quote="let answer = 42",
      comment="name this constant",
      resource=None,
      feedback_id=None,
    ),
  )
  let (_, with_added) = update(dispatch, added, test_model())
  let added_mentions = with_added.active().mentions
  assert_eq(added_mentions.length(), 1)
  assert_true(
    added_mentions[0].ref_
    is Annotation(
      file="src/main.mbt",
      start_line=7,
      end_line=7,
      quote="let answer = 42",
      comment="name this constant",
      side=@mention_context.WorkingRevision
    ),
  )
  assert_eq(added_mentions[0].range, Some(@common.Range(7, 1, 7, 16)))
  let deleted : Msg = FileEditor(
    DiffCommentAdded(
      file~,
      original_line_number=Some(3),
      modified_line_number=None,
      quote="obsolete()",
      comment="good removal",
      resource=None,
      feedback_id=None,
    ),
  )
  let (_, with_deleted) = update(dispatch, deleted, with_added)
  let deleted_mentions = with_deleted.active().mentions
  assert_eq(deleted_mentions.length(), 2)
  assert_true(
    deleted_mentions[1].ref_
    is Annotation(
      file="src/main.mbt",
      start_line=3,
      end_line=3,
      quote="obsolete()",
      comment="good removal",
      side=@mention_context.OriginalRevision
    ),
  )
  assert_eq(deleted_mentions[1].range, None)
}

///|
test "Codex original-side diff feedback queues in the Codex draft" {
  let dispatch = test_dispatch()
  let codex = @codex.State::from_thread_snapshot({
    "thread": {
      "id": "codex-thread-original-feedback",
      "cwd": "/work/project",
      "preview": "Review",
      "turns": [
        { "id": "codex-turn-original", "status": "inProgress", "items": [] },
      ],
    },
  })
  let model = { ..test_model(), codex, screen: Codex, }
  let (_, batched) = update(
    dispatch,
    FileEditor(
      DiffCommentAdded(
        file=Relative("src/main.mbt"),
        original_line_number=Some(3),
        modified_line_number=None,
        quote="obsolete()",
        comment="keep this removal",
        resource=None,
        feedback_id=None,
      ),
    ),
    model,
  )
  assert_true(batched.active().mentions.is_empty())
  let draft = batched.codex_composer_input().draft
  assert_eq(draft.mentions.length(), 1)
  assert_true(
    draft.mentions[0].ref_
    is Annotation(
      file="src/main.mbt",
      start_line=3,
      end_line=3,
      quote="obsolete()",
      comment="keep this removal",
      side=@mention_context.OriginalRevision
    ),
  )
  assert_eq(draft.mentions[0].range, None)
  let (_, applied) = update(
    dispatch,
    FileEditor(@fileeditor.ApplyAllFeedback),
    batched,
  )
  let queued = applied.codex.transcript_items()
  assert_eq(queued.length(), 1)
  guard queued[0].kind is @transcript.User(prompt) else {
    fail("expected the queued feedback as a user prompt")
  }
  assert_true(prompt.contains("side=\"original\""))
  assert_true(prompt.contains("keep this removal"))
}

///|
test "original-revision diff comment chip does not navigate into the working file" {
  let dispatch = test_dispatch()
  let original_comment : Mention = {
    ref_: Annotation(
      file="src/main.mbt",
      start_line=3,
      end_line=3,
      quote="obsolete()",
      comment="good removal",
      side=@mention_context.OriginalRevision,
    ),
    range: None,
  }
  let model = test_model().replace_conversation({
    ..test_conversation(),
    mentions: [original_comment],
  })
  let (_, next) = update(dispatch, JumpToMention(0), model)
  assert_false(next.right_panel_open)
  assert_true(next.dock.active is None)
}

///|
test "Codex editor comments use annotation context, not textarea text or OpenSeek chat" {
  let dispatch = test_dispatch()
  let codex = @codex.State::from_thread_snapshot({
    "thread": {
      "id": "codex-thread-1",
      "cwd": "/work/project",
      "preview": "Review",
      "turns": [],
    },
  })
  let model = { ..test_model(), codex, screen: Codex, }
  let msg : Msg = FileEditor(
    EditorCommentAdded(
      resource=@fileeditor.ModelUri::of(
        @interop.ChannelId::Local.test_resource("/work/project/src/main.mbt"),
      ),
      file=Relative("src/main.mbt"),
      range=@common.Range(5, 1, 6, 3),
      quote="fn parse_hover() {",
      comment="rename this",
      feedback_id="viewer-feedback-codex",
    ),
  )
  let (_, once) = update(dispatch, msg, model)
  let (_, twice) = update(dispatch, msg, model)
  assert_true(once.active().mentions.is_empty())
  assert_true(twice.active().mentions.is_empty())
  assert_eq(once.codex.draft_text(), twice.codex.draft_text())
  // The textarea stays untouched. Codex owns the annotation chip and sends
  // its file/range/comment/quote through the shared mention envelope.
  assert_eq(once.codex.draft_text(), "")
}

///|
test "Codex ApplyAllFeedback steers the running task through its composer" {
  let dispatch = test_dispatch()
  let codex = @codex.State::from_thread_snapshot({
    "thread": {
      "id": "codex-thread-feedback",
      "cwd": "/work/project",
      "preview": "Review",
      "turns": [
        { "id": "codex-turn-feedback", "status": "inProgress", "items": [] },
      ],
    },
  })
  let model = { ..test_model(), codex, screen: Codex, }
  let (_, batched) = update(
    dispatch,
    FileEditor(
      EditorCommentAdded(
        resource=@fileeditor.ModelUri::of(
          @interop.ChannelId::Local.test_resource("/work/project/src/main.mbt"),
        ),
        file=Relative("src/main.mbt"),
        range=@common.Range(5, 1, 6, 3),
        quote="fn parse_hover() {",
        comment="rename this",
        feedback_id="viewer-feedback-codex-immediate",
      ),
    ),
    model,
  )
  let before = batched.codex_composer_input()
  assert_eq(before.draft.mentions.length(), 1)
  let (_, applied) = update(
    dispatch,
    FileEditor(@fileeditor.ApplyAllFeedback),
    batched,
  )
  let queued = applied.codex.transcript_items()
  assert_eq(queued.length(), 1)
  guard queued[0].kind is @transcript.User(prompt) else {
    fail("expected the queued comment as a user prompt")
  }
  assert_true(prompt.contains("<user_mentions>"))
  assert_true(prompt.contains("rename this"))
}

///|
test "chip jumps relativize legacy absolute paths against the roots" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/work/project")
  // A project conversation uses its project root.
  let model = test_model()
    .replace_conversation({
      ..test_conversation(),
      workspace: Project(root=workspace),
    })
    .with_dev(dev => {
      ..dev,
      worktrees: [{ project: workspace, rows: [], generation: 1, }],
    })
  let model = {
    ..model,
    file_panel: {
      ..model.file_panel,
      owner: Some({
        channel: @interop.ChannelId::Remote("previous"),
        session: "previous-session",
      }),
      tree_open: false,
      explorer_mode: @fileeditor.ExplorerChanges,
      review_view_mode: @fileeditor.ReviewDiff,
      changes_generation: 7,
      watch_generation: 11,
    },
  }
  let (_, next) = update(
    dispatch,
    JumpToLocation(
      path="/work/project/src/main.mbt",
      range=Some(@common.Range(5, 1, 5, 1)),
      annotation=None,
    ),
    model,
  )
  assert_true(@dock.active_file(next.dock) is Some(Relative("src/main.mbt")))
  assert_false(next.file_panel.tree_open)
  assert_true(next.file_panel.explorer_mode is @fileeditor.ExplorerChanges)
  assert_true(next.file_panel.review_view_mode is @fileeditor.ReviewDiff)
  // The eager re-root retains 7. The jump keeps the explorer hidden while the
  // file is active, so Changes waits until the pane is shown before refreshing.
  assert_true(next.file_panel.changes_generation == 7)
  // The fresh watch spends the next page-lifetime identity; resetting the
  // eager panel to zero would let an older generation 1 push collide here.
  assert_eq(next.file_panel.watch_generation, 12)
  // The registry can still be loading; once loaded, the project root remains
  // the conversation root when no worktree row binds this session.
  let model = test_model()
    .replace_conversation({
      ..test_conversation(),
      workspace: Project(root=workspace),
    })
    .with_dev(dev => {
      ..dev,
      worktrees: [{ project: workspace, rows: [], generation: 1, }],
    })
  let (_, next) = update(
    dispatch,
    JumpToLocation(
      path="/work/project/src/main.mbt",
      range=Some(@common.Range(5, 1, 5, 1)),
      annotation=None,
    ),
    model,
  )
  assert_true(@dock.active_file(next.dock) is Some(Relative("src/main.mbt")))
  // An absolute path outside every root cannot be opened; the panel says so
  // instead of sending the host a bogus read.
  let (_, outside) = update(
    dispatch,
    JumpToLocation(
      path="/elsewhere/note.md",
      range=Some(@common.Range(1, 1, 1, 1)),
      annotation=None,
    ),
    model,
  )
  assert_true(outside.dock.active is None)
  assert_true(outside.file_panel.error is Some(_))
}

///|
test "RevealDirectory(\"\") opens the workspace breadcrumb picker" {
  let dispatch = test_dispatch()
  let model = test_model()
  let owner : @interop.ConversationKey = {
    channel: Local,
    session: "desktop-test",
  }
  let dock = {
    ..@dock.open_file(model.dock, Relative("README.md")),
    owner: Some(owner),
  }
  let panel = {
    ..model.file_panel,
    owner: Some(owner),
    tree_open: false,
    highlighted: Some(Relative("src")),
  }
  let (_, next) = update(
    dispatch,
    FileEditor(RevealDirectory(@pathx.Relative::root())),
    { ..model, dock, file_panel: panel, right_panel_open: true, },
  )
  // The active tab and docked explorer stay put while the picker opens.
  assert_true(@dock.active_file(next.dock) is Some(Relative("README.md")))
  assert_false(next.file_panel.tree_open)
  assert_true(next.file_panel.highlighted is Some(Relative("")))
}

///|
test "RevealDirectory loads an uncached breadcrumb directory" {
  let dispatch = test_dispatch()
  let model = test_model()
  let panel = {
    ..model.file_panel,
    owner: Some({ channel: Local, session: "desktop-test", }),
  }
  let (_, next) = update(
    dispatch,
    FileEditor(RevealDirectory(Relative("src/foo"))),
    { ..model, file_panel: panel, },
  )
  assert_true(next.file_panel.expanded.is_empty())
  assert_true(next.file_panel.loading.contains(Relative("src/foo")))
  assert_true(next.file_panel.highlighted is Some(Relative("src/foo")))
}

///|
test "RevealDirectory on an already-cached directory needs no reload" {
  let dispatch = test_dispatch()
  let model = test_model()
  let children : Map[@pathx.Relative, Array[@fileeditor.FileEntry]] = Map([
    (Relative("src/foo"), []),
  ])
  let panel = {
    ..model.file_panel,
    owner: Some({ channel: Local, session: "desktop-test", }),
    children,
  }
  let (_, next) = update(
    dispatch,
    FileEditor(RevealDirectory(Relative("src/foo"))),
    { ..model, file_panel: panel, },
  )
  assert_true(next.file_panel.expanded.is_empty())
  assert_false(next.file_panel.loading.contains(Relative("src/foo")))
  assert_true(next.file_panel.highlighted is Some(Relative("src/foo")))
}

///|
test "HighlightCleared only clears a highlight that still matches" {
  let dispatch = test_dispatch()
  let model = test_model()
  // Rooted in the active session, or the post-dispatch `sync` re-roots the
  // panel and clears the highlight itself.
  let panel = {
    ..model.file_panel,
    owner: Some({ channel: Local, session: "desktop-test", }),
    highlighted: Some(Relative("src")),
  }
  let (_, stale) = update(
    dispatch,
    FileEditor(HighlightCleared(Relative("old"))),
    { ..model, file_panel: panel, },
  )
  assert_true(stale.file_panel.highlighted is Some(Relative("src")))
  let (_, cleared) = update(
    dispatch,
    FileEditor(HighlightCleared(Relative("src"))),
    { ..model, file_panel: panel, },
  )
  assert_true(cleared.file_panel.highlighted is None)
}

///|
/// A prompt submitted mid-compaction must not start: the serve engine would
/// queue it behind the compaction, out of Stop's reach. The draft stays put.
test "a prompt submitted during compaction stays in the composer" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    compaction: Compacting,
    task: "do the thing",
  })
  let (_, next) = update(dispatch, Send, model)
  inspect(next.active().task, content="do the thing")
  inspect(next.active().messages.length(), content="0")
}

///|
/// A `/compact` sent mid-turn queues behind the open run in the engine. The
/// composer must say so immediately, swallow a duplicate, and keep the send
/// gate held through the gap between the turn's end and the engine's
/// compaction_started.
test "a mid-turn /compact stays visibly queued until compaction starts" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..running_conversation(),
    last_run_id: Some("r7"),
  })
  let (_, queued) = run_slash_command(dispatch, model, "compact")
  assert_true(queued.active().compaction is Queued)
  // One compaction at a time: the repeat is swallowed, not re-sent.
  let (_, again) = run_slash_command(dispatch, queued, "compact")
  assert_true(again.active().compaction is Queued)
  // The turn ends before compaction_started arrives; a prompt sent into
  // that gap would queue behind the compaction, out of Stop's reach.
  let (_, ended) = update_dev(
    dispatch,
    Finished(run_id="r7", status="completed", answer=None),
    again,
  )
  assert_true(ended.active().compaction is Queued)
  let drafted = ended.replace_conversation({
    ..ended.active(),
    task: "next prompt",
  })
  let (_, held) = update(dispatch, Send, drafted)
  inspect(held.active().task, content="next prompt")
  // The engine reaches the queued compaction: queued flips into compacting.
  let (_, started) = update_dev(
    dispatch,
    Engine(Some("r7"), CompactionStarted, session=None),
    held,
  )
  assert_true(started.active().compaction is Compacting)
}

///|
/// An idle `/compact` has no engine acknowledgment yet — the host may still
/// be spawning a serve engine for it (a resumed conversation compacted
/// before its first prompt) — but the request must hold the send gate
/// immediately: a prompt sent into that window would be consumed and
/// rejected by the host instead of held in the composer.
test "an idle /compact holds the send gate until the engine confirms" {
  let dispatch = test_dispatch()
  let (_, requested) = run_slash_command(dispatch, test_model(), "compact")
  assert_true(requested.active().compaction is Requested)
  // A repeat while the request is in flight is swallowed, not re-sent.
  let (_, again) = run_slash_command(dispatch, requested, "compact")
  assert_true(again.active().compaction is Requested)
  // A draft sent during the spawn/write window stays in the composer.
  let drafted = again.replace_conversation({
    ..again.active(),
    task: "next prompt",
  })
  let (_, held) = update(dispatch, Send, drafted)
  inspect(held.active().task, content="next prompt")
  inspect(held.active().messages.length(), content="0")
  // The engine confirms; the session stamp routes it (no run id exists yet).
  let (_, started) = update_dev(
    dispatch,
    Engine(None, CompactionStarted, session=Some("desktop-test")),
    held,
  )
  assert_true(started.active().compaction is Compacting)
}

///|
/// Rabbita purity: the automatic-checkpoint semantic event is lifecycle-only;
/// its Summary card comes from the durable commit.
test "update is pure: automatic checkpoint waits for its commit" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    turn: {
      ..running_conversation().turn,
      streaming_response: Some("partial"),
    },
  })
  let (_, once) = update_dev(
    dispatch,
    Engine(Some("r7"), AutoCompactionFinished("checkpoint recap"), session=None),
    model,
  )
  let (_, twice) = update_dev(
    dispatch,
    Engine(Some("r7"), AutoCompactionFinished("checkpoint recap"), session=None),
    model,
  )
  assert_eq(once.active().turn.streaming_response, Some("partial"))
  assert_eq(twice.active().turn.streaming_response, Some("partial"))
  assert_true(
    once.active().compaction is NotCompacting &&
    twice.active().compaction is NotCompacting,
  )
}

///|
/// Rabbita purity: context-yield guidance is a deterministic model update.
/// The raw stream event clears partial streams but does not close the run;
/// the host's following Finished message owns that transition.
test "update is pure: context yield waits for its commit" {
  let dispatch = test_dispatch()
  let answer = "[context ceiling] continue in a new turn"
  let model = running_model().replace_conversation({
    ..running_conversation(),
    turn: {
      ..running_conversation().turn,
      streaming_response: Some("partial"),
    },
  })
  let (_, once) = update_dev(
    dispatch,
    Engine(Some("r7"), ContextYield(answer), session=None),
    model,
  )
  let (_, twice) = update_dev(
    dispatch,
    Engine(Some("r7"), ContextYield(answer), session=None),
    model,
  )
  assert_eq(once.active().turn.streaming_response, None)
  assert_eq(twice.active().turn.streaming_response, None)
  assert_true(once.active().is_running() && twice.active().is_running())
}

///|
/// The successful ceiling path re-opens Send without synthesizing durable
/// transcript items. Its Summary and guidance arrive through commits.
test "context yield settles after its automatic checkpoint" {
  let dispatch = test_dispatch()
  let answer = "[context ceiling] continue in a new turn"
  let (_, checkpointed) = update_dev(
    dispatch,
    Engine(Some("r7"), AutoCompactionFinished("checkpoint recap"), session=None),
    running_model(),
  )
  let (_, yielded) = update_dev(
    dispatch,
    Engine(Some("r7"), ContextYield(answer), session=None),
    checkpointed,
  )
  assert_true(yielded.active().is_running())
  let (_, settled) = update_dev(
    dispatch,
    Finished(run_id="r7", status="context_yield", answer=Some(answer)),
    yielded,
  )
  assert_true(settled.active().compaction is NotCompacting)
  assert_false(settled.active().is_running())
  guard settled.display_status() is Finished(outcome) else {
    fail("expected a finished status")
  }
  assert_true(outcome is ContextYield)
  inspect(outcome.label(), content="Context limit reached")
  assert_true(settled.display_status().kind() is Warn)
}

///|
/// Compaction completion settles lifecycle state; its Summary is commit-only.
test "compaction_finished waits for its durable summary" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    compaction: Compacting,
    last_run_id: Some("r7"),
  })
  let (_, next) = update_dev(
    dispatch,
    Engine(
      Some("r7"),
      CompactionFinished("earlier turns compacted"),
      session=None,
    ),
    model,
  )
  assert_true(next.active().compaction is NotCompacting)
}

///|
/// A conversation resumed and compacted before its first prompt of this
/// app-lifetime has no run id anywhere — the spawned engine stamps run 0 and
/// the conversation's `last_run_id` is still `None` — so compaction events
/// must route by the session the host stamps on them.
test "compaction events route by session when no run id matches" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    last_run_id: None,
  })
  let (_, started) = update_dev(
    dispatch,
    Engine(None, CompactionStarted, session=Some("desktop-test")),
    model,
  )
  assert_true(started.active().compaction is Compacting)
  let (_, next) = update_dev(
    dispatch,
    Engine(
      None,
      CompactionFinished("earlier turns compacted"),
      session=Some("desktop-test"),
    ),
    started,
  )
  assert_true(next.active().compaction is NotCompacting)
}

///|
/// The host synthesizes compaction_failed when the engine dies with a
/// compaction still queued behind the dead turn; that terminal event must
/// settle the queued notice like any other compaction failure.
test "compaction_failed settles a still-queued compaction" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    compaction: Queued,
    last_run_id: Some("r7"),
  })
  let (_, next) = update_dev(
    dispatch,
    Engine(Some("r7"), CompactionFailed("engine exited"), session=None),
    model,
  )
  assert_true(next.active().compaction is NotCompacting)
  inspect(next.notifications.length(), content="1")
}

///|
/// A rejected compact request (no engine, host error) never produces
/// compaction events, so the rejection itself clears the queued notice and
/// reports the error.
test "CompactRejected clears the queued notice and reports the error" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    compaction: Queued,
  })
  let (_, next) = update_dev(
    dispatch,
    CompactRejected(session="desktop-test", message="no engine"),
    model,
  )
  assert_true(next.active().compaction is NotCompacting)
  inspect(next.notifications.length(), content="1")
  inspect(next.notifications[0].message, content="no engine")
}

///|
test "AppInfoLoaded replaces the displayed package version idempotently" {
  let dispatch = test_dispatch()
  let (_, once) = update(dispatch, AppInfoLoaded("0.2.0"), test_model())
  let (_, twice) = update(dispatch, AppInfoLoaded("0.2.0"), once)
  assert_eq(once.app_version, "0.2.0")
  assert_eq(twice.app_version, once.app_version)
  assert_eq(twice.notification_seq, once.notification_seq)
}

///|
test "a startup check surfaces an installable release as the Update button" {
  let dispatch = test_dispatch()
  let (_, model) = update(
    dispatch,
    UpdateCheckFinished(
      result=CheckFound(
        version="0.2.0",
        installable=true,
        unavailable_reason=None,
      ),
      explicit=false,
    ),
    test_model(),
  )
  assert_true(
    model.update_ux is UpdateAvailable(version="0.2.0", installable=true),
  )
  assert_eq(model.notifications.length(), 0)
}

///|
test "an unavailable startup update reports why without offering Update" {
  let dispatch = test_dispatch()
  let model = test_model()
  let msg = UpdateCheckFinished(
    result=CheckFound(
      version="0.2.0",
      installable=false,
      unavailable_reason=Some("Move SeekMoon.app to Applications."),
    ),
    explicit=false,
  )
  let (_, first) = update(dispatch, msg, model)
  let (_, replayed) = update(dispatch, msg, model)
  for result in [first, replayed] {
    assert_true(
      result.update_ux is UpdateAvailable(version="0.2.0", installable=false),
    )
    assert_eq(result.notifications.length(), 1)
    inspect(
      result.notifications[0].message,
      content="Move SeekMoon.app to Applications.",
    )
    assert_eq(result.notification_seq, 1)
  }
}

///|
test "a package-less release stays informational" {
  let dispatch = test_dispatch()
  let (_, model) = update(
    dispatch,
    UpdateCheckFinished(
      result=CheckFound(
        version="0.2.0",
        installable=false,
        unavailable_reason=None,
      ),
      explicit=false,
    ),
    test_model(),
  )
  assert_true(
    model.update_ux is UpdateAvailable(version="0.2.0", installable=false),
  )
  assert_eq(model.notifications.length(), 0)
}

///|
test "quiet startup outcomes leave no trace; explicit ones answer" {
  let dispatch = test_dispatch()
  for
    result in [
      CheckUpToDate,
      CheckUnreachable(reason="offline"),
      CheckMalformed(reason="not json"),
    ] {
    let (_, silent) = update(
      dispatch,
      UpdateCheckFinished(result~, explicit=false),
      test_model(),
    )
    assert_true(silent.update_ux is UpdateUnknown)
    assert_eq(silent.notifications.length(), 0)
  }
  let (_, ok) = update(
    dispatch,
    UpdateCheckFinished(result=CheckUpToDate, explicit=true),
    test_model(),
  )
  assert_true(ok.update_ux is UpToDate)
  let (_, offline) = update(
    dispatch,
    UpdateCheckFinished(
      result=CheckUnreachable(reason="offline"),
      explicit=true,
    ),
    test_model(),
  )
  assert_true(
    offline.update_ux is UpdateCheckFailed(..) &&
    offline.update_ux is UpdateCheckFailed(message~) &&
    message.contains("offline"),
  )
}

///|
test "a broken package entry is loud even when the app asked" {
  let dispatch = test_dispatch()
  let (_, model) = update(
    dispatch,
    UpdateCheckFinished(
      result=CheckBroken(version="0.2.0", reason="url is not https"),
      explicit=false,
    ),
    test_model(),
  )
  assert_eq(model.notifications.length(), 1)
  assert_true(model.notifications[0].message.contains("url is not https"))
  assert_true(model.update_ux is UpdateCheckFailed(..))
}

///|
test "clicking Update goes straight to download when nothing runs" {
  let dispatch = test_dispatch()
  let available = {
    ..test_model(),
    update_ux: UpdateAvailable(version="0.2.0", installable=true),
  }
  let (_, clicked) = update(dispatch, UpdateClicked, available)
  assert_true(clicked.update_ux is DownloadingUpdate(version="0.2.0", ..))
  let progress = UpdateDownloadProgress(
    downloaded_bytes=42,
    total_bytes=Some(100),
  )
  let (_, progressed) = update(dispatch, progress, clicked)
  let (_, replayed) = update(dispatch, progress, clicked)
  assert_true(progressed.update_ux == replayed.update_ux)
  assert_true(
    progressed.update_ux
    is DownloadingUpdate(
      version="0.2.0",
      progress={ downloaded_bytes: 42, total_bytes: Some(100), }
    ),
  )
  // Downloaded hands off to apply and marks the restart.
  let (_, done) = update(dispatch, UpdateDownloaded, progressed)
  assert_true(done.update_ux is RestartingForUpdate(version="0.2.0"))
}

///|
test "clicking Update asks first while a conversation runs" {
  let dispatch = test_dispatch()
  let busy = {
    ..test_model().replace_conversation({
      ..test_conversation(),
      run: Starting(submission_id="pending-update"),
    }),
    update_ux: UpdateAvailable(version="0.2.0", installable=true),
  }
  let (_, asked) = update(dispatch, UpdateClicked, busy)
  assert_true(asked.update_ux is ConfirmingRestart(version="0.2.0"))
  // Cancel restores the offer; confirm starts the download.
  let (_, kept) = update(dispatch, CancelUpdateRestart, asked)
  assert_true(
    kept.update_ux is UpdateAvailable(version="0.2.0", installable=true),
  )
  let (_, confirmed) = update(dispatch, ConfirmUpdateRestart, asked)
  assert_true(confirmed.update_ux is DownloadingUpdate(version="0.2.0", ..))
}

///|
test "a failed download says why and restores the offer" {
  let dispatch = test_dispatch()
  let downloading = {
    ..test_model(),
    update_ux: DownloadingUpdate(version="0.2.0", progress={
      downloaded_bytes: 42,
      total_bytes: Some(100),
    }),
  }
  let (_, failed) = update(
    dispatch,
    UpdateFailed(message="digest mismatch"),
    downloading,
  )
  assert_eq(failed.notifications.length(), 1)
  assert_true(failed.notifications[0].message.contains("digest mismatch"))
  assert_true(
    failed.update_ux is UpdateAvailable(version="0.2.0", installable=true),
  )
}

///|
test "a failed apply says why and withdraws the offer" {
  let dispatch = test_dispatch()
  let restarting = {
    ..test_model(),
    update_ux: RestartingForUpdate(version="0.2.0"),
  }
  let msg = UpdateFailed(message="the app location became read-only")
  let (_, first) = update(dispatch, msg, restarting)
  let (_, replayed) = update(dispatch, msg, restarting)
  for failed in [first, replayed] {
    assert_eq(failed.notifications.length(), 1)
    assert_true(failed.notifications[0].message.contains("read-only"))
    assert_eq(failed.notification_seq, 1)
    assert_true(
      failed.update_ux is UpdateAvailable(version="0.2.0", installable=false),
    )
  }
}

///|
test "a stale check reply cannot clobber a download in flight" {
  let dispatch = test_dispatch()
  let downloading = {
    ..test_model(),
    update_ux: DownloadingUpdate(version="0.2.0", progress={
      downloaded_bytes: 42,
      total_bytes: Some(100),
    }),
  }
  let (_, next) = update(
    dispatch,
    UpdateCheckFinished(result=CheckUpToDate, explicit=false),
    downloading,
  )
  assert_true(next.update_ux is DownloadingUpdate(version="0.2.0", ..))
}

///|
test "late update progress cannot revive an available release" {
  let dispatch = test_dispatch()
  let available = {
    ..test_model(),
    update_ux: UpdateAvailable(version="0.2.0", installable=true),
  }
  let msg = UpdateDownloadProgress(downloaded_bytes=42, total_bytes=Some(100))
  let (_, first) = update(dispatch, msg, available)
  let (_, replayed) = update(dispatch, msg, available)
  assert_true(first.update_ux == available.update_ux)
  assert_true(replayed.update_ux == available.update_ux)
}

///|
test "switching the chat provider leaves the update answer alone" {
  let dispatch = test_dispatch()
  let available = {
    ..test_model(),
    update_ux: UpdateAvailable(version="0.2.0", installable=true),
  }
  // A retired hosted-provider value lands on the BYOK default and the
  // update channel no longer derives from the chat provider.
  let (_, switched) = update(
    dispatch,
    ProviderChanged("openseek-staging"),
    available,
  )
  assert_true(switched.api_provider is Deepseek)
  assert_true(switched.update_ux is UpdateAvailable(..))
  let (_, kept) = update(dispatch, ProviderChanged("custom"), available)
  assert_true(kept.api_provider is Custom)
  assert_true(kept.update_ux is UpdateAvailable(..))
}

///|
test "send does not show a prompt until its commit lands" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    task: "build the thing",
  })
  let (_, sent) = update(dispatch, Send, model)
  // Starting the request changes lifecycle/composer state only.
  inspect(sent.active().messages.length(), content="0")
  inspect(sent.active().watermark, content="0")
  // The durable commit is the first point the prompt becomes transcript.
  let (_, committed) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=1,
      ts=None,
      item=@protocol.User({ content: "build the thing", submission_id: None, }),
      session_root=@interop.ChannelId::Local.test_store_root(),
    ),
    sent,
  )
  inspect(committed.active().messages.length(), content="1")
  guard committed.active().messages[0].kind is User(_) else {
    fail("expected a user item")
  }
  inspect(committed.active().watermark, content="1")
}

///|
test "a replayed commit at or below the watermark is dropped" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    messages: [{ kind: User("already there"), ts: None, sequence: None, }],
    watermark: 2,
  })
  let (_, next) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=2,
      ts=None,
      item=@protocol.User({ content: "already there", submission_id: None, }),
      session_root=@interop.ChannelId::Local.test_store_root(),
    ),
    model,
  )
  inspect(next.active().messages.length(), content="1")
  inspect(next.active().watermark, content="2")
}

///|
test "a commit past the frontier buffers and flips into a reload" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    watermark: 1,
  })
  let (_, next) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=5,
      ts=None,
      item=@protocol.User({ content: "from the future", submission_id: None, }),
      session_root=@interop.ChannelId::Local.test_store_root(),
    ),
    model,
  )
  // The gap means missed broadcasts; nothing is applied out of order.
  inspect(next.active().messages.length(), content="0")
  inspect(next.active().watermark, content="1")
  guard next.active().sync is Reloading(buffered~, ..) else {
    fail("expected a reload in flight")
  }
  inspect(buffered.length(), content="1")
  inspect(buffered[0].sequence, content="5")
}

///|
test "commits buffer while a reload is in flight" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    sync: test_reloading([]),
  })
  let (_, next) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=3,
      ts=None,
      item=@protocol.User({ content: "mid-reload", submission_id: None, }),
      session_root=@interop.ChannelId::Local.test_store_root(),
    ),
    model,
  )
  inspect(next.active().messages.length(), content="0")
  guard next.active().sync is Reloading(buffered~, ..) else {
    fail("expected the reload to stay in flight")
  }
  inspect(buffered.length(), content="1")
}

///|
test "a snapshot drains buffered commits in sequence order" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation()
    // Out of arrival order on purpose; the drain sorts by sequence.
    ,
    sync: test_reloading([
      {
        sequence: 4,
        ts: None,
        item: @protocol.User({ content: "four", submission_id: None, }),
      },
      {
        sequence: 3,
        ts: None,
        item: @protocol.User({ content: "three", submission_id: None, }),
      },
    ]),
  })
  let (_, next) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[
        { kind: User("one"), ts: None, sequence: None, },
        {
          kind: Assistant(
            reasoning=None,
            prose=Some("two"),
            calls=[],
            replay=false,
            finished=false,
          ),
          ts: None,
          sequence: None,
        },
      ],
      watermark=2,
      generation=1,
    ),
    model,
  )
  inspect(next.active().messages.length(), content="4")
  assert_eq(next.active().messages[2].text(), Some("three"))
  assert_eq(next.active().messages[3].text(), Some("four"))
  inspect(next.active().watermark, content="4")
  assert_true(next.active().sync is Synced)
}

///|
test "a snapshot already containing the buffered commits drops them" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    sync: test_reloading([
      {
        sequence: 2,
        ts: None,
        item: @protocol.User({ content: "dup", submission_id: None, }),
      },
    ]),
  })
  let (_, next) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[
        { kind: User("one"), ts: None, sequence: None, },
        { kind: User("dup"), ts: None, sequence: None, },
      ],
      watermark=2,
      generation=1,
    ),
    model,
  )
  inspect(next.active().messages.length(), content="2")
  inspect(next.active().watermark, content="2")
  assert_true(next.active().sync is Synced)
}

///|
test "a snapshot with a still-gapped buffer keeps reloading" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    sync: test_reloading([
      {
        sequence: 9,
        ts: None,
        item: @protocol.User({ content: "far", submission_id: None, }),
      },
    ]),
  })
  let (_, next) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[{ kind: User("one"), ts: None, sequence: None, }],
      watermark=2,
      generation=1,
    ),
    model,
  )
  inspect(next.active().watermark, content="2")
  guard next.active().sync is Reloading(buffered~, ..) else {
    fail("expected another reload for the remaining gap")
  }
  inspect(buffered.length(), content="1")
  inspect(buffered[0].sequence, content="9")
}

///|
test "background retries preserve buffered commits until a later success" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    messages: [{ kind: User("kept"), ts: None, sequence: None, }],
    watermark: 1,
    sync: test_reloading([
      {
        sequence: 3,
        ts: None,
        item: @protocol.User({ content: "x", submission_id: None, }),
      },
    ]),
  })
  let model = { ..model, transcript_request_generation: 1, }
  let failure = SessionRefreshFailed(session="desktop-test", generation=1)
  let (_, retrying2) = update_dev(dispatch, failure, model)
  guard retrying2.active().sync is Reloading(attempt=2, buffered=buffered2, ..) else {
    fail("expected the second background attempt")
  }
  inspect(buffered2.length(), content="1")
  let (_, retrying3) = update_dev(dispatch, failure, retrying2)
  guard retrying3.active().sync is Reloading(attempt=3, ..) else {
    fail("expected the third background attempt")
  }
  let (_, failed) = update_dev(dispatch, failure, retrying3)
  guard failed.active().sync is ReloadFailed(buffered=failed_buffer, ..) else {
    fail("expected bounded retry exhaustion")
  }
  inspect(failed_buffer.length(), content="1")
  inspect(failed.active().messages.length(), content="1")
  inspect(failed.notifications.length(), content="0")
  // The next commit starts a fresh generation without applying out of order.
  let (_, retrying) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=2,
      ts=None,
      item=@protocol.User({ content: "next", submission_id: None, }),
      session_root=@interop.ChannelId::Local.test_store_root(),
    ),
    failed,
  )
  guard retrying.active().sync
    is Reloading(generation=2, buffered=retry_buffer, ..) else {
    fail("expected a new generation")
  }
  inspect(retry_buffer.length(), content="2")
  let (_, healed) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[{ kind: User("kept"), ts: None, sequence: None, }],
      watermark=1,
      generation=2,
    ),
    retrying,
  )
  inspect(healed.active().messages.length(), content="3")
  assert_eq(healed.active().messages[1].text(), Some("next"))
  assert_eq(healed.active().messages[2].text(), Some("x"))
  inspect(healed.active().watermark, content="3")
  assert_true(healed.active().sync is Synced)
}

///|
test "reopening an active failed reload restarts it and keeps the buffer" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    messages: [{ kind: User("kept"), ts: None, sequence: None, }],
    watermark: 1,
    sync: ReloadFailed(generation=1, buffered=[
      {
        sequence: 2,
        ts: None,
        item: @protocol.User({ content: "two", submission_id: None, }),
      },
    ]),
  })
  let model = { ..model, transcript_request_generation: 1, }
  let (_, reopened) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-test"),
    model,
  )
  assert_true(
    reopened.loading_conversation
    is Some({ channel: Local, session: "desktop-test", }),
  )
  guard reopened.active().sync
    is Reloading(generation=2, attempt=1, buffered~, ..) else {
    fail("expected the active click to restart the reload")
  }
  inspect(buffered.length(), content="1")
  let (_, loaded) = update_dev(
    dispatch,
    SessionLoaded(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[{ kind: User("kept"), ts: None, sequence: None, }],
      watermark=1,
      generation=2,
    ),
    reopened,
  )
  assert_true(loaded.loading_conversation is None)
  inspect(loaded.active().messages.length(), content="2")
  inspect(loaded.active().watermark, content="2")
  assert_true(loaded.active().sync is Synced)
}

///|
test "stale and lower-watermark snapshots cannot overwrite current state" {
  let dispatch = test_dispatch()
  let current_root = @interop.ChannelId::Local.test_resource("/work/current")
  let model = test_model().replace_conversation({
    ..test_conversation(),
    workspace: Project(root=current_root),
    messages: [{ kind: User("current"), ts: None, sequence: None, }],
    watermark: 5,
    sync: Reloading(
      generation=2,
      attempt=1,
      buffered=[
        {
          sequence: 6,
          ts: None,
          item: @protocol.User({ content: "six", submission_id: None, }),
        },
      ],
      reload_after_current=false,
    ),
  })
  let (_, stale) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[{ kind: User("stale generation"), ts: None, sequence: None, }],
      watermark=9,
      generation=1,
    ),
    model,
  )
  assert_eq(stale.active().messages[0].text(), Some("current"))
  inspect(stale.active().watermark, content="5")
  assert_eq(stale.active().workspace, Project(root=current_root))
  guard stale.active().sync is Reloading(generation=2, attempt=1, ..) else {
    fail("stale generation changed the active reload")
  }
  let (_, lower) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[{ kind: User("older snapshot"), ts: None, sequence: None, }],
      watermark=4,
      generation=2,
    ),
    stale,
  )
  assert_eq(lower.active().messages[0].text(), Some("current"))
  inspect(lower.active().watermark, content="5")
  assert_eq(lower.active().workspace, Project(root=current_root))
  guard lower.active().sync is Reloading(generation=2, attempt=2, buffered~, ..) else {
    fail("lower watermark did not retry the current generation")
  }
  inspect(buffered.length(), content="1")
}

///|
test "tool decode semantics wait for their durable error tool result" {
  let dispatch = test_dispatch()
  let semantic = Engine(
    Some("r7"),
    ToolCallDecodeError(tool_name="edit", reason="invalid arguments"),
    session=None,
  )
  // The engine records the response with its undecodable call, then the
  // error result that closes it; the semantic event is only news.
  let call = SessionCommitted(
    session="desktop-test",
    sequence=1,
    ts=None,
    item=@protocol.Assistant({
      content: "",
      tool_calls: Some([{ id: "c1", name: "edit", arguments: "{", }]),
      reasoning_content: None,
      is_replay: None,
    }),
    session_root=@interop.ChannelId::Local.test_store_root(),
  )
  let result = SessionCommitted(
    session="desktop-test",
    sequence=2,
    ts=None,
    item=@protocol.ToolResult({
      tool_call_id: "c1",
      tool_name: "edit",
      content: "invalid arguments",
      is_error: true,
      brief: None,
    }),
    session_root=@interop.ChannelId::Local.test_store_root(),
  )
  let (_, semantic_first) = update_dev(dispatch, semantic, running_model())
  inspect(semantic_first.active().messages.length(), content="0")
  let (_, called) = update_dev(dispatch, call, semantic_first)
  let (_, committed_after) = update_dev(dispatch, result, called)
  inspect(committed_after.active().messages.length(), content="1")
  guard committed_after.active().messages[0].kind is Assistant(calls=[edit], ..) else {
    fail("expected the response carrying the failed call")
  }
  assert_true(
    edit.outcome is Done(content="invalid arguments", is_error=true, ..),
  )
  let (_, called_first) = update_dev(dispatch, call, running_model())
  let (_, committed_first) = update_dev(dispatch, result, called_first)
  let (_, semantic_after) = update_dev(dispatch, semantic, committed_first)
  inspect(semantic_after.active().messages.length(), content="1")
}

///|
test "assistant semantic events wait for their durable commit" {
  let dispatch = test_dispatch()
  let (_, thought) = update_dev(
    dispatch,
    Engine(Some("r7"), ReasoningMessage("think"), session=None),
    running_model(),
  )
  let (_, answered) = update_dev(
    dispatch,
    Engine(Some("r7"), AssistantMessage("answer"), session=None),
    thought,
  )
  inspect(answered.active().messages.length(), content="0")
  let (_, committed) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=1,
      ts=None,
      item=@protocol.Assistant({
        content: "answer",
        tool_calls: None,
        reasoning_content: Some("think"),
        is_replay: None,
      }),
      session_root=@interop.ChannelId::Local.test_store_root(),
    ),
    answered,
  )
  // One durable item projects as one response, thought and answer together.
  inspect(committed.active().messages.length(), content="1")
  assert_true(
    committed.active().messages[0].kind
    is Assistant(reasoning=Some("think"), ..),
  )
  assert_eq(committed.active().messages[0].text(), Some("answer"))
  inspect(committed.active().watermark, content="1")
}

///|
test "a committed tool result visibly changes its existing call row" {
  let (_, called) = running_conversation().apply_commit(
    1,
    @protocol.Assistant({
      content: "",
      tool_calls: Some([
        { id: "c1", name: "read", arguments: "{\"path\":\"moon.mod\"}", },
      ]),
      reasoning_content: None,
      is_replay: None,
    }),
  )
  inspect(called.messages.length(), content="1")
  let (changed, completed) = called.apply_commit(
    2,
    @protocol.ToolResult({
      tool_call_id: "c1",
      tool_name: "read",
      content: "module contents",
      is_error: false,
      brief: Some("read moon.mod"),
    }),
  )
  assert_true(changed)
  inspect(completed.messages.length(), content="1")
  guard completed.messages[0].kind is Assistant(calls=[call], ..) else {
    fail("expected the response to keep its one call")
  }
  assert_true(
    call.outcome
    is Done(content="module contents", brief=Some("read moon.mod"), ..),
  )
}

///|
test "a delayed assistant commit never clears a newer live delta" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    turn: {
      ..running_conversation().turn,
      streaming_response: Some("newer turn fragment"),
      live_reasoning: Some({
        content: "newer reasoning fragment",
        complete: false,
      }),
    },
  })
  let (_, committed) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=1,
      ts=None,
      item=@protocol.Assistant({
        content: "older committed answer",
        tool_calls: None,
        reasoning_content: Some("older reasoning"),
        is_replay: None,
      }),
      session_root=@interop.ChannelId::Local.test_store_root(),
    ),
    model,
  )
  assert_eq(
    committed.active().turn.streaming_response,
    Some("newer turn fragment"),
  )
  assert_eq(
    committed.active().turn.live_reasoning,
    Some({ content: "newer reasoning fragment", complete: false, }),
  )
}

///|
test "a delayed terminal commit never clears a newer live delta" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    messages: [{ kind: User("older prompt"), ts: None, sequence: None, }],
    watermark: 1,
    turn: {
      ..running_conversation().turn,
      streaming_response: Some("next turn fragment"),
    },
  })
  let (_, committed) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=2,
      ts=None,
      item=@protocol.Terminal(@protocol.Finished("older answer")),
      session_root=@interop.ChannelId::Local.test_store_root(),
    ),
    model,
  )
  assert_eq(
    committed.active().turn.streaming_response,
    Some("next turn fragment"),
  )
}

///|
test "commit-first assistant semantics do not append again" {
  let dispatch = test_dispatch()
  let streaming = running_model().replace_conversation({
    ..running_conversation(),
    turn: { ..running_conversation().turn, streaming_response: Some("answer"), },
  })
  let (_, committed) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=1,
      ts=None,
      item=@protocol.Assistant({
        content: "answer",
        tool_calls: None,
        reasoning_content: Some("think"),
        is_replay: None,
      }),
      session_root=@interop.ChannelId::Local.test_store_root(),
    ),
    streaming,
  )
  let (_, thought) = update_dev(
    dispatch,
    Engine(Some("r7"), ReasoningMessage("think"), session=None),
    committed,
  )
  let (_, answered) = update_dev(
    dispatch,
    Engine(Some("r7"), AssistantMessage("answer"), session=None),
    thought,
  )
  inspect(answered.active().messages.length(), content="1")
  inspect(answered.active().watermark, content="1")
  assert_eq(answered.active().turn.streaming_response, None)
}

///|
test "a sequence-one commit materializes an unknown hidden conversation" {
  let dispatch = test_dispatch()
  let (_, next) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-elsewhere",
      sequence=1,
      ts=None,
      item=@protocol.User({ content: "hi", submission_id: None, }),
      session_root=@interop.ChannelId::Local.test_store_root(),
    ),
    test_model(),
  )
  inspect(next.conversations.length(), content="2")
  inspect(next.active().messages.length(), content="0")
  guard next.find_conversation(@interop.ChannelId::Local, "desktop-elsewhere")
    is Some(hidden) else {
    fail("unknown commit did not materialize its session")
  }
  inspect(hidden.messages.length(), content="1")
  assert_eq(hidden.messages[0].text(), Some("hi"))
  inspect(hidden.watermark, content="1")
  inspect(next.dev().sessions_request_generation, content="1")
  let (_, repeated) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-elsewhere",
      sequence=1,
      ts=None,
      item=@protocol.User({ content: "hi", submission_id: None, }),
      session_root=@interop.ChannelId::Local.test_store_root(),
    ),
    next,
  )
  inspect(repeated.dev().sessions_request_generation, content="1")
}

///|
test "a gapped commit for an unknown session materializes then reloads" {
  let dispatch = test_dispatch()
  let (_, next) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-gap",
      sequence=3,
      ts=None,
      item=@protocol.User({ content: "third", submission_id: None, }),
      session_root=@interop.ChannelId::Local.test_store_root(),
    ),
    test_model(),
  )
  guard next.find_conversation(@interop.ChannelId::Local, "desktop-gap")
    is Some(hidden) else {
    fail("gapped commit did not materialize its session")
  }
  inspect(hidden.messages.length(), content="0")
  guard hidden.sync is Reloading(generation=1, buffered~, ..) else {
    fail("unknown gap did not start a snapshot recovery")
  }
  inspect(buffered.length(), content="1")
  inspect(buffered[0].sequence, content="3")
  inspect(next.active_session, content="desktop-test")
}

///|
test "a late commit cannot resurrect a locally known archived session" {
  let dispatch = test_dispatch()
  let model = test_model().with_dev(dev => {
    ..dev,
    archived: [
      {
        id: "desktop-archived",
        title: Some("archived"),
        workspace: @interop.ChannelId::Local.test_project(),
        workspace_name: "",
        updated_at_ms: None,
      },
    ],
  })
  let (_, next) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-archived",
      sequence=1,
      ts=None,
      item=@protocol.User({ content: "stale", submission_id: None, }),
      session_root=@interop.ChannelId::Local.test_store_root(),
    ),
    model,
  )
  assert_true(
    next.find_conversation(@interop.ChannelId::Local, "desktop-archived")
    is None,
  )
  inspect(next.conversations.length(), content="1")
}

///|
test "an archive tombstone blocks commits before the archived list refreshes" {
  let dispatch = test_dispatch()
  let model = test_model().with_archive_override(
    @interop.ChannelId::Local,
    {
      session: "desktop-tombstoned",
      workspace: @interop.ChannelId::Local.test_project(),
    },
    ArchiveStored,
  )
  let (_, next) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-tombstoned",
      sequence=1,
      ts=None,
      item=@protocol.User({ content: "stale", submission_id: None, }),
      session_root=@interop.ChannelId::Local.test_store_root(),
    ),
    model,
  )
  assert_true(
    next.find_conversation(@interop.ChannelId::Local, "desktop-tombstoned")
    is None,
  )
  inspect(next.conversations.length(), content="1")
}

///|
test "remote access walks connect states and dedups clicks" {
  let dispatch = test_dispatch()
  let signed_out : RemoteAccess = {
    server_url: Some("https://relay.example"),
    connected: false,
    managed_by_env: false,
    user_login: None,
    device_name: None,
    device_url: None,
  }
  let (_, seeded) = update(
    dispatch,
    RemoteStatusLoaded(signed_out),
    test_model(),
  )
  assert_true(seeded.remote_access is Some({ user_login: None, .. }))
  let (_, connecting) = update(dispatch, RemoteConnectClicked, seeded)
  assert_true(connecting.remote_connecting)
  // A second click while the browser round-trip is pending is a no-op.
  let (second_cmd, second) = update(dispatch, RemoteConnectClicked, connecting)
  assert_true(second.remote_connecting)
  ignore(second_cmd)
  let (_, failed) = update(dispatch, RemoteConnectFailed("nope"), connecting)
  assert_false(failed.remote_connecting)
  assert_true(failed.remote_error is Some("nope"))
  let signed_in : RemoteAccess = {
    ..signed_out,
    user_login: Some("octocat"),
    connected: true,
  }
  let (_, done) = update(dispatch, RemoteConnectFinished(signed_in), connecting)
  assert_false(done.remote_connecting)
  assert_true(
    done.remote_access
    is Some({ user_login: Some("octocat"), connected: true, .. }),
  )
  // A broadcast keeps the mirror fresh without touching the pending flag.
  let (_, broadcast) = update(
    dispatch,
    RemoteStatusLoaded(signed_out),
    connecting,
  )
  assert_true(broadcast.remote_connecting)
}

///|
test "auth status payloads decode by shape" {
  let status = RemoteAccess::from_status({
    connected: true,
    server_url: Some("https://relay.example"),
    managed_by_env: None,
    user: Some({ login: "octocat", avatar_url: "", }),
    device: Some({
      id: "d_abc",
      name: "My Mac",
      url: "https://relay.example/d/d_abc/",
    }),
  })
  assert_true(status.connected)
  assert_true(status.user_login is Some("octocat"))
  assert_true(status.device_url is Some("https://relay.example/d/d_abc/"))
  let signed_out = RemoteAccess::from_status({
    connected: false,
    server_url: None,
    managed_by_env: None,
    user: None,
    device: None,
  })
  assert_true(signed_out.user_login is None)
}

///|
/// Test-only: a desktop-shaped model (browser tabs exist only where the
/// native views do), after one settling dispatch so the per-conversation
/// sync passes have claimed their owners — as any real first message has
/// long done before a tab can open.
fn desktop_model() -> Model {
  let model = { ..test_model(), is_desktop: true, }
  let (_, model) = update(
    test_dispatch(),
    Terminal(@terminal.TabSelected(key="missing-tab")),
    model,
  )
  model
}

///|
test "terminal visibility changes in the root-owned terminal state" {
  let dispatch = test_dispatch()
  let model = test_model()
  assert_false(model.terminal.is_open())
  let (_, opened) = update(dispatch, Terminal(@terminal.ToggleTerminal), model)
  assert_true(opened.terminal.is_open())
  let (_, closed) = update(dispatch, Terminal(@terminal.ToggleTerminal), opened)
  assert_false(closed.terminal.is_open())
}

///|
test "launcher rows open Browser and all Explorer destinations" {
  let dispatch = test_dispatch()
  let model = desktop_model()
  let (_, model) = update(dispatch, ToggleRightPanel, model)
  let (_, model) = update(dispatch, ToggleRightPanelMenu, model)
  assert_true(model.right_panel_menu_open)
  let (_, model) = update(dispatch, BrowserTabRequested, model)
  assert_false(model.right_panel_menu_open)
  assert_true(@dock.active_browser(model.dock) == Some(1))
  let page = @preview.page(model.preview, 1).unwrap()
  assert_true(page.url is None)
  assert_false(page.loading)
  let (_, model) = update(dispatch, ExplorerRequested(ExplorerFiles), model)
  assert_true(model.dock.active == Some(@dock.DockTab::FilePicker))
  assert_true(model.file_panel.explorer_mode is ExplorerFiles)
  assert_true(
    model.dock.tabs == [@dock.DockTab::Browser(id=1), @dock.DockTab::FilePicker],
  )
  let (_, model) = update(dispatch, ExplorerRequested(ExplorerChanges), model)
  assert_true(model.dock.active == Some(@dock.DockTab::FilePicker))
  assert_true(model.file_panel.explorer_mode is ExplorerChanges)
  assert_true(model.file_panel.changes is ChangeListLoading(_))
  // Files is an explicit destination even after Review selected Changes.
  let (_, model) = update(dispatch, ExplorerRequested(ExplorerFiles), model)
  assert_true(model.file_panel.explorer_mode is ExplorerFiles)
  let (_, model) = update(dispatch, ExplorerRequested(ExplorerSearch), model)
  assert_true(model.file_panel.explorer_mode is ExplorerSearch)
  assert_true(model.file_panel.tree_open)
}

///|
test "CloseAllTabs tears down mixed tabs and keeps the empty launcher open" {
  let dispatch = test_dispatch()
  let (_, browser) = update(dispatch, BrowserTabRequested, {
    ..desktop_model(),
    right_panel_open: true,
  })
  let (_, mixed) = update(dispatch, ExplorerRequested(ExplorerFiles), browser)
  let mixed = {
    ..mixed,
    right_panel_menu_open: true,
    right_panel_expanded: true,
  }
  assert_true(
    mixed.dock.tabs == [@dock.DockTab::Browser(id=1), @dock.DockTab::FilePicker],
  )
  let (_, closed) = update(dispatch, CloseAllTabs, mixed)
  assert_true(closed.dock.tabs.is_empty())
  assert_true(closed.dock.active is None)
  assert_true(@preview.page(closed.preview, 1) is None)
  assert_true(closed.right_panel_open)
  assert_false(closed.right_panel_menu_open)
  assert_false(closed.right_panel_expanded)
}

///|
test "a tree pick fulfills the active picker in place" {
  let dispatch = test_dispatch()
  let model = desktop_model()
  let (_, model) = update(dispatch, ToggleRightPanel, model)
  let (_, model) = update(dispatch, ExplorerRequested(ExplorerFiles), model)
  let (_, model) = update(
    dispatch,
    FileEditor(FileSelected(path=Relative("src/main.mbt"), name="main.mbt")),
    model,
  )
  assert_true(
    model.dock.tabs == [@dock.DockTab::File(path=Relative("src/main.mbt"))],
  )
  assert_true(@dock.active_file(model.dock) == Some(Relative("src/main.mbt")))
}

///|
test "a changed row opens the file tab in review mode" {
  let dispatch = test_dispatch()
  let model = desktop_model()
  let (_, model) = update(dispatch, ToggleRightPanel, model)
  let (_, model) = update(dispatch, ExplorerRequested(ExplorerChanges), model)
  let path = @pathx.Relative("src/main.mbt")
  let (_, model) = update(
    dispatch,
    FileEditor(
      ChangedFileSelected({
        path,
        original_path: None,
        index_status: " ",
        worktree_status: "M",
        kind: ChangeModified,
      }),
    ),
    model,
  )
  assert_true(model.dock.tabs == [@dock.DockTab::File(path~)])
  assert_true(@dock.active_file(model.dock) == Some(path))
  assert_true(
    model.file_panel.docs.get(path)
    is Some(
      {
        state: TabLoading,
        review: Some({ generation: 1, baseline: ReviewLoading, .. }),
        ..
      }
    ),
  )
}

///|
test "file rows and location jumps cannot open while checkout placement is missing" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/proj")
  let model = desktop_model()
    .replace_conversation({
      ..test_conversation(),
      workspace: Worktree(project=workspace, name="wt"),
    })
    .with_dev(dev => {
      ..dev,
      projects: [workspace],
      worktrees: [
        {
          project: workspace,
          rows: [
            {
              name: "wt",
              session: Some("desktop-test"),
              path: None,
              codex_thread: None,
              present: false,
            },
          ],
          generation: 1,
        },
      ],
    })
  let path = @pathx.Relative("src/main.mbt")
  let (_, ordinary) = update(
    dispatch,
    FileEditor(FileSelected(path~, name="main.mbt")),
    model,
  )
  assert_false(ordinary.dock.tabs.contains(@dock.DockTab::File(path~)))
  assert_false(ordinary.file_panel.docs.contains(path))
  let (_, review) = update(
    dispatch,
    FileEditor(
      ChangedFileSelected({
        path,
        original_path: None,
        index_status: " ",
        worktree_status: "M",
        kind: ChangeModified,
      }),
    ),
    model,
  )
  assert_false(review.dock.tabs.contains(@dock.DockTab::File(path~)))
  assert_false(review.file_panel.docs.contains(path))
  let (_, jumped) = update(
    dispatch,
    JumpToLocation(
      path="/proj/src/main.mbt",
      range=Some(@common.Range(1, 1, 1, 1)),
      annotation=None,
    ),
    model,
  )
  assert_false(jumped.dock.tabs.contains(@dock.DockTab::File(path~)))
  assert_false(jumped.file_panel.docs.contains(path))
  let (_, navigation) = update(
    dispatch,
    FileEditor(
      OpenNavigationLocation(
        owner=file_ctx(model).owner,
        path~,
        range=@common.Range(1, 1, 1, 1),
      ),
    ),
    model,
  )
  assert_false(navigation.dock.tabs.contains(@dock.DockTab::File(path~)))
  assert_false(navigation.file_panel.docs.contains(path))
}

///|
test "language request failures toast once and remain conversation fenced" {
  let dispatch = test_dispatch()
  let model = desktop_model()
  let owner = file_ctx(model).owner
  let msg = FileEditor(
    @fileeditor.LanguageRequestFailed(
      owner~,
      message="Go to definition failed: workspace index is unavailable",
    ),
  )
  let (_, first) = update(dispatch, msg, model)
  let (_, same_input) = update(dispatch, msg, model)
  assert_true(first.notifications == same_input.notifications)
  assert_eq(first.notification_seq, same_input.notification_seq)
  assert_eq(first.notifications.length(), 1)
  assert_eq(
    first.notifications[0].message,
    "Go to definition failed: workspace index is unavailable",
  )
  let (_, repeated) = update(dispatch, msg, first)
  assert_eq(repeated.notifications.length(), 1)
  let (_, stale) = update(
    dispatch,
    FileEditor(
      @fileeditor.LanguageRequestFailed(
        owner={ channel: Local, session: "another-conversation", },
        message="late failure",
      ),
    ),
    repeated,
  )
  assert_true(stale.notifications == repeated.notifications)
}

///|
test "file watcher failures toast once and retain lifecycle state" {
  let dispatch = test_dispatch()
  let model = desktop_model()
  let owner = file_ctx(model).owner
  let root = @interop.ChannelId::Local.test_project()
  let generation = 7
  let panel = {
    ..model.file_panel,
    owner: Some(owner),
    placement: @fileeditor.PlacementLive(@interop.WorkspaceRoot(root~)),
    watching: Some({ owner, root, files: [], directories: [], recursive: true, }),
    watch_generation: generation,
  }
  let model = { ..model, file_panel: panel, }
  // A live index keeps the recursive watcher desired while the file pane is
  // closed, so the root update's ordinary sync pass preserves this failure.
  let file_emit = dispatch.map(next => FileEditor(next))
  let (_, loading) = @fileeditor.update(
    file_emit,
    @fileeditor.EnsureFileIndex,
    panel,
    file_ctx(model),
  )
  let (_, ready) = @fileeditor.update(
    file_emit,
    @fileeditor.FilesIndexed(
      owner~,
      epoch=loading.request_epoch,
      files=[],
      truncated=false,
    ),
    loading,
    file_ctx(model),
  )
  let model = { ..model, file_panel: ready, }
  let message = "File watching stopped: too many open files"
  let failure = FileEditor(
    @fileeditor.FileWatchFailed(
      channel=owner.channel,
      root~,
      generation="\{file_ctx(model).watch_namespace}:\{generation}",
      message~,
    ),
  )
  let (_, failed) = update(dispatch, failure, model)
  assert_eq(failed.file_panel.watch_error, Some(message))
  assert_eq(failed.notifications.length(), 1)
  assert_eq(failed.notifications[0].message, message)
  // The same current-generation notification neither mutates watcher state
  // again nor stacks another toast while the first one is still visible.
  let (_, repeated) = update(dispatch, failure, failed)
  assert_eq(repeated.file_panel.watch_error, Some(message))
  assert_eq(repeated.notifications.length(), 1)
  // The file-editor package rejects a failure from another concrete watcher;
  // the root therefore has no accepted failure to announce.
  let (_, stale) = update(
    dispatch,
    FileEditor(
      @fileeditor.FileWatchFailed(
        channel=owner.channel,
        root~,
        generation="\{file_ctx(model).watch_namespace}:\{generation - 1}",
        message="stale watcher failure",
      ),
    ),
    repeated,
  )
  assert_eq(stale.file_panel.watch_error, Some(message))
  assert_eq(stale.notifications.length(), 1)
}

///|
test "web links open (and reuse) a dock browser tab; other schemes do not" {
  let dispatch = test_dispatch()
  let model = desktop_model()
  let generation = model.file_panel.file_link_generation
  let (_, model) = update(
    dispatch,
    ExternalLinkClicked("http://127.0.0.1:5173/"),
    model,
  )
  assert_true(model.right_panel_open)
  assert_eq(model.file_panel.file_link_generation, generation + 1)
  assert_true(@dock.active_browser(model.dock) == Some(1))
  assert_true(
    @preview.page(model.preview, 1).unwrap().url ==
    Some("http://127.0.0.1:5173/"),
  )
  // The terminal component forwards its semantic link action to this same
  // application policy; exercise the policy directly here.
  let (_, model) = update(
    dispatch,
    ExternalLinkClicked("https://terminal.example/docs"),
    model,
  )
  assert_eq(model.dock.tabs.length(), 2)
  assert_eq(model.file_panel.file_link_generation, generation + 2)
  assert_true(@dock.active_browser(model.dock) == Some(2))
  assert_true(
    @preview.page(model.preview, 2).unwrap().url ==
    Some("https://terminal.example/docs"),
  )
  // The same URL re-activates the existing tab instead of duplicating, and
  // the reuse re-navigates so the view cannot keep showing a stale page.
  let (_, model) = update(
    dispatch,
    ExternalLinkClicked("http://127.0.0.1:5173/"),
    model,
  )
  assert_eq(model.dock.tabs.length(), 2)
  assert_eq(model.preview.pages.length(), 2)
  assert_true(@dock.active_browser(model.dock) == Some(1))
  assert_true(
    @preview.page(model.preview, 1).unwrap().url ==
    Some("http://127.0.0.1:5173/"),
  )
  assert_true(@preview.page(model.preview, 1).unwrap().loading)
  assert_eq(model.file_panel.file_link_generation, generation + 3)
  // External sites are web pages too: they get their own tab.
  let (_, model) = update(
    dispatch,
    ExternalLinkClicked("https://github.com/moonbit"),
    model,
  )
  assert_eq(model.dock.tabs.length(), 3)
  assert_true(@dock.active_browser(model.dock) == Some(3))
  assert_eq(model.file_panel.file_link_generation, generation + 4)
  // A non-web scheme keeps the system handler: no tab appears.
  let (_, model) = update(
    dispatch,
    ExternalLinkClicked("mailto:someone@example.com"),
    model,
  )
  assert_eq(model.dock.tabs.length(), 3)
  assert_eq(model.file_panel.file_link_generation, generation + 4)
  // So does a link clicked on another screen, where the dock is not on
  // screen to show a tab — Settings' device-page link wants the browser the
  // user is signed in to anyway.
  let (_, settings) = update(
    dispatch,
    ExternalLinkClicked("https://openseek.test/d/abc"),
    { ..model, screen: Settings, },
  )
  assert_eq(settings.dock.tabs.length(), 3)
  assert_eq(settings.preview.pages.length(), 3)
  assert_eq(settings.file_panel.file_link_generation, generation + 4)
}

///|
test "Codex web links use the same dock browser route as OpenSeek" {
  let dispatch = test_dispatch()
  let codex = @codex.State::from_thread_snapshot({
    "thread": {
      "id": "codex-thread-1",
      "preview": "Open its pull request",
      "cwd": "/work/codex-project",
      "turns": [],
    },
  })
  // Exercise the same root transition as a sidebar click. It selects the
  // Codex screen and, before a later PR click can arrive, reconciles the live
  // dock strip from the OpenSeek conversation owner to this Codex task.
  let (_, model) = update(dispatch, CodexOpenThread("codex-thread-1"), {
    ..desktop_model(),
    codex,
  })
  let (_, model) = update(
    dispatch,
    ExternalLinkClicked("https://github.com/moonbit-community/pty/pull/18"),
    model,
  )
  assert_true(model.right_panel_open)
  assert_true(@dock.active_browser(model.dock) == Some(1))
  assert_true(
    @preview.page(model.preview, 1).unwrap().url ==
    Some("https://github.com/moonbit-community/pty/pull/18"),
  )
}

///|
test "same-URL reuse scans this strip, not the global page map" {
  let dispatch = test_dispatch()
  let url = "http://127.0.0.1:5173/"
  // Another conversation's parked strip already holds this URL: its page
  // sits in the global map with no tab in this strip. It must not shadow
  // this strip's own tab.
  let (foreign, _) = @preview.open_page(@preview.State::empty(), url~)
  let model = { ..desktop_model(), preview: foreign, }
  let (_, model) = update(dispatch, ExternalLinkClicked(url), model)
  assert_eq(model.dock.tabs.length(), 1)
  assert_eq(model.preview.pages.length(), 2)
  // A repeat click re-activates this strip's tab instead of stacking a
  // duplicate per click.
  let (_, model) = update(dispatch, ExternalLinkClicked(url), model)
  assert_eq(model.dock.tabs.length(), 1)
  assert_eq(model.preview.pages.length(), 2)
}

///|
test "a remote console routes loopback links to the system browser too" {
  let dispatch = test_dispatch()
  // test_model is desktop-shaped except for the flag; without native views
  // the dock must not grow browser tabs.
  let model = test_model()
  let (_, model) = update(
    dispatch,
    ExternalLinkClicked("http://127.0.0.1:5173/"),
    model,
  )
  assert_true(model.dock.tabs.is_empty())
  assert_true(model.preview.pages.is_empty())
}

///|
test "re-clicking a chat link re-navigates the reused tab to the clicked URL" {
  // The reuse matched the page's optimistic URL mirror, which can have
  // drifted from what the native view shows — the clicked link must win over
  // whatever the tab currently displays, and the stale pane placement must
  // not survive a possibly rebuilt view (#1021).
  let dispatch = test_dispatch()
  let model = desktop_model()
  let (_, model) = update(
    dispatch,
    ExternalLinkClicked("http://127.0.0.1:5173/"),
    model,
  )
  let rect : @preview.Rect = { x: 480, y: 46, width: 640, height: 700, }
  let (_, model) = update(dispatch, BrowserPaneMeasured(rect~), model)
  assert_true(model.browser_pane.shown == Some(1))
  let (_, model) = update(
    dispatch,
    ExternalLinkClicked("https://github.com/moonbit"),
    model,
  )
  assert_true(@dock.active_browser(model.dock) == Some(2))
  // Back to the first link: its tab re-activates AND re-navigates.
  let (_, model) = update(
    dispatch,
    ExternalLinkClicked("http://127.0.0.1:5173/"),
    model,
  )
  assert_eq(model.dock.tabs.length(), 2)
  assert_true(@dock.active_browser(model.dock) == Some(1))
  let page = @preview.page(model.preview, 1).unwrap()
  assert_true(page.url == Some("http://127.0.0.1:5173/"))
  assert_eq(page.input, "http://127.0.0.1:5173/")
  assert_true(page.loading)
  assert_true(page.failure is None)
  // A rebuilt view arrives hidden at a placeholder size, so the placement
  // the old view had is dropped for the next sync to re-measure.
  assert_true(model.browser_pane.shown is None)
  assert_true(model.browser_pane.rect is None)
  // …and the re-measure places the view again.
  let (_, model) = update(dispatch, BrowserPaneMeasured(rect~), model)
  assert_true(model.browser_pane.shown == Some(1))
  assert_true(model.browser_pane.rect == Some(rect))
}

///|
test "submitting the address bar normalizes the draft and commits it" {
  let dispatch = test_dispatch()
  let model = desktop_model()
  let (_, model) = update(dispatch, ToggleRightPanel, model)
  let (_, model) = update(dispatch, BrowserTabRequested, model)
  let (_, model) = update(
    dispatch,
    BrowserAddressEdited("localhost:5173"),
    model,
  )
  let generation = model.file_panel.file_link_generation
  let (_, model) = update(dispatch, BrowserNavigateSubmitted, model)
  let page = @preview.page(model.preview, 1).unwrap()
  assert_true(page.url == Some("http://localhost:5173"))
  assert_eq(page.input, "http://localhost:5173")
  assert_true(page.loading)
  assert_eq(model.file_panel.file_link_generation, generation + 1)
  // A non-navigable draft changes nothing — including a bare scheme, which
  // the host would reject after the URL had already been committed.
  let (_, edited) = update(dispatch, BrowserAddressEdited("two words"), model)
  let (_, unchanged) = update(dispatch, BrowserNavigateSubmitted, edited)
  assert_true(
    @preview.page(unchanged.preview, 1).unwrap().url ==
    Some("http://localhost:5173"),
  )
  assert_eq(
    unchanged.file_panel.file_link_generation,
    model.file_panel.file_link_generation,
  )
  let (_, edited) = update(dispatch, BrowserAddressEdited("http://"), unchanged)
  let (_, still) = update(dispatch, BrowserNavigateSubmitted, edited)
  assert_true(
    @preview.page(still.preview, 1).unwrap().url ==
    Some("http://localhost:5173"),
  )
  assert_eq(
    still.file_panel.file_link_generation,
    model.file_panel.file_link_generation,
  )
}

///|
test "navigating an already-placed tab re-places its view" {
  let dispatch = test_dispatch()
  let model = desktop_model()
  let (_, model) = update(
    dispatch,
    ExternalLinkClicked("http://127.0.0.1:5173/"),
    model,
  )
  let rect : @preview.Rect = { x: 480, y: 46, width: 640, height: 700, }
  let (_, model) = update(dispatch, BrowserPaneMeasured(rect~), model)
  assert_true(model.browser_pane.shown == Some(1))
  // The host may have rebuilt the view under `browser.navigate` (nothing
  // acknowledges the ops that placed the old one), and a rebuilt view is
  // hidden at a placeholder size. Keeping the placement would leave the tab
  // blank until an unrelated resize, so the submission drops it…
  let (_, edited) = update(
    dispatch,
    BrowserAddressEdited("https://github.com/moonbit"),
    model,
  )
  let (_, navigated) = update(dispatch, BrowserNavigateSubmitted, edited)
  assert_true(navigated.browser_pane.shown is None)
  assert_true(navigated.browser_pane.rect is None)
  // …and the re-measure it provokes places the view again.
  let (_, replaced) = update(dispatch, BrowserPaneMeasured(rect~), navigated)
  assert_true(replaced.browser_pane.shown == Some(1))
  assert_true(replaced.browser_pane.rect == Some(rect))
}

///|
test "Search reuses the picker and keeps a request when its Explorer tab leaves" {
  let dispatch = test_dispatch()
  let (_, opened) = update(
    dispatch,
    ExplorerRequested(ExplorerSearch),
    desktop_model(),
  )
  assert_true(opened.right_panel_open)
  assert_true(opened.dock.active is Some(@dock.DockTab::FilePicker))
  assert_true(opened.dock.tabs == [@dock.DockTab::FilePicker])
  assert_true(opened.file_panel.explorer_mode is ExplorerSearch)
  assert_true(opened.file_panel.tree_open)
  let (_, reopened_picker) = update(
    dispatch,
    ExplorerRequested(ExplorerSearch),
    opened,
  )
  assert_true(reopened_picker.dock.tabs == [@dock.DockTab::FilePicker])
  let (_, edited) = update(
    dispatch,
    FileEditor(Search(@grep_search.QueryChanged("moon"))),
    reopened_picker,
  )
  let (_, running) = update(
    dispatch,
    FileEditor(Search(@grep_search.Submit)),
    edited,
  )
  let (_, files) = update(
    dispatch,
    FileEditor(@fileeditor.ExplorerModeSelected(ExplorerFiles)),
    running,
  )
  let (_, reopened) = update(dispatch, ExplorerRequested(ExplorerSearch), files)
  assert_true(reopened.dock.tabs == [@dock.DockTab::FilePicker])
  assert_true(reopened.file_panel.explorer_mode is ExplorerSearch)
}

///|
test "a Search result fulfills the picker while preserving Search beside the file" {
  let dispatch = test_dispatch()
  let (_, opened) = update(
    dispatch,
    ExplorerRequested(ExplorerSearch),
    desktop_model(),
  )
  let (_, edited) = update(
    dispatch,
    FileEditor(Search(@grep_search.QueryChanged("moon"))),
    opened,
  )
  let path = @pathx.Relative("src/main.mbt")
  let range = @common.Range(4, 2, 4, 6)
  let (_, selected) = update(
    dispatch,
    FileEditor(SearchMatchSelected(path=path.0, range~)),
    edited,
  )
  assert_true(selected.dock.tabs == [@dock.DockTab::File(path~)])
  assert_true(@dock.active_file(selected.dock) == Some(path))
  assert_true(selected.file_panel.explorer_mode is ExplorerSearch)
  assert_true(selected.file_panel.tree_open)
  assert_true(
    selected.file_panel.docs.get(path)
    is Some({ review: None, state: TabLoading, .. }),
  )

  // Opening Search again appends the one shared picker. Picking the already
  // open file removes that picker and activates the existing file tab.
  let (_, picker) = update(
    dispatch,
    ExplorerRequested(ExplorerSearch),
    selected,
  )
  assert_true(
    picker.dock.tabs == [@dock.DockTab::File(path~), @dock.DockTab::FilePicker],
  )
  let (_, reused) = update(
    dispatch,
    FileEditor(SearchMatchSelected(path=path.0, range~)),
    picker,
  )
  assert_true(reused.dock.tabs == [@dock.DockTab::File(path~)])
  assert_true(@dock.active_file(reused.dock) == Some(path))
  assert_true(reused.file_panel.explorer_mode is ExplorerSearch)
}

///|
test "narrow Search drill-down hides and restores the retained Explorer" {
  let dispatch = test_dispatch()
  let (_, narrow) = update(
    dispatch,
    ViewportResized(width=390),
    desktop_model(),
  )
  let (_, opened) = update(dispatch, ExplorerRequested(ExplorerSearch), narrow)
  let (_, edited) = update(
    dispatch,
    FileEditor(Search(@grep_search.QueryChanged("needle"))),
    opened,
  )
  let path = @pathx.Relative("src/narrow.mbt")
  let range = @common.Range(1, 1, 1, 7)
  let (_, drilled) = update(
    dispatch,
    FileEditor(SearchMatchSelected(path=path.0, range~)),
    edited,
  )
  assert_true(drilled.file_panel.explorer_mode is ExplorerSearch)
  assert_false(drilled.file_panel.tree_open)
  let (_, restored) = update(
    dispatch,
    FileEditor(@fileeditor.ToggleTree),
    drilled,
  )
  assert_true(restored.file_panel.tree_open)
  assert_true(restored.file_panel.explorer_mode is ExplorerSearch)
}

///|
test "Search requests survive hidden Explorer Browser and panel states" {
  let dispatch = test_dispatch()
  let (_, opened) = update(
    dispatch,
    ExplorerRequested(ExplorerSearch),
    desktop_model(),
  )
  let path = @pathx.Relative("src/main.mbt")
  let range = @common.Range(2, 1, 2, 5)
  let (_, file) = update(
    dispatch,
    FileEditor(SearchMatchSelected(path=path.0, range~)),
    opened,
  )
  let (_, edited) = update(
    dispatch,
    FileEditor(Search(@grep_search.QueryChanged("moon"))),
    file,
  )
  let (_, running) = update(
    dispatch,
    FileEditor(Search(@grep_search.Submit)),
    edited,
  )

  let (_, tree_hidden) = update(
    dispatch,
    FileEditor(@fileeditor.ToggleTree),
    running,
  )
  let (_, browser) = update(dispatch, BrowserTabRequested, tree_hidden)
  let (_, panel_closed) = update(dispatch, ToggleRightPanel, browser)
  assert_false(panel_closed.right_panel_open)
}

///|
test "pane measurements place the active view and idempotently settle" {
  let dispatch = test_dispatch()
  let model = desktop_model()
  let (_, model) = update(
    dispatch,
    ExternalLinkClicked("http://127.0.0.1:5173/"),
    model,
  )
  let rect : @preview.Rect = { x: 480, y: 46, width: 640, height: 700, }
  let (_, model) = update(dispatch, BrowserPaneMeasured(rect~), model)
  assert_true(model.browser_pane.shown == Some(1))
  assert_true(model.browser_pane.rect == Some(rect))
  let (_, again) = update(dispatch, BrowserPaneMeasured(rect~), model)
  assert_true(again == model)
  // A zero-size measurement (the observer firing against a hidden pane)
  // never places the view.
  let zero : @preview.Rect = { x: 0, y: 0, width: 0, height: 0, }
  let (_, still) = update(dispatch, BrowserPaneMeasured(rect=zero), model)
  assert_true(still.browser_pane.rect == Some(rect))
}

///|
test "the launcher popup and final tab close both retire the shown view" {
  let dispatch = test_dispatch()
  let model = desktop_model()
  let (_, model) = update(
    dispatch,
    ExternalLinkClicked("http://127.0.0.1:5173/"),
    model,
  )
  let rect : @preview.Rect = { x: 480, y: 46, width: 640, height: 700, }
  let (_, model) = update(dispatch, BrowserPaneMeasured(rect~), model)
  assert_true(model.browser_pane.shown == Some(1))
  // The popup overlaps the pane, so the native view must hide under it.
  let (_, covered) = update(dispatch, ToggleRightPanelMenu, model)
  assert_true(covered.browser_pane.shown is None)
  // Closing the tab drops the page and the placement.
  let closing = { ..model, right_panel_expanded: true, }
  let (_, closed) = update(
    dispatch,
    Dock(TabClosed(@dock.DockTab::Browser(id=1))),
    closing,
  )
  let (_, closed_again) = update(
    dispatch,
    Dock(TabClosed(@dock.DockTab::Browser(id=1))),
    closing,
  )
  assert_true(closed_again == closed)
  assert_true(closed.browser_pane.shown is None)
  assert_true(@preview.page(closed.preview, 1) is None)
  assert_true(closed.dock.tabs.is_empty())
  assert_false(closed.right_panel_open)
  assert_false(closed.right_panel_menu_open)
  assert_false(closed.right_panel_expanded)
}

///|
test "closing a background Browser tab keeps the shown view placement" {
  let dispatch = test_dispatch()
  let (_, first) = update(
    dispatch,
    ExternalLinkClicked("http://127.0.0.1:5173/one"),
    desktop_model(),
  )
  let (_, second) = update(
    dispatch,
    ExternalLinkClicked("http://127.0.0.1:5173/two"),
    first,
  )
  let rect : @preview.Rect = { x: 480, y: 46, width: 640, height: 700, }
  let (_, shown) = update(dispatch, BrowserPaneMeasured(rect~), second)
  assert_true(shown.browser_pane.shown == Some(2))
  let (_, closed) = update(
    dispatch,
    Dock(TabClosed(@dock.DockTab::Browser(id=1))),
    shown,
  )
  assert_true(closed.browser_pane.shown == Some(2))
  assert_true(closed.browser_pane.rect == Some(rect))
  assert_true(@preview.page(closed.preview, 1) is None)
  assert_true(@preview.page(closed.preview, 2) is Some(_))
  assert_true(closed.right_panel_open)
}

///|
test "full-screen modals hide the native view and closing restores it" {
  let dispatch = test_dispatch()
  let model = desktop_model()
  let (_, model) = update(
    dispatch,
    ExternalLinkClicked("http://127.0.0.1:5173/"),
    model,
  )
  let rect : @preview.Rect = { x: 480, y: 46, width: 640, height: 700, }
  let (_, model) = update(dispatch, BrowserPaneMeasured(rect~), model)
  assert_true(model.browser_pane.shown == Some(1))
  // The workspace picker's modal covers the pane; native views z-order
  // above HTML, so the view must hide first.
  let (_, covered) = update(dispatch, PickProject(Local), model)
  assert_true(covered.project_picker is Some(_))
  assert_true(covered.browser_pane.shown is None)
  // Closing the modal re-measures; the next measurement re-places the view.
  let (_, closed) = update(
    dispatch,
    ProjectPicker(@project_picker.Msg::Close),
    covered,
  )
  let (_, restored) = update(dispatch, BrowserPaneMeasured(rect~), closed)
  assert_true(restored.browser_pane.shown == Some(1))
  // Setup API owns the whole screen too. The browser is a native view above
  // the HTML shell, so opening the modal must hide it; dismissing the modal
  // then re-measures and restores the active Browser tab.
  let (_, setup) = update(dispatch, ProviderChanged("custom"), restored)
  assert_true(setup.api_setup_open)
  assert_true(setup.browser_pane.shown is None)
  let (_, setup_closed) = update(dispatch, DismissApiSetup, setup)
  assert_false(setup_closed.api_setup_open)
  let (_, setup_restored) = update(
    dispatch,
    BrowserPaneMeasured(rect~),
    setup_closed,
  )
  assert_true(setup_restored.browser_pane.shown == Some(1))
  // The composer's git popover opens upward over the pane's bottom-left
  // corner, so a native view left showing would paint straight over it. The
  // popover needs a branch to have a trigger at all, so give the
  // conversation one before opening it.
  let (_, on_branch) = update_dev(dispatch, branch_reply("feature/x"), restored)
  let (_, detailing) = update(dispatch, ToggleGitDetails, on_branch)
  assert_true(detailing.browser_pane.shown is None)
  // So do the other two surfaces `view.mbt` appends beside the picker: the
  // archive-discard confirmation and Quick Open.
  let (_, archiving) = update_dev(
    dispatch,
    ArchiveNeedsForce(session="desktop-test", refusal={
      worktree: "wt-1",
      dirty_paths: ["desktop/lepus"],
      dirty_path_count: 1,
    }),
    restored,
  )
  assert_true(archiving.archive_confirm is Some(_))
  assert_true(archiving.browser_pane.shown is None)
  let (_, searching) = update(
    dispatch,
    QuickOpenOpen(@quick_open.Symbols),
    restored,
  )
  assert_true(searching.quick_open.is_open())
  assert_true(searching.browser_pane.shown is None)
}

///|
/// Test-only: a page whose parent conversation owns one sub-run lane and whose
/// store also holds that sub-run's child transcript.
fn subrun_page(active~ : String, child_sync? : TranscriptSync) -> Model {
  let lane : @subrun.Lane = {
    id: "sr-1",
    kind: "explore",
    label: "where is X",
    steps: 0,
    activity: "",
    run: Some("r7"),
  }
  let base = running_conversation()
  let parent = { ..base, turn: { ..base.turn, subruns: [lane], }, }
  let child = {
    ..empty_conversation(
      @interop.ChannelId::Local,
      "desktop-test-sr-1",
      @interop.ChannelId::Local.test_project(),
    )
    // A child already read once. The positive watermark is what proves a
    // durable record exists, which is `can_reload_transcript`'s gate.
    ,
    watermark: 4,
    sync: child_sync.unwrap_or(Synced),
  }
  {
    ..test_model().replace_conversation(parent).replace_conversation(child),
    active_session: active,
  }
}

///|
fn subrun_child_of(model : Model) -> Conversation raise {
  guard model.find_conversation(@interop.ChannelId::Local, "desktop-test-sr-1")
    is Some(child) else {
    fail("expected the sub-run's child conversation")
  }
  child
}

///|
test "a sub-run's progress refreshes the child transcript on screen" {
  // No follower broadcasts a child's commits, so this probe push is the only
  // thing that can move a transcript the reader opened mid-run.
  let page = subrun_page(active="desktop-test-sr-1")
  let (_, next) = update_dev(
    test_dispatch(),
    SubrunProgressed(
      id="sr-1",
      session="desktop-test-sr-1",
      steps=3,
      activity="shell",
    ),
    page,
  )
  // A fresh generation was minted for the read. `Cmd` is opaque, so this is
  // what separates an issued load from a conversation parked in `Reloading`
  // with nothing on the way to settle it.
  let generation = page.transcript_request_generation + 1
  assert_eq(next.transcript_request_generation, generation)
  guard subrun_child_of(next).sync
    is Reloading(generation=minted, reload_after_current=false, ..) else {
    fail("expected the viewed child to start a background reload")
  }
  assert_eq(minted, generation)
  // The reply that generation fences is accepted and adopted, proving the read
  // this started is one the model can actually settle.
  let (_, settled) = update_dev(
    test_dispatch(),
    SessionRefreshed(
      session="desktop-test-sr-1",
      items=[
        {
          kind: Assistant(
            reasoning=Some("child thought"),
            prose=None,
            calls=[],
            replay=false,
            finished=false,
          ),
          ts: None,
          sequence: Some(5),
        },
      ],
      watermark=5,
      goal=None,
      goal_markers=[],
      generation~,
    ),
    next,
  )
  let child = subrun_child_of(settled)
  assert_true(child.sync is Synced)
  assert_eq(child.watermark, 5)
  assert_eq(child.messages.length(), 1)
  // The parent's lane still advances: the two readers are independent.
  guard next.find_conversation(@interop.ChannelId::Local, "desktop-test")
    is Some(parent) else {
    fail("expected the parent conversation to survive")
  }
  assert_eq(parent.turn.subruns[0].steps, 3)
  assert_eq(parent.turn.subruns[0].activity, "shell")
}

///|
test "a sub-run's progress leaves a child nobody is viewing alone" {
  // Reading the parent while its child works is the ordinary case; re-reading
  // a record no one is looking at is work with no reader.
  let (_, next) = update_dev(
    test_dispatch(),
    SubrunProgressed(
      id="sr-1",
      session="desktop-test-sr-1",
      steps=3,
      activity="shell",
    ),
    subrun_page(active="desktop-test"),
  )
  assert_true(subrun_child_of(next).sync is Synced)
  guard next.find_conversation(@interop.ChannelId::Local, "desktop-test")
    is Some(parent) else {
    fail("expected the parent conversation to survive")
  }
  assert_eq(parent.turn.subruns[0].steps, 3)
}

///|
test "progress during an in-flight read is coalesced, not dropped" {
  // `begin_transcript_reload` would answer this with `None` and lose the
  // signal. The probe publishes only when the child ADVANCED, so a dropped
  // signal can be the last one ever sent — the transcript would then sit one
  // step short with nothing left to correct it.
  let (_, next) = update_dev(
    test_dispatch(),
    SubrunProgressed(
      id="sr-1",
      session="desktop-test-sr-1",
      steps=3,
      activity="shell",
    ),
    subrun_page(
      active="desktop-test-sr-1",
      child_sync=Reloading(
        generation=1,
        attempt=1,
        buffered=[],
        reload_after_current=false,
      ),
    ),
  )
  guard subrun_child_of(next).sync
    is Reloading(generation=1, reload_after_current=true, ..) else {
    fail("expected the in-flight read to be followed by one fresh generation")
  }
}

///|
test "a lane whose parent is gone still refreshes the child on screen" {
  // The lane update must not be a precondition for the refresh: they answer
  // to different conversations.
  let page = subrun_page(active="desktop-test-sr-1")
  let orphaned = {
    ..page,
    conversations: page.conversations.filter(conv => {
      conv.session_id != "desktop-test"
    }),
  }
  let (_, next) = update_dev(
    test_dispatch(),
    SubrunProgressed(
      id="sr-1",
      session="desktop-test-sr-1",
      steps=3,
      activity="shell",
    ),
    orphaned,
  )
  guard subrun_child_of(next).sync is Reloading(..) else {
    fail("expected the viewed child to reload without its parent")
  }
}

///|
test "a sub-run's finish refreshes the child transcript one last time" {
  // The host cancels the progress probe at the finish bracket without a final
  // poll, and the probe sleeps before it reads — so the child's last writes,
  // its report among them, arrive here or nowhere.
  let page = subrun_page(active="desktop-test-sr-1")
  let (_, next) = update_dev(
    test_dispatch(),
    Engine(
      Some("r7"),
      SubrunClosed(id="sr-1", status="captured", steps=7, tokens=30),
      session=None,
    ),
    page,
  )
  assert_eq(
    next.transcript_request_generation,
    page.transcript_request_generation + 1,
  )
  guard subrun_child_of(next).sync is Reloading(..) else {
    fail("expected the finish to catch the child transcript up")
  }
}

///|
/// A workflow's brackets record the run, and the sub-run brackets the host
/// synthesizes from its sidecar give the run its rows — the SAME bracket that
/// opens a child's lane. A sub-run outside the run's reserved block is an
/// ordinary child and touches no row.
test "a workflow's brackets and its children's brackets build the run's rows" {
  let conv = { ..test_conversation(), run: Open(run_id="r1", stage=Opened), }
  let (_, opened) = apply_engine_event(
    conv,
    WorkflowOpened(
      id="wf-5",
      journal="/store/run-wf-5/journal.jsonl",
      events="/store/run-wf-5/events.jsonl",
      first_child=5,
      child_count=32,
    ),
    Some("r1"),
  )
  inspect(opened.workflows.length(), content="1")
  let (_, child) = apply_engine_event(
    opened,
    SubrunOpened(id="sr-5", kind="explore", label="scout:x"),
    Some("r1"),
  )
  inspect(child.visible_subruns().length(), content="1")
  inspect(child.workflows[0].rows.length(), content="1")
  inspect(child.workflows[0].running(), content="1")
  let (_, other) = apply_engine_event(
    child,
    SubrunOpened(id="sr-2", kind="explore", label="elsewhere"),
    Some("r1"),
  )
  inspect(other.visible_subruns().length(), content="2")
  inspect(other.workflows[0].rows.length(), content="1")
  let (_, closed) = apply_engine_event(
    other,
    SubrunClosed(id="sr-5", status="captured", steps=12, tokens=3400),
    Some("r1"),
  )
  inspect(closed.workflows[0].running(), content="0")
  inspect(closed.workflows[0].rows[0].steps, content="12")
  // The lane is gone, as for any captured sub-run; the row stays.
  inspect(closed.visible_subruns().length(), content="1")
  let (_, done) = apply_engine_event(
    closed,
    WorkflowClosed(id="wf-5"),
    Some("r1"),
  )
  inspect(done.workflows[0].closed, content="true")
  inspect(done.workflows[0].rows.length(), content="1")
}

///|
/// A resolved call reaches the run through the parent session the entry
/// names. A conversation this page does not hold gets nothing: only a bracket
/// knows a run exists, and an entry is never a reason to invent one.
test "a workflow entry refines the parent conversation's run" {
  let base = running_conversation()
  let parent = {
    ..base,
    workflows: @workflow.opened(
      [],
      id="wf-5",
      session=base.session_id,
      first_child=5,
      child_count=32,
    ),
  }
  let model = test_model().replace_conversation(parent)
  let entry : @workflow.Entry = {
    workflow: "wf-5",
    session: base.session_id,
    child: "\{base.session_id}-sr-5",
    kind: "explore",
    label: "scout:x",
    phase: Some("survey"),
    status: "captured",
    steps: 12,
    prompt_tokens: 3000,
    completion_tokens: 400,
    cost_usd: Some(0.01),
    started_at: Some(1788535817640.0),
    finished_at: Some(1788535817648.0),
  }
  let (_, next) = update_dev(
    test_dispatch(),
    WorkflowEntryArrived(@interop.ChannelId::Local, entry),
    model,
  )
  guard next.find_conversation(@interop.ChannelId::Local, base.session_id)
    is Some(conv) else {
    fail("expected the parent conversation")
  }
  inspect(conv.workflows[0].rows.length(), content="1")
  inspect(conv.workflows[0].rows[0].ordinal, content="5")
  debug_inspect(conv.workflows[0].rows[0].phase, content="Some(\"survey\")")
  debug_inspect(conv.workflows[0].cost_usd(), content="Some(0.01)")
  let (_, same) = update_dev(
    test_dispatch(),
    WorkflowEntryArrived(@interop.ChannelId::Local, {
      ..entry,
      session: "elsewhere",
    }),
    next,
  )
  assert_true(
    same.find_conversation(@interop.ChannelId::Local, "elsewhere") is None,
  )
  guard same.find_conversation(@interop.ChannelId::Local, base.session_id)
    is Some(untouched) else {
    fail("expected the parent conversation")
  }
  inspect(untouched.workflows[0].rows.length(), content="1")
}
