///|
fn schedule_status(
  locale~ : @i18n.Locale = English,
  status : @protocol.ScheduleRunStatus,
) -> String {
  match status {
    Running => ui(locale, RunningLabel)
    Succeeded => ui(locale, CompletedLabel)
    Failed(message) => "\{ui(locale, FailedLabel)}\{message}"
    Stopped => ui(locale, StoppedLabel)
    TimedOut => ui(locale, TimedOutLabel)
    Interrupted => ui(locale, InterruptedLabel)
  }
}

///|
/// Whether a one-time schedule's time has passed with nothing left to run.
/// Resume cannot revive it; a new time or Run now can.
fn schedule_finished(entry : @protocol.ScheduleEntry, now : Int64) -> Bool {
  !entry.enabled && entry.spec.timing is Once(at) && at <= now
}

///|
fn schedules_page(dispatch : @cmd.Emit[Msg], model : Model) -> @html.Html {
  let locale = model.locale
  let page = model.schedules
  let emit = dispatch.map(msg => SchedulePage(msg))
  let now = schedule_client_now()
  let content : Array[@html.Html] = [
    @html.div(class="page-header", [
      @html.div(class="page-eyebrow", model.focused_device_name()),
      @html.p(class="page-subtitle", ui(locale, ScheduleDescription)),
    ]),
    @html.div(class="schedule-toolbar", [
      @html.button(
        class="button primary",
        disabled=page.changing(),
        on_click=emit(New),
        ui(locale, NewSchedule),
      ),
      @html.button(
        class="button secondary",
        on_click=emit(Poll),
        ui(locale, RefreshLabel),
      ),
    ]),
  ]
  if page.error is Some(error) {
    content.push(
      @html.div(
        class="schedule-error",
        attrs=@html.Attrs::build().role("alert"),
        error,
      ),
    )
  }
  // A new schedule's form opens under the button that asked for it; an
  // edited schedule's form replaces that schedule's card.
  if page.form is Some(form) && form.id is None {
    content.push(schedule_form_view(emit, model, form))
  }
  if page.snapshot.entries.is_empty() {
    content.push(@html.p(class="schedule-meta", ui(locale, EmptySchedules)))
  }
  for entry in page.snapshot.entries {
    if page.form is Some(form) && form.id == Some(entry.id) {
      content.push(schedule_form_view(emit, model, form))
    } else {
      content.push(schedule_entry_card(emit, locale, page, entry, now))
    }
  }
  for running in [true, false] {
    let title = if running {
      ui(locale, RunningLabel)
    } else {
      ui(locale, RunHistory)
    }
    let runs = page.snapshot.runs.filter(run => {
      (run.status is Running) == running
    })
    let section : Array[@html.Html] = [
      @html.h2(class="schedule-history-title", title),
    ]
    if runs.is_empty() {
      section.push(
        @html.p(
          class="schedule-meta",
          if running {
            ui(locale, NoRunningTasks)
          } else {
            ui(locale, NoFinishedRuns)
          },
        ),
      )
    }
    for run in runs.rev_iter() {
      section.push(schedule_run_card(emit, locale, page, run))
    }
    content.push(
      @html.section(attrs=@html.Attrs::build().aria_label(title), section),
    )
  }
  @ui.dialog_page(class="schedules-page", content)
}

