///|
fn schedule_status(status : @protocol.ScheduleRunStatus) -> String {
  match status {
    Running => "Running"
    Succeeded => "Completed"
    Failed(message) => "Failed · " + message
    Stopped => "Stopped"
    TimedOut => "Timed out"
    Interrupted => "Interrupted · host stopped; not retried"
  }
}

///|
fn schedules_page(dispatch : @cmd.Emit[Msg], model : Model) -> @html.Html {
  let page = model.schedules
  let emit = dispatch.map(msg => SchedulePage(msg))
  let content : Array[@html.Html] = [
    @html.div(class="settings-header", [
      @html.div(class="page-eyebrow", model.focused_device_name()),
      @html.h1("Scheduled tasks"),
      @html.p(
        class="settings-subtitle",
        "Run independent OpenSeek tasks while this host is open. Missed times are skipped. Up to 4 tasks can run together; each plan runs one task at a time.",
      ),
    ]),
    @html.div(class="schedule-toolbar", [
      @html.button(
        class="button",
        disabled=page.busy,
        on_click=emit(New),
        "New schedule",
      ),
      @html.button(
        class="button secondary",
        disabled=page.busy,
        on_click=emit(Poll),
        "Refresh",
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
          @html.h2("Run log"),
          @html.button(
            class="button secondary",
            on_click=emit(CloseLog),
            "Close log",
          ),
        ]),
        @html.p(class="schedule-log", path),
        @html.pre(class="schedule-log-content", text),
      ]),
    )
  }
  if page.form is Some(form) {
    let options = [@html.option(value="auto", "Automatically create")]
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
            "Edit schedule"
          } else {
            "New schedule"
          },
        ),
        field("Name", "name", form.name),
        @html.label(class="schedule-field", [
          @html.span("Working directory"),
          @html.select(
            attrs=@html.Attrs::build()
              .aria_label("Working directory")
              .value_prop(form.workspace.unwrap_or("auto")),
            on_change=emit.map(value => Field("workspace", value)),
            options,
          ),
        ]),
        @html.p(
          class="settings-subtitle",
          if form.workspace is None {
            "OpenSeek creates a dedicated folder on the first run and reuses it to save this task's files and results."
          } else {
            "This task runs in the selected project folder and can read and update its files."
          },
        ),
        @html.label(class="schedule-field", [
          @html.span("Task"),
          @html.textarea(
            value=form.task,
            on_input=emit.map(value => Field("task", value)),
            "",
          ),
        ]),
        @html.div(class="schedule-form-grid", [
          @html.label(class="schedule-field", [
            @html.span("Schedule"),
            @html.select(
              attrs=@html.Attrs::build()
                .aria_label("Schedule")
                .value_prop(if form.once { "once" } else { "every" }),
              on_change=emit.map(value => Field("timing", value)),
              [
                @html.option(value="every", "Every"),
                @html.option(value="once", "Once, in"),
              ],
            ),
          ]),
          field("Minutes", "minutes", form.minutes),
          field("Timeout (minutes)", "timeout", form.timeout),
        ]),
        field("Model (blank uses host default)", "model", form.model),
        @html.p(
          class="settings-subtitle",
          "Uses this host's API settings. Permission escalation is refused in unattended runs.",
        ),
        @html.p(
          class="settings-subtitle",
          "Save and run now executes once immediately without changing the schedule.",
        ),
        @html.div(class="schedule-toolbar", [
          @html.button(
            class="button",
            disabled=page.busy,
            on_click=emit(Save(true)),
            "Save and run now",
          ),
          @html.button(
            class="button secondary",
            disabled=page.busy,
            on_click=emit(Save(false)),
            "Save schedule",
          ),
          @html.button(
            class="button secondary",
            on_click=emit(CloseForm),
            "Cancel",
          ),
        ]),
      ]),
    )
  }
  if page.snapshot.entries.is_empty() {
    content.push(
      @html.p(
        class="schedule-empty",
        "No schedules yet. Create one to run a task later or at a fixed interval.",
      ),
    )
  }
  for entry in page.snapshot.entries {
    let running = page.snapshot.runs.any(run => {
      run.schedule_id == entry.id && run.status is Running
    })
    let timing = match entry.spec.timing {
      Every(n) => "Every \{n} min"
      Once(at) => "Once · " + schedule_time(at)
    }
    let next = match entry.next_at {
      Some(at) => "Next: " + schedule_time(at)
      None => if entry.enabled { "Waiting" } else { "Paused / finished" }
    }
    content.push(
      @html.div(class="schedule-card", [
        @html.h2(entry.spec.name),
        @html.p(
          class="schedule-meta",
          timing + " · " + (if entry.run_requested { "Queued" } else { next }),
        ),
        @html.p(
          class="schedule-meta",
          entry.spec.workspace.unwrap_or(
            "Automatically created working directory",
          ),
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
            "Run now",
          ),
          @html.button(
            class="button secondary",
            disabled=page.busy,
            on_click=emit(
              Action(entry.id, if entry.enabled { "pause" } else { "resume" }),
            ),
            if entry.enabled {
              "Pause"
            } else {
              "Resume"
            },
          ),
          @html.button(
            class="button secondary",
            disabled=page.busy,
            on_click=emit(Edit(entry.id)),
            "Edit",
          ),
          if running {
            @html.button(
              class="button secondary",
              disabled=page.busy,
              on_click=emit(Action(entry.id, "stop")),
              "Stop run",
            )
          } else {
            @html.button(
              class="button secondary",
              disabled=page.busy,
              on_click=emit(Action(entry.id, "delete")),
              "Delete",
            )
          },
        ]),
      ]),
    )
  }
  for running in [true, false] {
    let title = if running { "Running" } else { "Run history" }
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
            "No tasks are running."
          } else {
            "No finished runs yet."
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
            schedule_time(run.started_at) + " · " + schedule_status(run.status),
          ),
          if run.status is Running {
            @html.button(
              class="button secondary",
              disabled=page.busy,
              on_click=emit(Action(run.schedule_id, "stop")),
              "Stop run",
            )
          } else {
            @html.nothing
          },
          @html.button(
            class="button secondary",
            on_click=emit(Open(run)),
            "Open session",
          ),
          @html.button(
            class="button secondary",
            on_click=emit(Log(run.log_path)),
            "View log",
          ),
          @html.p(class="schedule-log", "Log: " + run.log_path),
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
