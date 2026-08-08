// The contract: what counts as the standing plan, what a card diffs against,
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
  // And it is not a baseline either — nothing diffs against a plan that
  // never took effect.
  let baselines = @plan.baselines([
    plan_call("c1", applied),
    plan_call("c2", never_ran, has_result=false),
    plan_call("c3", plan_json([("one", "completed"), ("three", "pending")])),
  ])
  assert_true(baselines.get("c2") is None)
  guard baselines.get("c3") is Some(base) else {
    fail("expected c3 to diff against c1")
  }
  assert_eq(base.length(), 1)
}

///|
test "baselines pair each call with the previous applied one" {
  let first = plan_json([("one", "in_progress")])
  let second = plan_json([("one", "completed")])
  let third = plan_json([("one", "completed"), ("two", "in_progress")])
  let baselines = @plan.baselines([
    plan_call("c1", first),
    plan_call("c2", second),
    plan_call("c3", third),
  ])
  // The session's first plan has nothing to diff against.
  assert_true(baselines.get("c1") is None)
  guard baselines.get("c2") is Some(base_of_second) else {
    fail("expected a baseline for c2")
  }
  assert_true(base_of_second[0].status is InProgress)
  guard baselines.get("c3") is Some(base_of_third) else {
    fail("expected a baseline for c3")
  }
  assert_eq(base_of_third.length(), 1)
}

///|
test "baselines skip a rejected call" {
  let first = plan_json([("one", "in_progress")])
  let rejected = plan_json([("nonsense", "pending")])
  let third = plan_json([("one", "completed")])
  let baselines = @plan.baselines([
    plan_call("c1", first),
    plan_call("c2", rejected, is_error=true),
    plan_call("c3", third),
  ])
  // A rejected call never changed the plan, so it is neither a baseline nor
  // gets one: c3 diffs against c1.
  assert_true(baselines.get("c2") is None)
  guard baselines.get("c3") is Some(base) else {
    fail("expected a baseline for c3")
  }
  assert_true(base[0].status is InProgress)
}

///|
test "a card renders the meter, the checklist, and what changed" {
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
  guard @plan.decode(
      plan_json([
        ("read the failing test", "completed"),
        ("fix the parser", "in_progress"),
        ("run moon test", "pending"),
        ("write the changelog", "pending"),
      ]),
    )
    is Some(baseline) else {
    fail("expected a baseline")
  }
  let rendered = markup(@plan.card(steps, baseline~))
  // Two of four completed, with the in-progress step's own slice of the bar.
  assert_true(rendered.contains("plan-progress-count\">2/4"))
  assert_true(rendered.contains("width: 50%"))
  assert_true(rendered.contains("plan-progress-fill active"))
  // The steps that moved carry markers; the untouched first one does not.
  assert_true(rendered.contains("step-delta-done"))
  assert_true(rendered.contains("step-delta-started"))
  assert_true(rendered.contains("step-delta-new"))
  // The step this update cut stays visible as a ghost row.
  assert_true(rendered.contains("plan-step dropped"))
  assert_true(rendered.contains("write the changelog"))
}

///|
test "repeated titles are paired one to one, not all against the first" {
  // The tool permits a plan to repeat a title. Matching every occurrence
  // against the first old step of that name would trade their statuses: the
  // second row here would read "reopened" off the first row's baseline.
  guard @plan.decode(
      plan_json([("run tests", "completed"), ("run tests", "in_progress")]),
    )
    is Some(steps) else {
    fail("expected a plan")
  }
  guard @plan.decode(
      plan_json([("run tests", "completed"), ("run tests", "pending")]),
    )
    is Some(baseline) else {
    fail("expected a baseline")
  }
  let rendered = markup(@plan.card(steps, baseline~))
  assert_true(rendered.contains("step-delta-started"))
  assert_false(rendered.contains("step-delta-reopened"))
  assert_false(rendered.contains("step-delta-new"))
}

///|
test "a surviving duplicate pairs with the step that did not move" {
  // Which of two identical titles the survivor "is" has no answer, so the
  // tie goes to the reading that claims the least: pairing it with the
  // pending one would report work finishing that may never have happened,
  // and the ghost row reads the same either way.
  guard @plan.decode(plan_json([("run tests", "completed")])) is Some(steps) else {
    fail("expected a plan")
  }
  guard @plan.decode(
      plan_json([("run tests", "pending"), ("run tests", "completed")]),
    )
    is Some(baseline) else {
    fail("expected a baseline")
  }
  let rendered = markup(@plan.card(steps, baseline~))
  assert_false(rendered.contains("step-delta-done"))
  assert_true(rendered.contains("plan-step dropped"))
}

///|
test "dropping one of two same-titled steps still shows a ghost row" {
  // The surviving occurrence answers for the title, so a by-title lookup
  // would report nothing dropped at all.
  guard @plan.decode(plan_json([("run tests", "completed")])) is Some(steps) else {
    fail("expected a plan")
  }
  guard @plan.decode(
      plan_json([("run tests", "completed"), ("run tests", "pending")]),
    )
    is Some(baseline) else {
    fail("expected a baseline")
  }
  let rendered = markup(@plan.card(steps, baseline~))
  assert_true(rendered.contains("plan-step dropped"))
}

///|
test "a first card has no baseline to mark against" {
  guard @plan.decode(plan_json([("one", "in_progress"), ("two", "pending")]))
    is Some(steps) else {
    fail("expected a plan")
  }
  let rendered = markup(@plan.card(steps))
  assert_true(rendered.contains("plan-steps"))
  assert_false(rendered.contains("step-delta"))
  assert_false(rendered.contains("plan-rewrite-note"))
}

///|
test "a rewrite is noted once instead of marking every row" {
  guard @plan.decode(plan_json([("alpha", "pending"), ("beta", "pending")]))
    is Some(steps) else {
    fail("expected a plan")
  }
  guard @plan.decode(plan_json([("gamma", "completed"), ("delta", "pending")]))
    is Some(baseline) else {
    fail("expected a baseline")
  }
  let rendered = markup(@plan.card(steps, baseline~))
  assert_true(rendered.contains("plan-rewrite-note"))
  assert_false(rendered.contains("step-delta"))
}

///|
test "a plan that mostly repeats one title reads as a rewrite" {
  // Only one step genuinely carries over. A by-title count would see every
  // row as carried and call this an evolution, then mark nearly all of them —
  // the noise the rewrite note exists to avoid.
  let repeated = [
    ("run tests", "pending"),
    ..[
      for _ in 0..<5 => ("run tests", "pending")
    ],
  ]
  guard @plan.decode(plan_json(repeated)) is Some(steps) else {
    fail("expected a plan")
  }
  guard @plan.decode(
      plan_json(
        [
          ("run tests", "pending"),
          ..[
            for index in 0..<5 => ("step \{index}", "pending")
          ],
        ],
      ),
    )
    is Some(baseline) else {
    fail("expected a baseline")
  }
  let rendered = markup(@plan.card(steps, baseline~))
  assert_true(rendered.contains("plan-rewrite-note"))
  assert_false(rendered.contains("step-delta"))
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
  // The panel states the plan; it does not re-litigate what changed.
  assert_false(rendered.contains("step-delta"))
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
