///|
fn EvalResult::as_report(self : EvalResult) -> @report.Report {
  Report(
    title="Session Eval Result: " + empty_dash(self.session_id),
    summary=[
      Metric(name="session", value=empty_dash(self.session_id)),
      Metric(name="result", value=if self.success { "pass" } else { "fail" }),
      Metric(name="reason", value=self.reason),
      Metric(name="terminal", value=empty_dash(self.terminal_status)),
    ],
    metric_columns=[
      "Steps", "Tool Results", "Tool Errors", "Runtime Notices", "Finished",
    ],
    rows=[
      ReportRow(
        index=1,
        name=empty_dash(self.session_id),
        success=self.success,
        reason=self.reason,
        metrics=[
          Metric(name="Steps", value=self.steps.to_string()),
          Metric(name="Tool Results", value=self.tool_results.to_string()),
          Metric(name="Tool Errors", value=self.tool_errors.to_string()),
          Metric(name="Runtime Notices", value=self.runtime_notices.to_string()),
          Metric(name="Finished", value=self.finished.to_string()),
        ],
        details=[
          Metric(name="Finish Message", value=self.finish_message),
          Metric(name="Terminal Message", value=self.terminal_message),
        ],
      ),
    ],
  )
}

///|
fn empty_dash(value : String) -> String {
  if value == "" {
    "-"
  } else {
    value
  }
}
