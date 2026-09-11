// Deliberate exports with no in-repo production consumer (see
// shrink_package.md): test seams, round-trip/protocol surface, and
// future-proof API kept on purpose. Each entry documents its reason.

///|
/// Render this single-session result as standalone HTML.
pub fn EvalResult::html(self : EvalResult) -> String {
  self.as_report().html()
}

///|
/// Render this single-session result as Markdown.
pub fn EvalResult::markdown(self : EvalResult) -> String {
  self.as_report().markdown()
}

///|
/// Render this single-session result as JSON for tooling.
pub fn EvalResult::to_json(self : EvalResult) -> Json {
  {
    "session_id": self.session_id,
    "success": self.success,
    "reason": self.reason,
    "steps": self.steps,
    "tool_results": self.tool_results,
    "tool_errors": self.tool_errors,
    "runtime_notices": self.runtime_notices,
    "finished": self.finished,
    "finish_message": self.finish_message,
    "terminal_status": self.terminal_status,
    "terminal_message": self.terminal_message,
  }
}

///|
/// Write `report.md`, `report.html`, and `report.json` under `out_dir`.
pub async fn EvalResult::write_files(
  self : EvalResult,
  out_dir : String,
) -> Unit {
  @report.write_files(
    out_dir,
    self.markdown(),
    self.to_json(),
    html=self.html(),
  )
}
