///|
fn should_append_answer(conv : Conversation, answer : String) -> Bool {
  if answer.trim().is_empty() {
    false
  } else if conv.last_assistant_content() is Some(existing) {
    existing != answer
  } else {
    true
  }
}

///|
/// Scroll the transcript only when `session_id` is the conversation on
/// screen — a background conversation's stream must not yank the visible
/// scroll position around — and only while the user is at the bottom:
/// someone who scrolled up to read history stays where they are.
fn scroll_if_active(model : Model, session_id : String) -> @cmd.Cmd {
  if session_id == model.active_session && model.transcript_pinned {
    scroll_transcript_after_render()
  } else {
    @cmd.none
  }
}

///|
/// Whether an event is part of the compaction lifecycle, which the engine
/// emits while idle and the routing therefore matches by last run id.
fn is_compaction_event(event : @transcript.EngineEvent) -> Bool {
  match event {
    CompactionStarted | CompactionFinished(_) | CompactionFailed(_) => true
    _ => false
  }
}

///|
/// Apply an accepted completion row: a slash command runs its action, while a
/// skill mention or symbol reference becomes a chip in the composer's mention
/// tray (its expansion is spliced into the prompt on send). Either way the menu
/// closes and the typed trigger token is cleared from the textarea.
fn accept_completion(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  menu : Completion,
  item : CompletionItem,
) -> (@cmd.Cmd, Model) {
  match menu.kind {
    SlashCommands => run_slash_command(dispatch, model, item.command)
    // The chip label is the bare name (the skill's `insert` carries a trailing
    // space; the symbol's `label` is already bare); `insert` is the expansion
    // dropped into the prompt on send.
    SkillMentions =>
      accept_mention(
        model,
        SkillMention,
        label=item.insert.trim().to_owned(),
        expand=item.insert,
        path=None,
        range=None,
      )
    Symbols =>
      accept_mention(
        model,
        SymbolMention,
        label=item.label,
        expand=item.insert,
        path=item.path,
        range=item.range,
      )
  }
}

///|
/// Attach a mention chip to the active conversation's draft (deduplicated),
/// clear the typed trigger token, and close the menu.
fn accept_mention(
  model : Model,
  kind : MentionKind,
  label~ : String,
  expand~ : String,
  path~ : String?,
  range~ : @common.Range?,
) -> (@cmd.Cmd, Model) {
  let conv = model.active()
  let mentions = push_mention(conv.mentions, {
    kind,
    label,
    expand,
    path,
    range,
  })
  (
    @cmd.none,
    {
      ..model.replace_conversation({ ..conv, task: "", mentions }),
      completion: None,
    },
  )
}

///|
/// Open (or refocus) the editor side-panel on `path`, revealing `range` when
/// given — the shared tail of a composer chip's and a transcript chip's jump.
fn open_editor_at(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  path : String,
  range : @common.Range?,
) -> (@cmd.Cmd, Model) {
  let conv = model.active()
  // Re-root only when the panel's cached tree belongs to another
  // conversation; otherwise `sync_file_panel`'s post-dispatch pass would
  // see a session mismatch and wipe the `selected`/`open` set below.
  let panel = if model.file_panel.session == conv.session_id {
    model.file_panel
  } else {
    { ..empty_file_panel(), session: conv.session_id }
  }
  (
    @cmd.batch([
      request_viewer_mount(),
      request_resize_handle_mount(),
      request_viewer_remeasure(),
      read_file(
        dispatch,
        conv.session_id,
        path,
        basename(path),
        range~,
        workspace=conv.workspace,
      ),
    ]),
    {
      ..model,
      file_panel: { ..panel, open: true, selected: Some(path), error: "" },
    },
  )
}

///|
/// The command, if any, to fetch workspace symbols for a changed draft. Fires
/// only when the draft is a live `#` query (a non-empty token, no spaces) whose
/// results are not already cached for this conversation — so a fresh keystroke
/// refetches but a repeat of the same query does not.
fn symbol_fetch_cmd(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  value : String,
  session : String,
) -> @cmd.Cmd {
  guard value.has_prefix("#") && trigger_query(value) is Some(query) else {
    return @cmd.none
  }
  if model.symbol_cache.session == session && model.symbol_cache.query == query {
    return @cmd.none
  }
  read_workspace_symbols(
    dispatch,
    session,
    query,
    workspace=model.session_workspace(session),
  )
}

///|
/// Fold a workspace-symbol reply into the model: cache it and rebuild the menu,
/// but only while it still answers the composer's live `#` query for the active
/// conversation — a reply overtaken by a conversation switch or a later
/// keystroke is dropped, the same staleness guard the file panel uses.
fn apply_symbol_reply(
  model : Model,
  session : String,
  query : String,
  items : Array[CompletionItem],
) -> (@cmd.Cmd, Model) {
  let draft = model.active().task
  guard session == model.active().session_id &&
    draft.has_prefix("#") &&
    trigger_query(draft) is Some(live) &&
    live == query else {
    return (@cmd.none, model)
  }
  let cache : SymbolCache = { session, query, items }
  (
    @cmd.none,
    {
      ..model,
      symbol_cache: cache,
      completion: compute_completion(
        draft,
        model.installed_skills,
        cache,
        session,
      ),
    },
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
      (
        compact_openseek(dispatch, conv.session_id),
        { ..model.replace_conversation({ ..conv, task: "" }), completion: None },
      )
    }
    _ => (@cmd.none, { ..model, completion: None })
  }
}

