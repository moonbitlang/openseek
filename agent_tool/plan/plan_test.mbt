///|
test "reminder_checklist renders numbered statuses and falls back to None" {
  guard @plan.reminder_checklist({
      "steps": [
        { "title": "read the failing test", "status": "completed" },
        { "title": "fix the parser", "status": "in_progress" },
      ],
    })
    is Some(lines) else {
    fail("expected a checklist")
  }
  assert_eq(
    lines,
    (
      #|1. [completed] read the failing test
      #|2. [in_progress] fix the parser
    ),
  )
  // A cleared plan and undecodable arguments both yield None.
  assert_true(@plan.reminder_checklist({ "steps": [] }) is None)
  assert_true(@plan.reminder_checklist({ "nonsense": true }) is None)
}

///|
test "plan definition exposes the expected name and schema shape" {
  let definition = @plan.definition()
  assert_eq(definition.name, "plan")
  guard definition.schema is JsonSchema({ "required": ["steps"], .. }) else {
    fail("expected steps to be required")
  }
  guard definition.execute is Sync(_) else { fail("expected a Sync executor") }
}

///|
/// Run the `plan` tool through its public definition — the executor the
/// registry dispatches.
fn execute(arguments : Json) -> @agent_tool.ToolAction raise {
  match @plan.definition().execute {
    Sync(run) => run(arguments)
    Async(_) => fail("plan tool should be sync")
  }
}

///|
/// Asserts that `execute(arguments)` responds successfully with `content` and
/// `brief`.
fn assert_plan(
  arguments : Json,
  content : String,
  brief : String,
) -> Unit raise {
  guard execute(arguments) is Respond(output) else { fail("expected Respond") }
  assert_false(output.is_error)
  assert_eq(output.content, content)
  guard output.brief is Some(actual_brief) else { fail("expected a brief") }
  assert_eq(actual_brief, brief)
}

///|
/// Asserts that `execute(arguments)` responds with an error containing
/// `expected`.
fn assert_plan_error(arguments : Json, expected : String) -> Unit raise {
  guard execute(arguments) is Respond(output) else { fail("expected Respond") }
  assert_true(output.is_error)
  assert_true(
    output.content.contains(expected),
    msg="\{output.content} should contain \{expected}",
  )
}

///|
test "plan acknowledges progress and the in-progress step" {
  assert_plan(
    {
      "steps": [
        { "title": "read the failing test", "status": "completed" },
        { "title": "fix the parser", "status": "in_progress" },
        { "title": "run moon test", "status": "pending" },
      ],
    },
    "Plan updated: 1/3 done · in progress: fix the parser.",
    "plan 1/3 · fix the parser",
  )
}

///|
test "plan with every step completed reminds about missing verification" {
  assert_plan(
    {
      "steps": [
        { "title": "step one", "status": "completed" },
        { "title": "step two", "status": "completed" },
      ],
    },
    "Plan updated: all 2 steps completed. No step verified the work — run checks or tests before finishing.",
    "plan 2/2 · all steps done",
  )
}

///|
test "plan completed through a verification step needs no reminder" {
  assert_plan(
    {
      "steps": [
        { "title": "fix the parser", "status": "completed" },
        { "title": "run moon test", "status": "completed" },
      ],
    },
    "Plan updated: all 2 steps completed.",
    "plan 2/2 · all steps done",
  )
}

///|
test "plan with no in_progress step and work left omits the active title" {
  assert_plan(
    {
      "steps": [
        { "title": "step one", "status": "completed" },
        { "title": "step two", "status": "pending" },
      ],
    },
    "Plan updated: 1/2 done, no step in progress.",
    "plan 1/2",
  )
}

///|
test "plan renders trimmed titles" {
  assert_plan(
    { "steps": [{ "title": "  fix parser  ", "status": "in_progress" }] },
    "Plan updated: 0/1 done · in progress: fix parser.",
    "plan 0/1 · fix parser",
  )
}

///|
test "plan caps the composed brief at the shared budget" {
  let long_title = "a title long enough that prefix plus title passes the seventy-two character cap"
  guard execute({ "steps": [{ "title": long_title, "status": "in_progress" }] })
    is Respond(output) else {
    fail("expected Respond")
  }
  guard output.brief is Some(brief) else { fail("expected a brief") }
  assert_true(brief.char_length() <= 73, msg="brief too long: \{brief}")
  assert_true(brief.has_suffix("…"))
}

///|
test "plan clears with an empty step list" {
  assert_plan({ "steps": [] }, "Plan cleared.", "plan cleared")
}

///|
test "plan rejects malformed arguments with a field-naming error" {
  assert_plan_error(
    Json::empty_object(),
    "error: plan requires arguments.steps to be an array",
  )
  assert_plan_error(
    { "steps": [{ "title": "one", "status": "doing" }] },
    "arguments.steps[0].status to be one of pending|in_progress|completed",
  )
  assert_plan_error(
    { "steps": [{ "title": "line\nbreak", "status": "pending" }] },
    "arguments.steps[0].title to be a single line",
  )
  assert_plan_error(
    {
      "steps": [
        { "title": "one", "status": "in_progress" },
        { "title": "two", "status": "in_progress" },
      ],
    },
    "at most one in_progress step",
  )
  assert_plan_error(
    { "steps": [{ "title": "one", "status": "pending", "note": "extra" }] },
    "arguments.steps[0] to have only title and status fields",
  )
}
