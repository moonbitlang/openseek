///|
/// A job's status text and CSS class, decided together: a cleanup failure
/// overrides the process state in both.
fn job_status(
  locale? : @i18n.Locale = English,
  job : @wire.JobRecord,
) -> (String, String) {
  if job.cleanup_error is Some(_) {
    return (ui(locale, CleanupFailed), "failed")
  }
  match job.state {
    Running => (ui(locale, RunningLabel), "running")
    Stopping => (ui(locale, StoppingLabel), "stopping")
    Exited(0) => (ui(locale, CompletedLabel), "completed")
    Exited(code) =>
      (dynamic_text(locale, DFailedExit(code.to_string())), "failed")
    Stopped("user") => (ui(locale, StoppedLabel), "stopped")
    Stopped("session_ended") => (ui(locale, SessionEnded), "stopped")
    Stopped("output_limit") => (ui(locale, OutputLimit), "failed")
    Stopped("time_limit") => (ui(locale, TimeLimit), "failed")
    Stopped("capture_failed") => (ui(locale, CaptureFailed), "failed")
    Stopped(reason) =>
      (dynamic_text(locale, DStopped(reason.to_string())), "stopped")
    Interrupted => (ui(locale, InterruptedLabel), "stopped")
  }
}

///|
/// The host normalizes output paths: POSIX double-leading slashes collapse to
/// one, so a normalized // prefix here denotes a Windows UNC path.
fn tail_command(path : String, follow? : Bool = true) -> String {
  if (path.length() >= 2 && path[1] == ':') ||
    path.has_prefix("\\\\") ||
    path.has_prefix("//") {
    "Get-Content -LiteralPath '" +
    path.replace_all(old="'", new="''") +
    "' -Tail 100" +
    (if follow { " -Wait" } else { "" })
  } else {
    "tail -n 100" +
    (if follow { " -f" } else { "" }) +
    " -- '" +
    path.replace_all(old="'", new="'\\''") +
    "'"
  }
}

///|
extern "js" fn timestamp(value : Double, locale : String) -> String =
  #| (value, locale) => new Date(value).toLocaleString(locale)

///|
fn job_timing(
  locale? : @i18n.Locale = English,
  job : @wire.JobRecord,
) -> String {
  if job.state.is_terminal() {
    match job.finished_at_ms {
      Some(end) => {
        let seconds = ((end - job.started_at_ms).to_double().max(0) / 1000).to_int()
        dynamic_text(
          locale,
          DEnded(
            timestamp(end.to_double(), locale.tag()).to_string(),
            seconds.to_string(),
          ),
        )
      }
      None => ui(locale, EndTimeUnavailable)
    }
  } else {
    let seconds = ((@interop.now_ms() - job.started_at_ms.to_double()).max(0) /
    1000).to_int()
    dynamic_text(locale, DRunningTime(seconds.to_string()))
  }
}

///|
/// Whether the output pane has been scrolled far enough from the bottom that
/// following it would yank the reader away. A missing pane never follows.
fn away_from_end() -> Bool {
  match @dom.document().get_element_by_id("bg-job-output").to_option() {
    Some(el) =>
      el.get_scroll_height() - el.get_scroll_top() - el.get_client_height() >
      24.0
    None => false
  }
}

