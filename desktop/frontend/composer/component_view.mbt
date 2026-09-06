///|
fn Completion::view(self : Completion, emit : @cmd.Emit[Msg]) -> @html.Html {
  let hint = match self.kind {
    SlashCommands => "Commands"
    SkillMentions => "Skills"
    Symbols => "Symbols"
    Files => "Files"
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
      "Searching…"
    } else if self.kind is Files {
      "No files"
    } else {
      "No symbols"
    },
  }.render(index => emit(CompletionPick(index)))
}

///|
/// Render the permanent mention tray. Keeping it mounted when empty preserves
/// the textarea's positional DOM identity.
fn Draft::mention_chips(
  self : Draft,
  emit : @cmd.Emit[Msg],
) -> Array[@html.Html] {
  let chips : Array[@html.Html] = []
  for index, mention in self.mentions {
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
          "Jump to \{target.file}"
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
      }.render(),
    )
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
  self : GoalInput,
  identity : Identity,
  action_emit : @cmd.Emit[Action],
) -> @html.Html {
  if self.draft is Some(_) {
    return @html.div(class="composer-goal editing", [
      @html.span(class="composer-notice-icon", @icons.icon(@icons.icon_target)),
      @html.span(
        class="composer-goal-text",
        "You're editing this conversation's standing goal.",
      ),
      @html.button(
        id="goal-cancel",
        class="composer-goal-action",
        type_="button",
        title="Stop editing the standing goal — the goal itself is left alone (Esc)",
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
          "Setting goal: \{self.first_line(text)}",
          text,
          true,
        )
      GoalClearing =>
        (
          "composer-goal pending", "Clearing goal…", "Waiting for the engine to record it",
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
        "Goal blocked: \{self.first_line(reason)}",
        "Goal: \{goal.text}\n\nBlocked: \{reason}",
        true,
      )
    } else {
      ("composer-goal", "Goal: \{self.first_line(goal.text)}", goal.text, true)
    }
  }
  let edit : Array[@html.Html] = if editable {
    [
      @html.button(
        class="composer-goal-action",
        type_="button",
        title="Edit the standing goal",
        on_click=action_emit(GoalEditStarted(identity~)),
        "Edit",
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
        title="Clear the standing goal",
        on_click=action_emit(GoalCleared(identity~)),
        @icons.icon(@icons.icon_close),
      ),
    ],
  )
}

///|
fn Entry::action_buttons(
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
        title: "Set the standing goal (Enter)",
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
          title: "Send",
          disabled: !available ||
          (self.draft.task.is_blank() && self.draft.mentions.is_empty()),
          command: emit(SubmitRequested),
          content: @icons.icon(@icons.icon_arrow_up),
        },
      ]
    Running(steer_available~, can_stop~, submit~) => {
      let actions : Array[ActionButton] = [
        {
          id: "stop",
          class_name: "icon-button stop-button",
          title: "Stop",
          disabled: !can_stop,
          command: action_emit(StopRequested(identity=self.identity())),
          content: @icons.icon(@icons.icon_debug_stop),
        },
      ]
      if steer_available &&
        (!self.draft.task.is_blank() || !self.draft.mentions.is_empty()) {
        actions.push({
          id: "send",
          class_name: "icon-button send-button",
          title: match submit {
            Steer => "Steer the running task"
            Queue => "Queue for the next turn"
            SaveQueue => "Save queued message"
          },
          disabled: false,
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
  self : Entry,
  emit : @cmd.Emit[Msg],
  action_emit : @cmd.Emit[Action],
  input : Input,
  clock_ms~ : Double,
) -> @html.Html {
  let goal_mode = input.goal.draft is Some(_)
  let actions = self.action_buttons(emit, action_emit, input)
  let context : Array[@html.Html] = []
  for component in input.presentation.context {
    context.push(component.render(self.identity(), action_emit))
  }
  // Closest to the textarea: the turn's own liveness is what the person
  // waiting is watching for, and the wait is spent looking here rather than
  // at the top bar. Both rows are permanent slots, so neither can shift the
  // other's child index as a run starts and ends.
  context.push(running_row(input.run, clock_ms~))
  context.push(input.goal.view(self.identity(), action_emit))
  View::{
    before_inner: context,
    mentions: self.draft.mention_chips(emit),
    value: if goal_mode {
      self.goal_draft.unwrap_or("")
    } else {
      self.draft.task
    },
    placeholder: input.presentation.placeholder,
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
    status: input.presentation.status.map(component => {
      component.render(self.identity(), action_emit)
    }),
    actions,
    overlay: if goal_mode {
      None
    } else {
      self.completion.map(completion => completion.view(emit))
    },
  }.render()
}
