///|
test "program calls retain edit arguments and interruption state" {
  let calls = @transcript.program_calls(
    Some({
      "ptc_calls": [
        {
          "name": "edit",
          "arguments": { "path": "a.mbt" },
          "status": "done",
          "result": { "content": "ok", "is_error": false },
        },
        { "name": "multi_edit", "arguments": {}, "status": "interrupted" },
      ],
    }),
    "outer",
  )
  assert_eq(calls.length(), 2)
  assert_eq(calls[0].call_id, "outer/ptc/0")
  assert_true(calls[0].outcome is @transcript.Done(is_error=false, ..))
  assert_true(calls[1].outcome is @transcript.Done(is_error=true, ..))
  assert_true(@transcript.program_calls(None, "outer").is_empty())
}

///|
test "live program calls remain pending until their terminal result" {
  let calls = @transcript.program_calls(
    Some({
      "ptc_calls": [
        { "name": "web_search", "arguments": {}, "status": "running" },
      ],
    }),
    "job",
  )
  assert_true(calls is [{ outcome: @transcript.Pending(output=None), .. }])
}

///|
test "terminal jobs recover unfinished calls as interrupted" {
  let calls = @transcript.program_calls(
    Some({
      "ptc_calls": [{ "name": "edit", "arguments": {}, "status": "running" }],
    }),
    "job",
    origin=@transcript.Terminal,
  )
  assert_true(calls is [{ outcome: @transcript.Done(is_error=true, ..), .. }])
}

///|
test "immutable transcript snapshots do not claim calls are still live or interrupted" {
  let calls = @transcript.program_calls(
    Some({
      "ptc_job_id": "job-1",
      "ptc_calls": [{ "name": "edit", "arguments": {}, "status": "running" }],
    }),
    "outer",
    origin=@transcript.Recorded,
  )
  assert_true(
    calls is [{ outcome: @transcript.Snapshot(content~), .. }] &&
    content.contains("job-1"),
  )
}
