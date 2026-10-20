///|
fn Completion::view(
  locale~ : @i18n.Locale = English,
  self : Completion,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  ignore(locale)
  let hint = match self.kind {
    SlashCommands => ui(locale, CommandsLabel)
    SkillMentions => ui(locale, SkillsLabel)
    Symbols => ui(locale, SymbolsLabel)
    Files => ui(locale, FilesLabel)
  }
  let rows : Array[CompletionRow] = []
  for _, item in self.menu {
    rows.push({ label: item.label, detail: item.detail, })
  }
  CompletionView::{
    rows,
    selected: self.menu.selected(),
    hint,
    empty: if self.menu.loading() {
      ui(locale, SearchingLabel)
    } else if self.kind is Files {
      ui(locale, NoFiles)
    } else {
      ui(locale, NoSymbols)
    },
  }.render(locale~, index => emit(CompletionPick(index)))
}

///|
/// Render the permanent mention tray. Keeping it mounted when empty preserves
/// the textarea's positional DOM identity.
fn Entry::mention_chips(
  locale~ : @i18n.Locale = English,
  self : Entry,
  emit : @cmd.Emit[Msg],
  disabled~ : Bool,
) -> Array[@html.Html] {
  let chips : Array[@html.Html] = []
  for index, mention in self.draft.mentions {
    if mention.ref_ is @mention_context.ReviewChanges(_) {
      continue
    }
    let target = @mention_context.target(mention.ref_)
    chips.push(
      MentionChip::{
        glyph: @mention_context.glyph(mention.ref_),
        label: @mention_context.label(mention.ref_),
        title: if mention.ref_ is @mention_context.Annotation(comment~, ..) {
          comment
        } else if mention.ref_ is @mention_context.BrowserAnnotation(element~) {
          element.url + "\n" + element.selector.unwrap_or(element.tag)
        } else if mention.ref_ is @mention_context.SemanticSearch(reference) {
          "Open semantic search with \{reference.matches.length()} matches"
        } else if mention.ref_
          is @mention_context.OfficeSelection(materialized~) {
          @mention_context.office_selection_title(materialized)
        } else if target is Some(target) {
          dynamic_text(locale, DJump(target.file.to_string()))
        } else {
          @mention_context.label(mention.ref_)
        },
        jump: if target is Some(_) ||
          mention.ref_ is @mention_context.SemanticSearch(_) {
          Some(emit(MentionJumped(index)))
        } else {
          None
        },
        remove: Some(
          (emit(MentionRemoved(index)), @icons.icon(@icons.icon_close)),
        ),
      }.render(locale~, disabled~),
    )
  }
  if self.review_changes().length() > 0 {
    chips.push(self.changes_chip(locale~, emit, disabled~))
  }
  chips
}

///|
fn GoalInput::first_line(_self : GoalInput, text : String) -> String {
  if text.split_once("\n") is Some((first, _)) {
    first.to_owned()
  } else {
    text
  }
}

///|
/// Render the stable standing-goal row. All user operations leave the package
/// as owner-bound actions instead of dispatching root messages directly.
fn GoalInput::view(
  locale~ : @i18n.Locale = English,
  self : GoalInput,
  identity : Identity,
  action_emit : @cmd.Emit[Action],
) -> @html.Html {
  ignore(locale)
  if self.draft is Some(_) {
    return @html.div(class="composer-context-row composer-goal editing", [
      @html.span(class="composer-notice-icon", @icons.icon(@icons.icon_target)),
      @html.span(class="composer-goal-text", ui(locale, EditingGoal)),
      @html.button(
        id="goal-cancel",
        class="composer-goal-action",
        type_="button",
        title=ui(locale, CancelGoalEditing),
        on_click=action_emit(GoalCancelled(identity~)),
        @icons.icon(@icons.icon_close),
      ),
    ])
  }
  let (row_class, text, title, editable) = if self.pending is Some(pending) {
    match pending {
      GoalSetting(text) =>
        (
          "composer-context-row composer-goal pending",
          dynamic_text(locale, DSettingGoal(self.first_line(text).to_string())),
          text,
          true,
        )
      GoalClearing =>
        (
          "composer-context-row composer-goal pending",
          ui(locale, ClearingGoal),
          ui(locale, WaitingEngine),
          false,
        )
    }
  } else {
    guard self.standing is Some(goal) else {
      return @html.div(class="composer-context-row composer-goal hidden", "")
    }
    if goal.blocked is Some(reason) {
      (
        "composer-context-row composer-goal blocked",
        dynamic_text(locale, DGoalBlocked(self.first_line(reason).to_string())),
        dynamic_text(
          locale,
          DGoalBlockedDetails(goal.text.to_string(), reason.to_string()),
        ),
        true,
      )
    } else {
      (
        "composer-context-row composer-goal",
        dynamic_text(locale, DGoal(self.first_line(goal.text).to_string())),
        goal.text,
        true,
      )
    }
  }
  let edit : Array[@html.Html] = if editable {
    [
      @html.button(
        class="composer-goal-action",
        type_="button",
        title=ui(locale, EditGoal),
        on_click=action_emit(GoalEditStarted(identity~)),
        ui(locale, EditLabel),
      ),
    ]
  } else {
    []
  }
  @html.div(
    class=row_class,
    [
      @html.span(class="composer-notice-icon", @icons.icon(@icons.icon_target)),
      @html.span(class="composer-goal-text", title~, text),
      ..edit,
      @html.button(
        class="composer-goal-action",
        type_="button",
        title=ui(locale, ClearGoal),
        on_click=action_emit(GoalCleared(identity~)),
        @icons.icon(@icons.icon_close),
      ),
    ],
  )
}

