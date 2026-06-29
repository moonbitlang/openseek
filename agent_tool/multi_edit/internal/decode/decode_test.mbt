///|
test "decode_source returns inline edits" {
  let source = @decode.decode_source({
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
  guard source is Inline(edits) else { fail("expected an inline source") }
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
test "decode_source treats a string edits as a response-file path" {
  let source = @decode.decode_source({ "edits": "fixes.json" })
  guard source is FromFile(path) else { fail("expected a file source") }
  assert_eq(path, "fixes.json")
}

///|
test "decode_source requires edits to be an array or a path string" {
  try @decode.decode_source({}) catch {
    error => assert_true("\{error}".contains("arguments.edits"))
  } noraise {
    _ => fail("missing edits decoded")
  }
  try @decode.decode_source({ "edits": 5 }) catch {
    error =>
      assert_true(
        "\{error}".contains(
          "arguments.edits to be an array of edits or a file path string",
        ),
      )
  } noraise {
    _ => fail("numeric edits decoded")
  }
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
    _ => fail("non-array edits_file decoded")
  }
}

///|
test "decode rejects malformed edit entries with indexes" {
  try
    @decode.decode_source({
      "edits": [
        {
          "file": "file.mbt",
          "old_string": "old",
          "new_string": "new",
          "start_line": 0,
          "end_line": 1,
        },
      ],
    })
  catch {
    error =>
      assert_true(
        "\{error}".contains(
          "arguments.edits[0].start_line to be a positive integer",
        ),
      )
  } noraise {
    _ => fail("invalid start_line decoded")
  }
  try
    @decode.decode_source({
      "edits": [
        {
          "file": "file.mbt",
          "old_string": "old",
          "new_string": "new",
          "start_line": 3,
          "end_line": 2,
        },
      ],
    })
  catch {
    error =>
      assert_true(
        "\{error}".contains(
          "arguments.edits[0].end_line to be greater than or equal to arguments.edits[0].start_line",
        ),
      )
  } noraise {
    _ => fail("inverted range decoded")
  }
}

///|
test "decode rejects missing required fields" {
  try @decode.decode_source({ "edits": [] }) catch {
    error => assert_true("\{error}".contains("a non-empty array of edits"))
  } noraise {
    _ => fail("empty edits decoded")
  }
  try
    @decode.decode_source({
      "edits": [{ "old_string": "old", "new_string": "new", "start_line": 1 }],
    })
  catch {
    error =>
      assert_true("\{error}".contains("arguments.edits[0] to include file"))
  } noraise {
    _ => fail("missing file decoded")
  }
  try
    @decode.decode_source({
      "edits": [{ "file": "file.mbt", "old_string": "old", "start_line": 1 }],
    })
  catch {
    error =>
      assert_true(
        "\{error}".contains("arguments.edits[0] to include new_string"),
      )
  } noraise {
    _ => fail("missing new_string decoded")
  }
  try
    @decode.decode_source({
      "edits": [
        { "file": "file.mbt", "old_string": "old", "new_string": "new" },
      ],
    })
  catch {
    error =>
      assert_true(
        "\{error}".contains("arguments.edits[0] to include start_line"),
      )
  } noraise {
    _ => fail("missing start_line decoded")
  }
}

///|
test "decode lists present keys when a required field is misnamed" {
  // The agent named the line field `line` instead of `start_line` (exactly the
  // failure seen in an eval). The error should say start_line is missing AND
  // list the keys that are present, so the misnamed key is obvious.
  try
    @decode.decode_source({
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
  try @decode.decode_source(Json::null()) catch {
    error => assert_true("\{error}".contains("object arguments"))
  } noraise {
    _ => fail("non-object decoded")
  }
}
