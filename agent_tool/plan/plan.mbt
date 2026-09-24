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
fn execute(arguments : Json) -> @agent_tool.ToolAction {
  let input = @steps.decode(arguments) catch {
    error => {
      let message = @tool_error.failure_message("\{error}")
      return @agent_tool.respond(
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
    return @agent_tool.respond("Plan cleared.", brief="plan cleared")
  }
  let completed = input.steps.count_if(step => step.status is Completed)
  // The decoder rejects plans with more than one in_progress step, so the
  // first match is the only one.
  let in_progress = input.steps
    .iter()
    .find_first(step => step.status is InProgress)
    .map(step => step.title)
  let has_verification = input.steps.any(step => {
    is_verification_title(step.title)
  })
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
  @agent_tool.respond(content, brief~)
}