///|
/// Fold one engine event into its conversation. Returns whether the
/// transcript visibly grew (the caller turns that into a scroll command only
/// when this conversation is the one on screen) and the new conversation.
fn apply_engine_event(
  conv : Conversation,
  event : @transcript.EngineEvent,
) -> (Bool, Conversation) {
  match event {
    AgentStep(detail) =>
      (false, { ..conv.clear_streams(), status: Step(detail) })
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
    // The turn's full reasoning, emitted once its streaming ends and before
    // the assistant message commits — so the transcript reads thought →
    // answer.
    ReasoningMessage(content) => {
      let next = { ..conv, streaming_reasoning: "" }
      let content = content.trim().to_owned()
      if content.is_empty() {
        (false, next)
      } else {
        (true, next.append_item(Reasoning, content))
      }
    }
    AssistantMessage(content) => {
      let conv = conv.clear_streams()
      let content = content.trim().to_owned()
      if content.is_empty() {
        (false, conv)
      } else {
        (true, conv.append_item(Assistant(false), content))
      }
    }
    RuntimeUpdate(content) => {
      let update = @transcript.parse_runtime_update(content)
      let next = { ..conv, watcher_status: update.status }
      if !update.status.is_empty() || update.diagnostics.length() > 0 {
        (
          true,
          next.append_item(
            Tool(
              name=@transcript.runtime_update_title(update),
              is_error=false,
              brief="",
            ),
            update.diagnostics.join("\n"),
          ),
        )
      } else {
        (false, next)
      }
    }
    Usage(prompt_tokens~, completion_tokens~) =>
      (false, { ..conv, usage_tokens: prompt_tokens + completion_tokens })
    ToolResult(tool_name~, is_error~, content~, brief~) =>
      (
        true,
        conv.append_item(
          Tool(
            name=@transcript.non_empty_or(tool_name, "tool"),
            is_error~,
            brief~,
          ),
          content,
        ),
      )
    ToolCallDecodeError(tool_name~, reason~) =>
      (
        true,
        conv.append_item(
          Tool(
            name=@transcript.non_empty_or(tool_name, "tool"),
            is_error=true,
            brief="",
          ),
          @transcript.non_empty_or(reason, "tool call decode error"),
        ),
      )
    AgentFinished(answer) => {
      let conv = conv.clear_streams()
      let answer = answer.trim().to_owned()
      if should_append_answer(conv, answer) {
        (true, conv.append_item(Assistant(false), answer))
      } else {
        (false, conv)
      }
    }
    AgentAborted(reason) => {
      let content = if reason.trim().is_empty() {
        "aborted"
      } else {
        "aborted: " + reason
      }
      (true, conv.clear_streams().append_item(Assistant(true), content))
    }
    MaxStepsExhausted =>
      (
        true,
        conv.clear_streams().append_item(Assistant(true), "max steps exhausted"),
      )
    AgentSetupFailed(reason) => {
      let content = if reason.trim().is_empty() {
        "setup failed"
      } else {
        "setup failed: " + reason
      }
      (true, conv.clear_streams().append_item(Assistant(true), content))
    }
    // The steer took effect at a step boundary: it is part of the
    // conversation now, so echo it as a user message.
    SteerApplied(content) =>
      (true, conv.settle_pending_steer(content).append_item(User, content))
    // The steer raced the turn's end through the pipes and was rejected; the
    // text must not vanish silently.
    SteerDropped(content) =>
      (
        true,
        conv
        .settle_pending_steer(content)
        .append_item(Assistant(true), steer_dropped_notice(content)),
      )
    // Compaction runs while the engine is idle and the next prompt will carry
    // the shrunken context. The summary is appended as a `summary` item, the
    // same shape a reloaded session shows for the checkpoint, so the live and
    // replayed transcripts agree.
    CompactionStarted => (false, { ..conv, compacting: true })
    CompactionFinished(summary) => {
      let conv = { ..conv, compacting: false }
      let summary = summary.trim().to_owned()
      if summary.is_empty() {
        (false, conv)
      } else {
        (
          true,
          conv.append_item(
            Tool(name="summary", is_error=false, brief=""),
            summary,
          ),
        )
      }
    }
    CompactionFailed(reason) => {
      let content = if reason.trim().is_empty() {
        "compaction failed"
      } else {
        "compaction failed: " + reason
      }
      (
        true,
        { ..conv, compacting: false }.append_item(Assistant(true), content),
      )
    }
  }
}

///|
/// Reconcile the file panel with the active conversation after every message:
/// rebuild it when the conversation changed and list the workspace root once
/// its path is known. Centralizing it here keeps every conversation-switching
/// handler from having to re-root the panel itself. A no-op unless the panel
/// is open and a load is actually due, so it never re-fires while a request is
/// in flight or the tree is already current.
fn sync_file_panel(
  dispatch : @cmd.Emit[Msg],
  model : Model,
) -> (Model, @cmd.Cmd) {
  let panel = model.file_panel
  guard panel.open else { return (model, @cmd.none) }
  let conv = model.active()
  // When the active conversation changes, drop the cached tree *and* the
  // viewer's open document — the viewer is imperative state outside the model,
  // so it would otherwise keep showing the previous conversation's file.
  let (panel, reroot_cmd) = if panel.session == conv.session_id {
    (panel, @cmd.none)
  } else {
    (
      { ..empty_file_panel(), open: true, session: conv.session_id },
      clear_viewer(),
    )
  }
  // Load as soon as there is a conversation: the workspace directory is a pure
  // function of the session id, so the host can list it without waiting for a
  // run to report `cwd` (it reports an empty workspace until the first turn
  // creates the directory).
  if conv.session_id.is_empty() ||
    panel.children.contains("") ||
    panel.loading.contains("") {
    return ({ ..model, file_panel: panel }, reroot_cmd)
  }
  let loading = panel.loading.copy()
  loading.push("")
  (
    { ..model, file_panel: { ..panel, loading, } },
    @cmd.batch([
      reroot_cmd,
      read_directory(dispatch, conv.session_id, "", workspace=conv.workspace),
    ]),
  )
}

