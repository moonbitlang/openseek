// The contract: what a payload decodes to, what counts as the standing plan,
// and what each of the three renderings puts on screen.

///|
/// A recorded `plan` call, as the transcript stores one.
fn plan_call(
  id : String,
  arguments : String,
  is_error? : Bool = false,
  has_result? : Bool = true,
) -> @transcript.TranscriptItem {
  {
    kind: Tool(
      call_id=id,
      name="plan",
      arguments=Some(arguments),
      has_result~,
      is_error~,
      brief=None,
    ),
    content: "",
    ts: None,
    sequence: None,
  }
}

///|
/// A successful `plan` result the loader could not pair back to its call, as
/// `apply_session_item` records one: no arguments, but a result.
fn unpaired_result() -> @transcript.TranscriptItem {
  {
    kind: Tool(
      call_id="c9",
      name="plan",
      arguments=None,
      has_result=true,
      is_error=false,
      brief=None,
    ),
    content: "Plan updated.",
    ts: None,
    sequence: None,
  }
}

///|
/// A plan payload from `(title, status)` pairs.
fn plan_json(steps : Array[(String, String)]) -> String {
  let entries = [
    for step in steps => "{\"title\":\"\{step.0}\",\"status\":\"\{step.1}\"}"
  ]
  "{\"steps\":[\{entries.join(",")}]}"
}

///|
#warnings("-alert_unstable")
fn markup(html : @html.Html) -> String {
  @rabbita.render_to_string(() => @rabbita.Val::constant(html))
}

///|
test "decode reads the steps and trims their titles" {
  guard @plan.decode(
      plan_json([
        ("  read the failing test  ", "completed"),
        ("fix the parser", "in_progress"),
        ("run moon test", "pending"),
      ]),
    )
    is Some(steps) else {
    fail("expected a plan")
  }
  debug_inspect(
    steps,
    content=(
      #|[
      #|  { title: "read the failing test", status: Completed },
      #|  { title: "fix the parser", status: InProgress },
      #|  { title: "run moon test", status: Pending },
      #|]
    ),
  )
}

///|
test "decode keeps a status this build does not know" {
  guard @plan.decode(plan_json([("wait on upstream", "blocked")]))
    is Some(steps) else {
    fail("expected a plan")
  }
  assert_true(steps[0].status is Other("blocked"))
}

///|
test "decode accepts a cleared plan and rejects what is not one" {
  assert_true(@plan.decode("{\"steps\":[]}") is Some([]))
  // Not JSON, not a plan payload, and a step missing its status: a row
  // invented for any of these would show a plan that never existed.
  assert_true(@plan.decode("not json") is None)
  assert_true(@plan.decode("{\"goal\":\"ship it\"}") is None)
  assert_true(@plan.decode("{\"steps\":[{\"title\":\"one\"}]}") is None)
}

///|
test "decode refuses a payload too large to be a plan" {
  // The tool caps a plan at 20 steps, but the transcript records the
  // arguments of calls it rejected too — and of calls interrupted before any
  // result. Decoding one of those on every render would build a DOM row per
  // entry behind a collapsed card; past the bound the call keeps the generic
  // rendering, which clamps before it parses.
  let oversized = [ for index in 0..<201 => ("step \{index}", "pending") ]
  assert_true(@plan.decode(plan_json(oversized)) is None)
  // A plan an order of magnitude past the tool's cap still renders: the bound
  // is about cost, not about re-checking the tool's limits.
  let large = [ for index in 0..<199 => ("step \{index}", "pending") ]
  guard @plan.decode(plan_json(large)) is Some(steps) else {
    fail("expected a large but bounded plan to decode")
  }
  assert_eq(steps.length(), 199)
  // A single enormous title is bounded by payload size before it is parsed.
  assert_true(
    @plan.decode(plan_json([("x".repeat(200_000), "pending")])) is None,
  )
}

