///|
/// Raised when a review run fails for an infrastructure reason (e.g. the model
/// finished without producing a structured report), as opposed to completing
/// with findings.
priv suberror ReviewError {
  ReviewError(String)
}

///|
/// Default step budget for one review run.
let default_review_max_steps : Int = 120

///|
/// Run a code review of the changes between `base` and HEAD and return the
/// structured report. The toolset is `read`, `mbtx`, and
/// `submit_review` — no edit/multi_edit/write — so the review reports rather
/// than edits. Read-only is best-effort: `mbtx` runs under the "may not
/// write source" profile on macOS, but `moon check`/`moon test` may still
/// trigger pre-build source generation and a snippet can write non-source
/// files, so the checkout is not guaranteed byte-for-byte unchanged. Off macOS
/// there is no kernel profile at all. `scratch_dir` names the one place a
/// snippet may write; without it there is no lab, but the profile still
/// applies. Raises `ReviewError` if the model finishes without submitting a
/// report.
///
/// Runs the review kind IN THIS PROCESS via `@agent_kind.execute_kind`: the
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
  scratch_dir? : String,
) -> ReviewReport {
  let report = @agent_kind.execute_kind(
    session_id="review",
    system_prompt=review_system_prompt(),
    task=review_task(base, scratch_dir),
    tools=captured => {
      @agent_tool.Tools([
        @read.definition(workspace_root~),
        @mbtx.definition(workspace_root~, read_only=true, scratch_dir?),
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
