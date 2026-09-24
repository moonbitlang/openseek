///|
test "report lines round-trip" {
  let report : Json = { "answer": "x" }
  guard @json.parse(@agent_subrun.report_line(report))
    is { "subrun_report": parsed, .. } else {
    fail("the report line must carry the report")
  }
  assert_eq(parsed, report)
}
