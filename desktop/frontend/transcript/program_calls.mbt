///|
/// Where a retained trace is being read from, which decides what a call that
/// was still `running` when the trace was written means to the reader.
pub(all) enum TraceOrigin {
  /// A live job's metadata: the call may still be executing.
  Live
  /// A finished job: nothing is executing, so the call was interrupted.
  Terminal
  /// An immutable transcript row recorded at handoff: neither a spinner nor a
  /// claim of success, just an observation (rendered as a `Snapshot` outcome).
  Recorded
}

///|
/// Nested calls are display metadata, not synthetic assistant tool calls.
/// Reuse normal tool cards so editing arguments retain their diff views.
pub fn program_calls(
  data : Json?,
  parent : String,
  origin? : TraceOrigin = Live,
) -> Array[ToolCall] {
  guard data is Some({ "ptc_calls": Array(entries), .. }) else { return [] }
  // Only a recorded trace with a still-running entry needs the note; name
  // the owning job when the trace knows it.
  let snapshot_note = () => {
    match data {
      Some({ "ptc_job_id": String(id), .. }) =>
        "Running when this snapshot was recorded. See background job \{id} for its current status."
      _ =>
        "Running when this snapshot was recorded. See the background job for its current status."
    }
  }
  let calls : Array[ToolCall] = []
  for index, entry in entries[:entries.length().min(64)] {
    guard entry
      is {
        "name": String(name),
        "arguments": arguments,
        "status": String(status),
        ..
      } else {
      continue
    }
    let outcome = match entry {
      _ if status == "running" && origin is Recorded =>
        Snapshot(content=snapshot_note())
      _ if status == "running" && origin is Live => Pending(output=None)
      {
        "result": {
          "content": String(content),
          "is_error": True
          | False as flag,
          ..
        } as result,
        ..
      } if status == "done" => {
        let brief = match result {
          { "brief": String(value), .. } => Some(value)
          _ => None
        }
        Done(content=Content([Text(content)]), is_error=flag == true, brief~)
      }
      _ =>
        Done(
          content=Content([
            Text("Program call interrupted; changes may have occurred."),
          ]),
          is_error=true,
          brief=None,
        )
    }
    calls.push({
      call_id: "\{parent}/ptc/\{index}",
      name,
      arguments: Some(arguments.stringify()),
      outcome,
      children: [],
    })
  }
  calls
}

///|
test "program calls retain edit arguments and interruption state" {
  let calls = program_calls(
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
  assert_true(calls[0].outcome is Done(is_error=false, ..))
  assert_true(calls[1].outcome is Done(is_error=true, ..))
  assert_true(program_calls(None, "outer").is_empty())
}

///|
test "live program calls remain pending until their terminal result" {
  let calls = program_calls(
    Some({
      "ptc_calls": [
        { "name": "web_search", "arguments": {}, "status": "running" },
      ],
    }),
    "job",
  )
  assert_true(calls is [{ outcome: Pending(output=None), .. }])
}

///|
test "terminal jobs recover unfinished calls as interrupted" {
  let calls = program_calls(
    Some({
      "ptc_calls": [{ "name": "edit", "arguments": {}, "status": "running" }],
    }),
    "job",
    origin=Terminal,
  )
  assert_true(calls is [{ outcome: Done(is_error=true, ..), .. }])
}

///|
test "immutable transcript snapshots do not claim calls are still live or interrupted" {
  let calls = program_calls(
    Some({
      "ptc_job_id": "job-1",
      "ptc_calls": [{ "name": "edit", "arguments": {}, "status": "running" }],
    }),
    "outer",
    origin=Recorded,
  )
  assert_true(
    calls is [{ outcome: Snapshot(content~), .. }] && content.contains("job-1"),
  )
}
