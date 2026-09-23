///|
/// The distinguished final line a child writes after its turn: the typed
/// report. Parent and child are the same binary, so the derived
/// `to_json`/`from_json` pair on the report type cannot drift — this line is
/// a typed channel despite the process boundary.
pub fn report_line(report : Json) -> String {
  ({ "subrun_report": report } : Json).stringify()
}
