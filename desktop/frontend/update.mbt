///|
const TranscriptReloadMaxAttempts : Int = 3

///|
const ArchivedPendingInputNotice : String = "This conversation was archived while a prompt was being sent. The input was restored here; check the archived transcript before resubmitting."

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
  let workspace = model.session_project(channel, session)
  if activate_on_success {
    open_session(dispatch, channel, session, workspace~, generation~)
  } else {
    refresh_session(dispatch, channel, session, workspace~, generation~)
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
      loading_conversation: None,
      installed_skills: [],
      completion: None,
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
  let owner : @interop.ConversationKey = { channel, session: session_id }
  if session_id == model.active_session {
    let base = { ..model, screen: Chat, completion: None }
    // Re-selecting is an explicit catch-up point for writes made by an
    // idle CLI or another client. It also restarts an exhausted retry
    // round; an existing request stays single-flight. A fresh chat has no
    // durable record to read, including when returning here from Skills.
    match model.find_conversation(channel, session_id) {
      Some(conv) if !(conv.sync is Reloading(..)) &&
        model.can_reload_transcript(conv) => {
        let (next, generation) = base.begin_transcript_reload(conv)
        let next = { ..next, loading_conversation: Some(owner) }
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
      ..model.activate(channel, session_id),
      screen: Chat,
      loading_conversation: if generation is Some(_) {
        Some(owner)
      } else {
        None
      },
      completion: None,
    }.with_active_project(conv.workspace.project())
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
    let project = model.session_project(channel, session_id)
    let conversation = empty_conversation(
      channel,
      session_id,
      project?,
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
    let next = { ..model, screen: Chat, loading_conversation: Some(owner) }.with_active_project(
      project,
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
/// or rotate into a fresh scratch chat when none remains.
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
      (Some(target), { ..model, pending_project_adoption: None })
    _ => (None, model)
  }
  let active_detached = channel == model.focused &&
    model.find_conversation(channel, model.active_session) is Some(active) &&
    active.workspace.project() is Some(workspace) &&
    !paths.contains(workspace)
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
  let sessions = dev.sessions.filter(item => {
    item.workspace is None ||
    (item.workspace is Some(workspace) && paths.contains(workspace))
  })
  let conversations = model.conversations.filter(conv => {
    conv.device != channel ||
    conv.workspace is Scratch ||
    (conv.workspace.project() is Some(project) && paths.contains(project))
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
    // A detached workspace takes its open "…" menu and its settings page
    // with it; both address a row that no longer exists.
    project_menu: match model.project_menu {
      Some(menu) if menu.channel == channel && !paths.contains(menu.project) =>
        None
      menu => menu
    },
    screen: match model.screen {
      WorkspaceSettings(channel=owner, workspace~) if owner == channel &&
        !paths.contains(workspace) => Chat
      screen => screen
    },
  })
  commands.push(refresh_cmd)
  if active_detached {
    if focus_target is Some(project) {
      // This snapshot both removed the active conversation's project and
      // carries the row the user just added: the explicit add-and-focus
      // wins over fallback selection. NewChatIn rotates the fresh chat; the
      // dead session identity clears now so no render can address it while
      // the rotation is in flight (same rule as the scratch fallback
      // below).
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
          loading_conversation: None,
          screen: Chat,
          completion: None,
        },
      )
    }
    if sessions.get(0) is Some(fallback) {
      // The retained list is newest-first. Activate its first entry before
      // starting the reload so no render can address the detached session id
      // as an empty scratch conversation while the snapshot is in flight.
      let activated = next
        .activate(channel, fallback.id)
        .with_active_project(fallback.workspace)
      // The session list names only the project store. Reconcile that broad
      // placement with the registry and any already-known conversation before
      // reloading: a retained Worktree must not be downgraded to Project, while
      // a session not yet materialized on this page still initializes from its
      // listed project.
      let fallback_conv = activated.active()
      let activated = activated.replace_conversation({
        ..fallback_conv,
        workspace: dev.conversation_workspace(
          fallback.workspace,
          fallback.id,
          fallback_conv.workspace,
        ),
      })
      let (fallback_cmd, next) = open_session_on(
        dispatch,
        channel,
        activated,
        fallback.id,
      )
      commands.push(fallback_cmd)
      return (@cmd.batch(commands), next)
    }
    // Session ids are generated inside a Cmd so update remains pure. Clear
    // the dead identity now; SessionRotated installs the fresh scratch chat
    // on the next update-loop turn, exactly as it does at app startup.
    commands.push(rotate_session(dispatch, channel))
    return (
      @cmd.batch(commands),
      {
        ..next,
        active_session: "",
        loading_conversation: None,
        screen: Chat,
        completion: None,
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
  (@cmd.batch(commands), next)
}

///|
/// Retry one failed generation without losing commits that arrived while its
/// snapshot was in flight. Three attempts form one bounded round. Exhaustion
/// keeps the buffer and a visible local notice; a later commit/reconnect/open
/// starts a fresh generation.
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
    }.append_local_notice_once(
      Assistant(is_danger=true),
      TranscriptRefreshFailedNotice,
    )
    let next = model.replace_conversation(failed)
    let scroll = @cmd.none
    let owner : @interop.ConversationKey = { channel, session }
    if activate_on_success && model.loading_conversation == Some(owner) {
      let (toast, next) = next.notify_error(dispatch, message)
      let (sessions, next) = request_sessions_refresh(dispatch, channel, next)
      (
        @cmd.batch([toast, sessions, scroll]),
        { ..next, loading_conversation: None },
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
  event_boundaries : Array[(Int, Bool, Int)],
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
    event_boundaries,
    goal~,
    goal_markers~,
  )
  let mut next = model.replace_conversation(conv)
  let commands : Array[@cmd.Cmd] = []
  let owner : @interop.ConversationKey = { channel, session }
  if activate_on_success && model.loading_conversation == Some(owner) {
    next = {
      ..next.activate(channel, session),
      loading_conversation: None,
      completion: None,
    }
    let (branch_cmd, probed) = probe_branch(
      dispatch,
      next,
      channel,
      session,
      next.conversation_root(next.active()),
    )
    next = probed
    commands.push(branch_cmd)
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
    | RuntimeUpdate(_) => true
    _ => false
  }
}

///|
fn is_steer_receipt(event : @transcript.EngineEvent) -> Bool {
  event is (SteerApplied(..) | SteerDropped(..))
}

///|
/// Apply an accepted completion row: a slash command runs its action, while a
/// skill, symbol, or file reference becomes a chip in the composer's mention
/// tray (its expansion is spliced into the prompt on send). Either way the menu
/// closes and only the typed trigger token is removed from the textarea.
fn accept_completion(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  menu : Completion,
  item : CompletionItem,
) -> (@cmd.Cmd, Model) {
  match menu.kind {
    SlashCommands => run_slash_command(dispatch, model, item.command)
    // The chip carries its envelope form directly: the skill's bare name (its
    // `insert` has a trailing space), or the symbol's name plus resolved
    // location.
    SkillMentions =>
      accept_mention(
        model,
        Skill(name=item.insert.trim().to_owned()),
        range=None,
        task=menu.menu.draft_without_token(),
      )
    Symbols => {
      let (file, line) = if item.path is Some(path) && item.range is Some(range) {
        (path, range.start_line_number)
      } else {
        ("", 0)
      }
      accept_mention(
        model,
        Symbol(name=item.label, file~, line~),
        range=item.range,
        task=menu.menu.draft_without_token(),
      )
    }
    Files =>
      if item.path is Some(path) {
        accept_mention(
          model,
          File(path~),
          range=None,
          task=menu.menu.draft_without_token(),
        )
      } else {
        (@cmd.none, { ..model, completion: None })
      }
  }
}

///|
/// Attach a mention chip to the active conversation's draft (deduplicated),
/// remove the typed trigger token while preserving preceding prompt text, and
/// close the menu.
fn accept_mention(
  model : Model,
  ref_ : @mention_context.MentionRef,
  range~ : @common.Range?,
  task~ : String,
) -> (@cmd.Cmd, Model) {
  let conv = model.active()
  let mentions = push_mention(conv.mentions, { ref_, range })
  (
    @cmd.none,
    {
      ..model.replace_conversation({ ..conv, task, mentions }),
      completion: None,
    },
  )
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
    None | Some(Browser(_)) => @dock.open_picker(model.dock)
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
  let model = { ..model, file_panel: panel }
  if path.is_root() || panel.expanded.contains(path) {
    return (cmd, model)
  }
  let (expand_cmd, panel) = @fileeditor.update(
    dispatch.map(msg => FileEditor(msg)),
    @fileeditor.DirToggle(path),
    panel,
    file_ctx(model),
  )
  (@cmd.batch([cmd, expand_cmd]), { ..model, file_panel: panel })
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
  let conv = model.active()
  let placement = model.checkout_placement(conv)
  // Chip/transcript jumps call the file-editor package directly rather than
  // passing through its guarded message dispatcher. Keep them parked too: the
  // dock must not grow a loading tab, nor may a host read start, while checkout
  // placement is unresolved or missing.
  guard !(placement is None || placement is Some(@interop.MissingWorktree(_))) else {
    return (@cmd.none, model)
  }
  let owner : @interop.ConversationKey = {
    channel: model.focused,
    session: conv.session_id,
  }
  let femit = dispatch.map(msg => FileEditor(msg))
  // Park/restore the strip for a conversation switch up front, and re-root
  // the file subsystem when its cached tree belongs to another conversation;
  // otherwise `sync_file_panel`'s post-dispatch pass would see a session
  // mismatch and wipe the freshly opened tab below. A re-rooted document
  // table is seeded from the restored strip (identities only), exactly like
  // `@fileeditor.sync`'s own re-root.
  let dock = @dock.sync(model.dock, owner)
  let previous_panel = model.file_panel
  let panel = if previous_panel.owner == Some(owner) {
    previous_panel
  } else {
    let docs : Map[@pathx.Relative, @fileeditor.Doc] = Map([])
    for open_path in @dock.file_paths(dock) {
      docs[open_path] = {
        name: @fileeditor.basename(open_path),
        state: TabLoading,
        review: None,
        stale: false,
      }
    }
    {
      ..@fileeditor.State::empty(),
      owner: Some(owner),
      // Mirror fileeditor.sync's re-root invariants. In particular, request
      // and watcher generations must outlive an A→B→A jump so older A work
      // cannot collide with the next request or watch after this eager re-root.
      tree_open: previous_panel.tree_open,
      explorer_mode: previous_panel.explorer_mode,
      review_view_mode: previous_panel.review_view_mode,
      changes_generation: previous_panel.changes_generation,
      request_epoch: previous_panel.request_epoch + 1,
      file_link_generation: previous_panel.file_link_generation,
      review_generation: previous_panel.review_generation,
      watch_generation: previous_panel.watch_generation,
      // Preserve the old host configuration until the post-dispatch sync can
      // explicitly retire or replace it.
      watching: previous_panel.watching,
      docs,
    }
  }
  guard conversation_relative(model, conv, path) is Some(relative) else {
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
    file_ctx(model),
    relative,
    file_link_generation?,
    range~,
    annotation?,
    had_active~,
  )
  (cmd, { ..model, file_panel: panel })
}

///|
/// Start a delayed workspace-symbol request only while the composer still has
/// the exact owner, query, and draft generation that scheduled it.
fn Model::begin_completion_symbol_request(
  self : Model,
  dispatch : @cmd.Emit[Msg],
  owner : @interop.ConversationKey,
  query : String,
  generation : Int,
) -> (@cmd.Cmd, Model) {
  guard self.completion_debounce.accepts(generation) &&
    owner.channel == self.focused &&
    owner.session == self.active().session_id &&
    @composer.Trigger::parse(self.active().task, inline_markers="$#")
    is Some(trigger) &&
    trigger.marker() == "#" &&
    trigger.query() == query &&
    self.completion is Some(completion) &&
    completion.kind is Symbols &&
    completion.menu.loading() else {
    return (@cmd.none, self)
  }
  let root = self.conversation_root(self.active())
  if self.symbol_cache.owner == Some(owner) &&
    self.symbol_cache.root == root &&
    self.symbol_cache.query == query {
    return (@cmd.none, self)
  }
  (
    ComposerSymbolRequest(generation).search(dispatch, owner, query, root~),
    self,
  )
}

///|
/// Fold a workspace-symbol reply into the model: cache it and rebuild the menu,
/// but only while it still answers the composer's live `#` query for the active
/// conversation — a reply overtaken by a conversation switch or a later
/// keystroke is dropped, the same staleness guard the file panel uses.
fn apply_symbol_reply(
  model : Model,
  owner : @interop.ConversationKey,
  root : @common.Uri,
  query : String,
  generation : Int,
  symbols : Array[WorkspaceSymbol],
) -> (@cmd.Cmd, Model) {
  let draft = model.active().task
  guard model.completion_debounce.accepts(generation) &&
    owner.channel == model.focused &&
    owner.session == model.active().session_id &&
    model.conversation_root(model.active()) == Some(root) &&
    @composer.Trigger::parse(draft, inline_markers="$#") is Some(trigger) &&
    trigger.marker() == "#" &&
    trigger.query() == query &&
    model.completion is Some(completion) &&
    completion.kind is Symbols &&
    completion.menu.loading() else {
    return (@cmd.none, model)
  }
  let items : Array[CompletionItem] = []
  for symbol in symbols {
    items.push(CompletionItem::from_symbol(symbol))
  }
  let cache : SymbolCache = {
    owner: Some(owner),
    root: Some(root),
    query,
    items,
  }
  (
    @cmd.none,
    {
      ..model,
      symbol_cache: cache,
      completion: compute_completion(
        draft,
        model.installed_skills,
        cache,
        owner,
      ),
    },
  )
}

///|
/// Restart a live composer symbol query when the same conversation moves to a
/// different concrete root. Clearing the cache immediately prevents rows from
/// the previous checkout from remaining selectable while the new request is in
/// flight; the root carried by replies fences work that was already underway.
fn Model::restart_symbol_search_after_root_change(
  self : Model,
  dispatch : @cmd.Emit[Msg],
  previous : Model,
) -> (@cmd.Cmd, Model) {
  guard self.focused == previous.focused &&
    self.active_session == previous.active_session else {
    return (@cmd.none, self)
  }
  let conv = self.active()
  let previous_conv = previous.active()
  guard self.conversation_root(conv) !=
    previous.conversation_root(previous_conv) &&
    @composer.Trigger::parse(conv.task, inline_markers="$#") is Some(trigger) &&
    trigger.marker() == "#" else {
    return (@cmd.none, self)
  }
  let owner : @interop.ConversationKey = {
    channel: self.focused,
    session: conv.session_id,
  }
  let cache = empty_symbol_cache()
  let completion_debounce = self.completion_debounce.advanced()
  let next = {
    ..self,
    symbol_cache: cache,
    completion_debounce,
    completion: compute_completion(
      conv.task,
      self.installed_skills,
      cache,
      owner,
    ),
  }
  (
    completion_debounce.delayed(generation => {
      dispatch(CompletionDue(owner~, query=trigger.query(), generation~))
    }),
    next,
  )
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
  match command {
    "compact" => {
      let conv = model.active()
      // One compaction at a time: a repeat while one is queued or in flight
      // would stack another behind it in the engine's pending queue (the
      // host rejects it anyway) — swallow it like any settled command.
      if !(conv.compaction is NotCompacting) {
        (
          @cmd.none,
          {
            ..model.replace_conversation({ ..conv, task: "" }),
            completion: None,
          },
        )
      } else {
        (
          compact_openseek(
            dispatch,
            model.focused,
            session=conv.session_id,
            model=conv.engine_model,
            max_steps=model.max_steps,
            workspace?=conv.workspace.project(),
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
            completion: None,
          },
        )
      }
    }
    "goal" => {
      let conv = model.active()
      (
        @cmd.none,
        {
          ..model.replace_conversation({
            ..conv,
            task: "",
            goal_edit: Some({ draft: conv.goal_draft_seed() }),
          }),
          completion: None,
        },
      )
    }
    _ => (@cmd.none, { ..model, completion: None })
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
    max_steps=model.max_steps,
    workspace?=conv.workspace.project(),
    command,
    text,
  )
}

///|
/// Fold one engine event into its conversation. Returns whether the
/// transcript visibly grew (the caller turns that into a scroll command only
/// when this conversation is the one on screen) and the new conversation.
fn apply_engine_event(
  conv : Conversation,
  event : @transcript.EngineEvent,
  event_run_id : String?,
) -> (Bool, Conversation) {
  match event {
    AgentStep(step) => {
      let conv = conv.clear_streams()
      (
        false,
        // A step can only advance an open, uncancelled turn: after a Stop the
        // stage stays Cancelling (steering a dying turn is refused, so the
        // display must not flip the gate back open), and a stray step for a
        // closed run changes nothing.
        if conv.run is Open(run_id~, stage~) && !(stage is Cancelling) {
          { ..conv, run: Open(run_id~, stage=AtStep(step)) }
        } else {
          conv
        },
      )
    }
    AssistantDelta(content) =>
      if content.is_empty() {
        (false, conv)
      } else {
        (
          true,
          { ..conv, streaming_response: conv.streaming_response + content },
        )
      }
    ReasoningDelta(content) =>
      if content.is_empty() {
        (false, conv)
      } else {
        (
          true,
          { ..conv, streaming_reasoning: conv.streaming_reasoning + content },
        )
      }
    // Full semantic events never append transcript items: the store commit is
    // the sole source of the durable reasoning/answer item. These events only
    // settle the matching transient stream; the session commit supplies the
    // permanent transcript item without duplicating it here.
    ReasoningMessage(_) => (false, { ..conv, streaming_reasoning: "" })
    AssistantMessage(_) => (false, conv.clear_streams())
    RuntimeUpdate(content) => {
      let update = @transcript.parse_runtime_update(content)
      (false, { ..conv, watcher_status: update.status })
    }
    // A sub-run opened: the lane replaces the notice this used to be, so the
    // minutes it blocks for read as activity rather than silence. A repeated
    // id (a reconnect replaying the bracket) refreshes rather than doubles.
    SubrunOpened(id~, kind~, label~) => {
      let subruns = conv.subruns.filter(lane => lane.id != id)
      subruns.push({
        id,
        kind,
        label,
        steps: 0,
        activity: "",
        run: event_run_id,
      })
      // A lane is a row at the tail, so opening one grows the transcript: a
      // conversation pinned to the bottom has to follow it down, or several
      // concurrent sub-runs open entirely below the fold.
      (true, { ..conv, subruns, })
    }
    // Closed: always drop the lane. A captured sub-run already settles as the
    // durable tool brief, so repeating its status here would leave two
    // completion rows. Only an abnormal terminal status needs a local notice.
    //
    // The error goes in the retained OVERLAY, not in `messages`: the finish of
    // the enclosing run starts a snapshot whose `adopt_snapshot` replaces
    // `messages` wholesale, which would erase a non-durable error bubble.
    SubrunClosed(id~, status~, steps~, tokens~) => {
      let closed = conv.subruns.filter(lane => lane.id == id)
      let conv = { ..conv, subruns: conv.subruns.filter(lane => lane.id != id) }
      if status == "captured" {
        (true, conv)
      } else {
        let kind = match closed {
          [lane, ..] => lane.kind
          [] => "subrun"
        }
        (
          true,
          conv.append_local_notice(
            Assistant(is_danger=true),
            "\{kind} \{id}: \{status} · \{steps} step(s) · \{compact_count(tokens)} tok",
          ),
        )
      }
    }
    Usage(prompt_tokens~, completion_tokens~) =>
      (false, { ..conv, usage_tokens: prompt_tokens + completion_tokens })
    ToolResult(..) => (false, conv)
    // The turn loop records this as an error `tool_result`; its commit is the
    // one canonical transcript source, just like a successful tool result.
    ToolCallDecodeError(..) => (false, conv)
    AgentFinished(_)
    | ContextYield(_)
    | AgentAborted(_)
    | AgentSetupFailed(_) => (false, conv.clear_streams())
    MaxStepsExhausted => (false, conv.clear_streams())
    // The steer took effect at a step boundary. Its durable user item arrives
    // through `session.event`; the live event only settles pending UI.
    SteerApplied(content~, submission_id~) => {
      ignore(content)
      if submission_id is Some(submission_id) {
        let (next, _) = conv.acknowledge_submission(
          submission_id,
          SteerInput,
          event_run_id,
        )
        (false, next)
      } else {
        // Legacy receipt: lifecycle information only. Text is not ownership
        // in a multi-client session, even when it happens to match.
        (false, conv)
      }
    }
    // The steer raced the turn's end through the pipes and was rejected; the
    // text must not vanish silently.
    SteerDropped(content~, submission_id~) =>
      if submission_id is Some(submission_id) {
        let (next, removed) = conv.reject_submission(
          submission_id,
          SteerInput,
          event_run_id,
          steer_dropped_notice(content),
        )
        (removed, next)
      } else {
        (false, conv)
      }
    AutoCompactionFinished(_) => (false, conv)
    CompactionStarted => (false, { ..conv, compaction: Compacting })
    CompactionFinished(_) => (false, { ..conv, compaction: NotCompacting })
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
      (true, conv.append_local_notice(Assistant(is_danger=true), content))
    }
    CompactionFailed(reason) => {
      let content = if reason.is_blank() {
        "compaction failed"
      } else {
        "compaction failed: \{reason}"
      }
      (
        true,
        { ..conv, compaction: NotCompacting }.append_local_notice(
          Assistant(is_danger=true),
          content,
        ),
      )
    }
  }
}

///|
/// The file-editor package's view of the active conversation: which session
/// the panel serves, the concrete checkout root its file/LSP ops address, the
/// registered workspace its Git ops use, and the viewer's theme. Recomputed
/// per dispatch — it is only a projection of the model.
fn file_ctx(model : Model) -> @fileeditor.Ctx {
  let conv = model.active()
  let checkout = model.checkout_placement(conv)
  let file_body_visible = match model.dock.active {
    Some(File(_)) | Some(FilePicker) => true
    None | Some(Browser(_)) => false
  }
  {
    // Keep the real identity even while placement is unresolved or missing.
    // Both panel packages use the typed checkout state to park host work; the
    // stable owner lets an interrupted changed-file review resume after Repair
    // without ever treating the project root as a fallback checkout.
    owner: { channel: model.focused, session: conv.session_id },
    request_epoch: model.file_panel.request_epoch,
    // The native bridge and its watcher survive a page reload. Namespace the
    // panel's monotonic counter with this page's existing random identity so
    // a reloaded frontend cannot reuse the outgoing page's watcher token.
    watch_namespace: model.page_namespace + "-watch",
    root: model.conversation_root(conv),
    workspace: conv.workspace.project(),
    checkout,
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
    model.screen is Chat &&
    file_body_visible,
    open_files: @dock.file_paths(model.dock),
    active_file: @dock.active_file(model.dock),
  }
}

///|
/// The terminal package's view of the active conversation. The conversation's
/// device owns every PTY opened from this context; a remote connection is
/// considered unavailable from its first socket loss because its old PTYs are
/// torn down at that boundary, even before the page escalates to BridgeLost.
fn terminal_ctx(model : Model) -> @terminal.Ctx {
  let conv = model.active()
  let connected = match model.device_state(conv.device) {
    Some(dev) => dev.bridge is Connected(..) && dev.reconnect_failures == 0
    None => false
  }
  @terminal.Ctx(
    channel=conv.device,
    session=conv.session_id,
    workspace=conv.workspace.project(),
    checkout=model.checkout_placement(conv),
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
  ({ ..model, file_panel: panel }, cmd)
}

///|
/// Whether a full-screen surface is drawn over the window. Every overlay
/// `view.mbt` appends after the shell (see its trailing `children.push`
/// block) belongs here: native views z-order above all HTML, so an overlay
/// this predicate forgets renders with the browser pane punched through it,
/// swallowing the clicks that land there.
fn covering_overlay(model : Model) -> Bool {
  model.project_picker is Some(_) ||
  model.archive_confirm is Some(_) ||
  model.quick_open is Some(_) ||
  model.update_ux is ConfirmingRestart(_) ||
  // Best effort: with the bridge gone the hide op may not deliver.
  model.bridge_state() is BridgeLost(_)
}

///|
/// Which browser page's native view belongs on screen: the active Browser
/// tab's, once it has a URL (a blank tab has no view yet) — and only while
/// the pane is actually visible and uncovered. Native views z-order above
/// all HTML, so anything the frontend draws over the pane area — the `+`
/// launcher popup, the narrow layout's sidebar drawer, the topbar app
/// launcher, the composer's git popover, and every `covering_overlay` — must
/// hide the view rather than fight it.
fn desired_browser_view(model : Model) -> Int? {
  guard model.is_desktop &&
    model.screen is Chat &&
    model.right_panel_open &&
    !model.right_panel_menu_open &&
    !model.launcher.open &&
    !model.git_details_open &&
    !(model.narrow && model.sidebar_open) &&
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
            { ..model, browser_pane: { shown: None, rect: None, geo: None } },
            browser_set_visible(dispatch, old, false),
          )
        None =>
          if pane.geo is Some(_) {
            // A measurement was requested but the view left the screen
            // before it landed; forget it so a later show re-measures.
            (
              { ..model, browser_pane: { shown: None, rect: None, geo: None } },
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
          { ..model, browser_pane: { ..pane, geo: Some(geo) } },
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
/// Leave an archived active session immediately, carrying only resubmittable
/// composer state into the supplied fresh id. This is shared by list replies
/// and identity notifications because either can win their delivery race.
fn replace_archived_active(
  model : Model,
  channel : @interop.ChannelId,
  session : String,
  fresh_session : String,
  workspace : @common.Uri?,
) -> Model {
  guard channel == model.focused &&
    model.active_session == session &&
    model.find_conversation(channel, session) is Some(archived_conv) else {
    return model
  }
  let salvaged = archived_conv.archive_salvage()
  let restored_task = salvaged.task
  let restored_mentions = salvaged.mentions
  let pending_initial = salvaged.pending_initial
  let conversations = model.conversations.filter(conv => {
    conv.device != channel || conv.session_id != session
  })
  let activated = { ..model, conversations, }.activate(channel, fresh_session)
  let fresh = activated.active()
  let task = if fresh.task.is_empty() {
    restored_task
  } else if restored_task.is_empty() || fresh.task == restored_task {
    fresh.task
  } else {
    restored_task + "\n\n" + fresh.task
  }
  let mentions = restored_mentions
  for mention in fresh.mentions {
    mentions.push(mention)
  }
  // Goal mode comes across with its text: the replacement conversation is
  // where the user goes on writing it.
  let goal_edit = match (salvaged.goal_draft, fresh.goal_edit) {
    (Some(draft), None) => Some({ draft, })
    (_, existing) => existing
  }
  let fresh = {
    ..fresh,
    task,
    mentions,
    workspace: Workspace::from_project(workspace),
    worktree_mode: model.default_worktree_mode(channel, workspace),
    goal_edit,
  }
  let fresh = if pending_initial {
    fresh.append_local_notice(
      Assistant(is_danger=true),
      ArchivedPendingInputNotice,
    )
  } else {
    fresh
  }
  {
    ..activated.replace_conversation(fresh).with_active_project(workspace),
    screen: Chat,
    loading_conversation: None,
    completion: None,
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
    { ..model, sidebar_open: false }
  } else {
    model
  }
  // The quick pick belongs to the focused conversation captured when it
  // opened. Device/session switches can arrive through many messages (and
  // background pushes), so fence it once here rather than in every branch.
  let (quick_open_cmd, model) = close_stale_quick_open(dispatch, model)
  // A conversation's concrete root can change through connection metadata,
  // restored session data, or a worktree registry broadcast. Restart an open
  // picker once here so every path gets the same stale-result fence.
  let (quick_open_restart_cmd, model) = model.restart_quick_open_after_root_change(
    dispatch, previous,
  )
  let (symbol_restart_cmd, model) = model.restart_symbol_search_after_root_change(
    dispatch, previous,
  )
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
      !model.active().shows_git_chip()
    ) {
    { ..model, git_details_open: false }
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
  let (model, panel_cmd) = sync_file_panel(dispatch, model)
  // The launcher menu belongs to one dock owner. Conversation changes are
  // already explicit root transitions, so close it here instead of observing a
  // rendered owner marker through the DOM.
  let model = if model.right_panel_menu_open &&
    model.dock.owner != previous.dock.owner {
    { ..model, right_panel_menu_open: false }
  } else {
    model
  }
  // Terminal input changes are reconciled as part of the root transition.
  // This replaces the component's rendered marker and MutationObserver while
  // preserving one installation per connection generation.
  let terminal_emit = dispatch.map(msg => Terminal(msg))
  let terminal_input = model.terminal_input()
  let (terminal, terminal_cmd) = model.terminal.reconcile(
    terminal_emit,
    terminal_input,
    (channel, websocket_epoch) => {
      install_bridge(dispatch, terminal_emit, channel, websocket_epoch)
    },
  )
  let model = { ..model, terminal, }
  let (model, browser_cmd) = sync_browser_view(dispatch, model)
  (
    @cmd.batch([
      cmd, quick_open_cmd, quick_open_restart_cmd, symbol_restart_cmd, panel_visibility_cmd,
      panel_cmd, terminal_cmd, browser_cmd,
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
  is (JumpToMention(_) | JumpToLocation(..) | QuickOpenPick(_) | OpenFileAt(..))
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
            ]),
            model,
          )
        None =>
          (
            @cmd.batch([
              load_saved_settings(dispatch),
              watch_color_scheme(dispatch),
              rotate_session(dispatch, model.focused),
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
      model=stored,
      conversation_models=remembered
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
      (
        @cmd.batch([
          theme.apply(model.system_dark),
          app_font.apply(),
          app_font_size.apply(),
        ]),
        {
          ..model,
          notification_corner: NotificationCorner::parse(notification_corner),
          tree_layout: @fileeditor.TreeLayout::parse(tree_layout),
          theme,
          app_font,
          app_font_size,
          default_model,
          conversation_models: parse_conversation_models(remembered),
        },
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
    TaskChanged(value) => {
      let owner : @interop.ConversationKey = {
        channel: model.focused,
        session: model.active().session_id,
      }
      let root = model.conversation_root(model.active())
      // A root change invalidates paths even when the owner and query text are
      // unchanged. Drop that cache before rendering the menu so the delayed
      // request can enter its loading state instead of exposing stale rows.
      let symbol_cache = if model.symbol_cache.root == root {
        model.symbol_cache
      } else {
        empty_symbol_cache()
      }
      let completion_debounce = model.completion_debounce.advanced()
      let (files, files_loading) = model.completion_files(value)
      let command = match
        @composer.Trigger::parse(value, inline_markers="$#@") {
        Some(trigger) if trigger.marker() == "#" &&
          (
            model.symbol_cache.owner != Some(owner) ||
            model.symbol_cache.root != root ||
            model.symbol_cache.query != trigger.query()
          ) =>
          completion_debounce.delayed(generation => {
            dispatch(CompletionDue(owner~, query=trigger.query(), generation~))
          })
        Some(trigger) if trigger.marker() == "@" &&
          (
            model.file_panel.index is @fileeditor.IndexEmpty ||
            model.file_panel.index is @fileeditor.IndexFailed
          ) => dispatch(FileEditor(@fileeditor.EnsureFileIndex))
        _ => @cmd.none
      }
      (
        command,
        {
          ..model.replace_conversation({ ..model.active(), task: value }),
          symbol_cache,
          completion_debounce,
          completion: compute_completion(
            value,
            model.installed_skills,
            symbol_cache,
            owner,
            files~,
            files_loading~,
          ),
        },
      )
    }
    CompletionDue(owner~, query~, generation~) =>
      model.begin_completion_symbol_request(dispatch, owner, query, generation)
    CompletionMove(delta) =>
      if model.completion is Some(menu) {
        (
          @cmd.none,
          {
            ..model,
            completion: Some({ ..menu, menu: menu.menu.shifted(delta) }),
          },
        )
      } else {
        (@cmd.none, model)
      }
    CompletionDismiss => (@cmd.none, { ..model, completion: None })
    RemoveMention(index) => {
      let conv = model.active()
      guard conv.mentions.get(index) is Some(_) else {
        return (@cmd.none, model)
      }
      let mentions = conv.mentions.copy()
      let _ = mentions.remove(index)
      (@cmd.none, model.replace_conversation({ ..conv, mentions, }))
    }
    JumpToMention(index) => {
      let conv = model.active()
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
      let conv = model.active()
      let mentions = push_mention(conv.mentions, {
        ref_: Annotation(
          file=file.0,
          start_line=range.start_line_number,
          end_line=range.end_line_number,
          quote~,
          comment~,
          side=@mention_context.WorkingRevision,
        ),
        range: Some(range),
      })
      // The chip is the comment's carrier from here on; clearing the editor's
      // own bubble keeps the two from drifting apart (and from double-sending
      // if the user comments again).
      (
        @fileeditor.remove_editor_feedback(resource, feedback_id),
        model.replace_conversation({ ..conv, mentions, }),
      )
    }
    // Full-diff comments carry both line domains because a deletion has no
    // working-document position. Prefer the modified line for additions and
    // context; retain the original line for an original-only deletion. Only a
    // modified-side comment receives a concrete editor range, so reopening a
    // deleted-line chip cannot claim stale source columns.
    FileEditor(
      UnifiedDiffCommentAdded(
        file~,
        original_line_number~,
        modified_line_number~,
        quote~,
        comment~
      )
    ) => {
      let (line_number, range, side) = match modified_line_number {
        Some(line_number) if line_number >= 1 => {
          let end_column = if quote.is_empty() { 1 } else { quote.length() + 1 }
          (
            line_number,
            Some(@common.Range::Range(line_number, 1, line_number, end_column)),
            @mention_context.WorkingRevision,
          )
        }
        _ =>
          match original_line_number {
            Some(line_number) if line_number >= 1 =>
              (line_number, None, @mention_context.OriginalRevision)
            _ => return (@cmd.none, model)
          }
      }
      let conv = model.active()
      let mentions = push_mention(conv.mentions, {
        ref_: Annotation(
          file=file.0,
          start_line=line_number,
          end_line=line_number,
          quote~,
          comment~,
          side~,
        ),
        range,
      })
      (@cmd.none, model.replace_conversation({ ..conv, mentions, }))
    }
    // Intercepted like the comment above: which dock tab a tree click opens
    // is the strip's business. The dock opens (or re-activates) the tab,
    // then the file subsystem loads and shows the document against the
    // fresh projection.
    FileEditor(FileSelected(path~, name~)) => {
      let placement = file_ctx(model).checkout
      guard !(placement is None ||
        placement is Some(@interop.MissingWorktree(_))) else {
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
      (cmd, { ..model, file_panel: panel })
    }
    // A Changes row is the review action: open/activate the same ordinary file
    // tab, then let the file subsystem pair its working-tree document with the
    // row's HEAD path. Deleted rows have no working file but still use the
    // current path as their tab identity.
    FileEditor(ChangedFileSelected(change)) => {
      let placement = file_ctx(model).checkout
      guard !(placement is None ||
        placement is Some(@interop.MissingWorktree(_))) else {
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
      (cmd, { ..model, file_panel: panel })
    }
    // Intercepted for the same reason: a navigation jump (go-to-definition,
    // a reference pick) opens a dock tab before the document loads. The
    // owner stamp rejects a reply that outlived a conversation switch.
    FileEditor(OpenNavigationLocation(owner~, path~, range~)) => {
      guard model.file_panel.owner == Some(owner) &&
        file_ctx(model).owner == owner else {
        return (@cmd.none, model)
      }
      let placement = file_ctx(model).checkout
      guard !(placement is None ||
        placement is Some(@interop.MissingWorktree(_))) else {
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
      (cmd, { ..model, file_panel: panel })
    }
    CompletionAccept =>
      if model.completion is Some(menu) && menu.menu.current() is Some(item) {
        accept_completion(dispatch, model, menu, item)
      } else {
        (@cmd.none, { ..model, completion: None })
      }
    CompletionPick(index) =>
      if model.completion is Some(menu) && menu.menu.get(index) is Some(item) {
        accept_completion(dispatch, model, menu, item)
      } else {
        (@cmd.none, { ..model, completion: None })
      }
    SymbolsLoaded(owner~, root~, query~, generation~, items~) =>
      apply_symbol_reply(model, owner, root, query, generation, items)
    // A failed search reads as "no symbols": cache an empty result for the
    // query so the menu settles on "No symbols" rather than spinning.
    SymbolsFailed(owner~, root~, query~, generation~) =>
      apply_symbol_reply(model, owner, root, query, generation, [])
    QuickOpenOpen(mode) => open_quick_open(dispatch, model, mode)
    QuickOpenValueChanged(value) =>
      change_quick_open_value(dispatch, model, value)
    QuickOpenFilesDue(owner~, query~, generation~) =>
      begin_quick_open_file_request(dispatch, model, owner, query, generation)
    QuickOpenFileCacheLoaded(owner~, cache_key~, generation~) =>
      apply_quick_open_file_cache_loaded(
        dispatch, model, owner, cache_key, generation,
      )
    QuickOpenFileCacheRequestFailed(owner~, cache_key~, generation~) =>
      fail_quick_open_file_cache_load(model, owner, cache_key, generation)
    QuickOpenFilesLoaded(
      owner~,
      cache_key~,
      query~,
      generation~,
      files~,
      from_cache~,
      limit_hit~
    ) =>
      apply_quick_open_file_result(
        model, owner, cache_key, query, generation, files, from_cache, limit_hit,
      )
    QuickOpenFilesRequestFailed(owner~, cache_key~, query~, generation~) =>
      fail_quick_open_file_request(model, owner, cache_key, query, generation)
    QuickOpenDue(owner~, query~, generation~) =>
      begin_quick_open_symbol_request(dispatch, model, owner, query, generation)
    QuickOpenSymbolsLoaded(owner~, query~, generation~, items~) =>
      apply_quick_open_symbol_result(model, owner, query, generation, items)
    QuickOpenSymbolsRequestFailed(owner~, query~, generation~) =>
      fail_quick_open_symbol_request(model, owner, query, generation)
    QuickOpenMove(delta) => move_quick_open_selection(model, delta)
    QuickOpenSelect(index) => select_quick_open_row(model, index)
    QuickOpenPick(index) => pick_quick_open_row(dispatch, model, index)
    QuickOpenDismiss => dismiss_quick_open(dispatch, model)
    EngineModelChanged(value) => {
      // The selector changes the conversation on screen. The tier is pinned to
      // that conversation right away — a chat can be given a tier and left
      // unsent for days — and becomes what the next new chat starts from.
      // (Starting a run pins it too; see `Started`.) A turn already in flight
      // keeps the model it was started with; this takes effect on the next.
      guard EngineModel::parse(value) is Some(engine_model) else {
        return (@cmd.none, model)
      }
      let conv = model.active()
      let next = model
        .replace_conversation({ ..conv, engine_model, })
        .remember_model(conv.device, conv.session_id, engine_model)
      (
        @cmd.batch([
          save_default_model(engine_model),
          save_conversation_model(
            conversation_model_key(conv.device, conv.session_id),
            engine_model,
          ),
        ]),
        { ..next, default_model: engine_model },
      )
    }
    MaxStepsChanged(value) => (@cmd.none, { ..model, max_steps: value })
    SetupApiKeyChanged(value) => {
      guard model.host_settings_loaded() else { return (@cmd.none, model) }
      (@cmd.none, { ..model, setup_api_key: value })
    }
    ProviderChanged(value) => {
      guard model.host_settings_loaded() else { return (@cmd.none, model) }
      let provider = ApiProvider::parse(value)
      // A server switch can move the update channel with it; whatever the
      // old channel's check said no longer applies.
      let update_ux = if provider.update_channel() ==
        model.api_provider.update_channel() {
        model.update_ux
      } else {
        UpdateUnknown
      }
      (
        push_host_settings(
          dispatch,
          model.focused,
          provider_settings_patch(provider),
          model.focused_connection_generation(),
        ),
        {
          ..model,
          api_provider: provider,
          setup_api_key: "",
          settings_saves: model.settings_saves + 1,
          update_ux,
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
        { ..model, notification_corner: corner },
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
        { ..model, tree_layout: layout },
      )
    }
    NotificationExpired(id) | DismissNotification(id) =>
      (
        @cmd.none,
        { ..model, notifications: model.notifications.filter(t => t.id != id) },
      )
    RemoteStatusLoaded(status) =>
      (@cmd.none, { ..model, remote_access: Some(status) })
    RemoteConnectClicked =>
      // The flow blocks on a browser round-trip; a second click while one
      // is pending would start a second loopback flow just to be refused.
      if model.remote_connecting {
        (@cmd.none, model)
      } else {
        (
          connect_remote(dispatch),
          { ..model, remote_connecting: true, remote_error: None },
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
        { ..model, remote_connecting: false, remote_error: Some(message) },
      )
    RemoteCancelClicked =>
      // Fire-and-forget: the connect that is being cancelled reports back
      // through its own reply, which is what clears the pending state.
      (cancel_remote(dispatch), model)
    RemoteDisconnectClicked =>
      (disconnect_remote(dispatch), { ..model, remote_error: None })
    RemoteDisconnectFailed(message) =>
      (@cmd.none, { ..model, remote_error: Some(message) })
    AppInfoLoaded(version) => (@cmd.none, { ..model, app_version: version })
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
          check_for_updates(
            dispatch,
            model.api_provider.update_channel(),
            explicit=true,
          ),
          { ..model, update_ux: CheckingForUpdate },
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
          (cmd, { ..next, update_ux: UpdateAvailable(version~, installable~) })
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
            (@cmd.none, { ..model, update_ux: UpdateUnknown })
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
            (@cmd.none, { ..model, update_ux: UpdateUnknown })
          }
        CheckBroken(version~, reason~) => {
          // A broken package entry can only be the publisher's fault:
          // loud both ways.
          let message = "OpenSeek \{version} is published but its package is unusable: \{reason}"
          let (cmd, next) = if explicit {
            (@cmd.none, model)
          } else {
            model.notify_error(dispatch, message)
          }
          (cmd, { ..next, update_ux: UpdateCheckFailed(message~) })
        }
      }
    }
    UpdateClicked =>
      // Only meaningful while an installable release is on offer; the
      // button does not render otherwise, but a stale click must not
      // restart a download.
      if model.update_ux is UpdateAvailable(version~, installable=true) {
        if model.any_conversation_busy() {
          (@cmd.none, { ..model, update_ux: ConfirmingRestart(version~) })
        } else {
          (
            download_update(dispatch, model.api_provider.update_channel()),
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
          download_update(dispatch, model.api_provider.update_channel()),
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
          { ..model, update_ux: UpdateAvailable(version~, installable=true) },
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
          { ..model, update_ux: RestartingForUpdate(version~) },
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
    OpenSetup => (@cmd.none, { ..model, screen: Settings, setup_api_key: "" })
    ToggleSidebar => (@cmd.none, { ..model, sidebar_open: !model.sidebar_open })
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
        (cmd, { ..model, narrow, sidebar_open: !narrow })
      }
    }
    ToggleChatsSection =>
      (@cmd.none, { ..model, chats_collapsed: !model.chats_collapsed })
    ToggleProjectsSection =>
      (@cmd.none, { ..model, projects_collapsed: !model.projects_collapsed })
    ToggleSubruns(channel, session_id) => {
      let expanded = if model.subruns_expanded(channel, session_id) {
        model.expanded_subruns.filter(entry => {
          !(entry.0 == channel && entry.1 == session_id)
        })
      } else {
        [..model.expanded_subruns, (channel, session_id)]
      }
      (@cmd.none, { ..model, expanded_subruns: expanded })
    }
    SaveApiKey => {
      guard model.host_settings_loaded() else { return (@cmd.none, model) }
      let api_key = model.setup_api_key.trim().to_owned()
      if api_key.is_empty() {
        (@cmd.none, model)
      } else {
        match model.api_provider {
          // The key goes straight to the host's store; the mirror keeps
          // only its presence. Saving the key that completes the setup
          // returns to the chat — the same auto-dismiss the popup used to
          // have — optimistically; a failed save comes back as a toast.
          Deepseek | Custom as provider => {
            let next = {
              ..model,
              deepseek_key_saved: model.deepseek_key_saved ||
              provider is Deepseek,
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
              { ..next, screen: if next.api_ready() { Chat } else { Settings } },
            )
          }
          Openseek | OpenseekStaging =>
            (@cmd.none, { ..model, setup_api_key: "" })
        }
      }
    }
    OpenSkills => {
      // The catalog is fetched once per app run (and again after a
      // failure); the installed list is cheap and refreshes on every open.
      let (catalog_cmd, skills_catalog) = match model.skills_catalog {
        CatalogIdle | CatalogFailed(_) =>
          (fetch_skills_catalog(dispatch, model.focused), CatalogLoading)
        current => (@cmd.none, current)
      }
      (
        @cmd.batch([
          catalog_cmd,
          fetch_installed_skills(dispatch, model.focused),
        ]),
        { ..model, screen: Skills, skills_catalog, skills_notice: "" },
      )
    }
    SkillsQueryChanged(value) => (@cmd.none, { ..model, skills_query: value })
    SkillsCatalogLoaded(items) =>
      (@cmd.none, { ..model, skills_catalog: CatalogReady(items) })
    SkillsCatalogFailed(message) =>
      (@cmd.none, { ..model, skills_catalog: CatalogFailed(message) })
    SkillsNotice(message) => (@cmd.none, { ..model, skills_notice: message })
    InstallSkill(item) => {
      let key = @transcript.market_source_label(item)
      if model.skills_busy.contains(key) {
        (@cmd.none, model)
      } else {
        let skills_busy = model.skills_busy.copy()
        skills_busy.push(key)
        (
          install_skill(dispatch, model.focused, item),
          { ..model, skills_busy, skills_notice: "" },
        )
      }
    }
    UninstallSkill(id) =>
      if model.skills_busy.contains(id) {
        (@cmd.none, model)
      } else {
        let skills_busy = model.skills_busy.copy()
        skills_busy.push(id)
        (
          uninstall_skill(dispatch, model.focused, id),
          { ..model, skills_busy, skills_notice: "" },
        )
      }
    SkillActionDone(channel~, key~, error~) => {
      let skills_busy = model.skills_busy.filter(entry => entry != key)
      if error.is_empty() {
        // The library changed; what the panel shows must come from disk,
        // not from a client-side guess. A result that outlived a focus
        // switch belongs to its old host; that host will refetch when it is
        // focused again.
        if channel == model.focused {
          (fetch_installed_skills(dispatch, channel), { ..model, skills_busy, })
        } else {
          (@cmd.none, { ..model, skills_busy, })
        }
      } else {
        (
          @cmd.none,
          {
            ..model,
            skills_busy,
            skills_notice: if channel == model.focused {
              error
            } else {
              model.skills_notice
            },
          },
        )
      }
    }
    Send => {
      let conv = model.active()
      let checkout = model.checkout_placement(conv)
      // The outgoing prompt is the typed text with the chips folded in as the
      // `<user_mentions>` envelope. Typed text is required — chips alone are
      // context without an instruction and stay in the composer.
      let task = compose_prompt(conv.mentions, conv.task).trim().to_owned()
      if !conv.draft_sendable() ||
        !(model.bridge_state() is Connected(..)) ||
        !model.api_ready() ||
        checkout is None ||
        checkout is Some(@interop.MissingWorktree(_)) {
        (@cmd.none, model)
      } else if !(conv.sync is Synced) {
        // A prompt or steer submitted while the durable frontier is unknown
        // could make a delayed prior terminal look like this run's boundary.
        // Keep the draft until the single-flight snapshot settles.
        (@cmd.none, model)
      } else if conv.has_unresolved_run_tail_notice() {
        // The previous run's durable terminal is not proved yet. Starting or
        // steering another run would make its later terminal ambiguous.
        (@cmd.none, model)
      } else if conv.is_running() {
        // Submitting while this conversation's turn runs steers it: the text
        // is folded into the running turn at its next step boundary and
        // echoed back as a `steer_applied` event. A turn being cancelled
        // cannot be steered — the steer could outlive the dying turn in the
        // engine's queue and contaminate a later prompt — so the text stays
        // in the composer.
        if conv.run is Open(run_id~, stage~) &&
          !(stage is Cancelling) &&
          conv.run_durable_floor is Some(_) {
          let (model, submission_id) = model.allocate_submission_id()
          let conv = conv.enqueue_input(
            SteerInput,
            submission_id,
            Some(run_id),
            task,
            conv.task,
            conv.mentions,
          )
          (
            steer_openseek(
              dispatch,
              model.focused,
              conv.session_id,
              submission_id,
              task,
              run_id,
            ),
            {
              ..model.replace_conversation({ ..conv, task: "", mentions: [] }),
              completion: None,
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
        // attempt (see `wants_fresh_worktree`). Read before the ledger
        // entry below mutates the conversation.
        let fresh_worktree = conv.wants_fresh_worktree()
        let conv = conv.enqueue_input(
          InitialPrompt,
          submission_id,
          None,
          task,
          conv.task,
          conv.mentions,
        )
        let next = {
          ..conv,
          task: "",
          mentions: [],
          run: Starting(submission_id~),
          // The store may have advanced through an external CLI while this
          // page was idle. Only the real Started seam's causal snapshot may
          // establish this run's predecessor terminal floor.
          run_durable_floor: None,
          run_floor_generation: None,
          usage_tokens: 0,
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
            model.max_steps,
            conv.session_id,
            workspace=conv.workspace.project(),
          )
        }
        (start_cmd, { ..model.replace_conversation(next), completion: None })
      }
    }
    Stop => {
      let conv = model.active()
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
    NewChat =>
      // A fresh conversation can start at any time: the current one keeps
      // running in the background and stays one sidebar click away. It lands
      // in the active workspace — the one the on-screen conversation uses.
      (
        rotate_session(dispatch, model.focused),
        { ..model, loading_conversation: None },
      )
    NewChatIn(channel, workspace) => {
      // A workspace section's own "new chat": the fresh conversation lands in
      // that project, and the workspace stays active for the next one. A new
      // loose chat unfolds the Chats section so its row is visible; a new
      // project chat unfolds the Projects section for the same reason.
      // The explicit channel lets this handler move device selection before
      // creating the chat. Current sidebar rows pass the selected channel.
      guard model.device_state(channel) is Some(_) else {
        return (@cmd.none, model)
      }
      let (focus_cmd, model) = focus_channel(dispatch, model, channel)
      (
        @cmd.batch([focus_cmd, rotate_session(dispatch, channel)]),
        {
          ..model.with_active_project(workspace),
          loading_conversation: None,
          chats_collapsed: model.chats_collapsed && workspace is Some(_),
          projects_collapsed: model.projects_collapsed && workspace is None,
        },
      )
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
      let conv = model.active()
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
      let conv = model.active()
      guard model.checkout_placement(conv) is None &&
        conv.workspace.project() is Some(workspace) &&
        model.device_state(conv.device) is Some(dev) else {
        return (@cmd.none, model)
      }
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
      let conv = model.active()
      guard model.checkout_placement(conv) is Some(@interop.MissingWorktree(_)) &&
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
            return (@cmd.none, { ..model, archive_confirm: None })
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
    CancelArchiveDiscard => (@cmd.none, { ..model, archive_confirm: None })
    SessionRotated(owner) => {
      // A delayed rotation is owned by the channel that requested it. A focus
      // switch overtakes it; activating the old owner's id here would yank the
      // user back to the host they already left.
      guard owner.channel == model.focused &&
        model.device_state(owner.channel) is Some(dev) else {
        return (@cmd.none, model)
      }
      let existing = model.find_conversation(owner.channel, owner.session)
      let activated = model.activate(owner.channel, owner.session)
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
            workspace: Workspace::from_project(dev.active_project),
            worktree_mode: if existing is Some(existing) {
              existing.worktree_mode
            } else {
              dev.default_worktree_mode(dev.active_project)
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
          completion: None,
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
      let picker = opening_project_picker(channel)
      (
        @cmd.batch([
          focus_cmd,
          browse_directory(dispatch, channel, "", generation=picker.generation),
        ]),
        { ..model, project_picker: Some(picker) },
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
    ProjectPickerNavigate(path) =>
      match model.project_picker {
        Some(picker) => {
          let generation = picker.generation + 1
          (
            browse_directory(dispatch, picker.channel, path, generation~),
            {
              ..model,
              project_picker: Some({ ..picker, loading: true, generation }),
            },
          )
        }
        None => (@cmd.none, model)
      }
    ProjectPickerLoaded(channel~, path~, entries~, generation~) =>
      // A listing for a picker the user already closed — or one answering
      // a navigation that has since been superseded — is dropped.
      match model.project_picker {
        Some(picker) if picker.channel == channel &&
          picker.generation == generation =>
          (
            @cmd.none,
            {
              ..model,
              project_picker: Some({
                channel,
                path: Some(path),
                entries,
                loading: false,
                generation,
              }),
            },
          )
        _ => (@cmd.none, model)
      }
    ProjectPickerFailed(channel~, message~, generation~) =>
      // The failure pops as a toast — mainly a pasted path that names no
      // directory — while the previous listing stays usable.
      match model.project_picker {
        Some(picker) if picker.channel == channel &&
          picker.generation == generation => {
          let (toast, model) = model.notify_error(
            dispatch,
            "Cannot open folder: \{message}",
          )
          (
            toast,
            { ..model, project_picker: Some({ ..picker, loading: false }) },
          )
        }
        _ => (@cmd.none, model)
      }
    ProjectPickerConfirm =>
      match model.project_picker {
        // Confirm registers the directory the host last listed — always
        // something it confirmed exists — never raw pasted text; a paste
        // navigates (and validates) first. While a navigation is in flight
        // the shown listing is stale, so Enter must wait: confirming then
        // would attach the previous directory, not the destination. The
        // pending adoption later focuses the project the add committed.
        Some(picker) if picker.path is Some(path) && !picker.loading => {
          let known = match model.device_state(picker.channel) {
            Some(dev) => dev.projects.copy()
            None => []
          }
          (
            add_project(dispatch, picker.channel, path.path),
            {
              ..model,
              project_picker: None,
              pending_project_adoption: Some({
                channel: picker.channel,
                picked: path,
                known,
                resolved: None,
              }),
            },
          )
        }
        _ => (@cmd.none, model)
      }
    ProjectPickerClose => (@cmd.none, { ..model, project_picker: None })
    RemoveProject(channel, path) =>
      if @resource.belongs_to(path, channel) {
        // Close the row's menu with the click that acted from it; the row
        // itself leaves with the registry commit broadcast.
        (
          remove_project(dispatch, channel, path.path),
          { ..model, project_menu: None },
        )
      } else {
        (@cmd.none, model)
      }
    ToggleProjectMenu(channel, project) => {
      let menu : ProjectMenu = { channel, project }
      (
        @cmd.none,
        {
          ..model,
          project_menu: if model.project_menu == Some(menu) {
            None
          } else {
            Some(menu)
          },
        },
      )
    }
    CloseProjectMenu => (@cmd.none, { ..model, project_menu: None })
    OpenWorkspaceSettings(channel, workspace) =>
      (
        @cmd.none,
        {
          ..model,
          screen: WorkspaceSettings(channel~, workspace~),
          project_menu: None,
        },
      )
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
    NotificationClicked(run_id~) => {
      // The run has finished by the time its notification is clicked, so the
      // owner usually matches by last run id; a still-running owner (steered
      // runs re-notify per turn) matches by active run.
      let conv = if model.conversation_by_last_run(model.focused, run_id)
        is Some(conv) {
        Some(conv)
      } else {
        model.conversation_by_run(model.focused, run_id)
      }
      if conv is Some(conv) {
        update_msg(dispatch, OpenSession(conv.device, conv.session_id), model)
      } else {
        (@cmd.none, model)
      }
    }
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
        let (cmd, model) = open_session_on(dispatch, channel, model, session_id)
        (@cmd.batch([focus_cmd, cmd]), model)
      }
    ColorSchemeChanged(dark) => {
      let model = { ..model, system_dark: dark }
      match model.theme {
        System => (System.apply(dark), model)
        Light | Dark => (@cmd.none, model)
      }
    }
    ThemeChanged(value) => {
      let theme = Theme::parse(value, model.theme)
      if theme == model.theme {
        (@cmd.none, model)
      } else {
        (
          @cmd.batch([theme.apply(model.system_dark), theme.save()]),
          { ..model, theme, },
        )
      }
    }
    FontChanged(value) => {
      let app_font = AppFont::parse(value, model.app_font)
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
      let conv = model.active()
      // Spend the token before starting host work. This synchronously makes
      // every older host reply and positioned read stale, even if this click
      // ultimately opens a non-text path through the system instead.
      let generation = model.file_panel.file_link_generation + 1
      let model = {
        ..model,
        file_panel: { ..model.file_panel, file_link_generation: generation },
      }
      (
        open_file(
          dispatch,
          model.focused,
          conv.session_id,
          generation,
          cwd=model.conversation_root(conv),
          path,
        ),
        model,
      )
    }
    OpenFileAt(owner~, generation~, path~, line~, column~) => {
      let conv = model.active()
      guard owner.channel == model.focused &&
        owner.session == conv.session_id &&
        generation == model.file_panel.file_link_generation else {
        return (@cmd.none, model)
      }
      let range = match line {
        Some(line) => {
          let column = column.unwrap_or(1)
          Some(@common.Range::Range(line, column, line, column))
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
      let conv = model.active()
      guard owner.channel == model.focused &&
        owner.session == conv.session_id &&
        generation == model.file_panel.file_link_generation else {
        return (@cmd.none, model)
      }
      reveal_local_directory(dispatch, model, Relative(path))
    }
    ToggleGitDetails => {
      let opening = !model.git_details_open
      let model = { ..model, git_details_open: opening }
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
      let conv = model.active()
      probe_branch(
        dispatch,
        model,
        conv.device,
        conv.session_id,
        model.conversation_root(conv),
      )
    }
    CloseGitDetails => (@cmd.none, { ..model, git_details_open: false })
    CloseLauncher =>
      (@cmd.none, { ..model, launcher: { ..model.launcher, open: false } })
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
      (
        @cmd.none,
        { ..model, right_panel_open: opening, right_panel_menu_open: false },
      )
    }
    ToggleRightPanelMenu =>
      (
        @cmd.none,
        { ..model, right_panel_menu_open: !model.right_panel_menu_open },
      )
    CloseRightPanelMenu =>
      (@cmd.none, { ..model, right_panel_menu_open: false })
    ToggleLauncher => {
      let opening = !model.launcher.open
      // The launcher exists only in the desktop window, whose one native
      // host is Local. Installed apps are host-global, while the workspace
      // is supplied later to app.launch.
      let (cmd, apps) = if opening {
        match model.launcher.apps {
          AppsNotFetched | AppsFailed(_) => (fetch_apps(dispatch), AppsLoading)
          AppsLoading | AppsFetched(_) => (@cmd.none, model.launcher.apps)
        }
      } else {
        (@cmd.none, model.launcher.apps)
      }
      (cmd, { ..model, launcher: { open: opening, apps } })
    }
    LauncherLoaded(apps) => {
      // Only the one outstanding Local probe may settle the catalog. A
      // duplicate or delayed reply after it settled cannot overwrite it.
      guard model.launcher.apps is AppsLoading else {
        return (@cmd.none, model)
      }
      (
        @cmd.none,
        { ..model, launcher: { ..model.launcher, apps: AppsFetched(apps) } },
      )
    }
    LauncherFailed(message) => {
      guard model.launcher.apps is AppsLoading else {
        return (@cmd.none, model)
      }
      (
        @cmd.none,
        { ..model, launcher: { ..model.launcher, apps: AppsFailed(message) } },
      )
    }
    LaunchApp(app) => {
      let conv = model.active()
      (
        launch_app(
          dispatch,
          conv.session_id,
          cwd=model.conversation_root(conv),
          app,
        ),
        { ..model, launcher: { ..model.launcher, open: false } },
      )
    }
    OpenGoalEditor => {
      let conv = model.active()
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
            goal_edit: Some({ draft: conv.goal_draft_seed() }),
          }),
          completion: None,
        },
      )
    }
    GoalDraftEdited(draft) => {
      let conv = model.active()
      if conv.goal_edit is Some(_) {
        (
          @cmd.none,
          model.replace_conversation({ ..conv, goal_edit: Some({ draft, }) }),
        )
      } else {
        (@cmd.none, model)
      }
    }
    SubmitGoal => {
      let conv = model.active()
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
      let conv = model.active()
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
      let conv = model.active()
      (@cmd.none, model.replace_conversation({ ..conv, goal_edit: None }))
    }
    FileEditor(msg) => {
      let (cmd, panel) = @fileeditor.update(
        dispatch.map(msg => FileEditor(msg)),
        msg,
        model.file_panel,
        file_ctx(model),
      )
      let next = { ..model, file_panel: panel }
      let next = match msg {
        @fileeditor.EnsureFileIndex
        | @fileeditor.FilesIndexed(..)
        | @fileeditor.FileIndexFailed(..) => next.refresh_file_completion()
        _ => next
      }
      (cmd, next)
    }
    Dock(msg) => {
      // The strip machine is pure; the cross-package effects of the
      // transition — showing or dropping documents, mounting hosts — are
      // commanded here off the before/after difference.
      let before = model.dock
      let dock = @dock.update(msg, before)
      let model = { ..model, dock, }
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
              (@cmd.batch(cmds), { ..model, file_panel: panel })
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
            let was_active = before.active == Some(tab)
            // Closing any file tab is newer than a pending transcript link:
            // even an inactive tab must stay closed when that link's delayed
            // host lookup returns. Other tab kinds compete only when closing
            // them changes the active destination.
            let closes_file = match tab {
              File(_) => true
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
                (cmd, { ..model, file_panel: panel })
              }
              Browser(id~) => {
                let cmds : Array[@cmd.Cmd] = [browser_close_view(dispatch, id)]
                // Closing owns the native view's teardown. Retire its cached
                // placement at the same transition so the outer browser sync
                // does not enqueue a hide behind the close; the ordered bridge
                // lane would then try to hide a view the host already removed.
                // Clearing `geo` also makes a successor Browser tab re-measure.
                let browser_pane = if model.browser_pane.shown == Some(id) {
                  { shown: None, rect: None, geo: None }
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
                  (@cmd.batch(cmds), { ..model, file_panel: panel })
                } else {
                  (@cmd.batch(cmds), model)
                }
              }
              FilePicker =>
                if was_active && next_file is Some(path) {
                  let (cmd, panel) = @fileeditor.activate(
                    femit,
                    model.file_panel,
                    file_ctx(model),
                    path,
                  )
                  (cmd, { ..model, file_panel: panel })
                } else {
                  (@cmd.none, model)
                }
            }
          } else {
            (@cmd.none, model)
          }
      }
    }
    Preview(msg) =>
      (@cmd.none, { ..model, preview: @preview.update(msg, model.preview) })
    BrowserTabRequested => {
      let model = model.begin_editor_navigation()
      let (preview, id) = @preview.open_page(model.preview)
      let dock = @dock.open_browser(model.dock, id)
      (
        focus_browser_address(),
        { ..model, preview, dock, right_panel_menu_open: false },
      )
    }
    FilePickerRequested => {
      let model = model.begin_editor_navigation()
      let dock = @dock.open_picker(model.dock)
      let next = { ..model, dock, right_panel_menu_open: false }
      let (cmd, file_panel) = @fileeditor.update(
        dispatch.map(msg => FileEditor(msg)),
        @fileeditor.ExplorerModeSelected(ExplorerFiles),
        next.file_panel,
        file_ctx(next),
      )
      (cmd, { ..next, file_panel, })
    }
    ReviewRequested => {
      let model = model.begin_editor_navigation()
      let dock = @dock.open_picker(model.dock)
      let next = { ..model, dock, right_panel_menu_open: false }
      let (cmd, file_panel) = @fileeditor.update(
        dispatch.map(msg => FileEditor(msg)),
        @fileeditor.ExplorerModeSelected(ExplorerChanges),
        next.file_panel,
        file_ctx(next),
      )
      (cmd, { ..next, file_panel, })
    }
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
          browser_navigate(dispatch, id, url),
          { shown: None, rect: None, geo: None },
        )
      } else {
        // The blank tab's own placement is already absent (a page without a
        // URL is never the desired view), so the create needs no reset.
        (browser_open(dispatch, id, url), model.browser_pane)
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
        { ..model, browser_pane: { ..pane, shown: Some(id), rect: Some(rect) } },
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
    OpenFileFailed(owner~, generation~, message~) => {
      let conv = model.active()
      if owner.channel == model.focused &&
        owner.session == conv.session_id &&
        generation == model.file_panel.file_link_generation {
        model.notify_error(dispatch, message)
      } else {
        (@cmd.none, model)
      }
    }
    ExternalLinkClicked(url) =>
      // Web links open in the dock's Browser tabs by default — the
      // toolbar's open-external button hands the page to the system
      // browser when its chrome or logins are needed. Non-web schemes
      // (mailto:, vscode:, …) and remote consoles (no native views) keep
      // the external path. A same-URL tab already in this strip
      // re-activates instead of duplicating.
      //
      // Only from Chat: the capture listener behind this message is a
      // document-wide one, so it also reports anchors on the other screens,
      // where the dock is not rendered at all — routing there would open a
      // tab nobody can see. Settings' device-page link is the clearest
      // case: it names a URL to open in a browser the user is signed in to,
      // which a native view (with its own cookie jar) is not.
      if model.is_desktop && model.screen is Chat && @preview.is_web_url(url) {
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
            (
              @cmd.none,
              {
                ..model,
                dock,
                right_panel_open: true,
                right_panel_menu_open: false,
              },
            )
          }
          None => {
            let (preview, id) = @preview.open_page(model.preview, url~)
            let dock = @dock.open_browser(model.dock, id)
            (
              browser_open(dispatch, id, url),
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
        (@cmd.none, { ..model, installed_skills: items })
      } else {
        (@cmd.none, model)
      }
    InstalledSkillsFailed(message) =>
      if channel == model.focused {
        (@cmd.none, { ..model, skills_notice: message })
      } else {
        (@cmd.none, model)
      }
    // A running sub-run advanced: refresh its lane in place. An id with no
    // lane is a push that outraced (or outlived) its brackets — dropped, not
    // resurrected, since only a bracket knows a sub-run exists.
    SubrunProgressed(id~, session~, steps~, activity~) => {
      // Route by the CHILD session id, not by the sub-run id: `sr-N` is only
      // unique within its parent engine, so two conversations can both have
      // an `sr-1` in flight. The conversation on screen is not necessarily
      // the one that launched this child either — a background turn keeps
      // running while the user reads something else.
      guard @transcript.subrun_parent(session) is Some(parent) &&
        model.find_conversation(channel, parent) is Some(conv) else {
        return (@cmd.none, model)
      }
      let subruns = conv.subruns.map(lane => {
        if lane.id == id {
          { ..lane, steps, activity }
        } else {
          lane
        }
      })
      if subruns == conv.subruns {
        (@cmd.none, model)
      } else {
        (@cmd.none, model.replace_conversation({ ..conv, subruns, }))
      }
    }
    SkillsChanged =>
      if channel == model.focused {
        (fetch_installed_skills(dispatch, channel), model)
      } else {
        // `installed_skills` is the focused host's mirror. A background
        // device is refreshed when focus moves to it.
        (@cmd.none, model)
      }
    BridgeReady(scratch_root~) => {
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
        // Self-update and the relay sign-in are the desktop window's alone
        // (see `is_desktop`); a browser never checks, so neither UI
        // materializes there. The startup update check rides here: settings
        // (the update channel) load synchronously at Init, so they are in by
        // bridge time.
        if model.is_desktop {
          commands.push(model.fetch_app_info(dispatch))
          commands.push(
            check_for_updates(
              dispatch,
              model.api_provider.update_channel(),
              explicit=false,
            ),
          )
          commands.push(fetch_remote_status(dispatch))
        }
      }
      // Delta streams are not replayable across a connection boundary; keep
      // none of the pre-gap fragment, or the first post-gap delta would splice
      // onto stale text. Compaction has no wire resync in this protocol: an
      // local queued/requested/in-flight marker is released here so a missed
      // terminal event cannot disable Send forever. Any receipt still pending
      // at this boundary becomes truthful `delivery unconfirmed` state; an
      // exact late id can still retract it. If the host still compacts, its
      // next prompt rejection is a transient, visible local failure.
      let reconnect_snapshot_generation = model.transcript_request_generation +
        1
      let conversations = model.conversations.map(conv => {
        if conv.device == channel {
          {
            ..conv
            .clear_streams()
            .mark_awaiting_inputs_unconfirmed(
              snapshot_generation=reconnect_snapshot_generation,
            ),
            compaction: NotCompacting,
          }
        } else {
          conv
        }
      })
      let model = model.replace_device({
        ..dev,
        bridge: Connected(scratch_root~),
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
          ..model
          // The host this bridge just (re)connected to may be a fresh
          // process with no filesystem watcher; forgetting what was watched
          // makes the post-dispatch panel sync re-issue `fs.watch` instead
          // of reading the stale record as "already placed".
          ,
          file_panel: { ..model.file_panel, watching: None },
          // An unusable endpoint routes straight to Settings — the composer
          // could do nothing anyway.
          screen: if model.api_ready() {
            model.screen
          } else {
            Settings
          },
        },
      )
    }
    BridgeUnavailable(message) =>
      (@cmd.none, model.replace_device({ ..dev, bridge: BridgeLost(message) }))
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
          "Can't reach OpenSeek. Make sure OpenSeek is running, then reopen this page.",
        )
      } else {
        dev.bridge
      }
      (
        @cmd.delay(
          dispatch(FromDevice(channel, ReconnectDue(websocket_epoch~))),
          reconnect_delay(failures),
        ),
        model.replace_device({ ..dev, bridge, reconnect_failures: failures }),
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
        (@cmd.none, model.apply_host_settings(settings))
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
        { ..next, legacy_cleanup_pending: false }
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
    SteerUndelivered(session~, submission_id~, text~, run_id~) =>
      // The response path failed, but the host may have accepted the steer;
      // keep its exact-id ledger entry and let only a late id-bearing receipt
      // retract the truthful unconfirmed notice.
      if model.find_conversation(channel, session) is Some(conv) {
        let changed = conv.input_ledger
          .iter()
          .any(input => {
            input.submission_id == submission_id &&
            input.kind is SteerInput &&
            input.run_id is Some(owner) &&
            owner == run_id &&
            input.state is Awaiting
          })
        let (next, _) = if changed {
          conv.mark_submission_unconfirmed(
            submission_id,
            steer_unconfirmed_notice(text),
            false,
          )
        } else {
          (conv, false)
        }
        if !changed {
          (@cmd.none, model)
        } else {
          (@cmd.none, model.replace_conversation(next))
        }
      } else {
        (@cmd.none, model)
      }
    SteerRejected(session~, submission_id~, text~, run_id~) =>
      // A concrete `steered:false` cannot later commit. Retire the ledger entry
      // and restore its exact draft; a later same-text submission is unrelated.
      if model.find_conversation(channel, session) is Some(conv) {
        let (next, removed) = conv.reject_submission(
          submission_id,
          SteerInput,
          Some(run_id),
          steer_dropped_notice(text),
        )
        if removed {
          (@cmd.none, model.replace_conversation(next))
        } else {
          (@cmd.none, model)
        }
      } else {
        (@cmd.none, model)
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
        !(dev.archive_override(item.id) is Some(true))
      })
      for fact in dev.archive_overrides {
        if !fact.archived && !items.iter().any(item => item.id == fact.session) {
          for current in dev.sessions {
            if current.id == fact.session {
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
          let mut project = conv.workspace.project()
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
            active_project = item.workspace
          }
        }
      }
      let mut next = {
        ..model.replace_device({ ..dev, sessions: items, active_project }),
        conversations,
      }
      let commands : Array[@cmd.Cmd] = []
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
        pending.picked.path == added else {
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
        return (@cmd.none, { ..model, pending_project_adoption: None })
      }
      if dev.projects.contains(target) {
        // The commit broadcast beat this reply and the row already exists:
        // focus it now, the way the row's own ＋ does.
        let cleared = { ..model, pending_project_adoption: None }
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
            pending_project_adoption: Some({ ..pending, resolved: Some(target) }),
          },
        )
      }
    }
    ProjectFailed(message) => {
      // A failed mutation also settles any confirmed add still waiting to
      // focus its project: nothing was committed on its behalf.
      let model = if model.pending_project_adoption is Some(pending) &&
        pending.channel == channel {
        { ..model, pending_project_adoption: None }
      } else {
        model
      }
      model.notify_error(dispatch, "Workspace error: \{message}")
    }
    WorkspaceSettingsLoaded(
      workspace~,
      worktree_mode~,
      checkout_submodules~,
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
          ),
        ),
      )
    }
    WorkspaceSettingsChanged(workspace~, worktree_mode~, checkout_submodules~) => {
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
        if conv.device == channel && conv.workspace.project() == Some(workspace) {
          let placement = next_dev.conversation_workspace(
            Some(workspace),
            conv.session_id,
            conv.workspace,
          )
          if conv.workspace is Worktree(..) && placement is Project(..) {
            { ..conv.forget_git(fence~), workspace: placement }
          } else {
            { ..conv, workspace: placement }
          }
        } else {
          conv
        }
      })
      (@cmd.none, { ..next, conversations, })
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
        if conv.device == channel && conv.workspace.project() == Some(workspace) {
          let placement = next_dev.conversation_workspace(
            Some(workspace),
            conv.session_id,
            conv.workspace,
          )
          if conv.workspace is Worktree(..) && placement is Project(..) {
            // The checkout is gone, so every placement derived from it goes
            // too. `forget_git` retires probes already in flight for the removed
            // checkout; the enum transition simultaneously makes every file,
            // LSP, terminal and launcher root re-project to the project.
            { ..conv.forget_git(fence~), workspace: placement }
          } else {
            { ..conv, workspace: placement }
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
          conv.workspace.project() == Some(workspace) &&
          !rows.iter().any(row => row.session == Some(confirm.session)) => None
        other => other
      }
      (@cmd.none, { ..next, conversations, archive_confirm })
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
        { ..model, archive_confirm: Some({ channel, session, refusal }) },
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
        !(dev.archive_override(item.id) is Some(false))
      })
      for fact in dev.archive_overrides {
        if fact.archived && !items.iter().any(item => item.id == fact.session) {
          for current in dev.archived {
            if current.id == fact.session {
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
        if next.archive_override(channel, item.id) is None {
          next = next.with_archive_override(channel, item.id, true)
        }
      }
      let archived_now = (id : String) => {
        items.iter().any(item => item.id == id)
      }
      // The active conversation lives on the focused channel; another
      // device's archived list must not displace it even when a session id
      // collides across devices.
      if channel == next.focused && archived_now(next.active_session) {
        let mut workspace = next.session_project(channel, next.active_session)
        for item in items {
          if item.id == next.active_session {
            workspace = item.workspace
          }
        }
        next = replace_archived_active(
          next,
          channel,
          next.active_session,
          fresh_session,
          workspace,
        )
      }
      let conversations = next.conversations.filter(conv => {
        conv.device != channel || !archived_now(conv.session_id)
      })
      guard next.device_state(channel) is Some(ndev) else {
        return (@cmd.none, { ..next, conversations, })
      }
      let sessions = ndev.sessions.filter(item => !archived_now(item.id))
      (
        @cmd.none,
        {
          ..next.replace_device({ ..ndev, archived: items, sessions }),
          conversations,
        },
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
    WorktreeFailed(message) =>
      model.notify_error(dispatch, "Worktree error: \{message}")
    SessionsFailed(message) =>
      model.notify_error(dispatch, "Session list unavailable: \{message}")
    // Another client archived or unarchived a conversation. Both sidebar
    // lists are stale, but this identity-bearing fact takes effect for its
    // session immediately and remains authoritative over in-flight replies.
    SessionsChanged(change~, session~, fresh_session~) => {
      let (sessions, model) = request_sessions_refresh(dispatch, channel, model)
      let (archived, model) = request_archived_refresh(dispatch, channel, model)
      let commands = @cmd.batch([sessions, archived])
      guard model.device_state(channel) is Some(dev) else {
        return (commands, model)
      }
      if change == "unarchived" {
        let mut restored : @transcript.SessionListItem? = None
        for item in dev.archived {
          if item.id == session {
            restored = Some(item)
          }
        }
        let archived = dev.archived.filter(item => item.id != session)
        let sessions = dev.sessions.copy()
        if restored is Some(item) &&
          !sessions.iter().any(current => current.id == session) {
          sessions.push(item)
        }
        return (
          commands,
          model
          .replace_device({ ..dev, sessions, archived })
          .with_archive_override(channel, session, false),
        )
      }
      if change != "archived" {
        return (commands, model)
      }
      // Invalidate the live target before either async list reply. Keeping a
      // placeholder archived entry also blocks a late session.event from
      // rematerializing it during this window.
      let workspace = model.session_project(channel, session)
      let sessions = dev.sessions.filter(item => item.id != session)
      let conversations = model.conversations.filter(conv => {
        conv.device != channel || conv.session_id != session
      })
      let archived = dev.archived.copy()
      if !archived.iter().any(item => item.id == session) {
        let mut item : @transcript.SessionListItem = {
          id: session,
          title: None,
          workspace,
          workspace_name: "",
        }
        for live in dev.sessions {
          if live.id == session {
            item = live
          }
        }
        archived.push(item)
      }
      let overridden = model.with_archive_override(channel, session, true)
      let overridden = match overridden.device_state(channel) {
        Some(ndev) => overridden.replace_device({ ..ndev, sessions, archived })
        None => overridden
      }
      let next = {
        ..overridden,
        conversations: if channel == model.focused &&
          model.active_session == session {
          model.conversations
        } else {
          conversations
        },
      }
      if channel == model.focused &&
        model.active_session == session &&
        fresh_session is Some(fresh) {
        (
          commands,
          replace_archived_active(next, channel, session, fresh, workspace),
        )
      } else {
        (commands, { ..next, conversations, })
      }
    }
    SessionLoaded(
      session~,
      items~,
      watermark~,
      event_boundaries~,
      goal~,
      goal_markers~,
      generation~
    ) =>
      apply_session_snapshot(
        dispatch, channel, model, session, items, watermark, event_boundaries, goal,
        goal_markers, generation, true,
      )
    SessionRefreshed(
      session~,
      items~,
      watermark~,
      event_boundaries~,
      goal~,
      goal_markers~,
      generation~
    ) =>
      apply_session_snapshot(
        dispatch, channel, model, session, items, watermark, event_boundaries, goal,
        goal_markers, generation, false,
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
    SessionCommitted(session~, sequence~, ts~, item~) => {
      // Archiving removes live client state after the hub's ordered final
      // commit. A stale/replayed commit seen after that local fact must not
      // resurrect the archived record as a live hidden conversation.
      let archived = match dev.archive_override(session) {
        Some(value) => value
        None => dev.archived.iter().any(item => item.id == session)
      }
      if archived {
        return (@cmd.none, model)
      }
      let first_commit_unseen = match
        model.find_conversation(channel, session) {
        Some(conv) => !conv.has_seen_durable_sequence(sequence)
        None => true
      }
      let refresh_sessions = sequence == 1 &&
        !dev.sessions.iter().any(item => item.id == session) &&
        first_commit_unseen
      // A short foreign run can commit and finish before either the session
      // list or run resync reaches this page. Materialize hidden client state
      // from the commit itself: sequence 1 projects immediately; a later
      // sequence exposes a gap and follows the normal snapshot recovery path.
      let model = if model.find_conversation(channel, session) is None {
        model.replace_conversation(
          empty_conversation(
            channel,
            session,
            project?=model.session_project(channel, session),
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
        let commit : BufferedCommit = { sequence, ts, item }
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
                model.replace_conversation({ ..next, watermark: sequence }),
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
      let conv = { ..conv, branch, diffstat, diffstat_hint: base_hint }
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
        let pull_request = Some({ ..probe, stale: true })
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
      let conv = { ..conv, pull_request: Some(settled) }
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
        None =>
          empty_conversation(
            channel,
            session,
            project?=model.session_project(channel, session),
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
      let existing = match dev.project_for_session_root(session_root) {
        Some(project) =>
          {
            ..existing,
            workspace: dev.conversation_workspace(
              Some(project),
              session,
              existing.workspace,
            ),
          }
        None => existing
      }
      let owned = submission_id is Some(id) &&
        existing.has_initial_submission(id)
      let current_start = submission_id is Some(id) &&
        existing.run is Starting(submission_id=current) &&
        current == id
      let same_open = existing.run is Open(run_id=current, ..) &&
        current == run_id
      // A competing Started while an older start request is still in flight
      // does not retire that request's exact receipt path: its late rejection
      // must still be able to restore the draft. An already-open predecessor,
      // by contrast, is conclusively replaced by this lifecycle boundary.
      let can_retire_previous_initial = current_start ||
        !(existing.run is Starting(..))
      // Started establishes exact run ownership, but neither it nor the start
      // response proves the engine persisted its User item. Keep the draft in
      // the ledger until a terminal-backed normal finish proves that append.
      let conv = if owned && submission_id is Some(id) {
        existing.bind_initial_submission_to_run(id, run_id)
      } else {
        existing
      }
      let successor_snapshot_generation = model.transcript_request_generation +
        1
      let (conv, foreign, stale_terminal) = match conv.run {
        Starting(..) if owned && current_start => (conv, false, false)
        Starting(..) =>
          (
            conv.mark_awaiting_inputs_unconfirmed(
              snapshot_generation=successor_snapshot_generation,
            ),
            true,
            false,
          )
        Open(run_id=current, ..) if current == run_id => (conv, false, false)
        Open(run_id=previous_run, ..) =>
          (
            conv
            .clear_streams()
            .mark_awaiting_steers_unconfirmed(
              owner_run_id=previous_run,
              terminal_expected=false,
              terminal_snapshot_generation=successor_snapshot_generation,
            )
            .mark_initial_for_run_unconfirmed(
              previous_run,
              terminal_snapshot_generation=successor_snapshot_generation,
            ),
            true,
            false,
          )
        NoRun(..) if existing.last_run_id is Some(last) && last == run_id =>
          (conv, false, true)
        NoRun(..) => (conv, true, false)
      }
      let conv = if foreign {
        conv.prepare_tail_notices_for_successor(successor_snapshot_generation)
      } else {
        conv
      }
      // Settle and anchor the predecessor before releasing an older prompt's
      // exact-id ownership. BridgeReady may already have made that prompt
      // Unconfirmed; retiring it first would leave its notice fixed ahead of
      // durable predecessor output that lands with this successor snapshot.
      let conv = if can_retire_previous_initial && submission_id is Some(id) {
        conv.retire_unconfirmed_initials_before(id)
      } else {
        conv
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
      let run_durable_floor = if stale_terminal || same_open {
        conv.run_durable_floor
      } else {
        // Lifecycle and durable commits are independent producers. A new run
        // cannot trust this client's apparently-synced terminal frontier: its
        // Started may have overtaken the previous run's terminal commit.
        None
      }
      let run_floor_generation = if refresh {
        Some(successor_snapshot_generation)
      } else {
        conv.run_floor_generation
      }
      let sync = if refresh &&
        conv.sync
        is Reloading(generation~, attempt~, buffered~, reload_after_current=_) {
        Reloading(generation~, attempt~, buffered~, reload_after_current=true)
      } else {
        conv.sync
      }
      let conv = {
        ..conv,
        run,
        run_durable_floor,
        run_floor_generation,
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
        (@cmd.batch(commands), { ..updated, max_steps: max_steps.to_string() })
      } else {
        (@cmd.batch(commands), updated)
      }
    }
    RunsLoaded(runs~, settled~, live~, frontier~, connection_generation~) => {
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
          let bound = conv.bind_initial_submission_to_run(
            submission_id,
            settlement.run_id,
          )
          next = next.replace_conversation({
            ..bound,
            run: Open(run_id=settlement.run_id, stage=Opened),
            run_durable_floor: None,
            run_floor_generation: None,
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
            durable_sequence=settlement.durable_sequence,
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
      (@cmd.batch(commands), settled)
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
      let boundary_reloads : Array[String] = []
      let snapshot_generation = model.transcript_request_generation + 1
      let settled = model.conversations.map(conv => {
        if conv.device != channel {
          return conv
        }
        for captured in frontier {
          if captured.session == conv.session_id {
            return match captured.state {
              SnapshotOpen(run_id~) if conv.run is Open(run_id=current, ..) &&
                current == run_id &&
                !live.contains(run_id) => {
                // The runs reply may be slower than a steer the user sent
                // after this request began. Close the captured lifecycle, but
                // only adjudicate submissions that existed at the request's
                // own frontier; later exact receipts keep their ownership.
                let unconfirmed = conv
                  .clear_streams()
                  .mark_awaiting_steers_unconfirmed(
                    submission_ids=captured.steer_ids,
                    owner_run_id=run_id,
                    terminal_expected=false,
                    terminal_snapshot_generation=snapshot_generation,
                  )
                  .arm_unconfirmed_steers_at_snapshot_cut(
                    captured.steer_ids,
                    run_id,
                    snapshot_generation,
                  )
                  .mark_initial_for_run_unconfirmed(
                    run_id,
                    terminal_snapshot_generation=snapshot_generation,
                  )
                let needs_boundary_reload = unconfirmed.has_submission_at_snapshot_cut_for_run(
                  run_id,
                )
                if needs_boundary_reload {
                  boundary_reloads.push(conv.session_id)
                }
                {
                  ..unconfirmed,
                  run: NoRun(ended=None),
                  last_run_id: Some(run_id),
                }
              }
              SnapshotIdle(last_run_id=Some(run_id)) if conv.run is NoRun(..) &&
                conv.last_run_id is Some(current) &&
                current == run_id => {
                // A prior abnormal finish may have crossed a disconnect after
                // its lifecycle notification but before its exact EOF
                // boundary. Negative idle resync cannot replay that boundary,
                // so arm only the exact steer ids captured with this request
                // for a post-reply snapshot observation cut.
                let armed = conv.arm_unconfirmed_steers_at_snapshot_cut(
                  captured.steer_ids,
                  run_id,
                  snapshot_generation,
                )
                let armed = armed.mark_initial_for_run_unconfirmed(
                  run_id,
                  terminal_snapshot_generation=snapshot_generation,
                )
                let needs_boundary_reload = armed.has_submission_at_snapshot_cut_for_run(
                  run_id,
                )
                if needs_boundary_reload {
                  boundary_reloads.push(conv.session_id)
                }
                armed
              }
              SnapshotStarting(submission_id~) if conv.run
                is Starting(submission_id=current) &&
                current == submission_id => {
                let mut prompt = ""
                for input in conv.input_ledger {
                  if input.kind is InitialPrompt &&
                    input.submission_id == submission_id {
                    prompt = input.draft
                  }
                }
                let (unconfirmed, _) = conv.mark_submission_unconfirmed(
                  submission_id,
                  "Prompt delivery could not be confirmed after run resync — " +
                  "check the transcript before resubmitting: " +
                  prompt,
                  true,
                  terminal_expected=false,
                  terminal_snapshot_generation=snapshot_generation,
                )
                let unconfirmed = unconfirmed.anchor_submission_notice_at_snapshot_cut(
                  submission_id, snapshot_generation,
                )
                if unconfirmed.overlay
                  .iter()
                  .any(notice => {
                    notice.anchor is SnapshotCut(..) &&
                    notice.reconciliation is Submission(id) &&
                    id == submission_id
                  }) {
                  boundary_reloads.push(conv.session_id)
                }
                { ..unconfirmed.clear_streams(), run: NoRun(ended=None) }
              }
              _ => conv
            }
          }
        }
        conv
      })
      let commands : Array[@cmd.Cmd] = []
      let mut next = { ..model, conversations: settled }
      for session in boundary_reloads {
        if next.find_conversation(channel, session) is Some(conv) {
          let (updated, generation) = next.ensure_transcript_reload_after_current(
            conv,
          )
          next = updated
          if generation is Some(generation) {
            commands.push(
              session_snapshot_command(
                dispatch, channel, next, session, generation, false,
              ),
            )
          }
        }
      }
      (@cmd.batch(commands), next)
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
        // the exact local ownership ledger before the legacy run fallback.
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
        let (transcript_grew, next) = apply_engine_event(conv, event, run_id)
        (
          if transcript_grew {
            @cmd.none
          } else {
            @cmd.none
          },
          model.replace_conversation(next),
        )
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
      // The id-bearing reply always settles its exact ledger entry, even when
      // Finished A and Started B overtook A's RPC response. Only lifecycle
      // mutation remains conditional on A still owning the conversation.
      let owns_lifecycle = match conv.run {
        Starting(submission_id=current) => current == submission_id
        Open(run_id=current, ..) => current == run_id
        NoRun(..) => conv.last_run_id is Some(last) && last == run_id
      }
      let conv = conv.bind_initial_submission_to_run(submission_id, run_id)
      if status == "accepted" {
        let missed_started = owns_lifecycle &&
          conv.run is Starting(submission_id=current) &&
          current == submission_id
        let late_abnormal = conv.run is NoRun(..) &&
          conv.last_run_id is Some(owner) &&
          owner == run_id &&
          !(conv.run is NoRun(ended=Some(RunFinished(outcome))) &&
          outcome is (Completed | ContextYield | MaxStepsExhausted))
        let snapshot_generation = model.transcript_request_generation + 1
        // `accepted` proves only that the JSONL command reached the child
        // writer. Keep the recoverable prompt until a terminal-backed finish
        // proves its User append; a pre-append engine failure must not erase
        // the user's text. A response that trails such a normal finish can
        // retire it now because the exact run binding is finally known.
        let settled = if conv.run is NoRun(ended=Some(RunFinished(outcome))) &&
          conv.last_run_id is Some(owner) &&
          owner == run_id &&
          outcome is (Completed | ContextYield | MaxStepsExhausted) {
          conv.acknowledge_initial_for_run(run_id)
        } else if conv.run is NoRun(..) &&
          conv.last_run_id is Some(owner) &&
          owner == run_id {
          conv.mark_initial_for_run_unconfirmed(
            run_id,
            terminal_snapshot_generation=snapshot_generation,
          )
        } else {
          conv
        }
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
            _ =>
              {
                ..settled,
                run: Open(run_id~, stage=Opened),
                last_run_id: Some(run_id),
              }
          }
        } else {
          settled
        }
        let next = if missed_started {
          {
            ..next,
            run_durable_floor: None,
            run_floor_generation: Some(snapshot_generation),
          }
        } else {
          next
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
        // The process result closes a still-live run, but does not prove that
        // its User or Terminal append reached the store. Preserve the exact
        // prompt as unconfirmed until durable recovery or a definitive reject.
        let snapshot_generation = model.transcript_request_generation + 1
        let mut prompt = ""
        for input in conv.input_ledger {
          if input.kind is InitialPrompt && input.submission_id == submission_id {
            prompt = input.draft
          }
        }
        let (unconfirmed, _) = conv.mark_submission_unconfirmed(
          submission_id,
          "Prompt delivery could not be confirmed (host returned " +
          status +
          ", exit code " +
          exit_code.to_string() +
          ") — check the transcript before resubmitting: " +
          prompt,
          true,
          terminal_expected=false,
          terminal_snapshot_generation=snapshot_generation,
        )
        let unconfirmed = unconfirmed.anchor_submission_notice_at_snapshot_cut(
          submission_id, snapshot_generation,
        )
        let unconfirmed = if owns_lifecycle {
          unconfirmed.mark_awaiting_steers_unconfirmed(
            owner_run_id=run_id,
            terminal_expected=false,
            terminal_snapshot_generation=snapshot_generation,
          )
        } else {
          unconfirmed
        }
        let next = if owns_lifecycle {
          match unconfirmed.run {
            Starting(..) | Open(..) =>
              {
                ..unconfirmed.clear_streams(),
                run: NoRun(ended=Some(RunFailed)),
                last_run_id: Some(run_id),
              }
            NoRun(..) => unconfirmed
          }
        } else {
          unconfirmed
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
        let owns_submission = conv.has_initial_submission(submission_id)
        let mut prompt = ""
        for input in conv.input_ledger {
          if input.kind is InitialPrompt && input.submission_id == submission_id {
            prompt = input.draft
          }
        }
        let (unconfirmed, changed) = conv.mark_submission_unconfirmed(
          submission_id,
          "Prompt delivery could not be confirmed (" +
          message +
          ") — check the transcript before resubmitting: " +
          prompt,
          false,
        )
        if !owns_submission {
          (@cmd.none, model)
        } else {
          let next = if conv.run is Starting(submission_id=current) &&
            current == submission_id {
            { ..unconfirmed.clear_streams(), run: NoRun(ended=Some(RunFailed)) }
          } else {
            // A Started push/response for another run won the race. An
            // uncorrelated transport failure must never close that open run.
            unconfirmed
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
      if model.find_conversation(channel, session) is Some(conv) {
        let (rejected, removed) = conv.reject_submission(
          submission_id,
          InitialPrompt,
          None,
          message,
        )
        if !removed {
          (@cmd.none, model)
        } else {
          let next = if conv.run is Starting(submission_id=current) &&
            current == submission_id {
            { ..rejected.clear_streams(), run: NoRun(ended=Some(RunFailed)) }
          } else {
            rejected
          }
          let updated = model.replace_conversation(next)
          if conv.workspace.project() is Some(workspace) &&
            updated.device_state(channel) is Some(dev) {
            // A checkout deleted outside the app cannot publish a registry
            // notification. Any rejected workspace start is a cheap, reliable
            // point to refresh placement; a newly `present: false` row then
            // replaces the generic refusal with Repair/Archive immediately.
            let request_generation = dev.worktrees_request_generation + 1
            (
              @cmd.batch([
                @cmd.none,
                fetch_worktrees(
                  dispatch,
                  channel,
                  workspace,
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
            (@cmd.none, updated)
          }
        }
      } else {
        (@cmd.none, model)
      }
    Error(run_id~, message~, diagnostics~, exit_code~) => {
      // Agent-side semantic errors are lifecycle-only here; their durable
      // status is classified by the subsequent Finished event. Process
      // diagnostics carry `exit_code` and have no durable twin, so they remain
      // a local notice.
      let conv = if run_id is Some(run_id) {
        if model.conversation_by_run(channel, run_id) is Some(conv) {
          Some(conv)
        } else {
          model.conversation_by_last_run(channel, run_id)
        }
      } else if channel == model.focused {
        Some(model.active())
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
        let next = if run_id is Some(owner) && exit_code is Some(_) {
          conv.append_run_diagnostic(owner, content)
        } else {
          conv.append_local_notice(Assistant(is_danger=true), content)
        }
        (
          @cmd.none,
          model.replace_conversation(
            if next.run is NoRun(..) {
              { ..next, run: NoRun(ended=Some(RunErrored)) }
            } else {
              next
            },
          ),
        )
      } else {
        (@cmd.none, model)
      }
    }
    CompactRejected(session~, message~) =>
      if model.find_conversation(channel, session) is Some(conv) {
        (
          @cmd.none,
          model.replace_conversation({
            ..conv.append_local_notice(Assistant(is_danger=true), message),
            compaction: NotCompacting,
          }),
        )
      } else {
        (@cmd.none, model)
      }
    GoalRejected(session~, command~, draft~, message~) =>
      if model.find_conversation(channel, session) is Some(conv) {
        let reported = conv.append_local_notice(
          Assistant(is_danger=true),
          message,
        )
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
        // not what this conversation now stands at. The notice still reports
        // it; nothing here is silent.
        let restored = if !(reported.goal_pending is Some(pending) &&
          pending.id == command) {
          reported
        } else if draft is Some(draft) && reported.goal_edit is None {
          // Hand the goal text back, the way a rejected prompt restores its
          // draft: nothing durable will ever carry it, so losing it here
          // loses it for good. Only when this conversation has not claimed
          // goal mode since — a newer edit is the user's, not this dead
          // request's.
          { ..reported, goal_edit: Some({ draft, }), goal_pending: None }
        } else {
          { ..reported, goal_pending: None }
        }
        (@cmd.none, model.replace_conversation(restored))
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
        // refusal. It rides the notice instead, which is where the start path
        // leaves a prompt it could not confirm either.
        let detail = if draft is Some(draft) {
          " — check the transcript before setting it again: " + draft
        } else {
          " — check the transcript before clearing it again"
        }
        let reported = conv.append_local_notice(
          Assistant(is_danger=true),
          "Goal delivery could not be confirmed (" + message + ")" + detail,
        )
        (@cmd.none, model.replace_conversation(reported))
      } else {
        (@cmd.none, model)
      }
    Finished(run_id~, status~, answer~, durable_sequence~) =>
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
        // On abnormal EOF the host includes a sequence only after its final
        // follower scan succeeded. That is the exact durable EOF boundary;
        // unlike a normal finish, it need not be followed by a Terminal.
        let durable_frontier = durable_sequence
        // Only events logged strictly after a successful Terminal append are
        // terminal-backed. Failed/aborted/cancelled paths attempt the append
        // in a catch block that may itself fail; the host closes that engine
        // and later supplies an exact EOF boundary instead.
        let terminal_expected = match status {
          "finished" | "context_yield" | "max_steps_exhausted" => true
          _ => false
        }
        // Normal finishes use this generation to locate their promised
        // Terminal. Abnormal finishes use the same post-transition read only
        // as an observation cut; they never claim an anonymous Terminal.
        let terminal_snapshot_generation = Some(
          model.transcript_request_generation + 1,
        )
        let conv = if terminal_expected {
          // A successful terminal path can only occur after this run's User
          // append. This is the durable proof that finally retires the prompt
          // kept past the earlier stdin-write response.
          conv.acknowledge_initial_for_run(run_id)
        } else {
          conv.mark_initial_for_run_unconfirmed(
            run_id,
            durable_frontier?,
            terminal_snapshot_generation?,
          )
        }
        let conv = if durable_frontier is Some(frontier) {
          conv
          .anchor_unconfirmed_steers_at_durable_frontier(run_id, frontier)
          .anchor_run_diagnostics_at_durable_frontier(run_id, frontier)
        } else {
          conv
          .anchor_unconfirmed_steers_at_run_finish(
            run_id,
            terminal_expected,
            terminal_snapshot_generation?,
          )
          .anchor_run_diagnostics_at_finish(
            run_id,
            terminal_expected,
            terminal_snapshot_generation?,
          )
        }
        let settled_inputs = conv
          .clear_streams()
          .mark_awaiting_steers_unconfirmed(
            durable_frontier?,
            owner_run_id=run_id,
            terminal_expected~,
            terminal_snapshot_generation?,
          )
        let base = {
          ..settled_inputs,
          run: NoRun(ended=Some(RunFinished(RunOutcome::parse(status)))),
          last_run_id: Some(run_id),
          // A finish the user watched happen needs no reminder; one landing
          // in a background conversation leaves a dot until they visit.
          unseen_finish: conv.device != model.focused ||
          conv.session_id != model.active_session,
        }
        // An exact zero EOF cut proves that a fresh failed run created no
        // durable record. Cancel its now-obsolete speculative snapshot read:
        // otherwise `session.load` can only fail (the file does not exist)
        // and eventually leave Send permanently gated behind ReloadFailed.
        // Be deliberately narrow: any applied or buffered durable content
        // still takes the normal reconciliation path.
        let exact_empty_eof = !terminal_expected &&
          durable_frontier is Some(frontier) &&
          base.is_empty_at_durable_frontier(frontier)
        let base = if exact_empty_eof {
          { ..base.restore_unpersisted_initial_for_run(run_id), sync: Synced }
        } else {
          base
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
            FinishedSystemNotification::{ run_id, status, answer }.command(),
          )
        }
        // The turn's edits routinely land in files the editor panel never
        // shows — paths its pruned watcher does not cover — so the settled
        // boundary re-checks the active MoonBit file's module. The panel's
        // owner fence drops a finish from a conversation it is not showing.
        if first_finish {
          let (panel_cmd, panel_next) = update_msg(
            dispatch,
            FileEditor(RunSettled(owner={ channel, session: conv.session_id })),
            next,
          )
          commands.push(panel_cmd)
          next = panel_next
        }
        if first_finish && !exact_empty_eof && !base.session_id.is_empty() {
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
        if base.overlay.length() > conv.overlay.length() {
          commands.push(@cmd.none)
        }
        (@cmd.batch(commands), next)
      } else {
        // Even when this page missed both Started and every commit, the list
        // can reveal the finished durable session for a later open.
        request_sessions_refresh(dispatch, channel, model)
      }
    DurableBoundary(run_id~, session~, sequence~) =>
      if model.find_conversation(channel, session) is Some(conv) &&
        conv.last_run_id is Some(owner) &&
        owner == run_id {
        let anchored = conv
          .mark_initial_for_run_unconfirmed(run_id, durable_frontier=sequence)
          .anchor_unconfirmed_steers_at_durable_frontier(run_id, sequence)
          .anchor_run_diagnostics_at_durable_frontier(run_id, sequence)
        let exact_empty_eof = anchored.is_empty_at_durable_frontier(sequence)
        let anchored = if exact_empty_eof {
          {
            ..anchored.restore_unpersisted_initial_for_run(run_id),
            sync: Synced,
          }
        } else {
          anchored
        }
        let unresolved = anchored.overlay
          .iter()
          .any(notice => {
            notice.anchor is DurableTail(frontier) && frontier == sequence
          })
        if unresolved {
          // The earlier synthetic Finished may already have completed its
          // compatibility reload before this process finally exited. Re-read
          // once so the snapshot's per-event boundaries can place an exact
          // frontier that is older than the current display watermark.
          let (next, generation) = model.begin_transcript_reload(anchored)
          if generation is Some(generation) {
            (
              session_snapshot_command(
                dispatch, channel, next, session, generation, false,
              ),
              next,
            )
          } else {
            (@cmd.none, next)
          }
        } else {
          (@cmd.none, model.replace_conversation(anchored))
        }
        // Finished removes the run from the host's active set before a
        // failed final follower scan can publish this boundary. An earlier
        // runs snapshot may therefore have closed `Starting` without ever
        // learning the run id. The host records the boundary before this
        // notification reaches us; ask once more with the still-exact
        // submission selector so its now-replayable settlement can bind the
        // run and apply the frontier (including exact zero).
      } else if model.find_conversation(channel, session) is Some(conv) &&
        conv.has_recovering_initial() {
        (
          fetch_runs(
            dispatch,
            channel,
            model.run_snapshot_frontier(channel),
            dev.connection_generation,
          ),
          model,
        )
      } else {
        (@cmd.none, model)
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
/// Test-only connected state with the same required scratch root carried by a
/// real `agent.connected` notification.
fn @interop.ChannelId::test_connected(self : @interop.ChannelId) -> BridgeState {
  // This literal is valid by construction; retain a total test fixture so
  // every test using `test_model` does not acquire a synthetic error effect.
  let root = match @resource.of_path(self, "/scratch") {
    Some(root) => root
    None => @common.Uri::file("/scratch")
  }
  Connected(scratch_root=root)
}

///|
/// Test-only ready message paired with `test_connected`.
fn @interop.ChannelId::test_bridge_ready(
  self : @interop.ChannelId,
) -> DeviceMsg {
  guard self.test_connected() is Connected(scratch_root~) else {
    // `test_connected` has only one result, but spelling the match keeps this
    // constructor synchronized if BridgeState gains another test fixture.
    return BridgeReady(scratch_root=@common.Uri::file("/scratch"))
  }
  BridgeReady(scratch_root~)
}

///|
fn test_conversation() -> Conversation {
  empty_conversation(@interop.ChannelId::Local, "desktop-test")
}

///|
fn test_reloading(buffered : Array[BufferedCommit]) -> TranscriptSync {
  Reloading(generation=1, attempt=1, buffered~, reload_after_current=false)
}

///|
fn running_conversation() -> Conversation {
  {
    ..test_conversation(),
    run: Open(run_id="r7", stage=Opened),
    run_durable_floor: Some(0),
  }
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
        bridge: @interop.ChannelId::Local.test_connected(),
      },
    ],
    focused: @interop.ChannelId::Local,
    console: None,
    // The shared fixture represents a connected desktop after its initial
    // settings snapshot. Loading-state tests opt back into revision -1.
    host_settings_revision: 0,
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
/// Test-only: transform the focused device's state, e.g. seeding a session
/// list on `test_model()`.
fn Model::with_dev(
  self : Model,
  transform : (DeviceState) -> DeviceState,
) -> Model raise {
  self.replace_device(transform(self.dev()))
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
  let conv = { ..test_conversation(), run: Open(run_id="r1", stage=Opened) }
  let (grew, opened) = apply_engine_event(
    conv,
    SubrunOpened(id="sr-1", kind="explore", label="where is X"),
    Some("r1"),
  )
  // The lane is a row at the tail: a pinned transcript must follow it down.
  assert_true(grew)
  inspect(opened.visible_subruns().length(), content="1")
  // The run settles without a finish bracket ever arriving.
  let settled = { ..opened, run: NoRun(ended=Some(RunFailed)) }
  inspect(settled.visible_subruns().length(), content="0")
  // And the stranded lane does not reappear inside the NEXT turn.
  let next_turn = { ..settled, run: Open(run_id="r2", stage=Opened) }
  inspect(next_turn.visible_subruns().length(), content="0")
}

///|
/// A captured sub-run already has a durable tool brief, so closing its live
/// lane must not add a second completion row. An abnormal close has no
/// successful tool brief to explain it and remains visible as a local notice.
test "sub-run completion reports only abnormal terminal status" {
  let conv = { ..test_conversation(), run: Open(run_id="r1", stage=Opened) }
  let (_, opened) = apply_engine_event(
    conv,
    SubrunOpened(id="sr-1", kind="explore", label="where is X"),
    Some("r1"),
  )
  let (grew, closed) = apply_engine_event(
    opened,
    SubrunClosed(id="sr-1", status="captured", steps=37, tokens=12_449),
    Some("r1"),
  )
  assert_true(grew)
  inspect(closed.visible_subruns().length(), content="0")
  // The successful tool brief is the only completion row.
  inspect(closed.messages.length(), content="0")
  inspect(closed.overlay.length(), content="0")
  let (_, reopened) = apply_engine_event(
    closed,
    SubrunOpened(id="sr-2", kind="review", label="check the change"),
    Some("r1"),
  )
  let (failure_grew, failed) = apply_engine_event(
    reopened,
    SubrunClosed(id="sr-2", status="failed", steps=4, tokens=901),
    Some("r1"),
  )
  assert_true(failure_grew)
  inspect(failed.visible_subruns().length(), content="0")
  // The failed tool has no successful brief, so its terminal state survives
  // in the retained overlay.
  inspect(
    failed.overlay.map(notice => notice.content).join("; "),
    content="review sr-2: failed · 4 step(s) · 901 tok",
  )
}

///|
test "a conversation's sub-run twisty toggles only its own row" {
  let dispatch = test_dispatch()
  let model = test_model()
  assert_false(model.subruns_expanded(Local, "a"))
  let (_, opened) = update(dispatch, ToggleSubruns(Local, "a"), model)
  assert_true(opened.subruns_expanded(Local, "a"))
  // A neighbour, and the same id on another device, stay folded: the state
  // is keyed by both halves.
  assert_false(opened.subruns_expanded(Local, "b"))
  assert_false(opened.subruns_expanded(Remote("dev"), "a"))
  let (_, closed) = update(dispatch, ToggleSubruns(Local, "a"), opened)
  assert_false(closed.subruns_expanded(Local, "a"))
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
fn encoded_start_workspace(conv : Conversation) -> String? {
  let payload = start_payload(
    "continue",
    High,
    "1000",
    conv.session_id,
    "test-submission",
    workspace=conv.workspace.project(),
  )
  let json = payload.to_json()
  guard json is Object(fields) else { return None }
  @jsonx.json_text(fields, "workspace")
}

///|
test "runs resync names exact Starting Open and Idle owners" {
  let starting = {
    ..empty_conversation(@interop.ChannelId::Local, "starting-session"),
    run: Starting(submission_id="submission-starting"),
  }
  let open = {
    ..empty_conversation(@interop.ChannelId::Local, "open-session"),
    run: Open(run_id="run-open", stage=Opened),
  }
  let idle = {
    ..empty_conversation(@interop.ChannelId::Local, "idle-session"),
    last_run_id: Some("run-idle"),
  }
  let empty = empty_conversation(@interop.ChannelId::Local, "never-started")
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
    next = next.enqueue_input(
      SteerInput,
      "test-steer-" + index.to_string(),
      Some(run_id),
      text,
      text,
      [],
    )
  }
  next
}

///|
fn with_initial_submission(
  conv : Conversation,
  id : String,
  text : String,
) -> Conversation {
  conv.enqueue_input(InitialPrompt, id, None, text, text, [])
}

///|
/// Drive one new-chat prompt through its id-bearing Started boundary. The
/// resulting causal transcript read is deliberately left in flight.
fn fresh_started_model(
  submission_id : String,
  run_id : String,
  prompt : String,
) -> Model {
  let conv = with_initial_submission(
    { ..test_conversation(), run: Starting(submission_id~) },
    submission_id,
    prompt,
  )
  let (_, started) = update_dev(
    test_dispatch(),
    Started(
      run_id~,
      session="desktop-test",
      model=High,
      max_steps=1000,
      session_root=None,
      submission_id=Some(submission_id),
    ),
    test_model().replace_conversation(conv),
  )
  started
}

///|
/// Run A has finished but its exact start response is still in flight; run B
/// has already been sent and announced on the same conversation.
fn second_run_started_before_first_response() -> (Model, String)? {
  let dispatch = test_dispatch()
  let first = with_initial_submission(
    { ..test_conversation(), run: Starting(submission_id="first-start") },
    "first-start",
    "first prompt",
  )
  let (_, first_started) = update_dev(
    dispatch,
    Started(
      run_id="r-first",
      session="desktop-test",
      model=High,
      max_steps=1000,
      session_root=None,
      submission_id=Some("first-start"),
    ),
    test_model().replace_conversation(first),
  )
  let (_, first_finished) = update_dev(
    dispatch,
    Finished(
      run_id="r-first",
      status="finished",
      answer=None,
      durable_sequence=None,
    ),
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
      event_boundaries=[(1, true, 0)],
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
      event_boundaries=[(1, true, 0)],
      generation=2,
    ),
    reconciled,
  )
  let (_, drafted) = update(dispatch, TaskChanged("second prompt"), post_finish)
  let (_, sending) = update(dispatch, Send, drafted)
  guard sending.active().run is Starting(submission_id=second_submission) else {
    return None
  }
  let (_, second_started) = update_dev(
    dispatch,
    Started(
      run_id="r-second",
      session="desktop-test",
      model=High,
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
    Finished(run_id="r7", status="finished", answer=None, durable_sequence=None),
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
      event_boundaries=[(1, true, 0)],
      generation=1,
    ),
    first_finished,
  )
  let (_, drafted) = update(dispatch, TaskChanged("second prompt"), reconciled)
  let (_, sending) = update(dispatch, Send, drafted)
  guard sending.active().run is Starting(submission_id=second_submission) else {
    return None
  }
  let (_, second_started) = update_dev(
    dispatch,
    Started(
      run_id="r8",
      session="desktop-test",
      model=High,
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
  inspect(second.active().streaming_response, content="Hello, world")
  inspect(second.active().messages.length(), content="0")
}

///|
test "reasoning deltas accumulate beside the streaming response" {
  let dispatch = test_dispatch()
  let (_, first) = update_dev(
    dispatch,
    Engine(Some("r7"), ReasoningDelta("Let me"), session=None),
    running_model(),
  )
  let (_, thinking) = update_dev(
    dispatch,
    Engine(Some("r7"), ReasoningDelta(" think"), session=None),
    first,
  )
  let (_, answering) = update_dev(
    dispatch,
    Engine(Some("r7"), AssistantDelta("Answer"), session=None),
    thinking,
  )
  inspect(answering.active().streaming_reasoning, content="Let me think")
  inspect(answering.active().streaming_response, content="Answer")
  inspect(answering.active().messages.length(), content="0")
}

///|
test "update is pure: replaying a delta on the same model is idempotent" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    streaming_response: "partial",
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
  inspect(once.active().streaming_response, content="partial!")
  inspect(twice.active().streaming_response, content="partial!")
}

///|
test "deltas from an unknown run are dropped" {
  let dispatch = test_dispatch()
  let (_, next) = update_dev(
    dispatch,
    Engine(Some("r99"), AssistantDelta("stale"), session=None),
    running_model(),
  )
  inspect(next.active().streaming_response, content="")
}

///|
test "reasoning message waits for its durable commit" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    streaming_reasoning: "partial thought",
  })
  let (_, next) = update_dev(
    dispatch,
    Engine(Some("r7"), ReasoningMessage("full thought"), session=None),
    model,
  )
  inspect(next.active().streaming_reasoning, content="")
  inspect(next.active().messages.length(), content="0")
  inspect(next.active().overlay.length(), content="0")
}

///|
test "assistant message only settles the transient response" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    streaming_response: "answ",
    streaming_reasoning: "thought",
  })
  let (_, next) = update_dev(
    dispatch,
    Engine(Some("r7"), AssistantMessage("answer"), session=None),
    model,
  )
  inspect(next.active().streaming_response, content="")
  inspect(next.active().streaming_reasoning, content="")
  inspect(next.active().messages.length(), content="0")
  inspect(next.active().overlay.length(), content="0")
}

///|
test "agent setup failure is lifecycle-only until its durable terminal" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    streaming_response: "partial answer",
  })
  let (_, next) = update_dev(
    dispatch,
    Engine(Some("r7"), AgentSetupFailed("could not initialize"), session=None),
    model,
  )
  inspect(next.active().streaming_response, content="")
  inspect(next.active().messages.length(), content="0")
  inspect(next.active().overlay.length(), content="0")
}

///|
test "a new agent step clears the live stream" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    streaming_response: "left",
    streaming_reasoning: "over",
  })
  let (_, next) = update_dev(
    dispatch,
    Engine(Some("r7"), AgentStep(Some(2)), session=None),
    model,
  )
  inspect(next.active().streaming_response, content="")
  inspect(next.active().streaming_reasoning, content="")
}

///|
test "finished run clears any leftover stream" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    streaming_response: "leftover",
    streaming_reasoning: "unfinished thought",
  })
  let (_, next) = update_dev(
    dispatch,
    Finished(
      run_id="r7",
      status="finished",
      answer=Some("done"),
      durable_sequence=None,
    ),
    model,
  )
  inspect(next.active().streaming_response, content="")
  inspect(next.active().streaming_reasoning, content="")
  inspect(next.active().is_running(), content="false")
}

///|
test "finished run reloads the named durable session for an old host" {
  let dispatch = test_dispatch()
  let (_, finished) = update_dev(
    dispatch,
    Finished(
      run_id="r7",
      status="finished",
      answer=Some("done"),
      durable_sequence=None,
    ),
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
        { kind: User, content: "question", ts: None, sequence: None },
        {
          kind: Assistant(is_danger=false),
          content: "done",
          ts: None,
          sequence: None,
        },
      ],
      watermark=3,
      event_boundaries=[(3, true, 2)],
      generation=1,
    ),
    finished,
  )
  inspect(loaded.active().messages.length(), content="2")
  inspect(loaded.active().messages[1].content, content="done")
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
  let finish : DeviceMsg = Finished(
    run_id="r7",
    status="finished",
    answer=None,
    durable_sequence=None,
  )
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
      event_boundaries=[],
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
    Finished(
      run_id="r7",
      status="finished",
      answer=Some("done"),
      durable_sequence=None,
    ),
    running_model(),
  )
  inspect(next.active().unseen_finish, content="false")
}

///|
test "a background finish marks its conversation until it is opened" {
  let dispatch = test_dispatch()
  // The run belongs to "desktop-test"; the user is looking at another chat.
  let model = { ..running_model(), active_session: "desktop-elsewhere" }
  let (_, next) = update_dev(
    dispatch,
    Finished(
      run_id="r7",
      status="finished",
      answer=Some("done"),
      durable_sequence=None,
    ),
    model,
  )
  guard next.find_conversation(@interop.ChannelId::Local, "desktop-test")
    is Some(conv) else {
    fail("conversation missing")
  }
  inspect(conv.unseen_finish, content="true")
  let opened = next.activate(@interop.ChannelId::Local, "desktop-test")
  guard opened.find_conversation(@interop.ChannelId::Local, "desktop-test")
    is Some(seen) else {
    fail("conversation missing after activate")
  }
  inspect(seen.unseen_finish, content="false")
}

///|
test "an idle background notice routes by the last run id" {
  let dispatch = test_dispatch()
  // The run already finished: `active_run_id` is cleared, only the last-run
  // memory ties the id back to its conversation.
  let model = test_model().replace_conversation({
    ..test_conversation(),
    last_run_id: Some("r7"),
  })
  let notice = "[moon_check update]\nstatus=failed\nmain.mbt:1 error"
  let (_, next) = update_dev(
    dispatch,
    Engine(Some("r7"), RuntimeUpdate(notice), session=None),
    model,
  )
  inspect(next.active().watcher_status, content="failed")
  inspect(next.active().overlay.length(), content="0")
}

///|
test "new chat keeps the model intact until the rotation lands" {
  let dispatch = test_dispatch()
  let model = {
    ..running_model(),
    loading_conversation: Some({ channel: Local, session: "desktop-stale" }),
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
    messages: [{ kind: User, content: "hi", ts: None, sequence: None }],
  })
  let (_, next) = update(
    dispatch,
    SessionRotated({ channel: Local, session: "desktop-fresh" }),
    model,
  )
  inspect(next.active_session, content="desktop-fresh")
  inspect(next.active().messages.length(), content="0")
  inspect(next.active().usage_tokens, content="0")
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
    SessionRotated({ channel: Local, session: "desktop-a" }),
    test_model(),
  )
  let (_, second) = update(
    dispatch,
    SessionRotated({ channel: Local, session: "desktop-b" }),
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
      {
        ..empty_device_state(@interop.ChannelId::Local),
        bridge: @interop.ChannelId::Local.test_connected(),
      },
      { ..empty_device_state(remote), bridge: remote.test_connected() },
    ],
  }
  let (_, next) = update(
    dispatch,
    SessionRotated({ channel: remote, session: "remote-late" }),
    model,
  )
  assert_true(next.focused is Local)
  inspect(next.active_session, content="desktop-test")
  assert_true(next.find_conversation(remote, "remote-late") is None)
}

///|
test "a symbol reply with the same session id but another channel is stale" {
  let dispatch = test_dispatch()
  let local_owner : @interop.ConversationKey = {
    channel: Local,
    session: "desktop-test",
  }
  let remote_owner : @interop.ConversationKey = {
    channel: Remote("d-remote"),
    session: "desktop-test",
  }
  let (_, querying) = update(dispatch, TaskChanged("#parse"), test_model())
  let items : Array[WorkspaceSymbol] = [
    {
      name: "parse_file",
      kind: Some(12),
      container: None,
      path: "src/main.mbt",
      range: @common.Range::Range(1, 1, 1, 1),
    },
  ]
  let (_, stale) = update(
    dispatch,
    SymbolsLoaded(
      owner=remote_owner,
      root=remote_owner.channel.test_resource("/scratch/desktop-test"),
      query="parse",
      generation=querying.completion_debounce.generation(),
      items~,
    ),
    querying,
  )
  guard stale.completion is Some(stale_menu) else {
    fail("symbol menu disappeared")
  }
  assert_true(stale_menu.menu.loading())
  let (_, settled) = update(
    dispatch,
    SymbolsLoaded(
      owner=local_owner,
      root=local_owner.channel.test_resource("/scratch/desktop-test"),
      query="parse",
      generation=stale.completion_debounce.generation(),
      items~,
    ),
    stale,
  )
  guard settled.completion is Some(menu) else {
    fail("symbol menu disappeared")
  }
  assert_false(menu.menu.loading())
  guard menu.menu.get(0) is Some(first) else { fail("row expected") }
  inspect(first.label, content="parse_file")
}

///|
test "sessions loaded replaces the sidebar list" {
  let dispatch = test_dispatch()
  let items : Array[@transcript.SessionListItem] = [
    {
      id: "desktop-a",
      title: Some("first question"),
      workspace: None,
      workspace_name: "",
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
      item=@protocol.User({ content: "arrived before the list" }),
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
  assert_true(provisional.workspace is Scratch)
  let (_, listed) = update(
    dispatch,
    sessions_loaded(
      [
        {
          id: "desktop-foreign",
          title: Some("arrived before the list"),
          workspace: Some(workspace),
          workspace_name: "foreign",
        },
      ],
      request_generation=committed.dev().sessions_request_generation,
    ),
    committed.activate(@interop.ChannelId::Local, "desktop-foreign"),
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
test "a background session list updates only its channel's same-id workspace" {
  let dispatch = test_dispatch()
  let remote : @interop.ChannelId = Remote("d-remote")
  let local_conv = {
    ..empty_conversation(@interop.ChannelId::Local, "shared"),
    workspace: Project(root=@interop.ChannelId::Local.test_resource("/local")),
  }
  let remote_conv = {
    ..empty_conversation(remote, "shared"),
    workspace: Project(root=remote.test_resource("/remote-old")),
  }
  let model = {
    ..test_model(),
    devices: [
      {
        ..empty_device_state(@interop.ChannelId::Local),
        bridge: @interop.ChannelId::Local.test_connected(),
      },
      { ..empty_device_state(remote), bridge: remote.test_connected() },
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
            workspace: Some(remote.test_resource("/remote-new")),
            workspace_name: "remote-new",
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
      model=High,
      max_steps=1000,
      session_root=None,
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
  assert_true(provisional.workspace is Scratch)
  let (_, listed) = update(
    dispatch,
    sessions_loaded([
      {
        id: "desktop-started-first",
        title: Some("arrived before the list"),
        workspace: Some(workspace),
        workspace_name: "started-first",
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
  let model = test_model().with_dev(dev => { ..dev, projects: [workspace] })
  let (_, started) = update_dev(
    dispatch,
    Started(
      run_id="foreign-run",
      session="desktop-workspace-run",
      model=High,
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
    messages: [{ kind: User, content: "hi", ts: None, sequence: None }],
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
test "open session keeps live state on screen while re-reading the store" {
  let dispatch = test_dispatch()
  let background = {
    ..empty_conversation(@interop.ChannelId::Local, "desktop-bg"),
    run: Open(run_id="r9", stage=Opened),
    streaming_response: "mid-stream",
    messages: [
      { kind: User, content: "background task", ts: None, sequence: None },
    ],
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
  inspect(once.active().streaming_response, content="mid-stream")
  inspect(once.active().is_running(), content="true")
  assert_true(
    once.loading_conversation is Some({ channel: Local, session: "desktop-bg" }),
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
    messages: [{ kind: User, content: "kept", ts: None, sequence: None }],
    watermark: 1,
  })
  let (_, refreshing) = update_dev(
    dispatch,
    @interop.ChannelId::Local.test_bridge_ready(),
    model,
  )
  guard refreshing.active().sync is Reloading(generation=1, attempt=1, ..) else {
    fail("expected the first reconnect refresh")
  }
  let (_, buffered) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=3,
      ts=None,
      item=@protocol.User({ content: "future" }),
    ),
    refreshing,
  )
  let (_, reconnected_again) = update_dev(
    dispatch,
    @interop.ChannelId::Local.test_bridge_ready(),
    buffered,
  )
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
    streaming_response: "old answer",
    compaction: Queued,
  }
  let background = {
    ..empty_conversation(@interop.ChannelId::Local, "desktop-bg"),
    streaming_response: "background answer",
    compaction: Compacting,
  }
  let model = test_model()
    .replace_conversation(active)
    .replace_conversation(background)
  let (_, next) = update_dev(
    dispatch,
    @interop.ChannelId::Local.test_bridge_ready(),
    model,
  )
  for conv in next.conversations {
    inspect(conv.streaming_response, content="")
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
  let (_, next) = update_dev(
    dispatch,
    @interop.ChannelId::Local.test_bridge_ready(),
    model,
  )
  assert_false(next.host_settings_loaded())
  assert_true(next.api_provider is Openseek)
  inspect(next.custom_api_url, content="")
  assert_false(next.custom_key_saved)
  inspect(next.setup_api_key, content="")
}

///|
test "BridgeReady reattaches a live file index watcher" {
  let dispatch = test_dispatch()
  let model = test_model()
  let owner : @interop.ConversationKey = {
    channel: @interop.ChannelId::Local,
    session: "desktop-test",
  }
  let root = @interop.ChannelId::Local.test_resource("/scratch/desktop-test")
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
    placement_known: true,
    placement_workspace: None,
    placement_root: Some(root),
    placement_checkout: Some(@interop.WorkspaceRoot),
    watching: Some(watched),
    watch_generation: 7,
  }
  let model = { ..model, file_panel: panel }
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
  let model = { ..model, file_panel: ready }
  let (_, next) = update_dev(
    dispatch,
    @interop.ChannelId::Local.test_bridge_ready(),
    model,
  )
  // BridgeReady forgets the old HostConnection's watcher before the common
  // post-dispatch sync. A live hidden index then places the same recursive
  // selection on the new HostConnection with a fresh watcher identity.
  assert_true(
    next.file_panel.watching is Some({ root: next_root, .. }) &&
    next_root == root,
  )
  assert_eq(next.file_panel.watch_generation, 8)
  assert_true(
    next.file_panel.index is @fileeditor.IndexReady(refreshing=false, ..),
  )
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
  let root = @interop.ChannelId::Local.test_resource("/scratch/desktop-test")
  let devices = model.devices.copy()
  devices.push({ ..empty_device_state(remote), bridge: remote.test_connected() })
  let conversations = model.conversations.copy()
  conversations.push(empty_conversation(remote, "remote-session"))
  let panel = {
    ..model.file_panel,
    owner: Some(owner),
    placement_known: true,
    placement_workspace: None,
    placement_root: Some(root),
    placement_checkout: Some(@interop.WorkspaceRoot),
    watching: Some({ owner, root, files: [], directories: [], recursive: true }),
    watch_generation: 7,
  }
  let model = { ..model, devices, conversations, file_panel: panel }
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
    ..empty_conversation(@interop.ChannelId::Local, "shared"),
    streaming_response: "local answer",
    compaction: Queued,
  }
  let remote = {
    ..empty_conversation(background, "shared"),
    streaming_response: "remote answer",
    compaction: Compacting,
  }
  let model = {
    ..test_model(),
    devices: [
      {
        ..empty_device_state(@interop.ChannelId::Local),
        bridge: @interop.ChannelId::Local.test_connected(),
      },
      { ..empty_device_state(background), bridge: background.test_connected() },
    ],
    active_session: "shared",
    conversations: [local_conv, remote],
  }
  let (_, next) = update(
    dispatch,
    FromDevice(background, background.test_bridge_ready()),
    model,
  )
  guard next.find_conversation(@interop.ChannelId::Local, "shared")
    is Some(kept) &&
    next.find_conversation(background, "shared") is Some(reset) else {
    fail("same-id conversations were not preserved")
  }
  inspect(kept.streaming_response, content="local answer")
  assert_true(kept.compaction is Queued)
  inspect(reset.streaming_response, content="")
  assert_true(reset.compaction is NotCompacting)
}

///|
test "socket losses mark the bridge lost at the third consecutive drop" {
  let dispatch = test_dispatch()
  let channel : @interop.ChannelId = Remote("d1")
  let model = {
    ..initial_model(),
    devices: [
      { ..empty_device_state(channel), bridge: channel.test_connected() },
    ],
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
  assert_true(two.bridge_state() is Connected(..))
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
  let (_, next) = update(
    dispatch,
    FromDevice(channel, channel.test_bridge_ready()),
    model,
  )
  inspect(next.dev().reconnect_failures, content="0")
  assert_true(next.bridge_state() is Connected(..))
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
    { id: "same", name: "Mac", hostname: None, online: true },
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
test "BridgeReady fences an awaiting initial after disconnected canonical items" {
  let dispatch = test_dispatch()
  let conv = with_initial_submission(
    {
      ..test_conversation(),
      run: Starting(submission_id="reconnect-prompt"),
      messages: [
        { kind: User, content: "before disconnect", ts: None, sequence: None },
      ],
      watermark: 1,
    },
    "reconnect-prompt",
    "prompt sent near disconnect",
  )
  let (_, reconnected) = update_dev(
    dispatch,
    @interop.ChannelId::Local.test_bridge_ready(),
    test_model().replace_conversation(conv),
  )
  assert_true(reconnected.active().input_ledger[0].state is Unconfirmed)
  assert_true(
    reconnected.active().overlay[0].anchor is SnapshotCut(snapshot_generation=1),
  )
  assert_true(reconnected.active().sync is Reloading(generation=1, ..))
  let (_, reconciled) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[
        { kind: User, content: "before disconnect", ts: None, sequence: None },
        {
          kind: User,
          content: "canonical prompt from the gap",
          ts: None,
          sequence: None,
        },
        {
          kind: Assistant(is_danger=false),
          content: "canonical answer from the gap",
          ts: None,
          sequence: None,
        },
      ],
      watermark=3,
      event_boundaries=[(1, false, 1), (2, false, 2), (3, false, 3)],
      generation=1,
    ),
    reconnected,
  )
  assert_true(reconciled.active().overlay[0].anchor is AfterMessages(3))
  let visible = reconciled.active().visible_items()
  inspect(visible.length(), content="4")
  inspect(visible[2].content, content="canonical answer from the gap")
  assert_true(visible[3].content.contains("prompt sent near disconnect"))
}

///|
test "BridgeReady fences an awaiting steer after disconnected canonical items" {
  let dispatch = test_dispatch()
  let conv = with_pending_steers(
    {
      ..running_conversation(),
      messages: [
        { kind: User, content: "before disconnect", ts: None, sequence: None },
      ],
      watermark: 1,
    },
    ["steer sent near disconnect"],
  )
  let (_, reconnected) = update_dev(
    dispatch,
    @interop.ChannelId::Local.test_bridge_ready(),
    running_model().replace_conversation(conv),
  )
  assert_true(reconnected.active().input_ledger[0].state is Unconfirmed)
  assert_true(
    reconnected.active().overlay[0].anchor is SnapshotCut(snapshot_generation=1),
  )
  assert_true(reconnected.active().sync is Reloading(generation=1, ..))
  let (_, reconciled) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[
        { kind: User, content: "before disconnect", ts: None, sequence: None },
        {
          kind: User,
          content: "canonical steer from the gap",
          ts: None,
          sequence: None,
        },
        {
          kind: Assistant(is_danger=false),
          content: "canonical output from the gap",
          ts: None,
          sequence: None,
        },
      ],
      watermark=3,
      event_boundaries=[(1, false, 1), (2, false, 2), (3, false, 3)],
      generation=1,
    ),
    reconnected,
  )
  assert_true(reconciled.active().overlay[0].anchor is AfterMessages(3))
  let visible = reconciled.active().visible_items()
  inspect(visible.length(), content="4")
  inspect(visible[2].content, content="canonical output from the gap")
  assert_true(visible[3].content.contains("steer sent near disconnect"))
}

///|
test "an explicit rejected fresh start does not force reconnect reloads" {
  let dispatch = test_dispatch()
  let conv = with_initial_submission(
    { ..test_conversation(), run: Starting(submission_id="rejected-id") },
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
  inspect(rejected.active().input_ledger.length(), content="0")
  let (_, reconnected) = update_dev(
    dispatch,
    @interop.ChannelId::Local.test_bridge_ready(),
    rejected,
  )
  assert_true(reconnected.active().sync is Synced)
  inspect(reconnected.transcript_request_generation, content="0")
}

///|
test "an unconfirmed empty start forces reconnect recovery" {
  let dispatch = test_dispatch()
  let conv = with_initial_submission(
    { ..test_conversation(), run: Starting(submission_id="unknown-id") },
    "unknown-id",
    "maybe accepted",
  )
  let (_, uncertain) = update_dev(
    dispatch,
    StartUndelivered(
      session="desktop-test",
      submission_id="unknown-id",
      message="connection lost",
    ),
    test_model().replace_conversation(conv),
  )
  let (_, reconnected) = update_dev(
    dispatch,
    @interop.ChannelId::Local.test_bridge_ready(),
    uncertain,
  )
  guard reconnected.active().sync is Reloading(generation=1, ..) else {
    fail("unconfirmed start did not force a durable reload")
  }
}

///|
test "SessionsLoaded retries an unconfirmed start after an empty recovery" {
  let dispatch = test_dispatch()
  let conv = with_initial_submission(
    { ..test_conversation(), run: NoRun(ended=Some(RunFailed)) },
    "unknown-id",
    "maybe accepted",
  )
  let (conv, _) = conv.mark_submission_unconfirmed(
    "unknown-id", "delivery unconfirmed", false,
  )
  let model = {
    ..test_model().replace_conversation({ ..conv, sync: test_reloading([]) }),
    transcript_request_generation: 1,
  }
  let (_, empty) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[],
      watermark=0,
      event_boundaries=[],
      generation=1,
    ),
    model,
  )
  assert_true(empty.active().sync is Synced)
  inspect(empty.active().input_ledger.length(), content="1")
  let (_, proved) = update(
    dispatch,
    sessions_loaded([
      {
        id: "desktop-test",
        title: Some("persisted"),
        workspace: None,
        workspace_name: "",
      },
    ]),
    empty,
  )
  guard proved.active().sync is Reloading(generation=2, ..) else {
    fail("durable session-list proof did not retry the recovery")
  }
}

///|
test "open session tracks the latest load and ignores stale replies" {
  let dispatch = test_dispatch()
  let (_, loading_a) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-a"),
    test_model(),
  )
  inspect(loading_a.active_session, content="desktop-test")
  assert_true(
    loading_a.loading_conversation
    is Some({ channel: Local, session: "desktop-a" }),
  )
  let (_, loading_b) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-b"),
    loading_a,
  )
  assert_true(
    loading_b.loading_conversation
    is Some({ channel: Local, session: "desktop-b" }),
  )
  let a_items : Array[@transcript.TranscriptItem] = [
    { kind: User, content: "old selection", ts: None, sequence: None },
  ]
  let (_, after_a) = update_dev(
    dispatch,
    SessionLoaded(
      goal=None,
      goal_markers=[],
      session="desktop-a",
      items=a_items,
      watermark=0,
      event_boundaries=[],
      generation=1,
    ),
    loading_b,
  )
  inspect(after_a.active_session, content="desktop-test")
  assert_true(
    after_a.loading_conversation
    is Some({ channel: Local, session: "desktop-b" }),
  )
  let b_items : Array[@transcript.TranscriptItem] = [
    { kind: User, content: "latest selection", ts: None, sequence: None },
  ]
  let (_, after_b) = update_dev(
    dispatch,
    SessionLoaded(
      goal=None,
      goal_markers=[],
      session="desktop-b",
      items=b_items,
      watermark=0,
      event_boundaries=[],
      generation=2,
    ),
    after_a,
  )
  inspect(after_b.active_session, content="desktop-b")
  assert_true(after_b.loading_conversation is None)
  inspect(after_b.active().messages[0].content, content="latest selection")
}

///|
test "completed scratch session root comes from the connected device" {
  let dispatch = test_dispatch()
  let session = "desktop-restored-scratch"
  let (_, listed) = update(
    dispatch,
    sessions_loaded([
      {
        id: session,
        title: Some("restored scratch"),
        workspace: None,
        workspace_name: "",
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
    fail("scratch conversation was not materialized for loading")
  }
  assert_true(
    loading.conversation_root(before) is Some(root) &&
    root.path == "/scratch/desktop-restored-scratch",
  )
  let (_, restored) = update_dev(
    dispatch,
    SessionLoaded(
      session~,
      items=[],
      watermark=0,
      event_boundaries=[],
      goal=None,
      goal_markers=[],
      generation=1,
    ),
    loading,
  )
  assert_eq(restored.active_session, session)
  // Scratch placement remains stable across transcript restoration because
  // its root comes from the current device connection plus the session id.
  assert_true(restored.active().workspace is Scratch)
  assert_true(
    restored.conversation_root(restored.active()) is Some(root) &&
    root.path == "/scratch/desktop-restored-scratch",
  )
  assert_true(
    file_ctx(restored).root is Some(root) &&
    root.path == "/scratch/desktop-restored-scratch",
  )
}

///|
test "same-id session loads are fenced by channel owner" {
  let dispatch = test_dispatch()
  let remote : @interop.ChannelId = Remote("d-remote")
  let local_conv = {
    ..empty_conversation(@interop.ChannelId::Local, "shared"),
    messages: [{ kind: User, content: "local", ts: None, sequence: None }],
  }
  let remote_conv = {
    ..empty_conversation(remote, "shared"),
    messages: [{ kind: User, content: "remote", ts: None, sequence: None }],
  }
  let model = {
    ..test_model(),
    devices: [
      {
        ..empty_device_state(@interop.ChannelId::Local),
        bridge: @interop.ChannelId::Local.test_connected(),
      },
      { ..empty_device_state(remote), bridge: remote.test_connected() },
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
    is Some({ channel: Local, session: "shared" }),
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
            kind: Assistant(is_danger=false),
            content: "remote loaded",
            ts: None,
            sequence: None,
          },
        ],
        watermark=1,
        event_boundaries=[],
        generation=1,
      ),
    ),
    loading_local,
  )
  assert_true(remote_reply.focused is Local)
  inspect(remote_reply.active().messages[0].content, content="local")
  assert_true(
    remote_reply.loading_conversation
    is Some({ channel: Local, session: "shared" }),
  )
  guard remote_reply.find_conversation(remote, "shared") is Some(loaded) else {
    fail("remote conversation disappeared")
  }
  inspect(loaded.messages[0].content, content="remote loaded")
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
        workspace: None,
        workspace_name: "",
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
    is Some({ channel: Local, session: "desktop-test" }),
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
          kind: Assistant(is_danger=false),
          content: "written elsewhere",
          ts: None,
          sequence: None,
        },
      ],
      watermark=1,
      event_boundaries=[],
      generation=1,
    ),
    still_single_flight,
  )
  inspect(loaded.active().messages.length(), content="1")
  inspect(loaded.active().messages[0].content, content="written elsewhere")
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
    test_model(),
  )
  guard opening.find_conversation(@interop.ChannelId::Local, "desktop-pruned")
    is Some(first) &&
    first.sync is Reloading(generation=1, ..) else {
    fail("expected the original request")
  }
  let pruned = opening.activate(@interop.ChannelId::Local, "desktop-other")
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
      items=[
        { kind: User, content: "late old snapshot", ts: None, sequence: None },
      ],
      watermark=9,
      event_boundaries=[],
      generation=1,
    ),
    reopened,
  )
  assert_true(
    stale.loading_conversation
    is Some({ channel: Local, session: "desktop-pruned" }),
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
      items=[
        { kind: User, content: "fresh snapshot", ts: None, sequence: None },
      ],
      watermark=1,
      event_boundaries=[],
      generation=2,
    ),
    stale,
  )
  inspect(fresh.active_session, content="desktop-pruned")
  inspect(fresh.active().messages[0].content, content="fresh snapshot")
}

