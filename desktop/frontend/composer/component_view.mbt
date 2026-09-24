///|
fn Completion::view(
  locale? : @i18n.Locale = English,
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
  locale? : @i18n.Locale = English,
  self : Entry,
  emit : @cmd.Emit[Msg],
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
        } else if mention.ref_ is @mention_context.SemanticSearch(reference) {
          "Open semantic search with \{reference.matches.length()} matches"
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
      }.render(locale~),
    )
  }
  if self.review_changes().length() > 0 {
    chips.push(self.changes_chip(locale~, emit))
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
  locale? : @i18n.Locale = English,
  self : GoalInput,
  identity : Identity,
  action_emit : @cmd.Emit[Action],
) -> @html.Html {
  ignore(locale)
  if self.draft is Some(_) {
    return @html.div(class="composer-goal editing", [
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
          "composer-goal pending",
          dynamic_text(locale, DSettingGoal(self.first_line(text).to_string())),
          text,
          true,
        )
      GoalClearing =>
        (
          "composer-goal pending",
          ui(locale, ClearingGoal),
          ui(locale, WaitingEngine),
          false,
        )
    }
  } else {
    guard self.standing is Some(goal) else {
      return @html.div(class="composer-goal hidden", "")
    }
    if goal.blocked is Some(reason) {
      (
        "composer-goal blocked",
        dynamic_text(locale, DGoalBlocked(self.first_line(reason).to_string())),
        dynamic_text(
          locale,
          DGoalBlockedDetails(goal.text.to_string(), reason.to_string()),
        ),
        true,
      )
    } else {
      (
        "composer-goal",
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
  locale? : @i18n.Locale = English,
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
          disabled: !available || self.image_reads > 0 || self.draft.is_empty(),
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
      if steer_available && !self.draft.is_empty() {
        actions.push({
          id: "send",
          class_name: "icon-button send-button",
          title: match submit {
            Steer => ui(locale, SteerTask)
            Queue => ui(locale, QueueNextTurn)
            SaveQueue => ui(locale, SaveQueued)
          },
          disabled: self.image_reads > 0,
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
  locale? : @i18n.Locale = English,
  self : Entry,
  emit : @cmd.Emit[Msg],
  action_emit : @cmd.Emit[Action],
  input : Input,
  clock_ms~ : Double,
) -> @html.Html {
  ignore(locale)
  let goal_mode = input.goal.draft is Some(_)
  let actions = self.action_buttons(locale~, emit, action_emit, input)
  let context : Array[@html.Html] = []
  for component in input.presentation.context {
    context.push(component.render(locale~, self.identity(), action_emit))
  }
  // Closest to the textarea: the turn's own liveness is what the person
  // waiting is watching for, and the wait is spent looking here rather than
  // at the top bar. Both rows are permanent slots, so neither can shift the
  // other's child index as a run starts and ends.
  context.push(running_row(locale~, input.run, clock_ms~))
  context.push(input.goal.view(locale~, self.identity(), action_emit))
  let image_emit = emit.map(event => ImageRead(self.identity(), event))
  let can_attach = input.presentation.images_enabled &&
    !input.presentation.disabled &&
    !goal_mode
  let status = input.presentation.status.map(component => {
    component.render(locale~, self.identity(), action_emit)
  })
  if can_attach {
    status.push(
      @html.button(
        class="composer-attach",
        type_="button",
        title=ui(locale, AttachHint),
        on_click=@image_input.pick(locale~, image_emit),
        attrs=@html.Attrs::build().aria_label(ui(locale, AttachImages)),
        ui(locale, AttachImages),
      ),
    )
  }
  if self.image_reads > 0 {
    context.push(
      @html.div(class="composer-image-notice", ui(locale, ReadingImages)),
    )
  }
  if self.image_error is Some(message) {
    context.push(
      @html.div(
        class="composer-image-notice error",
        attrs=@html.Attrs::build().role("alert"),
        message,
      ),
    )
  }
  View::{
    images: if can_attach {
      Some(image_emit)
    } else {
      None
    },
    before_inner: context,
    mentions: [
      ..self.mention_chips(locale~, emit),
      ..self.draft.image_previews(locale~, emit),
    ],
    value: if goal_mode {
      self.goal_draft.unwrap_or("")
    } else {
      self.draft.task
    },
    placeholder: if !goal_mode && self.submission_choice(input) is Some(choice) {
      match choice {
        SteerNow => ui(locale, SteerPlaceholder)
        QueueNext => ui(locale, QueuePlaceholder)
      }
    } else {
      input.presentation.placeholder
    },
    disabled: input.presentation.disabled,
    input: emit.map(value => TextChanged(value)),
    keyboard: {
      menu_open: !goal_mode && self.completion is Some(_),
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
    followup_menu: self.followup_menu(locale~, input, emit),
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
  locale? : @i18n.Locale = English,
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
      presentation: Composer("↳", true),
    }.render(),
  )
}