///|
fn schedule_entry_card(
  emit : @cmd.Emit[SchedulePageMsg],
  locale : @i18n.Locale,
  page : SchedulePage,
  entry : @protocol.ScheduleEntry,
  now : Int64,
) -> @html.Html {
  let running = page.snapshot.runs.any(run => {
    run.schedule_id == entry.id && run.status is Running
  })
  let finished = schedule_finished(entry, now)
  let timing = match entry.spec.timing {
    Every(minutes) => schedule_interval_text(locale, minutes)
    Once(at) => "\{ui(locale, OnceLabel)}\{schedule_time(locale~, at)}"
  }
  let state = if entry.run_requested {
    ui(locale, QueuedLabel)
  } else {
    match entry.next_at {
      Some(at) => "\{ui(locale, NextLabel)}\{schedule_time(locale~, at)}"
      None =>
        if entry.enabled {
          ui(locale, WaitingLabel)
        } else if finished {
          ui(locale, FinishedStatus)
        } else {
          ui(locale, PausedStatus)
        }
    }
  }
  let actions = if page.confirm_delete == Some(entry.id) {
    @html.div(class="schedule-confirm", [
      @html.p(schedule_delete_question(locale, entry.spec.name)),
      @html.div(class="schedule-toolbar", [
        @html.button(
          class="button secondary",
          on_click=emit(CancelDelete),
          ui(locale, CancelLabel),
        ),
        @html.button(
          class="button danger",
          disabled=page.changing(),
          on_click=emit(Action(entry.id, Delete)),
          ui(locale, DeleteLabel),
        ),
      ]),
    ])
  } else {
    @html.div(class="schedule-toolbar", [
      @html.button(
        class="button secondary",
        disabled=page.changing() || running || entry.run_requested,
        on_click=emit(Action(entry.id, Run)),
        ui(locale, RunNow),
      ),
      if entry.enabled {
        @html.button(
          class="button secondary",
          disabled=page.changing(),
          on_click=emit(Action(entry.id, Pause)),
          ui(locale, PauseLabel),
        )
      } else if finished {
        // A passed one-time schedule resumes only through a new time.
        @html.nothing
      } else {
        @html.button(
          class="button secondary",
          disabled=page.changing(),
          on_click=emit(Action(entry.id, Resume)),
          ui(locale, ResumeLabel),
        )
      },
      @html.button(
        class="button secondary",
        disabled=page.changing(),
        on_click=emit(Edit(entry.id)),
        ui(locale, EditLabel),
      ),
      if running {
        @html.button(
          class="button secondary",
          disabled=page.changing(),
          on_click=emit(Action(entry.id, Stop)),
          ui(locale, StopRun),
        )
      } else {
        @html.button(
          class="button secondary",
          disabled=page.changing(),
          on_click=emit(AskDelete(entry.id)),
          ui(locale, DeleteLabel),
        )
      },
    ])
  }
  @html.div(class="schedule-card schedule-panel card-surface", [
    @html.h2(entry.spec.name),
    @html.p(class="schedule-meta", "\{timing} · \{state}"),
    @html.p(
      class="schedule-meta",
      entry.spec.workspace.unwrap_or(ui(locale, AutomaticDirectory)),
    ),
    @html.p(class="schedule-task", entry.spec.task),
    match entry.skipped {
      Some(skip) =>
        @html.p(class="schedule-meta", schedule_skip_text(locale, skip))
      None => @html.nothing
    },
    actions,
  ])
}

///|
fn schedule_run_card(
  emit : @cmd.Emit[SchedulePageMsg],
  locale : @i18n.Locale,
  page : SchedulePage,
  run : @protocol.ScheduleRun,
) -> @html.Html {
  // The log opens inside the run that asked for it, not at the top of the
  // page, where a run far down the history would show nothing happening.
  let log = match page.log {
    Some((path, text)) if path == run.log_path => Some(text)
    _ => None
  }
  @html.div(class="schedule-card schedule-panel card-surface", [
    @html.h3(run.name),
    @html.p(
      class="schedule-meta",
      "\{schedule_time(locale~, run.started_at)} · \{schedule_status(locale~, run.status)}",
    ),
    @html.div(class="schedule-toolbar", [
      if run.status is Running {
        @html.button(
          class="button secondary",
          disabled=page.changing(),
          on_click=emit(Action(run.schedule_id, Stop)),
          ui(locale, StopRun),
        )
      } else {
        @html.nothing
      },
      @html.button(
        class="button secondary",
        on_click=emit(Open(run)),
        ui(locale, OpenSession),
      ),
      if log is Some(_) {
        @html.button(
          class="button secondary",
          on_click=emit(CloseLog),
          ui(locale, CloseLog),
        )
      } else {
        @html.button(
          class="button secondary",
          on_click=emit(Log(run.log_path)),
          ui(locale, ViewLog),
        )
      },
    ]),
    match log {
      Some(text) =>
        @html.div(
          class="schedule-log",
          attrs=@html.Attrs::build()
            .role("region")
            .aria_label(ui(locale, RunLog)),
          [
            @html.p(
              class="schedule-meta",
              "\{ui(locale, LogLabel)}\{run.log_path}",
            ),
            @html.pre(class="schedule-log-content", text),
          ],
        )
      None => @html.nothing
    },
  ])
}

