///|
/// The distinguished final line a child writes after its turn: the typed
/// report. Parent and child are the same binary, so the derived
/// `to_json`/`from_json` pair on the report type cannot drift — this line is
/// a typed channel despite the process boundary.
pub fn report_line(report : Json) -> String {
  ({ "subrun_report": report } : Json).stringify()
}

///|
test "report lines round-trip" {
  let report : Json = { "answer": "x" }
  guard @json.parse(report_line(report)) is { "subrun_report": parsed, .. } else {
    fail("the report line must carry the report")
  }
  assert_eq(parsed, report)
}
