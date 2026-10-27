// Whitebox tests for the parts of the run state that only this package uses:
// a row's status cell (`row_status`) and the run's token and unaccounted
// totals. They are package internals rendered by `view.mbt`, so the tests
// that pin their behavior live inside the package; the blackbox tests in
// `state_test.mbt` keep covering the exported surface.

///|
/// The fixture: one announced run reserving ordinals 5..36.
fn announced_run() -> Array[Run] {
  opened([], id="wf-5", session="run7", first_child=5, child_count=32)
}

///|
test "a sub-run bracket makes a row only for a child in the run's block" {
  let runs = announced_run()
  // Ordinal 5 is the run's; ordinal 2 is an ordinary explore child of the
  // same conversation, and none of this package's business.
  let runs = child_opened(runs, id="sr-5", kind="explore", label="scout:x")
  let runs = child_opened(runs, id="sr-2", kind="explore", label="elsewhere")
  inspect(runs[0].rows.length(), content="1")
  let row = runs[0].rows[0]
  inspect(row.child, content="run7-sr-5")
  inspect(row.ordinal, content="5")
  debug_inspect(row.status, content="None")
  inspect(runs[0].running(), content="1")
  // The finish bracket carries the terminal and the spend.
  let runs = child_closed(
    runs,
    id="sr-5",
    status="captured",
    steps=12,
    tokens=3400,
  )
  debug_inspect(runs[0].rows[0].status, content="Some(\"captured\")")
  inspect(runs[0].rows[0].steps, content="12")
  inspect(runs[0].running(), content="0")
  inspect(runs[0].tokens(), content="3400")
}

///|
test "a row still running after the run closed reads as unresolved" {
  let runs = child_opened(announced_run(), id="sr-5", kind="explore", label="a")
  let row = runs[0].rows[0]
  debug_inspect(
    row_status(locale=English, row, closed=false),
    content="(\"running\", \"running\")",
  )
  debug_inspect(
    row_status(locale=English, row, closed=true),
    content="(\"unresolved\", \"failed\")",
  )
  let done = child_closed(runs, id="sr-5", status="captured", steps=1, tokens=1)
  debug_inspect(
    row_status(locale=English, done[0].rows[0], closed=true),
    content="(\"done\", \"done\")",
  )
  let timed = child_closed(
    runs,
    id="sr-5",
    status="timed_out",
    steps=1,
    tokens=1,
  )
  debug_inspect(
    row_status(locale=English, timed[0].rows[0], closed=true),
    content="(\"timed out\", \"failed\")",
  )
}

///|
test "a child whose spend is unknown makes the run's totals a floor" {
  let runs = child_closed(
    announced_run(),
    id="sr-5",
    status="captured",
    steps=12,
    tokens=3400,
  )
  inspect(runs[0].unaccounted(), content="0")
  // The launch was cancelled before its result was read: the counters are
  // only what was observed, and the run says it cannot total them.
  let runs = child_closed(
    runs,
    id="sr-6",
    status="failed",
    steps=0,
    tokens=0,
    unaccounted="the launch was cancelled before its result was read",
  )
  inspect(runs[0].unaccounted(), content="1")
  inspect(runs[0].tokens(), content="3400")
  // The journal's entry carries the same fact and refines the row with it.
  let runs = entry(runs, {
    workflow: "wf-5",
    session: "run7",
    child: "run7-sr-5",
    kind: "explore",
    label: "scout:x",
    phase: None,
    status: "failed",
    steps: 12,
    prompt_tokens: 3000,
    completion_tokens: 400,
    cost_usd: Some(0.01),
    unaccounted: Some("the child left no result"),
    started_at: Some(1788535817640.0),
    finished_at: Some(1788535817648.0),
  })
  inspect(runs[0].unaccounted(), content="2")
  debug_inspect(
    runs[0].rows.map(row => row.unaccounted),
    content=(
      #|[
      #|  Some("the child left no result"),
      #|  Some("the launch was cancelled before its result was read"),
      #|]
    ),
  )
}
