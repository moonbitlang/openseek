///|
fn schedule_status(
  locale? : @i18n.Locale = English,
  status : @protocol.ScheduleRunStatus,
) -> String {
  match status {
    Running => ui(locale, RunningLabel)
    Succeeded => ui(locale, CompletedLabel)
    Failed(message) => ui(locale, FailedLabel) + message
    Stopped => ui(locale, StoppedLabel)
    TimedOut => ui(locale, TimedOutLabel)
    Interrupted => ui(locale, InterruptedLabel)
  }
}

///|
fn schedules_page(dispatch : @cmd.Emit[Msg], model : Model) -> @html.Html {
  let locale = model.locale
  let page = model.schedules
  let emit = dispatch.map(msg => SchedulePage(msg))
  let content : Array[@html.Html] = [
    @html.div(class="settings-header", [
      @html.div(class="page-eyebrow", model.focused_device_name()),
      @html.h1(ui(locale, ScheduledTasks)),
      @html.p(class="settings-subtitle", ui(locale, ScheduleDescription)),
    ]),
    @html.div(class="schedule-toolbar", [
      @html.button(
        class="button",
        disabled=page.busy,
        on_click=emit(New),
        ui(locale, NewSchedule),
      ),
      @html.button(
        class="button secondary",
        disabled=page.busy,
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
  if page.log is Some((path, text)) {
    content.push(
      @html.div(class="schedule-card", [
        @html.div(class="schedule-toolbar", [
          @html.h2(ui(locale, RunLog)),
          @html.button(
            class="button secondary",
            on_click=emit(CloseLog),
            ui(locale, CloseLog),
          ),
        ]),
        @html.p(class="schedule-log", path),
        @html.pre(class="schedule-log-content", text),
      ]),
    )
  }
  if page.form is Some(form) {
    let options = [@html.option(value="auto", ui(locale, AutomaticallyCreate))]
    if model.focused_device() is Some(dev) {
      for project in dev.projects {
        options.push(@html.option(value=project.path, project.path))
      }
    }
    fn field(label : String, name : String, value : String) -> @html.Html {
      @html.label(class="schedule-field", [
        @html.span(label),
        @html.input(value~, on_input=emit.map(value => Field(name, value))),
      ])
    }
    content.push(
      @html.div(class="schedule-form", [
        @html.h2(
          if form.id is Some(_) {
            ui(locale, EditSchedule)
          } else {
            ui(locale, NewSchedule)
          },
        ),
        field(ui(locale, NameLabel), "name", form.name),
        @html.label(class="schedule-field", [
          @html.span(ui(locale, WorkingDirectory)),
          @html.select(
            attrs=@html.Attrs::build()
              .aria_label(ui(locale, WorkingDirectory))
              .value_prop(form.workspace.unwrap_or("auto")),
            on_change=emit.map(value => Field("workspace", value)),
            options,
          ),
        ]),
        @html.p(
          class="settings-subtitle",
          if form.workspace is None {
            ui(locale, AutomaticDirectoryDescription)
          } else {
            ui(locale, ProjectDirectoryDescription)
          },
        ),
        @html.label(class="schedule-field", [
          @html.span(ui(locale, TaskLabel)),
          @html.textarea(
            value=form.task,
            on_input=emit.map(value => Field("task", value)),
            "",
          ),
        ]),
        @html.div(class="schedule-form-grid", [
          @html.label(class="schedule-field", [
            @html.span(ui(locale, ScheduleLabel)),
            @html.select(
              attrs=@html.Attrs::build()
                .aria_label(ui(locale, ScheduleLabel))
                .value_prop(if form.once { "once" } else { "every" }),
              on_change=emit.map(value => Field("timing", value)),
              [
                @html.option(value="every", ui(locale, EveryLabel)),
                @html.option(value="once", ui(locale, OnceIn)),
              ],
            ),
          ]),
          field(ui(locale, MinutesLabel), "minutes", form.minutes),
          field(ui(locale, TimeoutMinutes), "timeout", form.timeout),
        ]),
        field(ui(locale, ModelDefault), "model", form.model),
        @html.p(class="settings-subtitle", ui(locale, SchedulePermissions)),
        @html.p(class="settings-subtitle", ui(locale, RunNowDescription)),
        @html.div(class="schedule-toolbar", [
          @html.button(
            class="button",
            disabled=page.busy,
            on_click=emit(Save(true)),
            ui(locale, SaveRunNow),
          ),
          @html.button(
            class="button secondary",
            disabled=page.busy,
            on_click=emit(Save(false)),
            ui(locale, SaveSchedule),
          ),
          @html.button(
            class="button secondary",
            on_click=emit(CloseForm),
            ui(locale, CancelLabel),
          ),
        ]),
      ]),
    )
  }
  if page.snapshot.entries.is_empty() {
    content.push(@html.p(class="schedule-empty", ui(locale, EmptySchedules)))
  }
  for entry in page.snapshot.entries {
    let running = page.snapshot.runs.any(run => {
      run.schedule_id == entry.id && run.status is Running
    })
    let timing = match entry.spec.timing {
      Every(n) =>
        match locale {
          SimplifiedChinese => "每 \{n} 分钟"
          TraditionalChinese => "每 \{n} 分鐘"
          Japanese => "\{n} 分ごと"
          English => "Every \{n} min"
          Spanish => "Cada \{n} min"
        }
      Once(at) => ui(locale, OnceLabel) + schedule_time(locale~, at)
    }
    let next = match entry.next_at {
      Some(at) => ui(locale, NextLabel) + schedule_time(locale~, at)
      None =>
        if entry.enabled {
          ui(locale, WaitingLabel)
        } else {
          ui(locale, PausedFinished)
        }
    }
    content.push(
      @html.div(class="schedule-card", [
        @html.h2(entry.spec.name),
        @html.p(
          class="schedule-meta",
          timing +
          " · " +
          (if entry.run_requested { ui(locale, QueuedLabel) } else { next }),
        ),
        @html.p(
          class="schedule-meta",
          entry.spec.workspace.unwrap_or(ui(locale, AutomaticDirectory)),
        ),
        @html.p(class="schedule-task", entry.spec.task),
        match entry.notice {
          Some(notice) => @html.p(class="schedule-meta", notice)
          None => @html.nothing
        },
        @html.div(class="schedule-toolbar", [
          @html.button(
            class="button secondary",
            disabled=page.busy || running || entry.run_requested,
            on_click=emit(Action(entry.id, "run")),
            ui(locale, RunNow),
          ),
          @html.button(
            class="button secondary",
            disabled=page.busy,
            on_click=emit(
              Action(entry.id, if entry.enabled { "pause" } else { "resume" }),
            ),
            if entry.enabled {
              ui(locale, PauseLabel)
            } else {
              ui(locale, ResumeLabel)
            },
          ),
          @html.button(
            class="button secondary",
            disabled=page.busy,
            on_click=emit(Edit(entry.id)),
            ui(locale, EditLabel),
          ),
          if running {
            @html.button(
              class="button secondary",
              disabled=page.busy,
              on_click=emit(Action(entry.id, "stop")),
              ui(locale, StopRun),
            )
          } else {
            @html.button(
              class="button secondary",
              disabled=page.busy,
              on_click=emit(Action(entry.id, "delete")),
              ui(locale, DeleteLabel),
            )
          },
        ]),
      ]),
    )
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
          class="schedule-empty",
          if running {
            ui(locale, NoRunningTasks)
          } else {
            ui(locale, NoFinishedRuns)
          },
        ),
      )
    }
    for run in runs.rev() {
      section.push(
        @html.div(class="schedule-card", [
          @html.h3(run.name),
          @html.p(
            class="schedule-meta",
            schedule_time(locale~, run.started_at) +
            " · " +
            schedule_status(locale~, run.status),
          ),
          if run.status is Running {
            @html.button(
              class="button secondary",
              disabled=page.busy,
              on_click=emit(Action(run.schedule_id, "stop")),
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
          @html.button(
            class="button secondary",
            on_click=emit(Log(run.log_path)),
            ui(locale, ViewLog),
          ),
          @html.p(class="schedule-log", ui(locale, LogLabel) + run.log_path),
        ]),
      )
    }
    content.push(
      @html.section(attrs=@html.Attrs::build().aria_label(title), section),
    )
  }
  @html.section(class="settings-page", [
    @html.div(class="settings-page-inner schedules-page", content),
  ])
}
