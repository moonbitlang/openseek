///|
/// Project the root application state into the composer's fixed package
/// boundary. This method is the only place where composer availability and
/// surrounding root-owned presentation are derived from `Model`.
///
/// The component stays mounted while onboarding is on screen — the root view
/// simply does not place it — so a model with no conversation projects a
/// dormant composer rather than inventing one to draft against.
fn Model::composer_input(self : Model) -> @composer.Input {
  guard self.active_conversation() is Some(conv) else {
    return self.dormant_composer_input()
  }
  let checkout = self.conversation_placement(conv)
  let owner : @interop.ConversationKey = {
    channel: self.focused,
    session: conv.session_id,
  }
  let identity : @composer.Identity = {
    owner,
    archive_generation: self.composer_entry_retirements.length(),
  }
  let checkout_ready = checkout is Some(value) && value.is_ready()
  // Sending needs a live engine and a workspace to run in — nothing about the
  // transcript. The record is what the turn writes, not a precondition for
  // starting one, so a reload in flight or a failed one never gates Send.
  let root_ready = self.bridge_state() is Connected &&
    self.api_ready() &&
    checkout_ready
  let primary_action : @composer.PrimaryAction = if conv.is_running() {
    @composer.Running(
      steer_available=root_ready &&
        conv.run is Open(stage~, ..) &&
        !(stage is Cancelling(..)),
      can_stop=can_stop(conv),
    )
  } else {
    @composer.Send(available=root_ready && conv.compaction is NotCompacting)
  }
  let status : Array[@composer.StatusComponent] = [
    @composer.ModelStatus(self.openseek_model_chip(conv)),
  ]
  if self.openseek_reasoning_chip(conv) is Some(control) {
    status.push(@composer.ReasoningStatus(control))
  }
  if conv.git_presentation() is Some(presentation) {
    status.push(
      @composer.GitStatus({ presentation, open: self.git_details_open, }),
    )
  }
  if self.worktree_control(conv) is Some(control) {
    status.push(@composer.WorktreeStatus(control))
  }
  // The composer owns the stable container and every context view. The root
  // projects only typed state, so no caller-owned DOM or command can alter
  // the component's child ordering.
  let context : Array[@composer.ContextComponent] = [
    @composer.ConnectionBanner(
      device_name=if self.console is Some(_) &&
        self.bridge_state() is BridgeLost(_) {
        Some(self.focused_device_name())
      } else {
        None
      },
    ),
    // Sub-runs dock here rather than at the transcript's tail: a child turn's
    // progress is live run status that no durable event describes, and the
    // scroller shows only what the record can place. The plan is the mirror
    // image: it is durable, so it stays in the transcript.
    @composer.SubrunDock(lanes=conv.visible_subruns()),
  ]
  // The BYOK reminder: readiness is otherwise folded silently into Send's
  // availability, and the top-bar status is owned by the run state — without
  // this notice a dismissed setup modal leaves a greyed Send with no
  // explanation and no way back to the form.
  if self.api_setup_banner_visible() {
    let text = if self.settings_status() is SetupRequired {
      "No endpoint URL configured — Send is disabled."
    } else if self.api_provider is Glm {
      "No GLM API key configured — Send is disabled."
    } else {
      "No DeepSeek API key configured — Send is disabled."
    }
    context.push(@composer.ApiSetupNotice(text~))
  }
  // First among the notices, because it is the only one the turn is waiting
  // on: everything else here is advice, and this is a question with a tool
  // blocked behind it.
  if conv.pending_approval is Some(pending) {
    context.push(
      @composer.ApprovalRequest({
        tool_name: pending.tool_name,
        detail: pending.detail,
        body: pending.body,
        answered: pending.answered,
      }),
    )
  }
  // Advice about the draft this composer is now holding, so it belongs to the
  // composer. It stands until the user acts on it: whether the archived record
  // got the prompt is a question only that record answers, and a toast would
  // be gone before they could go and look.
  if conv.archived_pending_input {
    context.push(@composer.ArchivedInputNotice(text=ArchivedPendingInputNotice))
  }
  if !conv.pending_steers.is_empty() {
    context.push(
      @composer.PendingSteerPanel(
        items=conv.pending_steers.map(steer => user_display_text(steer.content)),
      ),
    )
  }
  match conv.compaction {
    Requested | Compacting =>
      context.push(@composer.CompactionNotice(queued=false))
    Queued => context.push(@composer.CompactionNotice(queued=true))
    NotCompacting => ()
  }
  match checkout {
    None => context.push(@composer.WorktreePlacementNotice)
    Some(@interop.MissingWorktree(name~, ..)) =>
      context.push(
        @composer.MissingWorktreeNoticeComponent({
          name,
          conversation_noun: "chat",
        }),
      )
    Some(_) => ()
  }
  let pending : @composer.GoalPending? = conv.goal_pending.map(command => {
    match command.request {
      Setting(text) => @composer.GoalSetting(text)
      Clearing => @composer.GoalClearing
    }
  })
  let file_index = self.composer_file_index()
  {
    identity,
    draft: { task: conv.task, mentions: conv.mentions, },
    // The outer run heartbeat and child-run lanes are both typed live status,
    // rendered by the composer above the draft rather than persisted into the
    // transcript.
    run: conv.run_heartbeat(),
    goal: {
      draft: conv.goal_edit.map(edit => edit.draft),
      standing: conv.goal,
      pending,
    },
    slash_commands: [
      {
        label: "/compact",
        detail: "Summarize and shrink this conversation's context",
        command: "compact",
      },
      {
        label: "/goal",
        detail: "Set or clear this conversation's standing goal",
        command: "goal",
      },
    ],
    root: self.conversation_root(conv),
    installed_skills: self.installed_skills,
    context_generation: self.composer_context_generation,
    submission_sequence: self.submission_sequence,
    replacements: self.composer_entry_replacements,
    retirements: self.composer_entry_retirements,
    file_candidates: self.file_search().candidates,
    open_files: self.live_editor_files(),
    active_file: @dock.active_file(self.dock),
    file_index,
    presentation: {
      context,
      status,
      placeholder: if conv.goal_edit is Some(_) {
        "Describe the standing goal for this conversation — Enter sets it, Esc cancels."
      } else if conv.is_running() {
        "Steer the running task — your message joins it at the next step."
      } else {
        "Ask SeekMoon to inspect, edit, or explain this workspace."
      },
      disabled: false,
      primary_action,
    },
  }
}

