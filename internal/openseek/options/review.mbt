///|
/// Whether `--review-gate` was passed: the advisory goal-met audit is
/// opt-in while its precision is being calibrated on dogfood runs.
pub fn review_gate_enabled(matches : @argparse.Matches) -> Bool {
  matches is { flags: { "review-gate": true, .. }, .. }
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
pub fn review_deadline_ms(matches : @argparse.Matches) -> Int? raise {
  match matches {
    { values: { "review-deadline": [input, ..], .. }, .. } =>
      Some(@cli.parse_positive_int(input, "--review-deadline"))
    _ => None
  }
}
