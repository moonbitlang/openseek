///|
test "decode_args returns inline edits" {
  let args = @decode.decode_args({
    "edits": [
      {
        "file": "file.mbt",
        "old_string": "old one",
        "new_string": "new one",
        "start_line": 2,
        "end_line": 4,
      },
      {
        "file": "other.mbt",
        "old_string": "old two",
        "new_string": "new two",
        "start_line": 8,
      },
    ],
  })
  assert_true(args.edits_file is None)
  let edits = args.inline
  assert_eq(edits.length(), 2)
  assert_eq(edits[0].file, "file.mbt")
  assert_eq(edits[0].old_string, "old one")
  assert_eq(edits[0].new_string, "new one")
  assert_eq(edits[0].start_line, 2)
  assert_true(edits[0].end_line is Some(4))
  assert_eq(edits[1].file, "other.mbt")
  assert_eq(edits[1].start_line, 8)
  assert_true(edits[1].end_line is None)
}

///|
test "decode_args reads an edits_file path" {
  let args = @decode.decode_args({ "edits_file": "fixes.json" })
  assert_eq(args.inline.length(), 0)
  guard args.edits_file is Some(path) else {
    fail("expected an edits_file path")
  }
  assert_eq(path, "fixes.json")
}

///|
test "decode_args accepts inline edits and an edits_file together" {
  let args = @decode.decode_args({
    "edits": [
      { "file": "a.mbt", "old_string": "a", "new_string": "b", "start_line": 1 },
    ],
    "edits_file": "more.json",
  })
  assert_eq(args.inline.length(), 1)
  assert_true(args.edits_file is Some("more.json"))
}

///|
test "decode_args allows absent or empty edits (combined-empty is the tool's check)" {
  let nothing = @decode.decode_args(Json::empty_object())
  assert_eq(nothing.inline.length(), 0)
  assert_true(nothing.edits_file is None)
  let empty_array = @decode.decode_args({ "edits": [] })
  assert_eq(empty_array.inline.length(), 0)
}

///|
/// Asserts that decoding `arguments` fails and the error message names the
/// offending field.
fn assert_decode_args_error(arguments : Json, expected : String) -> Unit raise {
  let _ = @decode.decode_args(arguments) catch {
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
test "decode_args rejects wrong field types" {
  assert_decode_args_error(
    { "edits": 5 },
    "arguments.edits to be an array of edit objects",
  )
  assert_decode_args_error(
    { "edits_file": 5 },
    "arguments.edits_file to be a string path",
  )
}

///|
test "decode_args reads revert_if_error_delta_greater_or_equal and defaults to None" {
  let absent = @decode.decode_args({ "edits": [] })
  assert_true(absent.revert_if_error_delta_greater_or_equal is None)
  let present = @decode.decode_args({
    "edits": [],
    "revert_if_error_delta_greater_or_equal": 3,
  })
  assert_true(present.revert_if_error_delta_greater_or_equal is Some(3))
  // Zero requires a net decrease and must round-trip.
  let zero = @decode.decode_args({
    "edits": [],
    "revert_if_error_delta_greater_or_equal": 0,
  })
  assert_true(zero.revert_if_error_delta_greater_or_equal is Some(0))
}

///|
test "decode_args rejects a non-integer revert_if_error_delta_greater_or_equal" {
  assert_decode_args_error(
    { "revert_if_error_delta_greater_or_equal": -1 },
    "arguments.revert_if_error_delta_greater_or_equal to be a non-negative integer",
  )
  assert_decode_args_error(
    { "revert_if_error_delta_greater_or_equal": 1.5 },
    "arguments.revert_if_error_delta_greater_or_equal to be a non-negative integer",
  )
  assert_decode_args_error(
    { "revert_if_error_delta_greater_or_equal": "5" },
    "arguments.revert_if_error_delta_greater_or_equal to be a non-negative integer",
  )
}

///|
test "decode_args rejects legacy diagnostic guard names" {
  assert_decode_args_error(
    { "revert_when_errors_above": 10 },
    "replaced by revert_if_error_delta_greater_or_equal",
  )
  assert_decode_args_error(
    { "revert_when_warnings_above": 0 },
    "replaced by revert_if_warning_delta_greater_or_equal",
  )
}

///|
test "decode_edits_json parses a bare array of edits" {
  let edits = @decode.decode_edits_json([
    {
      "file": "lib/parser.mbt",
      "old_string": "old",
      "new_string": "new",
      "start_line": 3,
    },
  ])
  assert_eq(edits.length(), 1)
  assert_eq(edits[0].file, "lib/parser.mbt")
  assert_eq(edits[0].start_line, 3)
}

///|
test "decode_edits_json rejects a non-array document" {
  try @decode.decode_edits_json({ "edits": [] }) catch {
    error =>
      assert_true("\{error}".contains("edits file to contain a JSON array"))
  } noraise {
    _ => fail("non-array response file decoded")
  }
}

///|
test "decode rejects malformed edit entries with indexes" {
  assert_decode_args_error(
    {
      "edits": [
        {
          "file": "file.mbt",
          "old_string": "old",
          "new_string": "new",
          "start_line": 0,
          "end_line": 1,
        },
      ],
    },
    "arguments.edits[0].start_line to be a positive integer",
  )
  assert_decode_args_error(
    {
      "edits": [
        {
          "file": "file.mbt",
          "old_string": "old",
          "new_string": "new",
          "start_line": 3,
          "end_line": 2,
        },
      ],
    },
    "arguments.edits[0].end_line to be greater than or equal to arguments.edits[0].start_line",
  )
}

///|
test "decode rejects missing required fields" {
  assert_decode_args_error(
    { "edits": [{ "old_string": "old", "new_string": "new", "start_line": 1 }] },
    "arguments.edits[0] to include file",
  )
  assert_decode_args_error(
    { "edits": [{ "file": "file.mbt", "old_string": "old", "start_line": 1 }] },
    "arguments.edits[0] to include new_string",
  )
  assert_decode_args_error(
    {
      "edits": [
        { "file": "file.mbt", "old_string": "old", "new_string": "new" },
      ],
    },
    "arguments.edits[0] to include start_line",
  )
}

///|
test "decode lists present keys when a required field is misnamed" {
  // The agent named the line field `line` instead of `start_line` (exactly the
  // failure seen in an eval). The error should say start_line is missing AND
  // list the keys that are present, so the misnamed key is obvious.
  try
    @decode.decode_args({
      "edits": [
        {
          "file": "file.mbt",
          "old_string": "old",
          "new_string": "new",
          "line": 12,
        },
      ],
    })
  catch {
    error => {
      let text = "\{error}"
      assert_true(text.contains("arguments.edits[0] to include start_line"))
      assert_true(text.contains("present keys:"))
      assert_true(text.contains("line"))
      assert_false(text.contains("to be an integer"))
    }
  } noraise {
    _ => fail("misnamed start_line decoded")
  }
}

///|
test "decode rejects non-object arguments" {
  assert_decode_args_error(Json::null(), "object arguments")
}

///|
test "decode reads revert_on_parse_errors" {
  let off = @decode.decode_args({
    "edits": [
      { "file": "a.mbt", "old_string": "x", "new_string": "y", "start_line": 1 },
    ],
    "revert_on_parse_errors": false,
  })
  assert_false(off.revert_on_parse_errors)
  let default_on = @decode.decode_args({ "edits": [] })
  assert_true(default_on.revert_on_parse_errors)
  assert_decode_args_error(
    { "edits": [], "revert_on_parse_errors": 1 },
    "arguments.revert_on_parse_errors",
  )
}
