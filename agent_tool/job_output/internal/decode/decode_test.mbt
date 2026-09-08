///|
test "decode defaults offset when only job_id is given" {
  let input = @decode.decode({ "job_id": "bg-3" })
  assert_eq(input.job_id, "bg-3")
  assert_eq(input.offset, None)
}

///|
test "decode reads an explicit offset and treats null as absent" {
  assert_eq(
    @decode.decode({ "job_id": "bg-3", "offset": 12000 }).offset,
    Some(12000),
  )
  assert_eq(
    @decode.decode({ "job_id": "bg-3", "offset": Json::null() }).offset,
    None,
  )
}

///|
test "decode rejects all forms of the removed wait_ms" {
  for
    value in [
      Json::number(30000),
      Json::number(0),
      Json::string("30000"),
      Json::null(),
    ] {
    assert_eq(
      decode_error({ "job_id": "bg-3", "wait_ms": value }),
      Some("job_output no longer accepts wait_ms; use job_wait with job_ids"),
    )
  }
}

///|
test "decode names the argument to repair in malformed arguments" {
  assert_eq(decode_error({}), Some("job_output requires a string job_id"))
  assert_eq(
    decode_error({ "job_id": 7 }),
    Some("job_output requires a string job_id"),
  )
  assert_eq(
    decode_error({ "job_id": "bg-3", "offset": -1 }),
    Some("job_output offset must be zero or a positive number"),
  )
  assert_eq(
    decode_error({ "job_id": "bg-3", "offset": "0" }),
    Some("job_output offset must be a number"),
  )
}

///|
fn decode_error(arguments : Json) -> String? {
  try @decode.decode(arguments) catch {
    error => Some(@tool_error.failure_message("\{error}"))
  } noraise {
    _ => None
  }
}