///|
fn schedule_form_view(
  emit : @cmd.Emit[SchedulePageMsg],
  model : Model,
  form : ScheduleForm,
) -> @html.Html {
  let locale = model.locale
  let page = model.schedules
  let options = [@html.option(value="auto", ui(locale, AutomaticallyCreate))]
  if model.focused_device() is Some(dev) {
    for project in dev.projects {
      options.push(@html.option(value=project.path, project.path))
    }
  }
  fn field(
    label : String,
    edit : (String) -> ScheduleField,
    value : String,
  ) -> @html.Html {
    @html.label(class="schedule-field", [
      @html.span(label),
      @html.input(
        class="schedule-input field-surface",
        value~,
        attrs=@html.Attrs::build().data_set("focus-owner", ""),
        on_input=emit.map(value => Field(edit(value))),
      ),
    ])
  }
  @html.div(class="schedule-form schedule-panel card-surface", [
    @html.h2(
      if form.id is Some(_) {
        ui(locale, EditSchedule)
      } else {
        ui(locale, NewSchedule)
      },
    ),
    field(ui(locale, NameLabel), value => Name(value), form.name),
    @html.label(class="schedule-field", [
      @html.span(ui(locale, WorkingDirectory)),
      @html.select(
        class="schedule-input field-surface",
        attrs=@html.Attrs::build()
          .data_set("focus-owner", "")
          .aria_label(ui(locale, WorkingDirectory))
          .value_prop(form.workspace.unwrap_or("auto")),
        on_change=emit.map(value => {
          Field(Workspace(if value == "auto" { None } else { Some(value) }))
        }),
        options,
      ),
    ]),
    @html.p(
      class="page-subtitle",
      if form.workspace is None {
        ui(locale, AutomaticDirectoryDescription)
      } else {
        ui(locale, ProjectDirectoryDescription)
      },
    ),
    @html.label(class="schedule-field", [
      @html.span(ui(locale, TaskLabel)),
      @html.textarea(
        class="schedule-input field-surface",
        attrs=@html.Attrs::build().data_set("focus-owner", ""),
        value=form.task,
        on_input=emit.map(value => Field(Task(value))),
        "",
      ),
    ]),
    @html.div(class="schedule-form-grid", [
      @html.label(class="schedule-field", [
        @html.span(ui(locale, ScheduleLabel)),
        @html.select(
          class="schedule-input field-surface",
          attrs=@html.Attrs::build()
            .data_set("focus-owner", "")
            .aria_label(ui(locale, ScheduleLabel))
            .value_prop(if form.once { "once" } else { "every" }),
          on_change=emit.map(value => Field(OneTime(value == "once"))),
          [
            @html.option(value="every", ui(locale, EveryLabel)),
            @html.option(value="once", ui(locale, OnceIn)),
          ],
        ),
      ]),
      field(ui(locale, MinutesLabel), value => Minutes(value), form.minutes),
      field(ui(locale, TimeoutMinutes), value => Timeout(value), form.timeout),
    ]),
    field(ui(locale, ModelDefault), value => Model(value), form.model),
    @html.p(class="page-subtitle", ui(locale, SchedulePermissions)),
    @html.p(class="page-subtitle", ui(locale, RunNowDescription)),
    @html.div(class="schedule-toolbar", [
      @html.button(
        class="button primary",
        disabled=page.changing(),
        on_click=emit(Save(false)),
        ui(locale, SaveSchedule),
      ),
      @html.button(
        class="button secondary",
        disabled=page.changing(),
        on_click=emit(Save(true)),
        ui(locale, SaveRunNow),
      ),
      @html.button(
        class="button secondary",
        on_click=emit(CloseForm),
        ui(locale, CancelLabel),
      ),
    ]),
  ])
}
