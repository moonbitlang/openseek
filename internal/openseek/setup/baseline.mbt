///|
/// Per-probe wall budget. Each git probe gets its own bound so a slow
/// `status` (large or cold-cache repos) cannot discard an already-obtained
/// sha — on status timeout the baseline keeps the sha and reports
/// dirty=true, the conservative direction for an audit anchor.
const BaselineProbeBudgetMs : Int = 2_000

///|
/// The record appended when a goal is set but the baseline could not be
/// captured (not a repo, no git, over budget). Appending it — rather than
/// nothing — keeps the marker's preceding slot OWNED by this goal-set, so
/// a stale orphan baseline from an earlier fault cannot be stolen by
/// adjacency. `parse_goal_baseline` rejects it, yielding "no baseline".
const GoalBaselineUnavailable : String = "[goal baseline] unavailable"

///|
/// Run `command args...` in `cwd`, capturing stdout. `Some(output)` only on
/// exit 0 within the budget; any failure — spawn, nonzero exit, timeout —
/// is `None`. `collect_stdout` owns the pipe lifecycle (defer-closed on
/// every path, including cancellation mid-wait).
async fn run_capture(
  command : String,
  args : Array[String],
  cwd : String,
) -> String? {
  let outcome = @async.with_timeout_opt(BaselineProbeBudgetMs, () => {
    @process.collect_stdout(
      command.view(),
      args,
      inherit_env=true,
      cwd=cwd.view(),
    )
  }) catch {
    _ => return None
  }
  match outcome {
    Some((0, data)) => Some(data.text())
    _ => None
  }
}

///|
/// The goal-baseline notice for `workspace_root`: the commit the worktree
/// sits on plus whether it is dirty. Never `None` for a set — a failed sha
/// probe yields the `unavailable` record so the marker's preceding slot is
/// still owned by this set (see `GoalBaselineUnavailable`); a failed or
/// timed-out dirty probe keeps the sha and reports dirty=true.
pub async fn capture_goal_baseline(workspace_root : String) -> String {
  guard run_capture("git", ["rev-parse", "HEAD"], workspace_root)
    is Some(sha_line) else {
    return GoalBaselineUnavailable
  }
  let sha = sha_line.trim().to_owned()
  if sha.is_empty() {
    return GoalBaselineUnavailable
  }
  let dirty = run_capture("git", ["status", "--porcelain"], workspace_root)
    .map(status => !status.is_blank())
    .unwrap_or(true)
  @agent_session.goal_baseline_notice(sha~, dirty~)
}
