///|
fn decode_usage(text : String) -> @deepseek.Usage raise {
  @json.from_json(@json.parse(text))
}

///|
test "usage decode rejects malformed fields" {
  try
    decode_usage(
      (
        #|{"prompt_tokens":"2","completion_tokens":3}
      ),
    )
  catch {
    e =>
      debug_inspect(
        e,
        content=(
          #|JsonDecodeError(
          #|  (
          #|    <JsonPath: "">,
          #|    "Usage::from_json: expected object with numeric fields",
          #|  ),
          #|)
        ),
      )
  } noraise {
    _ => fail("expected malformed usage to fail")
  }
}

///|
test "usage decode rejects non-object input" {
  try
    decode_usage(
      (
        #|null
      ),
    )
  catch {
    e =>
      debug_inspect(
        e,
        content=(
          #|JsonDecodeError(
          #|  (
          #|    <JsonPath: "">,
          #|    "Usage::from_json: expected object with numeric fields",
          #|  ),
          #|)
        ),
      )
  } noraise {
    _ => fail("expected non-object usage to fail")
  }
}
