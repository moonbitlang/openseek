// Codex supplies app-server-specific skills, commands, and availability to
// the one shared composer component. Draft editing, completion state, file and
// symbol lookup, keyboard handling, and mention chips stay inside @composer.

///|
priv struct CodexSkill {
  name : String
  description : String
  path : String
} derive(Eq)

///|
priv enum CodexSkillCatalog {
  CodexSkillsEmpty
  CodexSkillsLoading(String)
  CodexSkillsReady(String, Array[CodexSkill])
  CodexSkillsFailed(String)
} derive(Eq)

///|
fn CodexSkill::decode_list(value : Json, cwd : String) -> Array[CodexSkill]? {
  guard value is Object(fields) && fields.get("data") is Some(Array(entries)) else {
    return None
  }
  for index, entry in entries {
    guard entry is Object(entry_fields) &&
      @jsonx.json_text(entry_fields, "cwd") is Some(entry_cwd) &&
      (entry_cwd == cwd || (entries.length() == 1 && index == 0)) &&
      entry_fields.get("skills") is Some(Array(skills)) else {
      continue
    }
    let decoded : Array[CodexSkill] = []
    for skill in skills {
      guard skill is Object(skill_fields) &&
        @jsonx.json_bool(skill_fields, "enabled").unwrap_or(false) &&
        @jsonx.json_text(skill_fields, "name") is Some(name) &&
        @jsonx.json_text(skill_fields, "description") is Some(description) &&
        @jsonx.json_text(skill_fields, "path") is Some(path) else {
        continue
      }
      decoded.push({ name, description, path })
    }
    return Some(decoded)
  }
  None
}

///|
priv struct CodexContext {
  thread_id : String
  cwd : String
}

///|
fn State::active_context(self : State) -> CodexContext? {
  match self.selection {
    CodexDraftTask(draft) =>
      match draft.project_root {
        Some(project_root) => {
          let cwd = project_root.trim().to_owned()
          if cwd.is_empty() {
            None
          } else {
            Some({ thread_id: draft.id, cwd })
          }
        }
        None => None
      }
    CodexStoredTask(thread) => {
      guard !self.has_missing_worktree() && thread.cwd is Some(raw_cwd) else {
        return None
      }
      let cwd = raw_cwd.trim().to_owned()
      if cwd.is_empty() {
        None
      } else {
        Some({ thread_id: thread.id, cwd })
      }
    }
    CodexNoTask => None
  }
}

///|
fn State::installed_codex_skills(
  self : State,
) -> Array[@transcript.InstalledSkillItem] {
  guard self.active_context() is Some(context) &&
    self.skills is CodexSkillsReady(cwd, skills) &&
    cwd == context.cwd else {
    return []
  }
  skills.map(skill => {
    // `id` retains app-server's exact SKILL.md path. The component only needs
    // name/description for completion; turn construction resolves the path
    // from this same catalog after the user submits.
    id: skill.path,
    name: skill.name,
    description: skill.description,
    source: "codex",
  })
}

///|
/// A prompt may consist entirely of structured mentions. Keep this predicate
/// next to the shared composer projection so send and draft-thread creation
/// use the same definition of an empty Codex prompt.
fn State::input_empty(self : State) -> Bool {
  self.draft.is_blank() && self.mentions.is_empty()
}

///|
/// Interpret a submitted shared-composer draft through Codex writer ownership
/// and thread creation. Input mechanics stay component-local; this method
/// begins only the app-server operation selected by the canonical task state.
fn State::submit_composer(
  self : State,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
) -> (@cmd.Cmd, State) {
  if self.input_empty() ||
    !self.has_active() ||
    self.loading ||
    !self.can_prompt() {
    return (@cmd.none, self)
  }
  if self.active_draft() is Some(draft) {
    (
      self.start_draft_thread(dispatch, channel),
      self.begin_foreground(CodexDraftThreadReply(draft.id)),
    )
  } else if self.write_access is CodexWritable {
    let next = self.with_pending_turn_delivery()
    guard next.active_thread() is Some(active) else { return (@cmd.none, self) }
    let next = next.begin_foreground(CodexTurnReply(active.id))
    (next.send(dispatch, channel), next)
  } else {
    let next = self.with_pending_turn_delivery()
    guard next.active_thread() is Some(active) else { return (@cmd.none, self) }
    (
      next.resume_for_send(dispatch, channel),
      next.begin_foreground(CodexWriterReply(active.id)),
    )
  }
}

///|
fn State::with_skills(
  self : State,
  cwd : String,
  skills : Array[CodexSkill],
) -> State {
  { ..self, skills: CodexSkillsReady(cwd, skills) }
}

///|
fn State::with_skill_failure(self : State, cwd : String) -> State {
  let skills = match self.skills {
    CodexSkillsReady(current, _) if current == cwd => self.skills
    _ => CodexSkillsFailed(cwd)
  }
  { ..self, skills, }
}