///|
test "archive removal and reopening cannot reuse a transcript request token" {
  let dispatch = test_dispatch()
  let (_, opening) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-archived"),
    test_model(),
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
  let (_, reopened) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-archived"),
    restored,
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
        {
          kind: User,
          content: "late archived snapshot",
          ts: None,
          sequence: None,
        },
      ],
      watermark=4,
      event_boundaries=[],
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
    test_model(),
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
    test_model(),
  )
  let failure = SessionLoadFailed(
    session="desktop-a",
    message="failed to load session desktop-a: no such file",
    generation=1,
  )
  let (_, retrying2) = update_dev(dispatch, failure, loading)
  assert_true(
    retrying2.loading_conversation
    is Some({ channel: Local, session: "desktop-a" }),
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
    content="failed to load session desktop-a: no such file",
  )
  guard next.find_conversation(@interop.ChannelId::Local, "desktop-a")
    is Some(failed) else {
    fail("expected the failed conversation")
  }
  assert_true(failed.sync is ReloadFailed(..))
  inspect(failed.overlay.length(), content="1")
  assert_eq(failed.overlay[0].content, TranscriptRefreshFailedNotice)
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
  )
  let (_, semantic_first) = update_dev(dispatch, semantic, running_model())
  inspect(semantic_first.active().overlay.length(), content="0")
  let (_, committed_after) = update_dev(dispatch, terminal, semantic_first)
  inspect(committed_after.active().messages.length(), content="1")
  inspect(committed_after.active().overlay.length(), content="0")
  let (_, committed_first) = update_dev(dispatch, terminal, running_model())
  let (_, semantic_after) = update_dev(dispatch, semantic, committed_first)
  inspect(semantic_after.active().messages.length(), content="1")
  inspect(semantic_after.active().overlay.length(), content="0")
}

