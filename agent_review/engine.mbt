///|
/// Default step budget for one code review: the `review` kind's ceiling for a
/// `base` input when neither `--max-steps` nor the request sets one.
pub let default_review_max_steps : Int = 120

///|
/// Run a code review of the changes between `base` and HEAD IN THIS PROCESS
/// and return the structured report, or `None` when the model finished
/// without a valid submission. The toolset is `mbtx` and `submit_review` —
/// no edit/multi_edit/write — so the review reports rather than edits.
/// Read-only is best-effort: `mbtx` runs under the "may not write source"
/// profile on macOS, but `moon check`/`moon test` may still trigger pre-build
/// source generation and a snippet can write non-source files, so the
/// checkout is not guaranteed byte-for-byte unchanged. Off macOS there is no
/// kernel profile at all. `scratch_dir` names the one place a snippet may
/// write; without it there is no lab, but the profile still applies.
///
/// `openseek run --kind review` calls this for a `base` input; a `goal` input
/// (the goal-met gate's child, the hosted review workflow) calls
/// `run_goal_audit` instead.
pub async fn run_review(
  base~ : String,
  api_key~ : String,
  model~ : @deepseek.Model,
  max_steps~ : Int,
  thinking? : @deepseek.ThinkingMode = Max,
  api_url? : String,
  retry_attempts? : Int,
  retry_backoff_ms? : Int,
  workspace_root? : String = ".",
  session_id? : String = "review",
  append_item? : async (@agent_session.Session, @agent_session.SessionItem) -> @agent_session.Session,
  scratch_dir? : String,
) -> ReviewReport? {
  @agent_kind.execute_kind(
    session_id~,
    append_item?,
    system_prompt=review_system_prompt(),
    task=review_task(base, scratch_dir),
    tools=captured => {
      Tools([
        @mbtx.definition(workspace_root~, read_only=true, scratch_dir?),
        submit_review_tool(captured),
      ])
    },
    max_steps~,
    api_key~,
    model~,
    thinking~,
    api_url?,
    retry_attempts?,
    retry_backoff_ms?,
    workspace_root~,
  )
}
