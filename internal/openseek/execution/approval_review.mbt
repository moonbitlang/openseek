///|
/// Wall deadline for one approval review. A tool is blocked on the answer, so
/// this is far tighter than the goal gate's: a reviewer that has not decided
/// in five minutes is not going to, and the question moves on to its fallback.
const ApprovalReviewDeadlineMs : Int32 = 300_000

///|
/// How many of the user's most recent messages the reviewer reads.
let intent_max_messages : Int32 = 3

///|
/// What answers a permission question under `--approval review`. Only
/// cancellation of the asking turn raises out of it.
struct ApprovalReviewer(
  async (@agent_runtime.ApprovalAsk) -> @agent_approval.Decision
)

///|
/// The user's words a reviewer holds a request to: the standing goal, when
/// one stands, then the most recent user messages, oldest first. Whole, never
/// truncated: a restriction at the end of a long message is exactly what a
/// clipped prefix would lose. The prompt `serve` submits to auto-continue a
/// goal is recorded as a `User` message but no person wrote it, so it is not
/// authorization and does not take a slot.
pub fn approval_intent(session : @agent_session.Session) -> Array[String] {
  let recent : Array[String] = []
  let events = session.events()
  for i = events.length() - 1
      i >= 0 && recent.length() < intent_max_messages
      i = i - 1 {
    if events.get(i) is Some(event) && event.item() is User(message) {
      let text = message.content().text()
      if !text.is_blank() && text != @agent_session.GoalContinuePrompt {
        recent.push(text)
      }
    }
  }
  recent.rev_in_place()
  if session.current_goal() is Some(goal) {
    ["[standing goal] \{goal.text()}", ..recent]
  } else {
    recent
  }
}

///|
/// Build the reviewer behind `--approval review`: each question spawns a
/// managed `run --kind approval` child, asked whether the user's words, as
/// `intent` reads them at the moment of asking, authorize it. The child is
/// delegated, so its own approval policy is `never`: a reviewer can never ask
/// for anything. `api_key` is the parent's resolved key, handed over under
/// its provider's variable exactly as a subagent's is: a key from the command
/// line reaches the child, and an unrelated one in the environment does not
/// win over it. A child that reaches no verdict (no report, a timeout, a
/// spawn failure) escalates.
pub fn build_approval_reviewer(
  self_exe~ : String,
  model~ : @deepseek.Model,
  api_key~ : String,
  api_url~ : String?,
  workspace_root~ : String,
  intent~ : () -> Array[String],
  deadline_ms~ : Int32 = ApprovalReviewDeadlineMs,
  child_session? : @agent_subrun.ChildSession,
) -> ApprovalReviewer {
  let (self_exe, launch_prefix) = @setup.workflow_launch(self_exe)
  // One name for both: the child refuses a request whose kind differs from
  // its `--kind`.
  let kind = "approval"
  let args = [
    ..launch_prefix,
    "run",
    "--input-format",
    "json",
    "--cancel-on-stdin-eof",
    "--kind",
    kind,
    "--result-file",
    @spawn.ResultFilePlaceholder,
    "--model",
    "\{model}",
    ..if api_url is Some(url) {
      ["--api-url", url]
    },
  ]
  ApprovalReviewer(ask => {
    let result = @agent_subrun.run_subrun(
      command=self_exe,
      args~,
      input=ToJson::to_json(@agent_approval.ReviewRequest(ask, intent=intent())),
      parse_report=@agent_approval.Verdict::parse,
      wall_deadline_ms=deadline_ms,
      kind~,
      label=@agent_tool.brief_line("\{ask.tool_name}: \{ask.detail}", limit=48),
      cwd=workspace_root,
      extra_env=Map([(provider_key_variable(model), api_key)]),
      child_session?,
    )
    result.value().map(verdict => verdict.decision()).unwrap_or(Escalate)
  })
}