///|
fn Entry::action_buttons(
  locale~ : @i18n.Locale = English,
  self : Entry,
  emit : @cmd.Emit[Msg],
  action_emit : @cmd.Emit[Action],
  input : Input,
) -> Array[ActionButton] {
  let goal_mode = input.goal.draft is Some(_)
  if goal_mode {
    return [
      {
        id: "goal-set",
        class_name: "icon-button send-button",
        title: ui(locale, SetGoal),
        disabled: self.goal_draft.unwrap_or("").is_blank(),
        command: emit(SubmitRequested),
        content: @icons.icon(@icons.icon_arrow_up),
      },
    ]
  }
  match input.presentation.primary_action {
    Send(available~) =>
      [
        {
          id: "send",
          class_name: "icon-button send-button",
          title: ui(locale, SendLabel),
          disabled: !available ||
          self.image_reads > 0 ||
          !self.attachment_requests.is_empty() ||
          self.draft.is_blank() ||
          (
            input.shell_command(self.draft) is Some(command) &&
            command.is_blank()
          ),
          command: emit(SubmitRequested),
          content: @icons.icon(@icons.icon_arrow_up),
        },
      ]
    Running(steer_available~, can_stop~, submit~, ..) => {
      let submit = self.running_submit(submit)
      let actions : Array[ActionButton] = [
        {
          id: "stop",
          class_name: "icon-button stop-button",
          title: ui(locale, StopLabel),
          disabled: !can_stop,
          command: action_emit(StopRequested(identity=self.identity())),
          content: @icons.icon(@icons.icon_debug_stop),
        },
      ]
      if steer_available && !self.draft.is_blank() {
        actions.push({
          id: "send",
          class_name: "icon-button send-button",
          title: match submit {
            Steer => ui(locale, SteerTask)
            Queue => ui(locale, QueueNextTurn)
            SaveQueue => ui(locale, SaveQueued)
          },
          disabled: input.presentation.disabled ||
          self.image_reads > 0 ||
          !self.attachment_requests.is_empty(),
          command: emit(SubmitRequested),
          content: @icons.icon(@icons.icon_arrow_up),
        })
      }
      actions
    }
  }
}

