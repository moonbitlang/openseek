///|
/// Nested calls are display metadata, not synthetic assistant tool calls.
/// Reuse normal tool cards so editing arguments retain their diff views.
pub fn program_calls(
  data : Json?,
  parent : String,
  terminal? : Bool = false,
  snapshot? : Bool = false,
) -> Array[ToolCall] {
  guard data is Some({ "ptc_calls": Array(entries), .. }) else { return [] }
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
      _ if status == "running" && snapshot =>
        Snapshot(
          content=match data {
            Some({ "ptc_job_id": String(id), .. }) =>
              "Running when this snapshot was recorded. See background job \{id} for its current status."
            _ =>
              "Running when this snapshot was recorded. See the background job for its current status."
          },
        )
      _ if status == "running" && !terminal => Pending(output=None)
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
        Done(content~, is_error=flag == true, brief~)
      }
      _ =>
        Done(
          content="Program call interrupted; changes may have occurred.",
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
    terminal=true,
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
    snapshot=true,
  )
  assert_true(
    calls is [{ outcome: Snapshot(content~), .. }] && content.contains("job-1"),
  )
}
