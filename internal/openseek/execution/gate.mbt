///|
/// Wall deadline for one gate audit: a reviewer that has not reported in
/// fifteen minutes is stuck, not thorough. Sized with the step ceiling:
/// audit steps run several seconds each (and slow as the child's context
/// grows), so the clock must comfortably cover a full step allowance —
/// dying by deadline instead of ceiling reports nothing either way.
const GateDeadlineMs : Int = 900_000

///|
/// Parse-and-validate the audit child's report line — the same contract the
/// child's submit tool enforced, re-checked at the trust boundary.
fn parse_audit_report(
  json : Json,
) -> Result[@agent_review.ReviewReport, String] {
  match @agent_review.ReviewReport::parse(json) {
    Err(msg) => Err(msg)
    Ok(report) => {
      let problems = report.validate()
      if problems.length() > 0 {
        Err(problems.join("; "))
      } else {
        Ok(report)
      }
    }
  }
}

///|
/// What a snippet's review child audits against when the model gives no
/// criteria: the LIVE standing goal and the baseline it recorded, read when
/// the snippet is reserved. The audited party does not restate its own
/// criteria; see `@host.AuditCriteria`.
pub fn audit_criteria(session : @agent_session.Session) -> @host.AuditCriteria? {
  session
  .current_goal()
  .map(goal => {
    let baseline = session.current_goal_baseline()
    (
      {
        goal: goal.text(),
        sha: baseline.map(b => b.sha),
        dirty: baseline.map(b => b.dirty).unwrap_or(false),
      } : @host.AuditCriteria)
  })
}

///|
/// The input every `subrun review` child reads: the criteria to audit
/// against, plus the baseline commit when the goal captured one.
fn review_subrun_input(
  goal : String,
  baseline : @agent_session.GoalBaseline?,
) -> Json {
  match baseline {
    Some(baseline) =>
      { "goal": goal, "sha": baseline.sha, "dirty": baseline.dirty }
    None => { "goal": goal }
  }
}

///|
/// Build the advisory goal-met gate: on a durably recorded met, spawn the
/// `subrun review` child against the goal's baseline and return the bounded
/// digest notice. Advisory by contract — every failure shape (no report,
/// timeout, spawn trouble) degrades to an `[review] unavailable` notice;
/// only external cancellation re-raises (through run_subrun's own
/// contract).
///
/// The gate has its own step allowance and fires at most once per met claim,
/// independently of model-initiated hosted workflows. The audit must retain
/// enough steps to inspect the claim even after the model delegated other work.
pub fn build_goal_met_gate(
  self_exe~ : String,
  model~ : @deepseek.Model,
  api_url~ : String?,
  workspace_root~ : String,
  review_deadline_ms? : Int = GateDeadlineMs,
  child_session? : @agent_subrun.ChildSession,
) -> async (String, @agent_session.GoalBaseline?) -> String? {
  let (self_exe, launch_prefix) = review_gate_launch(self_exe)
  (goal, baseline) => {
    // The `subrun review` child argv, shaped like every sub-run spawn: the
    // command and its kind, the inherited model and step ceiling, plus
    // `--api-url` only when one is configured (absent, the child falls back
    // to its own default endpoint).
    let args = [
      ..launch_prefix,
      "subrun",
      "review",
      "--model",
      "\{model}",
      "--max-steps",
      "\{@agent_review.default_audit_max_steps}",
      ..if api_url is Some(url) {
        ["--api-url", url]
      },
    ]
    let input = review_subrun_input(goal, baseline)
    let result = @agent_subrun.run_subrun(
      command=self_exe,
      args~,
      input~,
      parse_report=parse_audit_report,
      wall_deadline_ms=review_deadline_ms,
      kind="review",
      label=@agent_tool.brief_line(goal, limit=48),
      cwd=workspace_root,
      child_session?,
    )
    match result.value() {
      Some(report) => Some(report.digest())
      None =>
        Some(
          "[review] unavailable (\{@agent_tool.brief_line("\{Repr(result.terminal())}", limit=200)}) — treat the met claim as unaudited.",
        )
    }
  }
}

///|
/// A wasm module needs moonrun, the host providing this engine's process,
/// filesystem and socket APIs. The fence separates runtime and engine args.
fn review_gate_launch(exe : String) -> (String, Array[String]) {
  if exe.has_suffix(".wasm") {
    ("moonrun", [exe, "--"])
  } else {
    (exe, [])
  }
}
