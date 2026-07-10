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
/// Whether an event the engine emits while idle (between turns) — the
/// compaction lifecycle and background-job notices — so the routing must
/// match by last run id: the run that owned the id has already cleared
/// `active_run_id` by the time these arrive.
fn is_idle_event(event : @transcript.EngineEvent) -> Bool {
  match event {
    CompactionStarted
    | CompactionFinished(_)
    | CompactionFailed(_)
    | RuntimeUpdate(_) => true
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
    // The chip carries its envelope form directly: the skill's bare name (its
    // `insert` has a trailing space), or the symbol's name plus resolved
    // location.
    SkillMentions =>
      accept_mention(
        model,
        Skill(name=item.insert.trim().to_owned()),
        range=None,
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
      )
    }
  }
}

///|
/// Attach a mention chip to the active conversation's draft (deduplicated),
/// clear the typed trigger token, and close the menu.
fn accept_mention(
  model : Model,
  ref_ : @mention_context.MentionRef,
  range~ : @common.Range?,
) -> (@cmd.Cmd, Model) {
  let conv = model.active()
  let mentions = push_mention(conv.mentions, { ref_, range })
  (
    @cmd.none,
    {
      ..model.replace_conversation({ ..conv, task: "", mentions }),
      completion: None,
    },
  )
}

///|
/// A chip's raw jump path as the workspace-relative form the panel and the
/// host's workspace-rooted ops speak. The steady state is the identity: chips
/// minted since the panel started recording relative names are already
/// relative. A legacy envelope can still carry an absolute path (minted
/// before `cwd` was known); those are brought back inside against the
/// conversation's roots, and `None` — an absolute path outside anything this
/// conversation knows — means there is nothing the panel could open.
fn conversation_relative(
  conv : Conversation,
  path : String,
) -> @pathx.Relative? {
  guard is_absolute_path(path) else { return Some(Relative(path)) }
  let absolute : @pathx.Absolute = Absolute(path)
  for root in [conv.cwd, conv.workspace] {
    if root is Some(root) &&
      absolute.relative_to(root~) is Some(rest) &&
      !rest.is_root() {
      return Some(rest)
    }
  }
  None
}

///|
/// Whether a chip path is lexically absolute (POSIX root or a Windows drive)
/// rather than workspace-relative.
fn is_absolute_path(path : String) -> Bool {
  match path[:] {
    ['/', ..] | ['\\', ..] => true
    [drive, ':', ..] => drive.is_ascii_alphabetic()
    _ => false
  }
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
  annotation? : String,
) -> (@cmd.Cmd, Model) {
  let conv = model.active()
  let femit = dispatch.map(msg => FileEditor(msg))
  // Re-root only when the panel's cached tree belongs to another
  // conversation; otherwise `sync_file_panel`'s post-dispatch pass would
  // see a session mismatch and wipe the tab/`open` set below.
  let panel = if model.file_panel.session == conv.session_id {
    model.file_panel
  } else {
    { ..@fileeditor.State::empty(), session: conv.session_id }
  }
  guard conversation_relative(conv, path) is Some(relative) else {
    return (
      @fileeditor.mount_cmds(femit),
      {
        ..model,
        file_panel: {
          ..panel,
          open: true,
          error: "\{path} is outside the conversation workspace",
        },
      },
    )
  }
  let (cmd, panel) = @fileeditor.open_file(
    femit,
    panel,
    file_ctx(model),
    relative,
    range~,
    annotation?,
  )
  (cmd, { ..model, file_panel: panel })
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
    workspace=workspace_root(model.session_workspace(session)),
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
            session=conv.session_id,
            model=model.selected_model,
            max_steps=model.max_steps,
            api_key=model.effective_api_key(),
            api_url=model.effective_api_url(),
            workspace?=conv.workspace,
            wsl_enabled=model.wsl_active(),
            wsl_distro=model.wsl_distro,
            wsl_engine=model.wsl_engine,
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
              brief=None,
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
            name=if tool_name.trim().is_empty() { "tool" } else { tool_name },
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
            name=if tool_name.trim().is_empty() { "tool" } else { tool_name },
            is_error=true,
            brief=None,
          ),
          if reason.trim().is_empty() {
            "tool call decode error"
          } else {
            reason
          },
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
    // The checkpoint notice is not a task answer, but keeping the engine's
    // continuation guidance in the transcript makes the live view agree with
    // durable-session replay. The separate host Finished message closes the
    // run with the non-success `context_yield` outcome.
    ContextYield(answer) => {
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
    // Automatic compaction runs inside this open turn. Show the durable
    // checkpoint with the same Summary card as manual compaction and replay,
    // but leave the between-turn CompactionPhase untouched.
    AutoCompactionFinished(summary) => {
      let summary = summary.trim().to_owned()
      if summary.is_empty() {
        (false, conv)
      } else {
        (true, conv.append_item(Summary, summary))
      }
    }
    // Compaction runs while the engine is idle and the next prompt will carry
    // the shrunken context. The summary is appended as a `Summary` item, the
    // same shape a reloaded session shows for the checkpoint, so the live and
    // replayed transcripts agree.
    CompactionStarted => (false, { ..conv, compaction: Compacting })
    CompactionFinished(summary) => {
      let conv = { ..conv, compaction: NotCompacting }
      let summary = summary.trim().to_owned()
      if summary.is_empty() {
        (false, conv)
      } else {
        (true, conv.append_item(Summary, summary))
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
        { ..conv, compaction: NotCompacting }.append_item(
          Assistant(true),
          content,
        ),
      )
    }
  }
}

