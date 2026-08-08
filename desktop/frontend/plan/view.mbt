// Three renderings of the same checklist, at three altitudes: a meter on a
// folded run, the full card inside an expanded `plan` call, and the standing
// plan docked above the composer. They share the row and meter builders below
// so the three cannot drift apart.

///|
/// The card body for a `plan` tool call: a progress meter over the checklist,
/// in place of the raw arguments JSON.
///
/// When the call reads as an evolution of `baseline` (the previous applied
/// plan call), steps that changed carry a change marker and steps this update
/// dropped stay visible as struck-through ghost rows. A wholesale rewrite
/// would mark nearly every row, so it gets a single rewrite note instead.
pub fn card(steps : Array[Step], baseline? : Array[Step]) -> @html.Html {
  if steps.is_empty() {
    return @html.div(class="plan-args", [
      @html.span(class="plan-cleared", "plan cleared"),
    ])
  }
  let diff_base = if evolves(steps, baseline) { baseline } else { None }
  let rows : Array[@html.Html] = [
    for index, step in steps => {
      step_row(
        status=step.status,
        number="\{index + 1}.",
        title=step.title,
        delta?=delta(step, diff_base),
      )
    }
  ]
  for step in dropped(steps, diff_base) {
    rows.push(dropped_row(step))
  }
  let body : Array[@html.Html] = [progress_view(steps)]
  if diff_base is None && baseline is Some(previous) && !previous.is_empty() {
    body.push(
      @html.div(
        class="plan-rewrite-note",
        "rewritten — replaces the previous plan",
      ),
    )
  }
  body.push(@html.ul(class="plan-steps", rows))
  @html.div(class="plan-args", body)
}

///|
/// The meter for a folded run of activity, showing the plan as that run left
/// it — so a collapsed turn still reads as the plan filling up. `nothing`
/// when the run touched no plan.
pub fn fold_progress(items : Array[@transcript.TranscriptItem]) -> @html.Html {
  guard latest(items) is Some(steps) else { return @html.nothing }
  progress_view(steps, mini=true)
}

///|
/// The standing plan, docked above the composer: one line naming the active
/// step, expanding to the whole checklist. No change markers here — the panel
/// answers "what is the plan", while a call's card answers "what did this
/// update change".
///
/// The slot renders even with no plan to show, so the composer's child list
/// keeps a fixed shape while a plan appears and clears mid-turn; an empty slot
/// collapses in CSS. The `details` carries no `open` attribute, so whether the
/// reader expanded it is DOM state that survives every re-render.
pub fn panel(items : Array[@transcript.TranscriptItem]) -> @html.Html {
  guard latest(items) is Some(steps) else {
    return @html.div(class="plan-panel-slot", ([] : Array[@html.Html]))
  }
  let completed = completed_count(steps)
  let (glyph, active) = if active_step(steps) is Some(step) {
    ("◐", step.title)
  } else if completed == steps.length() {
    ("✓", "all steps done")
  } else {
    ("○", "no step in progress")
  }
  let rows : Array[@html.Html] = [
    for index, step in steps => {
      step_row(status=step.status, number="\{index + 1}.", title=step.title)
    }
  ]
  @html.div(class="plan-panel-slot", [
    @html.details(class="plan-panel", [
      @html.summary(class="plan-panel-summary", [
        @html.span(class="plan-panel-icon", glyph),
        @html.span(class="plan-panel-title", "Plan"),
        @html.span(class="plan-panel-active", title=active, active),
        progress_view(steps, mini=true),
        @html.span(class="plan-panel-caret", ""),
      ]),
      @html.ul(class="plan-steps", rows),
    ]),
  ])
}

///|
/// The progress meter: a proportional fill for the completed steps, then one
/// step's worth of lighter fill for the step in progress, plus the tally. The
/// completed fill turns green only once every step is completed, so a finished
/// plan reads differently from one merely underway. `mini` is the compact form
/// that rides a folded summary line, where its width must not grow with the
/// step count.
fn progress_view(steps : Array[Step], mini? : Bool = false) -> @html.Html {
  let total = steps.length()
  let completed = completed_count(steps)
  let fills : Array[@html.Html] = []
  if completed > 0 {
    let fill_class = if completed == total {
      "plan-progress-fill complete"
    } else {
      "plan-progress-fill"
    }
    fills.push(
      @html.div(
        class=fill_class,
        style=["width: \{completed * 100 / total}%"],
        "",
      ),
    )
  }
  if active_step(steps) is Some(_) {
    fills.push(
      @html.div(
        class="plan-progress-fill active",
        style=["width: \{100 / total}%"],
        "",
      ),
    )
  }
  @html.div(
    class=if mini { "plan-progress mini" } else { "plan-progress" },
    title=summary_line(steps),
    [
      @html.div(class="plan-progress-track", fills),
      @html.span(class="plan-progress-count", "\{completed}/\{total}"),
    ],
  )
}

///|
/// One checklist row, shared by the card and the panel so they cannot drift:
/// a status cell, the step number, the title, and an optional change marker.
/// The status doubles as the row's CSS class.
fn step_row(
  status~ : Status,
  number~ : String,
  title~ : String,
  delta? : String,
) -> @html.Html {
  let cells : Array[@html.Html] = [
    status_cell(status),
    @html.span(class="step-num", number),
    @html.span(class="step-title", title),
  ]
  if delta is Some(marker) {
    cells.push(@html.span(class="step-delta step-delta-\{marker}", marker))
  }
  @html.li(class="plan-step \{status_class(status)}", cells)
}

///|
/// A step the update dropped, kept visible as a ghost row.
fn dropped_row(step : Step) -> @html.Html {
  @html.li(class="plan-step dropped", [
    @html.span(class="step-icon", title="dropped", "✕"),
    @html.span(class="step-title", step.title),
    @html.span(class="step-delta step-delta-dropped", "dropped"),
  ])
}

///|
/// The leading cell of a row: a glyph for the statuses this build knows, or
/// the literal word for anything else. Disguising an unknown status as a
/// pending ring would misread e.g. a blocked step as untouched.
fn status_cell(status : Status) -> @html.Html {
  match status {
    Pending => @html.span(class="step-icon", title="pending", "○")
    InProgress => @html.span(class="step-icon", title="in_progress", "◐")
    Completed => @html.span(class="step-icon", title="completed", "✓")
    Other(word) => @html.span(class="step-status", word)
  }
}

///|
/// A row's status class. An unknown status becomes `other` rather than its own
/// word: the word is unvalidated model output, and it is already shown as
/// text in the row's leading cell.
fn status_class(status : Status) -> String {
  match status {
    Pending => "pending"
    InProgress => "in_progress"
    Completed => "completed"
    Other(_) => "other"
  }
}
