///|
/// Raised when a review run fails for an infrastructure reason (e.g. the model
/// finished without producing a structured report), as opposed to completing
/// with findings.
pub suberror ReviewError {
  ReviewError(String)
}

///|
/// Default step budget for one review run.
let default_review_max_steps : Int = 120

///|
/// Run a code review of the changes between `base` and HEAD and return the
/// structured report. The toolset is `read`, `shell` (in read-only mode),
/// `run_moonbit`, and `submit_review` — no edit/multi_edit/write — so the
/// review reports rather than edits. Read-only is best-effort: the shell
/// refuses obvious source-mutating moon commands and `run_moonbit` is
/// sandboxed against source writes on macOS, but `moon check`/`moon test`
/// may still trigger pre-build source generation and `run_moonbit` can write
/// non-source files, so the checkout is not guaranteed byte-for-byte
/// unchanged. Raises `ReviewError` if the model finishes without submitting a
/// report.
///
/// Runs the review kind IN THIS PROCESS via `@agent_subrun.execute_kind`: the
/// standalone CLI is already a dedicated process, and a future in-session
/// gate spawns `openseek subrun review` — a child process whose dispatch
/// calls this same code path.
pub async fn run_review(
  api_key : String,
  model : @deepseek.Model,
  base : String,
  workspace_root? : String = ".",
  max_steps? : Int = default_review_max_steps,
  thinking? : @deepseek.ThinkingMode = Max,
  api_url? : String,
) -> ReviewReport {
  let report = @agent_subrun.execute_kind(
    session_id="review",
    system_prompt=review_system_prompt(),
    task=review_task(base),
    tools=captured => {
      @agent_tool.Tools([
        @read.definition(workspace_root~),
        @run_moonbit.definition(workspace_root~),
        submit_review_tool(captured),
      ])
    },
    max_steps~,
    api_key~,
    model~,
    thinking~,
    api_url?,
    workspace_root~,
  )
  match report {
    Some(report) => report
    None =>
      raise ReviewError(
        "review finished without calling submit_review (no structured report)",
      )
  }
}