///|
fn Entry::view(
  locale~ : @i18n.Locale = English,
  self : Entry,
  emit : @cmd.Emit[Msg],
  action_emit : @cmd.Emit[Action],
  input : Input,
  clock_ms~ : Double,
) -> @html.Html {
  ignore(locale)
  let goal_mode = input.goal.draft is Some(_)
  let shell_command = input.shell_command(self.draft)
  let actions = self.action_buttons(locale~, emit, action_emit, input)
  // Notices can appear ahead of open disclosures. Key their parent panels as
  // well as their rows so inserting a notice preserves native DOM state.
  let context : Map[String, @html.Html] = Map([])
  for component in input.presentation.context {
    let key = match component {
      ConnectionBanner(..) => "connection"
      SubrunDock(..) => "subruns"
      ApiSetupNotice(..) => "api-setup"
      ApprovalRequest(_) => "approval"
      CodexRequests(..) => "codex-requests"
      PendingSteerPanel(..) => "steers"
      ShellCommandsRunning(..) => "shell-commands"
      QueuedInputPanel(..) => "queue"
      CompactionNotice(..) => "compaction"
      WorktreePlacementNotice => "worktree-placement"
      MissingWorktreeNoticeComponent(_) => "missing-worktree"
    }
    context[key] = component.render(locale~, self.identity(), action_emit)
  }
  // Closest to the textarea: the turn's own liveness is what the person
  // waiting is watching for, and the wait is spent looking here rather than
  // at the top bar.
  context["running"] = running_row(locale~, input.run, clock_ms~)
  context["goal"] = input.goal.view(locale~, self.identity(), action_emit)
  let image_emit = emit.map(event => {
    ImageRead(self.identity(), self.root, event)
  })
  let can_attach = (
      input.presentation.images_enabled ||
      (input.identity.owner.host() is Some(_) && input.root is Some(_))
    ) &&
    !input.presentation.disabled &&
    !goal_mode &&
    shell_command is None
  // Keep a permanent first slot so hiding the attachment button does not
  // rebuild the model and workspace controls that follow it.
  let status : Array[@html.Html] = [
    @html.div(
      class="composer-add",
      if can_attach {
        [
          @html.button(
            class="composer-attach",
            type_="button",
            title=ui(locale, AttachHint),
            on_click=pick_attachments(locale, input, image_emit),
            attrs=@html.Attrs::build().aria_label(ui(locale, AttachImages)),
            @icons.icon(@icons.icon_add),
          ),
        ]
      } else {
        ([] : Array[@html.Html])
      },
    ),
  ]
  for component in input.presentation.status {
    // A transfer snapshots completed content. Let attachment reads/uploads
    // finish before the user can move their owner to another agent.
    let component = match component {
      ModelStatus(control) if self.image_reads > 0 ||
        !self.attachment_requests.is_empty() =>
        ModelStatus({ ..control, disabled: true, })
      other => other
    }
    status.push(
      component.render(locale~, self.identity(), self.draft, action_emit),
    )
  }
  if self.image_reads > 0 {
    context["image-reading"] = @html.div(
      class="composer-context-row composer-image-notice",
      ui(locale, ReadingImages),
    )
  }
  if self.image_error is Some(message) {
    context["image-error"] = @html.div(
      class="composer-context-row composer-image-notice error",
      attrs=@html.Attrs::build().role("alert"),
      message,
    )
  }
  for index, confirmation in self.attachment_confirmations(locale, emit) {
    context["attachment-\{index}"] = confirmation
  }
  View::{
    allow_images: input.presentation.images_enabled,
    images: if can_attach {
      Some(image_emit)
    } else {
      None
    },
    before_inner: context,
    mentions: [
      ..self.mention_chips(locale~, emit, disabled=input.presentation.disabled),
      ..self.draft.image_previews(
        locale~,
        emit,
        disabled=input.presentation.disabled,
      ),
    ],
    value: if goal_mode {
      self.goal_draft.unwrap_or("")
    } else {
      self.draft.task
    },
    shell: shell_command is Some(_),
    placeholder: if self.prediction_text(input) is Some(text) {
      text
    } else if !goal_mode && self.submission_choice(input) is Some(choice) {
      match choice {
        SteerNow => ui(locale, SteerPlaceholder)
        QueueNext => ui(locale, QueuePlaceholder)
      }
    } else {
      input.presentation.placeholder
    },
    disabled: input.presentation.disabled,
    input: emit.map(value => TextChanged(value)),
    history: if goal_mode {
      None
    } else {
      self.history_label(locale, input)
    },
    keyboard: {
      menu_open: !goal_mode && self.completion is Some(_),
      prediction: self.prediction_text(input).map(_ => emit(PredictionAccepted)),
      history: if !goal_mode && self.can_recall_history(input) {
        Some(delta => emit(HistoryMoved(delta)))
      } else {
        None
      },
      navigate: delta => emit(CompletionMove(delta)),
      accept: emit(CompletionAccept),
      dismiss: emit(CompletionDismiss),
      submit: emit(SubmitRequested),
      cancel: if goal_mode {
        Some(emit(GoalCancelled))
      } else {
        None
      },
    },
    status,
    actions,
    // A command is not a follow-up: it never steers or queues behind the turn.
    followup_menu: if shell_command is Some(_) {
      None
    } else {
      self.followup_menu(locale~, input, emit)
    },
    overlay: if goal_mode {
      None
    } else {
      self.completion.map(completion => completion.view(locale~, emit))
    },
  }.render(locale~)
}

///|
fn Entry::running_submit(
  self : Entry,
  default : RunningSubmit,
) -> RunningSubmit {
  if default is SaveQueue {
    return SaveQueue
  }
  match self.followup_choice {
    Some(SteerNow) => Steer
    Some(QueueNext) => Queue
    None => default
  }
}

///|
fn Entry::submission_choice(self : Entry, input : Input) -> FollowupChoice? {
  guard input.presentation.primary_action
    is Running(queue_available=true, submit~, ..) else {
    return None
  }
  match self.running_submit(submit) {
    Steer => Some(SteerNow)
    Queue => Some(QueueNext)
    SaveQueue => None
  }
}

///|
fn Entry::followup_menu(
  locale~ : @i18n.Locale = English,
  self : Entry,
  input : Input,
  emit : @cmd.Emit[Msg],
) -> @html.Html? {
  guard input.goal.draft is None &&
    input.presentation.primary_action is Running(steer_available~, ..) &&
    self.submission_choice(input) is Some(choice) else {
    return None
  }
  Some(
    @select_control.Control::{
      id: "composer-followup-select",
      groups: [
        {
          label: ui(locale, ThisMessage),
          options: [
            { value: "steer", label: ui(locale, SteerNowLabel), },
            { value: "queue", label: ui(locale, QueueNextLabel), },
          ],
        },
      ],
      selected: match choice {
        SteerNow => "steer"
        QueueNext => "queue"
      },
      disabled: !steer_available || self.image_reads > 0,
      open: self.followup_menu_open,
      toggle: emit(FollowupMenuToggled),
      dismiss: emit(FollowupMenuDismissed),
      change: emit.map(value => FollowupSelected(value)),
      title: ui(locale, FollowupHint),
      aria_label: ui(locale, FollowupAction),
      presentation: Composer(@icons.icon(@icons.icon_indent), true),
    }.render(),
  )
}
