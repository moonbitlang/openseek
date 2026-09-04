///|
/// Handle `--review`: run a read-only review of `base...HEAD` and print a single
/// JSON `ReviewReport` to stdout. Exit code: 0 (clean or non-blocking findings),
/// 1 (the review failed to produce a report), 2 (blocker findings present).
async fn run_review_cli(
  matches : @argparse.Matches,
  workspace_root~ : String,
) -> Unit {
  // Reviews always run on the strongest model; flash is too shallow for the
  // judgement a code review needs, so --model is not consulted here.
  let model = @deepseek.Deepseek(V4Pro)
  guard model.api_key(matches.values) is Some(api_key) else {
    fail("an API key is required for \{model}: pass --api-key")
  }
  let max_steps = max_steps(matches)
  let (thinking, base, api_url) = match matches {
    {
      values: {
        "thinking": [thinking, ..],
        "base": [base, ..],
        "api-url": [api_url, ..],
        ..
      },
      ..
    } =>
      (
        @deepseek.ThinkingMode::parse(thinking),
        base,
        match api_url.trim() {
          "" => None
          url => Some("\{url}")
        },
      )
    _ => fail("missing parsed review defaults")
  }
  if base.is_blank() {
    @stdio.stderr.write("review failed: --base must be a non-empty git ref\n")
    @sys.exit(1)
    return
  }
  // The same lab every subrun kind gets: without it `run_review` wires
  // `mbtx` with no kernel profile at all, and the reviewer has nowhere
  // it may legitimately write.
  let scratch_dir = new_scratch_lab("openseek-review-lab-")
  // `defer` covers the paths that unwind — a normal finish and a cancelled
  // run. The `@sys.exit` arms below never unwind, so each removes the lab
  // itself before exiting.
  defer remove_scratch_lab(scratch_dir)
  let report = @agent_review.run_review(
    api_key,
    model,
    base,
    workspace_root~,
    scratch_dir~,
    // Omission means context-bounded here too — uniform with run/serve/TUI.
    // (run_review's own 120 default remains the contract for direct API
    // callers only; before the flip the root flag default 1000 always won.)
    max_steps=max_steps.unwrap_or(@agent.unbounded_max_steps),
    thinking~,
    api_url?,
  ) catch {
    error => {
      @stdio.stderr.write("review failed: \{error}\n")
      remove_scratch_lab(scratch_dir)
      // `@sys.exit` never returns at runtime but is typed `Unit`, so this arm
      // still needs a diverging expression to satisfy the report-branch type.
      @sys.exit(1)
      return
    }
  }
  @stdio.stdout.write(report.to_json_string() + "\n")
  if report.findings.any(f => f.severity == "blocker") {
    remove_scratch_lab(scratch_dir)
    @sys.exit(2)
  }
}
