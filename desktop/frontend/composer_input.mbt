///|
/// One stable composer slot shared by both conversation providers.
fn Model::connection_banner(self : Model) -> @composer.ContextComponent {
  @composer.ConnectionBanner(
    device_name=if !self.is_desktop &&
      self.focused_device() is Some(device) &&
      device.reconnect_failures > 0 {
      Some(self.focused_device_name())
    } else {
      None
    },
  )
}

///|
/// Project the root application state into the composer's fixed package
/// boundary. This method is the only place where composer availability and
/// surrounding root-owned presentation are derived from `Model`.
///
/// The component stays mounted while onboarding is on screen — the root view
/// simply does not place it — so a model with no conversation projects a
/// dormant composer rather than inventing one to draft against.
fn Model::composer_input(self : Model) -> @composer.Input {
  if self.cloud_composer_input() is Some(input) {
    return input
  }
  guard self.active_conversation() is Some(conv) else {
    return self.dormant_composer_input()
  }
  let checkout = self.conversation_placement(conv)
  let owner : @interop.ConversationKey = {
    channel: self.focused,
    session: conv.session_id,
  }
  let identity : @composer.Identity = {
    owner: @interop.Host(owner),
    archive_generation: self.composer_entry_changes.length(),
  }
  let checkout_ready = checkout is Some(value) && value.is_ready()
  let queue_save_pending = conv.saving_queue_edit()
  let semantic_selection_pending = conv.pending_semantic_submission is Some(_)
  // Sending needs a live engine and a workspace to run in — nothing about the
  // transcript. The record is what the turn writes, not a precondition for
  // starting one, so a reload in flight or a failed one never gates Send.
  let root_ready = self.bridge_state() is Connected &&
    self.api_ready() &&
    checkout_ready
  let primary_action : @composer.PrimaryAction = if conv.is_running() {
    @composer.Running(
      queue_available=true,
      steer_available=root_ready &&
        !semantic_selection_pending &&
        conv.run is Open(stage~, ..) &&
        !(stage is Cancelling),
      can_stop=can_stop(conv),
      submit=if conv.queue_edit is Some(_) {
        @composer.SaveQueue
      } else if self.followup_behavior is FollowupQueue {
        @composer.Queue
      } else {
        @composer.Steer
      },
    )
  } else {
    @composer.Send(
      available=root_ready &&
        !semantic_selection_pending &&
        !queue_save_pending &&
        conv.controls.compaction is NotCompacting,
    )
  }
  let status : Array[@composer.StatusComponent] = [
    @composer.ModelStatus(self.openseek_model_chip(conv)),
  ]
  if self.openseek_reasoning_chip(conv) is Some(control) {
    status.push(@composer.ReasoningStatus(control))
  }
  status.push(
    @composer.ApprovalStatus({
      on: self.approval_for(conv.device, conv.session_id) is ApprovalReview,
      enabled: !conv.is_running(),
    }),
  )
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
    self.connection_banner(),
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
      shell_text(self.locale, NoEndpoint)
    } else if self.api_provider is Glm {
      shell_text(self.locale, NoGlmKey)
    } else if self.api_provider is OpenRouter {
      shell_text(self.locale, NoOpenRouterKey)
    } else {
      shell_text(self.locale, NoDeepSeekKey)
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
        target_label: if pending.tool_name == "session.send" &&
          self.focused_device() is Some(device) &&
          device.sessions.iter().find_first(item => item.id == pending.detail)
          is Some(item) {
          item.title
        } else {
          None
        },
        body: pending.body,
        answered: pending.answered,
      }),
    )
  }
  let steering = conv.pending_steers.filter(input => {
    input.behavior is FollowupSteer
  })
  if !steering.is_empty() {
    context.push(
      @composer.PendingSteerPanel(
        items=steering.map(steer => {
          id: steer.submission_id,
          content: user_display_text(steer.content) +
          (if steer.images.is_empty() { "" } else { " [Image]" }),
        }),
      ),
    )
  }
  let queued_items : Array[@composer.QueuedInput] = []
  let interactive = conv.run is Open(stage~, ..) && !(stage is Cancelling)
  for item in conv.queued_inputs {
    if steering.any(input => input.submission_id == item.id) {
      continue
    }
    let queueing = conv.pending_steers.any(input => {
      input.behavior is FollowupQueue && input.submission_id == item.id
    })
    queued_items.push({
      id: item.id,
      content: user_display_text(item.content) +
      (if item.images.is_empty() { "" } else { " [Image]" }),
      state: if queueing {
        @composer.Queueing
      } else {
        @composer.Queued(
          editing=conv.queue_edit is Some(edit) && edit.id() == item.id,
          interactive~,
          steer_available=true,
        )
      },
    })
  }
  if !queued_items.is_empty() {
    context.push(
      @composer.QueuedInputPanel(
        items=queued_items,
        enabled=!queue_save_pending,
      ),
    )
  }
  if !conv.shell_commands.is_empty() {
    context.push(
      @composer.ShellCommandsRunning(
        commands=conv.shell_commands.map(pending => pending.command),
      ),
    )
  }
  match conv.controls.compaction {
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
  let file_index = self.composer_file_index()
  {
    identity,
    draft: { images: conv.images, task: conv.task, mentions: conv.mentions, },
    // The outer run heartbeat and child-run lanes are both typed live status,
    // rendered by the composer above the draft rather than persisted into the
    // transcript.
    run: conv.run_heartbeat(),
    goal: conv.controls.input(),
    slash_commands: self.openseek_commands(),
    // Editing a queued message rewrites that message; it never runs one.
    shell_available: conv.queue_edit is None,
    history: conv.sent_prompts(shell=conv.queue_edit is None),
    root: self.conversation_root(conv),
    cloud_access: None,
    staged_attachments: [],
    installed_skills: self.installed_skills,
    context_generation: self.composer_context_generation,
    turn_id: match conv.run {
      Open(run_id~, ..) => Some(run_id)
      _ => None
    },
    submission_sequence: self.submission_sequence,
    entry_changes: self.composer_entry_changes,
    prediction: conv.prediction,
    prediction_source: if self.screen is Chat &&
      root_ready &&
      conv.run is NoRun(ended~) &&
      conv.controls.compaction is NotCompacting &&
      conv.queued_inputs.is_empty() &&
      conv.pending_steers.is_empty() &&
      conv.shell_commands.is_empty() &&
      conv.controls.edit is None &&
      conv.queue_edit is None &&
      conv.watermark > 0 {
      @engine_session.prediction_source(
        conv.prediction,
        conv.watermark,
        completed=ended is Some(RunFinished(Completed)),
      )
    } else {
      None
    },
    file_candidates: self.file_search().candidates,
    open_files: self.live_editor_files(),
    active_file: self.active_workspace_file(),
    file_index,
    presentation: {
      images_enabled: conv.engine_model is Deepseek(V4Flash) &&
      self.api_provider is (Deepseek | Custom),
      context,
      status,
      placeholder: if conv.controls.edit is Some(_) {
        shell_text(self.locale, GoalPlaceholder)
      } else if conv.queue_edit is Some(_) {
        shell_text(self.locale, EditQueuePlaceholder)
      } else if conv.is_running() {
        if self.followup_behavior is FollowupQueue {
          shell_text(self.locale, QueuePlaceholder)
        } else {
          shell_text(self.locale, SteerPlaceholder)
        }
      } else {
        shell_text(self.locale, AskPlaceholder)
      },
      // Freeze submissions while their snapshot or queue mutation is in
      // flight, so a later edit cannot be cleared by an earlier response.
      disabled: semantic_selection_pending || queue_save_pending,
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
  let input = self.codex.composer_input(locale=self.locale, {
    channel: self.focused,
    // The model state is root-built because a cross-agent pick on a
    // composing draft leaves the Codex package entirely. The resulting
    // action still returns through the shared composer's typed route.
    model_control: self.codex_model_chip(),
    reasoning_control: self.codex.reasoning_effort_chip(
      locale=self.locale,
      self.select_menu is Some(CodexReasoningMenu),
    ),
    file_candidates: search.candidates,
    open_files: if workspace_ready {
      self.live_editor_files()
    } else {
      []
    },
    active_file: if workspace_ready {
      self.active_workspace_file()
    } else {
      None
    },
    file_index: if workspace_ready {
      self.composer_file_index()
    } else {
      @composer.FileIndexEmpty(epoch=self.file_panel.request_epoch)
    },
  })
  let input = {
    ..input,
    presentation: {
      ..input.presentation,
      context: [self.connection_banner(), ..input.presentation.context],
      primary_action: if self.bridge_state() is Connected {
        input.presentation.primary_action
      } else {
        match input.presentation.primary_action {
          Send(..) => @composer.Send(available=false)
          SaveQueuedInput(..) => @composer.SaveQueuedInput(available=false)
          Running(submit~, ..) =>
            @composer.Running(
              submit~,
              steer_available=false,
              can_stop=false,
              queue_available=false,
            )
        }
      },
    },
  }
  if self.codex_project_adoption_pending() {
    {
      ..input,
      presentation: {
        ..input.presentation,
        primary_action: @composer.Send(available=false),
      },
    }
  } else {
    input
  }
}

///|
/// The composer with nothing to compose in: no draft, no goal, no checkout,
/// and no way to send. Every action it could still emit carries the owner
/// identity below, which resolves to no conversation and is dropped.
fn Model::dormant_composer_input(self : Model) -> @composer.Input {
  {
    identity: {
      owner: @interop.Host({
        channel: self.focused,
        session: self.active_session,
      }),
      archive_generation: self.composer_entry_changes.length(),
    },
    draft: { images: [], task: "", mentions: [], },
    run: None,
    goal: { draft: None, standing: None, pending: None, },
    slash_commands: [],
    shell_available: false,
    history: [],
    root: None,
    cloud_access: None,
    staged_attachments: [],
    installed_skills: self.installed_skills,
    context_generation: self.composer_context_generation,
    turn_id: None,
    submission_sequence: self.submission_sequence,
    entry_changes: self.composer_entry_changes,
    prediction_source: None,
    prediction: None,
    file_candidates: [],
    open_files: [],
    active_file: None,
    file_index: self.composer_file_index(),
    presentation: {
      images_enabled: false,
      context: [],
      status: [],
      placeholder: "",
      disabled: true,
      primary_action: @composer.Send(available=false),
    },
  }
}

///|
/// The prompts the user sent in this conversation, oldest first, in the form
/// the composer shows them again: typed text with chip markers, no envelopes.
/// A `!` command comes back as the `!command` draft that ran it, but only where
/// the composer runs those (`shell`), and a prompt that itself starts with `!`
/// is left out: recalled without the chips or images it may have carried, it
/// would read as a shell command. A prompt repeating the one before it is left
/// out too.
fn Conversation::sent_prompts(
  self : Conversation,
  shell~ : Bool,
) -> Array[String] {
  let prompts : Array[String] = []
  for item in self.messages {
    guard item.kind is User(content~) else { continue }
    let text = content.text()
    let shown = if @command_context.parse(text) is Some(result) {
      if !shell {
        continue
      }
      "!\{result.command}"
    } else {
      let shown = user_display_text(text)
      if shown.has_prefix("!") {
        continue
      }
      shown
    }
    if !shown.is_blank() && prompts.last() != Some(shown) {
      prompts.push(shown)
    }
  }
  prompts
}

///|
/// What `/ultrareview [focus]` sends. It ends on `Focus:`, which the text typed
/// after the command completes.
const UltrareviewPrompt : String =
  #|Review the changes on this branch with the bundled review swarm.
  #|
  #|1. Use git to find the merge base of HEAD with the default branch.
  #|2. Call the `mbtx` tool with `filename: "@builtin/review.mbtx"` and `args: ["--swarm", "--sha", <merge base>, "--", <criteria>]`. The criteria are the Focus text below or, when it is empty, "The changes since that base are correct, well-structured and tested."
  #|3. Wait for the job with `job_wait` and read it with `job_output`; a job that failed on a blocker still has its findings there. Report the merged findings: verified ones first, then unverified ones, then the refuted list.
  #|
  #|Focus:

///|
/// What `/simplify [focus]` sends. It ends on `Focus:`, which the text typed
/// after the command completes.
const SimplifyPrompt : String =
  #|Sweep this repository for safe simplifications with the bundled simplify workflow.
  #|
  #|1. Call the `mbtx` tool with `filename: "@builtin/simplify.mbtx"` and `args: ["--", <focus>]`, where the focus is the Focus text below; when it is empty, pass no args.
  #|2. Wait for the job with `job_wait` and read it with `job_output`. If the sweep stops before starting (not at the repository root, uncommitted changes, HEAD not on the default branch, gh not signed in), report why and stop: do not commit, stash or push anything to get past it.
  #|3. Report the pull requests it opened, the changes the reviewers rejected, and the packages it skipped and why.
  #|
  #|Focus:

///|
fn Model::openseek_commands(self : Model) -> Array[@composer.SlashCommand] {
  [
    {
      label: "/compact",
      detail: shell_text(self.locale, CompactContext),
      command: "compact",
      prompt: None,
    },
    {
      label: "/goal",
      detail: shell_text(self.locale, SetGoal),
      command: "goal",
      prompt: None,
    },
    {
      label: "/ultrareview",
      detail: shell_text(self.locale, UltraReview),
      command: "ultrareview",
      prompt: Some(UltrareviewPrompt),
    },
    {
      label: "/simplify",
      detail: shell_text(self.locale, SimplifyProject),
      command: "simplify",
      prompt: Some(SimplifyPrompt),
    },
  ]
}
