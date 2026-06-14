///|
async fn write_report_files(report : EvalReport) -> Unit {
  @report.write_files(
    report.out_dir,
    report.markdown(),
    report.to_json(),
    html=report.html(),
  )
  for result in report.results {
    write_eval_result_files(report.out_dir, result)
  }
}

///|
async fn write_eval_result_files(out_dir : String, result : EvalResult) -> Unit {
  @report.write_files(
    out_dir + "/eval_results/" + eval_result_artifact_name(result),
    result.markdown(),
    result.to_json(),
    html=result.html(),
  )
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
fn EvalResult::to_json(self : EvalResult) -> Json {
  {
    "index": self.index,
    "prompt_label": self.prompt_label,
    "success": self.success,
    "reason": self.reason,
    "workspace": self.workspace,
    "log_path": self.log_path,
    "session_id": self.session_id,
    "events_path": self.events_path,
    "exit_code": self.exit_code,
    "steps": self.steps,
    "tool_results": self.tool_results,
    "tool_errors": self.tool_errors,
    "shell_uses": self.shell_uses,
    "shell_failures": self.shell_failures,
    "runtime_notices": self.runtime_notices,
    "finished": self.finished,
    "finish_message": self.finish_message,
    "terminal_status": self.terminal_status,
    "terminal_message": self.terminal_message,
    "validation": self.validation.to_json(),
    "parse_errors": self.parse_errors,
    "partial_tail": self.partial_tail,
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
    "ran": self.ran,
    "passed": self.passed,
    "reason": self.reason,
    "moon_check": self.moon_check,
    "moon_test": self.moon_test,
    "file_probe": self.file_probe,
    "stdin_probe": self.stdin_probe,
    "duplicate_probe": self.duplicate_probe,
    "probes": ([ for probe in self.probes => probe.to_json() ] : Json),
  }
}

///|
fn ProbeResult::to_json(self : ProbeResult) -> Json {
  { "name": self.name, "passed": self.passed, "reason": self.reason }
}

///|
/// Whether the analysis met its configured success threshold.
pub fn EvalReport::passed(self : EvalReport) -> Bool {
  self.successes >= self.min_successes
}

///|
/// One-line failure summary for CLIs that exit non-zero on a missed threshold.
pub fn EvalReport::failure_message(self : EvalReport) -> String {
  "prompt task eval failed: \{self.successes}/\{self.runs} below threshold \{self.min_successes}/\{self.runs}"
}

///|
/// Render this prompt-task analysis report as Markdown.
pub fn EvalReport::markdown(self : EvalReport) -> String {
  self.as_report().markdown()
}

///|
/// Render this prompt-task analysis report as standalone HTML.
pub fn EvalReport::html(self : EvalReport) -> String {
  self.as_report().html()
}

///|
/// Render this single-session eval result as Markdown.
pub fn EvalResult::markdown(self : EvalResult) -> String {
  self.as_report(out_dir="").markdown()
}

///|
/// Render this single-session eval result as standalone HTML.
pub fn EvalResult::html(self : EvalResult) -> String {
  self.as_report(out_dir="").html()
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
      "Steps", "Tool Results", "Tool Errors", "Shell Failures", "Finished", "Validation",
      "Exit Code",
    ],
    rows=[
      for result in self.results => {
        eval_result_row(result, out_dir=self.out_dir, include_eval_link=true)
      }
    ],
  )
}

///|
fn EvalResult::as_report(
  self : EvalResult,
  out_dir~ : String,
) -> @report.Report {
  Report(
    title="Prompt Task Eval Result: " + eval_result_name(self),
    summary=[
      Metric(name="session", value=empty_dash(self.session_id)),
      Metric(name="prompt", value=empty_dash(self.prompt_label)),
      Metric(name="result", value=if self.success { "pass" } else { "fail" }),
      Metric(name="reason", value=self.reason),
      Metric(name="workspace", value=empty_dash(self.workspace)),
      Metric(name="events", value=empty_dash(self.events_path)),
    ],
    metric_columns=[
      "Steps", "Tool Results", "Tool Errors", "Shell Failures", "Finished", "Validation",
      "Exit Code",
    ],
    rows=[eval_result_row(self, out_dir~, include_eval_link=false)],
  )
}

///|
fn eval_result_row(
  result : EvalResult,
  out_dir~ : String,
  include_eval_link~ : Bool,
) -> @report.ReportRow {
  ReportRow(
    index=display_index(result),
    name=eval_result_name(result),
    success=result.success,
    reason=result.reason,
    warnings=result.warnings,
    metrics=[
      Metric(name="Steps", value=result.steps.to_string()),
      Metric(name="Tool Results", value=result.tool_results.to_string()),
      Metric(name="Tool Errors", value=result.tool_errors.to_string()),
      Metric(name="Shell Failures", value=result.shell_failures.to_string()),
      Metric(name="Finished", value=result.finished.to_string()),
      Metric(name="Validation", value=validation_status(result.validation)),
      Metric(name="Exit Code", value=result.exit_code.to_string()),
    ],
    details=eval_details(result, out_dir~, include_eval_link~),
    log_path=relative_artifact_path(out_dir, result.log_path),
  )
}

