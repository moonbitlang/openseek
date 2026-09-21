///|
test "decode valid edit input" {
  debug_inspect(
    @decode.decode({
      "path": "file.mbt",
      "old_string": "old",
      "new_string": "new",
      "start_line": 1,
    }),
    content=(
      #|{
      #|  path: "file.mbt",
      #|  old_string: "old",
      #|  new_string: "new",
      #|  replace_all: false,
      #|  replace_all_preview: false,
      #|  start_line: 1,
      #|  end_line: None,
      #|  revert_on_parse_errors: true,
      #|  revert_if_error_delta_greater_or_equal: None,
      #|  revert_if_warning_delta_greater_or_equal: None,
      #|}
    ),
  )
}

///|
test "decode replace_all flag" {
  debug_inspect(
    @decode.decode({
      "path": "file.mbt",
      "old_string": "old",
      "new_string": "new",
      "replace_all": true,
      "start_line": 1,
    }),
    content=(
      #|{
      #|  path: "file.mbt",
      #|  old_string: "old",
      #|  new_string: "new",
      #|  replace_all: true,
      #|  replace_all_preview: false,
      #|  start_line: 1,
      #|  end_line: None,
      #|  revert_on_parse_errors: true,
      #|  revert_if_error_delta_greater_or_equal: None,
      #|  revert_if_warning_delta_greater_or_equal: None,
      #|}
    ),
  )
}

///|
test "decode line range" {
  debug_inspect(
    @decode.decode({
      "path": "file.mbt",
      "old_string": "old",
      "new_string": "new",
      "start_line": 2,
      "end_line": 4,
    }),
    content=(
      #|{
      #|  path: "file.mbt",
      #|  old_string: "old",
      #|  new_string: "new",
      #|  replace_all: false,
      #|  replace_all_preview: false,
      #|  start_line: 2,
      #|  end_line: Some(4),
      #|  revert_on_parse_errors: true,
      #|  revert_if_error_delta_greater_or_equal: None,
      #|  revert_if_warning_delta_greater_or_equal: None,
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
  fail("expected decode error")
}

///|
test "decode rejects invalid replace_all" {
  assert_decode_error(
    {
      "path": "file.mbt",
      "old_string": "old",
      "new_string": "new",
      "replace_all": "yes",
      "start_line": 1,
    },
    "arguments.replace_all",
  )
}

///|
test "decode rejects invalid line range" {
  assert_decode_error(
    {
      "path": "file.mbt",
      "old_string": "old",
      "new_string": "new",
      "start_line": 0,
    },
    "arguments.start_line to be a positive integer",
  )
  assert_decode_error(
    {
      "path": "file.mbt",
      "old_string": "old",
      "new_string": "new",
      "start_line": 1,
      "end_line": "4",
    },
    "arguments.end_line to be an integer",
  )
  assert_decode_error(
    {
      "path": "file.mbt",
      "old_string": "old",
      "new_string": "new",
      "start_line": 1.9,
    },
    "arguments.start_line to be an integer",
  )
  assert_decode_error(
    {
      "path": "file.mbt",
      "old_string": "old",
      "new_string": "new",
      "start_line": 4,
      "end_line": 2,
    },
    "arguments.end_line to be greater than or equal to arguments.start_line",
  )
}

///|
test "decode rejects missing required fields" {
  assert_decode_error({ "path": "file.mbt" }, "arguments.old_string")
  assert_decode_error(
    { "path": "file.mbt", "old_string": "old" },
    "arguments.new_string",
  )
  assert_decode_error(
    { "path": "file.mbt", "old_string": "old", "new_string": "new" },
    "arguments.start_line",
  )
}

///|
test "decode rejects non-object arguments" {
  assert_decode_error(Json::null(), "object arguments")
}

///|
test "decode reads revert_on_parse_errors" {
  let off = @decode.decode({
    "path": "file.mbt",
    "old_string": "old",
    "new_string": "new",
    "start_line": 1,
    "revert_on_parse_errors": false,
  })
  assert_false(off.revert_on_parse_errors)
  let default_on = @decode.decode({
    "path": "file.mbt",
    "old_string": "old",
    "new_string": "new",
    "start_line": 1,
  })
  assert_true(default_on.revert_on_parse_errors)
  assert_decode_error(
    {
      "path": "file.mbt",
      "old_string": "old",
      "new_string": "new",
      "start_line": 1,
      "revert_on_parse_errors": "yes",
    },
    "arguments.revert_on_parse_errors",
  )
}
