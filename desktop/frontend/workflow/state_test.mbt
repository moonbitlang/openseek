///|
fn announced() -> Array[@workflow.Run] {
  @workflow.opened([], id="wf-5", session="run7", first_child=5, child_count=32)
}

///|
test "a run is announced once and a replayed bracket does not drop its rows" {
  let runs = announced()
  inspect(runs.length(), content="1")
  let with_child = @workflow.child_opened(
    runs,
    id="sr-5",
    kind="explore",
    label="scout:x",
  )
  // A reconnect replays `workflow_started`: the run keeps what it knows.
  let replayed = @workflow.opened(
    with_child,
    id="wf-5",
    session="run7",
    first_child=5,
    child_count=32,
  )
  inspect(replayed.length(), content="1")
  inspect(replayed[0].rows.length(), content="1")
  inspect(replayed[0].closed, content="false")
}

///|
test "a sub-run bracket makes a row only for a child in the run's block" {
  let runs = announced()
  // Ordinal 5 is the run's; ordinal 2 is an ordinary explore child of the
  // same conversation, and none of this package's business.
  let runs = @workflow.child_opened(
    runs,
    id="sr-5",
    kind="explore",
    label="scout:x",
  )
  let runs = @workflow.child_opened(
    runs,
    id="sr-2",
    kind="explore",
    label="elsewhere",
  )
  inspect(runs[0].rows.length(), content="1")
  let row = runs[0].rows[0]
  inspect(row.child, content="run7-sr-5")
  inspect(row.ordinal, content="5")
  debug_inspect(row.status, content="None")
  inspect(runs[0].running(), content="1")
  // The finish bracket carries the terminal and the spend.
  let runs = @workflow.child_closed(
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
fn entry_for(child : String, phase : String?) -> @workflow.Entry {
  {
    workflow: "wf-5",
    session: "run7",
    child,
    kind: "explore",
    label: "scout:x",
    phase,
    status: "captured",
    steps: 12,
    prompt_tokens: 3000,
    completion_tokens: 400,
    cost_usd: Some(0.01),
    started_at: Some(1788535817640.0),
    finished_at: Some(1788535817648.0),
  }
}

///|
test "a journal entry refines the row its brackets created" {
  let runs = @workflow.child_opened(
    announced(),
    id="sr-5",
    kind="explore",
    label="scout:x",
  )
  let runs = @workflow.child_closed(
    runs,
    id="sr-5",
    status="captured",
    steps=12,
    tokens=3400,
  )
  let runs = @workflow.entry(runs, entry_for("run7-sr-5", Some("survey")))
  inspect(runs[0].rows.length(), content="1")
  let row = runs[0].rows[0]
  debug_inspect(row.phase, content="Some(\"survey\")")
  debug_inspect(row.cost_usd, content="Some(0.01)")
  debug_inspect(row.started_at, content="Some(1788535817640)")
  debug_inspect(runs[0].cost_usd(), content="Some(0.01)")
}

///|
test "an entry whose brackets were missed still becomes a row" {
  // A client that connected mid-run sees the journal's entries without ever
  // having seen the launches. The entry is a fact about the run: it gets a
  // row, keyed and ordered by the child it names.
  let runs = @workflow.entry(announced(), entry_for("run7-sr-7", None))
  inspect(runs[0].rows.length(), content="1")
  inspect(runs[0].rows[0].ordinal, content="7")
  inspect(runs[0].rows[0].kind, content="explore")
  debug_inspect(runs[0].rows[0].status, content="Some(\"captured\")")
  // And an entry for a run this client does not know is dropped, not
  // resurrected: only a bracket knows a run exists.
  let other = { ..entry_for("run7-sr-9", None), workflow: "wf-99", }
  inspect(@workflow.entry(runs, other)[0].rows.length(), content="1")
}

///|
test "rows read in launch order and a closed run keeps them" {
  let runs = @workflow.child_opened(
    announced(),
    id="sr-7",
    kind="explore",
    label="c",
  )
  let runs = @workflow.child_opened(runs, id="sr-5", kind="explore", label="a")
  let runs = @workflow.child_opened(runs, id="sr-6", kind="explore", label="b")
  debug_inspect(
    runs[0].ordered_rows().map(row => row.label),
    content="[\"a\", \"b\", \"c\"]",
  )
  let runs = @workflow.closed(runs, id="wf-5")
  inspect(runs[0].closed, content="true")
  inspect(runs[0].rows.length(), content="3")
}
