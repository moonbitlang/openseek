///|
test "decode valid multi_edit input" {
  debug_inspect(
    @decode.decode({
      "path": "file.mbt",
      "edits": [
        {
          "old_string": "old one",
          "new_string": "new one",
          "start_line": 2,
          "end_line": 4,
        },
        { "old_string": "old two", "new_string": "new two", "start_line": 8 },
      ],
    }),
    content=(
      #|{
      #|  path: "file.mbt",
      #|  edits: [
      #|    {
      #|      old_string: "old one",
      #|      new_string: "new one",
      #|      start_line: 2,
      #|      end_line: Some(4),
      #|    },
      #|    {
      #|      old_string: "old two",
      #|      new_string: "new two",
      #|      start_line: 8,
      #|      end_line: None,
      #|    },
      #|  ],
      #|}
    ),
  )
}

///|
test "decode rejects malformed edit entries with indexes" {
  try
    @decode.decode({
      "path": "file.mbt",
      "edits": [
        {
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
    @decode.decode({
      "path": "file.mbt",
      "edits": [
        {
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
  try @decode.decode({ "path": "file.mbt", "edits": [] }) catch {
    error =>
      assert_true(
        "\{error}".contains("arguments.edits to be a non-empty array"),
      )
  } noraise {
    _ => fail("empty edits decoded")
  }
  try
    @decode.decode({
      "path": "file.mbt",
      "edits": [{ "old_string": "old", "start_line": 1 }],
    })
  catch {
    error => assert_true("\{error}".contains("arguments.edits[0].new_string"))
  } noraise {
    _ => fail("missing new_string decoded")
  }
  try
    @decode.decode({
      "path": "file.mbt",
      "edits": [{ "old_string": "old", "new_string": "new" }],
    })
  catch {
    error => assert_true("\{error}".contains("arguments.edits[0].start_line"))
  } noraise {
    _ => fail("missing start_line decoded")
  }
}

///|
test "decode rejects non-object arguments" {
  try @decode.decode(Json::null()) catch {
    error => assert_true("\{error}".contains("object arguments"))
  } noraise {
    _ => fail("non-object decoded")
  }
}