///|
/// The file-editor package's view of the active conversation: which session
/// the panel serves, the workspace hint its fs ops carry, and the viewer's
/// theme. Recomputed per dispatch — it is only a projection of the model.
fn file_ctx(model : Model) -> @fileeditor.Ctx {
  let conv = model.active()
  {
    session: conv.session_id,
    workspace: conv.workspace,
    dark_mode: model.dark_mode,
    tree_layout: model.tree_layout,
  }
}

///|
/// Reconcile the file panel with the active conversation after every message
/// (see `@fileeditor.sync`). Centralizing it here keeps every
/// conversation-switching handler from having to re-root the panel itself.
fn sync_file_panel(
  dispatch : @cmd.Emit[Msg],
  model : Model,
) -> (Model, @cmd.Cmd) {
  let (panel, cmd) = @fileeditor.sync(
    dispatch.map(msg => FileEditor(msg)),
    model.file_panel,
    file_ctx(model),
  )
  ({ ..model, file_panel: panel }, cmd)
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
          bridge: Connected,
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
      (@cmd.none, { ..model, bridge: BridgeLost(message) })
    SettingsLoaded(
      provider~,
      custom_url~,
      api_key~,
      custom_api_key~,
      wsl_enabled~,
      wsl_distro~,
      wsl_engine~,
      notification_corner~,
      tree_layout~,
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
        tree_layout: @fileeditor.TreeLayout::parse(tree_layout),
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
      guard mention_target(mention.ref_) is Some(target) else {
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
      if !conv.draft_sendable() ||
        !(model.bridge is Connected) ||
        !model.api_ready() {
        (@cmd.none, model)
      } else if conv.is_running() {
        // Submitting while this conversation's turn runs steers it: the text
        // is folded into the running turn at its next step boundary and
        // echoed back as a `steer_applied` event. A turn being cancelled
        // cannot be steered — the steer could outlive the dying turn in the
        // engine's queue and contaminate a later prompt — so the text stays
        // in the composer.
        if conv.run is Open(run_id~, stage~) && !(stage is Cancelling) {
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
        let next = conv.append_item(User, task)
        let next = {
          ..next,
          task: "",
          mentions: [],
          run: Starting,
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
      if conv.run is Open(run_id~, ..) {
        (
          cancel_openseek(dispatch, run_id),
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
          !conv.is_running() {
          { ..conv, workspace: workspace_root(model.active_workspace) }
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
        if conv.workspace is Some(workspace) && !paths.contains(workspace.0) {
          { ..conv, workspace: None }
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
            active_workspace: workspace_token(conv.workspace),
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
        conv.is_running() {
        // A run that started in this conversation while the load was in flight
        // wins; dropping the reply keeps the live state intact.
        (@cmd.none, { ..model, loading_session: "" })
      } else {
        (
          // The host derives the resumed workspace from the session id, so
          // the branch probe sends no cwd.
          @cmd.batch([
            scroll_transcript_after_render(),
            fetch_branch(dispatch, session_id, None),
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
      (open_file(dispatch, conv.session_id, cwd=conv.cwd, path), model)
    }
    ToggleLauncher => {
      let opening = !model.launcher.open
      // Probe the host the first time the menu opens (and again after a
      // failure); the result is kept for the app run.
      let cmd = if opening && !(model.launcher.apps is AppsFetched(_)) {
        fetch_apps(dispatch)
      } else {
        @cmd.none
      }
      (cmd, { ..model, launcher: { ..model.launcher, open: opening } })
    }
    LauncherLoaded(apps) =>
      (
        @cmd.none,
        { ..model, launcher: { ..model.launcher, apps: AppsFetched(apps) } },
      )
    LauncherFailed(message) =>
      (
        @cmd.none,
        { ..model, launcher: { ..model.launcher, apps: AppsFailed(message) } },
      )
    LaunchApp(app) => {
      let conv = model.active()
      (
        launch_app(dispatch, conv.session_id, cwd=conv.cwd, app),
        { ..model, launcher: { ..model.launcher, open: false } },
      )
    }
    Started(run_id~, session~, model=selected_model, max_steps~, cwd~) =>
      if model.find_conversation(session) is Some(conv) {
        let updated = model.replace_conversation({
          ..conv,
          run: Open(run_id~, stage=Opened),
          last_run_id: Some(run_id),
          // A started run always reports its directory, but a malformed
          // event decodes as `None`; keeping the previous root beats
          // forgetting one we already knew.
          cwd: if cwd is Some(_) {
            cwd
          } else {
            conv.cwd
          },
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
    Engine(run_id, event, session~) => {
      // Compaction and background notices happen between turns, so their
      // events arrive after the run that owned `run_id` cleared
      // `active_run_id`. The host stamps them with their session, which also
      // covers a conversation compacted before its first prompt of this
      // app-lifetime (its engine has no run id at all); the conversation
      // that last held the id remains the fallback for unstamped events.
      let conv = if model.conversation_by_run(run_id) is Some(conv) {
        Some(conv)
      } else if is_idle_event(event) {
        if session is Some(session) &&
          model.find_conversation(session) is Some(conv) {
          Some(conv)
        } else {
          model.conversation_by_last_run(run_id)
        }
      } else {
        None
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
    // Everything else the panel owns (tree, viewer, diagnostics) is the
    // fileeditor package's business; route it there and adopt its state.
    FileEditor(msg) => {
      let (cmd, panel) = @fileeditor.update(
        dispatch.map(msg => FileEditor(msg)),
        msg,
        model.file_panel,
        file_ctx(model),
      )
      (cmd, { ..model, file_panel: panel })
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
          run: NoRun(ended=Some(RunFailed)),
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
      // A host error without a run belongs to whatever conversation the
      // user is looking at.
      let conv = if run_id is Some(run_id) {
        model.conversation_by_run(run_id)
      } else {
        Some(model.active())
      }
      if conv is Some(conv) {
        let content = if diagnostics is Some(diagnostics) &&
          !diagnostics.trim().is_empty() {
          message + "\n\n" + diagnostics
        } else {
          message
        }
        // Mid-run the error is transient — the host closes the run with its
        // own finished event moments later, and that verdict wins; only an
        // idle conversation keeps the error as how things stand.
        let next = conv.append_item(Assistant(true), content)
        (
          scroll_if_active(model, conv.session_id),
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
      if model.find_conversation(session) is Some(conv) {
        (
          scroll_if_active(model, conv.session_id),
          model.replace_conversation({
            ..conv.append_item(Assistant(true), message),
            compaction: NotCompacting,
          }),
        )
      } else {
        (@cmd.none, model)
      }
    Finished(run_id~, status~, answer~) =>
      if model.conversation_by_run(run_id) is Some(conv) {
        // In the normal path the engine settled every steer before this
        // terminal event; sweeping here only matters when the run died with
        // steers still in flight.
        let base = {
          ..conv.clear_streams().sweep_pending_steers(),
          run: NoRun(ended=Some(RunFinished(RunOutcome::parse(status)))),
          // A finish the user watched happen needs no reminder; one landing
          // in a background conversation leaves a dot until they visit.
          unseen_finish: conv.session_id != model.active_session,
        }
        let answer = answer.map(answer => answer.trim().to_owned())
        // The finished run just appended to the durable store, so the
        // sidebar list (and this conversation's title) may have changed —
        // and the turn may have created the repository or switched branches.
        let refresh = @cmd.batch([
          fetch_sessions(dispatch),
          fetch_branch(dispatch, conv.session_id, conv.cwd),
        ])
        if answer is Some(answer) && should_append_answer(conv, answer) {
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
