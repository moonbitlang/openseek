///|
async fn write_report_files(report : EvalReport) -> Unit {
  @report.write_files(report.out_dir, report.markdown(), report.to_json())
}

///|
fn EvalReport::to_json(self : EvalReport) -> Json {
  {
    "model": self.model,
    "prompt_label": self.prompt_label,
    "runs": self.runs,
    "concurrency": self.concurrency,
    "min_successes": self.min_successes,
    "successes": self.successes,
    "passed": self.passed(),
    "out_dir": self.out_dir,
    "results": ([ for result in self.results => result.to_json() ] : Json),
  }
}

///|
fn TrialResult::to_json(self : TrialResult) -> Json {
  {
    "index": self.index,
    "case_id": self.case_id,
    "prompt_label": self.prompt_label,
    "success": self.success,
    "reason": self.reason,
    "workspace": self.workspace,
    "log_path": self.log_path,
    "exit_code": self.exit_code,
    "steps": self.steps,
    "tool_errors": self.tool_errors,
    "shell_uses": self.shell_uses,
    "moon_cmd_uses": self.moon_cmd_uses,
    "moon_run_e_mentions": self.moon_run_e_mentions,
    "moon_run_c_mentions": self.moon_run_c_mentions,
    "moon_check_uses": self.moon_check_uses,
    "moon_test_uses": self.moon_test_uses,
    "moon_info_uses": self.moon_info_uses,
    "moon_fmt_uses": self.moon_fmt_uses,
    "edit_successes": self.edit_successes,
    "write_successes": self.write_successes,
    "validation_passed": self.validation_passed,
    "marker_present": self.marker_present,
    "warnings": self.warnings,
  }
}

///|
/// Whether the run met its success threshold. Thresholded rather than
/// all-or-nothing because agent trials are stochastic: the tooling is judged
/// on its success rate, not on a single unlucky trial.
pub fn EvalReport::passed(self : EvalReport) -> Bool {
  self.successes >= self.min_successes
}

///|
/// The one-line failure summary a runner prints (and exits non-zero with)
/// when the threshold was missed, stating tally and threshold.
pub fn EvalReport::failure_message(self : EvalReport) -> String {
  "file edit eval failed: \{self.successes}/\{self.runs} below threshold \{self.min_successes}/\{self.runs}"
}

///|
/// Render this run as the standard markdown report document.
pub fn EvalReport::markdown(self : EvalReport) -> String {
  self.as_report().markdown()
}

///|
fn EvalReport::as_report(self : EvalReport) -> @report.Report {
  Report(
    title="File Edit Eval",
    summary=[
      Metric(name="model", value=self.model),
      Metric(name="prompt", value=self.prompt_label),
      Metric(name="result", value="\{self.successes}/\{self.runs} successes"),
      Metric(name="concurrency", value=self.concurrency.to_string()),
      Metric(name="threshold", value="\{self.min_successes}/\{self.runs}"),
      Metric(name="passed", value=self.passed().to_string()),
      Metric(name="output", value=self.out_dir),
    ],
    metric_columns=[
      "Steps", "Tool Errors", "Shell Uses", "Moon Cmd", "Run -e", "Run -c", "Check",
      "Test", "Info", "Fmt", "Edit Successes", "Write Successes", "Exit Code", "Validation",
      "Marker",
    ],
    rows=[
      for result in self.results => {
        ReportRow(
          index=result.index,
          name=result.case_id,
          success=result.success,
          reason=result.reason,
          warnings=result.warnings,
          metrics=[
            Metric(name="Steps", value=result.steps.to_string()),
            Metric(name="Tool Errors", value=result.tool_errors.to_string()),
            Metric(name="Shell Uses", value=result.shell_uses.to_string()),
            Metric(name="Moon Cmd", value=result.moon_cmd_uses.to_string()),
            Metric(name="Run -e", value=result.moon_run_e_mentions.to_string()),
            Metric(name="Run -c", value=result.moon_run_c_mentions.to_string()),
            Metric(name="Check", value=result.moon_check_uses.to_string()),
            Metric(name="Test", value=result.moon_test_uses.to_string()),
            Metric(name="Info", value=result.moon_info_uses.to_string()),
            Metric(name="Fmt", value=result.moon_fmt_uses.to_string()),
            Metric(
              name="Edit Successes",
              value=result.edit_successes.to_string(),
            ),
            Metric(
              name="Write Successes",
              value=result.write_successes.to_string(),
            ),
            Metric(name="Exit Code", value=result.exit_code.to_string()),
            Metric(
              name="Validation",
              value=result.validation_passed.to_string(),
            ),
            Metric(name="Marker", value=result.marker_present.to_string()),
          ],
          log_path=result.log_path,
        )
      }
    ],
  )
}