///|
/// The file-index lifecycle is a root-owned fact shared by every composer
/// instance. Each component keeps its own draft and completion state while
/// observing this one authoritative index epoch.
fn Model::composer_file_index(self : Model) -> @composer.FileIndex {
  match self.file_panel.index {
    @fileeditor.IndexEmpty =>
      @composer.FileIndexEmpty(epoch=self.file_panel.request_epoch)
    @fileeditor.IndexLoading(_) =>
      @composer.FileIndexLoading(epoch=self.file_panel.request_epoch)
    @fileeditor.IndexReady(truncated~, ..) =>
      @composer.FileIndexReady(epoch=self.file_panel.request_epoch, truncated~)
    @fileeditor.IndexFailed =>
      @composer.FileIndexFailed(epoch=self.file_panel.request_epoch)
  }
}

///|
/// Project the selected Codex task into a second instance of the same
/// package-owned composer component used by OpenSeek conversations.
fn Model::codex_composer_input(self : Model) -> @composer.Input {
  // The two component instances stay mounted across page switches. Supply
  // workspace-file facts only while Codex owns the visible, resolved checkout
  // so its hidden draft can never offer paths indexed for an OpenSeek chat.
  let workspace_ready = self.screen is Codex &&
    self.codex.active_placement(self.focused) is Some(placement) &&
    placement.checkout_root() is Some(_)
  let search = if workspace_ready {
    self.file_search()
  } else {
    @files.Search([], [], None)
  }
  self.codex.composer_input({
    channel: self.focused,
    // The model state is root-built because a cross-agent pick on a
    // composing draft leaves the Codex package entirely. The resulting
    // action still returns through the shared composer's typed route.
    model_control: self.codex_model_chip(),
    reasoning_control: self.codex.reasoning_effort_chip(
      self.select_menu == Some(CodexReasoningMenu),
    ),
    file_candidates: search.candidates,
    open_files: if workspace_ready {
      self.live_editor_files()
    } else {
      []
    },
    active_file: if workspace_ready {
      @dock.active_file(self.dock)
    } else {
      None
    },
    file_index: if workspace_ready {
      self.composer_file_index()
    } else {
      @composer.FileIndexEmpty(epoch=self.file_panel.request_epoch)
    },
  })
}

///|
/// The composer with nothing to compose in: no draft, no goal, no checkout,
/// and no way to send. Every action it could still emit carries the owner
/// identity below, which resolves to no conversation and is dropped.
fn Model::dormant_composer_input(self : Model) -> @composer.Input {
  {
    identity: {
      owner: { channel: self.focused, session: self.active_session, },
      archive_generation: self.composer_entry_retirements.length(),
    },
    draft: { task: "", mentions: [], },
    run: None,
    goal: { draft: None, standing: None, pending: None, },
    slash_commands: [],
    root: None,
    installed_skills: self.installed_skills,
    context_generation: self.composer_context_generation,
    submission_sequence: self.submission_sequence,
    replacements: self.composer_entry_replacements,
    retirements: self.composer_entry_retirements,
    file_candidates: [],
    open_files: [],
    active_file: None,
    file_index: self.composer_file_index(),
    presentation: {
      context: [],
      status: [],
      placeholder: "",
      disabled: true,
      primary_action: @composer.Send(available=false),
    },
  }
}
