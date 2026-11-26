///|
test "failure_message strips fail wrapper" {
  assert_eq(
    @error.failure_message(
      "Failure(path/to/file.mbt:1:2-1:3@pkg FAILED: arguments.path)",
    ),
    "arguments.path",
  )
  assert_eq(@error.failure_message("arguments.path"), "arguments.path")
}

///|
test "failure_message preserves message parentheses in current fail rendering" {
  let message = "arguments.file (present keys: line, text)"
  let rendered = fail(message) catch { error => "\{error}" }
  assert_eq(@error.failure_message(rendered), message)
}