///|
fn State::loading_context(self : State, force_skills : Bool) -> State {
  guard self.active_context() is Some(context) else { return self }
  let skills = match self.skills {
    CodexSkillsReady(cwd, _) if cwd == context.cwd && !force_skills =>
      self.skills
    CodexSkillsLoading(cwd) if cwd == context.cwd => self.skills
    _ => CodexSkillsLoading(context.cwd)
  }
  { ..self, skills, }
}

///|
/// Root-owned file-index facts needed by the shared composer. Codex adds only
/// its channel identity; the component performs the same file and symbol
/// searches as OpenSeek and Ctrl+P.
pub(all) struct ComposerContext {
  channel : @interop.ChannelId
  file_candidates : Array[@pathx.Relative]
  open_files : Array[@pathx.Relative]
  active_file : @pathx.Relative?
  file_index : @composer.FileIndex
}

///|
fn State::composer_identity(
  self : State,
  channel : @interop.ChannelId,
) -> @composer.Identity {
  {
    owner: { channel, session: self.active_id().unwrap_or("codex.none") },
    archive_generation: 0,
  }
}

///|
/// Validate a component action against the task currently selected on the
/// Codex page. The Codex composer is a separate instance from OpenSeek's, but
/// delayed DOM actions still carry an exact thread id and cannot retarget a
/// newly selected task.
pub fn State::accepts_composer_identity(
  self : State,
  identity : @composer.Identity,
  channel : @interop.ChannelId,
) -> Bool {
  self.has_active() && self.composer_identity(channel) == identity
}

///|
/// Project Codex's canonical task state and app-server-specific controls into
/// the shared composer component. No editable or completion state is retained
/// in this view projection.
pub fn State::composer_input(
  self : State,
  dispatch : @cmd.Emit[Msg],
  context : ComposerContext,
) -> @composer.Input {
  let pending : Array[@html.Html] = []
  if self.active_thread() is Some(active) {
    for request in self.pending_requests {
      if request.thread_id == active.id {
        pending.push(request.view(dispatch))
      }
    }
  }
  let before : Array[@html.Html] = [@html.div(class="codex-pending", pending)]
  if self.active_thread() is Some(active) &&
    active.worktree is Some(worktree) &&
    !worktree.present {
    before.push(
      @composer.MissingWorktreeNotice::{
        name: worktree.name,
        conversation_noun: "task",
        rebuild: dispatch(RepairWorktree),
        archive: dispatch(ArchiveThread(active.id)),
      }.render(),
    )
  }
  let model_options : Array[@composer.ModelOption] = []
  for model in self.models {
    model_options.push({ value: model.id, label: model.label })
  }
  let status : Array[@html.Html] = [
    @composer.ModelSelect::{
      options: model_options,
      selected: self.selected_model,
      disabled: self.models.is_empty(),
      change: dispatch.map(value => ModelChanged(value)),
      title: "Codex model",
    }.render(),
  ]
  if self.worktree_launch_workspace(context.channel) is Some(_) &&
    self.active_draft() is Some(_) {
    status.push(
      @composer.WorktreeControl::{
        choice: self.placement,
        enabled: self.can_choose_worktree(),
        command: dispatch(ToggleWorktreeMode),
        content: icon(icon_worktree),
      }.render(),
    )
  }
  if self.git_status is Some(git) && git.presentation() is Some(presentation) {
    status.push(
      presentation.render(
        open=self.git_details_open,
        toggle=dispatch(ToggleGitDetails),
      ),
    )
  }
  let writable_turn = self.writable_turn_id()
  let read_only_turn = self.active_turn_is_read_only()
  let missing_worktree = self.has_missing_worktree()
  let can_edit = self.can_prompt() &&
    self.connection is CodexReady &&
    !read_only_turn &&
    !missing_worktree
  let primary_action = if writable_turn is Some(_) {
    @composer.Running(steer_available=can_edit, can_stop=true)
  } else {
    @composer.Send(available=!self.loading && can_edit && self.has_active())
  }
  {
    identity: self.composer_identity(context.channel),
    draft: { task: self.draft, mentions: self.mentions },
    goal: { draft: None, standing: None, pending: None },
    slash_commands: [
      {
        label: "/compact",
        detail: "Summarize and shrink this conversation's context",
        command: "compact",
      },
      {
        label: "/review",
        detail: "Review staged, unstaged, and untracked changes",
        command: "review",
      },
    ],
    root: self
    .active_placement(context.channel)
    .bind(placement => placement.checkout_root()),
    installed_skills: self.installed_codex_skills(),
    context_generation: 0,
    submission_sequence: self.submission_sequence,
    replacements: [],
    retirements: [],
    file_candidates: context.file_candidates,
    open_files: context.open_files,
    active_file: context.active_file,
    file_index: context.file_index,
    presentation: {
      context: before,
      status,
      placeholder: if writable_turn is Some(_) {
        "Steer the running task — your message joins it at the next step."
      } else if missing_worktree {
        "Rebuild this task's worktree before continuing."
      } else if read_only_turn {
        "This task is active in another Codex client."
      } else if self.is_active_elsewhere() {
        "Send to retry writer access for this task."
      } else {
        "Ask Codex to inspect, edit, or explain this workspace."
      },
      disabled: !can_edit,
      primary_action,
    },
  }
}

