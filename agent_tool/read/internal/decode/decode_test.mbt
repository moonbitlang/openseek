///|
test "decode valid read input" {
  debug_inspect(
    @decode.decode({
      "path": "file.mbt",
      "start_line": 3,
      "max_lines": 4,
      "max_output_chars": 999999,
    }),
    content=(
      #|{
      #|  path: "file.mbt",
      #|  start_line: 3,
      #|  max_lines: Some(4),
      #|  max_output_chars: 50000,
      #|}
    ),
  )
}

///|
test "decode defaults optional limits" {
  debug_inspect(
    @decode.decode({ "path": "file.mbt" }),
    content=(
      #|{
      #|  path: "file.mbt",
      #|  start_line: 1,
      #|  max_lines: None,
      #|  max_output_chars: 12000,
      #|}
    ),
  )
}

///|
/// Asserts that decoding `arguments` fails and the error message names the
/// offending field.
fn assert_decode_error(arguments : Json, expected : String) -> Unit raise {
  let _ = @decode.decode(arguments) catch {
    error => {
      let message = "\{error}"
      assert_true(
        message.contains(expected),
        msg="\{message} should contain \{expected}",
      )
      return
    }
  }
  fail("expected decode error naming \{expected}")
}

///|
test "decode rejects malformed arguments and names the offending field" {
  assert_decode_error(Json::empty_object(), "arguments.path")
  assert_decode_error(
    { "paths": ["a.mbt", "b.mbt"] },
    "arguments.paths is not supported",
  )
  assert_decode_error(
    { "path": "file.mbt", "max_lines": 0 },
    "arguments.max_lines to be a positive number",
  )
  assert_decode_error(Json::null(), "object arguments")
}