///|
test "classify names every state a plan call can be observed in" {
  let payload = plan_json([("one", "in_progress")])
  // The store commits a call and its result separately, so both sides of that
  // window are states a reader sees — and each consumer has to say which it
  // accepts rather than rebuilding the test from `has_result`.
  assert_true(@plan.classify(plan_call("c1", payload)) is Some(Applied(_)))
  assert_true(
    @plan.classify(plan_call("c1", payload, has_result=false))
    is Some(Pending(_)),
  )
  assert_true(
    @plan.classify(plan_call("c1", payload, is_error=true)) is Some(Rejected),
  )
  // Not a plan call at all, and a plan call this build declines to decode.
  assert_true(
    @plan.classify({
      kind: Tool(
        call_id="c1",
        name="shell",
        arguments=Some("{}"),
        has_result=true,
        is_error=false,
        brief=None,
      ),
      content: "",
      ts: None,
      sequence: None,
    })
    is None,
  )
  // A payload this build will not decode is its own state, not "not a plan
  // call": something landed here, and only the reading of it is missing. It
  // carries the same applied/pending distinction the readable states do.
  assert_true(
    @plan.classify(plan_call("c1", "not json"))
    is Some(Unreadable(applied=true)),
  )
  assert_true(
    @plan.classify(plan_call("c1", "not json", has_result=false))
    is Some(Unreadable(applied=false)),
  )
  // A successful result the loader could not pair back to its call keeps no
  // arguments, and is still evidence that a plan call ran.
  assert_true(
    @plan.classify(unpaired_result()) is Some(Unreadable(applied=true)),
  )
}

///|
test "an unreadable plan call hides the panel instead of showing an older plan" {
  let readable = plan_json([("one", "in_progress")])
  let oversized = plan_json(
    [
      for index in 0..<201 => ("step \{index}", "pending")
    ],
  )
  // A newer engine can raise the tool's caps past this build's display
  // bounds. That call still replaced the plan, so the plan before it is not
  // the current one — answering with it would be stale and silent.
  assert_true(
    @plan.latest([plan_call("c1", readable), plan_call("c2", oversized)])
    is None,
  )
  // The wall is the call, not the payload: a readable plan after it is again
  // the standing plan.
  guard @plan.latest([
      plan_call("c1", readable),
      plan_call("c2", oversized),
      plan_call("c3", plan_json([("two", "in_progress")])),
    ])
    is Some(steps) else {
    fail("expected the plan recorded after the unreadable one")
  }
  assert_eq(steps[0].title, "two")
  // A successful result with no recorded arguments is the same wall: the call
  // ran, and its payload is simply not in the log.
  assert_true(
    @plan.latest([plan_call("c1", readable), unpaired_result()]) is None,
  )
}

///|
test "an unreadable call still awaiting its result keeps the prior plan" {
  let readable = plan_json([("one", "in_progress")])
  // A malformed call is unresolved for the moment before its rejection lands.
  // Treating that as a wall would blank the panel on every malformed call,
  // and permanently for a run interrupted in the window — while an equally
  // unresolved *decodable* call correctly leaves the prior plan alone.
  guard @plan.latest([
      plan_call("c1", readable),
      plan_call("c2", "not json", has_result=false),
    ])
    is Some(steps) else {
    fail("expected the prior plan to survive a pending unreadable call")
  }
  assert_eq(steps[0].title, "one")
}

///|
test "latest reads the last applied call and skips rejected ones" {
  let first = plan_json([("one", "in_progress")])
  let rejected = plan_json([("two", "in_progress")])
  let applied = plan_json([("one", "completed"), ("three", "in_progress")])
  let items = [
    plan_call("c1", first),
    plan_call("c2", rejected, is_error=true),
    plan_call("c3", applied),
  ]
  guard @plan.latest(items) is Some(steps) else { fail("expected a plan") }
  assert_eq(steps.length(), 2)
  assert_eq(steps[1].title, "three")
}

///|
test "latest reports no plan for an empty transcript or a cleared plan" {
  assert_true(@plan.latest([]) is None)
  assert_true(
    @plan.latest([
      plan_call("c1", plan_json([("one", "pending")])),
      plan_call("c2", "{\"steps\":[]}"),
    ])
    is None,
  )
  // A conversation whose only plan call was rejected has no plan either.
  assert_true(
    @plan.latest([
      plan_call("c1", plan_json([("one", "pending")]), is_error=true),
    ])
    is None,
  )
}

///|
test "a call whose result never landed is not the standing plan" {
  let applied = plan_json([("one", "completed")])
  let never_ran = plan_json([("two", "in_progress")])
  // A run interrupted between the assistant event and its result leaves the
  // call unresolved for good. Arguments that were never executed must not
  // stand as the plan for the rest of the session.
  guard @plan.latest([
      plan_call("c1", applied),
      plan_call("c2", never_ran, has_result=false),
    ])
    is Some(steps) else {
    fail("expected the applied plan")
  }
  assert_eq(steps[0].title, "one")
  // Nor may an unresolved clear hide the plan that really did apply.
  guard @plan.latest([
      plan_call("c1", applied),
      plan_call("c2", "{\"steps\":[]}", has_result=false),
    ])
    is Some(surviving) else {
    fail("expected the applied plan to survive an unresolved clear")
  }
  assert_eq(surviving[0].title, "one")
}