///|
fn State::run_composer_command(
  self : State,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  command : String,
) -> (@cmd.Cmd, State) {
  guard self.active_thread() is Some(_) else {
    return (@cmd.none, { ..self, notice: "" })
  }
  match command {
    "compact" =>
      (
        self.compact(dispatch, channel, self.draft),
        self.begin_foreground(CodexCompactReply(self.draft)),
      )
    "review" =>
      (
        self.review(dispatch, channel, self.draft),
        self.begin_foreground(CodexReviewReply(self.draft)),
      )
    _ => (@cmd.none, self)
  }
}

///|
/// Interpret only deliberate component operations. Keystrokes, completion
/// navigation, debounce, file lookup, and symbol lookup never leave the
/// shared component and therefore never enter Codex's transcript-sized State.
fn State::apply_composer_action(
  self : State,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  action : @composer.Action,
) -> (@cmd.Cmd, State) {
  let identity = match action {
    @composer.DraftSubmitted(identity~, ..)
    | @composer.DraftPresenceChanged(identity~, ..)
    | @composer.RootMentionRemoved(identity~, ..)
    | @composer.SlashCommand(identity~, ..)
    | @composer.MentionOpened(identity~, ..)
    | @composer.GoalEditStarted(identity~)
    | @composer.GoalCancelled(identity~)
    | @composer.GoalCleared(identity~)
    | @composer.GoalSubmitted(identity~, ..)
    | @composer.StopRequested(identity~)
    | @composer.FileIndexEnsured(identity~) => identity
  }
  guard self.accepts_composer_identity(identity, channel) else {
    return (@cmd.none, self)
  }
  match action {
    @composer.DraftSubmitted(draft~, ..) => {
      let next = { ..self, draft: draft.task, mentions: draft.mentions }
      next.submit_composer(dispatch, channel)
    }
    @composer.DraftPresenceChanged(
      present=false,
      cleared_source=Some(source),
      ..
    ) => {
      let draft = if self.draft == source.task { "" } else { self.draft }
      let mentions = if self.mentions == source.mentions {
        []
      } else {
        self.mentions
      }
      (@cmd.none, { ..self, draft, mentions })
    }
    @composer.RootMentionRemoved(mention~, ..) =>
      (
        @cmd.none,
        {
          ..self,
          mentions: self.mentions.filter(existing => {
            existing.ref_ != mention.ref_
          }),
        },
      )
    @composer.SlashCommand(command~, ..) =>
      self.run_composer_command(dispatch, channel, command)
    @composer.StopRequested(..) => (self.interrupt(dispatch, channel), self)
    @composer.DraftPresenceChanged(..)
    | @composer.MentionOpened(..)
    | @composer.GoalEditStarted(..)
    | @composer.GoalCancelled(..)
    | @composer.GoalCleared(..)
    | @composer.GoalSubmitted(..)
    | @composer.FileIndexEnsured(..) => (@cmd.none, self)
  }
}

///|
test "Codex skills/list retains enabled cwd-scoped skills" {
  guard CodexSkill::decode_list(
      {
        "data": [
          {
            "cwd": "/work/project",
            "skills": [
              {
                "name": "review-pr",
                "description": "Review a pull request",
                "path": "/skills/review-pr/SKILL.md",
                "enabled": true,
              },
              {
                "name": "disabled",
                "description": "Disabled",
                "path": "/skills/disabled/SKILL.md",
                "enabled": false,
              },
            ],
          },
        ],
      },
      "/work/project",
    )
    is Some([skill]) else {
    fail("expected one enabled Codex skill")
  }
  inspect(skill.name, content="review-pr")
  inspect(skill.path, content="/skills/review-pr/SKILL.md")
}

///|
test "Codex projects app-server facts into the shared composer contract" {
  let state = State::from_thread_snapshot({
    "thread": {
      "id": "thread-shared-composer",
      "cwd": "/work/project",
      "turns": [],
    },
  })
  let dispatch : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let input = state.composer_input(dispatch, {
    channel: @interop.ChannelId::Local,
    file_candidates: [@pathx.Relative("src/main.mbt")],
    open_files: [],
    active_file: None,
    file_index: @composer.FileIndexReady(epoch=1, truncated=false),
  })
  assert_eq(input.identity.owner.session, "thread-shared-composer")
  assert_eq(input.slash_commands.length(), 2)
  assert_eq(input.file_candidates, [@pathx.Relative("src/main.mbt")])
  guard input.root is Some(root) else {
    fail("stored Codex task should expose a composer root")
  }
  assert_eq(root.path, "/work/project")
}

///|
test "Codex draft skills wait for the host-confirmed project root" {
  let pending = State().select_draft("draft-1", "/clicked/path")
  assert_true(pending.active_context() is None)
  let confirmed = pending.with_open_draft("draft-1", {
    "draftId": "draft-1",
    "projectRoot": "/canonical/project",
  })
  guard confirmed.active_context() is Some(context) else {
    fail("confirmed draft should expose a Codex skill context")
  }
  assert_eq(context.cwd, "/canonical/project")
}
