///|
test "encoding defaults to text and accepts only explicit supported strings" {
  assert_true(@decode.decode({ "path": "a", "content": "" }).encoding is Text)
  assert_true(
    @decode.decode({ "path": "a", "content": "", "encoding": "text" }).encoding
    is Text,
  )
  assert_true(
    @decode.decode({ "path": "a", "content": "", "encoding": "base64" }).encoding
    is Base64,
  )
  for encoding in [Json::null(), Json(1), Json("hex"), Json("BASE64")] {
    assert_decode_error(
      { "path": "a", "content": "", "encoding": encoding },
      "arguments.encoding",
    )
  }
}

///|
test "decode valid write input" {
  debug_inspect(
    @decode.decode({ "path": "/tmp/file.txt", "content": "hello" }),
    content=(
      #|{
      #|  path: "/tmp/file.txt",
      #|  content: "hello",
      #|  encoding: Text,
      #|  revert_on_parse_errors: true,
      #|}
    ),
  )
}

///|
test "decode accepts empty content" {
  debug_inspect(
    @decode.decode({ "path": "/tmp/file.txt", "content": "" }),
    content=(
      #|{
      #|  path: "/tmp/file.txt",
      #|  content: "",
      #|  encoding: Text,
      #|  revert_on_parse_errors: true,
      #|}
    ),
  )
}

///|
test "decode reads revert_on_parse_errors" {
  debug_inspect(
    @decode.decode({
      "path": "/tmp/fixture.mbt",
      "content": "broken(",
      "revert_on_parse_errors": false,
    }),
    content=(
      #|{
      #|  path: "/tmp/fixture.mbt",
      #|  content: "broken(",
      #|  encoding: Text,
      #|  revert_on_parse_errors: false,
      #|}
    ),
  )
  // Null is treated as absent, keeping the guard on.
  debug_inspect(
    @decode.decode({
      "path": "/tmp/a.mbt",
      "content": "x",
      "revert_on_parse_errors": Json::null(),
    }),
    content=(
      #|{
      #|  path: "/tmp/a.mbt",
      #|  content: "x",
      #|  encoding: Text,
      #|  revert_on_parse_errors: true,
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
  assert_decode_error(
    { "path": "/tmp/a.mbt", "content": "x", "revert_on_parse_errors": 1 },
    "arguments.revert_on_parse_errors to be a boolean",
  )
  assert_decode_error({ "path": "/tmp/file.txt" }, "arguments.content")
  assert_decode_error({ "content": "hello" }, "arguments.path")
  assert_decode_error(Json::null(), "object arguments")
}

///|
test "decode accepts filename as an alias and requires agreement" {
  let inputs : Array[Json] = [
    { "filename": "note.txt", "content": "hello" },
    { "path": "note.txt", "filename": "note.txt", "content": "hello" },
  ]
  for arguments in inputs {
    let input = @decode.decode(arguments)
    assert_eq(input.path, "note.txt")
    assert_eq(input.content, "hello")
    assert_true(input.revert_on_parse_errors)
  }
  assert_decode_error(
    { "path": "a.txt", "filename": "b.txt", "content": "hello" },
    "arguments.path and arguments.filename to match",
  )
  for value in [Json::null(), Json(42)] {
    assert_decode_error(
      { "filename": value, "content": "hello" },
      "arguments.filename",
    )
    assert_decode_error(
      { "path": "a.txt", "filename": value, "content": "hello" },
      "arguments.filename",
    )
    assert_decode_error(
      { "path": value, "filename": "a.txt", "content": "hello" },
      "arguments.path",
    )
  }
  assert_decode_error({ "filename": "note.txt" }, "arguments.content")
}
