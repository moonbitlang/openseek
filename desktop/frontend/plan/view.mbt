// Two renderings of the same checklist, at two altitudes: a meter riding
// the `plan` call's own transcript row, and the full card inside that row
// once expanded. They share the row and meter builders below so the two
// cannot drift apart.
//
// There is deliberately no third, standing rendering. A plan is a durable
// tool call and reads as one, in the turn that made it; hoisting the latest
// one into permanent chrome showed the same checklist twice and put a copy of
// the transcript somewhere the transcript is not.

///|
/// The card body for a `plan` tool call: a progress meter over the checklist,
/// in place of the raw arguments JSON.
///
/// It reports the call, not the difference from the call before it. The tool
/// sends a whole snapshot every time and its steps carry no identity — no id,
/// and titles the model may repeat — so which step of one call *is* which
/// step of the next is a correspondence the protocol never records. Marking
/// what changed meant guessing it.
pub fn card(steps : Array[Step]) -> @html.Html {
  if steps.is_empty() {
    return @html.div(class="plan-args", [
      @html.span(class="plan-cleared", "plan cleared"),
    ])
  }
  let rows : Array[@html.Html] = [
    for index, step in steps => {
      step_row(status=step.status, number="\{index + 1}.", title=step.title)
    }
  ]
  @html.div(class="plan-args", [
    progress_view(steps),
    @html.ul(class="plan-steps", rows),
  ])
}

///|
/// The meter riding a `plan` call's own row, showing the plan as that call
/// left it, so the checklist reads as it fills up without unfolding anything.
/// `nothing` for every other call, and for a plan call that did not apply.
pub fn fold_progress(call : @transcript.ToolCall) -> @html.Html {
  guard latest([call]) is Some(steps) else { return @html.nothing }
  progress_view(steps, mini=true)
}

///|
/// The progress meter: a proportional fill for the completed steps, then one
/// step's worth of lighter fill for the step in progress, plus the tally. The
/// completed fill turns green only once every step is completed, so a finished
/// plan reads differently from one merely underway. `mini` is the compact form
/// that rides a one-line row, where its width must not grow with the step
/// count.
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
      @html.div(class=fill_class, style=[fill_width(completed, total)], ""),
    )
  }
  if active_step(steps) is Some(_) {
    fills.push(
      @html.div(
        class="plan-progress-fill active",
        style=[fill_width(1, total)],
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
/// `part` of `total` as the progress fill's local CSS variable, in tenths of a
/// percent. The stylesheet owns the actual width property.
///
/// A whole percent truncated to nothing exactly where the bar had something
/// to say: `decode` tolerates plans of up to `MAX_RENDERED_STEPS` steps so a
/// newer engine's raised caps still render, and at 150 steps one step is
/// `100 / 150 == 0` — an active plan drawn as an empty track, which is a
/// state that is not true rather than a rounding error. Tenths keep the
/// smallest share a plan can have (one step of `MAX_RENDERED_STEPS`) at 0.5%,
/// and stay integer arithmetic, so no width is ever a float's idea of one.
fn fill_width(part : Int, total : Int) -> String {
  let tenths = part * 1000 / total
  "--plan-progress-width: \{tenths / 10}.\{tenths % 10}%"
}

///|
/// One checklist row, used by the card so both altitudes cannot drift:
/// a status cell, the step number, and the title. The status doubles as the
/// row's CSS class.
fn step_row(status~ : Status, number~ : String, title~ : String) -> @html.Html {
  @html.li(class="plan-step \{status_class(status)}", [
    status_cell(status),
    @html.span(class="step-num", number),
    @html.span(class="step-title", title),
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
