///|
test "pending job wait labels expose targets and clear on result" {
  let call : @transcript.ToolCall = {
    call_id: "wait",
    name: "job_wait",
    arguments: Some("{\"job_ids\":[\"bg-1\",\"bg-2\",\"bg-1\"]}"),
    outcome: Pending(output=None),
  }
  assert_eq(pending_job_wait_label(call), Some("Waiting for bg-1, bg-2"))
  assert_eq(
    pending_job_wait_label({
      ..call,
      outcome: Done(content="done", is_error=false, brief=None),
    }),
    None,
  )
  assert_eq(pending_job_wait_label({ ..call, arguments: Some("{}"), }), None)
  assert_eq(pending_job_wait_label({ ..call, name: "job_output", }), None)
}
