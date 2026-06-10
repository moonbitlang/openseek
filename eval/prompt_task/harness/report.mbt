///|
async fn write_report_files(report : EvalReport) -> Unit {
  @report.write_files(report.out_dir, report.markdown(), report.to_json())
}

///|
fn EvalReport::to_json(self : EvalReport) -> Json {
  {
    "model": self.model,
    "prompt_label": self.prompt_label,
    "task_file": self.task_file,
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
    "prompt_label": self.prompt_label,
    "success": self.success,
    "reason": self.reason,
    "workspace": self.workspace,
    "log_path": self.log_path,
    "exit_code": self.exit_code,
    "steps": self.steps,
    "tool_errors": self.tool_errors,
    "finished": self.finished,
    "validation": self.validation.to_json(),
    "moon_check_uses": self.moon_check_uses,
    "moon_test_uses": self.moon_test_uses,
    "moon_run_e_mentions": self.moon_run_e_mentions,
    "moon_run_c_mentions": self.moon_run_c_mentions,
    "bad_run_e_mentions": self.bad_run_e_mentions,
    "from_str_mentions": self.from_str_mentions,
    "parse_int_mentions": self.parse_int_mentions,
    "argparse_mentions": self.argparse_mentions,
    "old_argparse_mentions": self.old_argparse_mentions,
    "c_ffi_mentions": self.c_ffi_mentions,
    "env_args_mentions": self.env_args_mentions,
    "result_style_mentions": self.result_style_mentions,
    "try_mentions": self.try_mentions,
    "warnings": self.warnings,
  }
}

///|
fn ValidationResult::to_json(self : ValidationResult) -> Json {
  {
    "passed": self.passed,
    "reason": self.reason,
    "moon_check": self.moon_check,
    "moon_test": self.moon_test,
    "file_probe": self.file_probe,
    "stdin_probe": self.stdin_probe,
    "duplicate_probe": self.duplicate_probe,
  }
}

///|
/// Whether the run met its success threshold. Thresholded rather than
/// all-or-nothing because agent trials are stochastic: a prompt is judged on
/// its success rate, not on a single unlucky trial.
pub fn EvalReport::passed(self : EvalReport) -> Bool {
  self.successes >= self.min_successes
}

///|
/// The one-line failure summary a runner prints (and exits non-zero with)
/// when the threshold was missed, stating tally and threshold.
pub fn EvalReport::failure_message(self : EvalReport) -> String {
  "prompt task eval failed: \{self.successes}/\{self.runs} below threshold \{self.min_successes}/\{self.runs}"
}

///|
/// Render this run as the standard markdown report document.
pub fn EvalReport::markdown(self : EvalReport) -> String {
  self.as_report().markdown()
}

///|
fn EvalReport::as_report(self : EvalReport) -> @report.Report {
  Report(
    title="Prompt Task Eval",
    summary=[
      Metric(name="model", value=self.model),
      Metric(name="prompt", value=self.prompt_label),
      Metric(name="task", value=self.task_file),
      Metric(name="result", value="\{self.successes}/\{self.runs} successes"),
      Metric(name="concurrency", value=self.concurrency.to_string()),
      Metric(name="threshold", value="\{self.min_successes}/\{self.runs}"),
      Metric(name="passed", value=self.passed().to_string()),
      Metric(name="output", value=self.out_dir),
    ],
    metric_columns=[
      "Steps", "Tool Errors", "Finished", "Validation", "Check", "Test", "File Probe",
      "Stdin Probe", "Dup Probe", "Run -e", "Run -c", "Bad -e", "from_str", "parse_int",
      "argparse", "old argparse", "C FFI", "env args", "containers", "try", "Exit Code",
    ],
    rows=[
      for result in self.results => {
        ReportRow(
          index=result.index,
          name="trial-\{padded_index(result.index)}",
          success=result.success,
          reason=result.reason,
          warnings=result.warnings,
          metrics=[
            Metric(name="Steps", value=result.steps.to_string()),
            Metric(name="Tool Errors", value=result.tool_errors.to_string()),
            Metric(name="Finished", value=result.finished.to_string()),
            Metric(
              name="Validation",
              value=result.validation.passed.to_string(),
            ),
            Metric(name="Check", value=result.validation.moon_check.to_string()),
            Metric(name="Test", value=result.validation.moon_test.to_string()),
            Metric(
              name="File Probe",
              value=result.validation.file_probe.to_string(),
            ),
            Metric(
              name="Stdin Probe",
              value=result.validation.stdin_probe.to_string(),
            ),
            Metric(
              name="Dup Probe",
              value=result.validation.duplicate_probe.to_string(),
            ),
            Metric(name="Run -e", value=result.moon_run_e_mentions.to_string()),
            Metric(name="Run -c", value=result.moon_run_c_mentions.to_string()),
            Metric(name="Bad -e", value=result.bad_run_e_mentions.to_string()),
            Metric(name="from_str", value=result.from_str_mentions.to_string()),
            Metric(
              name="parse_int",
              value=result.parse_int_mentions.to_string(),
            ),
            Metric(name="argparse", value=result.argparse_mentions.to_string()),
            Metric(
              name="old argparse",
              value=result.old_argparse_mentions.to_string(),
            ),
            Metric(name="C FFI", value=result.c_ffi_mentions.to_string()),
            Metric(name="env args", value=result.env_args_mentions.to_string()),
            Metric(
              name="containers",
              value=result.result_style_mentions.to_string(),
            ),
            Metric(name="try", value=result.try_mentions.to_string()),
            Metric(name="Exit Code", value=result.exit_code.to_string()),
          ],
          log_path=result.log_path,
        )
      }
    ],
  )
}
