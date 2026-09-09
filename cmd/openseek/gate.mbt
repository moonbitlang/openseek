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
fn build_goal_met_gate(
  self_exe~ : String,
  model~ : @deepseek.Model,
  api_url~ : String?,
  workspace_root~ : String,
  review_deadline_ms? : Int = GateDeadlineMs,
  child_session? : @agent_subrun.ChildSession,
) -> async (String, @agent_session.GoalBaseline?) -> String? {
  (goal, baseline) => {
    let args = subrun_args(
      "review",
      model~,
      max_steps=@agent_review.default_audit_max_steps,
      api_url~,
    )
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
/// The `--review-gate` flag, shared by `run` and `serve`.
fn review_gate_flag() -> @argparse.FlagArg {
  FlagArg(
    "review-gate",
    long="review-gate",
    about="On goal(met), audit the worktree against the goal with a review subagent and inject the findings as an advisory notice.",
  )
}

///|
/// The `--review-deadline` option (milliseconds), shared by `run` and `serve`
/// like `--review-gate`: the wall clock one automatic goal-met audit
/// may take before it is treated as
/// stuck. Absent, the audit falls back to `GateDeadlineMs`.
fn review_deadline_option() -> @argparse.OptionArg {
  OptionArg(
    "review-deadline",
    long="review-deadline",
    about="Wall-clock deadline in milliseconds for one --review-gate audit; default 900000 (15 minutes).",
  )
}

///|
/// `None` — no flag — means the `GateDeadlineMs` default.
fn review_deadline_ms(matches : @argparse.Matches) -> Int? raise {
  match matches {
    { values: { "review-deadline": [input, ..], .. }, .. } =>
      Some(@cli.parse_positive_int(input, "--review-deadline"))
    _ => None
  }
}
