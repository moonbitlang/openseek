///|
/// Project the root application state into the composer's fixed package
/// boundary. This method is the only place where composer availability and
/// surrounding root-owned presentation are derived from `Model`.
///
/// The component stays mounted while onboarding is on screen — the root view
/// simply does not place it — so a model with no conversation projects a
/// dormant composer rather than inventing one to draft against.
fn Model::composer_input(
  self : Model,
  dispatch : @cmd.Emit[Msg],
) -> @composer.Input {
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
  let transcript_ready = conv.sync is Synced &&
    !conv.has_unresolved_run_tail_notice()
  let checkout_ready = checkout is Some(value) && value.is_ready()
  let root_ready = self.bridge_state() is Connected &&
    self.api_ready() &&
    transcript_ready &&
    checkout_ready
  let primary_action : @composer.PrimaryAction = if conv.is_running() {
    @composer.Running(
      steer_available=root_ready &&
        conv.run_durable_floor is Some(_) &&
        conv.run is Open(stage~, ..) &&
        !(stage is Cancelling),
      can_stop=can_stop(conv),
    )
  } else {
    @composer.Send(available=root_ready && conv.compaction is NotCompacting)
  }
  let status : Array[@html.Html] = [self.openseek_model_chip(dispatch, conv)]
  if git_chip(dispatch, self, conv) is Some(chip) {
    status.push(chip)
  }
  if worktree_mode_chip(dispatch, self, conv) is Some(chip) {
    status.push(chip)
  }
  // The composer owns the stable container and goal row. These root-owned
  // panels are supplied as one ordered view slot so their internal commands
  // stay in the application package.
  let context : Array[@html.Html] = [
    connection_banner(self),
    @plan.panel(conv.visible_items()),
  ]
  // The BYOK reminder: readiness is otherwise folded silently into Send's
  // availability, and the top-bar status is owned by the run state — without
  // this notice a dismissed setup modal leaves a greyed Send with no
  // explanation and no way back to the form.
  if self.api_setup_banner_visible() {
    let text = if self.settings_status() is SetupRequired {
      "No endpoint URL configured — Send is disabled."
    } else {
      "No DeepSeek API key configured — Send is disabled."
    }
    context.push(
      @html.div(class="composer-notice", [
        @html.span(class="composer-notice-text", text),
        @html.button(
          class="composer-notice-btn",
          type_="button",
          title="Configure the API endpoint",
          on_click=dispatch(OpenApiSetup),
          "Set up",
        ),
      ]),
    )
  }
  if !conv.pending_steers().is_empty() {
    context.push(pending_steers_panel(conv))
  }
  match conv.compaction {
    Requested | Compacting =>
      context.push(
        @html.div(class="composer-notice", [
          @html.span(class="composer-notice-icon", icon(icon_fold)),
          @html.span(class="composer-notice-text", "Compacting context…"),
        ]),
      )
    Queued =>
      context.push(
        @html.div(class="composer-notice", [
          @html.span(class="composer-notice-icon", icon(icon_fold)),
          @html.span(
            class="composer-notice-text",
            "Compaction queued — starts when the current turn ends",
          ),
        ]),
      )
    NotCompacting => ()
  }
  match checkout {
    None =>
      context.push(
        @html.div(class="composer-notice", [
          @html.span(
            class="composer-notice-text",
            "Waiting for workspace placement…",
          ),
          @html.button(
            class="composer-notice-btn",
            type_="button",
            title="Request this workspace's worktree list again",
            on_click=dispatch(RetryWorktreePlacement),
            "Retry",
          ),
        ]),
      )
    Some(@interop.MissingWorktree(name~, ..)) =>
      context.push(
        @composer.MissingWorktreeNotice::{
          name,
          conversation_noun: "chat",
          rebuild: dispatch(RepairWorktree),
          archive: dispatch(ArchiveSession(conv.device, conv.session_id)),
        }.render(),
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
    draft: { task: conv.task, mentions: conv.mentions },
    // Sub-run lanes stay in the transcript tail: they are activity *inside*
    // this turn, and drawing both in one place put the outer run on the same
    // footing as the children it spawned.
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
fn Model::codex_composer_input(
  self : Model,
  dispatch : @cmd.Emit[Msg],
) -> @composer.Input {
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
  self.codex.composer_input(
    dispatch.map(msg => Codex(channel=self.focused, msg)),
    {
      channel: self.focused,
      // The chip is root-built with the root's own dispatch: a cross-agent
      // pick on a composing draft leaves the Codex package entirely.
      model_chip: self.codex_model_chip(dispatch),
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
    },
  )
}

///|
/// The composer with nothing to compose in: no draft, no goal, no checkout,
/// and no way to send. Every action it could still emit carries the owner
/// identity below, which resolves to no conversation and is dropped.
fn Model::dormant_composer_input(self : Model) -> @composer.Input {
  {
    identity: {
      owner: { channel: self.focused, session: self.active_session },
      archive_generation: self.composer_entry_retirements.length(),
    },
    draft: { task: "", mentions: [] },
    run: None,
    goal: { draft: None, standing: None, pending: None },
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