///|
pub fn panel(
  locale? : @i18n.Locale = English,
  state : State,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  let running = state.jobs
    .filter(view => !view.job.state.is_terminal())
    .length()
  let header = @html.div(class="jobs-heading", [
    @html.div([
      @html.h3(ui(locale, BackgroundJobs)),
      @html.div(class="jobs-summary", [
        @html.span(
          class=if running > 0 {
            "jobs-summary-active"
          } else {
            "jobs-summary-idle"
          },
          "\{running} in progress",
        ),
        @html.span("\{state.jobs.length() - running} in history"),
      ]),
    ]),
    @html.button(
      class="jobs-action",
      on_click=emit(Poll),
      disabled=state.listing,
      ui(locale, RefreshLabel),
    ),
  ])
  let body : Array[@html.Html] = [header]
  if state.owner is Some(owner) {
    body.push(
      @html.div(
        class="jobs-host",
        dynamic_text(
          locale,
          DHost(
            owner.channel.uri_authority().to_string(),
            owner.scope.session.to_string(),
          ),
        ),
      ),
    )
  }
  if state.owner is Some(_) && !state.active {
    body.push(
      @html.div(class="jobs-error", ui(locale, DisconnectedDescription)),
    )
  }
  if state.error is Some(error) {
    body.push(
      @html.div(
        class="jobs-error",
        attrs=@html.Attrs::build().role("alert"),
        error,
      ),
    )
  }
  for warning in state.warnings {
    body.push(@html.div(class="jobs-error", warning))
  }
  if state.jobs.is_empty() {
    body.push(
      @html.div(class="jobs-empty", [
        @html.h3(
          if state.listing {
            ui(locale, LoadingJobs)
          } else {
            ui(locale, NoJobs)
          },
        ),
        @html.p(ui(locale, JobsDescription)),
      ]),
    )
  } else {
    let rows : Array[@html.Html] = []
    for terminal in [false, true] {
      let group = state.jobs.filter(view => {
        view.job.state.is_terminal() == terminal
      })
      if group.is_empty() && (!terminal || state.next_offset is None) {
        continue
      }
      let title = if terminal {
        ui(locale, HistoryLabel)
      } else {
        ui(locale, InProgress)
      }
      let cards = group.map(view => {
        let job = view.job
        let selected = state.selected == Some((job.generation, job.id))
        let (status_label, status_class) = job_status(locale~, job)
        @html.button(
          class="jobs-row jobs-row-\{status_class}" +
            (if selected { " selected" } else { "" }),
          attrs=@html.Attrs::build().aria_pressed(selected.to_string()),
          title=job.command,
          on_click=emit(Select(job.generation, job.id)),
          [
            @html.div(class="jobs-row-head", [
              @html.span(
                class="jobs-id",
                title=job.id,
                short_job_id(job.id, state.jobs),
              ),
              @html.span(
                class="jobs-status jobs-status-\{status_class}",
                status_label,
              ),
            ]),
            @html.div(
              class="jobs-command",
              job.description.unwrap_or(job.command),
            ),
            @html.div(
              class="jobs-row-meta",
              "\{job_timing(locale~, job)} · \{job.output_bytes} B",
            ),
          ],
        )
      })
      let label = [
        @html.span(title),
        @html.span(class="jobs-group-count", group.length().to_string()),
      ]
      let content : Array[@html.Html] = [@html.div(class="jobs-cards", cards)]
      if terminal && state.next_offset is Some(_) {
        content.push(
          @html.button(
            class="jobs-action jobs-more",
            disabled=state.listing,
            on_click=emit(More),
            ui(locale, LoadOlder),
          ),
        )
      }
      rows.push(
        @html.div(
          class="jobs-group",
          attrs=@html.Attrs::build().role("group").aria_label(title),
          if terminal {
            [
              @html.button(
                class="jobs-group-title jobs-history-toggle",
                attrs=@html.Attrs::build()
                  .aria_expanded(state.history_expanded.to_string())
                  .aria_controls("jobs-history-content"),
                on_click=emit(ToggleHistory),
                label,
              ),
              @html.div(
                id="jobs-history-content",
                hidden=!state.history_expanded,
                content,
              ),
            ]
          } else {
            [@html.h4(class="jobs-group-title", label), ..content]
          },
        ),
      )
    }
    body.push(
      @html.div(
        class="jobs-list",
        attrs=@html.Attrs::build().aria_label(ui(locale, BackgroundJobs)),
        rows,
      ),
    )
    if selected_job(state) is Some(view) {
      let job = view.job
      let (status_label, status_class) = job_status(locale~, job)
      let details : Array[@html.Html] = [
        @html.div(class="jobs-detail-title", [
          @html.strong(title=job.id, short_job_id(job.id, state.jobs)),
          @html.span(
            class="jobs-status jobs-status-\{status_class}",
            status_label,
          ),
        ]),
        @html.pre(class="jobs-full-command", job.command),
        @html.div(
          class="jobs-detail-meta",
          dynamic_text(
            locale,
            DStarted(
              timestamp(job.started_at_ms.to_double(), locale.tag()).to_string(),
            ),
          ),
        ),
      ]
      if job.cwd is Some(cwd) {
        details.push(
          @html.div(
            class="jobs-detail-meta",
            dynamic_text(locale, DWorkingDirectory(cwd.to_string())),
          ),
        )
      }
      details.push(
        @html.div(class="jobs-detail-meta", job_timing(locale~, job)),
      )
      if !job.state.is_terminal() {
        let activity = match job.last_output_at_ms {
          Some(last) =>
            dynamic_text(
              locale,
              DLastOutput(
                ((@interop.now_ms() - last.to_double()).max(0) / 1000)
                .to_int()
                .to_string(),
              ),
            )
          None => ui(locale, NoOutputLabel)
        }
        details.push(@html.div(class="jobs-detail-meta", activity))
      }
      let actions : Array[@html.Html] = [
        @html.button(
          class="jobs-action",
          on_click=@clipboard.copy(Text(job.id)),
          ui(locale, CopyId),
        ),
      ]
      if view.output_path is Some(path) {
        details.push(
          @html.div(class="jobs-path", [@html.code(title=path, path)]),
        )
        actions.append([
          @html.button(
            class="jobs-action",
            on_click=@clipboard.copy(Text(path)),
            ui(locale, CopyPath),
          ),
          @html.button(
            class="jobs-action",
            on_click=@clipboard.copy(
              Text(tail_command(path, follow=!job.state.is_terminal())),
            ),
            ui(locale, CopyTail),
          ),
          @html.button(
            class="jobs-action",
            on_click=emit(Reload),
            ui(locale, ReloadTail),
          ),
        ])
      }
      if view.output_path is Some(_) && !job.state.is_terminal() {
        actions.push(
          @html.button(
            class="jobs-action",
            on_click=emit(ToggleFollow),
            attrs=@html.Attrs::build().aria_pressed(state.follow.to_string()),
            if state.follow {
              ui(locale, PauseLabel)
            } else {
              ui(locale, FollowOutput)
            },
          ),
        )
      }
      if !job.state.is_terminal() {
        actions.push(
          @html.button(
            class="jobs-action jobs-stop",
            disabled=!view.controllable ||
              state.stopping ||
              job.state is Stopping,
            on_click=emit(Stop),
            if state.stopping || job.state is Stopping {
              ui(locale, StoppingLabel)
            } else {
              ui(locale, StopJob)
            },
          ),
        )
      }
      details.push(@html.div(class="jobs-toolbar", actions))
      if @transcript_component.program_calls_view(
          locale~,
          job.data,
          "job/\{job.generation}/\{job.id}",
          origin=if job.state.is_terminal() { Terminal } else { Live },
        )
        is Some(calls) {
        details.push(calls)
      }
      for
        error in [
          view.error,
          job.output_error,
          job.persistence_error,
          job.cleanup_error,
          state.read_error,
          state.control_error,
        ] {
        if error is Some(error) {
          details.push(
            @html.div(
              class="jobs-error",
              attrs=@html.Attrs::build().role("alert"),
              error,
            ),
          )
        }
      }
      if job.output_truncated {
        details.push(@html.div(class="jobs-error", ui(locale, TruncatedOutput)))
      }
      if job.invalid_utf8 {
        details.push(@html.div(class="jobs-error", ui(locale, InvalidUtf8)))
      }
      let note = if view.output_path is None {
        ui(locale, NoLogFile)
      } else if state.read_error is Some(_) {
        ui(locale, OutputUnavailable)
      } else if job.state.is_terminal() {
        if output_complete(state, job) && !state.reading {
          ui(locale, OutputEnded)
        } else {
          ui(locale, LoadingRemaining)
        }
      } else if state.follow {
        if state.catching_up {
          ui(locale, CatchingUp)
        } else {
          ui(locale, FollowingOutput)
        }
      } else {
        ui(locale, PausedOutput)
      }
      let note = if state.clipped &&
        view.output_path is Some(_) &&
        state.read_error is None {
        note +
        " · Showing recent output. The file contains the full retained log."
      } else {
        note
      }
      details.push(@html.div(class="jobs-output-note", note))
      if view.output_path is Some(_) {
        details.push(
          @html.div(
            id="bg-job-output",
            class="jobs-output",
            attrs=@html.Attrs::build()
              .tabindex(0)
              .role("region")
              .aria_label(ui(locale, JobOutput))
              .on_scroll(_ => {
                if state.follow && away_from_end() {
                  emit(Pause)
                } else {
                  @cmd.none
                }
              }),
            [
              @html.pre(
                if state.text.is_empty() {
                  if state.reading {
                    ui(locale, LoadingOutput)
                  } else if job.state.is_terminal() {
                    ui(locale, NoRetainedOutput)
                  } else {
                    ui(locale, NoOutputYet)
                  }
                } else {
                  state.text
                },
              ),
            ],
          ),
        )
      }
      details.push(
        @html.div(class="jobs-footnote", ui(locale, StopDescription)),
      )
      body.push(@html.div(class="jobs-detail", details))
    }
  }
  @html.div(class="jobs-panel", body)
}

///|
/// Use random suffix bits: UUIDv7 prefixes mostly contain the shared date.
/// Expand on a collision among loaded IDs; shortened labels are never handles.
/// Legacy bg-N IDs stay intact, including historical records from older builds.
fn short_job_id(id : String, jobs : Array[@protocol.JobView]) -> String {
  guard id.length() == 36 &&
    id[8] == '-' &&
    id[13] == '-' &&
    id[18] == '-' &&
    id[23] == '-' else {
    return id
  }
  let mut width = 8
  while width < id.length() {
    let suffix = id[id.length() - width:].to_owned()
    if !jobs.any(view => view.job.id != id && view.job.id.has_suffix(suffix)) {
      return "bg-…" + suffix
    }
    width += 4
  }
  id
}
