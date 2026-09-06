///|
/// The distinguished final line a child writes after its turn: the typed
/// report. Parent and child are the same binary, so the derived
/// `to_json`/`from_json` pair on the report type cannot drift — this line is
/// a typed channel despite the process boundary.
pub fn report_line(report : Json) -> String {
  ({ "subrun_report": report } : Json).stringify()
}

///|
/// The report a parent extracts from one child stdout line, or `None` for
/// every other line (protocol events, stray output).
fn parse_report_line(line : Json) -> Json? {
  match line {
    { "subrun_report": report, .. } => Some(report)
    _ => None
  }
}

///|
test "report lines round-trip and ordinary lines are not reports" {
  let report : Json = { "answer": "x" }
  let line = @json.parse(report_line(report))
  assert_eq(parse_report_line(line), Some(report))
  assert_eq(parse_report_line({ "event": "agent_step", "step": 1 }), None)
}