///|
test "a process-exit error keeps its host diagnostics as a local notice" {
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
  inspect(next.active().overlay.length(), content="1")
  assert_true(next.active().overlay[0].content.contains("fatal stderr"))
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
test "finished and durable-boundary decoders preserve exact EOF frontiers" {
  guard finished_msg({
      run_id: "r7",
      status: "failed",
      answer: None,
      exit_code: Some(9),
      durable_sequence: Some(12),
    })
    is Some(Finished(durable_sequence=Some(12), ..)) else {
    fail("expected the final-scan sequence")
  }
  guard durable_boundary_msg({
      run_id: "r7",
      session: "desktop-test",
      sequence: 12,
    })
    is Some(DurableBoundary(sequence=12, ..)) else {
    fail("expected the delayed durable boundary")
  }
}

///|
test "session loaded swaps the active conversation onto the stored session" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    usage_tokens: 42,
    watcher_status: "running",
    streaming_response: "leftover",
    messages: [{ kind: User, content: "old chat", ts: None, sequence: None }],
  })
  let (_, loading) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-stored"),
    model,
  )
  let items : Array[@transcript.TranscriptItem] = [
    { kind: User, content: "stored question", ts: None, sequence: None },
    {
      kind: Assistant(is_danger=false),
      content: "stored answer",
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
      event_boundaries=[],
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
      event_boundaries=[],
      generation=1,
    ),
    loading,
  )
  inspect(once.active_session, content="desktop-stored")
  inspect(once.active().messages.length(), content="2")
  inspect(once.active().messages[0].content, content="stored question")
  inspect(once.active().streaming_response, content="")
  inspect(once.active().usage_tokens, content="0")
  inspect(once.active().watcher_status, content="")
  assert_true(once.active().workspace is Scratch)
  assert_true(once.display_status() is Ready)
  inspect(twice.active().messages.length(), content="2")
}

