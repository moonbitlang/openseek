///|
test "decode valid write input" {
  debug_inspect(
    @decode.decode({ "path": "/tmp/file.txt", "content": "hello" }),
    content=(
      #|{
      #|  path: "/tmp/file.txt",
      #|  content: "hello",
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
      #|{ path: "/tmp/file.txt", content: "", revert_on_parse_errors: true }
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
      #|{ path: "/tmp/a.mbt", content: "x", revert_on_parse_errors: true }
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
