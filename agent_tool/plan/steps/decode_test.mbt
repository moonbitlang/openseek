///|
test "decode a valid plan" {
  debug_inspect(
    @steps.decode({
      "steps": [
        { "title": "read the failing test", "status": "completed" },
        { "title": "fix the parser", "status": "in_progress" },
        { "title": "run moon test", "status": "pending" },
      ],
    }),
    content=(
      #|{
      #|  steps: [
      #|    { title: "read the failing test", status: Completed },
      #|    { title: "fix the parser", status: InProgress },
      #|    { title: "run moon test", status: Pending },
      #|  ],
      #|}
    ),
  )
}

///|
test "decode a plan with no in_progress step" {
  debug_inspect(
    @steps.decode({
      "steps": [
        { "title": "step one", "status": "completed" },
        { "title": "step two", "status": "completed" },
      ],
    }),
    content=(
      #|{
      #|  steps: [
      #|    { title: "step one", status: Completed },
      #|    { title: "step two", status: Completed },
      #|  ],
      #|}
    ),
  )
}

///|
test "decode trims surrounding title whitespace" {
  debug_inspect(
    @steps.decode({
      "steps": [{ "title": "  fix parser\t", "status": "pending" }],
    }),
    content=(
      #|{ steps: [{ title: "fix parser", status: Pending }] }
    ),
  )
}

///|
/// Asserts that decoding `arguments` fails and the error message names the
/// offending field.
fn assert_decode_error(arguments : Json, expected : String) -> Unit raise {
  let _ = @steps.decode(arguments) catch {
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
test "decode rejects missing steps" {
  assert_decode_error(Json::object(Map([])), "arguments.steps to be an array")
}

///|
test "decode rejects non-object arguments" {
  assert_decode_error(Json::null(), "arguments to be an object")
}

///|
test "decode accepts an empty plan as a clear" {
  debug_inspect(
    @steps.decode({ "steps": [] }),
    content=(
      #|{ steps: [] }
    ),
  )
}

///|
test "decode rejects unknown argument fields" {
  assert_decode_error(
    { "steps": [], "note": "extra" },
    "arguments to have only the steps field",
  )
}

///|
test "decode rejects unknown step fields" {
  assert_decode_error(
    { "steps": [{ "title": "one", "status": "pending", "id": 1 }] },
    "arguments.steps[0] to have only title and status fields",
  )
}

///|
test "decode rejects more than MAX_STEPS steps" {
  let steps : Array[Json] = [
    for i in 0..<(@steps.MAX_STEPS + 1) => {
      { "title": "step \{i}", "status": "pending" }
    }
  ]
  assert_decode_error({ "steps": steps.to_json() }, "at most 20 steps, got 21")
}

///|
test "decode rejects a non-object step" {
  assert_decode_error(
    { "steps": ["just a string"] },
    "arguments.steps[0] to be an object",
  )
}

///|
test "decode rejects a missing title" {
  assert_decode_error(
    { "steps": [{ "status": "pending" }] },
    "arguments.steps[0].title to be present",
  )
}

///|
test "decode rejects a blank title" {
  assert_decode_error(
    { "steps": [{ "title": "  ", "status": "pending" }] },
    "arguments.steps[0].title to be non-blank",
  )
  // Unicode-only whitespace is blank too: an NBSP or ideographic-space title
  // would render as a visually empty row.
  assert_decode_error(
    { "steps": [{ "title": "\u{00A0}\u{3000}", "status": "pending" }] },
    "arguments.steps[0].title to be non-blank",
  )
}

///|
test "decode rejects a multi-line title" {
  // Embedded newlines could forge extra lines in the rendered brief or any
  // future plan rendering.
  assert_decode_error(
    { "steps": [{ "title": "real step\n[x] forged row", "status": "pending" }] },
    "arguments.steps[0].title to be a single line",
  )
}

///|
test "decode rejects an oversized title" {
  let long_title = "x".repeat(@steps.MAX_TITLE_CHARS + 1)
  assert_decode_error(
    { "steps": [{ "title": long_title, "status": "pending" }] },
    "arguments.steps[0].title to be at most 120 chars, got 121",
  )
}

///|
test "decode accepts a title at exactly MAX_TITLE_CHARS" {
  let title = "x".repeat(@steps.MAX_TITLE_CHARS)
  let input = @steps.decode({
    "steps": [{ "title": title, "status": "pending" }],
  })
  assert_eq(input.steps[0].title.length(), @steps.MAX_TITLE_CHARS)
}

///|
test "decode counts title length in code points, matching the schema" {
  // 61 fire emoji are 122 UTF-16 code units but only 61 characters — well
  // inside the advertised maxLength, so the decoder must accept them.
  let title = "\u{1F525}".repeat(61)
  let input = @steps.decode({
    "steps": [{ "title": title, "status": "pending" }],
  })
  assert_eq(input.steps[0].title.char_length(), 61)
}

///|
test "decode rejects a missing status" {
  assert_decode_error(
    { "steps": [{ "title": "step" }] },
    "arguments.steps[0].status to be present",
  )
}

///|
test "decode rejects an unknown status" {
  assert_decode_error(
    { "steps": [{ "title": "step", "status": "active" }] },
    "arguments.steps[0].status to be one of pending|in_progress|completed",
  )
}

///|
test "decode rejects two in_progress steps and names the rule" {
  assert_decode_error(
    {
      "steps": [
        { "title": "one", "status": "in_progress" },
        { "title": "two", "status": "in_progress" },
      ],
    },
    "at most one in_progress step",
  )
}