///|
test "session loaded adopts the store transcript and keeps live run state" {
  let dispatch = test_dispatch()
  let model = running_model()
  let items : Array[@transcript.TranscriptItem] = [
    { kind: User, content: "stored", ts: None, sequence: None },
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
      event_boundaries=[],
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
    streaming_response: "mid-step",
  })
  let loading_same = {
    ..streaming.replace_conversation({
      ..streaming.active(),
      sync: test_reloading([]),
    }),
    loading_conversation: Some({ channel: Local, session: "desktop-test" }),
  }
  let (_, same) = update_dev(
    dispatch,
    SessionLoaded(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items~,
      watermark=0,
      event_boundaries=[],
      generation=1,
    ),
    loading_same,
  )
  inspect(same.active().messages.length(), content="1")
  inspect(same.active().messages[0].content, content="stored")
  inspect(same.active().is_running(), content="true")
  inspect(same.active().streaming_response, content="mid-step")
}

///|
test "started routes by session without replacing scratch placement" {
  let dispatch = test_dispatch()
  let (_, next) = update_dev(
    dispatch,
    Started(
      run_id="r7",
      session="desktop-test",
      model=High,
      max_steps=1000,
      session_root=None,
      submission_id=None,
    ),
    test_model(),
  )
  assert_true(next.active().workspace is Scratch)
  assert_true(
    next.conversation_root(next.active()) is Some(root) &&
    root.path == "/scratch/desktop-test",
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
      model=High,
      max_steps=1000,
      session_root=None,
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
  inspect(ghost.overlay.length(), content="0")
  // Focus stays where the user is.
  inspect(next.active_session, content="desktop-test")
  inspect(next.active().is_running(), content="false")
}

///|
test "a distinct started id replaces a stale open run as foreign" {
  let dispatch = test_dispatch()
  let conv = with_pending_steers(
    {
      ..running_conversation(),
      run: Open(run_id="r-old", stage=AtStep(Some(3))),
      streaming_response: "old answer fragment",
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
      model=High,
      max_steps=1000,
      session_root=None,
      submission_id=None,
    ),
    model,
  )
  guard next.active().run is Open(run_id="r-new", stage=Opened) else {
    fail("expected the new run to replace the stale id")
  }
  inspect(next.active().streaming_response, content="")
  inspect(next.active().pending_steers().length(), content="0")
  inspect(next.active().overlay.length(), content="1")
  assert_true(next.active().overlay[0].content.contains("old steer"))
  guard next.active().sync is Reloading(generation=1, attempt=1, ..) else {
    fail("a foreign replacement did not refresh the transcript")
  }
}

///|
test "a repeated started id is idempotent" {
  let dispatch = test_dispatch()
  let conv = with_pending_steers(
    {
      ..running_conversation(),
      run: Open(run_id="r7", stage=AtStep(Some(4))),
      streaming_response: "current fragment",
    },
    ["current steer"],
  )
  let model = running_model().replace_conversation(conv)
  let (_, next) = update_dev(
    dispatch,
    Started(
      run_id="r7",
      session="desktop-test",
      model=High,
      max_steps=1000,
      session_root=None,
      submission_id=None,
    ),
    model,
  )
  guard next.active().run is Open(run_id="r7", stage=AtStep(Some(4))) else {
    fail("a repeated start reset the live run stage")
  }
  inspect(next.active().streaming_response, content="current fragment")
  inspect(next.active().pending_steers().length(), content="1")
  inspect(next.active().pending_steers()[0], content="current steer")
  inspect(next.transcript_request_generation, content="0")
  assert_true(next.active().sync is Synced)
}

///|
test "a start failure cannot close a run opened by a winning push" {
  let dispatch = test_dispatch()
  let starting_conv = with_initial_submission(
    { ..test_conversation(), run: Starting(submission_id="mine") },
    "mine",
    "my competing prompt",
  )
  let starting = test_model().replace_conversation(starting_conv)
  let (_, opened) = update_dev(
    dispatch,
    Started(
      run_id="r-foreign",
      session="desktop-test",
      model=High,
      max_steps=1000,
      session_root=None,
      submission_id=Some("theirs"),
    ),
    starting,
  )
  let opened = opened.replace_conversation(
    with_pending_steers(
      { ..opened.active(), streaming_response: "foreign fragment" },
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
  inspect(failed.active().streaming_response, content="foreign fragment")
  inspect(failed.active().pending_steers().length(), content="1")
  inspect(failed.active().pending_steers()[0], content="steer for foreign run")
  inspect(failed.active().task, content="my competing prompt")
  inspect(failed.active().overlay.length(), content="1")
  inspect(failed.active().overlay[0].content, content="start was rejected")
  guard failed.active().sync is Reloading(generation=1, ..) else {
    fail("the raced start failure did not catch up the transcript")
  }
}

///|
test "a start failure closes only a still-starting run" {
  let dispatch = test_dispatch()
  let conv = with_initial_submission(
    {
      ..test_conversation(),
      run: Starting(submission_id="prompt-id"),
      streaming_response: "partial",
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
  inspect(failed.active().streaming_response, content="")
  inspect(failed.active().overlay.length(), content="1")
  inspect(failed.active().task, content="prompt")
  inspect(failed.transcript_request_generation, content="0")
}

///|
test "canonical User text never claims an unconfirmed start" {
  let dispatch = test_dispatch()
  let conv = with_initial_submission(
    test_conversation(),
    "prompt-id",
    "accepted prompt",
  )
  let model = test_model().replace_conversation({
    ..conv,
    run: Starting(submission_id="prompt-id"),
  })
  let (_, failed) = update_dev(
    dispatch,
    StartUndelivered(
      session="desktop-test",
      submission_id="prompt-id",
      message="response transport closed",
    ),
    model,
  )
  assert_true(failed.active().run is NoRun(ended=Some(RunFailed)))
  inspect(failed.active().overlay.length(), content="1")
  inspect(failed.active().input_ledger.length(), content="1")
  let (_, committed) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=1,
      ts=None,
      item=@protocol.User({ content: "accepted prompt" }),
    ),
    failed,
  )
  assert_true(committed.active().run is NoRun(ended=Some(RunFailed)))
  inspect(committed.active().overlay.length(), content="1")
  inspect(committed.active().input_ledger.length(), content="1")
  inspect(committed.active().messages.length(), content="1")
}

///|
test "a matching Started establishes the run without consuming its prompt" {
  let dispatch = test_dispatch()
  let conv = with_initial_submission(
    { ..test_conversation(), run: Starting(submission_id="prompt-id") },
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
      model=High,
      max_steps=1000,
      session_root=None,
      submission_id=Some("prompt-id"),
    ),
    failed,
  )
  assert_true(started.active().run is Open(run_id="r-recovered", ..))
  inspect(started.active().overlay.length(), content="1")
  assert_true(started.active().overlay[0].content.contains("accepted prompt"))
  inspect(started.active().input_ledger.length(), content="1")
  inspect(started.active().input_ledger[0].submission_id, content="prompt-id")
  assert_true(started.active().input_ledger[0].state is Unconfirmed)
}

///|
test "an accepted start response opens the run without Started" {
  let dispatch = test_dispatch()
  let conv = with_initial_submission(
    { ..test_conversation(), run: Starting(submission_id="prompt-id") },
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
  inspect(responded.active().input_ledger.length(), content="1")
  assert_true(responded.active().input_ledger[0].run_id is Some("r-response"))
  assert_true(responded.active().sync is Reloading(generation=1, ..))
  assert_true(responded.active().run_durable_floor is None)
  assert_true(responded.active().run_floor_generation is Some(1))
  let (_, drafted) = update(dispatch, TaskChanged("too early"), responded)
  let (_, gated) = update(dispatch, Send, drafted)
  inspect(gated.active().input_ledger.length(), content="1")
  inspect(gated.active().task, content="too early")
  let (_, started) = update_dev(
    dispatch,
    Started(
      run_id="r-response",
      session="desktop-test",
      model=High,
      max_steps=1000,
      session_root=None,
      submission_id=Some("prompt-id"),
    ),
    gated,
  )
  // The delayed Started is idempotent with the response-first recovery: it
  // neither drops nor queues a second generation.
  assert_true(started.active().sync is Reloading(generation=1, ..))
  assert_true(started.active().run_floor_generation is Some(1))
  let (_, loaded) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[
        { kind: User, content: "external prompt", ts: None, sequence: None },
        {
          kind: Assistant(is_danger=false),
          content: "external answer",
          ts: None,
          sequence: None,
        },
        { kind: User, content: "prompt", ts: None, sequence: None },
      ],
      watermark=4,
      event_boundaries=[
        (1, false, 1),
        (2, false, 2),
        (3, true, 2),
        (4, false, 3),
      ],
      generation=1,
    ),
    started,
  )
  assert_true(loaded.active().sync is Synced)
  assert_true(loaded.active().run_durable_floor is Some(3))
  assert_true(loaded.active().run_floor_generation is None)
  inspect(loaded.active().input_ledger.length(), content="1")
}

///|
test "accepted start remains recoverable when the engine fails before User append" {
  let dispatch = test_dispatch()
  let conv = with_initial_submission(
    { ..test_conversation(), run: Starting(submission_id="prompt-id") },
    "prompt-id",
    "must not disappear",
  )
  let (_, accepted) = update_dev(
    dispatch,
    StartResponded(
      session="desktop-test",
      submission_id="prompt-id",
      run_id="r-failed",
      status="accepted",
      exit_code=0,
    ),
    test_model().replace_conversation(conv),
  )
  let (_, failed) = update_dev(
    dispatch,
    Finished(
      run_id="r-failed",
      status="failed",
      answer=None,
      durable_sequence=None,
    ),
    accepted,
  )
  inspect(failed.active().input_ledger.length(), content="1")
  assert_true(failed.active().input_ledger[0].state is Unconfirmed)
  assert_true(failed.active().overlay[0].content.contains("must not disappear"))
  let (_, external_snapshot) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[
        {
          kind: User,
          content: "external writer only",
          ts: None,
          sequence: None,
        },
      ],
      watermark=1,
      event_boundaries=[(1, false, 1)],
      generation=1,
    ),
    failed,
  )
  // Unrelated durable text is not ownership proof for this exact prompt.
  inspect(external_snapshot.active().input_ledger.length(), content="1")
  assert_true(
    external_snapshot.active().overlay[0].content.contains("must not disappear"),
  )
}

