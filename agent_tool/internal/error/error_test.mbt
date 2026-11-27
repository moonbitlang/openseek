///|
test "failure_message strips fail wrapper" {
  assert_eq(
    @error.failure_message(
      "Failure(path/to/file.mbt:1:2-1:3@pkg FAILED: arguments.path)",
    ),
    "arguments.path",
  )
  assert_eq(
    @error.failure_message(
      "path/to/file.mbt:1:2-1:3@pkg FAILED: arguments.edits[0] to include file (present keys: a, b)",
    ),
    "arguments.edits[0] to include file (present keys: a, b)",
  )
  assert_eq(@error.failure_message("arguments.path"), "arguments.path")
}
