///|
test "pending job wait labels expose targets and clear on result" {
  let call : @transcript.ToolCall = {
    call_id: "wait",
    name: "job_wait",
    arguments: Some("{\"job_ids\":[\"bg-1\",\"bg-2\",\"bg-1\"]}"),
    outcome: Pending(output=None),
  }
  assert_eq(
    pending_job_wait_label(call),
    Some("Wait for any of these jobs to complete: bg-1, bg-2"),
  )
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

///|
test "waiting labels reuse recorded job descriptions and keep unknown IDs" {
  let start : @transcript.ToolCall = {
    call_id: "start",
    name: "mbtx",
    arguments: Some("{\"description\":\"Watch CI on rebased PR 27\"}"),
    outcome: Done(
      content="untrusted output",
      is_error=false,
      brief=Some("mbtx → bg bg-10"),
    ),
  }
  let wait : @transcript.ToolCall = {
    call_id: "wait",
    name: "job_wait",
    arguments: Some("{\"job_ids\":[\"bg-10\",\"bg-11\",\"bg-10\"]}"),
    outcome: Pending(output=None),
  }
  let item : @transcript.TranscriptItem = {
    kind: Assistant(
      reasoning=None,
      prose=None,
      calls=[start, wait],
      replay=false,
      finished=false,
    ),
    ts: None,
    sequence: None,
  }
  let descriptions : Map[String, String] = Map([])
  assert_eq(
    job_wait_labels(item, descriptions).get(1),
    Some(
      "Wait for any of these jobs to complete: \"Watch CI on rebased PR 27\", bg-11",
    ),
  )
  assert_eq(
    pending_job_wait_label(wait),
    Some("Wait for any of these jobs to complete: bg-10, bg-11"),
  )
  let output : @transcript.ToolCall = {
    call_id: "output",
    name: "job_output",
    arguments: Some("{\"job_id\":\"bg-11\"}"),
    outcome: Done(
      content="",
      is_error=false,
      brief=Some("job bg-11 (running): Run tests: native"),
    ),
  }
  collect_job_description(output, descriptions)
  assert_eq(
    pending_job_wait_label(wait, descriptions~),
    Some(
      "Wait for any of these jobs to complete: \"Watch CI on rebased PR 27\", \"Run tests: native\"",
    ),
  )
  // A matching-looking log is not metadata; malformed and failed calls do
  // not create a description either.
  let ignored : Map[String, String] = Map([])
  collect_job_description(
    {
      ..output,
      outcome: Done(
        content="job bg-11 (running): fake",
        is_error=false,
        brief=None,
      ),
    },
    ignored,
  )
  collect_job_description({ ..start, arguments: Some("{"), }, ignored)
  collect_job_description(
    { ..start, arguments: Some("{\"description\":\"  \"}"), },
    ignored,
  )
  collect_job_description(
    {
      ..output,
      outcome: Done(
        content="",
        is_error=true,
        brief=Some("job bg-11 (running): fake"),
      ),
    },
    ignored,
  )
  assert_true(ignored.is_empty())
}

///|
test "waiting labels distinguish duplicate call IDs by position" {
  let first : @transcript.ToolCall = {
    call_id: "duplicate",
    name: "job_wait",
    arguments: Some("{\"job_ids\":[\"bg-1\"]}"),
    outcome: Pending(output=None),
  }
  let item : @transcript.TranscriptItem = {
    kind: Assistant(
      reasoning=None,
      prose=None,
      calls=[first, { ..first, arguments: Some("{\"job_ids\":[\"bg-2\"]}"), }],
      replay=false,
      finished=false,
    ),
    ts: None,
    sequence: None,
  }
  let labels = job_wait_labels(item, {
    "bg-1": "First job",
    "bg-2": "Second job",
  })
  assert_eq(labels.get(0), Some("Wait for job \"First job\" to complete"))
  assert_eq(labels.get(1), Some("Wait for job \"Second job\" to complete"))
}