///|
test "an old-host Started without an id is settled by the exact start response" {
  let dispatch = test_dispatch()
  let conv = with_initial_submission(
    { ..test_conversation(), run: Starting(submission_id="prompt-id") },
    "prompt-id",
    "prompt",
  )
  let (_, started) = update_dev(
    dispatch,
    Started(
      run_id="r-old-host",
      session="desktop-test",
      model=High,
      max_steps=1000,
      session_root=None,
      submission_id=None,
    ),
    test_model().replace_conversation(conv),
  )
  assert_true(started.active().run is Open(run_id="r-old-host", ..))
  inspect(started.active().input_ledger.length(), content="1")
  inspect(started.active().overlay.length(), content="1")
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
  assert_true(responded.active().run is Open(run_id="r-old-host", ..))
  inspect(responded.active().input_ledger.length(), content="1")
  assert_true(responded.active().input_ledger[0].run_id is Some("r-old-host"))
  inspect(responded.active().overlay.length(), content="1")
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
  inspect(responded.active().input_ledger.length(), content="1")
  inspect(
    responded.active().input_ledger[0].submission_id,
    content=second_submission,
  )
  assert_true(responded.active().input_ledger[0].state is Awaiting)
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
  inspect(responded.active().input_ledger.length(), content="1")
  inspect(
    responded.active().input_ledger[0].submission_id,
    content=second_submission,
  )
  assert_true(responded.active().input_ledger[0].state is Awaiting)
  inspect(responded.active().overlay.length(), content="0")
}

///|
test "runs settled closes runs the host no longer has, sparing live and starting ones" {
  let dispatch = test_dispatch()
  // A run that ended while this client was away: its terminal event is
  // gone for good, so only the `agent.runs` reply can close it.
  let stale = {
    ..empty_conversation(@interop.ChannelId::Local, "desktop-stale"),
    run: Open(run_id="r9", stage=AtStep(Some(4))),
    streaming_response: "mid-step",
  }
  // A send still in flight has no run id yet; its own `started` (or
  // failure) is coming and must be the one to settle it.
  let starting = {
    ..empty_conversation(@interop.ChannelId::Local, "desktop-starting"),
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
        steer_ids: [],
      },
      {
        session: "desktop-stale",
        state: SnapshotOpen(run_id="r9"),
        initial_ids: [],
        steer_ids: [],
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
  inspect(settled.streaming_response, content="")
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
  let conv = with_initial_submission(
    { ..test_conversation(), run: Starting(submission_id="pre-gap-start") },
    "pre-gap-start",
    "maybe accepted",
  )
  let (_, bridged) = update_dev(
    dispatch,
    @interop.ChannelId::Local.test_bridge_ready(),
    test_model().replace_conversation(conv),
  )
  assert_true(bridged.active().input_ledger[0].state is Unconfirmed)
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
test "an old empty runs snapshot cannot close a start sent after reconnect" {
  let dispatch = test_dispatch()
  let (_, ready) = update_dev(
    dispatch,
    @interop.ChannelId::Local.test_bridge_ready(),
    test_model(),
  )
  let (_, drafted) = update(dispatch, TaskChanged("new prompt"), ready)
  let (_, sent) = update(dispatch, Send, drafted)
  assert_true(sent.active().run is Starting(..))
  let (_, stale_snapshot) = update_dev(
    dispatch,
    RunsSettled(live=[], frontier=[]),
    sent,
  )
  assert_true(stale_snapshot.active().run is Starting(..))
}

///|
test "an older recovered ledger entry cannot adjudicate the current start" {
  let dispatch = test_dispatch()
  let old = with_initial_submission(
    test_conversation(),
    "pre-gap-start",
    "older prompt",
  )
  let (old, _) = old.mark_submission_unconfirmed(
    "pre-gap-start", "older delivery unconfirmed", false,
  )
  let current = with_initial_submission(
    { ..old, run: Starting(submission_id="current-start") },
    "current-start",
    "current prompt",
  )
  let (_, next) = update_dev(
    dispatch,
    RunsSettled(live=[], frontier=[
      {
        session: "desktop-test",
        state: SnapshotStarting(submission_id="pre-gap-start"),
        initial_ids: ["pre-gap-start"],
        steer_ids: [],
      },
    ]),
    test_model().replace_conversation(current),
  )
  assert_true(next.active().run is Starting(submission_id="current-start"))
  inspect(next.active().input_ledger.length(), content="2")
}

///|
test "an older start rejection cannot close the current start" {
  let dispatch = test_dispatch()
  let old = with_initial_submission(
    test_conversation(),
    "older-start",
    "older prompt",
  )
  let current = with_initial_submission(
    { ..old, run: Starting(submission_id="current-start") },
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
  inspect(next.active().input_ledger.length(), content="1")
  inspect(next.active().input_ledger[0].submission_id, content="current-start")
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
      model=High,
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
  let (_, generation_one) = update_dev(
    dispatch,
    @interop.ChannelId::Local.test_bridge_ready(),
    test_model(),
  )
  let stale = RunsLoaded(
    runs=[
      {
        run_id: "old-run",
        session: "old-session",
        model: High,
        max_steps: 1000,
        session_root: None,
        submission_id: None,
      },
    ],
    settled=[],
    live=["old-run"],
    frontier=generation_one.run_snapshot_frontier(@interop.ChannelId::Local),
    connection_generation=generation_one.dev().connection_generation,
  )
  let (_, generation_two) = update_dev(
    dispatch,
    @interop.ChannelId::Local.test_bridge_ready(),
    generation_one,
  )
  // The current generation's empty answer wins first. The delayed older
  // answer must then be rejected whole, before replaying its Started row.
  let (_, current) = update_dev(
    dispatch,
    RunsLoaded(
      runs=[],
      settled=[],
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
test "runs settlement restores a Starting prompt that reached exact-zero EOF offline" {
  let dispatch = test_dispatch()
  let submission_id = "offline-start"
  let before = test_model().replace_conversation(
    with_initial_submission(
      { ..test_conversation(), run: Starting(submission_id~), task: "" },
      submission_id,
      "restore after reconnect",
    ),
  )
  let frontier = before.run_snapshot_frontier(@interop.ChannelId::Local)
  let (_, bridged) = update_dev(
    dispatch,
    @interop.ChannelId::Local.test_bridge_ready(),
    before,
  )
  assert_true(bridged.active().sync is Reloading(..))
  let (_, recovered) = update_dev(
    dispatch,
    RunsLoaded(
      runs=[],
      settled=[
        {
          run_id: "run-offline-zero",
          session: "desktop-test",
          submission_id: Some(submission_id),
          status: "failed",
          durable_sequence: Some(0),
        },
      ],
      live=[],
      frontier~,
      connection_generation=bridged.dev().connection_generation,
    ),
    bridged,
  )
  assert_true(
    recovered.active().run is NoRun(ended=Some(RunFinished(RunFailed))),
  )
  assert_true(recovered.active().sync is Synced)
  inspect(recovered.active().task, content="restore after reconnect")
  inspect(recovered.active().input_ledger.length(), content="0")
  assert_true(recovered.active().overlay[0].reconciliation is Retained)
}

///|
test "a late durable boundary refetches a Starting settlement hidden by the first runs snapshot" {
  let dispatch = test_dispatch()
  let submission_id = "late-boundary-start"
  let before = test_model().replace_conversation(
    with_initial_submission(
      { ..test_conversation(), run: Starting(submission_id~), task: "" },
      submission_id,
      "restore after the boundary",
    ),
  )
  let first_frontier = before.run_snapshot_frontier(@interop.ChannelId::Local)
  // Finished has already removed the run, but its failed final scan has not
  // made the abnormal settlement replayable yet.
  let (_, absent) = update_dev(
    dispatch,
    RunsLoaded(
      runs=[],
      settled=[],
      live=[],
      frontier=first_frontier,
      connection_generation=before.dev().connection_generation,
    ),
    before,
  )
  assert_true(absent.active().run is NoRun(ended=None))
  assert_true(absent.active().last_run_id is None)
  assert_true(absent.active().has_recovering_initial())

  // The boundary cannot route by run id yet. It keeps the exact local owner
  // unchanged and schedules another current-generation agent.runs query.
  let (_, after_boundary) = update_dev(
    dispatch,
    DurableBoundary(
      run_id="run-late-boundary",
      session="desktop-test",
      sequence=0,
    ),
    absent,
  )
  assert_true(after_boundary.active().last_run_id is None)
  let second_frontier = after_boundary.run_snapshot_frontier(
    @interop.ChannelId::Local,
  )
  guard second_frontier is [captured] else {
    fail("late boundary lost the settlement selector")
  }
  assert_true(captured.initial_ids.contains(submission_id))

  // The host recorded agent.durable before broadcasting it, so that query
  // returns the newly replayable settlement and restores exact-zero input.
  let (_, recovered) = update_dev(
    dispatch,
    RunsLoaded(
      runs=[],
      settled=[
        {
          run_id: "run-late-boundary",
          session: "desktop-test",
          submission_id: Some(submission_id),
          status: "failed",
          durable_sequence: Some(0),
        },
      ],
      live=[],
      frontier=second_frontier,
      connection_generation=after_boundary.dev().connection_generation,
    ),
    after_boundary,
  )
  assert_true(recovered.active().sync is Synced)
  inspect(recovered.active().task, content="restore after the boundary")
  inspect(recovered.active().input_ledger.length(), content="0")
  assert_true(recovered.active().overlay[0].reconciliation is Retained)
}

///|
test "runs settlement recovers a transport-undelivered prompt by submission id" {
  let dispatch = test_dispatch()
  let submission_id = "socket-lost-start"
  let starting = test_model().replace_conversation(
    with_initial_submission(
      { ..test_conversation(), run: Starting(submission_id~), task: "" },
      submission_id,
      "restore after socket loss",
    ),
  )
  let (_, undelivered) = update_dev(
    dispatch,
    StartUndelivered(
      session="desktop-test",
      submission_id~,
      message="connection closed",
    ),
    starting,
  )
  assert_true(undelivered.active().run is NoRun(ended=Some(RunFailed)))
  assert_true(undelivered.active().input_ledger[0].run_id is None)
  let frontier = undelivered.run_snapshot_frontier(@interop.ChannelId::Local)
  let selectors = runs_payload(frontier).to_json()
  assert_true(
    selectors
    is {
      "known": Array(
        [
          {
            "session": "desktop-test",
            "submission_id": "socket-lost-start",
            ..
          },
        ]
      ),
      ..
    },
  )
  let (_, bridged) = update_dev(
    dispatch,
    @interop.ChannelId::Local.test_bridge_ready(),
    undelivered,
  )
  let (_, recovered) = update_dev(
    dispatch,
    RunsLoaded(
      runs=[],
      settled=[
        {
          run_id: "run-socket-lost-zero",
          session: "desktop-test",
          submission_id: Some(submission_id),
          status: "failed",
          durable_sequence: Some(0),
        },
      ],
      live=[],
      frontier~,
      connection_generation=bridged.dev().connection_generation,
    ),
    bridged,
  )
  assert_true(recovered.active().sync is Synced)
  inspect(recovered.active().task, content="restore after socket loss")
  inspect(recovered.active().input_ledger.length(), content="0")
  assert_true(recovered.active().overlay[0].reconciliation is Retained)
}

///|
test "runs settlement restores an Open prompt whose zero boundary was missed" {
  let dispatch = test_dispatch()
  let before = fresh_started_model(
    "offline-open", "run-offline-open", "restore open after reconnect",
  )
  let frontier = before.run_snapshot_frontier(@interop.ChannelId::Local)
  let (_, bridged) = update_dev(
    dispatch,
    @interop.ChannelId::Local.test_bridge_ready(),
    before,
  )
  let (_, recovered) = update_dev(
    dispatch,
    RunsLoaded(
      runs=[],
      settled=[
        {
          run_id: "run-offline-open",
          session: "desktop-test",
          submission_id: Some("offline-open"),
          status: "failed",
          durable_sequence: Some(0),
        },
      ],
      live=[],
      frontier~,
      connection_generation=bridged.dev().connection_generation,
    ),
    bridged,
  )
  assert_true(recovered.active().sync is Synced)
  inspect(recovered.active().task, content="restore open after reconnect")
  inspect(recovered.active().input_ledger.length(), content="0")
}

///|
test "one runs snapshot keeps an active successor after settling its predecessor" {
  let dispatch = test_dispatch()
  let before = fresh_started_model(
    "old-submission", "run-predecessor", "restore predecessor prompt",
  )
  let frontier = before.run_snapshot_frontier(@interop.ChannelId::Local)
  let (_, next) = update_dev(
    dispatch,
    RunsLoaded(
      runs=[
        {
          run_id: "run-successor",
          session: "desktop-test",
          model: High,
          max_steps: 1000,
          session_root: None,
          submission_id: Some("foreign-submission"),
        },
      ],
      settled=[
        {
          run_id: "run-predecessor",
          session: "desktop-test",
          submission_id: Some("old-submission"),
          status: "failed",
          durable_sequence: Some(0),
        },
      ],
      live=["run-successor"],
      frontier~,
      connection_generation=before.dev().connection_generation,
    ),
    before,
  )
  assert_true(next.active().run is Open(run_id="run-successor", ..))
  assert_true(next.active().last_run_id is Some("run-successor"))
  inspect(next.active().task, content="restore predecessor prompt")
  inspect(next.active().input_ledger.length(), content="0")
  assert_true(
    next.active().overlay
    .iter()
    .any(notice => {
      notice.reconciliation is Retained &&
      notice.content.contains("restored for resubmission")
    }),
  )
}

///|
test "a settlement captured for an older Starting owner cannot close its successor" {
  let dispatch = test_dispatch()
  let old = with_initial_submission(
    { ..test_conversation(), run: Starting(submission_id="old-owner") },
    "old-owner",
    "old prompt",
  )
  let frontier = test_model()
    .replace_conversation(old)
    .run_snapshot_frontier(@interop.ChannelId::Local)
  let current = with_initial_submission(
    { ..old, run: Starting(submission_id="new-owner") },
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
          durable_sequence: Some(0),
        },
      ],
      live=[],
      frontier~,
      connection_generation=model.dev().connection_generation,
    ),
    model,
  )
  assert_true(unchanged.active().run is Starting(submission_id="new-owner"))
  inspect(unchanged.active().input_ledger.length(), content="2")
}

///|
test "an older positive runs row cannot replace a newer Started" {
  let dispatch = test_dispatch()
  let model = running_model()
  let frontier = model.run_snapshot_frontier(@interop.ChannelId::Local)
  let (_, finished) = update_dev(
    dispatch,
    Finished(run_id="r7", status="finished", answer=None, durable_sequence=None),
    model,
  )
  let (_, newer) = update_dev(
    dispatch,
    Started(
      run_id="r8",
      session="desktop-test",
      model=High,
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
          model: High,
          max_steps: 1000,
          session_root: None,
          submission_id: None,
        },
      ],
      settled=[],
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
    Finished(run_id="r7", status="finished", answer=None, durable_sequence=None),
    model,
  )
  let (_, stale) = update_dev(
    dispatch,
    RunsLoaded(
      runs=[
        {
          run_id: "r7",
          session: "desktop-test",
          model: High,
          max_steps: 1000,
          session_root: None,
          submission_id: None,
        },
      ],
      settled=[],
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
  let finish : DeviceMsg = Finished(
    run_id="r7",
    status="finished",
    answer=None,
    durable_sequence=None,
  )
  let (_, once) = update_dev(dispatch, finish, settled)
  let (_, twice) = update_dev(dispatch, finish, once)
  assert_true(once.active().run is NoRun(ended=Some(RunFinished(Completed))))
  assert_true(twice.active().run is NoRun(ended=Some(RunFinished(Completed))))
  inspect(twice.active().overlay.length(), content="0")
}

///|
test "a failed start response keeps its prompt through an empty snapshot" {
  let dispatch = test_dispatch()
  let conv = {
    ..test_conversation(),
    run: Starting(submission_id="failed-start"),
  }.enqueue_input(
    InitialPrompt,
    "failed-start",
    None,
    "<user_mentions>serialized context</user_mentions>\nprompt",
    "prompt",
    [],
  )
  let (_, failed) = update_dev(
    dispatch,
    StartResponded(
      session="desktop-test",
      submission_id="failed-start",
      run_id="r-failed",
      status="failed",
      exit_code=1,
    ),
    test_model().replace_conversation(conv),
  )
  assert_true(failed.active().run is NoRun(ended=Some(RunFailed)))
  assert_true(failed.active().sync is Reloading(..))
  inspect(failed.active().input_ledger.length(), content="1")
  assert_true(failed.active().input_ledger[0].state is Unconfirmed)
  inspect(failed.active().input_ledger[0].draft, content="prompt")
  inspect(failed.active().overlay.length(), content="1")
  assert_true(failed.active().overlay[0].content.contains("prompt"))
  assert_false(failed.active().overlay[0].content.contains("<user_mentions>"))
  let (_, empty) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[],
      watermark=0,
      event_boundaries=[],
      generation=1,
    ),
    failed,
  )
  inspect(empty.active().input_ledger.length(), content="1")
  assert_true(empty.active().input_ledger[0].state is Unconfirmed)
  inspect(empty.active().visible_items().length(), content="1")
  assert_true(empty.active().visible_items()[0].content.contains("prompt"))
  let (_, late_started) = update_dev(
    dispatch,
    Started(
      run_id="r-failed",
      session="desktop-test",
      model=High,
      max_steps=1000,
      session_root=None,
      submission_id=Some("failed-start"),
    ),
    empty,
  )
  assert_true(late_started.active().run is NoRun(ended=Some(RunFailed)))
  // Lifecycle events do not change conversation placement. Scratch remains
  // the connected device root plus the durable session id.
  assert_true(
    late_started.conversation_root(late_started.active()) is Some(resource) &&
    resource.path == "/scratch/desktop-test",
  )
}

///|
test "a failed response after durable Finished cannot resurrect its prompt" {
  let dispatch = test_dispatch()
  let conv = with_initial_submission(
    { ..test_conversation(), run: Starting(submission_id="fast-start") },
    "fast-start",
    "fast prompt",
  )
  let (_, started) = update_dev(
    dispatch,
    Started(
      run_id="r-fast",
      session="desktop-test",
      model=High,
      max_steps=1000,
      session_root=None,
      submission_id=Some("fast-start"),
    ),
    test_model().replace_conversation(conv),
  )
  inspect(started.active().input_ledger.length(), content="1")
  let (_, finished) = update_dev(
    dispatch,
    Finished(
      run_id="r-fast",
      status="finished",
      answer=None,
      durable_sequence=None,
    ),
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
  inspect(failed.active().input_ledger.length(), content="0")
  inspect(failed.active().overlay.length(), content="0")
  let (_, empty) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[],
      watermark=0,
      event_boundaries=[],
      generation=1,
    ),
    failed,
  )
  assert_true(empty.active().run is NoRun(ended=Some(RunFinished(Completed))))
  inspect(empty.active().input_ledger.length(), content="0")
  inspect(empty.active().overlay.length(), content="0")
}

///|
test "an accepted response consumes a fast-finished prompt without reopening" {
  let dispatch = test_dispatch()
  let conv = with_initial_submission(
    {
      ..test_conversation(),
      run: NoRun(ended=Some(RunFinished(Completed))),
      last_run_id: Some("r-fast"),
    },
    "fast-start",
    "fast prompt",
  )
  let (conv, _) = conv.mark_submission_unconfirmed(
    "fast-start", "delivery unconfirmed: fast prompt", false,
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
  inspect(accepted.active().input_ledger.length(), content="0")
  inspect(accepted.active().overlay.length(), content="0")
}

///|
test "a newer Started retires an older unconfirmed start ledger entry" {
  let dispatch = test_dispatch()
  let old = with_initial_submission(
    { ..test_conversation(), run: NoRun(ended=Some(RunFailed)) },
    "old-start",
    "old prompt",
  )
  let (old, _) = old.mark_submission_unconfirmed(
    "old-start", "old delivery unconfirmed", false,
  )
  let current = with_initial_submission(
    { ..old, run: Starting(submission_id="new-start") },
    "new-start",
    "new prompt",
  )
  let (_, started) = update_dev(
    dispatch,
    Started(
      run_id="r-new",
      session="desktop-test",
      model=High,
      max_steps=1000,
      session_root=None,
      submission_id=Some("new-start"),
    ),
    test_model().replace_conversation(current),
  )
  inspect(started.active().input_ledger.length(), content="1")
  inspect(started.active().input_ledger[0].submission_id, content="new-start")
  inspect(started.active().overlay.length(), content="1")
  assert_true(started.active().overlay[0].reconciliation is Retained)
}

///|
test "concurrent conversations keep their streams apart" {
  let dispatch = test_dispatch()
  let second = {
    ..empty_conversation(@interop.ChannelId::Local, "desktop-second"),
    run: Open(run_id="r8", stage=Opened),
  }
  let model = running_model().replace_conversation(second)
  let (_, next) = update_dev(
    dispatch,
    Engine(Some("r8"), AssistantDelta("for B"), session=None),
    model,
  )
  // Run 8 belongs to the background conversation; the active one is untouched.
  inspect(next.active().streaming_response, content="")
  guard next.find_conversation(@interop.ChannelId::Local, "desktop-second")
    is Some(bg) else {
    fail("expected the background conversation")
  }
  inspect(bg.streaming_response, content="for B")
}

///|
test "a background run finishes without disturbing the conversation on screen" {
  let dispatch = test_dispatch()
  let second = {
    ..empty_conversation(@interop.ChannelId::Local, "desktop-second"),
    run: Open(run_id="r8", stage=Opened),
    messages: [
      { kind: User, content: "background ask", ts: None, sequence: None },
    ],
  }
  let model = running_model().replace_conversation(second)
  let (_, next) = update_dev(
    dispatch,
    Finished(
      run_id="r8",
      status="finished",
      answer=Some("done"),
      durable_sequence=None,
    ),
    model,
  )
  guard next.find_conversation(@interop.ChannelId::Local, "desktop-second")
    is Some(bg) else {
    fail("expected the background conversation")
  }
  inspect(bg.is_running(), content="false")
  assert_true(bg.run is NoRun(ended=Some(RunFinished(_))))
  inspect(bg.overlay.length(), content="0")
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
  inspect(once.active().pending_steers().length(), content="1")
  inspect(once.active().pending_steers()[0], content="focus on the tests")
  // The steer is pending, not part of the transcript yet.
  inspect(once.active().messages.length(), content="0")
  inspect(once.active().is_running(), content="true")
  inspect(twice.active().pending_steers().length(), content="1")
  inspect(twice.active().pending_steers()[0], content="focus on the tests")
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
  inspect(next.active().pending_steers().length(), content="0")
}

///|
test "the composer draft stays with its conversation across a switch" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..empty_conversation(@interop.ChannelId::Local, "desktop-second"),
    messages: [{ kind: User, content: "earlier", ts: None, sequence: None }],
  })
  let (_, drafted) = update(dispatch, TaskChanged("half a thought"), model)
  let (_, switched) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-second"),
    drafted,
  )
  // The other conversation starts with its own (empty) draft …
  inspect(switched.active().task, content="")
  let (_, back) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-test"),
    switched,
  )
  // … and the original draft is still waiting where it was typed.
  inspect(back.active().task, content="half a thought")
}

///|
test "update is pure: accepting an inline skill preserves prompt text" {
  let dispatch = test_dispatch()
  let model = {
    ..test_model(),
    installed_skills: [installed_skill("review-pr", "Review a pull request")],
  }
  let (_, drafted) = update(dispatch, TaskChanged("Please use $rev"), model)
  guard drafted.completion is Some(menu) else {
    fail("the inline skill token should open completion")
  }
  assert_eq(menu.menu.draft_without_token(), "Please use ")
  let (_, once) = update(dispatch, CompletionAccept, drafted)
  let (_, twice) = update(dispatch, CompletionAccept, drafted)
  // The same message and model always produce the same plain-data state.
  assert_eq(once.active().task, "Please use ")
  assert_eq(twice.active().task, "Please use ")
  assert_eq(once.active().mentions.length(), 1)
  assert_eq(twice.active().mentions.length(), 1)
  assert_true(
    once.active().mentions[0].ref_ is Skill(name="review-pr") &&
    twice.active().mentions[0].ref_ is Skill(name="review-pr"),
  )
  assert_true(once.completion is None && twice.completion is None)
}

///|
test "file index completion refreshes and accepts a workspace file" {
  let dispatch = test_dispatch()
  let owner : @interop.ConversationKey = {
    channel: Local,
    session: "desktop-test",
  }
  let base = test_model()
  let file_emit = dispatch.map(msg => FileEditor(msg))
  let (synced, _) = @fileeditor.sync(file_emit, base.file_panel, file_ctx(base))
  let (_, loading) = @fileeditor.update(
    file_emit,
    @fileeditor.EnsureFileIndex,
    synced,
    file_ctx(base),
  )
  let model = { ..base, file_panel: loading }
  let (_, searching) = update(dispatch, TaskChanged("Inspect @main"), model)
  guard searching.completion is Some(pending) else {
    fail("the inline file token should open completion")
  }
  assert_true(pending.kind is Files)
  assert_true(pending.menu.loading())
  assert_eq(pending.menu.length(), 0)
  let (_, loaded) = update(
    dispatch,
    FileEditor(
      @fileeditor.FilesIndexed(
        owner~,
        epoch=searching.file_panel.request_epoch,
        files=[@pathx.Relative("src/main.mbt")],
        truncated=false,
      ),
    ),
    searching,
  )
  guard loaded.completion is Some(menu) else {
    fail("the file-index reply should rebuild completion")
  }
  assert_false(menu.menu.loading())
  assert_eq(menu.menu.length(), 1)
  guard menu.menu.get(0) is Some(file) else { fail("file row expected") }
  assert_eq(file.label, "main.mbt")
  assert_eq(file.path, Some("src/main.mbt"))
  let (_, accepted) = update(dispatch, CompletionAccept, loaded)
  assert_eq(accepted.active().task, "Inspect ")
  assert_true(
    accepted.active().mentions ==
    [{ ref_: File(path="src/main.mbt"), range: None }],
  )
}

///|
test "file index failure settles an empty completion menu" {
  let dispatch = test_dispatch()
  let owner : @interop.ConversationKey = {
    channel: Local,
    session: "desktop-test",
  }
  let base = test_model()
  let file_emit = dispatch.map(msg => FileEditor(msg))
  let (synced, _) = @fileeditor.sync(file_emit, base.file_panel, file_ctx(base))
  let (_, loading) = @fileeditor.update(
    file_emit,
    @fileeditor.EnsureFileIndex,
    synced,
    file_ctx(base),
  )
  let (_, searching) = update(dispatch, TaskChanged("Inspect @missing"), {
    ..base,
    file_panel: loading,
  })
  let (_, failed) = update(
    dispatch,
    FileEditor(
      @fileeditor.FileIndexFailed(
        owner~,
        epoch=searching.file_panel.request_epoch,
      ),
    ),
    searching,
  )
  guard failed.completion is Some(menu) else {
    fail("a live @ token should retain its settled empty menu")
  }
  assert_true(menu.kind is Files)
  assert_false(menu.menu.loading())
  assert_eq(menu.menu.length(), 0)
}

///|
test "an inline symbol reply rebuilds the live completion menu" {
  let dispatch = test_dispatch()
  let (_, searching) = update(
    dispatch,
    TaskChanged("Inspect #parse"),
    test_model(),
  )
  guard searching.completion is Some(pending) else {
    fail("the inline symbol token should open completion")
  }
  assert_true(pending.kind is Symbols)
  assert_true(pending.menu.loading())
  assert_eq(pending.menu.draft_without_token(), "Inspect ")
  let item : WorkspaceSymbol = {
    name: "parse_hover",
    kind: Some(12),
    container: None,
    path: "src/main.mbt",
    range: @common.Range::Range(4, 2, 4, 13),
  }
  let (_, loaded) = update(
    dispatch,
    SymbolsLoaded(
      owner={ channel: Local, session: "desktop-test" },
      root=@interop.ChannelId::Local.test_resource("/scratch/desktop-test"),
      query="parse",
      generation=searching.completion_debounce.generation(),
      items=[item],
    ),
    searching,
  )
  guard loaded.completion is Some(menu) else {
    fail("the matching inline symbol reply should rebuild completion")
  }
  assert_false(menu.menu.loading())
  assert_eq(menu.menu.length(), 1)
  guard menu.menu.get(0) is Some(first) else { fail("row expected") }
  assert_eq(first.label, "parse_hover")
  assert_eq(menu.menu.draft_without_token(), "Inspect ")
}

