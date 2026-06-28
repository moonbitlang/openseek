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
test "decode_source returns the edits_file path" {
  let source = @decode.decode_source({ "edits_file": "fixes.json" })
  guard source is FromFile(path) else { fail("expected a file source") }
  assert_eq(path, "fixes.json")
}

///|
test "decode_source requires exactly one source" {
  try
    @decode.decode_source({
      "edits": [
        { "file": "f.mbt", "old_string": "a", "new_string": "b", "start_line": 1 },
      ],
      "edits_file": "fixes.json",
    })
  catch {
    error =>
      assert_true(
        "\{error}".contains(
          "exactly one of arguments.edits or arguments.edits_file",
        ),
      )
  } noraise {
    _ => fail("both sources decoded")
  }
  try @decode.decode_source({}) catch {
    error =>
      assert_true(
        "\{error}".contains("arguments.edits or arguments.edits_file"),
      )
  } noraise {
    _ => fail("missing source decoded")
  }
  try @decode.decode_source({ "edits_file": 5 }) catch {
    error =>
      assert_true("\{error}".contains("arguments.edits_file to be a string"))
  } noraise {
    _ => fail("non-string edits_file decoded")
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
      assert_true("\{error}".contains("edits_file to contain a JSON array"))
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
    error => assert_true("\{error}".contains("arguments.edits[0].file"))
  } noraise {
    _ => fail("missing file decoded")
  }
  try
    @decode.decode_source({
      "edits": [{ "file": "file.mbt", "old_string": "old", "start_line": 1 }],
    })
  catch {
    error => assert_true("\{error}".contains("arguments.edits[0].new_string"))
  } noraise {
    _ => fail("missing new_string decoded")
  }
  try
    @decode.decode_source({
      "edits": [{ "file": "file.mbt", "old_string": "old", "new_string": "new" }],
    })
  catch {
    error => assert_true("\{error}".contains("arguments.edits[0].start_line"))
  } noraise {
    _ => fail("missing start_line decoded")
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
