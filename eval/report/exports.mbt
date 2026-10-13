// Deliberate exports with no in-repo production consumer (see
// shrink_package.md): test seams, round-trip/protocol surface, and
// future-proof API kept on purpose. Each entry documents its reason.

///|
/// Whether every row passed — the run's exit-status verdict. Vacuously true
/// for a report with no rows.
pub fn Report::all_passed(self : Report) -> Bool {
  self.successes() == self.rows.length()
}

///|
/// How many rows passed.
pub fn Report::successes(self : Report) -> Int32 {
  self.rows.count_if(row => row.success)
}

///|
/// Write both renderings of this report under `out_dir` — the standard
/// artifact layout eval runners leave behind.
pub async fn Report::write_files(self : Report, out_dir : String) -> Unit {
  write_files(out_dir, self.markdown(), self.to_json(), html=self.html())
}