///|
test "a card renders the meter over the checklist" {
  guard @plan.decode(
      plan_json([
        ("read the failing test", "completed"),
        ("fix the parser", "completed"),
        ("run moon test", "in_progress"),
        ("update the mbti", "pending"),
      ]),
    )
    is Some(steps) else {
    fail("expected a plan")
  }
  let rendered = markup(@plan.card(steps))
  // Two of four completed, with the in-progress step's own slice of the bar.
  assert_true(rendered.contains("plan-progress-count\">2/4"))
  assert_true(rendered.contains("--plan-progress-width: 50.0%"))
  assert_true(rendered.contains("plan-progress-fill active"))
  // Every step is a row, in the order the call recorded them.
  assert_true(rendered.contains("plan-step completed"))
  assert_true(rendered.contains("plan-step in_progress"))
  assert_true(rendered.contains("plan-step pending"))
  assert_true(rendered.contains("update the mbti"))
}

///|
test "a cleared plan says so instead of rendering an empty checklist" {
  guard @plan.decode("{\"steps\":[]}") is Some(steps) else {
    fail("expected a plan")
  }
  let rendered = markup(@plan.card(steps))
  assert_true(rendered.contains("plan cleared"))
  assert_false(rendered.contains("plan-steps"))
}

///|
test "a large plan's smallest share still draws" {
  // `decode` tolerates plans well past the tool's own cap so a newer engine
  // still renders. A whole-percent width truncated one step of those to
  // nothing, drawing an active plan as an empty track.
  let many = [
    ("one", "completed"),
    ("two", "in_progress"),
    ..[
      for index in 0..<198 => ("step \{index}", "pending")
    ],
  ]
  guard @plan.decode(plan_json(many)) is Some(steps) else {
    fail("expected a plan")
  }
  let rendered = markup(@plan.card(steps))
  // 1/200 completed and one step in progress: both draw at 0.5%, not 0%.
  assert_true(rendered.contains("plan-progress-count\">1/200"))
  assert_false(rendered.contains("--plan-progress-width: 0.0%"))
  assert_true(rendered.contains("--plan-progress-width: 0.5%"))
}

///|
test "a completed plan turns the meter green" {
  guard @plan.decode(plan_json([("one", "completed"), ("two", "completed")]))
    is Some(steps) else {
    fail("expected a plan")
  }
  let rendered = markup(@plan.card(steps))
  assert_true(rendered.contains("plan-progress-fill complete"))
  assert_false(rendered.contains("plan-progress-fill active"))
}

///|
test "an unknown status shows its word rather than a pending ring" {
  guard @plan.decode(plan_json([("wait on upstream", "blocked")]))
    is Some(steps) else {
    fail("expected a plan")
  }
  let rendered = markup(@plan.card(steps))
  assert_true(rendered.contains("step-status\">blocked"))
  assert_true(rendered.contains("plan-step other"))
}

///|
test "the fold meter reports the run's last plan, or nothing" {
  let items = [
    plan_call("c1", plan_json([("one", "completed"), ("two", "pending")])),
    plan_call("c2", plan_json([("one", "completed"), ("two", "in_progress")])),
  ]
  let rendered = markup(@plan.fold_progress(items))
  assert_true(rendered.contains("plan-progress mini"))
  assert_true(rendered.contains("plan-progress-count\">1/2"))
  // The tooltip names the step the run left in progress.
  assert_true(rendered.contains("plan 1/2 · two"))
  assert_eq(markup(@plan.fold_progress([])), "")
}

///|
test "the panel names the active step and keeps its slot when empty" {
  let items = [
    plan_call(
      "c1",
      plan_json([
        ("read the failing test", "completed"),
        ("fix the parser", "in_progress"),
        ("run moon test", "pending"),
      ]),
    ),
  ]
  let rendered = markup(@plan.panel(items))
  assert_true(rendered.contains("plan-panel-summary"))
  assert_true(rendered.contains("fix the parser"))
  assert_true(rendered.contains("plan-progress-count\">1/3"))
  // With no plan the slot still renders, so the composer's children keep a
  // fixed shape as a plan appears and clears mid-turn.
  let empty = markup(@plan.panel([]))
  assert_true(empty.contains("plan-panel-slot"))
  assert_false(empty.contains("plan-panel-summary"))
}

///|
test "the panel reads a finished plan as done" {
  let items = [plan_call("c1", plan_json([("one", "completed")]))]
  let rendered = markup(@plan.panel(items))
  assert_true(rendered.contains("all steps done"))
}
