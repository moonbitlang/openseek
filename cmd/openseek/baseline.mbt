///|
/// Per-probe wall budget. Each git probe gets its own bound so a slow
/// `status` (large or cold-cache repos) cannot discard an already-obtained
/// sha — on status timeout the baseline keeps the sha and reports
/// dirty=true, the conservative direction for an audit anchor.
const BaselineProbeBudgetMs : Int = 2_000

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
    error if @async.is_being_cancelled() => raise error
    _ => return None
  }
  match outcome {
    Some((0, data)) => Some(data.text())
    _ => None
  }
}

///|
/// Capture the advisory anchor at goal-set time. A failed SHA probe is
/// explicitly unavailable; a failed dirty probe retains the SHA and the
/// existing conservative dirty=true policy.
async fn capture_goal_baseline(
  workspace_root : String,
) -> @agent_session.GoalBaselineState {
  guard run_capture("git", ["rev-parse", "HEAD"], workspace_root)
    is Some(sha_line) else {
    return Unavailable
  }
  let sha = sha_line.trim().to_owned()
  if sha.is_empty() {
    return Unavailable
  }
  let dirty = run_capture("git", ["status", "--porcelain"], workspace_root)
    .map(status => !status.is_blank())
    .unwrap_or(true)
  Captured({ sha, dirty, })
}

///|
async test "capture_goal_baseline probes the enclosing repo" {
  match capture_goal_baseline(".") {
    Captured(baseline) => assert_eq(baseline.sha.length(), 40)
    Unavailable => println("skipped: git probe unavailable")
  }
}