///|
fn eval_details(
  result : EvalResult,
  out_dir~ : String,
  include_eval_link~ : Bool,
) -> Array[@report.Metric] {
  let details : Array[@report.Metric] = [
    Metric(name="Session", value=result.session_id),
    Metric(
      name="Workspace",
      value=relative_artifact_path(out_dir, result.workspace),
    ),
    Metric(
      name="Events",
      value=relative_artifact_path(out_dir, result.events_path),
    ),
    Metric(name="Log", value=relative_artifact_path(out_dir, result.log_path)),
    Metric(name="Terminal Status", value=empty_dash(result.terminal_status)),
    Metric(
      name="Terminal Message",
      value=empty_dash(summarize(result.terminal_message)),
    ),
    Metric(name="Validation Reason", value=result.validation.reason),
    Metric(name="Validation Ran", value=result.validation.ran.to_string()),
    Metric(
      name="Validation Probes",
      value=validation_probe_summary(result.validation),
    ),
    Metric(name="Moon Check", value=result.validation.moon_check.to_string()),
    Metric(name="Moon Test", value=result.validation.moon_test.to_string()),
    Metric(name="File Probe", value=result.validation.file_probe.to_string()),
    Metric(name="Stdin Probe", value=result.validation.stdin_probe.to_string()),
    Metric(
      name="Duplicate Probe",
      value=result.validation.duplicate_probe.to_string(),
    ),
    Metric(name="Parse Errors", value=result.parse_errors.to_string()),
    Metric(name="Partial Tail", value=result.partial_tail.to_string()),
    Metric(name="Shell Uses", value=result.shell_uses.to_string()),
    Metric(name="Runtime Notices", value=result.runtime_notices.to_string()),
    Metric(name="moon check mentions", value=result.moon_check_uses.to_string()),
    Metric(name="moon test mentions", value=result.moon_test_uses.to_string()),
    Metric(
      name="moon run -e mentions",
      value=result.moon_run_e_mentions.to_string(),
    ),
    Metric(
      name="moon run -c mentions",
      value=result.moon_run_c_mentions.to_string(),
    ),
    Metric(name="bad -e mentions", value=result.bad_run_e_mentions.to_string()),
    Metric(
      name="@string.from_str mentions",
      value=result.from_str_mentions.to_string(),
    ),
    Metric(
      name="@string.parse_int mentions",
      value=result.parse_int_mentions.to_string(),
    ),
    Metric(name="argparse mentions", value=result.argparse_mentions.to_string()),
    Metric(
      name="old argparse mentions",
      value=result.old_argparse_mentions.to_string(),
    ),
    Metric(name="C FFI mentions", value=result.c_ffi_mentions.to_string()),
    Metric(
      name="@env.args mentions",
      value=result.env_args_mentions.to_string(),
    ),
    Metric(
      name="Result container mentions",
      value=result.result_style_mentions.to_string(),
    ),
    Metric(name="try mentions", value=result.try_mentions.to_string()),
  ]
  if include_eval_link {
    details.push(
      Metric(
        name="Eval Result Report",
        value="eval_results/" +
          eval_result_artifact_name(result) +
          "/report.html",
      ),
    )
  }
  details
}

///|
fn relative_artifact_path(out_dir : String, path : String) -> String {
  if out_dir == "" || path == "" {
    return path
  }
  let prefix = out_dir + "/"
  if path.has_prefix(prefix) {
    path.sub(start=prefix.length(), end=path.length()).to_owned()
  } else {
    path
  }
}

///|
fn eval_result_name(result : EvalResult) -> String {
  if result.index > 0 {
    "trial-\{padded_index(result.index)}"
  } else if result.session_id != "" {
    result.session_id
  } else {
    "session"
  }
}

///|
fn eval_result_artifact_name(result : EvalResult) -> String {
  eval_result_name(result)
  .replace_all(old="/", new="_")
  .replace_all(old="\\", new="_")
  .replace_all(old=":", new="_")
  .replace_all(old=" ", new="_")
}

///|
fn display_index(result : EvalResult) -> Int {
  if result.index > 0 {
    result.index
  } else {
    1
  }
}

///|
fn validation_status(validation : ValidationResult) -> String {
  if !validation.ran {
    "not run"
  } else {
    validation.passed.to_string()
  }
}

///|
fn validation_probe_summary(validation : ValidationResult) -> String {
  if validation.probes.length() == 0 {
    return "-"
  }
  let cells : Array[String] = []
  for probe in validation.probes {
    let status = if probe.passed { "pass" } else { "fail" }
    cells.push(probe.name + "=" + status)
  }
  cells.join(", ")
}

///|
fn empty_dash(value : String) -> String {
  if value == "" {
    "-"
  } else {
    value
  }
}
