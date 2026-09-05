// The workflows panel: every run this conversation announced, each with one
// row per subagent, the way a reader follows a fan-out — launch order, what
// each child is, whether it is still running, what it cost, and a click that
// opens the child's own transcript.
//
// It is a dock tab, not a dock lane. The lane dock above the composer is the
// glance surface for what is running RIGHT NOW and drops a lane the moment
// its child ends; a run is something to look back over, so its rows stay
// until the conversation is dropped. Both are fed by the same brackets, and a
// row here and a lane there for the same child agree by construction.

///|
/// What the panel can do: open a child's transcript. Root-owned, since
/// switching sessions allocates state in other packages.
pub(all) struct Actions {
  open_child : (String) -> @cmd.Cmd
}

///|
/// The panel body. Always rendered — CSS shows it only while its tab is
/// active — so the right panel's child order stays structural.
pub fn panel(runs : Array[Run], actions : Actions) -> @html.Html {
  if runs.is_empty() {
    return @html.div(class="workflow-panel workflow-panel-empty", [
      @html.p(
        class="workflow-empty",
        "No workflows in this conversation yet. A snippet that sets `subrun: true` and runs a workflow will appear here, with a row per subagent.",
      ),
    ])
  }
  // Newest run first: the one a reader is most likely watching.
  let ordered = runs.copy()
  ordered.rev_in_place()
  @html.div(class="workflow-panel", ordered.map(run => run_view(run, actions)))
}

///|
fn run_view(run : Run, actions : Actions) -> @html.Html {
  let rows = run.ordered_rows()
  let running = run.running()
  let state = if run.closed {
    "finished"
  } else if running > 0 {
    "running"
  } else {
    "open"
  }
  let summary : Array[@html.Html] = [
    @html.span(class="workflow-run-id", run.id),
    @html.span(class="workflow-run-state workflow-run-state-\{state}", state),
    @html.span(
      class="workflow-run-count",
      "\{rows.length()} of \{run.child_count} subagent\{plural(rows.length())}",
    ),
  ]
  if run.tokens() > 0 {
    summary.push(
      @html.span(
        class="workflow-run-tokens",
        "\{@labels.compact_count(run.tokens())} tok",
      ),
    )
  }
  if run.cost_usd() is Some(cost) {
    summary.push(@html.span(class="workflow-run-cost", money(cost)))
  }
  @html.section(class="workflow-run workflow-run-\{state}", [
    @html.header(class="workflow-run-head", summary),
    @html.div(
      class="workflow-rows",
      rows.map(row => row_view(row, closed=run.closed, actions)),
    ),
  ])
}

///|
fn row_view(row : Row, closed~ : Bool, actions : Actions) -> @html.Html {
  let (status, status_class) = row_status(row, closed~)
  let detail : Array[@html.Html] = []
  if row.phase is Some(phase) {
    detail.push(@html.span(class="workflow-row-phase", phase))
  }
  if row.steps > 0 {
    detail.push(
      @html.span(
        class="workflow-row-steps",
        "\{row.steps} step\{plural(row.steps)}",
      ),
    )
  }
  if row.tokens > 0 {
    detail.push(
      @html.span(
        class="workflow-row-tokens",
        "\{@labels.compact_count(row.tokens)} tok",
      ),
    )
  }
  if row.cost_usd is Some(cost) {
    detail.push(@html.span(class="workflow-row-cost", money(cost)))
  }
  if row.started_at is Some(started) && row.finished_at is Some(finished) {
    detail.push(
      @html.span(class="workflow-row-duration", duration(finished - started)),
    )
  }
  let label = if row.label.is_empty() { row.child } else { row.label }
  @html.button(
    class="workflow-row workflow-row-\{status_class}",
    title="Open \{row.child}",
    on_click=(actions.open_child)(row.child),
    [
      @html.span(class="workflow-row-mark", ""),
      @html.span(class="workflow-row-kind", row.kind),
      @html.span(class="workflow-row-label", label),
      @html.span(class="workflow-row-status", status),
      @html.span(class="workflow-row-detail", detail),
    ],
  )
}

///|
fn plural(n : Int) -> String {
  if n == 1 {
    ""
  } else {
    "s"
  }
}

///|
/// Dollars to the cent, the way a cost line reads; a fraction of a cent is
/// still shown as one, never as zero.
fn money(cost : Double) -> String {
  let cents = (cost * 100.0 + 0.5).to_int()
  let cents = if cost > 0.0 && cents == 0 { 1 } else { cents }
  let dollars = cents / 100
  let rest = cents % 100
  let rest = if rest < 10 { "0\{rest}" } else { "\{rest}" }
  "$\{dollars}.\{rest}"
}

///|
/// A wall-clock span in the unit a reader thinks in.
fn duration(ms : Double) -> String {
  let seconds = (ms / 1000.0).to_int()
  if seconds < 60 {
    "\{seconds}s"
  } else if seconds < 3600 {
    "\{seconds / 60}m \{seconds % 60}s"
  } else {
    "\{seconds / 3600}h \{seconds % 3600 / 60}m"
  }
}