///|
test "typing the same symbol query after a root change drops the old cache" {
  let dispatch = test_dispatch()
  let owner : @interop.ConversationKey = {
    channel: Local,
    session: "desktop-test",
  }
  let old_root = owner.channel.test_resource("/scratch/desktop-test")
  let cached = {
    ..test_model(),
    symbol_cache: {
      owner: Some(owner),
      root: Some(old_root),
      query: "parse",
      items: [
        CompletionItem::symbol(
          "parse_old_symbol",
          container=None,
          path="src/old.mbt",
          range=@common.Range::Range(1, 1, 1, 1),
        ),
      ],
    },
  }
  // No live `#` token means the root-change handler deliberately leaves the
  // cache alone until the composer next needs it.
  let (_, rerooted) = update_dev(
    dispatch,
    BridgeReady(scratch_root=owner.channel.test_resource("/next-scratch")),
    cached,
  )
  assert_eq(rerooted.symbol_cache.root, Some(old_root))
  let (_, querying) = update(dispatch, TaskChanged("#parse"), rerooted)
  assert_true(querying.symbol_cache.owner is None)
  guard querying.completion is Some(menu) else {
    fail("the symbol menu should open for the new root")
  }
  assert_true(menu.menu.loading())
  assert_eq(menu.menu.length(), 0)
}

///|
test "a composer symbol query restarts and fences replies when its root changes" {
  let dispatch = test_dispatch()
  let owner : @interop.ConversationKey = {
    channel: Local,
    session: "desktop-test",
  }
  let old_root = owner.channel.test_resource("/scratch/desktop-test")
  let item : WorkspaceSymbol = {
    name: "parse_old_symbol",
    kind: Some(12),
    container: None,
    path: "src/old.mbt",
    range: @common.Range::Range(1, 1, 1, 1),
  }
  let (_, querying) = update(dispatch, TaskChanged("#parse"), test_model())
  let (_, loaded) = update(
    dispatch,
    SymbolsLoaded(
      owner~,
      root=old_root,
      query="parse",
      generation=querying.completion_debounce.generation(),
      items=[item],
    ),
    querying,
  )
  guard loaded.completion is Some(ready) else {
    fail("the first root should settle the symbol menu")
  }
  assert_false(ready.menu.loading())
  assert_eq(ready.menu.length(), 1)

  let connected_root = owner.channel.test_resource("/next-scratch")
  let ready_msg = BridgeReady(scratch_root=connected_root)
  let (_, rerooted) = update_dev(dispatch, ready_msg, loaded)
  let (_, repeated) = update_dev(dispatch, ready_msg, loaded)
  assert_true(rerooted.symbol_cache == repeated.symbol_cache)
  assert_true(rerooted.completion == repeated.completion)
  assert_true(rerooted.symbol_cache.owner is None)
  guard rerooted.completion is Some(waiting) else {
    fail("the changed root should keep the symbol menu open")
  }
  assert_true(waiting.menu.loading())
  assert_eq(waiting.menu.length(), 0)

  let (_, stale) = update(
    dispatch,
    SymbolsLoaded(
      owner~,
      root=old_root,
      query="parse",
      generation=querying.completion_debounce.generation(),
      items=[item],
    ),
    rerooted,
  )
  assert_true(stale.symbol_cache.owner is None)
  assert_true(stale.completion == rerooted.completion)

  let new_root = owner.channel.test_resource("/next-scratch/desktop-test")
  let (_, settled) = update(
    dispatch,
    SymbolsLoaded(
      owner~,
      root=new_root,
      query="parse",
      generation=stale.completion_debounce.generation(),
      items=[item],
    ),
    stale,
  )
  guard settled.completion is Some(current) else {
    fail("the new root should settle the symbol menu")
  }
  assert_false(current.menu.loading())
  assert_eq(settled.symbol_cache.root, Some(new_root))
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
  inspect(next.active().pending_steers().length(), content="0")
  inspect(next.active().messages.length(), content="0")
  inspect(next.active().overlay.length(), content="0")
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
  inspect(next.active().pending_steers().length(), content="1")
  inspect(next.active().input_ledger.length(), content="1")
}

///|
test "a live commit dates its row on arrival, buffered or applied straight" {
  let dispatch = test_dispatch()
  let stamped = (session, sequence, ts) => {
    SessionCommitted(
      session~,
      sequence~,
      ts=Some(ts),
      item=@protocol.User({ content: "question" }),
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
  let (_, reconnecting) = update_dev(
    dispatch,
    @interop.ChannelId::Local.test_bridge_ready(),
    running_model(),
  )
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
      event_boundaries=[],
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
      item=@protocol.User({ content: "go left" }),
    ),
    model,
  )
  inspect(committed.active().messages.length(), content="1")
  inspect(committed.active().pending_steers().length(), content="1")
  inspect(committed.active().input_ledger.length(), content="1")
}

///|
test "a snapshot never settles a local steer by text" {
  let dispatch = test_dispatch()
  let conv = with_pending_steers(
    {
      ..running_conversation(),
      messages: [{ kind: User, content: "same", ts: None, sequence: None }],
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
      items=[{ kind: User, content: "same", ts: None, sequence: None }],
      watermark=1,
      event_boundaries=[],
      generation=1,
    ),
    model,
  )
  inspect(loaded.active().pending_steers().length(), content="1")
  inspect(loaded.active().input_ledger.length(), content="1")
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
  inspect(next.active().pending_steers().length(), content="0")
  inspect(next.active().overlay.length(), content="1")
  inspect(next.active().task, content="go left")
  guard next.active().overlay[0].kind is Assistant(is_danger=true) else {
    fail("expected an error bubble")
  }
  assert_true(next.active().overlay[0].content.contains("go left"))
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
  inspect(next.active().pending_steers().length(), content="1")
  inspect(next.active().pending_steers()[0], content="again")
  inspect(next.active().input_ledger[0].submission_id, content="test-steer-1")
  inspect(next.active().overlay.length(), content="0")
}

///|
test "an undelivered steer is reported instead of vanishing" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation(
    with_pending_steers(running_conversation(), ["lost"]),
  )
  let (_, next) = update_dev(
    dispatch,
    SteerUndelivered(
      session="desktop-test",
      submission_id="test-steer-0",
      text="lost",
      run_id="r7",
    ),
    model,
  )
  inspect(next.active().pending_steers().length(), content="0")
  inspect(next.active().input_ledger.length(), content="1")
  assert_true(next.active().input_ledger[0].state is Unconfirmed)
  inspect(next.active().overlay.length(), content="1")
  guard next.active().overlay[0].kind is Assistant(is_danger=true) else {
    fail("expected an error bubble")
  }
  assert_true(next.active().overlay[0].content.contains("lost"))
}

///|
test "a run that ends with steers in flight marks delivery unconfirmed" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation(
    with_pending_steers(running_conversation(), ["orphaned"]),
  )
  let (_, next) = update_dev(
    dispatch,
    Finished(
      run_id="r7",
      status="finished",
      answer=Some(""),
      durable_sequence=None,
    ),
    model,
  )
  inspect(next.active().pending_steers().length(), content="0")
  inspect(next.active().input_ledger.length(), content="1")
  inspect(next.active().is_running(), content="false")
  guard next.active().overlay[0].kind is Assistant(is_danger=true) else {
    fail("expected an error bubble")
  }
  assert_true(next.active().overlay[0].content.contains("orphaned"))
}

///|
test "a late exact applied receipt retracts a run-end unconfirmed notice" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation(
    with_pending_steers(running_conversation(), ["lost"]),
  )
  let (_, finished) = update_dev(
    dispatch,
    Finished(
      run_id="r7",
      status="finished",
      answer=Some(""),
      durable_sequence=None,
    ),
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
  inspect(next.active().pending_steers().length(), content="0")
  inspect(next.active().input_ledger.length(), content="0")
  inspect(next.active().overlay.length(), content="0")
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
  inspect(next.active().input_ledger.length(), content="1")
  assert_true(next.active().input_ledger[0].kind is InitialPrompt)
  inspect(next.active().overlay.length(), content="0")
}

///|
test "a trailing dropped receipt for run A restores input without closing run B" {
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
  assert_true(next.active().run is Open(run_id="r8", ..))
  assert_true(next.active().last_run_id is Some("r8"))
  inspect(next.active().input_ledger.length(), content="1")
  assert_true(next.active().input_ledger[0].kind is InitialPrompt)
  inspect(next.active().task, content="late steer")
  inspect(next.active().overlay.length(), content="1")
  assert_true(next.active().overlay[0].content.contains("late steer"))
}

///|
test "run-end unconfirmed notice follows assistant and terminal before freezing" {
  let dispatch = test_dispatch()
  let conv = with_pending_steers(
    {
      ..running_conversation(),
      messages: [{ kind: User, content: "question", ts: None, sequence: None }],
      watermark: 1,
    },
    ["late steer"],
  )
  let (_, finished) = update_dev(
    dispatch,
    Finished(
      run_id="r7",
      status="finished",
      answer=Some("answer"),
      durable_sequence=None,
    ),
    running_model().replace_conversation(conv),
  )
  let (_, buffered) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=2,
      ts=None,
      item=@protocol.Assistant({
        content: "answer",
        tool_calls: None,
        reasoning_content: None,
      }),
    ),
    finished,
  )
  let (_, buffered_terminal) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=3,
      ts=None,
      item=@protocol.Terminal(@protocol.Finished("answer")),
    ),
    buffered,
  )
  let (_, answered) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[
        { kind: User, content: "question", ts: None, sequence: None },
        {
          kind: Assistant(is_danger=false),
          content: "answer",
          ts: None,
          sequence: None,
        },
      ],
      watermark=3,
      event_boundaries=[(3, true, 2)],
      generation=1,
    ),
    buffered_terminal,
  )
  let visible = answered.active().visible_items()
  inspect(visible.length(), content="3")
  inspect(visible[1].content, content="answer")
  assert_true(visible[2].content.contains("late steer"))
  let (_, next_turn) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=4,
      ts=None,
      item=@protocol.User({ content: "next question" }),
    ),
    answered,
  )
  let visible = next_turn.active().visible_items()
  inspect(visible.length(), content="4")
  inspect(visible[1].content, content="answer")
  assert_true(visible[2].content.contains("late steer"))
  inspect(visible[3].content, content="next question")
}

///|
test "a snapshot freezes a prior run-tail notice before its next turn" {
  let dispatch = test_dispatch()
  let conv = with_pending_steers(
    {
      ..running_conversation(),
      messages: [{ kind: User, content: "question", ts: None, sequence: None }],
      watermark: 1,
    },
    ["late steer"],
  )
  let (_, finished) = update_dev(
    dispatch,
    Finished(run_id="r7", status="finished", answer=None, durable_sequence=None),
    running_model().replace_conversation(conv),
  )
  let (_, loaded) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[
        { kind: User, content: "question", ts: None, sequence: None },
        {
          kind: Assistant(is_danger=false),
          content: "first answer",
          ts: None,
          sequence: None,
        },
        { kind: User, content: "next question", ts: None, sequence: None },
        {
          kind: Assistant(is_danger=false),
          content: "next answer",
          ts: None,
          sequence: None,
        },
      ],
      watermark=7,
      event_boundaries=[(3, true, 2), (7, true, 4)],
      generation=1,
    ),
    finished,
  )
  let visible = loaded.active().visible_items()
  inspect(visible.length(), content="5")
  inspect(visible[0].content, content="question")
  inspect(visible[1].content, content="first answer")
  assert_true(visible[2].content.contains("late steer"))
  inspect(visible[3].content, content="next question")
  inspect(visible[4].content, content="next answer")
}

///|
test "a snapshot does not mistake a same-run steer User for the terminal boundary" {
  let dispatch = test_dispatch()
  let conv = with_pending_steers(
    {
      ..running_conversation(),
      messages: [{ kind: User, content: "question", ts: None, sequence: None }],
      watermark: 1,
      sync: test_reloading([]),
    },
    ["late steer"],
  )
  let model = running_model().replace_conversation(conv)
  let (_, steer_buffered) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=2,
      ts=None,
      item=@protocol.User({ content: "late steer" }),
    ),
    model,
  )
  let (_, finished) = update_dev(
    dispatch,
    Finished(run_id="r7", status="finished", answer=None, durable_sequence=None),
    steer_buffered,
  )
  let (_, answered) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=3,
      ts=None,
      item=@protocol.Assistant({
        content: "answer",
        tool_calls: None,
        reasoning_content: None,
      }),
    ),
    finished,
  )
  let (_, terminal) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=4,
      ts=None,
      item=@protocol.Terminal(@protocol.Finished("answer")),
    ),
    answered,
  )
  let (_, loaded) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[
        { kind: User, content: "question", ts: None, sequence: None },
        { kind: User, content: "late steer", ts: None, sequence: None },
        {
          kind: Assistant(is_danger=false),
          content: "answer",
          ts: None,
          sequence: None,
        },
      ],
      watermark=4,
      event_boundaries=[(4, true, 3)],
      generation=1,
    ),
    terminal,
  )
  let visible = loaded.active().visible_items()
  inspect(visible.length(), content="4")
  inspect(visible[1].content, content="late steer")
  inspect(visible[2].content, content="answer")
  assert_true(visible[3].content.contains("late steer"))
}

///|
test "an unknown terminal before Finished still owns the run-tail notice" {
  let dispatch = test_dispatch()
  let conv = with_pending_steers(
    {
      ..running_conversation(),
      messages: [
        { kind: User, content: "question", ts: None, sequence: None },
        {
          kind: Assistant(is_danger=false),
          content: "answer",
          ts: None,
          sequence: None,
        },
      ],
      watermark: 2,
    },
    ["late steer"],
  )
  let (_, committed) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=3,
      ts=None,
      item=@protocol.UnknownTerminal({
        "kind": "terminal",
        "payload": { "kind": "future_terminal", "message": "answer" },
      }),
    ),
    running_model().replace_conversation(conv),
  )
  inspect(committed.active().last_terminal_sequence, content="3")
  let (_, finished) = update_dev(
    dispatch,
    Finished(run_id="r7", status="finished", answer=None, durable_sequence=None),
    committed,
  )
  let (_, loaded) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[
        { kind: User, content: "question", ts: None, sequence: None },
        {
          kind: Assistant(is_danger=false),
          content: "answer",
          ts: None,
          sequence: None,
        },
      ],
      watermark=3,
      event_boundaries=[(3, true, 2)],
      generation=1,
    ),
    finished,
  )
  let visible = loaded.active().visible_items()
  inspect(visible.length(), content="3")
  inspect(visible[1].content, content="answer")
  assert_true(visible[2].content.contains("late steer"))
}

///|
test "a successor resolves an old terminal tail only from its causal snapshot" {
  let dispatch = test_dispatch()
  let conv = with_pending_steers(
    {
      ..running_conversation(),
      messages: [
        { kind: User, content: "first question", ts: None, sequence: None },
        {
          kind: Assistant(is_danger=false),
          content: "first answer",
          ts: None,
          sequence: None,
        },
      ],
      watermark: 2,
      run_durable_floor: Some(0),
      sync: test_reloading([]),
    },
    ["late steer"],
  )
  let model = {
    ..running_model().replace_conversation(conv),
    transcript_request_generation: 1,
  }
  // The old terminal commit beat Finished, so no future live commit can be
  // assumed to be the boundary for the notice Finished is about to create.
  let (_, committed) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=3,
      ts=None,
      item=@protocol.Terminal(@protocol.Finished("first answer")),
    ),
    model,
  )
  let (_, finished) = update_dev(
    dispatch,
    Finished(run_id="r7", status="finished", answer=None, durable_sequence=None),
    committed,
  )
  assert_true(
    finished.active().overlay[0].anchor
    is PriorTerminalTail(floor=0, snapshot_generation=2),
  )
  let (_, started) = update_dev(
    dispatch,
    Started(
      run_id="r8",
      session="desktop-test",
      model=High,
      max_steps=1000,
      session_root=None,
      submission_id=None,
    ),
    finished,
  )
  assert_true(
    started.active().overlay[0].anchor
    is PriorTerminalTail(floor=0, snapshot_generation=2),
  )
  let (_, second_user) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=4,
      ts=None,
      item=@protocol.User({ content: "second question" }),
    ),
    started,
  )
  let (_, second_terminal) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=5,
      ts=None,
      item=@protocol.Terminal(@protocol.Finished("second answer")),
    ),
    second_user,
  )
  // Generation 1 predates Finished and Started. It drains both runs' buffered
  // terminals, but neither anonymous live commit may place the notice.
  let (_, old_cut) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[
        { kind: User, content: "first question", ts: None, sequence: None },
        {
          kind: Assistant(is_danger=false),
          content: "first answer",
          ts: None,
          sequence: None,
        },
      ],
      watermark=2,
      event_boundaries=[(1, false, 1), (2, false, 2)],
      generation=1,
    ),
    second_terminal,
  )
  assert_true(old_cut.active().sync is Reloading(generation=2, ..))
  assert_true(old_cut.active().overlay[0].anchor is PriorTerminalTail(..))
  let (_, causal) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[
        { kind: User, content: "first question", ts: None, sequence: None },
        {
          kind: Assistant(is_danger=false),
          content: "first answer",
          ts: None,
          sequence: None,
        },
        { kind: User, content: "second question", ts: None, sequence: None },
        {
          kind: Assistant(is_danger=false),
          content: "second answer",
          ts: None,
          sequence: None,
        },
      ],
      watermark=5,
      event_boundaries=[
        (1, false, 1),
        (2, false, 2),
        (3, true, 2),
        (4, false, 3),
        (5, true, 4),
      ],
      generation=2,
    ),
    old_cut,
  )
  assert_true(causal.active().overlay[0].anchor is AfterMessages(2))
  let visible = causal.active().visible_items()
  inspect(visible.length(), content="5")
  assert_true(visible[2].content.contains("late steer"))
  inspect(visible[3].content, content="second question")
}

///|
test "a successor terminal cannot claim a setup-failed run's snapshot cut" {
  let dispatch = test_dispatch()
  let conv = with_pending_steers(
    {
      ..running_conversation(),
      watermark: 1,
      last_terminal_sequence: 1,
      run_durable_floor: Some(1),
    },
    ["late steer"],
  )
  let (_, setup_failed) = update_dev(
    dispatch,
    Error(
      run_id=Some("r7"),
      message="agent setup failed: boom",
      diagnostics=None,
      exit_code=None,
    ),
    running_model().replace_conversation(conv),
  )
  inspect(setup_failed.active().overlay.length(), content="0")
  let (_, finished) = update_dev(
    dispatch,
    Finished(run_id="r7", status="failed", answer=None, durable_sequence=None),
    setup_failed,
  )
  assert_true(
    finished.active().overlay[0].anchor is SnapshotCut(snapshot_generation=1),
  )
  let (_, started) = update_dev(
    dispatch,
    Started(
      run_id="r8",
      session="desktop-test",
      model=High,
      max_steps=1000,
      session_root=None,
      submission_id=None,
    ),
    finished,
  )
  assert_true(
    started.active().overlay[0].anchor is SnapshotCut(snapshot_generation=2),
  )
  let (_, old_cut) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[],
      watermark=1,
      event_boundaries=[(1, true, 0)],
      generation=1,
    ),
    started,
  )
  assert_true(old_cut.active().sync is Reloading(generation=2, ..))
  assert_true(
    old_cut.active().overlay[0].anchor is SnapshotCut(snapshot_generation=2),
  )
  let (_, causal) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[
        { kind: User, content: "next question", ts: None, sequence: None },
        {
          kind: Assistant(is_danger=false),
          content: "next answer",
          ts: None,
          sequence: None,
        },
      ],
      watermark=3,
      event_boundaries=[(1, true, 0), (2, false, 1), (3, true, 2)],
      generation=2,
    ),
    old_cut,
  )
  assert_true(causal.active().overlay[0].anchor is AfterMessages(2))
  assert_false(causal.active().has_unresolved_run_tail_notice())
  let visible = causal.active().visible_items()
  inspect(visible.length(), content="3")
  inspect(visible[0].content, content="next question")
  inspect(visible[1].content, content="next answer")
  assert_true(visible[2].content.contains("late steer"))
}

///|
test "an offline successor snapshot fences without claiming its terminal" {
  let dispatch = test_dispatch()
  let conv = with_pending_steers(
    {
      ..running_conversation(),
      watermark: 1,
      last_terminal_sequence: 1,
      run_durable_floor: Some(1),
    },
    ["unconfirmed steer"],
  )
  let (_, finished) = update_dev(
    dispatch,
    Finished(run_id="r7", status="failed", answer=None, durable_sequence=None),
    running_model().replace_conversation(conv),
  )
  // This page missed every lifecycle event for r8 while it was offline. The
  // snapshot's terminal therefore has no identity tying it to r7.
  let (_, loaded) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[
        { kind: User, content: "offline successor", ts: None, sequence: None },
        {
          kind: Assistant(is_danger=false),
          content: "successor answer",
          ts: None,
          sequence: None,
        },
      ],
      watermark=3,
      event_boundaries=[(1, true, 0), (2, false, 1), (3, true, 2)],
      generation=1,
    ),
    finished,
  )
  assert_true(loaded.active().overlay[0].anchor is AfterMessages(2))
  assert_false(loaded.active().has_unresolved_run_tail_notice())
}

///|
test "failure and abort statuses never assume a durable terminal" {
  let dispatch = test_dispatch()
  for status in ["failed", "aborted", "cancelled", "future_failure"] {
    let conv = with_pending_steers(running_conversation(), ["unconfirmed"])
    let (_, finished) = update_dev(
      dispatch,
      Finished(run_id="r7", status~, answer=None, durable_sequence=None),
      running_model().replace_conversation(conv),
    )
    guard finished.active().overlay is [notice] else {
      fail("expected one notice for " + status)
    }
    assert_true(notice.anchor is SnapshotCut(snapshot_generation=1))
  }
}

///|
test "a foreign run gains a floor only after snapshot data follows the prior terminal" {
  let dispatch = test_dispatch()
  let conv = {
    ..test_conversation(),
    messages: [
      {
        kind: Assistant(is_danger=false),
        content: "previous",
        ts: None,
        sequence: None,
      },
    ],
    watermark: 2,
    last_terminal_sequence: 2,
    sync: test_reloading([]),
  }
  let (_, started) = update_dev(
    dispatch,
    Started(
      run_id="foreign",
      session="desktop-test",
      model=High,
      max_steps=1000,
      session_root=None,
      submission_id=None,
    ),
    test_model().replace_conversation(conv),
  )
  assert_true(started.active().run_durable_floor is None)
  let (_, loaded) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[
        {
          kind: Assistant(is_danger=false),
          content: "previous",
          ts: None,
          sequence: None,
        },
        { kind: User, content: "current", ts: None, sequence: None },
      ],
      watermark=3,
      event_boundaries=[(2, true, 1)],
      generation=1,
    ),
    started,
  )
  assert_true(loaded.active().run_durable_floor is Some(2))
}

///|
test "a foreign background run waits for a snapshot cut after Started" {
  let dispatch = test_dispatch()
  let session = "desktop-background"
  let conv = {
    ..empty_conversation(@interop.ChannelId::Local, session),
    watermark: 1,
    last_terminal_sequence: 1,
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
      }),
    ),
    model,
  )
  let (_, started) = update_dev(
    dispatch,
    Started(
      run_id="foreign-next",
      session~,
      model=High,
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
  assert_true(started_conv.run_durable_floor is None)
  assert_true(started_conv.run_floor_generation is Some(2))
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
    ),
    started,
  )
  let (_, buffered_user) = update_dev(
    dispatch,
    SessionCommitted(
      session~,
      sequence=4,
      ts=None,
      item=@protocol.User({ content: "current question" }),
    ),
    buffered_terminal,
  )
  // Generation 1 predates Started. It may drain the ordered buffer, but it
  // cannot let the old answer claim the new run's floor.
  let (_, after_old_cut) = update_dev(
    dispatch,
    SessionRefreshed(
      session~,
      items=[],
      watermark=1,
      event_boundaries=[(1, true, 0)],
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
  assert_true(after_old.run_durable_floor is None)
  assert_true(after_old.run_floor_generation is Some(2))
  assert_true(after_old.sync is Reloading(generation=2, ..))
  inspect(after_old.last_terminal_sequence, content="3")
  let (_, causal) = update_dev(
    dispatch,
    SessionRefreshed(
      session~,
      items=[
        {
          kind: Assistant(is_danger=false),
          content: "previous answer",
          ts: None,
          sequence: None,
        },
        { kind: User, content: "current question", ts: None, sequence: None },
      ],
      watermark=4,
      event_boundaries=[
        (1, true, 0),
        (2, false, 1),
        (3, true, 1),
        (4, false, 2),
      ],
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
  assert_true(current.run_durable_floor is Some(3))
  assert_true(current.run_floor_generation is None)
}

///|
test "buffered future terminal cannot become its own run floor" {
  let dispatch = test_dispatch()
  let conv = {
    ..running_conversation(),
    watermark: 1,
    last_terminal_sequence: 1,
    run_durable_floor: None,
    sync: test_reloading([]),
  }
  let model = test_model().replace_conversation(conv)
  let (_, user) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=2,
      ts=None,
      item=@protocol.User({ content: "current question" }),
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
      }),
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
    ),
    answer,
  )
  // Buffered state is delivery, not applied chronology.
  inspect(terminal.active().last_terminal_sequence, content="1")
  let (_, loaded) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[],
      watermark=1,
      event_boundaries=[(1, true, 0)],
      generation=1,
    ),
    terminal,
  )
  assert_true(loaded.active().run_durable_floor is Some(1))
  inspect(loaded.active().last_terminal_sequence, content="4")
}

///|
test "a late durable EOF finalizes an unconfirmed steer without a terminal" {
  let dispatch = test_dispatch()
  let conv = with_pending_steers(
    {
      ..running_conversation(),
      watermark: 1,
      last_terminal_sequence: 1,
      run_durable_floor: Some(1),
    },
    ["late steer"],
  )
  let (_, errored) = update_dev(
    dispatch,
    Error(
      run_id=Some("r7"),
      message="engine exited without a result",
      diagnostics=None,
      exit_code=Some(1),
    ),
    test_model().replace_conversation(conv),
  )
  let (_, synthetic) = update_dev(
    dispatch,
    Finished(run_id="r7", status="failed", answer=None, durable_sequence=None),
    errored,
  )
  guard synthetic.active().overlay is [_, steer_notice] else {
    fail("expected the process error and unconfirmed steer notices")
  }
  assert_true(steer_notice.anchor is SnapshotCut(snapshot_generation=1))
  let (_, partial) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=2,
      ts=None,
      item=@protocol.Assistant({
        content: "partial answer",
        tool_calls: None,
        reasoning_content: None,
      }),
    ),
    synthetic,
  )
  // The real EOF consumer publishes a non-lifecycle boundary only after its
  // final scan, carrying the exact last sequence even though no Terminal was
  // appended.
  let (_, finalized) = update_dev(
    dispatch,
    DurableBoundary(run_id="r7", session="desktop-test", sequence=2),
    partial,
  )
  assert_true(finalized.active().overlay[1].anchor is DurableTail(2))
  let (_, loaded) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[
        {
          kind: Assistant(is_danger=false),
          content: "partial answer",
          ts: None,
          sequence: None,
        },
      ],
      watermark=2,
      event_boundaries=[(1, true, 0), (2, false, 1)],
      generation=1,
    ),
    finalized,
  )
  assert_true(loaded.active().overlay[1].anchor is AfterMessages(1))
  assert_false(loaded.active().has_unresolved_run_tail_notice())
  let visible = loaded.active().visible_items()
  inspect(visible.length(), content="3")
  inspect(visible[0].content, content="partial answer")
  assert_true(visible[1].content.contains("engine exited"))
  assert_true(visible[2].content.contains("late steer"))
}

///|
test "two run-tail notice groups freeze only at their own terminals" {
  let first = { ..test_conversation(), run_durable_floor: Some(1) }.append_run_tail_notice(
    Assistant(is_danger=true),
    "first",
    Retained,
  )
  let second = { ..first, run_durable_floor: Some(5) }.append_run_tail_notice(
    Assistant(is_danger=true),
    "second",
    Retained,
  )
  let frozen = second.freeze_run_tail_notices_from_snapshot(
    [(4, true, 2), (8, true, 4)],
    1,
  )
  assert_true(frozen.overlay[0].anchor is AfterMessages(2))
  assert_true(frozen.overlay[1].anchor is AfterMessages(4))
}

///|
test "only a causal gap-free snapshot may abandon a missing prior terminal" {
  let prior = { ..test_conversation(), run_durable_floor: Some(1) }
    .append_run_tail_notice(Assistant(is_danger=true), "old notice", Retained)
    .prepare_tail_notices_for_successor(2)
  let old_cut = prior
    .freeze_run_tail_notices_from_snapshot([], 1)
    .abandon_missing_prior_terminals(1, 0)
  assert_true(old_cut.overlay[0].anchor is PriorTerminalTail(..))
  let causal = old_cut
    .freeze_run_tail_notices_from_snapshot([], 2)
    .abandon_missing_prior_terminals(2, 0)
  assert_true(causal.overlay[0].anchor is AfterMessages(0))
}

///|
test "send waits while the durable transcript frontier is reloading" {
  let dispatch = test_dispatch()
  let conv = {
    ..running_conversation(),
    task: "do not send yet",
    sync: test_reloading([]),
  }
  let model = running_model().replace_conversation(conv)
  let (_, next) = update(dispatch, Send, model)
  inspect(next.active().task, content="do not send yet")
  inspect(next.active().input_ledger.length(), content="0")
}

///|
test "runs settled keeps exact steer ownership without notice growth" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation(
    with_pending_steers(running_conversation(), ["lost"]),
  )
  let frontier = model.run_snapshot_frontier(@interop.ChannelId::Local)
  let (_, once) = update_dev(dispatch, RunsSettled(live=[], frontier~), model)
  inspect(once.active().input_ledger.length(), content="1")
  assert_true(once.active().input_ledger[0].state is Unconfirmed)
  inspect(once.active().overlay.length(), content="1")
  assert_true(
    once.active().overlay[0].reconciliation is Submission("test-steer-0"),
  )
  let (_, twice) = update_dev(dispatch, RunsSettled(live=[], frontier~), once)
  inspect(twice.active().input_ledger.length(), content="1")
  inspect(twice.active().overlay.length(), content="1")
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
  inspect(applied.active().input_ledger.length(), content="0")
  inspect(applied.active().overlay.length(), content="0")
}

///|
test "a trailing dropped receipt restores input after an empty runs snapshot" {
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
  inspect(dropped.active().input_ledger.length(), content="0")
  inspect(dropped.active().task, content="late dropped")
  inspect(dropped.active().overlay.length(), content="1")
  assert_true(dropped.active().overlay[0].content.contains("late dropped"))
}

///|
test "a successor step cannot retire an older steer before its RPC rejection" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation(
    with_pending_steers(running_conversation(), ["late rejection"]),
  )
  let frontier = model.run_snapshot_frontier(@interop.ChannelId::Local)
  let (_, settled) = update_dev(
    dispatch,
    RunsSettled(live=[], frontier~),
    model,
  )
  let (_, started) = update_dev(
    dispatch,
    Started(
      run_id="r8",
      session="desktop-test",
      model=High,
      max_steps=1000,
      session_root=None,
      submission_id=None,
    ),
    settled,
  )
  let (_, stepped) = update_dev(
    dispatch,
    Engine(Some("r8"), AgentStep(Some(1)), session=None),
    started,
  )
  inspect(stepped.active().input_ledger.length(), content="1")
  let (_, rejected) = update_dev(
    dispatch,
    SteerRejected(
      session="desktop-test",
      submission_id="test-steer-0",
      text="late rejection",
      run_id="r7",
    ),
    stepped,
  )
  assert_true(rejected.active().run is Open(run_id="r8", ..))
  inspect(rejected.active().input_ledger.length(), content="0")
  inspect(rejected.active().task, content="late rejection")
}

///|
test "a runs snapshot cannot retire a steer submitted after its frontier" {
  let dispatch = test_dispatch()
  let model = running_model()
  let frontier = model.run_snapshot_frontier(@interop.ChannelId::Local)
  let (_, drafted) = update(dispatch, TaskChanged("post-snapshot steer"), model)
  let (_, steered) = update(dispatch, Send, drafted)
  guard steered.active().input_ledger is [pending] else {
    fail("expected one steer awaiting its exact receipt")
  }
  let submission_id = pending.submission_id
  assert_true(pending.state is Awaiting)
  let (_, settled) = update_dev(
    dispatch,
    RunsSettled(live=[], frontier~),
    steered,
  )
  assert_true(settled.active().run is NoRun(ended=None))
  guard settled.active().input_ledger is [still_pending] else {
    fail("the older runs reply retired a newer steer")
  }
  assert_eq(still_pending.submission_id, submission_id)
  assert_true(still_pending.state is Awaiting)
  let (_, r2_started) = update_dev(
    dispatch,
    Started(
      run_id="r8",
      session="desktop-test",
      model=High,
      max_steps=1000,
      session_root=None,
      submission_id=None,
    ),
    settled,
  )
  let (_, after_r2) = update_dev(
    dispatch,
    Finished(run_id="r8", status="finished", answer=None, durable_sequence=None),
    r2_started,
  )
  guard after_r2.active().input_ledger is [still_r1] else {
    fail("the successor finish consumed an older run's steer")
  }
  assert_eq(still_r1.submission_id, submission_id)
  assert_true(still_r1.state is Awaiting)
  inspect(after_r2.active().overlay.length(), content="0")
  // With no transcript, draft, overlay, or live run, exact ownership is the
  // only reason this conversation survives a switch.
  let other = {
    ..empty_conversation(@interop.ChannelId::Local, "desktop-other"),
    messages: [
      { kind: User, content: "other conversation", ts: None, sequence: None },
    ],
  }
  let (_, switched) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-other"),
    after_r2.replace_conversation(other),
  )
  guard switched.find_conversation(@interop.ChannelId::Local, "desktop-test")
    is Some(retained) else {
    fail("switching conversations pruned exact steer ownership")
  }
  assert_true(retained.has_begun())
  let (_, rejected) = update_dev(
    dispatch,
    SteerRejected(
      session="desktop-test",
      submission_id~,
      text="post-snapshot steer",
      run_id="r7",
    ),
    switched,
  )
  guard rejected.find_conversation(@interop.ChannelId::Local, "desktop-test")
    is Some(restored) else {
    fail("late rejection lost its conversation")
  }
  inspect(restored.input_ledger.length(), content="0")
  inspect(restored.task, content="post-snapshot steer")
}

///|
test "runs settlement releases after a causal cut and keeps exact receipt" {
  let dispatch = test_dispatch()
  let conv = with_pending_steers(
    {
      ..running_conversation(),
      watermark: 2,
      last_terminal_sequence: 2,
      run_durable_floor: Some(2),
      sync: test_reloading([]),
    },
    ["captured steer"],
  )
  let model = {
    ..running_model().replace_conversation(conv),
    transcript_request_generation: 1,
  }
  let frontier = model.run_snapshot_frontier(@interop.ChannelId::Local)
  let (_, snapshot_first) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[],
      watermark=3,
      event_boundaries=[(3, true, 0)],
      generation=1,
    ),
    model,
  )
  assert_true(snapshot_first.active().sync is Synced)
  let (_, settled) = update_dev(
    dispatch,
    RunsSettled(live=[], frontier~),
    snapshot_first,
  )
  assert_true(settled.active().sync is Reloading(generation=2, ..))
  assert_true(settled.active().has_unresolved_run_tail_notice())
  let (_, reconciled) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[],
      watermark=3,
      event_boundaries=[(3, true, 0)],
      generation=2,
    ),
    settled,
  )
  assert_true(reconciled.active().sync is Synced)
  assert_true(reconciled.active().overlay[0].anchor is AfterMessages(0))
  assert_false(reconciled.active().has_unresolved_run_tail_notice())
  inspect(reconciled.active().input_ledger.length(), content="1")
  let (_, drafted) = update(dispatch, TaskChanged("next prompt"), reconciled)
  let (_, sent) = update(dispatch, Send, drafted)
  assert_true(sent.active().run is Starting(..))
  let (_, received) = update_dev(
    dispatch,
    Engine(
      Some("r7"),
      SteerApplied(content="captured steer", submission_id=Some("test-steer-0")),
      session=None,
    ),
    sent,
  )
  assert_false(received.active().has_unresolved_run_tail_notice())
  inspect(received.active().overlay.length(), content="0")
  inspect(received.active().input_ledger.length(), content="1")
}