///|
fn update(
  dispatch : @cmd.Emit[Msg],
  msg : Msg,
  model : Model,
) -> (@cmd.Cmd, Model) {
  let (cmd, model) = update_msg(dispatch, msg, model)
  let (model, panel_cmd) = sync_file_panel(dispatch, model)
  (@cmd.batch([cmd, panel_cmd]), model)
}

///|
fn update_msg(
  dispatch : @cmd.Emit[Msg],
  msg : Msg,
  model : Model,
) -> (@cmd.Cmd, Model) {
  match msg {
    Init =>
      (
        @cmd.batch([
          install_bridge(dispatch),
          load_saved_settings(dispatch),
          watch_transcript_scroll(dispatch),
          watch_color_scheme(dispatch),
          rotate_session(dispatch),
        ]),
        model,
      )
    BridgeReady =>
      (
        // The installed skills also feed the composer's `$` completion, so they
        // are fetched on connect rather than only when the Skills page opens.
        // The startup update check rides here too: settings (the channel)
        // load synchronously at Init, so they are in by bridge time.
        @cmd.batch([
          fetch_sessions(dispatch),
          fetch_installed_skills(dispatch),
          fetch_archived(dispatch),
          fetch_workspaces(dispatch),
          check_for_updates(dispatch, model.update_channel, explicit=false),
        ]),
        {
          ..model,
          bridge_ready: true,
          bridge_error: "",
          // An unusable endpoint routes straight to Settings — the composer
          // could do nothing anyway.
          screen: if model.api_ready() {
            model.screen
          } else {
            Settings
          },
        },
      )
    BridgeUnavailable(message) =>
      (@cmd.none, { ..model, bridge_ready: false, bridge_error: message })
    SettingsLoaded(
      provider~,
      custom_url~,
      api_key~,
      custom_api_key~,
      wsl_enabled~,
      wsl_distro~,
      wsl_engine~,
      notification_corner~,
      update_channel~
    ) => {
      let next = {
        ..model,
        api_provider: ApiProvider::parse(provider),
        custom_api_url: custom_url.trim().to_owned(),
        api_key: api_key.trim().to_owned(),
        custom_api_key: custom_api_key.trim().to_owned(),
        wsl_enabled: wsl_enabled == "1",
        wsl_distro: wsl_distro.trim().to_owned(),
        wsl_engine: wsl_engine.trim().to_owned(),
        notification_corner: NotificationCorner::parse(notification_corner),
        update_channel: UpdateChannel::parse(update_channel),
        setup_api_key: "",
      }
      // The default provider needs no setup, so the Settings page only takes
      // over when the stored settings are incomplete (official endpoint
      // without a key, custom endpoint without a URL).
      (
        @cmd.none,
        {
          ..next,
          screen: if next.api_ready() {
            next.screen
          } else {
            Settings
          },
        },
      )
    }
    TaskChanged(value) => {
      let session = model.active().session_id
      (
        symbol_fetch_cmd(dispatch, model, value, session),
        {
          ..model.replace_conversation({ ..model.active(), task: value }),
          completion: compute_completion(
            value,
            model.installed_skills,
            model.symbol_cache,
            session,
          ),
        },
      )
    }
    CompletionMove(delta) =>
      if model.completion is Some(menu) {
        (@cmd.none, { ..model, completion: Some(menu.shifted(delta)) })
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
      guard mention.path is Some(path) else { return (@cmd.none, model) }
      open_editor_at(dispatch, model, path, mention.range)
    }
    JumpToLocation(path~, line~) => {
      // A transcript chip carries only the reference's line (the envelope
      // stores `path:line`); an empty range still anchors the viewer there,
      // it just selects nothing.
      let range = if line >= 1 {
        Some(@common.Range::Range(line, 1, line, 1))
      } else {
        None
      }
      open_editor_at(dispatch, model, path, range)
    }
    CompletionAccept =>
      if model.completion is Some(menu) && menu.current() is Some(item) {
        accept_completion(dispatch, model, menu, item)
      } else {
        (@cmd.none, { ..model, completion: None })
      }
    CompletionPick(index) =>
      if model.completion is Some(menu) && menu.items.get(index) is Some(item) {
        accept_completion(dispatch, model, menu, item)
      } else {
        (@cmd.none, { ..model, completion: None })
      }
    SymbolsLoaded(session~, query~, items~) =>
      apply_symbol_reply(model, session, query, items)
    // A failed search reads as "no symbols": cache an empty result for the
    // query so the menu settles on "No symbols" rather than spinning.
    SymbolsFailed(session~, query~) =>
      apply_symbol_reply(model, session, query, [])
    ModelChanged(value) => (@cmd.none, { ..model, selected_model: value })
    MaxStepsChanged(value) => (@cmd.none, { ..model, max_steps: value })
    SetupApiKeyChanged(value) => (@cmd.none, { ..model, setup_api_key: value })
    ProviderChanged(value) => {
      let provider = ApiProvider::parse(value)
      (
        save_api_provider(provider),
        { ..model, api_provider: provider, setup_api_key: "" },
      )
    }
    CustomApiUrlChanged(value) =>
      (save_custom_api_url(value), { ..model, custom_api_url: value })
    WslModeChanged(value) => {
      let enabled = value == "wsl"
      (save_wsl_enabled(enabled), { ..model, wsl_enabled: enabled })
    }
    WslDistroChanged(value) =>
      (save_wsl_distro(value), { ..model, wsl_distro: value })
    WslEngineChanged(value) =>
      (save_wsl_engine(value), { ..model, wsl_engine: value })
    NotificationCornerChanged(value) => {
      let corner = NotificationCorner::parse(value)
      (
        save_notification_corner(corner),
        { ..model, notification_corner: corner },
      )
    }
    NotificationExpired(id) | DismissNotification(id) =>
      (
        @cmd.none,
        { ..model, notifications: model.notifications.filter(t => t.id != id) },
      )
    UpdateChannelChanged(value) => {
      let channel = UpdateChannel::parse(value)
      // Whatever the old channel said no longer applies; the next check
      // (Settings button or next launch) answers for the new one.
      (
        save_update_channel(channel),
        { ..model, update_channel: channel, update_ux: UpdateUnknown },
      )
    }
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
          check_for_updates(dispatch, model.update_channel, explicit=true),
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
        CheckFound(version~, installable~) =>
          (
            @cmd.none,
            { ..model, update_ux: UpdateAvailable(version~, installable~) },
          )
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
            download_update(dispatch, model.update_channel),
            { ..model, update_ux: DownloadingUpdate(version~) },
          )
        }
      } else {
        (@cmd.none, model)
      }
    ConfirmUpdateRestart =>
      if model.update_ux is ConfirmingRestart(version~) {
        (
          download_update(dispatch, model.update_channel),
          { ..model, update_ux: DownloadingUpdate(version~) },
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
    UpdateDownloaded =>
      if model.update_ux is DownloadingUpdate(version~) {
        (
          apply_update(dispatch),
          { ..model, update_ux: RestartingForUpdate(version~) },
        )
      } else {
        (@cmd.none, model)
      }
    UpdateFailed(message~) => {
      // Download or swap failed: say why, and put the button back so the
      // user can retry.
      let (cmd, next) = model.notify_error(dispatch, message)
      let update_ux = match next.update_ux {
        DownloadingUpdate(version~) | RestartingForUpdate(version~) =>
          UpdateAvailable(version~, installable=true)
        other => other
      }
      (cmd, { ..next, update_ux, })
    }
    UpdateApplied => (close_window(), model)
    OpenSetup => (@cmd.none, { ..model, screen: Settings, setup_api_key: "" })
    ToggleSidebar => (@cmd.none, { ..model, sidebar_open: !model.sidebar_open })
    ToggleChatsSection =>
      (@cmd.none, { ..model, chats_collapsed: !model.chats_collapsed })
    ToggleWorkspacesSection =>
      (
        @cmd.none,
        { ..model, workspaces_collapsed: !model.workspaces_collapsed },
      )
    SaveApiKey => {
      let api_key = model.setup_api_key.trim().to_owned()
      if api_key.is_empty() {
        (@cmd.none, model)
      } else {
        match model.api_provider {
          // Saving the key that completes the setup returns to the chat —
          // the same auto-dismiss the popup used to have.
          Deepseek => {
            let next = { ..model, api_key, setup_api_key: "" }
            (
              save_api_key(api_key),
              { ..next, screen: if next.api_ready() { Chat } else { Settings } },
            )
          }
          Custom => {
            let next = { ..model, custom_api_key: api_key, setup_api_key: "" }
            (
              save_custom_api_key(api_key),
              { ..next, screen: if next.api_ready() { Chat } else { Settings } },
            )
          }
          Openseek => (@cmd.none, { ..model, setup_api_key: "" })
        }
      }
    }
    OpenSkills => {
      // The catalog is fetched once per app run (and again after a
      // failure); the installed list is cheap and refreshes on every open.
      let (catalog_cmd, skills_catalog) = match model.skills_catalog {
        CatalogIdle | CatalogFailed(_) =>
          (fetch_skills_catalog(dispatch), CatalogLoading)
        current => (@cmd.none, current)
      }
      (
        @cmd.batch([catalog_cmd, fetch_installed_skills(dispatch)]),
        { ..model, screen: Skills, skills_catalog, skills_notice: "" },
      )
    }
    SkillsQueryChanged(value) => (@cmd.none, { ..model, skills_query: value })
    SkillsCatalogLoaded(items) =>
      (@cmd.none, { ..model, skills_catalog: CatalogReady(items) })
    SkillsCatalogFailed(message) =>
      (@cmd.none, { ..model, skills_catalog: CatalogFailed(message) })
    InstalledSkillsLoaded(items) =>
      (@cmd.none, { ..model, installed_skills: items })
    SkillsNotice(message) => (@cmd.none, { ..model, skills_notice: message })
    InstallSkill(item) => {
      let key = @transcript.market_source_label(item)
      if model.skills_busy.contains(key) {
        (@cmd.none, model)
      } else {
        let skills_busy = model.skills_busy.copy()
        skills_busy.push(key)
        (
          install_skill(dispatch, item),
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
          uninstall_skill(dispatch, id),
          { ..model, skills_busy, skills_notice: "" },
        )
      }
    SkillActionDone(key~, error~) => {
      let skills_busy = model.skills_busy.filter(entry => entry != key)
      if error.is_empty() {
        // The library changed; what the panel shows must come from disk,
        // not from a client-side guess.
        (fetch_installed_skills(dispatch), { ..model, skills_busy, })
      } else {
        (@cmd.none, { ..model, skills_busy, skills_notice: error })
      }
    }
    Send => {
      let conv = model.active()
      // The outgoing prompt is the typed text with the chips folded in as the
      // `<user_mentions>` envelope. Typed text is required — chips alone are
      // context without an instruction and stay in the composer.
      let task = compose_prompt(conv.mentions, conv.task).trim().to_owned()
      if !conv.draft_sendable() || !model.bridge_ready || !model.api_ready() {
        (@cmd.none, model)
      } else if conv.running {
        // Submitting while this conversation's turn runs steers it: the text
        // is folded into the running turn at its next step boundary and
        // echoed back as a `steer_applied` event. A turn being cancelled
        // cannot be steered — the steer could outlive the dying turn in the
        // engine's queue and contaminate a later prompt — so the text stays
        // in the composer.
        if conv.active_run_id is Some(run_id) && !(conv.status is Cancelling) {
          let pending_steers = conv.pending_steers.copy()
          pending_steers.push(task)
          (
            @cmd.batch([
              steer_openseek(dispatch, conv.session_id, task, run_id),
              scroll_transcript_after_render(),
            ]),
            {
              ..model.replace_conversation({
                ..conv,
                pending_steers,
                task: "",
                mentions: [],
              }),
              transcript_pinned: true,
              completion: None,
            },
          )
        } else {
          (@cmd.none, model)
        }
      } else if conv.compacting {
        // A prompt submitted mid-compaction would sit in the serve engine's
        // queue behind it, where Stop (which cancels only the compaction)
        // cannot reach it — the user's cancel would not stop the submitted
        // work. The draft stays in the composer until compaction settles.
        (@cmd.none, model)
      } else {
        let next = conv.append_item(User, task)
        let next = {
          ..next,
          task: "",
          mentions: [],
          running: true,
          active_run_id: None,
          status: Starting,
          usage_tokens: 0,
        }
        (
          @cmd.batch([
            start_openseek(
              dispatch,
              task,
              model.selected_model,
              model.max_steps,
              model.effective_api_key(),
              model.effective_api_url(),
              conv.session_id,
              workspace=conv.workspace,
              wsl_enabled=model.wsl_active(),
              wsl_distro=model.wsl_distro,
              wsl_engine=model.wsl_engine,
            ),
            scroll_transcript_after_render(),
          ]),
          // Submitting is an explicit jump to the conversation's tail, so it
          // re-pins a transcript the user had scrolled away from.
          {
            ..model.replace_conversation(next),
            transcript_pinned: true,
            completion: None,
          },
        )
      }
    }
    SteerUndelivered(session~, text~) =>
      // The steer never reached the engine, so no `steer_applied` /
      // `steer_dropped` event will settle it — report the loss here instead.
      if model.find_conversation(session) is Some(conv) {
        let settled = conv.settle_pending_steer(text)
        if settled.pending_steers.length() == conv.pending_steers.length() {
          (@cmd.none, model)
        } else {
          (
            scroll_if_active(model, session),
            model.replace_conversation(
              settled.append_item(Assistant(true), steer_dropped_notice(text)),
            ),
          )
        }
      } else {
        (@cmd.none, model)
      }
    Stop => {
      let conv = model.active()
      if conv.running && conv.active_run_id is Some(run_id) {
        (
          cancel_openseek(dispatch, run_id),
          model.replace_conversation({ ..conv, status: Cancelling }),
        )
      } else {
        (@cmd.none, model)
      }
    }
    NewChat =>
      // A fresh conversation can start at any time: the current one keeps
      // running in the background and stays one sidebar click away. It lands
      // in the active workspace — the one the on-screen conversation uses.
      (rotate_session(dispatch), { ..model, loading_session: "" })
    NewChatIn(workspace) =>
      // A workspace section's own "new chat": the fresh conversation lands in
      // that project, and the workspace stays active for the next one. A new
      // loose chat unfolds the Chats section so its row is visible; a new
      // workspace chat unfolds the Workspaces section for the same reason.
      (
        rotate_session(dispatch),
        {
          ..model,
          active_workspace: workspace,
          loading_session: "",
          chats_collapsed: model.chats_collapsed && !workspace.is_empty(),
          workspaces_collapsed: model.workspaces_collapsed &&
          workspace.is_empty(),
        },
      )
    SessionRotated(session_id) => {
      let activated = model.activate(session_id)
      // A rotation creates the conversation, so stamp it with the workspace
      // it was asked into; an existing conversation keeps its own.
      let conversations = activated.conversations.map(conv => {
        if conv.session_id == session_id &&
          conv.messages.length() == 0 &&
          !conv.running {
          { ..conv, workspace: model.active_workspace }
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
          transcript_pinned: true,
          loading_session: "",
          completion: None,
        },
      )
    }
    SessionsLoaded(items) => (@cmd.none, { ..model, sessions: items })
    WorkspacesLoaded(paths) => {
      // A workspace that vanished from the registry cannot host runs anymore;
      // conversations attached to it fall back to the default store so their
      // next start does not error on an unregistered path.
      let conversations = model.conversations.map(conv => {
        if !conv.workspace.is_empty() && !paths.contains(conv.workspace) {
          { ..conv, workspace: "" }
        } else {
          conv
        }
      })
      let active_workspace = if model.active_workspace.is_empty() ||
        paths.contains(model.active_workspace) {
        model.active_workspace
      } else {
        ""
      }
      (
        @cmd.none,
        { ..model, workspaces: paths, conversations, active_workspace },
      )
    }
    PickWorkspace => (pick_workspace(dispatch), model)
    OpenWorkspaceInput => (@cmd.none, { ..model, workspace_input: Some("") })
    ToggleWorkspaceInput =>
      (
        @cmd.none,
        {
          ..model,
          workspace_input: if model.workspace_input is Some(_) {
            None
          } else {
            Some("")
          },
        },
      )
    WorkspaceInput(text) =>
      (@cmd.none, { ..model, workspace_input: Some(text) })
    AddWorkspace => {
      let path = model.workspace_input.unwrap_or("").trim().to_owned()
      if path.is_empty() {
        (@cmd.none, model)
      } else {
        (add_workspace(dispatch, path), { ..model, workspace_input: None })
      }
    }
    RemoveWorkspace(path) => (remove_workspace(dispatch, path), model)
    WorkspaceFailed(message) =>
      model.notify_error(dispatch, "Workspace error: \{message}")
    ArchiveSession(session_id) => (archive_session(dispatch, session_id), model)
    UnarchiveSession(session_id) =>
      (unarchive_session(dispatch, session_id), model)
    ArchivedLoaded(items) => {
      // Live client state for anything archived is dropped; when that
      // includes the conversation on screen, rotate to a fresh chat.
      let archived_now = (id : String) => {
        items.iter().any(item => item.id == id)
      }
      let conversations = model.conversations.filter(conv => {
        !archived_now(conv.session_id)
      })
      let next = { ..model, archived: items, conversations }
      if archived_now(model.active_session) {
        (rotate_session(dispatch), { ..next, loading_session: "" })
      } else {
        (@cmd.none, next)
      }
    }
    ArchiveFailed(message) =>
      model.notify_error(dispatch, "Archive failed: \{message}")
    SessionsFailed(message) =>
      model.notify_error(dispatch, "Session list unavailable: \{message}")
    NotificationClicked(run_id~) => {
      // The run has finished by the time its notification is clicked, so the
      // owner usually matches by last run id; a still-running owner (steered
      // runs re-notify per turn) matches by active run.
      let conv = if model.conversation_by_last_run(run_id) is Some(conv) {
        Some(conv)
      } else {
        model.conversation_by_run(run_id)
      }
      if conv is Some(conv) {
        update_msg(dispatch, OpenSession(conv.session_id), model)
      } else {
        (@cmd.none, model)
      }
    }
    OpenSession(session_id) =>
      // Selecting a conversation always returns to the chat — including
      // re-selecting the active one from the Skills page.
      if session_id.is_empty() {
        (@cmd.none, model)
      } else if session_id == model.active_session {
        (
          @cmd.none,
          { ..model, screen: Chat, loading_session: "", completion: None },
        )
      } else if model.find_conversation(session_id) is Some(conv) {
        // The conversation already has live client state — it may well still
        // be running — so switching is just a change of focus. A switch lands
        // at the new conversation's tail, so the transcript re-pins.
        (
          scroll_transcript_after_render(),
          {
            ..model.activate(session_id),
            screen: Chat,
            transcript_pinned: true,
            loading_session: "",
            completion: None,
            active_workspace: conv.workspace,
          },
        )
      } else {
        // The sidebar item says which store holds the session; opening it
        // also makes its workspace the active one, so "New chat" follows.
        let workspace = model.session_workspace(session_id)
        (
          open_session(dispatch, session_id, workspace~),
          {
            ..model,
            screen: Chat,
            loading_session: session_id,
            active_workspace: workspace,
          },
        )
      }
    SessionLoaded(session=session_id, items~) =>
      if model.loading_session != session_id {
        (@cmd.none, model)
      } else if model.find_conversation(session_id) is Some(conv) &&
        conv.running {
        // A run that started in this conversation while the load was in flight
        // wins; dropping the reply keeps the live state intact.
        (@cmd.none, { ..model, loading_session: "" })
      } else {
        (
          // The host derives the resumed workspace from the session id, so
          // the branch probe sends no cwd.
          @cmd.batch([
            scroll_transcript_after_render(),
            fetch_branch(dispatch, session_id, ""),
          ]),
          {
            ..model
            .replace_conversation({
              ..empty_conversation(
                session_id,
                workspace=model.session_workspace(session_id),
              ),
              messages: items,
            })
            .activate(session_id),
            transcript_pinned: true,
            loading_session: "",
            completion: None,
          },
        )
      }
    TranscriptPinned(pinned) =>
      (@cmd.none, { ..model, transcript_pinned: pinned })
    // Pin eagerly so the button hides on the click's own render; the scroll
    // watcher would only confirm it after the scroll settles.
    JumpToLatest =>
      (scroll_transcript_after_render(), { ..model, transcript_pinned: true })
    ColorSchemeChanged(dark) => (@cmd.none, { ..model, dark_mode: dark })
    BranchLoaded(session~, branch~) =>
      if model.find_conversation(session) is Some(conv) {
        (@cmd.none, model.replace_conversation({ ..conv, branch, }))
      } else {
        (@cmd.none, model)
      }
    OpenFile(path) => {
      // A relative path is taken against the active conversation's working
      // directory: its `cwd` for a live run, or — when resumed without one —
      // the directory the host derives from the session id. Absolute paths
      // open directly. No workspace containment — the agent surfaced it.
      let conv = model.active()
      (open_file(dispatch, conv.session_id, conv.cwd, path), model)
    }
    ToggleLauncher => {
      let opening = !model.launcher.open
      // Probe the host the first time the menu opens (and again after a
      // failure); the result is kept for the app run.
      let cmd = if opening && !model.launcher.loaded {
        fetch_apps(dispatch)
      } else {
        @cmd.none
      }
      (cmd, { ..model, launcher: { ..model.launcher, open: opening } })
    }
    LauncherLoaded(apps) =>
      (
        @cmd.none,
        {
          ..model,
          launcher: { ..model.launcher, apps, loaded: true, error: "" },
        },
      )
    LauncherFailed(message) =>
      (
        @cmd.none,
        {
          ..model,
          launcher: { ..model.launcher, loaded: false, error: message },
        },
      )
    LaunchApp(app) => {
      let conv = model.active()
      (
        launch_app(dispatch, conv.session_id, conv.cwd, app),
        { ..model, launcher: { ..model.launcher, open: false } },
      )
    }
    Started(run_id~, session~, model=selected_model, max_steps~, cwd~) =>
      if model.find_conversation(session) is Some(conv) {
        let updated = model.replace_conversation({
          ..conv,
          running: true,
          active_run_id: Some(run_id),
          last_run_id: Some(run_id),
          status: Running,
          cwd,
        })
        // The run's workspace directory now exists, so the branch chip can be
        // probed (and refreshed — a rerun may follow a checkout).
        let branch_cmd = fetch_branch(dispatch, session, cwd)
        // Sync the global model/step settings only when this start belongs to
        // the conversation on screen. A slow background start (the user switched
        // chats mid-spawn) must not overwrite settings the user has since
        // changed for the now-active conversation.
        if session == model.active_session {
          (
            branch_cmd,
            { ..updated, selected_model, max_steps: max_steps.to_string() },
          )
        } else {
          (branch_cmd, updated)
        }
      } else {
        (@cmd.none, model)
      }
    Engine(run_id, event) => {
      // Compaction is requested between turns, so its events arrive after the
      // run that owned `run_id` cleared `active_run_id`; fall back to the
      // conversation that last held the id so the summary still lands.
      let conv = match model.conversation_by_run(run_id) {
        Some(conv) => Some(conv)
        None =>
          if is_compaction_event(event) {
            model.conversation_by_last_run(run_id)
          } else {
            None
          }
      }
      if conv is Some(conv) {
        let (transcript_grew, next) = apply_engine_event(conv, event)
        (
          if transcript_grew {
            scroll_if_active(model, conv.session_id)
          } else {
            @cmd.none
          },
          model.replace_conversation(next),
        )
      } else {
        (@cmd.none, model)
      }
    }
    ToggleFilePanel => {
      let panel = model.file_panel
      // Attach the viewer the first time the column has real width, install the
      // resize-drag handle, and re-measure on every width change; loading the
      // tree is left to `sync_file_panel`.
      (
        @cmd.batch([
          request_viewer_mount(),
          request_resize_handle_mount(),
          request_viewer_remeasure(),
        ]),
        { ..model, file_panel: { ..panel, open: !panel.open } },
      )
    }
    RevealDirectory(path) =>
      if path.is_empty() {
        (
          @cmd.none,
          {
            ..model,
            file_panel: {
              ..model.file_panel,
              selected: None,
              highlighted: None,
            },
          },
        )
      } else {
        let panel = model.file_panel
        let expanded = panel.expanded.copy()
        let loading = panel.loading.copy()
        let cmds = []
        for ancestor in ancestor_paths(path) {
          if !expanded.contains(ancestor) {
            expanded.push(ancestor)
          }
          if !panel.children.contains(ancestor) && !loading.contains(ancestor) {
            loading.push(ancestor)
            cmds.push(
              read_directory(
                dispatch,
                model.active().session_id,
                ancestor,
                workspace=model.active().workspace,
              ),
            )
          }
        }
        cmds.push(reveal_row_after_render(path))
        cmds.push(@cmd.delay(dispatch(HighlightCleared(path)), 1500))
        (
          @cmd.batch(cmds),
          {
            ..model,
            file_panel: {
              ..panel,
              expanded,
              loading,
              selected: None,
              highlighted: Some(path),
            },
          },
        )
      }
    HighlightCleared(path) =>
      if model.file_panel.highlighted == Some(path) {
        (
          @cmd.none,
          { ..model, file_panel: { ..model.file_panel, highlighted: None } },
        )
      } else {
        (@cmd.none, model)
      }
    DirToggle(path) => {
      let panel = model.file_panel
      if panel.expanded.contains(path) {
        (
          @cmd.none,
          {
            ..model,
            file_panel: {
              ..panel,
              expanded: panel.expanded.filter(entry => entry != path),
            },
          },
        )
      } else {
        let expanded = panel.expanded.copy()
        expanded.push(path)
        // A directory listed once stays cached, so re-expanding is instant.
        if panel.children.contains(path) || panel.loading.contains(path) {
          (@cmd.none, { ..model, file_panel: { ..panel, expanded, } })
        } else {
          let loading = panel.loading.copy()
          loading.push(path)
          (
            read_directory(
              dispatch,
              model.active().session_id,
              path,
              workspace=model.active().workspace,
            ),
            { ..model, file_panel: { ..panel, expanded, loading } },
          )
        }
      }
    }
    FileFilterChanged(query) => {
      let panel = model.file_panel
      (@cmd.none, { ..model, file_panel: { ..panel, filter: query } })
    }
    DirLoaded(session~, path~, entries~) =>
      // Drop a reply whose conversation is no longer the panel's.
      if model.file_panel.session != session {
        (@cmd.none, model)
      } else {
        let panel = model.file_panel
        let children = panel.children.copy()
        children[path] = entries
        // A pending highlight's target row may only now exist in the DOM —
        // this directory could be one of the ancestors `RevealDirectory` had
        // to list first (e.g. reached via a mention jump, which never
        // touched `expanded`/`children` itself).
        let reveal_cmd = match panel.highlighted {
          Some(target) if ancestor_paths(target).contains(path) =>
            reveal_row_after_render(target)
          _ => @cmd.none
        }
        (
          reveal_cmd,
          {
            ..model,
            file_panel: {
              ..panel,
              children,
              loading: panel.loading.filter(entry => entry != path),
              error: "",
            },
          },
        )
      }
    DirFailed(session~, path~, message~) =>
      if model.file_panel.session != session {
        (@cmd.none, model)
      } else {
        let panel = model.file_panel
        (
          @cmd.none,
          {
            ..model,
            file_panel: {
              ..panel,
              loading: panel.loading.filter(entry => entry != path),
              error: message,
            },
          },
        )
      }
    FileSelected(path~, name~) => {
      let panel = model.file_panel
      (
        read_file(
          dispatch,
          model.active().session_id,
          path,
          name,
          range=None,
          workspace=model.active().workspace,
        ),
        { ..model, file_panel: { ..panel, selected: Some(path), error: "" } },
      )
    }
    FileLoaded(session~, path~, name~, file~, range~) =>
      // A stale read — the conversation switched, or another file was clicked
      // first — must not replace what the viewer now shows.
      if model.file_panel.session != session ||
        model.file_panel.selected != Some(path) {
        (@cmd.none, model)
      } else {
        let cmd = match file {
          // A real file also gets a diagnostics request: the host opens it in
          // the language server and returns its current diagnostics, and future
          // re-analysis arrives as `diagnostics` events.
          Content(content~, absolute~) =>
            @cmd.batch([
              show_file_in_viewer(name, content, absolute~, range~),
              request_diagnostics(dispatch, absolute),
            ])
          Binary => show_file_in_viewer(name, "Binary file is not previewable.")
          Oversized =>
            show_file_in_viewer(name, "File is too large to preview.")
        }
        (cmd, model)
      }
    DiagnosticsPublished(absolute~, diagnostics~) =>
      (apply_diagnostics(absolute, diagnostics), model)
    FileFailed(session~, message~) =>
      if model.file_panel.session != session {
        (@cmd.none, model)
      } else {
        (
          @cmd.none,
          { ..model, file_panel: { ..model.file_panel, error: message } },
        )
      }
    Failed(session~, message~) =>
      // The start request broke the turn the user just sent, so the error
      // belongs in that conversation's transcript.
      if model.find_conversation(session) is Some(conv) {
        let next = {
          ..conv
          .clear_streams()
          .sweep_pending_steers()
          .append_item(Assistant(true), message),
          running: false,
          active_run_id: None,
          status: Failed,
        }
        (
          @cmd.batch([
            scroll_if_active(model, session),
            fetch_sessions(dispatch),
          ]),
          model.replace_conversation(next),
        )
      } else {
        (@cmd.none, model)
      }
    SessionLoadFailed(session~, message~) =>
      // Only the newest selection may settle the loading marker; a failure
      // overtaken by a later click (or an abandoning New chat) is dropped.
      if model.loading_session != session {
        (@cmd.none, model)
      } else {
        // The sidebar may be listing sessions the store no longer has —
        // refresh it alongside the toast.
        let (toast, next) = model.notify_error(dispatch, message)
        (
          @cmd.batch([toast, fetch_sessions(dispatch)]),
          { ..next, loading_session: "" },
        )
      }
    HostActionFailed(message) => model.notify_error(dispatch, message)
    Error(run_id~, message~, diagnostics~) => {
      // A host error without a run (run_id is the empty sentinel) belongs to
      // whatever conversation the user is looking at.
      let conv = if run_id == EmptyRunId {
        Some(model.active())
      } else {
        model.conversation_by_run(run_id)
      }
      if conv is Some(conv) {
        let content = if diagnostics.trim().is_empty() {
          message
        } else {
          message + "\n\n" + diagnostics
        }
        (
          scroll_if_active(model, conv.session_id),
          model.replace_conversation({
            ..conv.append_item(Assistant(true), content),
            status: Errored,
          }),
        )
      } else {
        (@cmd.none, model)
      }
    }
    Finished(run_id~, status~, answer~) =>
      if model.conversation_by_run(run_id) is Some(conv) {
        // In the normal path the engine settled every steer before this
        // terminal event; sweeping here only matters when the run died with
        // steers still in flight.
        let base = {
          ..conv.clear_streams().sweep_pending_steers(),
          running: false,
          active_run_id: None,
          status: Finished(RunOutcome::parse(status)),
          // A finish the user watched happen needs no reminder; one landing
          // in a background conversation leaves a dot until they visit.
          unseen_finish: conv.session_id != model.active_session,
        }
        let answer = answer.trim().to_owned()
        // The finished run just appended to the durable store, so the
        // sidebar list (and this conversation's title) may have changed —
        // and the turn may have created the repository or switched branches.
        let refresh = @cmd.batch([
          fetch_sessions(dispatch),
          fetch_branch(dispatch, conv.session_id, conv.cwd),
        ])
        if should_append_answer(conv, answer) {
          (
            @cmd.batch([scroll_if_active(model, conv.session_id), refresh]),
            model.replace_conversation(
              base.append_item(Assistant(false), answer),
            ),
          )
        } else {
          (refresh, model.replace_conversation(base))
        }
      } else {
        (@cmd.none, model)
      }
  }
}
