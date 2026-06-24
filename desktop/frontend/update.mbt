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
/// Apply an accepted completion row: a slash command runs its action, a skill
/// mention replaces the composer's `$query` token with the skill name so the
/// user keeps typing the rest of the prompt. Either way the menu closes.
fn accept_completion(
  dispatch : @cmd.Dispatch[Msg],
  model : Model,
  menu : Completion,
  item : CompletionItem,
) -> (@cmd.Cmd, Model) {
  match menu.kind {
    SlashCommands => run_slash_command(dispatch, model, item.command)
    SkillMentions =>
      (
        @cmd.none,
        {
          ..model.replace_conversation({ ..model.active(), task: item.insert }),
          completion: None,
        },
      )
  }
}

///|
/// Run an accepted slash command against the active conversation and close the
/// completion menu. The command text is cleared from the composer; an unknown
/// id just dismisses the menu.
fn run_slash_command(
  dispatch : @cmd.Dispatch[Msg],
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
            Tool(@transcript.runtime_update_title(update), false),
            update.diagnostics.join("\n"),
          ),
        )
      } else {
        (false, next)
      }
    }
    Usage(prompt_tokens~, completion_tokens~) =>
      (false, { ..conv, usage_tokens: prompt_tokens + completion_tokens })
    ToolResult(tool_name~, is_error~, content~) =>
      (
        true,
        conv.append_item(
          Tool(@transcript.non_empty_or(tool_name, "tool"), is_error),
          content,
        ),
      )
    ToolCallDecodeError(tool_name~, reason~) =>
      (
        true,
        conv.append_item(
          Tool(@transcript.non_empty_or(tool_name, "tool"), true),
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
        (true, conv.append_item(Tool("summary", false), summary))
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
fn update(
  dispatch : @cmd.Dispatch[Msg],
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
          rotate_session(dispatch),
        ]),
        model,
      )
    BridgeReady =>
      (
        // The installed skills also feed the composer's `$` completion, so they
        // are fetched on connect rather than only when the Skills page opens.
        @cmd.batch([fetch_sessions(dispatch), fetch_installed_skills(dispatch)]),
        {
          ..model,
          bridge_ready: true,
          bridge_error: "",
          setup_open: model.setup_open || !model.api_ready(),
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
      wsl_engine~
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
        setup_api_key: "",
      }
      // The default provider needs no setup, so the popup only opens when
      // the stored settings are incomplete (official endpoint without a
      // key, custom endpoint without a URL).
      (@cmd.none, { ..next, setup_open: !next.api_ready() })
    }
    TaskChanged(value) =>
      (
        @cmd.none,
        {
          ..model.replace_conversation({ ..model.active(), task: value }),
          completion: compute_completion(value, model.installed_skills),
        },
      )
    CompletionMove(delta) =>
      if model.completion is Some(menu) {
        (@cmd.none, { ..model, completion: Some(menu.shifted(delta)) })
      } else {
        (@cmd.none, model)
      }
    CompletionDismiss => (@cmd.none, { ..model, completion: None })
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
    OpenSetup => (@cmd.none, { ..model, setup_open: true, setup_api_key: "" })
    CloseSetup =>
      // The popup cannot be dismissed while the configured endpoint is
      // unusable — there would be nothing the composer could do.
      if model.api_ready() {
        (@cmd.none, { ..model, setup_open: false, setup_api_key: "" })
      } else {
        (@cmd.none, model)
      }
    SaveApiKey => {
      let api_key = model.setup_api_key.trim().to_owned()
      if api_key.is_empty() {
        (@cmd.none, model)
      } else {
        match model.api_provider {
          Deepseek => {
            let next = { ..model, api_key, setup_api_key: "" }
            (save_api_key(api_key), { ..next, setup_open: !next.api_ready() })
          }
          Custom => {
            let next = { ..model, custom_api_key: api_key, setup_api_key: "" }
            (
              save_custom_api_key(api_key),
              { ..next, setup_open: !next.api_ready() },
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
      let task = conv.task.trim().to_owned()
      if task.is_empty() || !model.bridge_ready || !model.api_ready() {
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
              ..model.replace_conversation({ ..conv, pending_steers, task: "" }),
              transcript_pinned: true,
              completion: None,
            },
          )
        } else {
          (@cmd.none, model)
        }
      } else {
        let next = conv.append_item(User, task)
        let next = {
          ..next,
          task: "",
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
      // running in the background and stays one sidebar click away.
      (rotate_session(dispatch), { ..model, loading_session: "" })
    SessionRotated(session_id) =>
      (
        @cmd.none,
        {
          ..model.activate(session_id),
          screen: Chat,
          transcript_pinned: true,
          loading_session: "",
          completion: None,
        },
      )
    SessionsLoaded(items) =>
      (@cmd.none, { ..model, sessions: items, sessions_error: "" })
    SessionsFailed(message) => (@cmd.none, { ..model, sessions_error: message })
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
      } else if model.find_conversation(session_id) is Some(_) {
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
          },
        )
      } else {
        (
          open_session(dispatch, session_id),
          { ..model, screen: Chat, loading_session: session_id },
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
          scroll_transcript_after_render(),
          {
            ..model
            .replace_conversation({
              ..empty_conversation(session_id),
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
        // Sync the global model/step settings only when this start belongs to
        // the conversation on screen. A slow background start (the user switched
        // chats mid-spawn) must not overwrite settings the user has since
        // changed for the now-active conversation.
        if session == model.active_session {
          (
            @cmd.none,
            { ..updated, selected_model, max_steps: max_steps.to_string() },
          )
        } else {
          (@cmd.none, updated)
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
    Failed(session~, message~) =>
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
      } else if model.loading_session != session {
        (@cmd.none, model)
      } else {
        // The conversation never came to exist (a session load failed before
        // creating one): surface the message where the user is looking, but
        // leave that conversation's own run state alone.
        let conv = model.active().append_item(Assistant(true), message)
        let conv = if conv.running { conv } else { { ..conv, status: Failed } }
        (
          @cmd.batch([
            scroll_transcript_after_render(),
            fetch_sessions(dispatch),
          ]),
          { ..model.replace_conversation(conv), loading_session: "" },
        )
      }
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
          status: Finished(status),
        }
        let answer = answer.trim().to_owned()
        // The finished run just appended to the durable store, so the
        // sidebar list (and this conversation's title) may have changed.
        if should_append_answer(conv, answer) {
          (
            @cmd.batch([
              scroll_if_active(model, conv.session_id),
              fetch_sessions(dispatch),
            ]),
            model.replace_conversation(
              base.append_item(Assistant(false), answer),
            ),
          )
        } else {
          (fetch_sessions(dispatch), model.replace_conversation(base))
        }
      } else {
        (@cmd.none, model)
      }
  }
}
