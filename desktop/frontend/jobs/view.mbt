///|
fn status_label(state : @wire.JobState) -> String {
  match state {
    Running => "Running"
    Stopping => "Stopping"
    Exited(0) => "Completed"
    Exited(code) => "Failed · exit \{code}"
    Stopped("user") => "Stopped"
    Stopped("session_ended") => "Session ended"
    Stopped("output_limit") => "Stopped · output limit reached"
    Stopped("time_limit") => "Stopped · time limit reached"
    Stopped("capture_failed") => "Stopped · output capture failed"
    Stopped(reason) => "Stopped · \{reason}"
    Interrupted => "Interrupted"
  }
}

///|
fn status_class(state : @wire.JobState) -> String {
  match state {
    Running | Stopping => "running"
    Exited(0) => "completed"
    Exited(_) | Stopped("capture_failed" | "output_limit" | "time_limit") =>
      "failed"
    _ => "stopped"
  }
}

///|
/// The host normalizes output paths: POSIX double-leading slashes collapse to
/// one, so a normalized // prefix here denotes a Windows UNC path.
fn tail_command(path : String) -> String {
  if (path.length() >= 2 && path[1] == ':') ||
    path.has_prefix("\\\\") ||
    path.has_prefix("//") {
    "Get-Content -LiteralPath '" +
    path.replace_all(old="'", new="''") +
    "' -Tail 100 -Wait"
  } else {
    "tail -n 100 -f -- '" + path.replace_all(old="'", new="'\\''") + "'"
  }
}

///|
extern "js" fn timestamp(value : Double) -> String =
  #| value => new Date(value).toLocaleString()

///|
extern "js" fn away_from_end() -> Bool =
  #| () => { const el = document.getElementById("bg-job-output"); return !!el && el.scrollHeight - el.scrollTop - el.clientHeight > 24; }

///|
pub fn panel(state : State, emit : @cmd.Emit[Msg]) -> @html.Html {
  let running = state.jobs
    .filter(view => !view.job.state.is_terminal())
    .length()
  let header = @html.div(class="jobs-heading", [
    @html.div([
      @html.h3("Background jobs"),
      @html.span(
        class="jobs-summary",
        "\{running} active · \{state.jobs.length()} loaded",
      ),
    ]),
    @html.button(
      class="jobs-action",
      on_click=emit(Poll),
      disabled=state.listing,
      "Refresh",
    ),
  ])
  let body : Array[@html.Html] = [header]
  if state.owner is Some(owner) {
    body.push(
      @html.div(
        class="jobs-host",
        "Host: \{owner.channel.uri_authority()} · \{owner.scope.session}",
      ),
    )
  }
  if state.owner is Some(_) && !state.active {
    body.push(
      @html.div(
        class="jobs-error",
        "Disconnected. Output remains on the host; reconnect to refresh.",
      ),
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
            "Loading jobs…"
          } else {
            "No background jobs yet"
          },
        ),
        @html.p(
          "Commands appear here when they move to the background. Their output files stay with this conversation.",
        ),
      ]),
    )
  } else {
    let rows = state.jobs.map(view => {
      let job = view.job
      let selected = state.selected == Some((job.generation, job.id))
      @html.button(
        class="jobs-row" + (if selected { " selected" } else { "" }),
        attrs=@html.Attrs::build().aria_pressed(selected.to_string()),
        title=job.command,
        on_click=emit(Select(job.generation, job.id)),
        [
          @html.div(class="jobs-row-head", [
            @html.span(class="jobs-id", job.id),
            @html.span(
              class="jobs-status jobs-status-\{status_class(job.state)}",
              status_label(job.state),
            ),
          ]),
          @html.div(
            class="jobs-command",
            job.description.unwrap_or(job.command),
          ),
          @html.div(
            class="jobs-row-meta",
            "\{timestamp(job.backgrounded_at_ms.to_double())} · \{job.output_bytes} B",
          ),
        ],
      )
    })
    if state.next_offset is Some(_) {
      rows.push(
        @html.button(
          class="jobs-action jobs-more",
          disabled=state.listing,
          on_click=emit(More),
          "Load older jobs",
        ),
      )
    }
    body.push(
      @html.div(
        class="jobs-list",
        attrs=@html.Attrs::build().aria_label("Background jobs"),
        rows,
      ),
    )
    if selected_job(state) is Some(view) {
      let job = view.job
      let details : Array[@html.Html] = [
        @html.div(class="jobs-detail-title", [
          @html.strong(job.id),
          @html.span(
            class="jobs-status jobs-status-\{status_class(job.state)}",
            status_label(job.state),
          ),
        ]),
        @html.pre(class="jobs-full-command", job.command),
        @html.div(
          class="jobs-detail-meta",
          "Started \{timestamp(job.started_at_ms.to_double())}",
        ),
      ]
      if job.cwd is Some(cwd) {
        details.push(
          @html.div(class="jobs-detail-meta", "Working directory: \{cwd}"),
        )
      }
      let end = job.finished_at_ms
        .map(n => n.to_double())
        .unwrap_or(@interop.now_ms())
      let seconds = ((end - job.started_at_ms.to_double()).max(0) / 1000).to_int()
      let activity = match job.last_output_at_ms {
        Some(last) =>
          "Last output \{((@interop.now_ms() - last.to_double()).max(0) / 1000).to_int()}s ago"
        None => "No output yet"
      }
      details.push(
        @html.div(
          class="jobs-detail-meta",
          "Elapsed \{seconds}s · \{activity}",
        ),
      )
      let actions : Array[@html.Html] = []
      if view.output_path is Some(path) {
        details.push(
          @html.div(class="jobs-path", [@html.code(title=path, path)]),
        )
        actions.append([
          @html.button(
            class="jobs-action",
            on_click=@clipboard.copy(Text(path)),
            "Copy path",
          ),
          @html.button(
            class="jobs-action",
            on_click=@clipboard.copy(Text(tail_command(path))),
            "Copy tail command",
          ),
          @html.button(
            class="jobs-action",
            on_click=emit(ToggleFollow),
            attrs=@html.Attrs::build().aria_pressed(state.follow.to_string()),
            if state.follow {
              "Pause"
            } else {
              "Follow output"
            },
          ),
          @html.button(
            class="jobs-action",
            on_click=emit(Reload),
            "Reload tail",
          ),
        ])
      }
      actions.push(
        @html.button(
          class="jobs-action jobs-stop",
          disabled=!view.controllable || state.stopping,
          on_click=emit(Stop),
          if state.stopping {
            "Stopping…"
          } else {
            "Stop job"
          },
        ),
      )
      details.push(@html.div(class="jobs-toolbar", actions))
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
        details.push(
          @html.div(
            class="jobs-error",
            "Output capture reached its limit; the retained log is truncated.",
          ),
        )
      }
      if job.invalid_utf8 {
        details.push(
          @html.div(
            class="jobs-error",
            "Output contained invalid UTF-8; replacement characters were saved.",
          ),
        )
      }
      let note = if view.output_path is None {
        "No retained log file for this job."
      } else if state.read_error is Some(_) {
        "Output unavailable · reload to retry."
      } else if state.follow {
        if state.catching_up {
          "Catching up with output…"
        } else {
          "Following output"
        }
      } else {
        "Paused · output continues to the file"
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
              .aria_label("Job output")
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
                    "Loading output…"
                  } else {
                    "No output yet."
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
        @html.div(
          class="jobs-footnote",
          "Stop controls the direct process. Logs are retained with the session.",
        ),
      )
      body.push(@html.div(class="jobs-detail", details))
    }
  }
  @html.div(class="jobs-panel", body)
}
