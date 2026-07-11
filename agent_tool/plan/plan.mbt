///|
/// Tool definition for `plan`: records or replaces the agent's step-by-step
/// plan for the current task.
///
/// ## Arguments
/// - `steps` (array, required): the complete ordered plan. Each item is an
///   object with exactly a `title` (non-blank single line, at most
///   `@steps.MAX_TITLE_CHARS` characters after trimming) and a `status` of
///   `"pending"`, `"in_progress"`, or `"completed"`. At most one step may be
///   `in_progress`, the plan is capped at `@steps.MAX_STEPS` steps, and an
///   empty array clears the plan.
///
/// ## Result
/// - `Respond` with a terse acknowledgment (`Plan updated: 2/5 done · in
///   progress: fix the parser.`) plus a one-line `brief` for the UI
///   (`plan 2/5 · fix the parser`). The plan itself stays model-visible
///   through the tool-call arguments, which the session replays on every
///   request — echoing the checklist again in the result would double that
///   cost for no information gain. When every step is completed and none of
///   them looks like a verification step, the acknowledgment appends a
///   reminder to verify before finishing — at exactly the moment such skips
///   happen.
/// - Malformed arguments produce `Respond(is_error=true)` naming the first
///   offending field so the model can correct the call.
///
/// The tool is deliberately stateless: every call passes the whole plan and
/// replaces the previous one, so plan state lives in the transcript itself and
/// there is nothing to reconcile, persist, or leak across turns. A plan is a
/// bookkeeping aid, not evidence: a plan with every step completed only
/// records that the model believes its steps are exhausted, and never
/// substitutes for verifying the actual work.
pub fn definition() -> @agent_tool.AgentToolDefinition {
  AgentToolDefinition(
    name="plan",
    description=(
      #|Record or update your step-by-step plan for a multi-step task. Pass the complete list of steps on every call; it replaces the previous plan, and an empty list clears it. Keep titles short, single-line, and imperative, mark at most one step "in_progress", and mark finished steps "completed". Use it when a task needs several distinct steps, and update it as steps complete; skip it for trivial single-step tasks. Never write a plan as plain assistant text. Updating the plan records intent only: it is not a substitute for doing the work, and a fully completed plan is not evidence the task is done — verify with checks or tests before finishing.
    ),
    schema=JsonSchema({
      "type": "object",
      "properties": {
        "steps": {
          "type": "array",
          "description": "The complete ordered plan; replaces the previous plan. An empty array clears the plan.",
          "maxItems": @steps.MAX_STEPS.to_json(),
          "items": {
            "type": "object",
            "properties": {
              "title": {
                "type": "string",
                "description": "Short imperative step title on a single line; non-blank after trimming.",
                "minLength": 1,
                "maxLength": @steps.MAX_TITLE_CHARS.to_json(),
              },
              "status": {
                "type": "string",
                "enum": ["pending", "in_progress", "completed"],
              },
            },
            "required": ["title", "status"],
            "additionalProperties": false,
          },
        },
      },
      "required": ["steps"],
      "additionalProperties": false,
    }),
    execute=Sync(execute),
  )
}

///|
/// Best-effort numbered rendering of `plan` tool-call arguments for host-side
/// staleness reminders: `1. [in_progress] fix the parser` lines. Returns
/// `None` for arguments that do not decode as a plan, or that cleared it, so
/// callers fall back to a plan-free nudge. Lives here so the agent loop never
/// grows its own copy of the plan argument syntax.
pub fn reminder_checklist(arguments : Json) -> String? {
  let input = @steps.decode(arguments) catch { _ => return None }
  if input.steps.is_empty() {
    return None
  }
  Some(
    [
      for index, step in input.steps => {
        "\{index + 1}. [\{step.status.label()}] \{step.title}"
      }
    ].join("\n"),
  )
}

///|
test "reminder_checklist renders numbered statuses and falls back to None" {
  guard reminder_checklist({
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
  assert_true(reminder_checklist({ "steps": [] }) is None)
  assert_true(reminder_checklist({ "nonsense": true }) is None)
}

///|
fn execute(arguments : Json) -> @agent_tool.ToolAction {
  let input = @steps.decode(arguments) catch {
    error => {
      let message = @tool_error.failure_message("\{error}")
      return @agent_tool.ToolAction::respond(
        "error: plan requires \{message}",
        is_error=true,
      )
    }
  }
  render(input)
}

///|
/// Step titles that read as verification work. Deciding "did the plan end
/// without a verification step" only needs a coarse net: false positives just
/// suppress a reminder the model did not need.
fn is_verification_title(title : String) -> Bool {
  let lowered = title.to_lower()
  lowered.contains("test") ||
  lowered.contains("check") ||
  lowered.contains("verify") ||
  lowered.contains("validate") ||
  lowered.contains("lint")
}

///|
/// Renders the decoded plan as a terse acknowledgment: progress count plus
/// the in-progress step. The full plan already lives in the tool-call
/// arguments that the session replays on every request, so the result adds
/// only what the arguments do not state — the tally, and a verification
/// reminder when a plan finishes without any verification-looking step.
fn render(input : @steps.PlanInput) -> @agent_tool.ToolAction {
  let total = input.steps.length()
  if total == 0 {
    return @agent_tool.ToolAction::respond(
      "Plan cleared.",
      brief="plan cleared",
    )
  }
  let completed = input.steps.count_if(step => step.status is Completed)
  // The decoder rejects plans with more than one in_progress step, so the
  // first match is the only one.
  let in_progress = input.steps
    .iter()
    .find_first(step => step.status is InProgress)
    .map(step => step.title)
  let has_verification = input.steps
    .iter()
    .any(step => is_verification_title(step.title))
  let mut content = match in_progress {
    Some(title) =>
      "Plan updated: \{completed}/\{total} done · in progress: \{title}."
    None =>
      if completed == total {
        "Plan updated: all \{total} steps completed."
      } else {
        "Plan updated: \{completed}/\{total} done, no step in progress."
      }
  }
  if completed == total && !has_verification {
    content += " No step verified the work — run checks or tests before finishing."
  }
  let brief = match in_progress {
    Some(title) =>
      @agent_tool.brief_line("plan \{completed}/\{total} · \{title}")
    None =>
      if completed == total {
        "plan \{completed}/\{total} · all steps done"
      } else {
        "plan \{completed}/\{total}"
      }
  }
  @agent_tool.ToolAction::respond(content, brief~)
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
    Json::object(Map([])),
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

///|
test "plan definition exposes the expected name and schema shape" {
  let definition = definition()
  assert_eq(definition.name, "plan")
  guard definition.schema is JsonSchema({ "required": ["steps"], .. }) else {
    fail("expected steps to be required")
  }
  guard definition.execute is Sync(_) else { fail("expected a Sync executor") }
}