///|
test "a late normal Finished upgrades a runs-settled uncertain steer" {
  let dispatch = test_dispatch()
  let conv = with_pending_steers(
    {
      ..running_conversation(),
      watermark: 1,
      last_terminal_sequence: 1,
      run_durable_floor: Some(1),
    },
    ["captured steer"],
  )
  let model = running_model().replace_conversation(conv)
  let frontier = model.run_snapshot_frontier(@interop.ChannelId::Local)
  let (_, settled) = update_dev(
    dispatch,
    RunsSettled(live=[], frontier~),
    model,
  )
  assert_true(
    settled.active().overlay[0].anchor is SnapshotCut(snapshot_generation=1),
  )
  let finish : DeviceMsg = Finished(
    run_id="r7",
    status="finished",
    answer=None,
    durable_sequence=None,
  )
  let (_, finished) = update_dev(dispatch, finish, settled)
  assert_true(
    finished.active().overlay[0].anchor
    is PriorTerminalTail(floor=1, snapshot_generation=2),
  )
  let (_, duplicate) = update_dev(dispatch, finish, finished)
  assert_true(
    duplicate.active().overlay[0].anchor
    is PriorTerminalTail(floor=1, snapshot_generation=2),
  )
  let (_, old_cut) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[],
      watermark=1,
      event_boundaries=[(1, true, 0)],
      generation=1,
    ),
    duplicate,
  )
  assert_true(old_cut.active().sync is Reloading(generation=2, ..))
  assert_true(old_cut.active().overlay[0].anchor is PriorTerminalTail(..))
  let (_, causal) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[
        {
          kind: Assistant(is_danger=false),
          content: "answer",
          ts: None,
          sequence: None,
        },
      ],
      watermark=2,
      event_boundaries=[(1, true, 0), (2, true, 1)],
      generation=2,
    ),
    old_cut,
  )
  assert_true(causal.active().overlay[0].anchor is AfterMessages(1))
  assert_false(causal.active().has_unresolved_run_tail_notice())
  let (_, after_duplicate) = update_dev(dispatch, finish, causal)
  assert_true(after_duplicate.active().overlay[0].anchor is AfterMessages(1))
  assert_false(after_duplicate.active().has_unresolved_run_tail_notice())
}

///|
test "a late failed Finished preserves a runs-settled snapshot cut" {
  let dispatch = test_dispatch()
  let conv = with_pending_steers(running_conversation(), ["captured steer"])
  let model = running_model().replace_conversation(conv)
  let frontier = model.run_snapshot_frontier(@interop.ChannelId::Local)
  let (_, settled) = update_dev(
    dispatch,
    RunsSettled(live=[], frontier~),
    model,
  )
  let finish : DeviceMsg = Finished(
    run_id="r7",
    status="failed",
    answer=None,
    durable_sequence=None,
  )
  let (_, finished) = update_dev(dispatch, finish, settled)
  assert_true(
    finished.active().overlay[0].anchor is SnapshotCut(snapshot_generation=1),
  )
  assert_true(finished.active().has_unresolved_run_tail_notice())
  let (_, finalized) = update_dev(
    dispatch,
    DurableBoundary(run_id="r7", session="desktop-test", sequence=1),
    finished,
  )
  assert_true(finalized.active().overlay[0].anchor is DurableTail(1))
  let (_, duplicate) = update_dev(dispatch, finish, finalized)
  assert_true(duplicate.active().overlay[0].anchor is DurableTail(1))
  assert_true(duplicate.active().has_unresolved_run_tail_notice())
}

///|
test "runs settlement follows an older in-flight transcript cut" {
  let dispatch = test_dispatch()
  let conv = with_pending_steers(
    { ..running_conversation(), sync: test_reloading([]) },
    ["captured steer"],
  )
  let model = {
    ..running_model().replace_conversation(conv),
    transcript_request_generation: 1,
  }
  let frontier = model.run_snapshot_frontier(@interop.ChannelId::Local)
  let (_, settled) = update_dev(
    dispatch,
    RunsSettled(live=[], frontier~),
    model,
  )
  assert_true(
    settled.active().sync
    is Reloading(generation=1, reload_after_current=true, ..),
  )
  let (_, first_cut) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[],
      watermark=1,
      event_boundaries=[(1, true, 0)],
      generation=1,
    ),
    settled,
  )
  assert_true(first_cut.active().sync is Reloading(generation=2, ..))
}

///|
test "duplicate abnormal Finished keeps an initial prompt on one causal cut" {
  let dispatch = test_dispatch()
  let conv = with_initial_submission(
    running_conversation(),
    "prompt-id",
    "recover this prompt",
  ).bind_initial_submission_to_run("prompt-id", "r7")
  let finish : DeviceMsg = Finished(
    run_id="r7",
    status="failed",
    answer=None,
    durable_sequence=None,
  )
  let (_, once) = update_dev(
    dispatch,
    finish,
    running_model().replace_conversation(conv),
  )
  guard once.active().overlay is [first_notice] else {
    fail("the failed run should leave one recoverable prompt notice")
  }
  assert_true(first_notice.anchor is SnapshotCut(snapshot_generation=1))
  assert_true(once.active().sync is Reloading(generation=1, ..))
  let (_, twice) = update_dev(dispatch, finish, once)
  guard twice.active().overlay is [duplicate_notice] else {
    fail("duplicate Finished must not grow the prompt notice set")
  }
  assert_true(duplicate_notice.anchor is SnapshotCut(snapshot_generation=1))
  assert_true(twice.active().sync is Reloading(generation=1, ..))
  let (_, reconciled) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[],
      watermark=0,
      event_boundaries=[],
      generation=1,
    ),
    twice,
  )
  assert_true(reconciled.active().sync is Synced)
  assert_true(reconciled.active().overlay[0].anchor is AfterMessages(0))
  assert_false(reconciled.active().has_unresolved_run_tail_notice())
  inspect(reconciled.active().input_ledger.length(), content="1")
  assert_true(reconciled.active().input_ledger[0].state is Unconfirmed)
}

///|
test "runs settlement causally freezes bound initial prompts from open and idle frontiers" {
  let dispatch = test_dispatch()
  let open_conv = with_initial_submission(
    running_conversation(),
    "open-prompt",
    "prompt from the open run",
  ).bind_initial_submission_to_run("open-prompt", "r7")
  let open_model = running_model().replace_conversation(open_conv)
  let (_, open_settled) = update_dev(
    dispatch,
    RunsSettled(
      live=[],
      frontier=open_model.run_snapshot_frontier(@interop.ChannelId::Local),
    ),
    open_model,
  )
  assert_true(open_settled.active().run is NoRun(ended=None))
  assert_true(open_settled.active().input_ledger[0].state is Unconfirmed)
  assert_true(
    open_settled.active().overlay[0].anchor
    is SnapshotCut(snapshot_generation=1),
  )
  assert_true(open_settled.active().sync is Reloading(generation=1, ..))
  let (_, open_frozen) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[
        {
          kind: User,
          content: "open-run durable tail",
          ts: None,
          sequence: None,
        },
      ],
      watermark=1,
      event_boundaries=[(1, false, 1)],
      generation=1,
    ),
    open_settled,
  )
  assert_true(open_frozen.active().overlay[0].anchor is AfterMessages(1))
  assert_false(open_frozen.active().has_unresolved_run_tail_notice())
  inspect(open_frozen.active().input_ledger.length(), content="1")

  let idle_bound = with_initial_submission(
    { ..test_conversation(), run: NoRun(ended=None), last_run_id: Some("r7") },
    "idle-prompt",
    "prompt from the idle run",
  ).bind_initial_submission_to_run("idle-prompt", "r7")
  let (idle_conv, marked) = idle_bound.mark_submission_unconfirmed(
    "idle-prompt", "existing uncertain prompt notice", false,
  )
  assert_true(marked)
  let idle_model = test_model().replace_conversation(idle_conv)
  let (_, idle_settled) = update_dev(
    dispatch,
    RunsSettled(
      live=[],
      frontier=idle_model.run_snapshot_frontier(@interop.ChannelId::Local),
    ),
    idle_model,
  )
  assert_true(idle_settled.active().input_ledger[0].state is Unconfirmed)
  assert_true(
    idle_settled.active().overlay[0].anchor
    is SnapshotCut(snapshot_generation=1),
  )
  assert_true(idle_settled.active().sync is Reloading(generation=1, ..))
  let (_, idle_frozen) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[
        {
          kind: Assistant(is_danger=false),
          content: "idle-run durable tail",
          ts: None,
          sequence: None,
        },
      ],
      watermark=1,
      event_boundaries=[(1, false, 1)],
      generation=1,
    ),
    idle_settled,
  )
  assert_true(idle_frozen.active().overlay[0].anchor is AfterMessages(1))
  assert_false(idle_frozen.active().has_unresolved_run_tail_notice())
  inspect(idle_frozen.active().input_ledger.length(), content="1")
}

///|
test "an initial warning freezes between a snapshot and its buffered successor" {
  let dispatch = test_dispatch()
  let conv = with_initial_submission(
    running_conversation(),
    "prompt-id",
    "prompt awaiting proof",
  ).bind_initial_submission_to_run("prompt-id", "r7")
  let (_, finished) = update_dev(
    dispatch,
    Finished(run_id="r7", status="failed", answer=None, durable_sequence=None),
    running_model().replace_conversation(conv),
  )
  let (_, buffered) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=2,
      ts=None,
      item=@protocol.User({ content: "buffered W+1" }),
    ),
    finished,
  )
  guard buffered.active().sync is Reloading(buffered=commits, ..) else {
    fail("the post-cut commit should wait behind the snapshot")
  }
  inspect(commits.length(), content="1")
  let (_, reconciled) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[{ kind: User, content: "snapshot W", ts: None, sequence: None }],
      watermark=1,
      event_boundaries=[(1, false, 1)],
      generation=1,
    ),
    buffered,
  )
  assert_true(reconciled.active().sync is Synced)
  assert_true(reconciled.active().overlay[0].anchor is AfterMessages(1))
  inspect(reconciled.active().watermark, content="2")
  let visible = reconciled.active().visible_items()
  inspect(visible.length(), content="3")
  inspect(visible[0].content, content="snapshot W")
  assert_true(visible[1].content.contains("prompt awaiting proof"))
  inspect(visible[2].content, content="buffered W+1")
}

///|
test "foreign Started reanchors a reconnected initial before retiring its ownership" {
  let dispatch = test_dispatch()
  let conv = with_initial_submission(
    running_conversation(),
    "old-prompt",
    "old prompt",
  ).bind_initial_submission_to_run("old-prompt", "r7")
  let (_, bridged) = update_dev(
    dispatch,
    @interop.ChannelId::Local.test_bridge_ready(),
    running_model().replace_conversation(conv),
  )
  assert_true(bridged.active().input_ledger[0].state is Unconfirmed)
  assert_true(
    bridged.active().overlay[0].anchor is SnapshotCut(snapshot_generation=1),
  )
  assert_true(bridged.active().sync is Reloading(generation=1, ..))
  let (_, started) = update_dev(
    dispatch,
    Started(
      run_id="r8",
      session="desktop-test",
      model=High,
      max_steps=1000,
      session_root=None,
      submission_id=Some("foreign-prompt"),
    ),
    bridged,
  )
  inspect(started.active().input_ledger.length(), content="0")
  guard started.active().overlay is [retired_notice] else {
    fail("the old prompt warning should survive as a retained notice")
  }
  assert_true(retired_notice.reconciliation is Retained)
  assert_true(retired_notice.anchor is SnapshotCut(snapshot_generation=2))
  assert_true(
    started.active().sync
    is Reloading(generation=1, reload_after_current=true, ..),
  )
  let (_, old_cut) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[
        { kind: User, content: "old durable prompt", ts: None, sequence: None },
      ],
      watermark=1,
      event_boundaries=[(1, false, 1)],
      generation=1,
    ),
    started,
  )
  assert_true(old_cut.active().sync is Reloading(generation=2, ..))
  assert_true(
    old_cut.active().overlay[0].anchor is SnapshotCut(snapshot_generation=2),
  )
  let (_, causal) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[
        { kind: User, content: "old durable prompt", ts: None, sequence: None },
      ],
      watermark=1,
      event_boundaries=[(1, false, 1)],
      generation=2,
    ),
    old_cut,
  )
  assert_true(causal.active().sync is Synced)
  assert_true(causal.active().overlay[0].anchor is AfterMessages(1))
  let visible = causal.active().visible_items()
  inspect(visible.length(), content="2")
  inspect(visible[0].content, content="old durable prompt")
  assert_true(visible[1].content.contains("old prompt"))
}

///|
test "an exact zero abnormal EOF releases a fresh prompt for another send" {
  let dispatch = test_dispatch()
  let conv = with_initial_submission(
    { ..test_conversation(), run: Starting(submission_id="fresh-prompt") },
    "fresh-prompt",
    "prompt before setup failure",
  )
  let (_, started) = update_dev(
    dispatch,
    Started(
      run_id="r-fresh",
      session="desktop-test",
      model=High,
      max_steps=1000,
      session_root=None,
      submission_id=Some("fresh-prompt"),
    ),
    test_model().replace_conversation(conv),
  )
  assert_true(started.active().sync is Reloading(generation=1, ..))
  let (_, failed) = update_dev(
    dispatch,
    Finished(
      run_id="r-fresh",
      status="failed",
      answer=None,
      durable_sequence=Some(0),
    ),
    started,
  )
  assert_true(failed.active().sync is Synced)
  assert_true(failed.active().run is NoRun(ended=Some(RunFinished(RunFailed))))
  inspect(failed.active().input_ledger.length(), content="0")
  inspect(failed.active().task, content="prompt before setup failure")
  assert_true(failed.active().overlay[0].anchor is AfterMessages(0))
  assert_true(failed.active().overlay[0].reconciliation is Retained)
  assert_true(
    failed.active().visible_items()[0].content.contains(
      "restored for resubmission",
    ),
  )
  assert_false(failed.active().has_unresolved_run_tail_notice())
  let (_, retried) = update(dispatch, Send, failed)
  assert_true(retried.active().run is Starting(..))
  inspect(retried.active().task, content="")
  inspect(retried.active().input_ledger.length(), content="1")
}

///|
test "late start responses cannot reopen an exact-zero recovery read" {
  let dispatch = test_dispatch()
  let started = fresh_started_model(
    "late-response-prompt", "r-late-response", "restore before the response",
  )
  let (_, recovered) = update_dev(
    dispatch,
    Finished(
      run_id="r-late-response",
      status="failed",
      answer=None,
      durable_sequence=Some(0),
    ),
    started,
  )
  assert_true(recovered.active().sync is Synced)
  inspect(recovered.active().input_ledger.length(), content="0")
  let generation = recovered.transcript_request_generation
  let (_, accepted) = update_dev(
    dispatch,
    StartResponded(
      session="desktop-test",
      submission_id="late-response-prompt",
      run_id="r-late-response",
      status="accepted",
      exit_code=0,
    ),
    recovered,
  )
  assert_true(accepted.active().sync is Synced)
  assert_eq(accepted.transcript_request_generation, generation)
  inspect(accepted.active().task, content="restore before the response")
  inspect(accepted.active().input_ledger.length(), content="0")
  let (_, failed) = update_dev(
    dispatch,
    StartResponded(
      session="desktop-test",
      submission_id="late-response-prompt",
      run_id="r-late-response",
      status="failed",
      exit_code=1,
    ),
    recovered,
  )
  assert_true(failed.active().sync is Synced)
  assert_eq(failed.transcript_request_generation, generation)
  inspect(failed.active().task, content="restore before the response")
  inspect(failed.active().input_ledger.length(), content="0")
}

///|
test "BridgeReady does not probe a record disproved by exact-zero EOF" {
  let dispatch = test_dispatch()
  let started = fresh_started_model(
    "reconnect-zero-prompt", "r-reconnect-zero", "restore across reconnect",
  )
  let (_, recovered) = update_dev(
    dispatch,
    Finished(
      run_id="r-reconnect-zero",
      status="failed",
      answer=None,
      durable_sequence=Some(0),
    ),
    started,
  )
  let generation = recovered.transcript_request_generation
  let (_, reconnected) = update_dev(
    dispatch,
    @interop.ChannelId::Local.test_bridge_ready(),
    recovered,
  )
  assert_true(reconnected.active().sync is Synced)
  assert_eq(reconnected.transcript_request_generation, generation)
  inspect(reconnected.active().task, content="restore across reconnect")
  inspect(reconnected.active().input_ledger.length(), content="0")
  assert_true(reconnected.active().overlay[0].reconciliation is Retained)
}

///|
test "a late exact-zero durable boundary recovers from active and failed reloads" {
  let dispatch = test_dispatch()
  let reloading_started = fresh_started_model(
    "reloading-zero-prompt", "r-reloading-zero", "restore from reloading",
  )
  let (_, reloading) = update_dev(
    dispatch,
    Finished(
      run_id="r-reloading-zero",
      status="failed",
      answer=None,
      durable_sequence=None,
    ),
    reloading_started,
  )
  assert_true(reloading.active().sync is Reloading(..))
  let (_, recovered_reloading) = update_dev(
    dispatch,
    DurableBoundary(
      run_id="r-reloading-zero",
      session="desktop-test",
      sequence=0,
    ),
    reloading,
  )
  assert_true(recovered_reloading.active().sync is Synced)
  inspect(recovered_reloading.active().task, content="restore from reloading")
  inspect(recovered_reloading.active().input_ledger.length(), content="0")
  assert_true(
    recovered_reloading.active().overlay[0].reconciliation is Retained,
  )

  let failed_started = fresh_started_model(
    "failed-zero-prompt", "r-failed-zero", "restore from failed reload",
  )
  let (_, waiting) = update_dev(
    dispatch,
    Finished(
      run_id="r-failed-zero",
      status="failed",
      answer=None,
      durable_sequence=None,
    ),
    failed_started,
  )
  let failed_reload = waiting.replace_conversation({
    ..waiting.active(),
    sync: ReloadFailed(generation=1, buffered=[]),
  })
  let (_, recovered_failed) = update_dev(
    dispatch,
    DurableBoundary(run_id="r-failed-zero", session="desktop-test", sequence=0),
    failed_reload,
  )
  assert_true(recovered_failed.active().sync is Synced)
  inspect(recovered_failed.active().task, content="restore from failed reload")
  inspect(recovered_failed.active().input_ledger.length(), content="0")
  assert_true(recovered_failed.active().overlay[0].reconciliation is Retained)
}

///|
test "exact-zero recovery refuses buffered or nonzero durable frontiers" {
  let dispatch = test_dispatch()
  let buffered_started = fresh_started_model(
    "buffered-zero-prompt", "r-buffered-zero", "keep buffered ownership",
  )
  let (_, waiting) = update_dev(
    dispatch,
    Finished(
      run_id="r-buffered-zero",
      status="failed",
      answer=None,
      durable_sequence=None,
    ),
    buffered_started,
  )
  let (_, buffered) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=1,
      ts=None,
      item=@protocol.User({ content: "durable prompt arrived" }),
    ),
    waiting,
  )
  let (_, zero_with_buffer) = update_dev(
    dispatch,
    DurableBoundary(
      run_id="r-buffered-zero",
      session="desktop-test",
      sequence=0,
    ),
    buffered,
  )
  guard zero_with_buffer.active().sync is Reloading(buffered=commits, ..) else {
    fail("a buffered commit must keep transcript reconciliation active")
  }
  inspect(commits.length(), content="1")
  inspect(zero_with_buffer.active().task, content="")
  inspect(zero_with_buffer.active().input_ledger.length(), content="1")
  assert_true(
    zero_with_buffer.active().overlay[0].reconciliation
    is Submission("buffered-zero-prompt"),
  )

  let nonzero_started = fresh_started_model(
    "nonzero-prompt", "r-nonzero", "keep nonzero ownership",
  )
  let (_, nonzero) = update_dev(
    dispatch,
    Finished(
      run_id="r-nonzero",
      status="failed",
      answer=None,
      durable_sequence=Some(1),
    ),
    nonzero_started,
  )
  assert_true(nonzero.active().sync is Reloading(..))
  inspect(nonzero.active().task, content="")
  inspect(nonzero.active().input_ledger.length(), content="1")
  assert_true(nonzero.active().overlay[0].anchor is DurableTail(1))
  assert_true(
    nonzero.active().overlay[0].reconciliation is Submission("nonzero-prompt"),
  )
}

///|
test "the default provider needs no API key to be ready" {
  let model = test_model()
  assert_false(model.deepseek_key_saved)
  assert_true(model.api_ready())
}

///|
test "the official endpoint requires a key, a custom endpoint a URL" {
  let official = { ..test_model(), api_provider: Deepseek }
  assert_false(official.api_ready())
  assert_true(official.display_status() is ApiKeyRequired)
  assert_true({ ..official, deepseek_key_saved: true }.api_ready())
  let custom = { ..test_model(), api_provider: Custom, custom_api_url: "" }
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
      font_size="large",
      model="deepseek-v4-flash",
      conversation_models="[{\"key\":\"local/desktop-test\",\"model\":\"deepseek-v4-pro\"}]",
    ),
    test_model(),
  )
  assert_true(restored.notification_corner is TopLeft)
  assert_true(restored.theme is Dark)
  assert_true(restored.app_font is Menlo)
  assert_true(restored.app_font_size is Large)
  assert_true(restored.default_model is Low)
  // The stored conversation outranks the stored default for its own chat.
  assert_true(restored.active().engine_model is High)
  // Unknown stored values fall back to the defaults.
  let (_, unknown) = update(
    dispatch,
    SettingsLoaded(
      notification_corner="",
      tree_layout="",
      theme="broken",
      font="broken",
      font_size="broken",
      model="",
      conversation_models="not json",
    ),
    test_model(),
  )
  assert_true(unknown.notification_corner is BottomRight)
  assert_true(unknown.theme is System)
  assert_true(unknown.app_font is GeistMono)
  assert_true(unknown.app_font_size is Medium)
  assert_true(unknown.default_model is High)
  // A store that will not parse remembers nothing rather than wedging.
  assert_eq(unknown.conversation_models.length(), 0)
}

///|
test "the model selector switches one conversation, not the app" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation(
    empty_conversation(@interop.ChannelId::Local, "other-chat"),
  )
  let (_, low) = update(
    dispatch,
    EngineModelChanged("deepseek-v4-flash"),
    model,
  )
  assert_true(low.active().engine_model is Low)
  // The conversation next door keeps the tier it was already on.
  guard low.find_conversation(@interop.ChannelId::Local, "other-chat")
    is Some(other) else {
    fail("the second conversation vanished")
  }
  assert_true(other.engine_model is High)
  // The tier just picked is what conversations opened afterwards start from.
  assert_true(low.default_model is Low)
  assert_true(
    low.activate(@interop.ChannelId::Local, "fresh-chat").active().engine_model
    is Low,
  )
  let (_, high) = update(dispatch, EngineModelChanged("deepseek-v4-pro"), low)
  assert_true(high.active().engine_model is High)
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
    EngineModelChanged("deepseek-v4-flash"),
    test_model(),
  )
  assert_true(queued.active().engine_model is Low)
  let (_, ran) = update_dev(
    dispatch,
    Started(
      run_id="r1",
      session="desktop-test",
      model=High,
      max_steps=1000,
      session_root=None,
      submission_id=None,
    ),
    queued,
  )
  assert_true(ran.active().engine_model is Low)
}

///|
test "reopening a conversation recovers its own tier, not the last pick" {
  let dispatch = test_dispatch()
  // Set the chat on screen to Low, then open a different one and put it back
  // on High. The second pick moves the default new chats inherit — it must
  // not follow the first conversation home.
  let (_, low) = update(
    dispatch,
    EngineModelChanged("deepseek-v4-flash"),
    test_model(),
  )
  let other = low.activate(@interop.ChannelId::Local, "other-chat")
  assert_true(other.active().engine_model is Low)
  let (_, high) = update(dispatch, EngineModelChanged("deepseek-v4-pro"), other)
  assert_true(high.default_model is High)
  // Reopening drops the conversation and mints it again (nothing was sent,
  // so `activate` does not retain it) — exactly the path that used to hand
  // back the unrelated default.
  let reopened = high.activate(@interop.ChannelId::Local, "desktop-test")
  assert_true(reopened.active().engine_model is Low)
}

///|
test "a run pins an inherited tier the user never clicked for" {
  let dispatch = test_dispatch()
  // This chat never touched the chip — it just inherited High and ran. That
  // still has to pin, or a later toggle elsewhere silently retiers it.
  let (_, ran) = update_dev(
    dispatch,
    Started(
      run_id="r1",
      session="desktop-test",
      model=High,
      max_steps=1000,
      session_root=None,
      submission_id=None,
    ),
    test_model(),
  )
  assert_true(
    ran.remembered_model(@interop.ChannelId::Local, "desktop-test")
    is Some(High),
  )
  // Another chat moves the page default to Low...
  let elsewhere = ran.activate(@interop.ChannelId::Local, "other-chat")
  let (_, moved) = update(
    dispatch,
    EngineModelChanged("deepseek-v4-flash"),
    elsewhere,
  )
  assert_true(moved.default_model is Low)
  // ...and the first one still comes back on the tier it ran with.
  let reopened = moved.activate(@interop.ChannelId::Local, "desktop-test")
  assert_true(reopened.active().engine_model is High)
}

///|
test "remembered tiers survive a round trip through storage" {
  let dispatch = test_dispatch()
  let (_, chosen) = update(
    dispatch,
    EngineModelChanged("deepseek-v4-flash"),
    test_model(),
  )
  let restored = parse_conversation_models(
    encoded_conversation_models(chosen.conversation_models),
  )
  assert_eq(restored, chosen.conversation_models)
  assert_true(restored is [{ key: "local/desktop-test", model: Low }])
}

///|
test "a write merges into the stored rows instead of replacing them" {
  // A sibling console tab on the same origin wrote these while this page held
  // a copy loaded at its own startup. Pinning here must not drop the other
  // tab's row — that conversation would silently revert to the default.
  let stored = parse_conversation_models(
    encoded_conversation_models([
      { key: "remote.b/sibling-chat", model: Low },
      { key: "remote.a/desktop-test", model: High },
    ]),
  )
  let merged = remembered_with(stored, "remote.a/desktop-test", Low)
  assert_true(
    merged
    is [
      { key: "remote.a/desktop-test", model: Low },
      { key: "remote.b/sibling-chat", model: Low },
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
        Low
      } else {
        High
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
    is Some(Low),
  )
  // Re-choosing an existing conversation moves it, never duplicates it.
  let again = model.remember_model(@interop.ChannelId::Local, "session-1", Low)
  assert_eq(again.conversation_models.length(), ConversationModelsLimit)
  assert_true(
    again.remembered_model(@interop.ChannelId::Local, "session-1") is Some(Low),
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
      model=Low,
      max_steps=1000,
      session_root=None,
      submission_id=None,
    ),
    test_model(),
  )
  guard background.find_conversation(
      @interop.ChannelId::Local,
      "background-chat",
    )
    is Some(conv) else {
    fail("the background run materialized no conversation")
  }
  assert_true(conv.engine_model is Low)
  assert_true(background.active().engine_model is High)
  assert_true(background.default_model is High)
}

