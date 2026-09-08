///|
test "decode defaults wait_ms and offset when only job_id is given" {
  debug_inspect(
    @decode.decode({ "job_id": "bg-3" }),
    content="{ job_id: \"bg-3\", wait_ms: None, offset: None }",
  )
}

///|
test "decode reads explicit wait_ms and offset selectors" {
  debug_inspect(
    @decode.decode({ "job_id": "bg-3", "wait_ms": 30000, "offset": 12000 }),
    content="{ job_id: \"bg-3\", wait_ms: Some(30000), offset: Some(12000) }",
  )
}

///|
test "decode treats explicitly-null selectors as absent" {
  debug_inspect(
    @decode.decode({
      "job_id": "bg-3",
      "wait_ms": Json::null(),
      "offset": Json::null(),
    }),
    content="{ job_id: \"bg-3\", wait_ms: None, offset: None }",
  )
}

///|
test "decode caps an oversized wait_ms at max_wait_ms instead of rejecting it" {
  inspect(@decode.max_wait_ms, content="120000")
  debug_inspect(
    @decode.decode({ "job_id": "bg-3", "wait_ms": 999999 }),
    content="{ job_id: \"bg-3\", wait_ms: Some(120000), offset: None }",
  )
}

///|
test "decode names the argument to repair in malformed arguments" {
  debug_inspect(
    [
      decode_error({ "wait_ms": 500 }),
      decode_error({ "job_id": 7 }),
      decode_error({ "job_id": "bg-3", "wait_ms": -5 }),
      decode_error({ "job_id": "bg-3", "wait_ms": "30000" }),
      decode_error({ "job_id": "bg-3", "offset": -1 }),
      decode_error({ "job_id": "bg-3", "offset": "0" }),
    ],
    content=(
      #|[
      #|  "job_output requires a string job_id",
      #|  "job_output requires a string job_id",
      #|  "job_output wait_ms must be a positive number",
      #|  "job_output wait_ms must be a number",
      #|  "job_output offset must be zero or a positive number",
      #|  "job_output offset must be a number",
      #|]
    ),
  )
}

///|
/// The decoder's failure message with the source-location wrapper stripped, or
/// "unexpected success" when decoding somehow succeeds.
fn decode_error(arguments : Json) -> String {
  try @decode.decode(arguments) catch {
    error => @tool_error.failure_message("\{error}")
  } noraise {
    _ => "unexpected success"
  }
}
