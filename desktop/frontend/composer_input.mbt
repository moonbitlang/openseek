///|
/// Project the root application state into the composer's fixed package
/// boundary. This method is the only place where composer availability and
/// surrounding root-owned presentation are derived from `Model`.
fn Model::composer_input(
  self : Model,
  dispatch : @cmd.Emit[Msg],
) -> @composer.Input {
  let conv = self.active()
  let checkout = self.checkout_placement(conv)
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
  let checkout_ready = checkout is Some(@interop.WorkspaceRoot) ||
    checkout is Some(@interop.Worktree(_))
  let root_ready = self.bridge_state() is Connected(..) &&
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
  let status : Array[@html.Html] = [conv.engine_model.composer_select(dispatch)]
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
    Some(@interop.MissingWorktree(name~)) =>
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
  let file_index : @composer.FileIndex = match self.file_panel.index {
    @fileeditor.IndexEmpty =>
      @composer.FileIndexEmpty(epoch=self.file_panel.request_epoch)
    @fileeditor.IndexLoading(_) =>
      @composer.FileIndexLoading(epoch=self.file_panel.request_epoch)
    @fileeditor.IndexReady(truncated~, ..) =>
      @composer.FileIndexReady(epoch=self.file_panel.request_epoch, truncated~)
    @fileeditor.IndexFailed =>
      @composer.FileIndexFailed(epoch=self.file_panel.request_epoch)
  }
  {
    identity,
    draft: { task: conv.task, mentions: conv.mentions },
    goal: {
      draft: conv.goal_edit.map(edit => edit.draft),
      standing: conv.goal,
      pending,
    },
    root: self.conversation_root(conv),
    installed_skills: self.installed_skills,
    context_generation: self.composer_context_generation,
    submission_sequence: self.submission_sequence,
    replacements: self.composer_entry_replacements,
    retirements: self.composer_entry_retirements,
    file_candidates: self.file_search().candidates,
    open_files: quick_open_open_files(self),
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
        "Ask OpenSeek to inspect, edit, or explain this workspace."
      },
      primary_action,
    },
  }
}
