///|
/// Wall deadline for one gate audit: a reviewer that has not reported in
/// fifteen minutes is stuck, not thorough. Sized with the step ceiling:
/// audit steps run several seconds each (and slow as the child's context
/// grows), so the clock must comfortably cover a full step allowance —
/// dying by deadline instead of ceiling reports nothing either way.
const GateDeadlineMs : Int = 900_000

///|
/// Whether `--review-gate` was passed: the advisory goal-met audit is
/// opt-in while its precision is being calibrated on dogfood runs.
fn review_gate_enabled(matches : @argparse.Matches) -> Bool {
  matches is { flags: { "review-gate": true, .. }, .. }
}

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
/// Build the advisory goal-met gate: on a durably recorded met, spawn the
/// `subrun review` child against the goal's baseline and return the bounded
/// digest notice. Advisory by contract — every failure shape (no report,
/// timeout, spawn trouble) degrades to an `[review] unavailable` notice;
/// only external cancellation re-raises (through run_subrun's own
/// contract).
///
/// The gate does NOT draw from the shared `SubrunBudget`: that allowance
/// meters MODEL-initiated delegation, while the gate is engine-initiated
/// and fires at most once per met claim. Sharing let a turn's explore
/// calls starve the audit into an underpowered run that died at its step
/// ceiling unreported (ccomp-run10) — the one subrun that must not be
/// shortchanged is the one auditing the claim everything else rests on.
fn build_goal_met_gate(
  self_exe~ : String,
  model~ : @deepseek.Model,
  api_url~ : String?,
  workspace_root~ : String,
  child_session? : @agent_subrun.ChildSession,
) -> async (String, @agent_session.GoalBaseline?) -> String? {
  (goal, baseline) => {
    let args = [
      "subrun",
      "review",
      "--model",
      "\{model}",
      "--max-steps",
      "\{@agent_review.default_audit_max_steps}",
    ]
    if api_url is Some(url) {
      args.push("--api-url")
      args.push(url)
    }
    let input : Json = match baseline {
      Some(baseline) =>
        { "goal": goal, "sha": baseline.sha, "dirty": baseline.dirty }
      None => { "goal": goal }
    }
    let result = @agent_subrun.run_subrun(
      command=self_exe,
      args~,
      input~,
      parse_report=parse_audit_report,
      wall_deadline_ms=GateDeadlineMs,
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
/// The `--review-gate` flag, shared by `run` and `serve`.
fn review_gate_flag() -> @argparse.FlagArg {
  FlagArg(
    "review-gate",
    long="review-gate",
    about="On goal(met), audit the worktree against the goal with a review subagent and inject the findings as an advisory notice.",
  )
}