///|
fn host_settings(
  provider~ : String,
  revision? : Int = 0,
  has_deepseek_key? : Bool = false,
) -> HostSettings {
  {
    revision,
    provider,
    custom_api_url: "",
    has_deepseek_key,
    has_custom_key: false,
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
test "host settings open the settings page only when incomplete" {
  let dispatch = test_dispatch()
  let (_, zero_config) = update_dev(
    dispatch,
    HostSettingsLoaded(
      host_settings(provider="openseek"),
      connection_generation=None,
    ),
    test_model(),
  )
  assert_true(zero_config.screen is Chat)
  assert_true(zero_config.api_provider is Openseek)
  assert_true(zero_config.display_status() is Ready)
  let (_, keyless) = update_dev(
    dispatch,
    HostSettingsLoaded(
      host_settings(provider="deepseek"),
      connection_generation=None,
    ),
    test_model(),
  )
  assert_true(keyless.screen is Settings)
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
  assert_true(restored.deepseek_key_saved)
}

///|
test "a background device's pushes leave the focused mirrors alone" {
  let dispatch = test_dispatch()
  let background : @interop.ChannelId = Remote("d_bg")
  let model = {
    ..test_model(),
    devices: [
      {
        ..empty_device_state(@interop.ChannelId::Local),
        bridge: @interop.ChannelId::Local.test_connected(),
      },
      { ..empty_device_state(background), bridge: background.test_connected() },
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
  assert_true(settled.api_provider is Openseek)
  assert_true(settled.screen is Chat)
}

///|
test "host settings are deferred while this client's writes are in flight" {
  let dispatch = test_dispatch()
  let model = { ..test_model(), settings_saves: 1 }
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
  assert_true(ignored.api_provider is Openseek)
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
  let stacked = { ..model, settings_saves: 2 }
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
  assert_true(still_pending.api_provider is Openseek)
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
  let (_, browser) = update(dispatch, legacy, {
    ..test_model(),
    is_desktop: false,
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
      {
        ..empty_device_state(Remote("d_b")),
        bridge: @interop.ChannelId::Remote("d_b").test_connected(),
      },
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
  let model = { ..test_model(), setup_api_key: "typed" }
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
    setup_api_key: "  sk-new  ",
    screen: Settings,
  }
  let (_, saved_deepseek) = update(dispatch, SaveApiKey, deepseek)
  assert_true(saved_deepseek.deepseek_key_saved)
  assert_false(saved_deepseek.custom_key_saved)
  inspect(saved_deepseek.setup_api_key, content="")
  inspect(saved_deepseek.settings_saves, content="1")
  assert_true(saved_deepseek.screen is Chat)
  let custom = {
    ..deepseek,
    api_provider: Custom,
    custom_api_url: "https://proxy.example/chat/completions",
    setup_api_key: "  sk-custom-new  ",
  }
  let (_, saved_custom) = update(dispatch, SaveApiKey, custom)
  assert_false(saved_custom.deepseek_key_saved)
  assert_true(saved_custom.custom_key_saved)
  assert_true(saved_custom.screen is Chat)
}

///|
test "changing settings mid-run leaves the run status alone" {
  let dispatch = test_dispatch()
  let (_, next) = update(dispatch, ProviderChanged("deepseek"), running_model())
  assert_true(next.display_status() is Running)
  assert_true(next.api_provider is Deepseek)
}

///|
/// The Settings page has no Done button — the sidebar is the only way out,
/// even while the endpoint is unusable (the composer blocks sending then).
test "sidebar navigation leaves the settings page" {
  let dispatch = test_dispatch()
  let model = { ..test_model(), api_provider: Deepseek, screen: Settings }
  let (_, next) = update(
    dispatch,
    SessionRotated({ channel: Local, session: "s-fresh" }),
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
  { branch, probing: true, stale: false, pull_request, compare_url }
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
    checks: Some({ passed: 1, failed: 0, pending: 3 }),
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
    Some({ ..probing_for("feature/x", pull_request=answer), probing: false }),
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
  let stacked = { ..test_pull_request(), base: "feature/x" }
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

  fn picked(model : Model) {
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
    Some({ ..probing_for("feature/x"), stale: true }),
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
    SessionRotated({ channel: Local, session: "desktop-other" }),
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
test "every click-away menu closes without reopening on a second dismissal" {
  let dispatch = test_dispatch()
  // The topbar app launcher.
  let (_, launched) = update(dispatch, ToggleLauncher, test_model())
  assert_true(launched.launcher.open)
  let (_, dropped) = update(dispatch, CloseLauncher, launched)
  assert_false(dropped.launcher.open)
  let (_, twice) = update(dispatch, CloseLauncher, dropped)
  assert_false(twice.launcher.open)
  // Dismissing does not discard the catalog the launcher already probed, so
  // reopening it does not go back to the host for a list it has.
  assert_true(dropped.launcher.apps is AppsLoading)
  // Right-panel actions update the root's single visibility state directly.
  let (_, docked) = update(dispatch, ToggleRightPanel, desktop_model())
  let (_, menued) = update(dispatch, ToggleRightPanelMenu, docked)
  assert_true(menued.right_panel_menu_open)
  let (_, unmenued) = update(dispatch, CloseRightPanelMenu, menued)
  assert_false(unmenued.right_panel_menu_open)
  let (_, unmenued_twice) = update(dispatch, CloseRightPanelMenu, unmenued)
  assert_false(unmenued_twice.right_panel_menu_open)
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
    dock: { ..model.dock, owner: Some(stale_owner) },
  }
  // Any root message runs the centralized dock synchronization. The owner
  // transition closes the menu directly, with no rendered marker or observer.
  let (_, synced) = update(dispatch, CloseLauncher, stale)
  assert_false(synced.right_panel_menu_open)
  assert_true(synced.dock.owner != Some(stale_owner))
}

///|
fn archived_item(id : String) -> @transcript.SessionListItem {
  { id, title: Some(""), workspace: None, workspace_name: "" }
}

///|
test "session.changed decoder preserves archive invalidation identity" {
  guard session_changed_msg({ change: "archived", session: "desktop-old" })
    is Some(
      SessionsChanged(
        change="archived",
        session="desktop-old",
        fresh_session=Some(_)
      )
    ) else {
    fail("archive invalidation was not decoded")
  }
}

///|
test "archive broadcast invalidates the active send target before list replies" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/work/archived")
  let mention : Mention = { ref_: Skill(name="draft-skill"), range: None }
  let model = test_model()
    .replace_conversation({
      ..test_conversation(),
      task: "must not target archived session",
      mentions: [mention],
    })
    .with_dev(dev => {
      ..dev.with_workspace_settings(workspace, true, generation=1),
      sessions: [
        {
          ..archived_item("desktop-test"),
          workspace: Some(workspace),
          workspace_name: "archived",
        },
      ],
      worktrees: [{ project: workspace, rows: [], generation: 1 }],
    })
  let (_, invalidated) = update_dev(
    dispatch,
    SessionsChanged(
      change="archived",
      session="desktop-test",
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
  inspect(invalidated.active().task, content="must not target archived session")
  inspect(invalidated.active().mentions.length(), content="1")
  assert_true(
    invalidated.active().mentions[0].ref_ is Skill(name="draft-skill"),
  )
  assert_true(
    invalidated.dev().archived.iter().any(item => item.id == "desktop-test"),
  )
  assert_false(
    invalidated.dev().sessions.iter().any(item => item.id == "desktop-test"),
  )
  // Even before either sidebar refresh returns, the next submit belongs to
  // the replacement conversation; no live state can target the archived id.
  let (_, drafted) = update(
    dispatch,
    TaskChanged("safe replacement"),
    invalidated,
  )
  let (_, sent) = update(dispatch, Send, drafted)
  inspect(sent.active_session, content="desktop-fresh")
  inspect(sent.active().session_id, content="desktop-fresh")
  assert_true(sent.active().run is Starting(..))
  assert_true(
    sent.find_conversation(@interop.ChannelId::Local, "desktop-test") is None,
  )
}

///|
test "an archive response arriving before its notification preserves the draft once" {
  let dispatch = test_dispatch()
  let model = test_model()
    .replace_conversation({ ..test_conversation(), task: "keep this draft" })
    .with_dev(dev => { ..dev, sessions: [archived_item("desktop-test")] })
  let (_, responded) = update(
    dispatch,
    archived_loaded([archived_item("desktop-test")]),
    model,
  )
  inspect(responded.active_session, content="desktop-archive-replacement")
  inspect(responded.active().task, content="keep this draft")
  let (_, notified) = update_dev(
    dispatch,
    SessionsChanged(
      change="archived",
      session="desktop-test",
      fresh_session=Some("desktop-notification-replacement"),
    ),
    responded,
  )
  // The late duplicate only refreshes the tombstone; it cannot rotate the
  // already-safe composer a second time or lose its recovered text.
  inspect(notified.active_session, content="desktop-archive-replacement")
  inspect(notified.active().task, content="keep this draft")
  inspect(notified.active().overlay.length(), content="0")
}

///|
test "archiving a pending start restores its original composer without ownership" {
  let dispatch = test_dispatch()
  let sent_mention : Mention = { ref_: Skill(name="sent-skill"), range: None }
  let newer_mention : Mention = { ref_: Skill(name="newer-skill"), range: None }
  let pending = test_conversation().enqueue_input(
    InitialPrompt,
    "pending-start",
    None,
    "serialized prompt",
    "original draft",
    [sent_mention],
  )
  let model = test_model()
    .replace_conversation({
      ..pending,
      run: Starting(submission_id="pending-start"),
      task: "typed afterward",
      mentions: [newer_mention],
    })
    .with_dev(dev => { ..dev, sessions: [archived_item("desktop-test")] })
  let (_, next) = update_dev(
    dispatch,
    SessionsChanged(
      change="archived",
      session="desktop-test",
      fresh_session=Some("desktop-restored"),
    ),
    model,
  )
  inspect(next.active_session, content="desktop-restored")
  inspect(next.active().task, content="original draft\n\ntyped afterward")
  inspect(next.active().mentions.length(), content="2")
  assert_true(next.active().run is NoRun(ended=None))
  inspect(next.active().input_ledger.length(), content="0")
  inspect(next.active().overlay.length(), content="1")
  inspect(next.active().overlay[0].content, content=ArchivedPendingInputNotice)
  assert_true(next.active().overlay[0].reconciliation is Retained)
}

///|
test "an archive notification wins over a stale live-list reply" {
  let dispatch = test_dispatch()
  let item = archived_item("desktop-test")
  let model = test_model().with_dev(dev => { ..dev, sessions: [item] })
  let (_, invalidated) = update_dev(
    dispatch,
    SessionsChanged(
      change="archived",
      session="desktop-test",
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
    ..empty_conversation(@interop.ChannelId::Local, "shared"),
    messages: [{ kind: User, content: "local", ts: None, sequence: None }],
  }
  let remote_conv = {
    ..empty_conversation(remote, "shared"),
    messages: [{ kind: User, content: "remote", ts: None, sequence: None }],
  }
  let model = {
    ..test_model(),
    devices: [
      {
        ..empty_device_state(@interop.ChannelId::Local),
        bridge: @interop.ChannelId::Local.test_connected(),
      },
      { ..empty_device_state(remote), bridge: remote.test_connected() },
    ],
    active_session: "shared",
    conversations: [local_conv, remote_conv],
  }
  let (_, next) = update(
    dispatch,
    FromDevice(
      remote,
      ArchivedLoaded(
        [archived_item("shared")],
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
  inspect(kept.messages[0].content, content="local")
  assert_true(next.find_conversation(remote, "shared") is None)
}

///|
test "an unarchive notification wins over a stale archived-list reply" {
  let dispatch = test_dispatch()
  let item = archived_item("desktop-old")
  let model = test_model().with_dev(dev => { ..dev, archived: [item] })
  let (_, restored) = update_dev(
    dispatch,
    SessionsChanged(
      change="unarchived",
      session="desktop-old",
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
  let model = test_model()
    .with_archive_override(@interop.ChannelId::Local, "desktop-old", true)
    .with_dev(dev => { ..dev, archived: [item] })
  let (_, ready) = update_dev(
    dispatch,
    @interop.ChannelId::Local.test_bridge_ready(),
    model,
  )
  inspect(ready.dev().connection_generation, content="1")
  inspect(ready.dev().archive_overrides.length(), content="0")
  let (_, live) = update_dev(
    dispatch,
    SessionsLoaded([item], connection_generation=1, request_generation=1),
    ready,
  )
  let (_, reconciled) = update_dev(
    dispatch,
    ArchivedLoaded(
      [],
      connection_generation=1,
      request_generation=1,
      fresh_session="desktop-unused",
    ),
    live,
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
    workspace: None,
    workspace_name: "",
  }
  let current = { ..old, title: Some("current title") }
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
    workspace: None,
    workspace_name: "",
  }
  let current = { ..old, title: Some("current title") }
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
      empty_conversation(@interop.ChannelId::Local, "desktop-old"),
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
    archived_loaded([archived_item("desktop-test")]),
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
  let system = { ..test_model(), theme: System, system_dark: false }
  let (_, dark) = update(dispatch, ColorSchemeChanged(true), system)
  assert_true(dark.theme is System)
  assert_true(dark.system_dark)
  let fixed = { ..dark, theme: Light }
  let (_, changed_host) = update(dispatch, ColorSchemeChanged(false), fixed)
  assert_true(changed_host.theme is Light)
  assert_false(changed_host.system_dark)
}

///|
test "theme settings switch fixed palettes and are idempotent" {
  let dispatch = test_dispatch()
  let system = { ..test_model(), theme: System, system_dark: true }
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
test "font settings switch every text surface and are idempotent" {
  let dispatch = test_dispatch()
  let model = test_model()
  let (_, first) = update(dispatch, FontChanged("system-mono"), model)
  let (_, second) = update(dispatch, FontChanged("system-mono"), model)
  assert_true(first.app_font is SystemMono)
  assert_true(second.app_font is SystemMono)
  let (_, menlo) = update(dispatch, FontChanged("menlo"), first)
  assert_true(menlo.app_font is Menlo)
  let (_, bundled) = update(dispatch, FontChanged("geist-mono"), menlo)
  assert_true(bundled.app_font is GeistMono)
  let (_, unchanged) = update(dispatch, FontChanged("unknown"), model)
  assert_true(unchanged.app_font is GeistMono)
}

///|
test "font-size settings switch every text surface and are idempotent" {
  let dispatch = test_dispatch()
  let model = test_model()
  let (_, first) = update(dispatch, FontSizeChanged("small"), model)
  let (_, second) = update(dispatch, FontSizeChanged("small"), model)
  assert_true(first.app_font_size is Small)
  assert_true(second.app_font_size is Small)
  let (_, large) = update(dispatch, FontSizeChanged("large"), first)
  assert_true(large.app_font_size is Large)
  let (_, medium) = update(dispatch, FontSizeChanged("medium"), large)
  assert_true(medium.app_font_size is Medium)
  let (_, unchanged) = update(dispatch, FontSizeChanged("unknown"), model)
  assert_true(unchanged.app_font_size is Medium)
}

///|
test "a transcript stream grows without application-owned scroll state" {
  let dispatch = test_dispatch()
  let (_, next) = update_dev(
    dispatch,
    Engine(Some("r7"), AssistantDelta("more"), session=None),
    running_model(),
  )
  inspect(next.active().streaming_response, content="more")
}

///|
fn test_market_item() -> @transcript.MarketSkillItem {
  {
    name: "acme/widget",
    module_name: "acme/widget",
    package_path: "",
    version: "1.0.0",
    description: "Build widgets fast.",
    author: "acme",
    repository: "",
  }
}

///|
test "opening the skills page fetches the catalog once" {
  let dispatch = test_dispatch()
  let (_, opened) = update(dispatch, OpenSkills, test_model())
  assert_true(opened.screen is Skills)
  assert_true(opened.skills_catalog is CatalogLoading)

  // Reopening with a loaded catalog keeps it; only a failure refetches.
  let loaded = { ..test_model(), skills_catalog: CatalogReady([]) }
  let (_, reopened) = update(dispatch, OpenSkills, loaded)
  assert_true(reopened.skills_catalog is CatalogReady(_))
  let failed = {
    ..test_model(),
    skills_catalog: CatalogFailed("offline"),
    skills_notice: "stale",
  }
  let (_, retried) = update(dispatch, OpenSkills, failed)
  assert_true(retried.skills_catalog is CatalogLoading)
  inspect(retried.skills_notice, content="")
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
    SessionRotated({ channel: Local, session: "desktop-fresh" }),
    opened,
  )
  assert_true(rotated.screen is Chat)
}

///|
test "update is pure: opening the skills page twice is idempotent" {
  let dispatch = test_dispatch()
  let model = test_model()
  let (_, once) = update(dispatch, OpenSkills, model)
  let (_, twice) = update(dispatch, OpenSkills, model)
  assert_true(once.screen is Skills)
  assert_true(twice.screen is Skills)
  assert_true(once.skills_catalog is CatalogLoading)
  assert_true(twice.skills_catalog is CatalogLoading)
}

///|
test "the skills search query lands on the model" {
  let dispatch = test_dispatch()
  let (_, typed) = update(dispatch, SkillsQueryChanged("widget"), test_model())
  inspect(typed.skills_query, content="widget")
}

///|
test "an install marks its entry busy exactly once" {
  let dispatch = test_dispatch()
  let (_, busy) = update(
    dispatch,
    InstallSkill(test_market_item()),
    test_model(),
  )
  inspect(busy.skills_busy.length(), content="1")
  inspect(busy.skills_busy[0], content="acme/widget@1.0.0")

  // A second click while in flight is a no-op.
  let (_, again) = update(dispatch, InstallSkill(test_market_item()), busy)
  inspect(again.skills_busy.length(), content="1")
}

///|
test "a settled action releases its busy entry" {
  let dispatch = test_dispatch()
  let busy = { ..test_model(), skills_busy: ["acme/widget@1.0.0", "other"] }
  let (_, done) = update(
    dispatch,
    SkillActionDone(
      channel=@interop.ChannelId::Local,
      key="acme/widget@1.0.0",
      error="",
    ),
    busy,
  )
  inspect(done.skills_busy.length(), content="1")
  inspect(done.skills_busy[0], content="other")
  inspect(done.skills_notice, content="")

  // A failure surfaces as the panel notice instead.
  let (_, failed) = update(
    dispatch,
    SkillActionDone(
      channel=@interop.ChannelId::Local,
      key="other",
      error="digest mismatch",
    ),
    done,
  )
  inspect(failed.skills_busy.length(), content="0")
  inspect(failed.skills_notice, content="digest mismatch")
}

///|
test "uninstall is keyed by the library id and deduplicated" {
  let dispatch = test_dispatch()
  let (_, busy) = update(dispatch, UninstallSkill("acme-widget"), test_model())
  inspect(busy.skills_busy.length(), content="1")
  inspect(busy.skills_busy[0], content="acme-widget")
  let (_, again) = update(dispatch, UninstallSkill("acme-widget"), busy)
  inspect(again.skills_busy.length(), content="1")
}

///|
test "catalog and library replies land on the model" {
  let dispatch = test_dispatch()
  let (_, ready) = update(
    dispatch,
    SkillsCatalogLoaded([test_market_item()]),
    test_model(),
  )
  guard ready.skills_catalog is CatalogReady(items) else {
    fail("catalog should be ready")
  }
  inspect(items.length(), content="1")
  assert_false(ready.skill_installed("acme/widget@1.0.0"))
  let (_, failed) = update(dispatch, SkillsCatalogFailed("offline"), ready)
  assert_true(failed.skills_catalog is CatalogFailed(_))
  let installed : Array[@transcript.InstalledSkillItem] = [
    {
      id: "acme-widget",
      name: "widget",
      description: "",
      source: "acme/widget@1.0.0",
    },
  ]
  let (_, listed) = update_dev(
    dispatch,
    InstalledSkillsLoaded(installed),
    ready,
  )
  assert_true(listed.skill_installed("acme/widget@1.0.0"))
  let (_, noticed) = update(
    dispatch,
    SkillsNotice("library unreadable"),
    listed,
  )
  inspect(noticed.skills_notice, content="library unreadable")
}

///|
test "installed skills replies are scoped to their source device" {
  let dispatch = test_dispatch()
  let home = test_model()
  let focused = {
    ..home,
    devices: [
      home.devices[0],
      {
        ..empty_device_state(Remote("d_b")),
        bridge: @interop.ChannelId::Remote("d_b").test_connected(),
      },
    ],
    focused: Remote("d_b"),
    installed_skills: [],
  }
  let old_host : Array[@transcript.InstalledSkillItem] = [
    { id: "old", name: "old", description: "", source: "old/source@1.0.0" },
  ]
  let (_, ignored) = update(
    dispatch,
    FromDevice(Local, InstalledSkillsLoaded(old_host)),
    focused,
  )
  assert_eq(ignored.installed_skills.length(), 0)
  let new_host : Array[@transcript.InstalledSkillItem] = [
    { id: "new", name: "new", description: "", source: "new/source@1.0.0" },
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
    dock: { ..model.dock, tabs: [File(path~)], active: Some(File(path~)) },
  }
  assert_true(file_ctx(file_model).panel_open)
  assert_false(file_ctx({ ..file_model, right_panel_open: false }).panel_open)
  let picker_model = {
    ..file_model,
    dock: { ..file_model.dock, tabs: [FilePicker], active: Some(FilePicker) },
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
    dock: { ..file_model.dock, tabs: [], active: None },
  }
  assert_false(file_ctx(launcher_model).panel_open)
  assert_false(file_ctx({ ..file_model, screen: Skills }).panel_open)
  assert_false(file_ctx({ ..file_model, screen: Settings }).panel_open)
}

///|
test "only synchronous file-open messages suppress panel reactivation" {
  let owner : @interop.ConversationKey = {
    channel: Local,
    session: "desktop-test",
  }
  assert_true(JumpToMention(0).opens_file_before_panel_reconciliation())
  assert_true(
    JumpToLocation(path="a.mbt", range=None, annotation=None).opens_file_before_panel_reconciliation(),
  )
  assert_true(QuickOpenPick(0).opens_file_before_panel_reconciliation())
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
    range: Some(@common.Range::Range(5, 1, 5, 12)),
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
  let panel_open_pending = { ..latest_pending, right_panel_open: true }
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
        range=@common.Range::Range(9, 1, 9, 4),
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
        range=Some(@common.Range::Range(2738, 17, 2738, 17)),
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
        range=Some(@common.Range::Range(1, 1, 1, 1)),
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
        range=Some(@common.Range::Range(2738, 17, 2738, 17)),
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
      owner={ ..owner, session: "another-session" },
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
  let mention : Mention = { ref_: Skill(name="review-pr"), range: None }
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
      range=@common.Range::Range(5, 1, 6, 3),
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
test "UnifiedDiffCommentAdded preserves modified and original-only line identity" {
  let dispatch = test_dispatch()
  let file = @pathx.Relative("src/main.mbt")
  let added : Msg = FileEditor(
    UnifiedDiffCommentAdded(
      file~,
      original_line_number=None,
      modified_line_number=Some(7),
      quote="let answer = 42",
      comment="name this constant",
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
  assert_eq(added_mentions[0].range, Some(@common.Range::Range(7, 1, 7, 16)))
  let deleted : Msg = FileEditor(
    UnifiedDiffCommentAdded(
      file~,
      original_line_number=Some(3),
      modified_line_number=None,
      quote="obsolete()",
      comment="good removal",
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
      worktrees: [{ project: workspace, rows: [], generation: 1 }],
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
      review_view_mode: @fileeditor.ReviewUnifiedDiff,
      changes_generation: 7,
      watch_generation: 11,
    },
  }
  let (_, next) = update(
    dispatch,
    JumpToLocation(
      path="/work/project/src/main.mbt",
      range=Some(@common.Range::Range(5, 1, 5, 1)),
      annotation=None,
    ),
    model,
  )
  assert_true(@dock.active_file(next.dock) is Some(Relative("src/main.mbt")))
  assert_false(next.file_panel.tree_open)
  assert_true(next.file_panel.explorer_mode is @fileeditor.ExplorerChanges)
  assert_true(next.file_panel.review_view_mode is @fileeditor.ReviewUnifiedDiff)
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
      worktrees: [{ project: workspace, rows: [], generation: 1 }],
    })
  let (_, next) = update(
    dispatch,
    JumpToLocation(
      path="/work/project/src/main.mbt",
      range=Some(@common.Range::Range(5, 1, 5, 1)),
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
      range=Some(@common.Range::Range(1, 1, 1, 1)),
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
    { ..model, dock, file_panel: panel, right_panel_open: true },
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
    owner: Some({ channel: Local, session: "desktop-test" }),
  }
  let (_, next) = update(
    dispatch,
    FileEditor(RevealDirectory(Relative("src/foo"))),
    { ..model, file_panel: panel },
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
    owner: Some({ channel: Local, session: "desktop-test" }),
    children,
  }
  let (_, next) = update(
    dispatch,
    FileEditor(RevealDirectory(Relative("src/foo"))),
    { ..model, file_panel: panel },
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
    owner: Some({ channel: Local, session: "desktop-test" }),
    highlighted: Some(Relative("src")),
  }
  let (_, stale) = update(
    dispatch,
    FileEditor(HighlightCleared(Relative("old"))),
    { ..model, file_panel: panel },
  )
  assert_true(stale.file_panel.highlighted is Some(Relative("src")))
  let (_, cleared) = update(
    dispatch,
    FileEditor(HighlightCleared(Relative("src"))),
    { ..model, file_panel: panel },
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
    Finished(
      run_id="r7",
      status="completed",
      answer=None,
      durable_sequence=None,
    ),
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
    streaming_response: "partial",
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
  inspect(model.active().overlay.length(), content="0")
  inspect(once.active().overlay.length(), content="0")
  inspect(twice.active().overlay.length(), content="0")
  inspect(once.active().streaming_response, content="partial")
  inspect(twice.active().streaming_response, content="partial")
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
    streaming_response: "partial",
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
  inspect(model.active().overlay.length(), content="0")
  inspect(once.active().overlay.length(), content="0")
  inspect(twice.active().overlay.length(), content="0")
  inspect(once.active().streaming_response, content="")
  inspect(twice.active().streaming_response, content="")
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
    Finished(
      run_id="r7",
      status="context_yield",
      answer=Some(answer),
      durable_sequence=None,
    ),
    yielded,
  )
  inspect(settled.active().overlay.length(), content="0")
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
  inspect(next.active().overlay.length(), content="0")
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
  inspect(next.active().overlay.length(), content="0")
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
  inspect(next.active().overlay.length(), content="1")
}

///|
/// A rejected compact request (no engine, host error) never produces
/// compaction events, so the rejection itself clears the queued notice and
/// lands the error in the transcript.
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
  inspect(next.active().overlay.length(), content="1")
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
      progress={ downloaded_bytes: 42, total_bytes: Some(100) }
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
test "switching the server to staging moves the channel and forgets the previous answer" {
  let dispatch = test_dispatch()
  let available = {
    ..test_model(),
    update_ux: UpdateAvailable(version="0.2.0", installable=true),
  }
  let (_, switched) = update(
    dispatch,
    ProviderChanged("openseek-staging"),
    available,
  )
  assert_true(switched.api_provider is OpenseekStaging)
  assert_true(switched.api_provider.update_channel() is Staging)
  assert_true(switched.update_ux is UpdateUnknown)
  // A switch that keeps the channel keeps the answer.
  let (_, kept) = update(dispatch, ProviderChanged("deepseek"), available)
  assert_true(kept.api_provider.update_channel() is Production)
  assert_true(kept.update_ux is UpdateAvailable(..))
}

///|
test "check_update replies decode by kind" {
  assert_true(UpdateCheck::from_reply(@protocol.UpToDate) is CheckUpToDate)
  assert_true(
    UpdateCheck::from_reply(
      @protocol.Available(
        version="0.2.0",
        installable=true,
        unavailable_reason=None,
      ),
    )
    is CheckFound(version="0.2.0", installable=true, unavailable_reason=None),
  )
  assert_true(
    UpdateCheck::from_reply(
      @protocol.Available(
        version="0.2.0",
        installable=false,
        unavailable_reason=Some("move the app"),
      ),
    )
    is CheckFound(
      version="0.2.0",
      installable=false,
      unavailable_reason=Some("move the app")
    ),
  )
  assert_true(
    UpdateCheck::from_reply(@protocol.Unreachable(reason="offline"))
    is CheckUnreachable(reason="offline"),
  )
  assert_true(
    UpdateCheck::from_reply(@protocol.Malformed(reason="not json"))
    is CheckMalformed(reason="not json"),
  )
  assert_true(
    UpdateCheck::from_reply(@protocol.Broken(version="0.2.0", reason="bad url"))
    is CheckBroken(version="0.2.0", reason="bad url"),
  )
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
  inspect(sent.active().overlay.length(), content="0")
  inspect(sent.active().watermark, content="0")
  // The durable commit is the first point the prompt becomes transcript.
  let (_, committed) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=1,
      ts=None,
      item=@protocol.User({ content: "build the thing" }),
    ),
    sent,
  )
  inspect(committed.active().messages.length(), content="1")
  guard committed.active().messages[0].kind is User else {
    fail("expected a user item")
  }
  inspect(committed.active().overlay.length(), content="0")
  inspect(committed.active().watermark, content="1")
}

///|
test "a replayed commit at or below the watermark is dropped" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    messages: [
      { kind: User, content: "already there", ts: None, sequence: None },
    ],
    watermark: 2,
  })
  let (_, next) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=2,
      ts=None,
      item=@protocol.User({ content: "already there" }),
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
      item=@protocol.User({ content: "from the future" }),
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
      item=@protocol.User({ content: "mid-reload" }),
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
      { sequence: 4, ts: None, item: @protocol.User({ content: "four" }) },
      { sequence: 3, ts: None, item: @protocol.User({ content: "three" }) },
    ]),
  })
  let (_, next) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[
        { kind: User, content: "one", ts: None, sequence: None },
        {
          kind: Assistant(is_danger=false),
          content: "two",
          ts: None,
          sequence: None,
        },
      ],
      watermark=2,
      event_boundaries=[],
      generation=1,
    ),
    model,
  )
  inspect(next.active().messages.length(), content="4")
  inspect(next.active().messages[2].content, content="three")
  inspect(next.active().messages[3].content, content="four")
  inspect(next.active().watermark, content="4")
  assert_true(next.active().sync is Synced)
}

///|
test "a snapshot already containing the buffered commits drops them" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    sync: test_reloading([
      { sequence: 2, ts: None, item: @protocol.User({ content: "dup" }) },
    ]),
  })
  let (_, next) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[
        { kind: User, content: "one", ts: None, sequence: None },
        { kind: User, content: "dup", ts: None, sequence: None },
      ],
      watermark=2,
      event_boundaries=[],
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
      { sequence: 9, ts: None, item: @protocol.User({ content: "far" }) },
    ]),
  })
  let (_, next) = update_dev(
    dispatch,
    SessionRefreshed(
      goal=None,
      goal_markers=[],
      session="desktop-test",
      items=[{ kind: User, content: "one", ts: None, sequence: None }],
      watermark=2,
      event_boundaries=[],
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
    messages: [{ kind: User, content: "kept", ts: None, sequence: None }],
    watermark: 1,
    sync: test_reloading([
      { sequence: 3, ts: None, item: @protocol.User({ content: "x" }) },
    ]),
  })
  let model = { ..model, transcript_request_generation: 1 }
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
  inspect(failed.active().overlay.length(), content="1")
  // The next commit starts a fresh generation without applying out of order.
  let (_, retrying) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=2,
      ts=None,
      item=@protocol.User({ content: "next" }),
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
      items=[{ kind: User, content: "kept", ts: None, sequence: None }],
      watermark=1,
      event_boundaries=[],
      generation=2,
    ),
    retrying,
  )
  inspect(healed.active().messages.length(), content="3")
  inspect(healed.active().messages[1].content, content="next")
  inspect(healed.active().messages[2].content, content="x")
  inspect(healed.active().watermark, content="3")
  inspect(healed.active().overlay.length(), content="0")
  assert_true(healed.active().sync is Synced)
}

///|
test "reopening an active failed reload retries and preserves other local notices" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    messages: [{ kind: User, content: "kept", ts: None, sequence: None }],
    watermark: 1,
    sync: ReloadFailed(generation=1, buffered=[
      { sequence: 2, ts: None, item: @protocol.User({ content: "two" }) },
    ]),
    overlay: [
      {
        id: 1,
        kind: Assistant(is_danger=true),
        content: TranscriptRefreshFailedNotice,
        anchor: AfterMessages(1),
        reconciliation: Retained,
      },
      {
        id: 2,
        kind: Assistant(is_danger=true),
        content: "local steer loss",
        anchor: AfterMessages(1),
        reconciliation: Retained,
      },
    ],
    next_notice_id: 2,
  })
  let model = { ..model, transcript_request_generation: 1 }
  let (_, reopened) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-test"),
    model,
  )
  assert_true(
    reopened.loading_conversation
    is Some({ channel: Local, session: "desktop-test" }),
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
      items=[{ kind: User, content: "kept", ts: None, sequence: None }],
      watermark=1,
      event_boundaries=[],
      generation=2,
    ),
    reopened,
  )
  assert_true(loaded.loading_conversation is None)
  inspect(loaded.active().messages.length(), content="2")
  inspect(loaded.active().watermark, content="2")
  // Success clears only the exact refresh-state warning.
  inspect(loaded.active().overlay.length(), content="1")
  inspect(loaded.active().overlay[0].content, content="local steer loss")
}

///|
test "stale and lower-watermark snapshots cannot overwrite current state" {
  let dispatch = test_dispatch()
  let current_root = @interop.ChannelId::Local.test_resource("/work/current")
  let model = test_model().replace_conversation({
    ..test_conversation(),
    workspace: Project(root=current_root),
    messages: [{ kind: User, content: "current", ts: None, sequence: None }],
    watermark: 5,
    sync: Reloading(
      generation=2,
      attempt=1,
      buffered=[
        { sequence: 6, ts: None, item: @protocol.User({ content: "six" }) },
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
      items=[
        { kind: User, content: "stale generation", ts: None, sequence: None },
      ],
      watermark=9,
      event_boundaries=[],
      generation=1,
    ),
    model,
  )
  inspect(stale.active().messages[0].content, content="current")
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
      items=[
        { kind: User, content: "older snapshot", ts: None, sequence: None },
      ],
      watermark=4,
      event_boundaries=[],
      generation=2,
    ),
    stale,
  )
  inspect(lower.active().messages[0].content, content="current")
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
  let commit = SessionCommitted(
    session="desktop-test",
    sequence=1,
    ts=None,
    item=@protocol.ToolResult({
      tool_call_id: "",
      tool_name: "edit",
      content: "invalid arguments",
      is_error: true,
      brief: None,
    }),
  )
  let (_, semantic_first) = update_dev(dispatch, semantic, running_model())
  inspect(semantic_first.active().messages.length(), content="0")
  inspect(semantic_first.active().overlay.length(), content="0")
  let (_, committed_after) = update_dev(dispatch, commit, semantic_first)
  inspect(committed_after.active().messages.length(), content="1")
  inspect(committed_after.active().overlay.length(), content="0")
  guard committed_after.active().messages[0].kind
    is Tool(name="edit", is_error=true, ..) else {
    fail("expected the canonical error tool result")
  }
  inspect(
    committed_after.active().messages[0].content,
    content="invalid arguments",
  )
  let (_, committed_first) = update_dev(dispatch, commit, running_model())
  let (_, semantic_after) = update_dev(dispatch, semantic, committed_first)
  inspect(semantic_after.active().messages.length(), content="1")
  inspect(semantic_after.active().overlay.length(), content="0")
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
  inspect(answered.active().overlay.length(), content="0")
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
      }),
    ),
    answered,
  )
  // One durable item projects as reasoning + answer exactly once.
  inspect(committed.active().messages.length(), content="2")
  inspect(committed.active().overlay.length(), content="0")
  inspect(committed.active().watermark, content="1")
}

///|
test "a committed tool result visibly changes its existing call row" {
  let (_, called) = running_conversation().apply_commit(
    1,
    @protocol.Assistant({
      content: "",
      tool_calls: Some([
        { id: "c1", name: "read", arguments: "{\"path\":\"moon.mod\"}" },
      ]),
      reasoning_content: None,
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
  inspect(completed.messages[0].content, content="module contents")
}

///|
test "a delayed assistant commit never clears a newer live delta" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    streaming_response: "newer turn fragment",
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
        reasoning_content: None,
      }),
    ),
    model,
  )
  inspect(committed.active().streaming_response, content="newer turn fragment")
}

///|
test "a delayed terminal commit never clears a newer live delta" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    messages: [
      { kind: User, content: "older prompt", ts: None, sequence: None },
    ],
    watermark: 1,
    streaming_response: "next turn fragment",
  })
  let (_, committed) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=2,
      ts=None,
      item=@protocol.Terminal(@protocol.Finished("older answer")),
    ),
    model,
  )
  inspect(committed.active().streaming_response, content="next turn fragment")
}

///|
test "a fixed local notice stays before later durable turns" {
  let dispatch = test_dispatch()
  let conv = {
    ..test_conversation(),
    messages: [{ kind: User, content: "question", ts: None, sequence: None }],
    watermark: 1,
  }.append_local_notice(Assistant(is_danger=true), "local failure")
  let (_, committed) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=2,
      ts=None,
      item=@protocol.Assistant({
        content: "later answer",
        tool_calls: None,
        reasoning_content: None,
      }),
    ),
    test_model().replace_conversation(conv),
  )
  let visible = committed.active().visible_items()
  inspect(visible.length(), content="3")
  inspect(visible[0].content, content="question")
  inspect(visible[1].content, content="local failure")
  inspect(visible[2].content, content="later answer")
}

///|
test "a durable commit never retires a same-class local notice" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    overlay: [
      {
        id: 1,
        kind: Assistant(is_danger=true),
        content: "local-only failure",
        anchor: AfterMessages(0),
        reconciliation: Retained,
      },
    ],
    next_notice_id: 1,
  })
  let (_, committed) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=1,
      ts=None,
      item=@protocol.Assistant({
        content: "durable answer",
        tool_calls: None,
        reasoning_content: None,
      }),
    ),
    model,
  )
  inspect(committed.active().messages.length(), content="1")
  inspect(committed.active().overlay.length(), content="1")
  inspect(committed.active().overlay[0].content, content="local-only failure")
}

///|
test "commit-first assistant semantics do not append again" {
  let dispatch = test_dispatch()
  let streaming = running_model().replace_conversation({
    ..running_conversation(),
    streaming_response: "answer",
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
      }),
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
  inspect(answered.active().messages.length(), content="2")
  inspect(answered.active().overlay.length(), content="0")
  inspect(answered.active().watermark, content="1")
  inspect(answered.active().streaming_response, content="")
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
      item=@protocol.User({ content: "hi" }),
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
  inspect(hidden.messages[0].content, content="hi")
  inspect(hidden.watermark, content="1")
  inspect(next.dev().sessions_request_generation, content="1")
  let (_, repeated) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-elsewhere",
      sequence=1,
      ts=None,
      item=@protocol.User({ content: "hi" }),
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
      item=@protocol.User({ content: "third" }),
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
        workspace: None,
        workspace_name: "",
      },
    ],
  })
  let (_, next) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-archived",
      sequence=1,
      ts=None,
      item=@protocol.User({ content: "stale" }),
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
    "desktop-tombstoned",
    true,
  )
  let (_, next) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-tombstoned",
      sequence=1,
      ts=None,
      item=@protocol.User({ content: "stale" }),
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
    user: Some({ login: "octocat", avatar_url: "" }),
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
  let model = { ..test_model(), is_desktop: true }
  let (_, model) = update(
    test_dispatch(),
    Terminal(@terminal.TabSelected(key=0)),
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
test "launcher rows open Browse, Files, and Review destinations" {
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
  let (_, model) = update(dispatch, FilePickerRequested, model)
  assert_true(model.dock.active == Some(@dock.DockTab::FilePicker))
  assert_true(model.file_panel.explorer_mode is ExplorerFiles)
  assert_true(
    model.dock.tabs == [@dock.DockTab::Browser(id=1), @dock.DockTab::FilePicker],
  )
  let (_, model) = update(dispatch, ReviewRequested, model)
  assert_true(model.dock.active == Some(@dock.DockTab::FilePicker))
  assert_true(model.file_panel.explorer_mode is ExplorerChanges)
  assert_true(model.file_panel.changes is ChangeListLoading(_))
  // Files is an explicit destination even after Review selected Changes.
  let (_, model) = update(dispatch, FilePickerRequested, model)
  assert_true(model.file_panel.explorer_mode is ExplorerFiles)
}

///|
test "a tree pick fulfills the active picker in place" {
  let dispatch = test_dispatch()
  let model = desktop_model()
  let (_, model) = update(dispatch, ToggleRightPanel, model)
  let (_, model) = update(dispatch, FilePickerRequested, model)
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
  let (_, model) = update(dispatch, FilePickerRequested, model)
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
        ..,
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
      range=Some(@common.Range::Range(1, 1, 1, 1)),
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
        range=@common.Range::Range(1, 1, 1, 1),
      ),
    ),
    model,
  )
  assert_false(navigation.dock.tabs.contains(@dock.DockTab::File(path~)))
  assert_false(navigation.file_panel.docs.contains(path))
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
  // The same URL re-activates the existing tab instead of duplicating.
  let (_, model) = update(
    dispatch,
    ExternalLinkClicked("http://127.0.0.1:5173/"),
    model,
  )
  assert_eq(model.dock.tabs.length(), 2)
  assert_eq(model.preview.pages.length(), 2)
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
    { ..model, screen: Settings },
  )
  assert_eq(settings.dock.tabs.length(), 3)
  assert_eq(settings.preview.pages.length(), 3)
  assert_eq(settings.file_panel.file_link_generation, generation + 4)
}

///|
test "same-URL reuse scans this strip, not the global page map" {
  let dispatch = test_dispatch()
  let url = "http://127.0.0.1:5173/"
  // Another conversation's parked strip already holds this URL: its page
  // sits in the global map with no tab in this strip. It must not shadow
  // this strip's own tab.
  let (foreign, _) = @preview.open_page(@preview.State::empty(), url~)
  let model = { ..desktop_model(), preview: foreign }
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
  let rect : @preview.Rect = { x: 480, y: 46, width: 640, height: 700 }
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
test "pane measurements place the active view and idempotently settle" {
  let dispatch = test_dispatch()
  let model = desktop_model()
  let (_, model) = update(
    dispatch,
    ExternalLinkClicked("http://127.0.0.1:5173/"),
    model,
  )
  let rect : @preview.Rect = { x: 480, y: 46, width: 640, height: 700 }
  let (_, model) = update(dispatch, BrowserPaneMeasured(rect~), model)
  assert_true(model.browser_pane.shown == Some(1))
  assert_true(model.browser_pane.rect == Some(rect))
  let (_, again) = update(dispatch, BrowserPaneMeasured(rect~), model)
  assert_true(again == model)
  // A zero-size measurement (the observer firing against a hidden pane)
  // never places the view.
  let zero : @preview.Rect = { x: 0, y: 0, width: 0, height: 0 }
  let (_, still) = update(dispatch, BrowserPaneMeasured(rect=zero), model)
  assert_true(still.browser_pane.rect == Some(rect))
}

///|
test "the launcher popup and tab close both retire the shown view" {
  let dispatch = test_dispatch()
  let model = desktop_model()
  let (_, model) = update(
    dispatch,
    ExternalLinkClicked("http://127.0.0.1:5173/"),
    model,
  )
  let rect : @preview.Rect = { x: 480, y: 46, width: 640, height: 700 }
  let (_, model) = update(dispatch, BrowserPaneMeasured(rect~), model)
  assert_true(model.browser_pane.shown == Some(1))
  // The popup overlaps the pane, so the native view must hide under it.
  let (_, covered) = update(dispatch, ToggleRightPanelMenu, model)
  assert_true(covered.browser_pane.shown is None)
  // Closing the tab drops the page and the placement.
  let (_, closed) = update(
    dispatch,
    Dock(TabClosed(@dock.DockTab::Browser(id=1))),
    model,
  )
  assert_true(closed.browser_pane.shown is None)
  assert_true(@preview.page(closed.preview, 1) is None)
  assert_true(closed.dock.tabs.is_empty())
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
  let rect : @preview.Rect = { x: 480, y: 46, width: 640, height: 700 }
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
  let rect : @preview.Rect = { x: 480, y: 46, width: 640, height: 700 }
  let (_, model) = update(dispatch, BrowserPaneMeasured(rect~), model)
  assert_true(model.browser_pane.shown == Some(1))
  // The workspace picker's modal covers the pane; native views z-order
  // above HTML, so the view must hide first.
  let (_, covered) = update(dispatch, PickProject(Local), model)
  assert_true(covered.project_picker is Some(_))
  assert_true(covered.browser_pane.shown is None)
  // Closing the modal re-measures; the next measurement re-places the view.
  let (_, closed) = update(dispatch, ProjectPickerClose, covered)
  let (_, restored) = update(dispatch, BrowserPaneMeasured(rect~), closed)
  assert_true(restored.browser_pane.shown == Some(1))
  // The topbar app launcher covers the pane too, and so does the composer's
  // git popover: it opens upward over the pane's bottom-left corner, and a
  // native view left showing would paint straight over it.
  let (_, launched) = update(dispatch, ToggleLauncher, restored)
  assert_true(launched.browser_pane.shown is None)
  // The popover needs a branch to have a trigger at all, so give the
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
    QuickOpenOpen(QuickOpenSymbols),
    restored,
  )
  assert_true(searching.quick_open is Some(_))
  assert_true(searching.browser_pane.shown is None)
}
